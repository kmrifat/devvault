# cred_parsers

Parsers that read facts out of developer credential files (.p8, .p12, .mobileprovision, .jks, Firebase/GCP/OAuth JSON). Pure Dart.

Part of the DevVault pub workspace. See `docs/PLAN.md` at the repo root.

## Contract

- `detectFormat(filename, bytes)` places a file from magic bytes, then DER
  or JSON structure, then the filename. The extension alone never decides.
- `CredentialParsers.parse` never throws. Unknown input, a format with no
  parser yet, or any exception inside a parser all come back as a
  `generic_file` result with no facts.
- Every fact in a `ParseResult` has `source: file`, and `expiresAt` is only
  what the file states. Missing passwords come back as `secretsNeeded`.
- Secrets are asked for by key: `store_password` and `key_password` for
  JKS/JCEKS keystores (kept apart, so each error is reported on its own).
  Whatever is stored in clear (aliases, certificates) is read without them.
- When a file describes several things and the user must pick one (a
  multi-app `google-services.json`), the result lists them in `options`
  (`ParseOption{id, label}`, both from the file) and `needsChoice` is true.
  Parse again with `ParseInput.choice` set to an option's `id`; the result's
  `chosen` says which one the facts describe. A choice that isn't in the
  file is a warning, never a guess.
- `parseInIsolate` runs the same thing off the UI isolate.
- Errors, warnings and `toString()` never quote file contents or secrets.

## Parsers

Field keys are `static const`s on each parser class.

| Parser | Formats | Secret fields |
|---|---|---|
| `AppleAuthKeyParser` | `.p8` | none (the key itself stays in the file) |
| `X509CertificateParser` | `.cer`, `.crt`, single-cert PEM | none |
| `Pkcs12Parser` | `.p12`, `.pfx` | none (asks for `password`) |
| `ProvisioningProfileParser` | `.mobileprovision`, `.provisionprofile` (CMS signature not verified) | none |
| `JavaKeystoreParser` | JKS, JCEKS | none (asks for `store_password`, `key_password`) |
| `FirebaseConfigParser` | `google-services.json`, `GoogleService-Info.plist` | none (Firebase API keys are public) |
| `ServiceAccountParser` | GCP service-account JSON | `private_key` |
| `OAuthClientParser` | `client_secret_*.json` (`installed` or `web`) | `client_secret` |

None of the Google formats states an expiry (SPEC §6.5). `src/plist.dart` has a
strict XML plist reader (`parseXmlPlist`); binary plists aren't read and
import as generic files.

Fixtures in `test/fixtures` are test-only material; see its README.
