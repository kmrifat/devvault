import 'dart:ui' show Tristate;

import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/core/expiry.dart';
import 'package:devvault/data/vault_filter.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:flutter/material.dart';
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
    await open(tester, vault: TestVault.locked);
    expect(inList(find.text('Your vault is empty')), findsOneWidget);
    await tester.tap(inList(find.text('Import')));
    await tester.pump();
    expect(find.text('Import is on its way'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 10));
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
