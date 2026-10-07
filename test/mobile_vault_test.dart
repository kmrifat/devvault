import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/vault/mobile_vault_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  Future<void> open(WidgetTester tester, [String? location]) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 2400 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: location ?? Routes.vault(),
      vault: TestVault.sample,
      layout: AppLayout.mobile,
    );
  }

  GoRouter router(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(MobileVaultScreen)));

  String location(WidgetTester tester) => router(tester).state.uri.toString();

  VaultIndex index(WidgetTester tester) =>
      (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

  Finder inList(String text) => find.descendant(
    of: find.byType(MobileVaultScreen),
    matching: find.text(text),
  );

  testWidgets('groups items by app, then items without one', (tester) async {
    await open(tester);
    final kitchenly = tester.getTopLeft(inList('Kitchenly').last).dy;
    final ledgerly = tester.getTopLeft(inList('Ledgerly').last).dy;
    final noApp = tester.getTopLeft(inList('No app')).dy;
    expect(kitchenly, lessThan(ledgerly));
    expect(ledgerly, lessThan(noApp));
    expect(inList('Stripe secret key'), findsOneWidget);
    expect(inList('GitHub deploy key'), findsOneWidget);
    expect(inList('12 days'), findsOneWidget);
  });

  testWidgets('app chips and tabs filter, and are part of the link', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(inList('Ledgerly').first);
    await tester.pumpAndSettle();
    final ledgerly = index(tester).apps.values
        .firstWhere((a) => a.name == 'Ledgerly');
    expect(location(tester), Routes.vault(app: ledgerly.id));
    expect(inList('Stripe secret key'), findsOneWidget);
    expect(inList('Upload keystore'), findsNothing);

    await tester.tap(inList('All apps'));
    await tester.pumpAndSettle();
    await tester.tap(inList('Expiring'));
    await tester.pumpAndSettle();
    expect(location(tester), Routes.vault(kind: 'expiring'));
    expect(inList('Play publisher'), findsOneWidget);
    expect(inList('Maps API key'), findsNothing);
  });

  testWidgets('search narrows the list', (tester) async {
    await open(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(MobileVaultScreen),
        matching: find.byType(EditableText),
      ),
      'apns',
    );
    await tester.pumpAndSettle();
    expect(location(tester), Routes.vault(q: 'apns'));
    expect(inList('APNs auth key'), findsOneWidget);
    expect(inList('Upload keystore'), findsNothing);
  });

  testWidgets('tapping an item pushes its screen', (tester) async {
    await open(tester);
    final apns = index(tester).all
        .firstWhere((i) => i.title == 'APNs auth key');
    await tester.tap(inList('APNs auth key'));
    await tester.pumpAndSettle();
    expect(
      GoRouter.of(tester.element(find.byType(Scaffold).last)).state.uri
          .toString(),
      Routes.item(apns.id),
    );
  });
}
