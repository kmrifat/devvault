import 'dart:async';
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

  /// Sets a new master password. Writes `vault.json` only.
  Future<void> changePassword(String newPassword) => exclusive(() async {
    final current = state;
    if (current is! Unlocked) throw StateError('The vault is locked');
    await current.vault.changePassword(newPassword);
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
