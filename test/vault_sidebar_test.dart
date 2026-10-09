import 'package:devvault/app/desktop_shell.dart' show ShellStatusBar;
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/core/expiry.dart';
import 'package:devvault/data/vault_filter.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/item_editor/item_editor.dart';
import 'package:devvault/features/vault/vault_heading.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:devvault/shared/desktop/desktop_symbols.dart';
import 'package:devvault/shared/desktop/desktop_theme.dart';

import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
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

  group('context menus and dragging', () {
    AppRecord app(WidgetTester tester, String name) =>
        index(tester).apps.values.firstWhere((a) => a.name == name);

    Item item(WidgetTester tester, String title) =>
        index(tester).items.values.firstWhere((i) => i.title == title);

    /// Lets the vault write that the UI started finish, then settles.
    Future<void> settle(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 300 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(done(), isTrue, reason: 'the write never finished');
      await tester.pumpAndSettle();
    }

    Future<void> saveApp(WidgetTester tester, AppRecord app) async {
      await tester.runAsync(
        () =>
            appContainer(tester)
                .read(vaultSessionProvider.notifier)
                .saveApp(app),
      );
      await tester.pumpAndSettle();
    }

    /// Drags [from] onto [to] with a mouse, as a desktop user would.
    Future<void> drag(WidgetTester tester, Finder from, Finder to) async {
      final gesture = await tester.startGesture(
        tester.getCenter(from),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(to));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    Future<void> rightClick(WidgetTester tester, Finder finder) async {
      await tester.tap(
        finder,
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
    }

    Finder listed(String title) => find.descendant(
      of: find.byType(VaultListPane),
      matching: find.text(title),
    );

    testWidgets('an item dragged onto an app moves there; Undo puts it back', (
      tester,
    ) async {
      await open(tester);
      final ledgerly = app(tester, 'Ledgerly').id;

      await drag(tester, listed('GitHub deploy key'), row('Ledgerly'));
      await settle(
        tester,
        () => item(tester, 'GitHub deploy key').appId == ledgerly,
      );
      expect(row('Ledgerly, 2 items'), findsOneWidget);
      expect(inSidebar('No app'), findsNothing);
      expect(
        find.text('“GitHub deploy key” moved to Ledgerly'),
        findsOneWidget,
      );
      // Dropped on an app: it keeps having no platform or environment.
      expect(item(tester, 'GitHub deploy key').platform, isNull);
      expect(item(tester, 'GitHub deploy key').environment, isNull);

      await tester.tap(find.text('Undo'));
      await settle(
        tester,
        () => item(tester, 'GitHub deploy key').appId == null,
      );
      expect(row('No app, 1 item'), findsOneWidget);
      expect(row('Ledgerly, 1 item'), findsOneWidget);
    });

    testWidgets('an item dragged onto a platform takes the app and platform '
        'and keeps its environment', (tester) async {
      await open(tester);
      final kitchenly = app(tester, 'Kitchenly').id;

      await drag(tester, listed('Stripe secret key'), row('iOS'));
      await settle(
        tester,
        () => item(tester, 'Stripe secret key').appId == kitchenly,
      );
      final moved = item(tester, 'Stripe secret key');
      expect(moved.platform, 'ios');
      expect(moved.environment, 'production');
      expect(row('iOS, 4 items'), findsOneWidget);
      expect(
        find.text('“Stripe secret key” moved to Kitchenly › iOS'),
        findsOneWidget,
      );
    });

    testWidgets('the row an item is already in doesn’t take it', (
      tester,
    ) async {
      await open(tester);
      final before = item(tester, 'Stripe secret key');

      await drag(tester, listed('Stripe secret key'), row('Ledgerly'));
      await tester.pumpAndSettle();
      expect(item(tester, 'Stripe secret key').rev, before.rev);
      expect(find.textContaining('moved to'), findsNothing);
    });

    testWidgets('an app dragged onto an organization moves into it; the '
        'menu takes it out again', (tester) async {
      await open(tester);
      await saveApp(
        tester,
        app(tester, 'Ledgerly').copyWith(organization: 'Acme Corp'),
      );
      expect(row('Personal, 10 items'), findsOneWidget);

      await drag(tester, row('Kitchenly'), row('Acme Corp'));
      await settle(
        tester,
        () => app(tester, 'Kitchenly').organization == 'Acme Corp',
      );
      expect(row('Acme Corp, 11 items'), findsOneWidget);
      expect(inSidebar('Personal'), findsNothing);
      expect(find.text('“Kitchenly” moved to Acme Corp'), findsOneWidget);

      await rightClick(tester, row('Kitchenly'));
      expect(find.text('Edit app…'), findsOneWidget);
      expect(find.text('Delete app…'), findsOneWidget);
      await tester.tap(find.text('Remove from Acme Corp'));
      await settle(tester, () => app(tester, 'Kitchenly').organization == null);
      expect(row('Personal, 10 items'), findsOneWidget);
      expect(row('Acme Corp, 1 item'), findsOneWidget);
    });

    testWidgets('an organization’s menu adds an item to its only app', (
      tester,
    ) async {
      await open(tester);
      await saveApp(
        tester,
        app(tester, 'Ledgerly').copyWith(organization: 'Acme Corp'),
      );

      await rightClick(tester, row('Acme Corp'));
      expect(find.text('New app…'), findsOneWidget);
      expect(find.text('Rename organization…'), findsOneWidget);
      await tester.tap(find.text('New item…'));
      await tester.pumpAndSettle();
      expect(find.byType(ItemEditor), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ItemEditor),
          matching: find.textContaining('Ledgerly'),
        ),
        findsWidgets,
      );
    });

    testWidgets('a platform’s menu adds an item there', (tester) async {
      await open(tester);
      await rightClick(tester, row('iOS'));
      await tester.tap(find.text('New item…'));
      await tester.pumpAndSettle();
      final editor = find.byType(ItemEditor);
      expect(editor, findsOneWidget);
      expect(
        find.descendant(of: editor, matching: find.textContaining('Kitchenly')),
        findsWidgets,
      );
    });

    testWidgets('renaming an organization renames it on each of its apps', (
      tester,
    ) async {
      await open(tester);
      await saveApp(
        tester,
        app(tester, 'Ledgerly').copyWith(organization: 'Acme Corp'),
      );
      await saveApp(
        tester,
        app(tester, 'Kitchenly').copyWith(organization: 'Acme Corp'),
      );
      await tap(tester, row('Acme Corp'));

      await rightClick(tester, row('Acme Corp'));
      await tester.tap(find.text('Rename organization…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('organization-name')),
        '  Globex ',
      );
      await tester.pump();
      await tester.tap(find.text('Rename'));
      await settle(
        tester,
        () =>
            index(tester).apps.values.every((a) => a.organization == 'Globex'),
      );
      expect(row('Globex, 11 items'), findsOneWidget);
      expect(inSidebar('Acme Corp'), findsNothing);
      // The selection follows the new name.
      expect(location(tester), Routes.vault(org: 'Globex'));
    });
  });

  group('TreePlace', () {
    testWidgets('moves only what its row sets, and puts an item back', (
      tester,
    ) async {
      await open(tester);
      final idx = index(tester);
      final stripe = idx.items.values.firstWhere(
        (i) => i.title == 'Stripe secret key',
      );
      final kitchenly = appId(tester, 'Kitchenly');

      final toApp = TreePlace(app: kitchenly).applyTo(stripe);
      expect(toApp.appId, kitchenly);
      expect(toApp.platform, 'server');
      expect(toApp.environment, 'production');

      final toOther = const TreePlace(
        app: VaultFilter.none,
        platform: VaultFilter.none,
        env: VaultFilter.none,
      ).applyTo(stripe);
      expect(toOther.appId, isNull);
      expect(toOther.platform, isNull);
      expect(toOther.environment, isNull);

      final back = TreePlace.of(stripe).applyTo(toOther);
      expect(back.appId, stripe.appId);
      expect(back.platform, 'server');
      expect(back.environment, 'production');

      expect(TreePlace(app: stripe.appId!).holds(stripe, idx), isTrue);
      expect(
        TreePlace(app: stripe.appId!, platform: 'ios').holds(stripe, idx),
        isFalse,
      );
      expect(const TreePlace(app: VaultFilter.none).label(idx), 'No app');
      expect(
        TreePlace(
          app: kitchenly,
          platform: VaultFilter.none,
          env: 'staging',
        ).label(idx),
        'Kitchenly › Other › Staging',
      );
    });
  });
}
