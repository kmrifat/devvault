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
| `development.mobileprovision` | profile below: `ProvisionedDevices` + `get-task-allow` true (Development) |
| `adhoc.mobileprovision` | `ProvisionedDevices`, `get-task-allow` false (Ad Hoc) |
| `appstore.mobileprovision` | no devices, `get-task-allow` false (App Store) |
| `enterprise.mobileprovision` | `ProvisionsAllDevices` true (Enterprise / In-House) |
| `wildcard.mobileprovision` | Development, App ID `TESTTEAM01.*` |
| `development-ber.mobileprovision` | `development.mobileprovision` re-encoded as Apple writes it: indefinite lengths and a constructed OCTET STRING of 1000-byte chunks |
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

## Provisioning profiles

The `.mobileprovision` fixtures other than `test`/`ber` are CMS
SignedData over a placeholder plist, signed with a throwaway P-256 key
and self-signed certificate that weren't kept (the parser never looks at
the signature). The plist mimics what the developer portal writes; every
value is a placeholder, and the device ids are made up. The one
`DeveloperCertificates` entry is `apple_development.cer`, so its SHA-1 is
`openssl x509 -inform DER -in apple_development.cer -noout -fingerprint -sha1`.
Made with OpenSSL 3.6, from this directory:

```sh
#!/bin/bash
# Generates the provisioning-profile fixtures. Run from test/fixtures.
set -euo pipefail
OPENSSL=${OPENSSL:-openssl}
work=$(mktemp -d)
$OPENSSL req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -subj "/CN=DevVault Test Profile Signer/O=DevVault Tests" -days 365 \
  -keyout "$work/signer.key" -out "$work/signer.crt" 2>/dev/null
cert=$(base64 < apple_development.cer | tr -d '\n')

# profile <out> <name> <uuid> <app-id> <get-task-allow> <devices: yes|no> <all-devices: yes|no>
profile() {
  local devices="" all=""
  [ "$6" = yes ] && devices='	<key>ProvisionedDevices</key>
	<array>
		<string>00008030-000000000000001E</string>
		<string>00008110-00000000000000AB</string>
		<string>0000000000000000000000000000000000000003</string>
	</array>'
  [ "$7" = yes ] && all='	<key>ProvisionsAllDevices</key>
	<true/>'
  cat > "$work/$1.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AppIDName</key>
	<string>DevVault Test App</string>
	<key>ApplicationIdentifierPrefix</key>
	<array>
	<string>TESTTEAM01</string>
	</array>
	<key>CreationDate</key>
	<date>2026-10-07T00:00:00Z</date>
	<key>Platform</key>
	<array>
		<string>iOS</string>
		<string>xrOS</string>
		<string>visionOS</string>
	</array>
	<key>IsXcodeManaged</key>
	<false/>
	<key>DeveloperCertificates</key>
	<array>
		<data>$cert</data>
	</array>
	<key>Entitlements</key>
	<dict>
		<key>application-identifier</key>
		<string>$4</string>
		<key>keychain-access-groups</key>
		<array>
			<string>TESTTEAM01.*</string>
		</array>
		<key>get-task-allow</key>
		<$5/>
		<key>com.apple.developer.team-identifier</key>
		<string>TESTTEAM01</string>
	</dict>
	<key>ExpirationDate</key>
	<date>2027-10-07T00:00:00Z</date>
	<key>Name</key>
	<string>$2</string>
$devices
$all
	<key>TeamIdentifier</key>
	<array>
		<string>TESTTEAM01</string>
	</array>
	<key>TeamName</key>
	<string>DevVault Tests</string>
	<key>TimeToLive</key>
	<integer>365</integer>
	<key>UUID</key>
	<string>$3</string>
	<key>Version</key>
	<integer>1</integer>
</dict>
</plist>
PLIST
  $OPENSSL cms -sign -nodetach -binary -outform DER -md sha256 \
    -signer "$work/signer.crt" -inkey "$work/signer.key" \
    -in "$work/$1.plist" -out "$1"
}

profile development.mobileprovision "DevVault Test Development" \
  00000000-0000-4000-8000-000000000001 TESTTEAM01.com.example.devvault true yes no
profile adhoc.mobileprovision "DevVault Test Ad Hoc" \
  00000000-0000-4000-8000-000000000002 TESTTEAM01.com.example.devvault false yes no
profile appstore.mobileprovision "DevVault Test App Store" \
  00000000-0000-4000-8000-000000000003 TESTTEAM01.com.example.devvault false no no
profile enterprise.mobileprovision "DevVault Test In House" \
  00000000-0000-4000-8000-000000000004 TESTTEAM01.com.example.devvault false no yes
profile wildcard.mobileprovision "DevVault Test Wildcard" \
  00000000-0000-4000-8000-000000000005 'TESTTEAM01.*' true yes no
rm -rf "$work"
```

`development-ber.mobileprovision` is `python3 ber.py development.mobileprovision
development-ber.mobileprovision` with this `ber.py`; `openssl cms -verify
-noverify -inform DER` gives the same plist for both files:

```python
"""Re-encodes a DER CMS profile with BER indefinite lengths, as Apple
writes them: ContentInfo, [0], SignedData, encapContentInfo and its [0]
get indefinite lengths, and eContent becomes a constructed OCTET STRING
of 1000-byte chunks. Everything else is copied unchanged.

usage: python3 ber.py in.mobileprovision out.mobileprovision"""
import sys

def read(b, i):
    tag = b[i]; n = b[i + 1]; i += 2
    if n & 0x80:
        k = n & 0x7F; n = int.from_bytes(b[i:i + k], 'big'); i += k
    return tag, b[i:i + n], i + n

def children(b):
    out, i = [], 0
    while i < len(b):
        tag, content, end = read(b, i)
        out.append((tag, content, b[i:end])); i = end
    return out

def der_len(n):
    if n < 0x80: return bytes([n])
    k = (n.bit_length() + 7) // 8
    return bytes([0x80 | k]) + n.to_bytes(k, 'big')

def indef(tag, parts):
    return bytes([tag, 0x80]) + b''.join(parts) + b'\0\0'

data = open(sys.argv[1], 'rb').read()
_, ci, _ = read(data, 0)
(oid_t, _, oid), (_, wrapper, _) = children(ci)
(_, sd, _), = children(wrapper)
sd_parts = children(sd)
_, eci, _ = sd_parts[2]
(_, _, e_oid), (_, e_wrap, _) = children(eci)
(_, plist, _), = children(e_wrap)
chunks = [b'\x04' + der_len(len(c)) + c
          for c in (plist[i:i + 1000] for i in range(0, len(plist), 1000))]
econtent = indef(0x24, chunks)
eci_ber = indef(0x30, [e_oid, indef(0xA0, [econtent])])
sd_ber = indef(0x30, [sd_parts[0][2], sd_parts[1][2], eci_ber]
               + [p[2] for p in sd_parts[3:]])
out = indef(0x30, [oid, indef(0xA0, [sd_ber])])
open(sys.argv[2], 'wb').write(out)
```

## P4-07: OpenSSH keys and PEM bundles

Test-only keys made with `ssh-keygen` and OpenSSL 3. Expected facts in
`more_parsers_test.dart` come from `ssh-keygen -lf` and `openssl x509`.

| File | Made with |
|---|---|
| `id_ed25519` | `ssh-keygen -t ed25519 -N '' -C devvault-test@example` |
| `id_ecdsa` | `ssh-keygen -t ecdsa -b 384 -N '' -C devvault-ecdsa` |
| `id_rsa_encrypted` | `ssh-keygen -t rsa -b 3072 -N test-password -C devvault-rsa` (the comment is encrypted with the key) |
| `apns.pem` | an `Apple Push Services: dev.devvault.test` cert (`openssl req -x509`) followed by its PKCS#8 key, as `openssl pkcs12 -nodes` writes it |
| `chain.pem` | a test CA, then an `Apple Distribution: DevVault Test (TESTTEAM01)` leaf it signed (`-set_serial 0x0DEAD5 -days 400`) |
| `encrypted-key.pem` | the `apns.pem` cert followed by `openssl genrsa -aes256 -traditional` output (`Proc-Type: 4,ENCRYPTED`) |
