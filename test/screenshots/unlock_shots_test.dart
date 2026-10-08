@Tags(['golden'])
library;

import 'package:devvault/app/routes.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/services/biometric_key_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_overrides.dart';
import 'harness.dart';

void main() {
  setUpAll(loadAppFonts);

  shot('D00-unlock', Routes.unlock, vault: TestVault.locked, realKdf: true);
  shot(
    'D00-unlock-light',
    Routes.unlock,
    vault: TestVault.locked,
    realKdf: true,
    brightness: Brightness.light,
  );
  shot(
    'B1-unlock',
    Routes.unlock,
    device: ShotDevice.mobile,
    vault: TestVault.locked,
    realKdf: true,
  );
  shot(
    'B1-unlock-face-id',
    Routes.unlock,
    device: ShotDevice.mobile,
    vault: TestVault.locked,
    realKdf: true,
    overrides: [biometricKeyStoreProvider.overrideWithValue(_Dismissed())],
    // After a dismissed prompt the password field takes focus; when that
    // happens depends on timing, so focus it here, the same every time.
    interact: (tester) => tester.tap(find.byType(EditableText)),
  );
  shot('D00-recover', Routes.recover, vault: TestVault.locked);
}

/// Face ID is on and the user dismissed the automatic prompt: the screen
/// as it stays.
class _Dismissed extends MemoryBiometricKeyStore {
  @override
  Future<bool> has(String vaultId) async => true;

  @override
  Future<Uint8List?> read(String vaultId, {required String reason}) async =>
      null;
}
