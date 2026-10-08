import 'package:bc_ui/bc_ui.dart' show BCChip, BCSelect;
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_filter.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/app_editor/app_draft.dart';
import 'package:devvault/features/app_editor/app_editor.dart';
import 'package:devvault/features/vault/mobile_vault_screen.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:devvault/shared/desktop_ui.dart'
    show DesktopComboBox, DesktopPopup;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  AppRecord record(String id, String name) => AppRecord(
    id: '00000000-0000-4000-8000-$id',
    name: name,
    createdAt: testNow,
    updatedAt: testNow,
    rev: Hlc.zero(testDeviceId),
    deviceId: testDeviceId,
  );

  group('AppDraft', () {
    final kitchenly = record('000000000001', 'Kitchenly');

    test('needs a unique name and well-formed identifiers', () {
      final draft = AppDraft.create();
      expect(draft.validate([kitchenly]), {'name': 'Give the app a name'});

      draft
        ..name = ' kitchenly '
        ..identifiers.addAll([
          DraftIdentifier(kindName: 'bundle_id', value: 'not a bundle'),
          DraftIdentifier(kindName: 'package_name', value: '1bad.name'),
          DraftIdentifier(value: 'api.example.com'),
          // Empty rows are dropped, not flagged; anything goes for a URL.
          DraftIdentifier(),
          DraftIdentifier(kindName: 'url', value: 'not even a url'),
        ]);
      expect(draft.validate([kitchenly]), {
        'name': 'Another app has this name',
        'id0': 'Not a bundle ID: not a bundle',
        'id1': 'Not a package name: 1bad.name',
        'id2': 'Choose what kind of identifier this is',
      });

      draft
        ..name = 'Ledgerly'
        ..identifiers.removeRange(0, 3);
      expect(draft.validate([kitchenly]), isEmpty);
    });

    test('saving trims, drops empty rows and repeats, and stores bundle IDs '
        'and package names where older clients read them', () {
      final draft = AppDraft.create()
        ..name = ' Billing API '
        ..organization = '  Acme Corp '
        ..kindName = AppKind.backend.wireName
        ..identifiers.addAll([
          DraftIdentifier(kindName: 'domain', value: ' api.acme.example '),
          DraftIdentifier(kindName: 'domain', value: 'api.acme.example'),
          DraftIdentifier(kindName: 'bundle_id', value: 'com.acme.billing'),
          DraftIdentifier(kindName: 'repository', value: ''),
          DraftIdentifier(),
        ]);
      final app = draft.toApp((name) => record('000000000002', name));
      expect(app.name, 'Billing API');
      expect(app.organization, 'Acme Corp');
      expect(app.kind, AppKind.backend);
      expect(app.bundleIds, ['com.acme.billing']);
      expect(app.identifiers, [
        AppIdentifier.of(IdentifierKind.domain, 'api.acme.example'),
      ]);
    });

    test('editing keeps the identity, clears what was emptied and keeps '
        'what this version does not know', () {
      final acme = AppRecord.fromJson({
        ...record('000000000003', 'Billing').toJson(),
        'organization': 'Acme',
        'kind': 'game',
        'bundle_ids': ['com.acme.app'],
        'identifiers': [
          {'kind': 'npm_package', 'value': '@acme/billing', 'scope': 'org'},
        ],
      });
      final draft = AppDraft.edit(acme);
      expect(draft.organization, 'Acme');
      expect(draft.kindName, 'game');
      expect(draft.identifiers.map((i) => (i.kindName, i.value)), [
        ('bundle_id', 'com.acme.app'),
        ('npm_package', '@acme/billing'),
      ]);
      draft
        ..name = 'Billing Pro'
        ..organization = ' ';
      final app = draft.toApp((_) => throw StateError('not new'));
      expect(app.id, acme.id);
      expect(app.createdAt, acme.createdAt);
      expect(app.name, 'Billing Pro');
      expect(app.organization, isNull);
      expect(app.kindName, 'game');
      expect(app.bundleIds, ['com.acme.app']);
      expect(app.identifiers.single.toJson(), {
        'kind': 'npm_package',
        'value': '@acme/billing',
        'scope': 'org',
      });
    });
  });

  VaultIndex index(WidgetTester tester) =>
      (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

  Future<void> settleWrite(
    WidgetTester tester,
    Finder button,
    bool Function() done,
  ) async {
    await tester.tap(button);
    for (var i = 0; i < 300 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(done(), isTrue, reason: 'the write never finished');
    await tester.pumpAndSettle();
  }

  /// Saves [app] through the session, as the form would.
  Future<AppRecord> saveApp(WidgetTester tester, AppRecord app) async {
    final saved = await tester.runAsync(
      () =>
          appContainer(tester).read(vaultSessionProvider.notifier).saveApp(app),
    );
    await tester.pumpAndSettle();
    return saved!;
  }

  AppRecord appNamed(WidgetTester tester, String name) =>
      index(tester).apps.values.firstWhere((a) => a.name == name);

  Finder editable(Finder within) =>
      find.descendant(of: within, matching: find.byType(EditableText));

  group('desktop sheet', () {
    Future<void> open(WidgetTester tester) async {
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
    }

    GoRouter router(WidgetTester tester) =>
        GoRouter.of(tester.element(find.byType(VaultListPane)));

    Finder inSidebar(String text) => find.descendant(
      of: find.byType(VaultSidebar),
      matching: find.text(text),
    );

    Finder inList(String text) => find.descendant(
      of: find.byType(VaultListPane),
      matching: find.text(text),
    );

    /// A pop-up's choices, and picking one. (macos_ui draws its menu rows
    /// in the test font, which is too wide for them, so pick through the
    /// pop-up's callback.)
    DesktopPopup<String> popup(WidgetTester tester, Finder at) =>
        tester.widget<DesktopPopup<String>>(
          find.descendant(of: at, matching: find.byType(DesktopPopup<String>)),
        );

    testWidgets('+ in the sidebar adds an app with an organization, a kind '
        'and identifiers, and opens it', (tester) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('New app'));
      await tester.pumpAndSettle();
      expect(find.text('New app'), findsOneWidget);
      expect(
        find.textContaining('An app, site, service or tool'),
        findsOneWidget,
      );

      await tester.enterText(
        editable(find.byKey(const ValueKey('app-name'))),
        'Ledgerly',
      );
      await tester.tap(find.text('Add app'));
      await tester.pumpAndSettle();
      expect(find.text('Another app has this name'), findsOneWidget);

      await tester.enterText(
        editable(find.byKey(const ValueKey('app-name'))),
        'Billing API',
      );
      await tester.enterText(
        editable(find.byKey(const ValueKey('app-organization'))),
        'Acme Corp',
      );
      // Kind starts as Not set; nothing is chosen for the user.
      final kind = popup(tester, find.byKey(const ValueKey('app-kind')));
      expect(kind.value, '');
      expect(kind.choices.map((c) => c.label), [
        'Not set',
        'Mobile app',
        'Web app',
        'Desktop app',
        'Backend service',
        'CLI / tool',
        'Library',
        'Other',
      ]);
      kind.onChanged!('backend');
      await tester.pumpAndSettle();

      // Identifiers: a row has no kind until one is picked.
      await tester.tap(find.text('Add Identifier'));
      await tester.pumpAndSettle();
      await tester.enterText(
        editable(find.byKey(const ValueKey('app-identifier-0'))),
        'api.acme.example',
      );
      await tester.tap(find.text('Add app'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose what kind of identifier this is'),
        findsOneWidget,
      );
      final idKind = popup(
        tester,
        find.byKey(const ValueKey('app-identifier-kind-0')),
      );
      expect(idKind.value, isNull);
      expect(idKind.choices.map((c) => c.label), [
        'Bundle ID (Apple)',
        'Package name (Android)',
        'Domain',
        'URL',
        'Repository',
        'Other',
      ]);
      idKind.onChanged!('domain');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Identifier'));
      await tester.pumpAndSettle();
      popup(
        tester,
        find.byKey(const ValueKey('app-identifier-kind-1')),
      ).onChanged!('bundle_id');
      await tester.pumpAndSettle();
      await tester.enterText(
        editable(find.byKey(const ValueKey('app-identifier-1'))),
        'com.acme.billing',
      );
      // A third row, removed again.
      await tester.tap(find.text('Add Identifier'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Remove Identifier'));
      await tester.pumpAndSettle();

      await settleWrite(
        tester,
        find.text('Add app'),
        () => index(tester).apps.values.any((a) => a.name == 'Billing API'),
      );

      final billing = appNamed(tester, 'Billing API');
      expect(billing.organization, 'Acme Corp');
      expect(billing.kind, AppKind.backend);
      expect(billing.bundleIds, ['com.acme.billing']);
      expect(billing.identifiers, [
        AppIdentifier.of(IdentifierKind.domain, 'api.acme.example'),
      ]);
      expect(
        router(tester).state.uri.toString(),
        Routes.vault(app: billing.id),
      );
      // The details strip: organization and kind, then every identifier.
      expect(inList('Acme Corp · Backend service'), findsOneWidget);
      expect(inList('com.acme.billing · api.acme.example'), findsOneWidget);
    });

    testWidgets('the organization suggests the ones already in the vault', (
      tester,
    ) async {
      await open(tester);
      await saveApp(
        tester,
        appNamed(tester, 'Ledgerly').copyWith(organization: 'Acme Corp'),
      );
      await tester.tap(inSidebar('Kitchenly'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit app…'));
      await tester.pumpAndSettle();

      final org = tester.widget<DesktopComboBox>(
        find.byKey(const ValueKey('app-organization')),
      );
      expect(org.value, '');
      expect(org.suggestions, ['Acme Corp']);
      // Picking one is the same as typing it.
      org.onChanged('Acme Corp');
      await tester.pumpAndSettle();
      // Kitchenly's bundle ID and package name are rows like any other.
      expect(
        popup(
          tester,
          find.byKey(const ValueKey('app-identifier-kind-1')),
        ).value,
        'package_name',
      );
      await settleWrite(
        tester,
        find.text('Save'),
        () => appNamed(tester, 'Kitchenly').organization == 'Acme Corp',
      );
      final kitchenly = appNamed(tester, 'Kitchenly');
      expect(kitchenly.bundleIds, ['com.kitchenly.app']);
      expect(kitchenly.packageNames, ['com.kitchenly.android']);
    });

    testWidgets('renaming an app renames it in the tree', (tester) async {
      await open(tester);
      await tester.tap(inSidebar('Ledgerly'));
      await tester.pumpAndSettle();
      expect(inList('No identifiers'), findsOneWidget);
      await tester.tap(find.text('Edit app…'));
      await tester.pumpAndSettle();
      expect(find.text('Edit app'), findsWidgets);

      await tester.enterText(
        editable(find.byKey(const ValueKey('app-name'))),
        'Ledgerly Cloud',
      );
      await settleWrite(
        tester,
        find.text('Save'),
        () => index(tester).apps.values.any((a) => a.name == 'Ledgerly Cloud'),
      );
      expect(inSidebar('Ledgerly Cloud'), findsOneWidget);
      expect(inSidebar('Ledgerly'), findsNothing);
    });

    testWidgets('deleting an app keeps its items under No app', (tester) async {
      await open(tester);
      await tester.tap(inSidebar('Ledgerly'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('App actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete app…'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('its item stays in the vault under “No app”'),
        findsOneWidget,
      );
      await settleWrite(
        tester,
        find.text('Delete app'),
        () => !index(tester).apps.values.any((a) => a.name == 'Ledgerly'),
      );

      expect(router(tester).state.uri.toString(), Routes.vault());
      expect(inSidebar('Ledgerly'), findsNothing);
      expect(
        index(tester).all.map((i) => i.title),
        contains('Stripe secret key'),
      );
      final noApp = index(tester).tree.firstWhere((n) => n.app == null);
      expect(noApp.count, 2);
      expect(
        const VaultFilter(app: VaultFilter.none)
            .apply(index(tester))
            .map((i) => i.title),
        ['GitHub deploy key', 'Stripe secret key'],
      );
      await tester.pumpAndSettle(const Duration(seconds: 10));
    });

    testWidgets('the item editor names an app with its organization', (
      tester,
    ) async {
      await open(tester);
      await saveApp(
        tester,
        appNamed(tester, 'Ledgerly').copyWith(organization: 'Acme Corp'),
      );
      await tester.tap(find.bySemanticsLabel('New item'));
      await tester.pumpAndSettle();
      final apps = tester
          .widgetList<DesktopPopup<String>>(find.byType(DesktopPopup<String>))
          .firstWhere((p) => p.choices.any((c) => c.label == 'No app'));
      expect(apps.choices.map((c) => c.label), [
        'No app',
        'Acme Corp › Ledgerly',
        'Kitchenly',
      ]);
    });
  });

  group('phone form', () {
    Future<void> open(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(390 * 3, 2400 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpUnlockedApp(
        tester,
        location: Routes.vault(),
        vault: TestVault.sample,
        layout: AppLayout.mobile,
      );
    }

    testWidgets('adds an app: organization from the suggestions, kind and '
        'identifiers', (tester) async {
      await open(tester);
      await saveApp(
        tester,
        appNamed(tester, 'Ledgerly').copyWith(organization: 'Acme Corp'),
      );
      String? saved;
      showAppEditor(tester.element(find.byType(MobileVaultScreen)))
          .then((id) => saved = id);
      await tester.pumpAndSettle();
      expect(find.text('New app'), findsOneWidget);
      expect(
        find.textContaining('An app, site, service or tool'),
        findsOneWidget,
      );

      await tester.enterText(
        editable(find.byKey(const ValueKey('app-name'))),
        'Billing API',
      );
      // The vault's organizations are offered under the field.
      await tester.enterText(
        editable(find.byKey(const ValueKey('app-organization'))),
        'ac',
      );
      await tester.pump();
      Finder suggestion(String org) => find.descendant(
        of: find.byType(AppEditor),
        matching: find.widgetWithText(BCChip, org),
      );
      await tester.tap(suggestion('Acme Corp'));
      await tester.pumpAndSettle();
      expect(suggestion('Acme Corp'), findsNothing);

      final kind = tester.widget<BCSelect<String>>(
        find.byKey(const ValueKey('app-kind')),
      );
      expect(kind.value, '');
      expect(kind.items.first.label, 'Not set');
      kind.onValueChange!('web');
      await tester.pumpAndSettle();

      final add = find.text('Add identifier');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      final idKind = tester.widget<BCSelect<String>>(
        find.byKey(const ValueKey('app-identifier-kind-0')),
      );
      expect(idKind.value, isNull);
      idKind.onValueChange!('repository');
      await tester.pumpAndSettle();
      await tester.enterText(
        editable(find.byKey(const ValueKey('app-identifier-0'))),
        'github.com/acme/billing',
      );

      final save = find.text('Add app');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await settleWrite(tester, save, () => saved != null);

      final billing = appNamed(tester, 'Billing API');
      expect(billing.id, saved);
      expect(billing.organization, 'Acme Corp');
      expect(billing.kind, AppKind.web);
      expect(billing.identifiers, [
        AppIdentifier.of(IdentifierKind.repository, 'github.com/acme/billing'),
      ]);
    });
  });
}
