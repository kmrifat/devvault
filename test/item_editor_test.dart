import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/item_editor/item_draft.dart';
import 'package:devvault/features/vault/item_detail_pane.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/shared/desktop_ui.dart' show DesktopTokenField;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  group('ItemDraft', () {
    var counter = 0;
    Item fresh(ItemType type, String title) => Item(
      id: '00000000-0000-4000-8000-${(++counter).toString().padLeft(12, '0')}',
      typeName: type.wireName,
      title: title,
      createdAt: testNow,
      updatedAt: testNow,
      rev: Hlc.zero(testDeviceId),
      deviceId: testDeviceId,
    );

    Item imported() =>
        fresh(ItemType.androidKeystore, 'Upload keystore').copyWith(
          fields: {
            'sha1': const ItemField(value: 'AA:BB', source: FieldSource.file),
            'store_password': const ItemField(
              value: 'pw',
              source: FieldSource.user,
              secret: true,
            ),
          },
          expiresAt: DateTime.utc(2051),
          expiresSource: ExpirySource.file,
          tags: ['release'],
        );

    test('a new item starts with its type’s fields, empty', () {
      final draft = ItemDraft.create(ItemType.androidKeystore, appId: 'a1');
      expect(
        [for (final f in draft.fields) (f.name, f.key, f.secret)],
        [
          ('Alias', 'alias', false),
          ('Store password', 'store_password', true),
          ('Key password', 'key_password', true),
        ],
      );
      expect(draft.appId, 'a1');
      expect(draft.isNew, isTrue);
    });

    test('changing type keeps what was typed and swaps the suggestions', () {
      final draft = ItemDraft.create(ItemType.androidKeystore);
      draft.fields.first.value = 'upload';
      draft.changeType(ItemType.oauthClient);
      expect(
        [for (final f in draft.fields) f.key],
        ['alias', 'client_id', 'client_secret'],
      );
    });

    test('needs a name and distinct field names', () {
      final draft = ItemDraft.create(ItemType.genericFile)
        ..fields.addAll([
          DraftField(name: 'Token', value: 'a'),
          DraftField(name: 'token', value: 'b'),
          DraftField(value: 'c'),
          DraftField(), // blank rows are ignored
        ]);
      expect(draft.validate(), {
        'title': 'Give it a name',
        '1': 'Another field has this name',
        '2': 'Name this field',
      });
      draft
        ..title = 'Deploy'
        ..fields.removeRange(1, 3);
      expect(draft.validate(), isEmpty);
    });

    test('a new item gets typed fields, user expiry, tags and notes', () {
      final draft = ItemDraft.create(ItemType.genericSecret)
        ..title = '  Stripe key  '
        ..tags = 'billing, prod, billing,'
        ..notes = 'rotate yearly'
        ..expiresAt = DateTime.utc(2027, 3, 1);
      draft.fields.single.value = 'sk_live';
      draft.fields.add(DraftField(name: 'API key ID', value: 'k1'));
      draft.fields.add(DraftField()); // dropped
      final item = draft.toItem(fresh);
      expect(item.title, 'Stripe key');
      expect(item.tags, ['billing', 'prod']);
      expect(item.notes, 'rotate yearly');
      expect(item.expiresAt, DateTime.utc(2027, 3, 1));
      expect(item.expiresSource, ExpirySource.user);
      expect(item.fields.keys, ['value', 'api_key_id']);
      expect(item.fields['value']!.secret, isTrue);
      expect(item.fields['value']!.source, FieldSource.user);
    });

    test('editing keeps file facts, the file expiry and the identity', () {
      final base = imported();
      final draft = ItemDraft.edit(base)
        ..title = 'Renamed'
        ..expiresAt = DateTime.utc(2030); // ignored: it came from the file
      // Even if a row were changed, a file fact is written back as it was.
      draft.fields.first
        ..name = 'SHA-1'
        ..value = 'tampered';
      final item = draft.toItem(fresh);
      expect(item.id, base.id);
      expect(item.createdAt, base.createdAt);
      expect(item.title, 'Renamed');
      expect(item.fields['sha1']!.value, 'AA:BB');
      expect(item.fields['sha1']!.source, FieldSource.file);
      expect(item.expiresAt, DateTime.utc(2051));
      expect(item.expiresSource, ExpirySource.file);
      expect(item.tags, ['release']);
    });

    test('renaming a typed field renames its key; clearing a user expiry', () {
      final base = fresh(ItemType.genericSecret, 'Token').copyWith(
        fields: {
          'value': const ItemField(value: 'x', source: FieldSource.user),
        },
        expiresAt: DateTime.utc(2027),
        expiresSource: ExpirySource.user,
      );
      final draft = ItemDraft.edit(base)..expiresAt = null;
      expect(draft.fields.single.key, 'value');
      draft.fields.single.name = 'Access token';
      final item = draft.toItem(fresh);
      expect(item.fields.keys, ['access_token']);
      expect(item.expiresAt, isNull);
      expect(item.expiresSource, isNull);
    });
  });

  group('screens', () {
    Future<void> open(WidgetTester tester, [String? location]) async {
      tester.view
        ..physicalSize = const Size(1440, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpUnlockedApp(
        tester,
        location: location ?? Routes.vault(),
        vault: TestVault.sample,
        layout: AppLayout.desktop,
      );
    }

    VaultIndex index(WidgetTester tester) =>
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

    GoRouter router(WidgetTester tester) =>
        GoRouter.of(tester.element(find.byType(VaultListPane)));

    Finder input(Finder within) =>
        find.descendant(of: within, matching: find.byType(EditableText));

    Finder labelled(String label) => find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == label,
    );

    /// Taps [button] and lets the real file I/O behind it finish, until
    /// [done] (I/O needs runAsync, and the save spinner never settles).
    Future<void> settleWrite(
      WidgetTester tester,
      Finder button,
      bool Function() done,
    ) async {
      await tester.tap(button);
      for (var i = 0; i < 200 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(done(), isTrue, reason: 'the write never finished');
      await tester.pumpAndSettle();
    }

    testWidgets('+ adds an item where the user is looking and selects it', (
      tester,
    ) async {
      await open(tester);
      final kitchenly = index(tester).apps.values
          .firstWhere((a) => a.name == 'Kitchenly');
      router(tester)
          .go(Routes.vault(app: kitchenly.id, platform: 'ios', env: 'staging'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('New item'));
      await tester.pumpAndSettle();
      expect(find.text('New item'), findsOneWidget);

      // Saving without a name says so.
      await tester.tap(find.text('Add item'));
      await tester.pumpAndSettle();
      expect(find.text('Give it a name'), findsOneWidget);

      await tester.enterText(
        input(find.byKey(const ValueKey('item-name'))),
        'Sign in with Apple key',
      );
      await tester.enterText(input(labelled('Value value')), 'secret-123');
      // The environment is a combo box: any value, stored as typed.
      await tester.enterText(
        input(find.byKey(const ValueKey('item-environment'))),
        ' qa-eu ',
      );
      // Tags are tokens.
      await tester.enterText(input(find.byType(DesktopTokenField)), 'siwa');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      // An expiry typed by the user is checked, then saved as theirs.
      final expiry = input(find.byKey(const ValueKey('item-expiry')));
      await tester.enterText(expiry, 'next year');
      await tester.tap(find.text('Add item'));
      await tester.pumpAndSettle();
      expect(find.text('Type the date as YYYY-MM-DD'), findsOneWidget);
      await tester.enterText(expiry, '2027-02-30');
      await tester.tap(find.text('Add item'));
      await tester.pumpAndSettle();
      expect(find.text('No such date'), findsOneWidget);
      expect(index(tester).all.any((i) => i.title.contains('Apple')), isFalse);
      await tester.enterText(expiry, '2027-03-01');
      await settleWrite(
        tester,
        find.text('Add item'),
        () => index(tester).all.any((i) => i.title == 'Sign in with Apple key'),
      );

      final created = index(tester).all
          .firstWhere((i) => i.title == 'Sign in with Apple key');
      expect(created.appId, kitchenly.id);
      expect(created.platform, 'ios');
      expect(created.environment, 'qa-eu');
      expect(created.tags, ['siwa']);
      expect(created.expiresAt, DateTime.utc(2027, 3, 1));
      expect(created.expiresSource, ExpirySource.user);
      expect(created.typeName, ItemType.genericSecret.wireName);
      expect(created.fields['value']!.value, 'secret-123');
      expect(created.fields['value']!.secret, isTrue);
      expect(router(tester).state.uri.queryParameters['item'], created.id);
      expect(
        find.descendant(
          of: find.byType(ItemDetailPane),
          matching: find.text('Sign in with Apple key'),
        ),
        findsOneWidget,
      );
      expect(find.text('secret-123'), findsNothing);
    });

    testWidgets('Edit changes an item and keeps it selected', (tester) async {
      await open(tester);
      final keystore = index(tester).all
          .firstWhere((i) => i.title == 'Upload keystore');
      router(tester).go(Routes.vault(item: keystore.id));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit “Upload keystore”'), findsOneWidget);
      // The expiry came from the file: shown, not editable.
      expect(find.byKey(const ValueKey('item-expiry')), findsNothing);
      // So did some fields: shown, not editable.
      expect(find.text('From file'), findsWidgets);

      final name = input(find.byKey(const ValueKey('item-name')));
      await tester.enterText(name, 'Play upload keystore');
      await settleWrite(
        tester,
        find.text('Save'),
        () => index(tester).items[keystore.id]!.title == 'Play upload keystore',
      );

      final edited = index(tester).items[keystore.id]!;
      expect(edited.title, 'Play upload keystore');
      expect(edited.fields['sha1'], keystore.fields['sha1']);
      expect(edited.attachments, keystore.attachments);
      expect(edited.expiresSource, ExpirySource.file);
      expect(edited.rev > keystore.rev, isTrue);
      expect(router(tester).state.uri.queryParameters['item'], keystore.id);
      expect(
        find.descendant(
          of: find.byType(ItemDetailPane),
          matching: find.text('Play upload keystore'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Delete asks first, then removes the item', (tester) async {
      await open(tester);
      final maps = index(tester).all
          .firstWhere((i) => i.title == 'Maps API key');
      router(tester).go(Routes.vault(tag: null, item: maps.id));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete item…'));
      await tester.pumpAndSettle();
      expect(find.text('Delete “Maps API key”?'), findsOneWidget);

      // Cancel keeps it.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(index(tester).items, contains(maps.id));

      await tester.tap(find.bySemanticsLabel('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete item…'));
      await tester.pumpAndSettle();
      await settleWrite(
        tester,
        find.text('Delete'),
        () => !index(tester).items.containsKey(maps.id),
      );

      expect(index(tester).items, isNot(contains(maps.id)));
      expect(router(tester).state.uri.toString(), Routes.vault());
      expect(find.text('“Maps API key” deleted'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 10));
    });
  });
}
