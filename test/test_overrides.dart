import 'dart:io';

import 'package:devvault/app/app.dart';
import 'package:devvault/app/layout.dart';
import 'package:devvault/data/providers.dart';
import 'package:devvault/data/vault_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_core/vault_core.dart';

import 'sample_vault.dart';

/// The fixed "now" every test sees: the day the project started.
final testNow = DateTime.utc(2026, 10, 7, 9);

const testDeviceId = '00000000-0000-4000-8000-000000000001';
const testPassword = 'correct horse battery staple';

/// libsodium for tests; load it once per file with `setUpAll(loadTestCrypto)`.
VaultCrypto? _crypto;
VaultCrypto get testCrypto =>
    _crypto ?? (throw StateError('Call setUpAll(loadTestCrypto) first'));
Future<void> loadTestCrypto() async => _crypto ??= await VaultCrypto.init();

/// The recovery key of the vault the last [testSupportDir] call created.
String? lastTestRecoveryKey;

/// What the device holds when a test starts.
enum TestVault {
  /// First launch: no vault yet.
  none,

  /// A vault exists, locked, with password [testPassword].
  locked,

  /// Like [locked], filled with the design frames' credentials
  /// ([seedSampleVault]).
  sample,
}

/// A throwaway app support folder, optionally with a vault in it.
///
/// Pass a seeded [crypto] for reproducible ids and keys (screenshots).
Future<Directory> testSupportDir([
  TestVault vault = TestVault.none,
  VaultCrypto? crypto,
  bool realKdf = false,
]) async {
  final dir = Directory.systemTemp.createTempSync('devvault_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  if (vault != TestVault.none) {
    final c = crypto ?? testCrypto;
    final id = VaultKeys.uuidV4(c);
    final (created, recoveryKey) = await Vault.create(
      crypto: c,
      store: VaultStore(Directory('${dir.path}/vaults/$id')),
      password: testPassword,
      deviceId: testDeviceId,
      now: () => testNow,
      vaultId: id,
      opsLimit: realKdf ? KdfParams.defaultOpsLimit : KdfParams.minOpsLimit,
      memLimit: realKdf ? KdfParams.defaultMemLimit : KdfParams.minMemLimit,
    );
    if (vault == TestVault.sample) await seedSampleVault(created, testNow);
    created.lock();
    lastTestRecoveryKey = recoveryKey.toDisplayString();
    recoveryKey.dispose();
  }
  return dir;
}

/// Provider overrides shared by every app-level test: a fixed clock (or
/// [clock], for tests that move time) and device id, the given support
/// folder, libsodium ([crypto] or the shared test instance) and, unless
/// [realKdf], the cheapest Argon2id the format allows.
List<Override> testOverrides({
  required Directory supportDir,
  bool realKdf = false,
  VaultCrypto? crypto,
  DateTime Function()? clock,
}) => [
  clockProvider.overrideWithValue(clock ?? () => testNow),
  deviceIdProvider.overrideWithValue(testDeviceId),
  appSupportDirProvider.overrideWithValue(supportDir),
  cryptoProvider.overrideWithValue(crypto ?? testCrypto),
  if (!realKdf) ...[
    kdfOpsLimitProvider.overrideWithValue(KdfParams.minOpsLimit),
    kdfMemLimitProvider.overrideWithValue(KdfParams.minMemLimit),
  ],
];

/// The whole app, wired the way main() wires it but with [testOverrides].
Widget testApp({
  required String location,
  required Directory supportDir,
  AppLayout? layout,
  List<Override> overrides = const [],
  bool realKdf = false,
  VaultCrypto? crypto,
  DateTime Function()? clock,
}) => ProviderScope(
  overrides: [
    ...testOverrides(
      supportDir: supportDir,
      realKdf: realKdf,
      crypto: crypto,
      clock: clock,
    ),
    ...overrides,
  ],
  child: DevVaultApp(initialLocation: location, layout: layout),
);

/// The provider container behind the running app.
ProviderContainer appContainer(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(DevVaultApp)));

/// Opens the app at [location] with an unlocked vault: the app starts
/// locked, bounces to unlock, and the test unlocks it the way the unlock
/// screen would. The vault is empty unless [vault] is [TestVault.sample].
Future<void> pumpUnlockedApp(
  WidgetTester tester, {
  required String location,
  TestVault vault = TestVault.locked,
  AppLayout? layout,
  List<Override> overrides = const [],
  VaultCrypto? crypto,
  DateTime Function()? clock,
  Future<void> Function()? settle,
}) async {
  final dir = await tester.runAsync(() => testSupportDir(vault, crypto));
  await tester.pumpWidget(
    testApp(
      location: location,
      supportDir: dir!,
      layout: layout,
      overrides: overrides,
      crypto: crypto,
      clock: clock,
    ),
  );
  await tester.pump();
  await tester.runAsync(
    () =>
        appContainer(tester)
            .read(vaultSessionProvider.notifier)
            .unlock(testPassword),
  );
  await (settle?.call() ?? tester.pumpAndSettle());
}
