# Releasing DevVault (P4-09)

`.github/workflows/release.yml` builds the three desktop apps on a
version tag, signs each one whose secrets are set, writes `SHA256SUMS`
and attaches everything to a **draft** GitHub Release. Nothing is
published until someone checks the draft against
[`docs/acceptance/v1.md`](acceptance/v1.md) and presses Publish.

The phones go to their stores from the same tag (P3-08): iOS to
TestFlight, Android to Play's internal testing track. Their builds aren't
attached to the GitHub Release.

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
It also runs on pull requests that change it, `tool/release/` or
`pubspec.yaml`, which exercises the unsigned path.

Each tag gives these desktop files:

| Platform | Files |
|---|---|
| macOS | `DevVault-macos.dmg` (notarized) |
| Windows | `devvault-windows-x64.zip` (signed exe and DLLs), `devvault-windows-x64.msix` |
| Linux | `devvault-linux-x64.tar.gz`, `devvault-linux-x64.AppImage`, each with a `.asc` signature |

## The agent helper (P5-09)

The macOS build compiles `devvault-mcp` (`packages/devvault_mcp`) and embeds
it at `DevVault.app/Contents/Helpers/devvault-mcp` (Xcode phase *Embed
devvault-mcp*, `tool/build_mcp_helper.sh`).
- **Signing:** it is signed like the app, with the hardened runtime and
  `macos/Runner/Helper.entitlements`, and is not sandboxed (ADR-0006).
  `tool/release/macos_sign_notarize.sh` re-signs it with the Developer ID
  before the app.
- **Docs:** setup for users is in `docs/agent/USING.md`.

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

`tool/release/windows_msix.ps1` then packages the signed build as an MSIX
with the `msix` package (`msix_config` in `pubspec.yaml`), signed with the
same certificate; the certificate's subject becomes the MSIX publisher.
Windows installs a signed MSIX only when it trusts that certificate.

### Linux: detached GPG signature

| Secret | What |
|---|---|
| `LINUX_GPG_PRIVATE_KEY` | An armored private key (`gpg --armor --export-secret-keys <id>`). Publish its public key in the README so users can verify. |
| `LINUX_GPG_PASSPHRASE` | Its passphrase. |

The tarball and the AppImage each get a `.asc` signature
(`devvault-linux-x64.tar.gz.asc`, `devvault-linux-x64.AppImage.asc`).
Users check them with `gpg --verify <file>.asc`, and every file with
`sha256sum -c SHA256SUMS`.

`tool/release/linux_appimage.sh` builds the AppImage from the release
bundle with `appimagetool`, which is pinned to 1.9.1 and checked against
its SHA-256. Like the tarball, it uses the host's GTK 3 and libsecret.

### iOS: TestFlight

| Secret | What |
|---|---|
| `APPLE_TEAM_ID` | The same Team ID as macOS. |
| `IOS_DIST_CERT_P12_BASE64` | An **Apple Distribution** certificate with its private key, exported as `.p12`, base64. |
| `IOS_DIST_CERT_PASSWORD` | The password chosen when exporting it. |
| `APP_STORE_CONNECT_KEY_ID` | An App Store Connect API key (Users and Access › Integrations › App Store Connect API), role **App Manager** or higher. |
| `APP_STORE_CONNECT_ISSUER_ID` | The issuer ID shown above the keys. |
| `APP_STORE_CONNECT_KEY_P8_BASE64` | The key's `AuthKey_<id>.p8`, base64. It can be downloaded only once. |

Before the first upload, create the app in App Store Connect with bundle
ID `com.binarycastle.devvault`, and register that bundle ID with Face ID
in Certificates, Identifiers & Profiles.

`tool/release/ios_testflight.sh` imports the certificate into a throwaway
keychain, archives with automatic signing (Xcode fetches or creates the
App Store profile through the API key) and exports with
`destination: upload`, which sends the build to App Store Connect. It
appears in TestFlight once Apple has processed it; add testers there.
Bump the build number (`+N` in `pubspec.yaml`) for every upload.

### Android: Play internal testing

| Secret | What |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The **upload** keystore (`keytool -genkeypair -keystore upload.jks -alias upload -keyalg RSA -keysize 4096 -validity 10000`), base64. Keep a copy offline. |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password. |
| `ANDROID_KEY_ALIAS` | The key's alias (`upload` above). |
| `ANDROID_KEY_PASSWORD` | The key's password. |
| `PLAY_SERVICE_ACCOUNT_JSON` | A Google Cloud service account's JSON key, invited in Play Console › Users and permissions with **Release to testing tracks** for DevVault. |

Play can't create an app over the API: create DevVault in Play Console,
turn on Play App Signing, and upload the first bundle by hand (a signed
`devvault-android.aab` from a run of this workflow). After that, every tag
uploads to the internal testing track as a completed release.

`android/app/build.gradle.kts` signs release builds with the upload key
from `ANDROID_KEYSTORE_PATH` and the variables above, or from
`android/key.properties` on a developer's machine (`storeFile`,
`storePassword`, `keyAlias`, `keyPassword`; git-ignored). Without either it
keeps the debug key, and the workflow names the bundle `-unsigned`.
