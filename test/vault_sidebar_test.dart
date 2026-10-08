import 'package:devvault/app/desktop_shell.dart' show ShellStatusBar;
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/core/expiry.dart';
import 'package:devvault/data/vault_filter.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:devvault/shared/desktop/desktop_symbols.dart';
import 'package:devvault/shared/desktop/desktop_theme.dart';

import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  Future<void> open(WidgetTester tester, [String? location]) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: location ?? Routes.vault(),
      vault: TestVault.sample,
      layout: AppLayout.desktop,
    );
  }

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(VaultSidebar))).state.uri
          .toString();

  VaultIndex index(WidgetTester tester) =>
      (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

  String appId(WidgetTester tester, String name) =>
      index(tester).apps.values.firstWhere((a) => a.name == name).id;

  Finder inSidebar(String text) =>
      find.descendant(of: find.byType(VaultSidebar), matching: find.text(text));

  /// The sidebar row whose semantics label starts with [label].
  Finder row(String label) => find.descendant(
    of: find.byType(VaultSidebar),
    matching: find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}')),
  );

  Finder chevron(String label, IconData icon) =>
      find.descendant(of: row(label), matching: find.byIcon(icon));

  bool isSelected(WidgetTester tester, String label) =>
      tester.getSemantics(row(label).first).flagsCollection.isSelected ==
      Tristate.isTrue;

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('counts all, expiring and expired items', (tester) async {
    await open(tester);
    expect(find.text('12 items · this device'), findsOneWidget);
    expect(isSelected(tester, 'All items'), isTrue);
    final allRow = find.ancestor(
      of: inSidebar('All items'),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: allRow.first, matching: find.text('12')),
      findsOneWidget,
    );
    // Play publisher (12 days) and App Store profile (20 days).
    expect(
      find.descendant(
        of: find
            .ancestor(
              of: inSidebar('Expiring in 30 days'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    // Distribution certificate, 3 days ago.
    expect(
      find.descendant(
        of: find
            .ancestor(of: inSidebar('Expired'), matching: find.byType(Row))
            .first,
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    // Nothing to resolve or recover: those rows stay out of the way.
    expect(inSidebar('Conflicts'), findsNothing);
    expect(inSidebar('Unreadable'), findsNothing);
  });

  testWidgets('an unreadable object gets a row, and the row lists it', (
    tester,
  ) async {
    await open(tester);
    // Copy one item's ciphertext over another's: the copy no longer
    // matches where it is, so the next unlock quarantines it.
    final vault =
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).vault;
    final ids = index(tester).items.keys.toList()..sort();
    final items = '${vault.store.root.path}/items';
    File('$items/${ids[0]}.enc').copySync('$items/${ids[1]}.enc');
    final notifier = appContainer(tester).read(vaultSessionProvider.notifier)
      ..lock();
    await tester.pumpAndSettle();
    await tester.runAsync(() => notifier.unlock(testPassword));
    await tester.pumpAndSettle();

    expect(index(tester).quarantined.single.objectId, ids[1]);
    expect(inSidebar('Unreadable'), findsOneWidget);
    expect(
      find.descendant(
        of: find
            .ancestor(of: inSidebar('Unreadable'), matching: find.byType(Row))
            .first,
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(inSidebar('Conflicts'), findsNothing);

    await tap(tester, inSidebar('Unreadable'));
    expect(location(tester), contains('view=quarantine'));
    expect(isSelected(tester, 'Unreadable'), isTrue);
    expect(find.text('Unreadable item'), findsOneWidget);
    expect(find.text(ids[1]), findsOneWidget);
  });

  testWidgets('shows apps open and platforms closed', (tester) async {
    await open(tester);
    expect(row('Kitchenly, 10 items'), findsOneWidget);
    expect(row('Ledgerly, 1 item'), findsOneWidget);
    expect(row('No app, 1 item'), findsOneWidget);
    expect(row('Android, 6 items'), findsOneWidget);
    expect(row('iOS, 3 items'), findsOneWidget);
    expect(row('Web, 1 item'), findsOneWidget);
    expect(row('Server, 1 item'), findsOneWidget);
    expect(inSidebar('Production'), findsNothing);
  });

  testWidgets('tree rows link to app, platform and environment filters', (
    tester,
  ) async {
    await open(tester);
    final kitchenly = appId(tester, 'Kitchenly');

    await tap(tester, inSidebar('Android'));
    expect(location(tester), Routes.vault(app: kitchenly, platform: 'android'));
    expect(isSelected(tester, 'Android'), isTrue);
    expect(isSelected(tester, 'All items'), isFalse);
    // Selecting a platform opens it.
    expect(row('Production, 5 items'), findsOneWidget);
    expect(row('Staging, 1 item'), findsOneWidget);

    await tap(tester, inSidebar('Production'));
    expect(
      location(tester),
      Routes.vault(app: kitchenly, platform: 'android', env: 'production'),
    );
    expect(isSelected(tester, 'Production'), isTrue);
    expect(isSelected(tester, 'Android'), isFalse);

    await tap(tester, inSidebar('No app'));
    expect(location(tester), Routes.vault(app: VaultFilter.none));

    await tap(tester, inSidebar('All items'));
    expect(location(tester), Routes.vault());
  });

  testWidgets('chevrons open and close without changing the list', (
    tester,
  ) async {
    await open(tester);
    await tap(
      tester,
      chevron('iOS', DesktopSymbol.chevronRight.of(DesktopKit.current)),
    );
    expect(row('Production, 3 items'), findsOneWidget);
    expect(location(tester), Routes.vault());

    await tap(
      tester,
      chevron('Kitchenly', DesktopSymbol.chevronDown.of(DesktopKit.current)),
    );
    expect(inSidebar('iOS'), findsNothing);
    expect(inSidebar('Production'), findsNothing);
    expect(location(tester), Routes.vault());
  });

  testWidgets('a link opens the tree down to its selection', (tester) async {
    await open(tester);
    final kitchenly = appId(tester, 'Kitchenly');
    GoRouter.of(tester.element(find.byType(VaultSidebar)))
        .go(Routes.vault(app: kitchenly, platform: 'ios', env: 'production'));
    await tester.pumpAndSettle();
    expect(isSelected(tester, 'Production'), isTrue);
  });

  testWidgets('tags filter the list and toggle off', (tester) async {
    await open(tester);
    for (final tag in ['ci', 'push', 'release', 'signing']) {
      expect(inSidebar(tag), findsOneWidget);
    }
    await tap(tester, inSidebar('ci'));
    expect(location(tester), Routes.vault(tag: 'ci'));
    await tap(tester, inSidebar('push'));
    expect(location(tester), Routes.vault(tag: 'push'));
    await tap(tester, inSidebar('push'));
    expect(location(tester), Routes.vault());
  });

  testWidgets('a sidebar link keeps the search', (tester) async {
    await open(tester, Routes.vault(q: 'firebase'));
    await tap(tester, inSidebar('Ledgerly'));
    expect(
      location(tester),
      Routes.vault(app: appId(tester, 'Ledgerly'), q: 'firebase'),
    );
  });

  testWidgets('typing in search writes the query into the location', (
    tester,
  ) async {
    await open(tester, Routes.vault(tag: 'ci'));
    await tester.enterText(find.byType(EditableText), 'deploy');
    await tester.pumpAndSettle();
    expect(location(tester), Routes.vault(tag: 'ci', q: 'deploy'));

    await tester.enterText(find.byType(EditableText), '');
    await tester.pumpAndSettle();
    expect(location(tester), Routes.vault(tag: 'ci'));
  });

  testWidgets('the search field follows the location', (tester) async {
    await open(tester, Routes.vault(q: 'apns'));
    expect(find.text('apns'), findsOneWidget);
    await tap(tester, inSidebar('All items'));
    // "All items" keeps the search: it only clears the filters.
    expect(find.text('apns'), findsOneWidget);
    GoRouter.of(tester.element(find.byType(VaultSidebar))).go(Routes.vault());
    await tester.pumpAndSettle();
    expect(find.text('apns'), findsNothing);
  });

  testWidgets('rows work from assistive tech too', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    tester.semantics.tap(find.semantics.byLabel('Expired'));
    await tester.pumpAndSettle();
    expect(location(tester), Routes.expiryShowing(expired: true));
    semantics.dispose();
  });

  testWidgets('the footer says when the vault locks itself', (tester) async {
    await open(tester);
    expect(inSidebar('5m'), findsOneWidget);
    expect(find.bySemanticsLabel('Locks after 5m idle'), findsOneWidget);
  });

  testWidgets('the status bar counts what the list shows', (tester) async {
    await open(tester, Routes.vault(tag: 'ci'));
    expect(
      find.descendant(
        of: find.byType(ShellStatusBar),
        matching: find.text('2 items'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Lock locks the vault and shows the unlock screen', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, find.bySemanticsLabel(RegExp('^Lock now')));
    expect(appContainer(tester).read(vaultSessionProvider), isA<Locked>());
    expect(find.text('Unlock your vault'), findsOneWidget);
  });

  group('VaultFilter', () {
    test('reads and writes the same location', () {
      const filter = VaultFilter(
        app: 'a1',
        platform: 'ios',
        env: VaultFilter.none,
        tag: 'push',
        view: VaultView.conflicts,
        q: 'key id',
      );
      final uri = Uri.parse(filter.location(item: 'i1'));
      expect(VaultFilter.fromUri(uri), filter);
      expect(uri.queryParameters['item'], 'i1');
      expect(
        VaultFilter.fromUri(Uri.parse('/vault?view=bogus&q=')).isAll,
        true,
      );
    });

    test('withQuery sets and clears the search only', () {
      const filter = VaultFilter(tag: 'ci');
      expect(filter.withQuery('x'), const VaultFilter(tag: 'ci', q: 'x'));
      expect(filter.withQuery('  '), filter);
      expect(filter.withQuery('x').isAll, isFalse);
      expect(const VaultFilter(q: 'x').isAll, isTrue);
    });
  });

  group('labels', () {
    test('known platforms are spelled their way, others capitalised', () {
      expect(VaultLabels.platform('ios'), 'iOS');
      expect(VaultLabels.platform('macos'), 'macOS');
      expect(VaultLabels.platform('tvos'), 'Tvos');
      expect(VaultLabels.platform(null), 'Other');
      expect(VaultLabels.environment('staging'), 'Staging');
      expect(VaultLabels.environment(null), 'No environment');
    });
  });

  group('ExpiryState', () {
    Item item(DateTime? expiresAt) => Item(
      id: '00000000-0000-4000-8000-0000000000aa',
      typeName: ItemType.appleCertificate.wireName,
      title: 'Cert',
      createdAt: testNow,
      updatedAt: testNow,
      rev: Hlc.zero(testDeviceId),
      deviceId: testDeviceId,
      expiresAt: expiresAt,
      expiresSource: expiresAt == null ? null : ExpirySource.file,
    );

    test('is soon within 30 days and expired from the moment it passes', () {
      ExpiryState at(Duration offset) =>
          ExpiryState.of(item(testNow.add(offset)), testNow);
      expect(ExpiryState.of(item(null), testNow), ExpiryState.none);
      expect(at(const Duration(days: 31)), ExpiryState.valid);
      expect(at(const Duration(days: 30)), ExpiryState.soon);
      expect(at(const Duration(seconds: 1)), ExpiryState.soon);
      expect(at(Duration.zero), ExpiryState.expired);
      expect(at(const Duration(days: -1)), ExpiryState.expired);
    });
  });
}
