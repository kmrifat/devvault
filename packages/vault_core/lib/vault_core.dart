/// DevVault core: key hierarchy, encryption, vault format and items.
///
/// Pure Dart so it can be tested with `dart test` on every desktop OS and
/// mirrored by other clients. The format contract lives in
/// `docs/format/SPEC.md`.
library;

export 'package:sodium/sodium_sumo.dart' show SecureKey;

export 'src/crypto/vault_crypto.dart';
export 'src/format/envelope.dart';
export 'src/format/format_error.dart';
export 'src/format/kdf_params.dart';
export 'src/format/timestamps.dart';
export 'src/format/vault_header.dart';
export 'src/keys/recovery_key.dart';
export 'src/keys/vault_keys.dart';
export 'src/index/vault_index.dart';
export 'src/model/item_type.dart';
export 'src/model/records.dart';
export 'src/store/vault_store.dart';
export 'src/sync/hlc.dart';
export 'src/sync/local_dir_backend.dart';
export 'src/sync/memory_backend.dart';
export 'src/sync/merge.dart';
export 'src/sync/storage_backend.dart';
export 'src/sync/storage_capabilities.dart';
export 'src/sync/sync_engine.dart';
export 'src/sync/sync_state.dart';
export 'src/vault/vault.dart';

/// Version of the on-disk and in-bucket vault format this package writes.
const int vaultFormatVersion = 1;
