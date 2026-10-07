/// Reads facts out of developer credential files.
///
/// A parser only reports what the file itself contains. Anything it cannot
/// read is left empty and the file falls back to a generic file; nothing is
/// guessed.
library;

export 'src/detect.dart' show CredentialFormat, detectFormat;
export 'src/parse_result.dart';
export 'src/parsers.dart';
export 'src/parsers/apple_auth_key.dart';
export 'src/parsers/firebase_config.dart';
export 'src/parsers/java_keystore.dart';
export 'src/parsers/oauth_client.dart';
export 'src/parsers/pkcs12.dart';
export 'src/parsers/provisioning_profile.dart';
export 'src/parsers/service_account.dart';
export 'src/parsers/x509_certificate.dart';
export 'src/x509.dart';

/// File extensions DevVault recognises on import. Everything else is
/// imported as a generic file.
const Set<String> knownExtensions = {
  'p8',
  'p12',
  'pfx',
  'cer',
  'crt',
  'der',
  'pem',
  'mobileprovision',
  'provisionprofile',
  'jks',
  'jceks',
  'keystore',
  'json',
  'plist',
};
