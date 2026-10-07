@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
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
    'D01-create-vault',
    Routes.create,
    vault: TestVault.none,
    interact: typePassword,
    realKdf: true, // show the real Argon2id defaults
  );
  shot(
    'D01-create-vault-light',
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
}
