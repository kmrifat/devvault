/// Reads facts out of developer credential files.
///
/// A parser only reports what the file itself contains. Anything it cannot
/// read is left empty and the file falls back to a generic file; nothing is
/// guessed.
library;

/// File extensions DevVault recognises on import. Everything else is
/// imported as a generic file.
const Set<String> knownExtensions = {
  'p8',
  'p12',
  'cer',
  'mobileprovision',
  'jks',
  'keystore',
  'json',
  'plist',
};
