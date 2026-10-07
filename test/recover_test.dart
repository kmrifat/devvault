import 'dart:io';

import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_core/vault_core.dart';

import 'test_overrides.dart';

void main() {
  setUpAll(loadTestCrypto);

  late Directory dir;
  late String recoveryKey;

  Future<void> openRecover(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dir = (await tester.runAsync(() => testSupportDir(TestVault.locked)))!;
    recoveryKey = lastTestRecoveryKey!;
    await tester.pumpWidget(testApp(location: Routes.recover, supportDir: dir));
    await tester.pumpAndSettle();
  }

  /// Presses [button], then alternates real time and frames until [until]
  /// shows up. The work behind the button does real file I/O and runs
  /// Argon2id on an isolate.
  Future<void> press(
    WidgetTester tester,
    String button, {
    required Finder until,
  }) async {
    // Rebuild first: typing only marks the field dirty, and the button is
    // enabled by the next frame. Tapping inside runAsync runs the handler
    // in the real zone, so its file I/O completes on its own.
    await tester.pump();
    await tester.runAsync(() => tester.tap(find.text(button)));
    for (var i = 0; i < 200 && until.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  String location(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri
          .toString();

  testWidgets('points at a typo before trying the key', (tester) async {
    await openRecover(tester);
    final typo = recoveryKey.replaceRange(
      0,
      1,
      recoveryKey[0] == 'A' ? 'B' : 'A',
    );
    await tester.enterText(find.byType(EditableText), typo);
    final typoError = find.text(
      'This recovery key has a typo. Check each group.',
    );
    await press(tester, 'Continue', until: typoError);
    expect(typoError, findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'K7QF-2M9X');
    final lengthError = find.text(
      'A recovery key has 14 groups of 4 characters',
    );
    await press(tester, 'Continue', until: lengthError);
    expect(lengthError, findsOneWidget);
    expect(appContainer(tester).read(vaultSessionProvider), isA<Locked>());
  });

  testWidgets("refuses another vault's key", (tester) async {
    await openRecover(tester);
    final other = RecoveryKey.generate(testCrypto);
    await tester.enterText(find.byType(EditableText), other.toDisplayString());
    other.dispose();
    final wrongVault = find.text(
      "This recovery key doesn't belong to this vault",
    );
    await press(tester, 'Continue', until: wrongVault);
    expect(wrongVault, findsOneWidget);
  });

  testWidgets('recovery key, new password, vault open', (tester) async {
    await openRecover(tester);
    // Typed sloppily: lower case, spaces instead of dashes.
    await tester.enterText(
      find.byType(EditableText),
      recoveryKey.toLowerCase().replaceAll('-', ' '),
    );
    final stepTwo = find.text('Choose a new master password');
    await press(tester, 'Continue', until: stepTwo);
    expect(stepTwo, findsOneWidget);
    expect(location(tester), Routes.recover, reason: 'held until reset');

    final fields = find.byType(EditableText);
    await tester.enterText(fields.at(0), 'a brand new password');
    await tester.enterText(fields.at(1), 'a brand new password');
    await press(
      tester,
      'Set password and open vault',
      until: find.text('New master password set'),
    );
    expect(location(tester), Routes.vault());

    // The old password is gone, the new one works.
    final store = VaultStore(
      Directory('${dir.path}/vaults').listSync().first as Directory,
    );
    await tester.runAsync(() async {
      await expectLater(
        VaultKeys.unlockWithPassword(
          testCrypto,
          await store.readHeader(),
          testPassword,
        ),
        throwsA(isA<WrongPassword>()),
      );
      (await VaultKeys.unlockWithPassword(
        testCrypto,
        await store.readHeader(),
        'a brand new password',
      )).dispose();
    });
  });
}
