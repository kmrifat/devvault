import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/features/unlock/unlock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  Future<void> openLocked(WidgetTester tester, {String? at}) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = await tester.runAsync(() => testSupportDir(TestVault.locked));
    await tester.pumpWidget(
      testApp(location: at ?? Routes.unlock, supportDir: dir!),
    );
    await tester.pumpAndSettle();
  }

  /// Types [password] and presses Unlock, giving Argon2id real time.
  Future<void> tryPassword(WidgetTester tester, String password) async {
    await tester.enterText(find.byType(EditableText), password);
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Unlock'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pumpAndSettle();
  }

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri
          .toString();

  testWidgets('shows only what vault.json says', (tester) async {
    await openLocked(tester);
    expect(find.text('Unlock your vault'), findsOneWidget);
    expect(find.textContaining('Argon2id · 8 MiB · 1 pass'), findsOneWidget);
    expect(find.textContaining('vault '), findsOneWidget);
  });

  testWidgets('a wrong password says so and clears the field', (tester) async {
    await openLocked(tester);
    await tryPassword(tester, 'not the password');
    expect(find.text("That password didn't open this vault"), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
    expect(appContainer(tester).read(vaultSessionProvider), isA<Locked>());
  });

  testWidgets('the right password opens the vault where you were going', (
    tester,
  ) async {
    await openLocked(tester, at: Routes.expiry);
    expect(location(tester), '/unlock?from=%2Fexpiry');
    await tryPassword(tester, testPassword);
    expect(appContainer(tester).read(vaultSessionProvider), isA<Unlocked>());
    expect(location(tester), Routes.expiry);
  });

  testWidgets('links to recovery', (tester) async {
    await openLocked(tester);
    await tester.tap(find.text('Use your recovery key'));
    await tester.pumpAndSettle();
    expect(location(tester), Routes.recover);
  });

  test('waits longer after repeated wrong passwords', () {
    expect(UnlockScreen.backoff(4), Duration.zero);
    expect(UnlockScreen.backoff(5), const Duration(seconds: 30));
    expect(UnlockScreen.backoff(6), const Duration(seconds: 60));
    expect(UnlockScreen.backoff(8), const Duration(seconds: 240));
    expect(UnlockScreen.backoff(20), const Duration(minutes: 5));
  });
}
