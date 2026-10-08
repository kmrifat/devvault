import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/conflict/conflict_dialog.dart';
import 'package:devvault/features/conflict/conflict_resolution.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

const _other = '00000000-0000-4000-8000-0000000000ff';

/// [item] as another device changed it: a later rev from [_other].
Item theirsOf(Item item, Item Function(Item) change) {
  final changed = change(item);
  return Item.fromJson({
    ...changed.toJson(),
    'rev': Hlc.zero(_other)
        .tick(testNow.add(const Duration(hours: 1)))
        .toString(),
    'device_id': _other,
  });
}

Item withSecret(Item item, String key, String value) => item.copyWith(
  fields: {
    ...item.fields,
    key: ItemField(value: value, source: FieldSource.user, secret: true),
  },
);

void main() {
  setUpAll(loadTestCrypto);

  group('resolution', () {
    final mine = Item(
      id: '00000000-0000-4000-8000-000000000001',
      typeName: ItemType.androidKeystore.wireName,
      title: 'Upload keystore',
      createdAt: testNow,
      updatedAt: testNow,
      rev: Hlc.zero(testDeviceId).tick(testNow),
      deviceId: testDeviceId,
      fields: const {
        'alias': ItemField(value: 'upload', source: FieldSource.file),
        'store_password': ItemField(
          value: 'pw-mine',
          source: FieldSource.user,
          secret: true,
        ),
      },
    );
    final theirs = theirsOf(
      mine,
      (i) => withSecret(
        i.copyWith(title: 'Play keystore'),
        'store_password',
        'pw-theirs',
      ),
    );

    test('lists only what differs, secrets marked', () {
      final rows = conflictRows(mine, theirs, const {});
      expect(rows.map((r) => r.key), ['title', 'field:store_password']);
      expect(rows.last.secret, isTrue);
      expect(rows.last.label, 'Store password');
      expect(
        (rows.first.mine, rows.first.theirs),
        ('Upload keystore', 'Play keystore'),
      );
    });

    test('needs a choice for every difference', () {
      expect(
        () => resolveConflict(
          mine: mine,
          theirs: theirs,
          choices: {'title': ConflictSide.theirs},
        ),
        throwsArgumentError,
      );
    });

    test('applies each choice and drops the version from the conflict', () {
      final withBoth = withConflict(mine, Conflict()..addVersion(theirs));
      final resolved = resolveConflict(
        mine: withBoth,
        theirs: theirs,
        choices: {
          'title': ConflictSide.mine,
          'field:store_password': ConflictSide.theirs,
        },
      );
      expect(resolved.title, 'Upload keystore');
      expect(resolved.fields['store_password']!.value, 'pw-theirs');
      expect(resolved.conflict, isNull);
    });

    test('other versions and deletions stay until chosen too', () {
      final third = theirsOf(mine, (i) => i.copyWith(title: 'Third'));
      final conflict = Conflict()
        ..addVersion(theirs)
        ..addVersion(
          Item.fromJson({
            ...third.toJson(),
            'rev': Hlc.zero(_other)
                .tick(testNow.add(const Duration(hours: 2)))
                .toString(),
          }),
        )
        ..addDeletion(
          Tombstone(
            id: mine.id,
            kind: TombstoneKind.item,
            deletedAt: testNow,
            rev: Hlc.zero(_other).tick(testNow),
            deviceId: _other,
          ),
        );
      final item = withConflict(mine, conflict);
      final afterOne = dropVersion(item, theirs);
      expect(Conflict.of(afterOne).versions.single.title, 'Third');
      expect(Conflict.of(afterOne).deletions, hasLength(1));
      expect(Conflict.of(keepDespiteDeletion(afterOne)).deletions, isEmpty);
    });
  });

  group('dialog', () {
    VaultIndex index(WidgetTester tester) =>
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

    /// Opens the sample vault with "Maps API key" in conflict and selected.
    Future<Item> open(WidgetTester tester, {bool deletionOnly = false}) async {
      tester.view
        ..physicalSize = const Size(1440, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpUnlockedApp(
        tester,
        location: Routes.vault(),
        vault: TestVault.sample,
        layout: AppLayout.desktop,
      );
      final mine = index(tester).all
          .firstWhere((i) => i.title == 'Maps API key');
      final conflict = Conflict();
      if (deletionOnly) {
        conflict.addDeletion(
          Tombstone(
            id: mine.id,
            kind: TombstoneKind.item,
            deletedAt: testNow,
            rev: Hlc.zero(_other).tick(testNow),
            deviceId: _other,
          ),
        );
      } else {
        conflict.addVersion(
          theirsOf(
            mine,
            (i) => withSecret(
              i.copyWith(title: 'Maps key (prod)'),
              'value',
              'AIza-theirs',
            ),
          ),
        );
      }
      await tester.runAsync(
        () =>
            appContainer(tester)
                .read(vaultSessionProvider.notifier)
                .saveItem(withConflict(mine, conflict)),
      );
      GoRouter.of(tester.element(find.byType(VaultListPane)))
          .go(Routes.vault(item: mine.id));
      await tester.pumpAndSettle();
      return mine;
    }

    Future<void> tapAndWrite(
      WidgetTester tester,
      Finder finder,
      bool Function() done,
    ) async {
      await tester.tap(finder);
      for (var i = 0; i < 300 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(done(), isTrue);
      await tester.pumpAndSettle();
    }

    testWidgets('a conflict shows in the list, the sidebar and the item', (
      tester,
    ) async {
      final mine = await open(tester);
      Finder inSidebar(String text) => find.descendant(
        of: find.byType(VaultSidebar),
        matching: find.text(text),
      );
      Finder inList(Finder finder) =>
          find.descendant(of: find.byType(VaultListPane), matching: finder);
      Finder rowOf(String title) => find
          .ancestor(of: inList(find.text(title)), matching: find.byType(Row))
          .first;

      // The list row carries a Conflict chip; other rows don't.
      expect(
        find.descendant(
          of: rowOf('Maps API key'),
          matching: find.text('Conflict'),
        ),
        findsOneWidget,
      );
      expect(inList(find.text('Conflict')), findsOneWidget);
      // The sidebar row appears, with its count.
      expect(inSidebar('Conflicts'), findsOneWidget);
      expect(
        find.descendant(
          of: find
              .ancestor(of: inSidebar('Conflicts'), matching: find.byType(Row))
              .first,
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      // The item says what happened.
      expect(
        find.textContaining('Another device changed this item'),
        findsOneWidget,
      );

      // The sidebar row filters the list down to it.
      expect(inList(find.text('Upload keystore')), findsOneWidget);
      await tester.tap(inSidebar('Conflicts'));
      await tester.pumpAndSettle();
      expect(
        GoRouter.of(tester.element(find.byType(VaultListPane)))
            .state
            .uri
            .queryParameters['view'],
        'conflicts',
      );
      expect(inList(find.text('Maps API key')), findsOneWidget);
      expect(inList(find.text('Upload keystore')), findsNothing);

      // Resolved, the row and the chip go away.
      GoRouter.of(tester.element(find.byType(VaultListPane)))
          .go(Routes.vault(item: mine.id));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resolve…'));
      await tester.pumpAndSettle();
      await tapAndWrite(
        tester,
        find.text('Keep both'),
        () => index(tester).items[mine.id]!.conflict == null,
      );
      expect(inSidebar('Conflicts'), findsNothing);
      expect(inList(find.text('Conflict')), findsNothing);
    });

    testWidgets('resolving needs every choice, then applies it', (
      tester,
    ) async {
      final mine = await open(tester);
      expect(find.text('Resolve…'), findsOneWidget);
      await tester.tap(find.text('Resolve…'));
      await tester.pumpAndSettle();
      expect(find.byType(ConflictDialog), findsOneWidget);

      Finder resolveButton() => find.widgetWithText(BCButton, 'Resolve');
      expect(tester.widget<BCButton>(resolveButton()).isDisabled, isTrue);
      // Secrets are masked until shown.
      expect(find.text('AIza-theirs'), findsNothing);
      await tester.tap(find.text('Show secrets'));
      await tester.pumpAndSettle();
      expect(find.text('AIza-theirs'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Name from this device'));
      await tester.pump();
      expect(tester.widget<BCButton>(resolveButton()).isDisabled, isTrue);
      await tester.tap(find.bySemanticsLabel('Value from the other device'));
      await tester.pump();
      expect(tester.widget<BCButton>(resolveButton()).isDisabled, isFalse);

      await tapAndWrite(
        tester,
        resolveButton(),
        () => index(tester).items[mine.id]!.conflict == null,
      );
      final resolved = index(tester).items[mine.id]!;
      expect(resolved.title, 'Maps API key');
      expect(resolved.fields['value']!.value, 'AIza-theirs');
      expect(find.byType(ConflictDialog), findsNothing);
      expect(find.text('Resolve…'), findsNothing);
    });

    testWidgets('keep both makes the other version its own item', (
      tester,
    ) async {
      final mine = await open(tester);
      await tester.tap(find.text('Resolve…'));
      await tester.pumpAndSettle();
      await tapAndWrite(
        tester,
        find.text('Keep both'),
        () => index(tester).items[mine.id]!.conflict == null,
      );
      final copy = index(tester).all
          .firstWhere((i) => i.title == 'Maps key (prod) (other device)');
      expect(copy.fields['value']!.value, 'AIza-theirs');
      expect(
        index(tester).items[mine.id]!.fields['value']!.value,
        isNot('AIza-theirs'),
      );
    });

    testWidgets('a deletion that lost to an edit: keep or delete', (
      tester,
    ) async {
      final mine = await open(tester, deletionOnly: true);
      expect(find.textContaining('Deleted on another device'), findsOneWidget);
      await tester.tap(find.text('Resolve…'));
      await tester.pumpAndSettle();
      expect(find.text('Keep it'), findsOneWidget);
      await tapAndWrite(
        tester,
        find.text('Keep it'),
        () => index(tester).items[mine.id]!.conflict == null,
      );
      expect(index(tester).items, contains(mine.id));
    });

    testWidgets('…or delete it everywhere', (tester) async {
      final mine = await open(tester, deletionOnly: true);
      await tester.tap(find.text('Resolve…'));
      await tester.pumpAndSettle();
      await tapAndWrite(
        tester,
        find.text('Delete everywhere'),
        () => !index(tester).items.containsKey(mine.id),
      );
      expect(
        (await tester.runAsync(
          () => (appContainer(tester).read(vaultSessionProvider) as Unlocked)
              .vault
              .loadAll(),
        ))!.tombstones,
        contains(mine.id),
      );
    });
  });
}
