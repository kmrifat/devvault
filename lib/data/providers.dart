import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

// Every service the app depends on, in one place. Values that need I/O are
// loaded in main() before the first frame and handed in with overrides, so
// providers stay synchronous. Tests override the same providers with fakes
// (see test/test_overrides.dart).

/// The current time. Overridden with a fixed clock in tests, so expiry
/// rules and notification plans are deterministic.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The app support folder: vaults, device id and sync state live here.
final appSupportDirProvider = Provider<Directory>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// This device's id, stamped on every record it writes.
final deviceIdProvider = Provider<String>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// libsodium, loaded once in main(). Tests load it too: the native library
/// is compiled for the host by the `sodium` package's build hooks.
final cryptoProvider = Provider<VaultCrypto>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

/// Where vaults live: `<app support>/vaults/<vault_id>/`.
final vaultsDirProvider = Provider<Directory>(
  (ref) => Directory('${ref.watch(appSupportDirProvider).path}/vaults'),
);

/// Argon2id cost for new vaults and password changes (ADR-0003). Tests
/// lower it to keep runs fast.
final kdfOpsLimitProvider = Provider<int>((ref) => KdfParams.defaultOpsLimit);
final kdfMemLimitProvider = Provider<int>((ref) => KdfParams.defaultMemLimit);
