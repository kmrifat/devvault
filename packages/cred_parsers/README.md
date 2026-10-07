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
- `parseInIsolate` runs the same thing off the UI isolate.
- Errors, warnings and `toString()` never quote file contents or secrets.

Fixtures in `test/fixtures` are test-only material; see its README.
