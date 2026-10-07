import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/expiry/expiry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  group('ExpiryGroups', () {
    var n = 0;
    Item item(String title, DateTime? expiresAt) => Item(
      id: '00000000-0000-4000-8000-${(++n).toString().padLeft(12, '0')}',
      typeName: ItemType.appleCertificate.wireName,
      title: title,
      expiresAt: expiresAt,
      expiresSource: expiresAt == null ? null : ExpirySource.file,
      createdAt: testNow,
      updatedAt: testNow,
      rev: Hlc.zero(testDeviceId),
      deviceId: testDeviceId,
    );
    DateTime days(int d) => testNow.add(Duration(days: d));

    test('sorts items into the four groups, soonest first', () {
      final groups = ExpiryGroups([
        item('later b', days(400)),
        item('soon b', days(29)),
        item('none 1', null),
        item('expired recently', days(-1)),
        item('soon a', days(2)),
        item('expired long ago', days(-90)),
        item('later a', days(31)),
        item('none 2', null),
        item('right now', testNow),
      ], testNow);
      String titles(List<(Item, Object)> g) =>
          g.map((e) => e.$1.title).join(', ');
      expect(
        titles(groups.expired),
        'expired long ago, expired recently, right now',
      );
      expect(titles(groups.soon), 'soon a, soon b');
      expect(titles(groups.later), 'later a, later b');
      expect(groups.noExpiry, 2);
    });
  });

  group('dashboard', () {
    Future<void> open(
      WidgetTester tester, {
      String? location,
      TestVault vault = TestVault.sample,
      AppLayout layout = AppLayout.desktop,
    }) async {
      tester.view
        ..physicalSize = layout == AppLayout.desktop
            ? const Size(1440, 1200)
            : const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpUnlockedApp(
        tester,
        location: location ?? Routes.expiry,
        vault: vault,
        layout: layout,
      );
    }

    VaultIndex index(WidgetTester tester) =>
        (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

    String location(WidgetTester tester) =>
        GoRouter.of(tester.element(find.byType(ExpiryScreen).first)).state.uri
            .toString();

    Finder inScreen(Finder f) =>
        find.descendant(of: find.byType(ExpiryScreen), matching: f);

    Finder row(String title) => inScreen(
      find.byWidgetPredicate(
        (w) =>
            w is Semantics && (w.properties.label ?? '').startsWith('$title,'),
      ),
    );

    testWidgets('groups the sample vault, with each date’s source', (
      tester,
    ) async {
      await open(tester);
      expect(inScreen(find.text('Expired')), findsOneWidget);
      expect(inScreen(find.text('Within 30 days')), findsOneWidget);
      expect(inScreen(find.text('Later')), findsOneWidget);

      // Rows, in date order within each group.
      for (final title in [
        'Distribution certificate',
        'Play publisher',
        'App Store profile',
        'Upload keystore',
      ]) {
        expect(row(title), findsOneWidget, reason: title);
      }
      final soonOrder = [
        tester.getTopLeft(row('Play publisher')).dy,
        tester.getTopLeft(row('App Store profile')).dy,
      ];
      expect(soonOrder.first, lessThan(soonOrder.last));

      expect(inScreen(find.text('in 12 days')), findsOneWidget);
      expect(inScreen(find.text('3 days ago')), findsOneWidget);
      expect(inScreen(find.text('From file')), findsNWidgets(4));

      // No expiry: a count, not a list.
      final none = index(tester).all.where((i) => i.expiresAt == null).length;
      expect(
        inScreen(find.text('$none items have no expiry date')),
        findsOneWidget,
      );
      expect(row('Maps API key'), findsNothing);
    });

    testWidgets('a row opens the item in the vault', (tester) async {
      await open(tester);
      final cert = index(tester).all
          .firstWhere((i) => i.title == 'Distribution certificate');
      await tester.tap(row('Distribution certificate'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpiryScreen), findsNothing);
      expect(
        GoRouter.of(tester.element(find.byType(Scaffold).first))
            .state
            .uri
            .queryParameters['item'],
        cert.id,
      );
    });

    testWidgets('?show=expired narrows to the expired items', (tester) async {
      await open(tester, location: Routes.expiryShowing(expired: true));
      expect(row('Distribution certificate'), findsOneWidget);
      expect(row('Play publisher'), findsNothing);
      expect(inScreen(find.text('Within 30 days')), findsNothing);
      await tester.tap(inScreen(find.text('Show all')));
      await tester.pumpAndSettle();
      expect(location(tester), Routes.expiry);
      expect(row('Play publisher'), findsOneWidget);
    });

    testWidgets('a date the user typed says so', (tester) async {
      await open(tester);
      final profile = index(tester).all
          .firstWhere((i) => i.title == 'App Store profile');
      await tester.runAsync(
        () =>
            appContainer(tester)
                .read(vaultSessionProvider.notifier)
                .saveItem(profile.copyWith(expiresSource: ExpirySource.user)),
      );
      await tester.pumpAndSettle();
      expect(inScreen(find.text('Set by you')), findsOneWidget);
      expect(inScreen(find.text('From file')), findsNWidgets(3));
    });

    testWidgets('an empty vault says what will show up here', (tester) async {
      await open(tester, vault: TestVault.locked);
      expect(inScreen(find.byType(BCEmptyState)), findsOneWidget);
      expect(inScreen(find.text('Nothing to track yet')), findsOneWidget);
    });

    testWidgets('the phone Expiry tab pushes the item screen', (tester) async {
      await open(tester, layout: AppLayout.mobile);
      expect(row('Distribution certificate'), findsOneWidget);
      final cert = index(tester).all
          .firstWhere((i) => i.title == 'Distribution certificate');
      await tester.tap(row('Distribution certificate'));
      await tester.pumpAndSettle();
      expect(
        GoRouter.of(tester.element(find.byType(Scaffold).last)).state.uri
            .toString(),
        Routes.item(cert.id),
      );
    });
  });
}
