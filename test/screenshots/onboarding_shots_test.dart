@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_overrides.dart';
import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<void> typePassword(WidgetTester tester) async {
    await tester.enterText(
      find.byType(EditableText).first,
      'correct horse battery staple',
    );
  }

  shot(
    'N01-create',
    Routes.create,
    vault: TestVault.none,
    interact: typePassword,
    realKdf: true, // show the real Argon2id defaults
  );
  shot(
    'N01-create-light',
    Routes.create,
    vault: TestVault.none,
    brightness: Brightness.light,
    interact: typePassword,
    realKdf: true, // show the real Argon2id defaults
  );
  shot(
    'B-create-vault',
    Routes.create,
    device: ShotDevice.mobile,
    vault: TestVault.none,
    realKdf: true, // show the real Argon2id defaults
  );

  // N02: create a vault the way N01 does, then hold its recovery key.
  Future<void> createVault(WidgetTester tester) async {
    final c = appContainer(tester);
    await tester.runAsync(() async {
      final rk = await c
          .read(vaultSessionProvider.notifier)
          .create('correct horse battery staple');
      c.read(pendingRecoveryKeyProvider.notifier).hold(rk);
    });
  }

  shot(
    'N02-recovery-kit',
    Routes.create,
    vault: TestVault.none,
    interact: createVault,
  );
  // As in the frame: the key is saved and Open Vault is ready.
  shot(
    'N02-recovery-kit-light',
    Routes.create,
    vault: TestVault.none,
    brightness: Brightness.light,
    interact: (tester) async {
      await createVault(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text("I've saved my recovery key somewhere safe"));
    },
  );
  shot(
    'B-recovery-kit',
    Routes.create,
    device: ShotDevice.mobile,
    vault: TestVault.none,
    interact: createVault,
  );
}
