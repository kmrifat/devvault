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
| `legacy.p12` | `openssl pkcs12 -export -legacy` (RC2-40 certificates, 3DES key, HMAC-SHA1) of the Apple-style leaf below |
| `3des.p12` | 3DES certificates and key, HMAC-SHA1 (as Keychain exports), same leaf |
| `empty-password.p12` | OpenSSL 3 defaults with an empty password, same leaf |
| `nomac.p12` | `-nomac -certpbe AES-256-CBC`: no MAC, so the password is only checked by decrypting; same leaf |
| `chain.p12` | the leaf, its key and the test CA, OpenSSL 3 defaults |
| `chain-nokey.p12` | `-nokeys` with the leaf and the test CA: no `localKeyId`, so the leaf is found by issuer |
| `two-certs.p12` | `-nokeys` with the leaf and `cert.pem`, which are unrelated: no leaf can be picked |
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

## PKCS#12 leaf and test CA

The `.p12` fixtures other than `cert.p12` hold one Apple-style leaf
certificate signed by a throwaway test CA; neither private key was kept
outside the `.p12` files. Made with OpenSSL 3.6:

```sh
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out ca.key
openssl req -x509 -new -key ca.key -subj "/CN=DevVault Test CA/O=DevVault Tests" \
  -not_before 20261001000000Z -not_after 20361001000000Z -out ca.crt
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out leaf.key
openssl req -new -key leaf.key -out leaf.csr \
  -subj "/UID=TESTTEAM01/CN=Apple Development: DevVault Test (TESTTEAM01)/OU=TESTTEAM01/O=DevVault Tests/C=US"
printf '%s\n' 'basicConstraints=critical,CA:FALSE' \
  'keyUsage=critical,digitalSignature' \
  'extendedKeyUsage=critical,codeSigning' \
  '1.2.840.113635.100.6.1.12=critical,DER:05:00' > leaf.ext
openssl x509 -req -in leaf.csr -CA ca.crt -CAkey ca.key -set_serial 0x1A2B3C4D5E6F \
  -not_before 20261007000000Z -not_after 20271007000000Z -extfile leaf.ext -out leaf.crt

openssl pkcs12 -export -legacy -inkey leaf.key -in leaf.crt -name "DevVault Test" \
  -passout pass:test-password -out legacy.p12
openssl pkcs12 -export -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
  -inkey leaf.key -in leaf.crt -name "DevVault Test" -passout pass:test-password -out 3des.p12
openssl pkcs12 -export -inkey leaf.key -in leaf.crt -name "DevVault Test" \
  -passout pass: -out empty-password.p12
openssl pkcs12 -export -nomac -certpbe AES-256-CBC -inkey leaf.key -in leaf.crt \
  -name "DevVault Test" -passout pass:test-password -out nomac.p12
openssl pkcs12 -export -inkey leaf.key -in leaf.crt -certfile ca.crt -name "DevVault Test" \
  -passout pass:test-password -out chain.p12
openssl pkcs12 -export -nokeys -in leaf.crt -certfile ca.crt \
  -passout pass:test-password -out chain-nokey.p12
cat leaf.crt cert.pem > two.pem
openssl pkcs12 -export -nokeys -in two.pem -passout pass:test-password -out two-certs.p12
```

The expected values in `pkcs12_test.dart` are from `openssl pkcs12 -info`
(with `-legacy` for `legacy.p12`) and
`openssl x509 -noout -subject -issuer -serial -dates -fingerprint -sha256`
(and `-sha1`).
