/// DevVault core: key hierarchy, encryption, vault format and items.
///
/// Pure Dart so it can be tested with `dart test` on every desktop OS and
/// mirrored by other clients. The format contract lives in
/// `docs/format/SPEC.md`.
library;

export 'src/model/item_type.dart';

/// Version of the on-disk and in-bucket vault format this package writes.
const int vaultFormatVersion = 1;
