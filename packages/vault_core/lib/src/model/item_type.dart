/// The kinds of record a vault holds.
///
/// [wireName] is what the item JSON stores (see `docs/format/SPEC.md`), so
/// renaming an enum value never changes the format.
enum ItemType {
  appleAuthKey('apple_auth_key', 'Apple Auth Key'),
  appleCertificate('apple_certificate', 'Apple Certificate'),
  provisioningProfile('provisioning_profile', 'Provisioning Profile'),
  androidKeystore('android_keystore', 'Android Keystore'),
  firebaseConfig('firebase_config', 'Firebase Config'),
  gcpServiceAccount('gcp_service_account', 'GCP Service Account'),
  oauthClient('oauth_client', 'OAuth Client'),
  genericFile('generic_file', 'Generic File'),
  genericSecret('generic_secret', 'Generic Secret');

  const ItemType(this.wireName, this.label);

  /// Stable identifier written into item JSON.
  final String wireName;

  /// Human-readable name for the UI.
  final String label;

  static final Map<String, ItemType> _byWireName = {
    for (final type in values) type.wireName: type,
  };

  /// The type for [wireName], or `null` for a type this version doesn't know.
  static ItemType? fromWireName(String wireName) => _byWireName[wireName];
}

/// Where an item's `expires_at` came from. There is no third option: an
/// expiry is either read from the file or typed in by the user, never
/// inferred.
enum ExpirySource {
  file('file'),
  user('user');

  const ExpirySource(this.wireName);

  final String wireName;

  static ExpirySource? fromWireName(String wireName) => switch (wireName) {
    'file' => ExpirySource.file,
    'user' => ExpirySource.user,
    _ => null,
  };
}
