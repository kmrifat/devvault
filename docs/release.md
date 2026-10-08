# Releasing DevVault (P4-09)

`.github/workflows/release.yml` builds the three desktop apps on a
version tag, signs each one whose secrets are set, writes `SHA256SUMS`
and attaches everything to a **draft** GitHub Release. Nothing is
published until someone checks the draft against
[`docs/acceptance/v1.md`](acceptance/v1.md) and presses Publish.

iOS (TestFlight) and Android (Play internal testing) are built by P3-08.

## Cutting a release

1. Bump `version:` in `pubspec.yaml` (e.g. `1.0.0+1`) in a PR and merge it.
2. Tag the merge commit and push the tag:
   ```bash
   git tag -s v1.0.0 -m "DevVault 1.0.0"
   git push origin v1.0.0
   ```
3. Wait for **Release** to finish, open the draft release, check that no
   file ends in `-unsigned`, run through `docs/acceptance/v1.md`, publish.

The workflow can also be run by hand (**Actions › Release › Run
workflow**); without a tag it uploads the files as run artifacts only.
It also runs on pull requests that change it or `tool/release/`, which
exercises the unsigned path.

## Secrets

Set them under **Settings › Secrets and variables › Actions**. A platform
whose secrets are missing still builds, and its file is named
`…-unsigned`.

### macOS: Developer ID + notarization

| Secret | What |
|---|---|
| `MACOS_CERT_P12_BASE64` | A **Developer ID Application** certificate with its private key, exported from Keychain Access as `.p12`, then `base64 -i cert.p12 \| pbcopy`. |
| `MACOS_CERT_PASSWORD` | The password chosen when exporting it. |
| `APPLE_TEAM_ID` | The 10-character Team ID (developer.apple.com › Membership). |
| `APPLE_ID` | The Apple ID that notarizes. |
| `APPLE_APP_PASSWORD` | An app-specific password for that Apple ID (appleid.apple.com › Sign-In and Security). |

`tool/release/macos_sign_notarize.sh` imports the certificate into a
throwaway keychain, signs every framework and dylib and then the app with
the hardened runtime and `macos/Runner/Release.entitlements` (sandbox,
network client, user-selected files), wraps it in a DMG, signs that,
notarizes it with `notarytool`, staples the ticket and checks it with
`spctl`. The keychain and the decoded certificate are deleted afterwards.

### Windows: Authenticode

| Secret | What |
|---|---|
| `WINDOWS_CERT_PFX_BASE64` | A code-signing certificate with its key as `.pfx`, base64 (`[Convert]::ToBase64String([IO.File]::ReadAllBytes('cert.pfx'))`). |
| `WINDOWS_CERT_PASSWORD` | Its password. |

`tool/release/windows_sign.ps1` signs `DevVault.exe` and every DLL with
SHA-256 and a DigiCert RFC 3161 timestamp, then verifies the exe. An OV
certificate builds SmartScreen reputation over time; an EV certificate
is trusted at once but usually lives on a hardware token, which a hosted
runner can't use.

### Linux: detached GPG signature

| Secret | What |
|---|---|
| `LINUX_GPG_PRIVATE_KEY` | An armored private key (`gpg --armor --export-secret-keys <id>`). Publish its public key in the README so users can verify. |
| `LINUX_GPG_PASSPHRASE` | Its passphrase. |

The tarball gets `devvault-linux-x64.tar.gz.asc`. Users check it with
`gpg --verify devvault-linux-x64.tar.gz.asc`, and every file with
`sha256sum -c SHA256SUMS`.
