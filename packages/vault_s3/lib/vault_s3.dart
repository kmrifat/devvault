/// S3-compatible storage backend for DevVault sync.
///
/// Signs requests with AWS Signature Version 4 and relies on conditional
/// writes (`If-Match` / `If-None-Match`) for compare-and-swap without a
/// server.
library;

export 'src/s3_backend.dart';
export 'src/sigv4.dart';

/// Region to sign with when the provider has no real regions (Cloudflare R2).
const String autoRegion = 'auto';
