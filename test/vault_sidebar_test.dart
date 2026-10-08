import 'package:devvault/app/desktop_shell.dart' show ShellStatusBar;
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/core/expiry.dart';
import 'package:devvault/data/vault_filter.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/vault/vault_heading.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
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

  group('organizations', () {
    /// Saves [name] with [change] applied, as the app form would.
    Future<void> editApp(
      WidgetTester tester,
      String name,
      AppRecord Function(AppRecord) change,
    ) async {
      final app = index(tester).apps.values.firstWhere((a) => a.name == name);
      await tester.runAsync(
        () =>
            appContainer(tester)
                .read(vaultSessionProvider.notifier)
                .saveApp(change(app)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('no organization anywhere: the Apps section is unchanged', (
      tester,
    ) async {
      await open(tester);
      expect(index(tester).orgGroups, isEmpty);
      expect(inSidebar('Personal'), findsNothing);
      // Apps and No app are top-level rows, as before.
      expect(
        tester.getTopLeft(row('Kitchenly')).dx,
        tester.getTopLeft(row('No app')).dx,
      );
    });

    testWidgets('apps group under their organization, then Personal; No app '
        'stays last, outside the groups', (tester) async {
      await open(tester);
      await editApp(
        tester,
        'Ledgerly',
        (a) => a.copyWith(organization: 'Acme Corp'),
      );

      expect(row('Acme Corp, 1 item'), findsOneWidget);
      expect(row('Personal, 10 items'), findsOneWidget);
      double y(String label) => tester.getTopLeft(row(label)).dy;
      expect(y('Acme Corp'), lessThan(y('Ledgerly')));
      expect(y('Ledgerly'), lessThan(y('Personal')));
      expect(y('Personal'), lessThan(y('Kitchenly')));
      expect(y('Kitchenly'), lessThan(y('No app')));
      double x(String label) => tester.getTopLeft(row(label)).dx;
      // Rows are full width; their content is indented by depth.
      double indent(String label) => tester
          .getTopLeft(
            find.descendant(of: row(label), matching: find.text(label)).first,
          )
          .dx;
      expect(x('Ledgerly'), x('Acme Corp'));
      expect(indent('Ledgerly'), greaterThan(indent('Acme Corp')));
      expect(indent('Kitchenly'), indent('Ledgerly'));
      expect(indent('No app'), indent('Acme Corp'));

      // An organization is a link to its apps' items.
      await tap(tester, row('Acme Corp'));
      expect(location(tester), Routes.vault(org: 'Acme Corp'));
      expect(isSelected(tester, 'Acme Corp'), isTrue);
      expect(isSelected(tester, 'Ledgerly'), isFalse);
      expect(
        VaultFilter.fromUri(Uri.parse(location(tester)))
            .apply(index(tester))
            .map((i) => i.title),
        ['Stripe secret key'],
      );

      await tap(tester, row('Personal'));
      expect(location(tester), Routes.vault(org: VaultFilter.none));
      expect(
        VaultFilter.fromUri(Uri.parse(location(tester))).apply(index(tester)),
        hasLength(10),
      );

      // Closing a group hides its apps and keeps the list.
      await tap(
        tester,
        chevron('Acme Corp', DesktopSymbol.chevronDown.of(DesktopKit.current)),
      );
      expect(inSidebar('Ledgerly'), findsNothing);
      expect(location(tester), Routes.vault(org: VaultFilter.none));
    });

    testWidgets('search finds items by their app’s domain or repository', (
      tester,
    ) async {
      await open(tester);
      await editApp(
        tester,
        'Ledgerly',
        (a) => a.copyWith(
          identifiers: [
            AppIdentifier.of(IdentifierKind.domain, 'api.ledgerly.example'),
            AppIdentifier.of(
              IdentifierKind.repository,
              'github.com/ledgerly/server',
            ),
          ],
        ),
      );
      for (final q in ['api.ledgerly', 'github.com/ledgerly']) {
        await tester.enterText(find.byType(EditableText), q);
        await tester.pumpAndSettle();
        expect(location(tester), Routes.vault(q: q));
        expect(
          VaultFilter.fromUri(Uri.parse(location(tester)))
              .apply(index(tester))
              .map((i) => i.title),
          ['Stripe secret key'],
        );
        expect(
          find.descendant(
            of: find.byType(VaultListPane),
            matching: find.text('Stripe secret key'),
          ),
          findsOneWidget,
        );
      }
    });
  });

  group('VaultFilter', () {
    test('reads and writes the same location', () {
      const filter = VaultFilter(
        org: 'Acme Corp',
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

    test('an organization titles its list and leads its apps’ paths', () {
      final billing = AppRecord(
        id: '00000000-0000-4000-8000-0000000000b1',
        name: 'Billing API',
        organization: 'Acme Corp',
        createdAt: testNow,
        updatedAt: testNow,
        rev: Hlc.zero(testDeviceId),
        deviceId: testDeviceId,
      );
      final apps = {billing.id: billing};
      expect(
        vaultHeading(const VaultFilter(org: 'Acme Corp'), apps).title,
        'Acme Corp',
      );
      expect(
        vaultHeading(const VaultFilter(org: VaultFilter.none), apps).title,
        'Personal',
      );
      final app = vaultHeading(VaultFilter(app: billing.id), apps);
      expect(app.title, 'Billing API');
      expect(app.path, ['Acme Corp']);
      final ios = vaultHeading(
        VaultFilter(app: billing.id, platform: 'ios'),
        apps,
      );
      expect(ios.path, ['Acme Corp', 'Billing API']);
      expect(const VaultFilter(org: 'Acme Corp').isAll, isFalse);
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
