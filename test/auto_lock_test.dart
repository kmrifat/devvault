import 'dart:ui' show AppExitResponse;

import 'package:devvault/app/auto_lock.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/app/routes.dart';
import 'package:devvault/data/app_settings.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:devvault/services/clipboard_guard.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'clipboard_guard_test.dart' show FakeClipboard;
import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  late DateTime now;
  late FakeClipboard clipboard;

  Future<void> open(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    now = testNow;
    clipboard = FakeClipboard();
    await pumpUnlockedApp(
      tester,
      location: Routes.vault(),
      vault: TestVault.sample,
      layout: AppLayout.desktop,
      clock: () => now,
      overrides: [
        clipboardGuardProvider.overrideWithValue(
          ClipboardGuard(clipboard: clipboard),
        ),
      ],
    );
  }

  VaultSession session(WidgetTester tester) =>
      appContainer(tester).read(vaultSessionProvider);

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri
          .toString();

  /// Moves the wall clock on by [by] and lets one idle check run.
  Future<void> idle(WidgetTester tester, Duration by) async {
    now = now.add(by);
    await tester.pump(AutoLock.checkEvery);
    await tester.pumpAndSettle();
  }

  testWidgets('locks after 5 minutes without input, everything gone', (
    tester,
  ) async {
    await open(tester);
    final unlocked = session(tester) as Unlocked;
    await appContainer(tester)
        .read(clipboardGuardProvider)
        .copySecret('kitchenly-store-pass');

    await idle(tester, const Duration(minutes: 4, seconds: 50));
    expect(session(tester), isA<Unlocked>());

    await idle(tester, const Duration(seconds: 10));
    final locked = session(tester);
    expect(locked, isA<Locked>());
    // AC: nothing decrypted is reachable once locked. The session holds
    // only the store and the plaintext vault.json; the key is wiped and
    // the old Vault refuses to read.
    expect(unlocked.vault.isLocked, isTrue);
    final firstId = unlocked.index.all.first.id;
    await tester.runAsync(
      () => expectLater(unlocked.vault.readItem(firstId), throwsStateError),
    );
    expect(clipboard.text, isEmpty);
    expect(location(tester), startsWith(Routes.unlock));
    expect(find.text('Unlock your vault'), findsOneWidget);
  });

  testWidgets('pointer and key input keep it open', (tester) async {
    await open(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 400));
    addTearDown(mouse.removePointer);

    for (var i = 0; i < 3; i++) {
      await idle(tester, const Duration(minutes: 4));
      await mouse.moveBy(const Offset(5, 0));
    }
    expect(session(tester), isA<Unlocked>());

    await idle(tester, const Duration(minutes: 4));
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await idle(tester, const Duration(minutes: 4));
    expect(session(tester), isA<Unlocked>());

    await idle(tester, const Duration(minutes: 2));
    expect(session(tester), isA<Locked>());
  });

  testWidgets('waking from sleep past the limit locks at once', (tester) async {
    await open(tester);
    // Asleep: no timers run, but the wall clock moves on.
    now = now.add(const Duration(hours: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(session(tester), isA<Locked>());
  });

  testWidgets('"Never" keeps it open', (tester) async {
    await open(tester);
    appContainer(tester).read(settingsProvider.notifier).setAutoLock(null);
    await idle(tester, const Duration(hours: 8));
    expect(session(tester), isA<Unlocked>());
  });

  testWidgets('a shorter setting applies right away', (tester) async {
    await open(tester);
    appContainer(tester)
        .read(settingsProvider.notifier)
        .setAutoLock(const Duration(minutes: 1));
    await idle(tester, const Duration(minutes: 1));
    expect(session(tester), isA<Locked>());
  });

  for (final modifier in [
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.controlLeft,
  ]) {
    testWidgets('${modifier.keyLabel}+L locks', (tester) async {
      await open(tester);
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(session(tester), isA<Locked>());
      expect(find.text('Unlock your vault'), findsOneWidget);
    });
  }

  testWidgets('quitting clears a copied secret', (tester) async {
    await open(tester);
    await appContainer(tester)
        .read(clipboardGuardProvider)
        .copySecret('kitchenly-store-pass');
    expect(clipboard.text, 'kitchenly-store-pass');
    final response = await tester.binding.handleRequestAppExit();
    expect(response, AppExitResponse.exit);
    expect(clipboard.text, isEmpty);
  });

  testWidgets('a plain L types, it doesn’t lock', (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pumpAndSettle();
    expect(session(tester), isA<Unlocked>());
  });

  test('defaults to 5 minutes', () {
    expect(const AppSettings().autoLockAfter, const Duration(minutes: 5));
  });
}
