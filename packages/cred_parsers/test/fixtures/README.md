# Parser fixtures

Test-only files generated for this repo with `openssl` and `keytool`.
None of them is a real credential: the keys were created for these tests,
JSON and plist values are placeholders, and every password is
`test-password` (keystore key passwords marked below are `key-password`).

The expected keystore fingerprints and expiry dates in
`java_keystore_test.dart` were copied from `keytool -list -v -keystore <file>
-storepass test-password` (add `-storetype JCEKS` for `.jceks`).

| File | Made with |
|---|---|
| `AuthKey_TESTKEY123.p8` | `openssl ecparam -name prime256v1` + `openssl pkcs8 -topk8 -nocrypt` |
| `renamed-key.p8` | a copy of `AuthKey_TESTKEY123.p8` without Apple's filename |
| `AuthKey_ED25519KEY.p8` | `openssl genpkey -algorithm ed25519` (not P-256, so not an Apple key) |
| `cert.pem`, `cert.cer` | `openssl req -x509` (PEM), `openssl x509 -outform DER` |
| `apple_development.cer` | `openssl req -x509 -subj "/UID=TESTUID001/CN=Apple Development: DevVault Test (TESTTEAM01)/OU=TESTTEAM01/O=DevVault Tests/C=US" -days 365 -outform DER` |
| `developer_id_oid.cer` | `openssl req -x509 -subj "/CN=DevVault Test Signer/OU=TESTTEAM01/O=DevVault Tests" -addext "1.2.840.113635.100.6.1.13=ASN1:NULL" -days 36500 -outform DER` (Apple marker extension only; GeneralizedTime notAfter) |
| `cert.p12` | `openssl pkcs12 -export` (OpenSSL 3 defaults: PBES2/AES) |
| `test.mobileprovision` | `openssl cms -sign -nodetach -binary -outform DER` over a small plist |
| `ber.mobileprovision` | `test.mobileprovision` with its outer layers re-encoded with BER indefinite lengths, as Apple writes them |
| `test.jks`, `test.jceks` | `keytool -genkeypair -storetype JKS` / `JCEKS`, alias `upload` |
| `keypass.jks`, `keypass.jceks` | as above, but `-keypass key-password` (key password differs from the store password) |
| `two-keys.jks` | two `keytool -genkeypair` runs: `upload` (EC, key password `test-password`) and `release` (RSA 2048, `-keypass key-password`) |
| `chain.jks` | `upload` key whose certificate is signed by a separate root: `-certreq`, `-gencert` from a throwaway root keystore, then `-importcert` of leaf + root (chain length 2) |
| `trusted.jks` | `keytool -importcert -alias ca -file cert.cer` only (no private key) |
| `secret.jceks` | `keytool -genseckey -alias api -keyalg AES` then `-genkeypair -alias signing` (the serialized secret key comes first in the file) |
| `*.json`, `GoogleService-Info.plist` | written by hand |
| `GoogleService-Info.binary.plist` | `plutil -convert binary1` of `GoogleService-Info.plist` (binary plists aren't read) |

The Google config fixtures cover:

- `google-services.json`: one Android app, so its facts are reported.
- `google-services.multi.json`: two Android apps, so the user picks one.
- `GoogleService-Info.plist`: the iOS config as the Firebase console writes it.
- `service-account.json`: a GCP service-account key.
- `client_secret_…-test…json` / `client_secret_…-web…json`: OAuth
  `installed` and `web` clients.
