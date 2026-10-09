import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vault_core/vault_core.dart';
import 'package:vault_s3/vault_s3.dart';

import 'providers.dart';
import 'vault_session.dart';

/// Where a vault can sync to. R2 is the suggested default: no egress fees
/// and a free tier that fits a credential vault many times over.
enum StorageProvider {
  r2('Cloudflare R2', 'R2'),
  aws('Amazon S3', 'S3'),
  b2('Backblaze B2', 'B2'),
  minio('MinIO', 'MinIO'),
  custom('Other S3-compatible', 'S3');

  const StorageProvider(this.label, this.shortLabel);

  final String label;

  /// For the status chip: "Synced · R2".
  final String shortLabel;

  static StorageProvider parse(Object? name) =>
      values.where((p) => p.name == name).firstOrNull ?? r2;
}

/// The non-secret half of a sync setup. Saved next to the vault on this
/// device (`<vault_id>.sync/storage.json`), never uploaded.
class SyncSettings {
  const SyncSettings({
    this.provider = StorageProvider.r2,
    this.accountId = '',
    this.endpoint = '',
    this.region = '',
    this.bucket = '',
    this.prefix = '',
    this.pathStyle = true,
  });

  final StorageProvider provider;

  /// R2 only: the account the bucket belongs to.
  final String accountId;

  /// MinIO and other stores: the service URL.
  final String endpoint;
  final String region;
  final String bucket;

  /// An optional folder in the bucket, as typed (`devvault`).
  final String prefix;
  final bool pathStyle;

  /// [prefix] as a key prefix: `devvault/`, or empty.
  String get rootPrefix {
    final trimmed = prefix.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    return trimmed.isEmpty ? '' : '$trimmed/';
  }

  /// Why these settings can't be used, by field; empty when they can.
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (bucket.trim().isEmpty) errors['bucket'] = 'Enter the bucket name';
    switch (provider) {
      case StorageProvider.r2:
        if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(accountId.trim())) {
          errors['accountId'] =
              'The 32-character account ID from the R2 dashboard';
        }
      case StorageProvider.aws || StorageProvider.b2:
        if (region.trim().isEmpty) errors['region'] = 'Enter the region';
      case StorageProvider.minio || StorageProvider.custom:
        final uri = Uri.tryParse(endpoint.trim());
        if (uri == null ||
            !(uri.scheme == 'https' || uri.scheme == 'http') ||
            uri.host.isEmpty) {
          errors['endpoint'] = 'A URL such as https://s3.example.com';
        }
    }
    if (rootPrefix.isNotEmpty &&
        !StorageKeys.isValid(rootPrefix.substring(0, rootPrefix.length - 1))) {
      errors['prefix'] = 'Letters, digits, dots, dashes, underscores and /';
    }
    return errors;
  }

  S3Config toConfig() => switch (provider) {
    StorageProvider.r2 => S3Config.r2(
      accountId: accountId.trim().toLowerCase(),
      bucket: bucket.trim(),
    ),
    StorageProvider.aws => S3Config(
      endpoint: Uri.parse('https://s3.${region.trim()}.amazonaws.com'),
      bucket: bucket.trim(),
      region: region.trim(),
      pathStyle: pathStyle,
    ),
    StorageProvider.b2 => S3Config(
      endpoint: Uri.parse('https://s3.${region.trim()}.backblazeb2.com'),
      bucket: bucket.trim(),
      region: region.trim(),
      pathStyle: pathStyle,
    ),
    StorageProvider.minio || StorageProvider.custom => S3Config(
      endpoint: Uri.parse(endpoint.trim()),
      bucket: bucket.trim(),
      region: region.trim().isEmpty ? 'us-east-1' : region.trim(),
      pathStyle: pathStyle,
    ),
  };

  Map<String, Object?> toJson() => {
    'provider': provider.name,
    'account_id': accountId,
    'endpoint': endpoint,
    'region': region,
    'bucket': bucket,
    'prefix': prefix,
    'path_style': pathStyle,
  };

  factory SyncSettings.fromJson(Map<String, Object?> json) => SyncSettings(
    provider: StorageProvider.parse(json['provider']),
    accountId: json['account_id'] as String? ?? '',
    endpoint: json['endpoint'] as String? ?? '',
    region: json['region'] as String? ?? '',
    bucket: json['bucket'] as String? ?? '',
    prefix: json['prefix'] as String? ?? '',
    pathStyle: json['path_style'] as bool? ?? true,
  );
}

/// A working sync setup for the open vault.
class SyncSetup {
  const SyncSetup({
    required this.settings,
    required this.credentials,
    this.capabilities,
  });

  final SyncSettings settings;
  final AwsCredentials credentials;

  /// What the last connection test found; null if never tested.
  final StorageCapabilities? capabilities;
}

/// The open vault's sync setup: loaded after unlock, dropped on lock (the
/// access keys stay in the keychain, never in memory while locked).
class SyncSetupNotifier extends Notifier<SyncSetup?> {
  @override
  SyncSetup? build() {
    ref.listen(vaultSessionProvider, (previous, next) {
      if (next is Unlocked && previous is! Unlocked) {
        _load(next.vault);
      } else if (next is! Unlocked) {
        state = null;
      }
    });
    final session = ref.read(vaultSessionProvider);
    if (session is Unlocked) _load(session.vault);
    return null;
  }

  static String credentialKey(String vaultId) => 's3:$vaultId';

  static File _settingsFile(Vault vault) =>
      File('${SyncStateStore(vault.store).root.path}/storage.json');

  Future<void> _load(Vault vault) async {
    final file = _settingsFile(vault);
    if (!file.existsSync()) return;
    final settings = SyncSettings.fromJson(
      json.decode(await file.readAsString()) as Map<String, Object?>,
    );
    final keys = await ref
        .read(credentialStoreProvider)
        .read(credentialKey(vault.vaultId));
    if (keys == null) return; // keys removed from the keychain: sync off
    final decoded = json.decode(keys) as Map<String, Object?>;
    final state = await SyncStateStore(vault.store).load();
    if (ref.read(vaultSessionProvider) is! Unlocked) return;
    this.state = SyncSetup(
      settings: settings,
      credentials: AwsCredentials(
        accessKeyId: decoded['access_key_id']! as String,
        secretAccessKey: decoded['secret_access_key']! as String,
      ),
      capabilities: state.capabilities,
    );
  }

  Vault get _vault => switch (ref.read(vaultSessionProvider)) {
    Unlocked(:final vault) => vault,
    _ => throw StateError('The vault is locked'),
  };

  /// Probes the bucket with these settings (P2-04). Throws a
  /// [StorageException] when it can't be read and written at all.
  Future<StorageCapabilities> test(
    SyncSettings settings,
    AwsCredentials credentials,
  ) => ref.read(storageProbeProvider)(
    settings,
    credentials,
    '${settings.rootPrefix}${_vault.vaultId}/.devvault-probe',
  );

  /// Keeps the setup: settings beside the vault, keys in the keychain,
  /// capabilities in the sync state. Sync starts right away. Takes the
  /// session's write lock, so a sync still running finishes first and its
  /// bookkeeping isn't overwritten.
  Future<void> save(
    SyncSettings settings,
    AwsCredentials credentials,
    StorageCapabilities capabilities,
  ) => ref.read(vaultSessionProvider.notifier).exclusive(() async {
    final vault = _vault;
    await ref
        .read(credentialStoreProvider)
        .write(
          credentialKey(vault.vaultId),
          json.encode({
            'access_key_id': credentials.accessKeyId,
            'secret_access_key': credentials.secretAccessKey,
          }),
        );
    final file = _settingsFile(vault);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
      flush: true,
    );
    await temp.rename(file.path);
    final stateStore = SyncStateStore(vault.store);
    final syncState = await stateStore.load()
      ..capabilities = capabilities;
    await stateStore.save(syncState);
    state = SyncSetup(
      settings: settings,
      credentials: credentials,
      capabilities: capabilities,
    );
  });

  /// Stops syncing on this device: forgets the settings, the keys and the
  /// sync bookkeeping. The vault and the bucket are left as they are.
  ///
  /// Takes the session's write lock, which a sync holds until its blob GC
  /// is done: a run already going finishes before the bookkeeping is
  /// deleted, so it can't write it back, and one still waiting finds sync
  /// off and does nothing.
  Future<void> turnOff() =>
      ref.read(vaultSessionProvider.notifier).exclusive(() async {
        final vault = _vault;
        await ref
            .read(credentialStoreProvider)
            .delete(credentialKey(vault.vaultId));
        await SyncStateStore(vault.store).clear();
        state = null;
      });
}

final syncSetupProvider = NotifierProvider<SyncSetupNotifier, SyncSetup?>(
  SyncSetupNotifier.new,
);

/// Makes the backend for a bucket: [S3Backend]. Tests swap in a
/// [MemoryBackend] so no request leaves the machine.
final storageBackendFactoryProvider =
    Provider<StorageBackend Function(SyncSettings, AwsCredentials)>(
      (ref) =>
          (settings, credentials) =>
              S3Backend(config: settings.toConfig(), credentials: credentials),
    );

/// Tests a bucket: [S3Backend.probe] under the given prefix. Tests swap in
/// a fake so no request leaves the machine.
typedef StorageProbe = Future<StorageCapabilities> Function(
  SyncSettings settings,
  AwsCredentials credentials,
  String prefix,
);

final storageProbeProvider = Provider<StorageProbe>(
  (ref) => (settings, credentials, prefix) async {
    final backend = S3Backend(
      config: settings.toConfig(),
      credentials: credentials,
      maxAttempts: 2,
    );
    try {
      return await backend.probe(prefix);
    } finally {
      backend.close();
    }
  },
);

/// The configured storage, or null when sync is off. Stores that don't
/// enforce every condition are wrapped in a [VerifyingBackend].
final storageBackendProvider = Provider<StorageBackend?>((ref) {
  final setup = ref.watch(syncSetupProvider);
  if (setup == null) return null;
  final s3 = ref.watch(storageBackendFactoryProvider)(
    setup.settings,
    setup.credentials,
  );
  if (s3 is S3Backend) ref.onDispose(s3.close);
  final capabilities = setup.capabilities;
  return capabilities == null || capabilities.isRaceFree
      ? s3
      : VerifyingBackend(s3, capabilities);
});

/// A short name for the storage in the status chip, such as `R2`.
final storageLabelProvider = Provider<String?>(
  (ref) => ref.watch(syncSetupProvider)?.settings.provider.shortLabel,
);

/// The folder in the bucket vaults sync under.
final storageRootPrefixProvider = Provider<String>(
  (ref) => ref.watch(syncSetupProvider)?.settings.rootPrefix ?? '',
);
