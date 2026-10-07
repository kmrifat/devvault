import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import 'providers.dart';

/// Where the app is with its vault. Drives routing: no vault → create,
/// locked → unlock, unlocked → the vault.
sealed class VaultSession {
  const VaultSession();
}

/// No vault on this device yet.
final class NoVault extends VaultSession {
  const NoVault();
}

/// A vault exists and is locked.
final class Locked extends VaultSession {
  const Locked(this.store);

  final VaultStore store;
}

/// The vault is open: [index] is the decrypted contents.
final class Unlocked extends VaultSession {
  const Unlocked(this.vault, this.index);

  final Vault vault;
  final VaultIndex index;
}

/// Finds the vault on this device: the first folder under [vaultsDir] that
/// holds a `vault.json`. One vault per device in v1.
VaultStore? findVault(Directory vaultsDir) {
  if (!vaultsDir.existsSync()) return null;
  final folders = vaultsDir.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final folder in folders) {
    final store = VaultStore(folder);
    if (store.exists) return store;
  }
  return null;
}

/// The vault session: create, unlock, lock and reload.
class VaultSessionNotifier extends Notifier<VaultSession> {
  @override
  VaultSession build() {
    final store = findVault(ref.read(vaultsDirProvider));
    return store == null ? const NoVault() : Locked(store);
  }

  VaultCrypto get _crypto => ref.read(cryptoProvider);
  String get _deviceId => ref.read(deviceIdProvider);
  DateTime Function() get _now => ref.read(clockProvider);

  /// Creates the vault and leaves it unlocked. Returns the recovery key,
  /// which the caller shows once (design frame D02) and then disposes.
  Future<RecoveryKey> create(String password) async {
    final vaultId = VaultKeys.uuidV4(_crypto);
    final store = VaultStore(
      Directory('${ref.read(vaultsDirProvider).path}/$vaultId'),
    );
    final (vault, recoveryKey) = await Vault.create(
      crypto: _crypto,
      store: store,
      password: password,
      deviceId: _deviceId,
      now: _now,
      vaultId: vaultId,
      opsLimit: ref.read(kdfOpsLimitProvider),
      memLimit: ref.read(kdfMemLimitProvider),
    );
    await _open(vault);
    return recoveryKey;
  }

  /// Unlocks with the master password. Throws [WrongPassword] or
  /// [VaultKeyMismatch]; the session stays locked.
  Future<void> unlock(String password) async {
    final vault = await Vault.unlock(
      crypto: _crypto,
      store: _lockedStore,
      password: password,
      deviceId: _deviceId,
      now: _now,
    );
    await _open(vault);
  }

  /// Unlocks with the recovery key as typed. Throws
  /// [RecoveryKeyFormatException] for a typo, [WrongRecoveryKey] for
  /// another vault's key.
  Future<void> unlockWithRecovery(String typed) async {
    final recoveryKey = RecoveryKey.parse(_crypto, typed);
    try {
      final vault = await Vault.unlockWithRecovery(
        crypto: _crypto,
        store: _lockedStore,
        recoveryKey: recoveryKey,
        deviceId: _deviceId,
        now: _now,
      );
      await _open(vault);
    } finally {
      recoveryKey.dispose();
    }
  }

  /// Re-reads the vault after a write, so the index matches the disk.
  Future<void> reload() async {
    final current = state;
    if (current is! Unlocked) return;
    await _open(current.vault);
  }

  /// Wipes the vault key and drops every decrypted record.
  void lock() {
    final current = state;
    if (current is! Unlocked) return;
    current.vault.lock();
    state = Locked(current.vault.store);
  }

  VaultStore get _lockedStore => switch (state) {
    Locked(:final store) => store,
    _ => throw StateError('No locked vault to open'),
  };

  Future<void> _open(Vault vault) async {
    final contents = await vault.loadAll();
    state = Unlocked(vault, VaultIndex(contents));
  }
}

final vaultSessionProvider =
    NotifierProvider<VaultSessionNotifier, VaultSession>(
      VaultSessionNotifier.new,
    );

/// The recovery key of a vault created moments ago, held until the user
/// confirms they saved it (design frame D02), then disposed.
class PendingRecoveryKey extends Notifier<RecoveryKey?> {
  @override
  RecoveryKey? build() => null;

  void hold(RecoveryKey key) {
    state?.dispose();
    state = key;
  }

  /// The user saved it: wipe it from memory for good.
  void confirmSaved() {
    state?.dispose();
    state = null;
  }
}

final pendingRecoveryKeyProvider =
    NotifierProvider<PendingRecoveryKey, RecoveryKey?>(PendingRecoveryKey.new);
