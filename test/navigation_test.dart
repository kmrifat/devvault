import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/features/expiry/expiry_screen.dart';
import 'package:devvault/features/vault/vault_list_pane.dart';
import 'package:devvault/features/vault/vault_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  /// Opens [location] with an unlocked vault.
  Future<void> open(
    WidgetTester tester,
    AppLayout layout,
    String location,
  ) async {
    tester.view
      ..physicalSize = layout == AppLayout.desktop
          ? const Size(1440, 900)
          : const Size(390 * 3, 844 * 3)
      ..devicePixelRatio = layout == AppLayout.desktop ? 1 : 3;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(tester, location: location, layout: layout);
  }

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri
          .toString();

  /// Every route reachable with an open vault, with the title its
  /// placeholder shows. Lock screens are covered by session_routing_test.
  const screens = {Routes.pair: 'Pair a device'};

  for (final layout in AppLayout.values) {
    group('${layout.name} layout', () {
      for (final MapEntry(key: path, value: title) in screens.entries) {
        testWidgets('$path opens "$title" in a MaterialPage', (tester) async {
          await open(tester, layout, path);
          final titleFinder = find.descendant(
            of: find.byType(BCEmptyState),
            matching: find.text(title),
          );
          expect(titleFinder, findsOneWidget);
          final route = ModalRoute.of(tester.element(titleFinder))!;
          expect(route.settings, isA<MaterialPage<void>>());
        });
      }

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
      await tester.tap(find.text('Expiring soon'));
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
      expect(
        find.descendant(
          of: find.byType(BCEmptyState),
          matching: find.text('Vault'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an item is pushed as its own screen', (tester) async {
      await open(tester, AppLayout.mobile, Routes.vault());
      GoRouter.of(tester.element(find.byType(Scaffold).first))
          .push(Routes.item('abc'));
      await tester.pumpAndSettle();
      final title = find.text('Item abc');
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
