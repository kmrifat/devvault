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
export 'src/model/item_type.dart';

/// Version of the on-disk and in-bucket vault format this package writes.
const int vaultFormatVersion = 1;
