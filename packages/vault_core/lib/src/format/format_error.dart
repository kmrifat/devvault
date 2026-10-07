/// A vault file or field doesn't follow `docs/format/SPEC.md`.
///
/// The message is meant for logs and bug reports. It never contains secret
/// material, only which rule was broken.
class VaultFormatException implements Exception {
  const VaultFormatException(this.message);

  final String message;

  @override
  String toString() => 'VaultFormatException: $message';
}
