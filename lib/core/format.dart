/// Display text for stored values: field names, sizes, hashes.
abstract final class Format {
  /// Words shown in capitals inside field names.
  static const _acronyms = {
    'id': 'ID',
    'uuid': 'UUID',
    'url': 'URL',
    'uri': 'URI',
    'api': 'API',
    'sha1': 'SHA-1',
    'sha256': 'SHA-256',
    'md5': 'MD5',
    'pem': 'PEM',
    'oauth': 'OAuth',
    'gcp': 'GCP',
    'apns': 'APNs',
  };

  /// A field's stored name as a label: `store_password` → "Store password",
  /// `key_id` → "Key ID", `sha256` → "SHA-256".
  static String fieldLabel(String key) {
    final words = key
        .split(RegExp(r'[_\-\s]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return key;
    return [
      for (final (i, word) in words.indexed)
        _acronyms[word.toLowerCase()] ??
            (i == 0
                ? word[0].toUpperCase() + word.substring(1)
                : word.toLowerCase()),
    ].join(' ');
  }

  /// A file size: "512 bytes", "2.6 KB", "1.2 MB".
  static String bytes(int size) {
    if (size < 1024) return size == 1 ? '1 byte' : '$size bytes';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// The first and last eight characters of a hex digest.
  static String shortHash(String hex) => hex.length <= 16
      ? hex
      : '${hex.substring(0, 8)}…${hex.substring(hex.length - 8)}';
}
