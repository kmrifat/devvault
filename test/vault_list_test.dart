import 'dart:ui' show Tristate;

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/core/expiry.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_filter.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/import/import_draft.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/services/file_import.dart';
import 'package:devvault/shared/ui.dart' show BCChip, BCText, MonoText;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  Future<void> open(
    WidgetTester tester, {
    String? location,
    TestVault vault = TestVault.sample,
    List<Override> overrides = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1440, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: location ?? Routes.vault(),
      vault: vault,
      layout: AppLayout.desktop,
      overrides: overrides,
    );
  }

  Finder inList(Finder finder) =>
      find.descendant(of: find.byType(VaultListPane), matching: finder);

  /// Item titles in the order the list shows them.
  List<String> titles(WidgetTester tester) => [
    for (final widget in tester.widgetList<Semantics>(
      inList(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              (w.properties.label ?? '').contains(', '),
        ),
      ),
    ))
      widget.properties.label!.split(', ').first,
  ];

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(VaultListPane))).state.uri
          .toString();

  VaultIndex index(WidgetTester tester) =>
      (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

  Item item(WidgetTester tester, String title) =>
      index(tester).all.firstWhere((i) => i.title == title);

  Future<void> go(WidgetTester tester, String location) async {
    GoRouter.of(tester.element(find.byType(VaultListPane))).go(location);
    await tester.pumpAndSettle();
  }

  testWidgets('lists every item by title under "All items"', (tester) async {
    await open(tester);
    expect(inList(find.text('All items')), findsOneWidget);
    expect(inList(find.text('12')), findsOneWidget);
    expect(titles(tester), [
      'APNs auth key',
      'App Store profile',
      'Distribution certificate',
      'Firebase config',
      'Firebase config',
      'GitHub deploy key',
      'Google Sign-In client',
      'Maps API key',
      'Play publisher',
      'Stripe secret key',
      'Upload keystore',
      'Web OAuth client',
    ]);
  });

  testWidgets('shows expiry as a chip when it needs attention', (tester) async {
    await open(tester);
    expect(inList(find.text('12 days')), findsOneWidget); // Play publisher
    expect(inList(find.text('20 days')), findsOneWidget); // App Store profile
    expect(inList(find.text('Expired')), findsOneWidget); // Distribution cert
    expect(inList(find.text('Jan 2051')), findsOneWidget); // Upload keystore
  });

  testWidgets('an undated row has no chip and no date', (tester) async {
    await open(tester);
    final undated = index(tester).all
        .where((i) => i.expiresAt == null && i.conflict == null);
    expect(undated, isNotEmpty);
    for (final item in undated) {
      final row = inList(
        find.byWidgetPredicate(
          (w) => w is VaultItemRow && w.item.id == item.id,
        ),
      );
      expect(row, findsOneWidget, reason: item.title);
      expect(
        find.descendant(of: row, matching: find.byType(BCChip)),
        findsNothing,
        reason: item.title,
      );
      // Title and file name or type, nothing more.
      expect(
        find
                .descendant(of: row, matching: find.byType(BCText))
                .evaluate()
                .length +
            find
                .descendant(of: row, matching: find.byType(MonoText))
                .evaluate()
                .length,
        1,
        reason: item.title,
      );
    }
  });

  testWidgets('arrow keys move the selection through the list', (tester) async {
    await open(tester, location: Routes.vault(tag: 'release'));
    final order = titles(tester);
    expect(order.length, greaterThan(2));
    String selectedTitle() {
      final id = Uri.parse(location(tester)).queryParameters['item'];
      return index(tester).items[id]!.title;
    }

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    await tester.tap(inList(find.text(order.first)));
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.arrowDown);
    expect(selectedTitle(), order[1]);
    expect(location(tester), contains('tag=release'));
    await press(LogicalKeyboardKey.arrowDown);
    expect(selectedTitle(), order[2]);
    await press(LogicalKeyboardKey.arrowUp);
    await press(LogicalKeyboardKey.arrowUp);
    expect(selectedTitle(), order.first);
    // The ends hold.
    await press(LogicalKeyboardKey.arrowUp);
    expect(selectedTitle(), order.first);
    for (var i = 0; i < order.length; i++) {
      await press(LogicalKeyboardKey.arrowDown);
    }
    expect(selectedTitle(), order.last);
  });

  testWidgets('arrows typed in search stay in the search field', (
    tester,
  ) async {
    await open(tester);
    final before = location(tester);
    await tester.tap(find.byType(EditableText).first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(location(tester), before);
  });

  testWidgets(
    '1,000 rows: built lazily, scroll, and the selection stays in view',
    (tester) async {
      await open(tester, vault: TestVault.locked);
      // Written straight to the vault, then loaded the way an unlock does.
      final vault =
          (appContainer(tester).read(vaultSessionProvider) as Unlocked).vault;
      await tester.runAsync(() async {
        for (var i = 0; i < 1000; i++) {
          await vault.putItem(
            vault.newItem(
              type: ItemType.genericSecret,
              title: 'Token ${i.toString().padLeft(4, '0')}',
            ),
          );
        }
      });
      final notifier = appContainer(tester).read(vaultSessionProvider.notifier)
        ..lock();
      await tester.pumpAndSettle();
      await tester.runAsync(() => notifier.unlock(testPassword));
      await tester.pumpAndSettle();
      expect(inList(find.text('1000')), findsOneWidget);
      // Only what's on screen (and a little beyond) is built.
      expect(find.byType(VaultItemRow).evaluate().length, lessThan(60));

      final list = inList(find.byType(Scrollable)).first;
      for (var i = 0; i < 3; i++) {
        await tester.fling(list, const Offset(0, -2000), 3000);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(inList(find.text('Token 0000')), findsNothing);
      await tester.fling(list, const Offset(0, 20000), 20000);
      await tester.pumpAndSettle();

      // Walk down past the bottom of the pane: the selection scrolls along.
      await tester.tap(inList(find.text('Token 0000')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      final selected = inList(find.text('Token 0040'));
      expect(selected, findsOneWidget);
      final view = tester.getRect(list);
      final row = tester.getRect(selected);
      expect(view.top <= row.top && row.bottom <= view.bottom, isTrue);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets('a tree selection sets the title, path and items', (
    tester,
  ) async {
    await open(tester);
    final kitchenly = index(tester).apps.values
        .firstWhere((a) => a.name == 'Kitchenly')
        .id;
    await go(
      tester,
      Routes.vault(app: kitchenly, platform: 'android', env: 'production'),
    );
    expect(inList(find.text('Production')), findsOneWidget);
    expect(inList(find.text('Kitchenly')), findsOneWidget);
    expect(inList(find.text('Android')), findsOneWidget);
    expect(titles(tester), [
      'Firebase config',
      'Google Sign-In client',
      'Maps API key',
      'Play publisher',
      'Upload keystore',
    ]);

    await go(tester, Routes.vault(app: kitchenly));
    expect(inList(find.text('Kitchenly')), findsOneWidget);
    expect(titles(tester), hasLength(10));

    await go(tester, Routes.vault(tag: 'ci'));
    expect(inList(find.text('#ci')), findsOneWidget);
    expect(titles(tester), ['GitHub deploy key', 'Play publisher']);
  });

  testWidgets('tabs narrow the list and are part of the link', (tester) async {
    await open(tester);
    await tester.tap(inList(find.text('Expiring')));
    await tester.pumpAndSettle();
    expect(location(tester), Routes.vault(kind: 'expiring'));
    expect(titles(tester), [
      'App Store profile',
      'Distribution certificate',
      'Play publisher',
    ]);

    await tester.tap(inList(find.text('Files')));
    await tester.pumpAndSettle();
    expect(location(tester), Routes.vault(kind: 'files'));
    expect(titles(tester), ['Upload keystore']);
    // A file's row shows its name rather than the type.
    expect(inList(find.text('kitchenly-upload.jks')), findsOneWidget);

    await tester.tap(inList(find.text('Secrets')));
    await tester.pumpAndSettle();
    expect(titles(tester), hasLength(11));
    expect(titles(tester), isNot(contains('Upload keystore')));
  });

  testWidgets('tapping a row selects it and keeps the filter', (tester) async {
    await open(tester, location: Routes.vault(tag: 'push'));
    await tester.tap(inList(find.text('APNs auth key')));
    await tester.pumpAndSettle();
    final apns = item(tester, 'APNs auth key');
    expect(location(tester), Routes.vault(item: apns.id, tag: 'push'));
    final row = inList(find.bySemanticsLabel(RegExp('^APNs auth key')));
    expect(
      tester.getSemantics(row).flagsCollection.isSelected,
      Tristate.isTrue,
    );
  });

  testWidgets('search narrows the list and says when nothing matches', (
    tester,
  ) async {
    await open(tester, location: Routes.vault(q: '7KQ2M9XH4D'));
    expect(titles(tester), ['APNs auth key']);
    await go(tester, Routes.vault(q: 'nothing like this'));
    expect(inList(find.text('No matches')), findsOneWidget);
  });

  testWidgets('an empty vault invites an import', (tester) async {
    final opener = _CountingOpener();
    await open(
      tester,
      vault: TestVault.locked,
      overrides: [fileOpenerProvider.overrideWithValue(opener)],
    );
    expect(inList(find.text('Your vault is empty')), findsOneWidget);
    await tester.tap(inList(find.text('Import')));
    await tester.pumpAndSettle();
    // The file picker opens (import itself is covered in import_test.dart).
    expect(opener.picks, 1);
  });

  group('VaultKind', () {
    test('reads unknown names as all and writes only the others', () {
      expect(VaultKind.parse('files'), VaultKind.files);
      expect(VaultKind.parse('bogus'), VaultKind.all);
      expect(const VaultFilter().location(), '/vault');
      expect(
        const VaultFilter(kind: VaultKind.secrets).location(),
        '/vault?kind=secrets',
      );
    });
  });

  test('days left round up to whole days', () {
    expect(daysLeft(testNow.add(const Duration(hours: 1)), testNow), '1 day');
    expect(daysLeft(testNow.add(const Duration(days: 12)), testNow), '12 days');
    expect(
      daysLeft(testNow.add(const Duration(days: 11, hours: 2)), testNow),
      '12 days',
    );
  });
}

/// A file picker the user cancels, counting how often it was opened.
class _CountingOpener implements FileOpener {
  int picks = 0;

  @override
  Future<List<PickedFile>> pick() async {
    picks++;
    return const [];
  }
}
