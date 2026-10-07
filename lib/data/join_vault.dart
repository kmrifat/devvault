import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart';

import 'providers.dart';
import 'sync_setup.dart';
import 'vault_session.dart';

/// A vault found in a bucket: its id and plaintext `vault.json`.
class RemoteVault {
  const RemoteVault(this.id, this.header);

  final String id;
  final VaultHeader header;
}

/// The vault you already have elsewhere (P2-10): find it in the bucket,
/// check the master password, download it, open it and keep syncing.
class VaultJoiner {
  VaultJoiner(this._ref);

  final Ref _ref;

  StorageBackend _backend(SyncSettings settings, AwsCredentials credentials) =>
      _ref.read(storageBackendFactoryProvider)(settings, credentials);

  /// Every vault under the settings' folder: each `<id>/vault.json`.
  Future<List<RemoteVault>> find(
    SyncSettings settings,
    AwsCredentials credentials,
  ) async {
    final prefix = settings.rootPrefix;
    final backend = _backend(settings, credentials);
    final headerKey = RegExp(
      '^${RegExp.escape(prefix)}([0-9a-f-]{36})/${RegExp.escape(VaultHeader.fileName)}\$',
    );
    final vaults = <RemoteVault>[];
    for (final object in await backend.list(prefix)) {
      final id = headerKey.firstMatch(object.key)?.group(1);
      if (id == null || !isCanonicalUuid(id)) continue;
      final body = await backend.get(object.key);
      if (body == null) continue;
      try {
        final header = VaultHeader.parse(String.fromCharCodes(body.bytes));
        if (header.vaultId == id) vaults.add(RemoteVault(id, header));
      } on Object {
        // Not a vault.json this version can read: not offered.
      }
    }
    return vaults;
  }

  /// Joins [vault]. Throws [WrongPassword] before downloading anything when
  /// the password doesn't open it, and [StateError] when this device
  /// already has a vault. Afterwards the vault is open and syncing.
  Future<void> join({
    required SyncSettings settings,
    required AwsCredentials credentials,
    required RemoteVault vault,
    required String password,
  }) async {
    final crypto = _ref.read(cryptoProvider);
    (await VaultKeys.unlockWithPassword(
      crypto,
      vault.header,
      password,
    )).dispose();

    final vaultsDir = _ref.read(vaultsDirProvider);
    if (findVault(vaultsDir) != null) {
      throw StateError('This device already has a vault');
    }
    final store = VaultStore(Directory('${vaultsDir.path}/${vault.id}'));
    final backend = _backend(settings, credentials);
    final remotePrefix = '${settings.rootPrefix}${vault.id}/';
    try {
      await _download(backend, remotePrefix, store);
      final session = _ref.read(vaultSessionProvider.notifier)..findOnDisk();
      await session.unlock(password);
      final capabilities = await _ref.read(storageProbeProvider)(
        settings,
        credentials,
        '$remotePrefix.devvault-probe',
      );
      await _ref
          .read(syncSetupProvider.notifier)
          .save(settings, credentials, capabilities);
    } on Object {
      if (_ref.read(vaultSessionProvider) is! Unlocked) {
        await SyncStateStore(store).clear();
        if (store.root.existsSync()) await store.root.delete(recursive: true);
        _ref.read(vaultSessionProvider.notifier).findOnDisk();
      }
      rethrow;
    }
  }

  /// Copies every object under [prefix] into [store], and records each as
  /// synced (etag and base) so the first sync has nothing to fetch again.
  /// `vault.json` is written last: until then the folder isn't a vault.
  Future<void> _download(
    StorageBackend backend,
    String prefix,
    VaultStore store,
  ) async {
    final syncState = SyncStateStore(store);
    final state = SyncState();
    Uint8List? header;
    String? headerEtag;
    for (final object in await backend.list(prefix)) {
      final path = object.key.substring(prefix.length);
      final parts = path.split('/');
      final isHeader = path == VaultHeader.fileName;
      final isObject =
          parts.length == 2 &&
          parts[1].endsWith('.enc') &&
          const {'items', 'apps', 'blobs', 'tombstones'}.contains(parts[0]);
      if (!isHeader && !isObject) continue;
      final body = await backend.get(object.key);
      if (body == null) continue;
      if (isHeader) {
        header = body.bytes;
        headerEtag = body.etag;
        continue;
      }
      final file = File('${store.root.path}/$path');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(body.bytes, flush: true);
      state.remote[path] = SyncedObject(etag: body.etag);
      if (parts[0] != 'blobs') await syncState.putBase(path, body.bytes);
    }
    if (header == null) {
      throw StateError('vault.json disappeared while joining');
    }
    state.remote[VaultHeader.fileName] = SyncedObject(etag: headerEtag!);
    await syncState.putBase(VaultHeader.fileName, header);
    await syncState.save(state);
    await store.open();
    await File('${store.root.path}/${VaultHeader.fileName}')
        .writeAsBytes(header, flush: true);
  }
}

final vaultJoinerProvider = Provider<VaultJoiner>(VaultJoiner.new);
