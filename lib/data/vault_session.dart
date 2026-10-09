import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';

import '../services/biometric_key_store.dart';
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
  const Locked(this.store, this.header);

  final VaultStore store;

  /// The plaintext `vault.json`, or `null` if it can't be parsed (unlocking
  /// will then report the problem).
  final VaultHeader? header;

  static Locked of(VaultStore store) {
    VaultHeader? header;
    try {
      header = store.readHeaderSync();
    } on Object {
      header = null;
    }
    return Locked(store, header);
  }
}

/// The vault is open: [index] is the decrypted contents.
final class Unlocked extends VaultSession {
  const Unlocked(this.vault, this.index);

  final Vault vault;
  final VaultIndex index;
}

/// Finds the vault on this device: the first folder under [vaultsDir],
/// named after its vault id, that holds a `vault.json`. Working folders
/// next to it (`.sync`, `.adopting`) are skipped. One vault per device in
/// v1.
VaultStore? findVault(Directory vaultsDir) {
  if (!vaultsDir.existsSync()) return null;
  final folders =
      vaultsDir
          .listSync()
          .whereType<Directory>()
          .where(
            (d) => isCanonicalUuid(
              d.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
            ),
          )
          .toList()
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
    return store == null ? const NoVault() : Locked.of(store);
  }

  /// Looks for a vault on disk again (after joining one from a bucket).
  void findOnDisk() {
    final store = findVault(ref.read(vaultsDirProvider));
    state = store == null ? const NoVault() : Locked.of(store);
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

  BiometricKeyStore get _biometric => ref.read(biometricKeyStoreProvider);

  /// Unlocks with the vault key kept behind biometrics (SPEC §9.1). Returns
  /// false if the user cancelled the prompt. Throws [BiometricKeyGone] when
  /// the key is gone or no longer matches the vault (rotated elsewhere); the
  /// stored key is deleted then, and the password is the way in.
  Future<bool> unlockWithBiometrics({required String reason}) async {
    final store = _lockedStore;
    final vaultId = switch (state) {
      Locked(:final header?) => header.vaultId,
      _ => throw const BiometricKeyGone(),
    };
    final Uint8List? bytes;
    try {
      bytes = await _biometric.read(vaultId, reason: reason);
    } on BiometricKeyGone {
      await _forgetBiometricKey(vaultId);
      rethrow;
    }
    if (bytes == null) return false;
    final key = _crypto.keyFromBytes(bytes);
    bytes.fillRange(0, bytes.length, 0);
    final Vault vault;
    try {
      vault = await Vault.unlockWithKey(
        crypto: _crypto,
        store: store,
        vaultKey: key,
        deviceId: _deviceId,
        now: _now,
      );
    } on VaultKeyMismatch {
      await _forgetBiometricKey(vaultId);
      throw const BiometricKeyGone();
    }
    await _open(vault);
    return true;
  }

  /// Keeps the vault key on this device behind biometrics, so it can be
  /// unlocked without the password. Returns false if the user cancelled the
  /// prompt (Android asks before storing). Throws [BiometricKeyUnavailable].
  Future<bool> enableBiometricUnlock({required String reason}) async {
    final vault = _vault;
    final bytes = vault.withVaultKeyBytes(Uint8List.fromList);
    try {
      return await _biometric.save(vault.vaultId, bytes, reason: reason);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      ref.read(_biometricRevision.notifier).bump();
    }
  }

  /// Deletes the key kept behind biometrics.
  Future<void> disableBiometricUnlock() => _forgetBiometricKey(_vault.vaultId);

  Future<void> _forgetBiometricKey(String vaultId) async {
    try {
      await _biometric.delete(vaultId);
    } finally {
      ref.read(_biometricRevision.notifier).bump();
    }
  }

  /// Swaps in the vault [adopt] reopens under a new key (a rotation done on
  /// another device), under the write lock. A key kept behind biometrics
  /// is the old one, so it's deleted (SPEC §9.1).
  Future<KeyAdoption> adoptKey(
    Future<KeyAdoption> Function(Vault current) adopt,
  ) => exclusive(() async {
    final current = _vault;
    final adoption = await adopt(current);
    await _forgetBiometricKey(current.vaultId);
    await _open(adoption.vault);
    return adoption;
  });

  /// Whether [password] is the current master password. Runs Argon2id, so
  /// it takes as long as an unlock.
  Future<bool> checkPassword(String password) async {
    try {
      final key = await VaultKeys.unlockWithPassword(
        _crypto,
        _vault.header,
        password,
      );
      key.dispose();
      return true;
    } on WrongPassword {
      return false;
    }
  }

  /// Sets a new master password. Writes `vault.json` only. A key kept
  /// behind biometrics is deleted (SPEC §9.1): the user turns it on again.
  Future<void> changePassword(String newPassword) => exclusive(() async {
    final current = state;
    if (current is! Unlocked) throw StateError('The vault is locked');
    await current.vault.changePassword(newPassword);
    await _forgetBiometricKey(current.vault.vaultId);
  });

  Future<void>? _writing;

  /// Runs [action] once no other write is running, so an edit and a sync
  /// never touch the vault files at the same time. When nothing is running
  /// it starts at once, in the caller's zone.
  Future<T> exclusive<T>(Future<T> Function() action) async {
    for (var running = _writing; running != null; running = _writing) {
      await running;
    }
    final done = Completer<void>();
    _writing = done.future;
    try {
      return await action();
    } finally {
      _writing = null;
      done.complete();
    }
  }

  /// Rotates the vault key (SPEC §9): every item, app, tombstone and file
  /// is re-encrypted under a new key, with a new recovery key, which is
  /// returned for the caller to show once and dispose. Needs the master
  /// password. Other synced devices pause until they adopt the new key.
  Future<RecoveryKey> rotateVaultKey(String password) => exclusive(() async {
    final current = state;
    if (current is! Unlocked) throw StateError('The vault is locked');
    final recoveryKey = await current.vault.rotateVaultKey(password);
    // The stored key is the old one now (SPEC §9.1).
    await _forgetBiometricKey(current.vault.vaultId);
    await _open(current.vault);
    return recoveryKey;
  });

  /// The new recovery key of a rotation that was interrupted and finished
  /// by this unlock, handed over once (null almost always).
  RecoveryKey? takePendingRecoveryKey() => switch (state) {
    Unlocked(:final vault) => vault.takePendingRecoveryKey(),
    _ => null,
  };

  /// Issues a new recovery key; the old one stops working. Writes
  /// `vault.json` only. The caller shows the key once and disposes it.
  Future<RecoveryKey> replaceRecoveryKey() => exclusive(() async {
    final current = state;
    if (current is! Unlocked) throw StateError('The vault is locked');
    return current.vault.replaceRecoveryKey();
  });

  Vault get _vault => switch (state) {
    Unlocked(:final vault) => vault,
    _ => throw StateError('The vault is locked'),
  };

  /// A new, unsaved item of [type] (fresh id, this device).
  Item newItem(ItemType type, String title) =>
      _vault.newItem(type: type, title: title);

  /// Saves [item] and refreshes the index. Returns it as stored.
  Future<Item> saveItem(Item item) => exclusive(() async {
    final saved = await _vault.putItem(item);
    await reload();
    return saved;
  });

  /// Deletes the item [id] (a tombstone, so other devices delete it too)
  /// and refreshes the index.
  Future<void> deleteItem(String id) => exclusive(() async {
    await _vault.delete(id, TombstoneKind.item);
    await reload();
  });

  /// A new, unsaved app (fresh id, this device).
  AppRecord newApp(String name) => _vault.newApp(name: name);

  /// Saves [app] and refreshes the index. Returns it as stored.
  Future<AppRecord> saveApp(AppRecord app) => exclusive(() async {
    final saved = await _vault.putApp(app);
    await reload();
    return saved;
  });

  /// Saves every app in [apps] (an organization renamed across its apps)
  /// and refreshes the index once.
  Future<void> saveApps(Iterable<AppRecord> apps) => exclusive(() async {
    for (final app in apps) {
      await _vault.putApp(app);
    }
    await reload();
  });

  /// Deletes the app [id]. Its items stay, grouped under "No app".
  Future<void> deleteApp(String id) => exclusive(() async {
    await _vault.delete(id, TombstoneKind.app);
    await reload();
  });

  /// Re-reads the vault after a write, so the index matches the disk.
  Future<void> reload() async {
    final current = state;
    if (current is! Unlocked) return;
    await _open(current.vault);
  }

  /// Wipes the vault key, drops every decrypted record and takes any copied
  /// secret off the clipboard.
  void lock() {
    final current = state;
    if (current is! Unlocked) return;
    ref.read(clipboardGuardProvider).clearNow();
    current.vault.lock();
    state = Locked(current.vault.store, current.vault.header);
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

/// Device-bound unlock for this device's vault: what the device offers and
/// whether the vault key is stored behind it.
class BiometricUnlock {
  const BiometricUnlock(this.biometry, {required this.enabled});

  /// Null when the device has no biometrics (or none enrolled).
  final Biometry? biometry;
  final bool enabled;

  bool get available => biometry != null;
}

/// Bumped when the stored key changes, so [biometricUnlockProvider] asks
/// the key store again.
class _Revision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final _biometricRevision = NotifierProvider<_Revision, int>(_Revision.new);

final biometricUnlockProvider = FutureProvider<BiometricUnlock>((ref) async {
  ref.watch(_biometricRevision);
  final store = ref.watch(biometricKeyStoreProvider);
  final vaultId = ref.watch(
    vaultSessionProvider.select(
      (s) => switch (s) {
        Locked(:final header) => header?.vaultId,
        Unlocked(:final vault) => vault.vaultId,
        NoVault() => null,
      },
    ),
  );
  final biometry = await store.biometry();
  final enabled =
      biometry != null && vaultId != null && await store.has(vaultId);
  return BiometricUnlock(biometry, enabled: enabled);
});

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

/// Set after unlocking with the recovery key: the user must choose a new
/// master password before the vault opens (design frame D00, recovery).
class PasswordResetPending extends Notifier<bool> {
  @override
  bool build() => false;

  void require() => state = true;
  void done() => state = false;
}

final passwordResetPendingProvider =
    NotifierProvider<PasswordResetPending, bool>(PasswordResetPending.new);
