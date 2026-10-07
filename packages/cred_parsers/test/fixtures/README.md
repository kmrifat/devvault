# Parser fixtures

Test-only files generated for this repo with `openssl` and `keytool`.
None of them is a real credential: the keys were created for these tests,
JSON and plist values are placeholders, and every password is
`test-password`.

| File | Made with |
|---|---|
| `AuthKey_TESTKEY123.p8` | `openssl ecparam -name prime256v1` + `openssl pkcs8 -topk8 -nocrypt` |
| `cert.pem`, `cert.cer` | `openssl req -x509` (PEM), `openssl x509 -outform DER` |
| `cert.p12` | `openssl pkcs12 -export` (OpenSSL 3 defaults: PBES2/AES) |
| `test.mobileprovision` | `openssl cms -sign -nodetach -binary -outform DER` over a small plist |
| `test.jks`, `test.jceks` | `keytool -genkeypair -storetype JKS` / `JCEKS`, alias `upload` |
| `*.json`, `GoogleService-Info.plist` | written by hand |
