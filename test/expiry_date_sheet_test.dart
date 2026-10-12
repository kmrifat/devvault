import 'package:bc_ui/bc_ui.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/vault/expiry_date_sheet.dart';
import 'package:devvault/features/vault/item_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  VaultIndex index(WidgetTester tester) =>
      (appContainer(tester).read(vaultSessionProvider) as Unlocked).index;

  Item item(WidgetTester tester, String title) =>
      index(tester).all.firstWhere((i) => i.title == title);

  Future<void> openItem(WidgetTester tester, String title) async {
    tester.view
      ..physicalSize = const Size(390 * 3, 1600 * 3)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpUnlockedApp(
      tester,
      location: Routes.vault(),
      vault: TestVault.sample,
      layout: AppLayout.mobile,
    );
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .push(Routes.item(item(tester, title).id));
    await tester.pumpAndSettle();
  }

  /// Saving encrypts for real: lets it run until the sheet has closed.
  Future<void> settleSave(WidgetTester tester) async {
    for (
      var i = 0;
      i < 200 && find.byType(ExpiryDateSheet).evaluate().isNotEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Finder inItem(Finder f) =>
      find.descendant(of: find.byType(ItemScreen), matching: f);

  testWidgets('a date the file didn’t give is set by hand, as the user’s', (
    tester,
  ) async {
    await openItem(tester, 'Maps API key');
    await tester.tap(inItem(find.text('Set date')));
    await tester.pumpAndSettle();
    expect(find.byType(ExpiryDateSheet), findsOneWidget);
    expect(find.byType(BCCalendar), findsOneWidget);

    // A day of the month shown (the calendar opens on today's month).
    await tester.tap(
      find
          .descendant(of: find.byType(BCCalendar), matching: find.text('28'))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Save'));
    await settleSave(tester);

    final saved = item(tester, 'Maps API key');
    expect(saved.expiresSource, ExpirySource.user);
    expect(saved.expiresAt!.day, 28);
    expect(saved.expiresAt!.isUtc, isTrue);
    expect(find.byType(ExpiryDateSheet), findsNothing);
    expect(inItem(find.text('Set by you')), findsOneWidget);
  });

  testWidgets('a date set by hand can be removed', (tester) async {
    await openItem(tester, 'Maps API key');
    await tester.tap(inItem(find.text('Set date')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(of: find.byType(BCCalendar), matching: find.text('28'))
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Save'));
    await settleSave(tester);

    await tester.tap(inItem(find.textContaining('Expires Oct 28')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove date'));
    await settleSave(tester);
    final saved = item(tester, 'Maps API key');
    expect(saved.expiresAt, isNull);
    expect(saved.expiresSource, isNull);
  });

  testWidgets('a date read from the file isn’t edited here', (tester) async {
    await openItem(tester, 'Upload keystore');
    expect(inItem(find.text('Set date')), findsNothing);
    await tester.tap(inItem(find.textContaining('Valid until')));
    await tester.pumpAndSettle();
    expect(find.byType(ExpiryDateSheet), findsNothing);
  });
}
