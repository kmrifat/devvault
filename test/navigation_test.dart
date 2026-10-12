import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/mobile_shell.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/features/expiry/expiry_screen.dart';
import 'package:devvault/features/pairing/pair_screen.dart';
import 'package:devvault/features/vault/mobile_vault_screen.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:devvault/shared/widgets/native_phone_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  void setView(WidgetTester tester, AppLayout layout) {
    tester.view
      ..physicalSize = layout == AppLayout.desktop
          ? const Size(1440, 900)
          : const Size(390 * 3, 844 * 3)
      ..devicePixelRatio = layout == AppLayout.desktop ? 1 : 3;
    addTearDown(tester.view.reset);
  }

  /// Opens [location] with an unlocked vault.
  Future<void> open(
    WidgetTester tester,
    AppLayout layout,
    String location,
  ) async {
    setView(tester, layout);
    await pumpUnlockedApp(tester, location: location, layout: layout);
  }

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri
          .toString();

  /// Every page on every navigator (root and shell branches) is a
  /// [MaterialPage], so each screen gets the platform's push transition and
  /// back gesture.
  void expectOnlyMaterialPages(WidgetTester tester) {
    final pages = [
      for (final navigator in tester.widgetList<Navigator>(
        find.byType(Navigator),
      ))
        ...navigator.pages,
    ];
    expect(pages, isNotEmpty);
    for (final page in pages) {
      expect(page, isA<MaterialPage<void>>(), reason: '${page.name}');
    }
  }

  for (final layout in AppLayout.values) {
    group('${layout.name} layout: every route is a MaterialPage', () {
      for (final path in [
        Routes.vault(),
        Routes.item('abc'),
        Routes.expiry,
        Routes.settings,
        Routes.settingsSync,
        Routes.settingsSecurity,
        if (layout == AppLayout.desktop) Routes.settingsAgents,
        if (layout == AppLayout.mobile) Routes.search(q: 'apns'),
        Routes.pair,
      ]) {
        testWidgets(path, (tester) async {
          await open(tester, layout, path);
          expectOnlyMaterialPages(tester);
        });
      }

      // The lock screens, reached the way the session sends people there.
      for (final (vault, path) in [
        (null, Routes.create),
        (null, Routes.joinVault),
        (TestVault.locked, Routes.unlock),
        (TestVault.locked, Routes.recover),
      ]) {
        testWidgets(path, (tester) async {
          setView(tester, layout);
          final dir = await tester.runAsync(
            () => vault == null ? testSupportDir() : testSupportDir(vault),
          );
          await tester.pumpWidget(
            testApp(location: path, supportDir: dir!, layout: layout),
          );
          await tester.pumpAndSettle();
          expect(location(tester), path);
          expectOnlyMaterialPages(tester);
        });
      }
    });

    group('${layout.name} layout', () {
      testWidgets('/pair opens the pairing screen in a MaterialPage', (
        tester,
      ) async {
        await open(tester, layout, Routes.pair);
        final screen = find.byType(PairScreen);
        expect(screen, findsOneWidget);
        expect(
          ModalRoute.of(tester.element(screen))!.settings,
          isA<MaterialPage<void>>(),
        );
      });

      testWidgets('/expiry opens the expiry dashboard in a MaterialPage', (
        tester,
      ) async {
        await open(tester, layout, Routes.expiry);
        final screen = find.byType(ExpiryScreen);
        expect(screen, findsOneWidget);
        expect(
          ModalRoute.of(tester.element(screen))!.settings,
          isA<MaterialPage<void>>(),
        );
      });

      testWidgets('unknown paths show the not-found screen', (tester) async {
        await open(tester, layout, '/nope');
        expect(find.text('Page not found'), findsOneWidget);
        await tester.tap(find.text('Go to vault'));
        await tester.pumpAndSettle();
        expect(location(tester), Routes.vaultRoot);
      });
    });
  }

  group('desktop', () {
    testWidgets('shows the sidebar and the list + detail panes', (
      tester,
    ) async {
      await open(tester, AppLayout.desktop, Routes.vault());
      expect(find.byType(VaultSidebar), findsOneWidget);
      expect(find.byType(BCBottomNav), findsNothing);
      expect(find.byType(VaultListPane), findsOneWidget);
      expect(find.text('Your vault is empty'), findsOneWidget);
      expect(find.text('No item selected'), findsOneWidget);
    });

    testWidgets('an item link selects it in the detail pane', (tester) async {
      await open(tester, AppLayout.desktop, Routes.item('abc'));
      expect(location(tester), Routes.vault(item: 'abc'));
      expect(find.text('This item isn’t in the vault'), findsOneWidget);
      expect(find.byType(VaultSidebar), findsOneWidget);
    });

    testWidgets('sidebar switches branches', (tester) async {
      await open(tester, AppLayout.desktop, Routes.vault());
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(location(tester), Routes.settings);
      await tester.tap(find.text('Expiring in 30 days'));
      await tester.pumpAndSettle();
      expect(location(tester), Routes.expiry);
      await tester.tap(find.text('Expired'));
      await tester.pumpAndSettle();
      expect(location(tester), Routes.expiryShowing(expired: true));
      await tester.tap(find.text('All items'));
      await tester.pumpAndSettle();
      expect(location(tester), Routes.vault());
    });
  });

  group('mobile', () {
    testWidgets('shows the bottom nav, not the sidebar', (tester) async {
      await open(tester, AppLayout.mobile, Routes.vault());
      expect(find.byType(BCBottomNav), findsOneWidget);
      expect(find.byType(VaultSidebar), findsNothing);
      expect(find.byType(MobileVaultScreen), findsOneWidget);
      expect(find.text('Your vault is empty'), findsOneWidget);
    });

    testWidgets('on iPhone the tab bar is UIKit\'s own', (tester) async {
      setView(tester, AppLayout.mobile);
      await pumpUnlockedApp(
        tester,
        location: Routes.vault(),
        layout: AppLayout.mobile,
        overrides: [nativeBarsProvider.overrideWithValue(true)],
      );
      expect(find.byType(LiquidGlassTabBar), findsOneWidget);
      expect(find.byType(BCBottomNav), findsNothing);
      final bar = tester.widget<LiquidGlassTabBar>(
        find.byType(LiquidGlassTabBar),
      );
      expect(
        [for (final item in bar.items) item.label],
        ['Vault', 'Expiry', 'Settings'],
      );
      expect(
        [for (final item in bar.items) item.icon.sfSymbolName],
        ['square.stack.3d.up', 'clock', 'gearshape'],
      );
      expect(bar.currentIndex, 0);
      // Search is its own button beside the tabs.
      expect(bar.iosActionButton?.label, 'Search');
      expect(bar.iosActionButton?.icon.sfSymbolName, 'magnifyingglass');

      // On Search the bar gives way to the search field and a button back
      // to the last tab.
      bar.onActionButtonPressed!();
      await tester.pumpAndSettle();
      expect(
        GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path,
        Routes.searchRoot,
      );
      expect(find.byType(LiquidGlassTabBar), findsNothing);
      expect(find.byType(SearchDock), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);

      await tester.enterText(find.byType(TextField), 'apns');
      await tester.pumpAndSettle();
      expect(
        GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri
            .toString(),
        Routes.search(q: 'apns'),
      );

      // Back to the last tab.
      await tester.tap(find.bySemanticsLabel('Vault'));
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlassTabBar), findsOneWidget);
      expect(
        GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path,
        Routes.vaultRoot,
      );
    });

    testWidgets('on iPhone each screen\'s header is UIKit\'s', (tester) async {
      setView(tester, AppLayout.mobile);
      await pumpUnlockedApp(
        tester,
        location: Routes.vault(),
        layout: AppLayout.mobile,
        overrides: [nativeBarsProvider.overrideWithValue(true)],
      );
      NativePhoneHeader header() =>
          tester.widget<NativePhoneHeader>(find.byType(NativePhoneHeader));

      // At the top the title is large, in the page; the bar takes it once
      // it has scrolled under.
      expect(header().title, '');
      expect(find.byType(PhoneLargeTitle), findsOneWidget);
      await tester.drag(
        find.byType(CustomScrollView).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(header().title, 'Vault');
      expect(
        [for (final a in header().actions) a.symbol],
        ['square.and.arrow.down', 'plus'],
      );
      expect(find.byType(BCSliverAppHeader), findsNothing);

      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      router.go(Routes.expiry);
      await tester.pumpAndSettle();
      expect(header().title, '');
      expect(find.byType(PhoneLargeTitle), findsOneWidget);
      // The title is the header's, not a heading in the page too.
      expect(
        find.byWidgetPredicate((w) => w is BCText && w.data == 'Expiry'),
        findsNothing,
      );

      router.go(Routes.settings);
      await tester.pumpAndSettle();
      expect(header().title, '');
      expect([for (final a in header().actions) a.label], ['Lock']);
      expect(header().onBack, isNull);
    });

    testWidgets('an item is pushed as its own screen', (tester) async {
      await open(tester, AppLayout.mobile, Routes.vault());
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .push(Routes.item('abc'));
      await tester.pumpAndSettle();
      // A missing item still opens its screen, which says so.
      final title = find.text('This item isn’t in the vault');
      expect(title, findsOneWidget);
      expect(
        ModalRoute.of(tester.element(title))!.settings,
        isA<MaterialPage<void>>(),
      );
    });

    testWidgets('bottom nav switches branches', (tester) async {
      await open(tester, AppLayout.mobile, Routes.vault());
      await tester.tap(find.text('Expiry').last);
      await tester.pumpAndSettle();
      expect(location(tester), Routes.expiry);
    });
  });

  test('vault links carry only the filters that are set', () {
    expect(Routes.vault(), '/vault');
    expect(
      Routes.vault(app: 'k1', env: 'production', item: 'i9'),
      '/vault?item=i9&app=k1&env=production',
    );
    expect(Routes.vault(q: 'AuthKey 7X'), '/vault?q=AuthKey+7X');
  });

  test('desktop OSes get the three-pane layout, phones the mobile one', () {
    expect(AppLayout.forPlatform(TargetPlatform.macOS), AppLayout.desktop);
    expect(AppLayout.forPlatform(TargetPlatform.windows), AppLayout.desktop);
    expect(AppLayout.forPlatform(TargetPlatform.linux), AppLayout.desktop);
    expect(AppLayout.forPlatform(TargetPlatform.iOS), AppLayout.mobile);
    expect(AppLayout.forPlatform(TargetPlatform.android), AppLayout.mobile);
  });
}
