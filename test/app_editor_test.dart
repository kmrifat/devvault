import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_filter.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/app_editor/app_draft.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
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
        ..bundleIds = 'com.ok.app, not a bundle'
        ..packageNames = 'com.ok.android\n1bad.name';
      expect(draft.validate([kitchenly]), {
        'name': 'Another app has this name',
        'bundleIds': 'Not a bundle ID: not',
        'packageNames': 'Not a package name: 1bad.name',
      });

      draft
        ..name = 'Ledgerly'
        ..bundleIds = 'com.ledgerly.app,  com.ledgerly.app\ncom.ledgerly.widget'
        ..packageNames = '';
      expect(draft.validate([kitchenly]), isEmpty);
      expect(draft.bundleIdList, ['com.ledgerly.app', 'com.ledgerly.widget']);
    });

    test('renaming keeps the identity; an app may keep its own name', () {
      final draft = AppDraft.edit(kitchenly)..name = 'Kitchenly';
      expect(draft.validate([kitchenly]), isEmpty);
      draft
        ..name = 'Kitchenly Pro'
        ..packageNames = 'com.kitchenly.android';
      final app = draft.toApp((_) => throw StateError('not new'));
      expect(app.id, kitchenly.id);
      expect(app.createdAt, kitchenly.createdAt);
      expect(app.name, 'Kitchenly Pro');
      expect(app.packageNames, ['com.kitchenly.android']);
    });
  });

  group('screens', () {
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

    VaultIndex index(WidgetTester tester) =>
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

    GoRouter router(WidgetTester tester) =>
        GoRouter.of(tester.element(find.byType(VaultListPane)));

    Finder inSidebar(String text) => find.descendant(
      of: find.byType(VaultSidebar),
      matching: find.text(text),
    );

    Finder input(int i) => find.descendant(
      of: find.byKey(
        ValueKey(['app-name', 'app-bundle-ids', 'app-package-names'][i]),
      ),
      matching: find.byType(EditableText),
    );

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

    testWidgets('+ in the sidebar adds an app and opens it', (tester) async {
      await open(tester);
      await tester.tap(find.bySemanticsLabel('New app'));
      await tester.pumpAndSettle();
      expect(find.text('New app'), findsOneWidget);

      await tester.enterText(input(0), 'Ledgerly');
      await tester.tap(find.text('Add app'));
      await tester.pumpAndSettle();
      expect(find.text('Another app has this name'), findsOneWidget);

      await tester.enterText(input(0), 'Pantry');
      await tester.enterText(input(1), 'com.pantry.app');
      await settleWrite(
        tester,
        find.text('Add app'),
        () => index(tester).apps.values.any((a) => a.name == 'Pantry'),
      );

      final pantry = index(tester).apps.values
          .firstWhere((a) => a.name == 'Pantry');
      expect(pantry.bundleIds, ['com.pantry.app']);
      expect(router(tester).state.uri.toString(), Routes.vault(app: pantry.id));
      // An app with no items isn't in the tree yet, but its page opens.
      expect(
        find.descendant(
          of: find.byType(VaultListPane),
          matching: find.text('com.pantry.app'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renaming an app renames it in the tree', (tester) async {
      await open(tester);
      await tester.tap(inSidebar('Ledgerly'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit app…'));
      await tester.pumpAndSettle();
      expect(find.text('Edit app'), findsWidgets);

      await tester.enterText(input(0), 'Ledgerly Cloud');
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
  });
}
