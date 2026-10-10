# ADR-0007: Desktop updates: an opt-in check and signed in-place updates

- Status: Accepted (2026-10-10)

## Context

DevVault is open source (`kmrifat/devvault`, public). A `v*` tag builds
signed desktop files and attaches them to a draft GitHub Release
(`docs/release.md`). iOS and Android update through their stores. On the
desktop nothing tells a user that a newer version exists, so they stay on
whatever they downloaded until they go and look.

Two facts shape the answer:

1. **The update channel can read every vault.** Whoever can ship an update
   to a user's machine can replace the app that holds the master password.
   HTTPS proves where the bytes came from, not who made them. Every update
   that installs itself has to carry a signature from a key only the
   release pipeline holds, and the installer has to check it.
2. **A check is a network call the app does not make today.** DevVault
   talks only to the bucket the user configured ("There is no DevVault
   server", CHANGELOG). Asking GitHub for the latest release tells GitHub
   the user's IP address and that they run DevVault. The user should
   decide whether that happens, as with *Allow AI agents*.

Each desktop OS has its own updater, and each install format suits a
different one:

| File | Updater that fits it |
|---|---|
| `DevVault-macos.dmg` | Sparkle 2 (EdDSA-signed appcast; also checks the Developer ID) |
| `devvault-windows-x64.msix` | Windows App Installer (`.appinstaller` file; the OS checks the MSIX signature and publisher) |
| `devvault-windows-x64.zip` | None in-app. Replacing files of a running exe is fragile |
| `devvault-linux-x64.AppImage` | AppImage update information + zsync (AppImageUpdate, Gear Lever, AppImageLauncher) |
| `devvault-linux-x64.tar.gz` | None in-app |

## Decision

### 1. One setting, off until the user answers

*Settings → General → Check for updates* (desktop only). It starts
**unset**. After the first unlock on a desktop build, a one-time banner
asks: "Check GitHub for new versions of DevVault once a day?" with *Check
daily* and *Not now*. Until the user picks *Check daily* the app makes no
update request of any kind, including Sparkle's. *Not now* stores `off`,
and the banner does not return; the setting stays in Settings.

When it is on, the app checks at launch if the last successful check was
more than 24 hours ago, and on *Check now* in Settings. There is no
background check while the app is closed.

The setting is local to the device (`AppSettings`), never synced: one
machine's choice says nothing about another's.

### 2. The check itself (all desktops)

`GET https://api.github.com/repos/kmrifat/devvault/releases/latest` with
`Accept: application/vnd.github+json` and `User-Agent: DevVault`. No
version, device id, vault id or cookie is sent. `releases/latest` never
returns drafts or pre-releases, so a release is visible only after a
person presses Publish, as `docs/release.md` already requires.

The response is **untrusted data**:

- `tag_name` must match `^v(\d+)\.(\d+)\.(\d+)$`, or the result is
  discarded. It is compared to the running version (`version:` in
  `pubspec.yaml`, compiled in) as three integers.
- The release page is opened at a URL the app builds itself,
  `https://github.com/kmrifat/devvault/releases/tag/<tag>`, never a URL
  taken from the response.
- The notes are shown as plain text, without links that open anything.
- Facts only: the app shows the version and `published_at` as GitHub
  returns them, and "Last checked <time>" only after a check succeeded.
  A failed check shows "Couldn't check for updates" with the time; it
  never says "up to date".

On its own this is **notify-only**: a banner with *View release*. The
user downloads and checks the file against `SHA256SUMS` and the `.asc`
signatures as today. This is the whole update path for the Windows zip
and the Linux tarball.

### 3. macOS: Sparkle 2

- Sparkle 2 (the current release, pinned), driven by the setting above:
  `automaticallyChecksForUpdates` follows it, and `SUEnableAutomaticChecks`
  is `NO` in `Info.plist` so Sparkle never shows its own permission prompt.
  On macOS Sparkle **replaces** the check in §2 (both read the same
  release; one network request is enough).
- Sparkle checks two signatures before installing: the **EdDSA (Ed25519)**
  signature in the appcast, and that the new app is signed by the same
  Developer ID team as the running one. The public key is
  `SUPublicEDKey` in `Info.plist`; the private key is the CI secret
  `SPARKLE_ED_PRIVATE_KEY` and a copy kept offline. It is never on a
  developer machine's disk otherwise.
- **Sandbox:** the app is sandboxed (ADR-0006, `Release.entitlements`).
  Sparkle's installer then runs through its XPC launcher service:
  `SUEnableInstallerLauncherService = YES`, plus the
  `temporary-exception.mach-lookup.global-name` entitlement for
  `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` and `-spki`. Downloads use the
  app's existing `network.client`.
- **Signing:** `macos_sign_notarize.sh` signs Sparkle's nested code
  (`Autoupdate`, `Updater.app`, the XPC services) inside-out with the
  Developer ID and the hardened runtime before the app, as it already
  does for `devvault-mcp`. No `--deep`.
- **Integration:** the `auto_updater` plugin if it can be configured for
  the sandboxed launcher; otherwise a small method channel in
  `macos/Runner` that calls `SPUStandardUpdaterController`. P6-04
  decides, and either way all of it sits behind one `Updater` interface
  in `lib/services/updater.dart`.
- The update archive is the notarized DMG that the release already
  builds. `release.yml` runs `sign_update` on it and writes `appcast.xml`
  (one item: version, `published_at`, length, `sparkle:edSignature`,
  minimum macOS 12, and a link to the release page for notes).

### 4. Windows: App Installer for the MSIX

- `release.yml` writes `DevVault.appinstaller`. Its own `Uri` is the
  stable feed URL (§6); `MainPackage` points at that tag's
  `devvault-windows-x64.msix`. It declares **no** `OnLaunch` or
  background checks, so Windows does not check behind the user's back.
- The running app, when the setting is on and it was installed through
  the `.appinstaller`, calls `Package.Current.CheckUpdateAvailabilityAsync()`
  through a method channel in `windows/runner`. If an update exists, the
  banner offers *Restart and update*, which calls
  `PackageManager.AddPackageByAppInstallerFileAsync(feed,
  ForceTargetAppShutdown)`. When the app was installed from the bare
  `.msix` or the zip, it falls back to the notify-only check in §2.
- Windows checks the MSIX signature and refuses an update whose
  publisher differs from the installed package. **A renewed
  certificate must keep the same subject**, or every installed copy is
  stranded. This goes in `docs/release.md › Windows`.
- WinSparkle for the zip is rejected: overwriting a running exe and its
  DLLs from inside it is the fragile path, and the MSIX exists for this.

### 5. Linux: AppImage update information

- `linux_appimage.sh` passes
  `-u "gh-releases-zsync|kmrifat|devvault|latest|devvault-linux-x64.AppImage.zsync"`
  to `appimagetool`, which also writes the `.zsync` file; `release.yml`
  uploads it with the AppImage.
- The AppImage keeps its detached `.asc`. Embedding a GPG signature
  (`appimagetool --sign`) so AppImageUpdate can check it is deferred
  until the Linux key exists to test it with: AppImageUpdate only
  compares embedded signatures when the old and the new AppImage both
  carry one from the same key, so the first signed release starts that
  chain.
- The app does not update itself on Linux. External tools pick up the
  update information if the user runs one; inside the app, §2 applies.

### 6. Where the feed files live

`appcast.xml`, `DevVault.appinstaller` and the `.zsync` are attached to
the release by `release.yml`, next to the files they describe, so they are
reviewed with the draft. The stable URL is
`https://github.com/kmrifat/devvault/releases/latest/download/<file>`,
which, like the API, ignores drafts and pre-releases: publishing the draft
is what ships the update. If the P6-05 spike shows that App Installer does
not follow GitHub's redirect for `releases/latest/download`, the
`.appinstaller` is published to GitHub Pages by a workflow on
`release: published` instead, and only for Windows.

### 7. Package managers

Package managers update DevVault on their own schedule and under the
user's control, which fits an open-source app better than anything we
run. They are listed in order of effort:

- **Homebrew cask** in our tap (`kmrifat/homebrew-tap`) until the cask
  qualifies for `homebrew/cask`. `auto_updates true`, because Sparkle
  updates the app.
- **winget**: a manifest for the MSIX, submitted to `microsoft/winget-pkgs`
  by `wingetcreate` on `release: published`.
- **Flathub** (later): builds from source in Flathub's infrastructure; the
  keyring goes through the Secret portal. It is a separate project because
  of the build (libsodium, Flutter in flatpak-builder) and the sandbox.

### 8. Out of scope

- Phones: the App Store and Play update the app. No in-app check.
- Beta or nightly channels. `releases/latest` skips pre-releases; a
  channel would be a second appcast and a setting, if it is ever wanted.
- Delta updates beyond what zsync gives for free.
- Forced or silent updates. Every install is started by the user.

## Consequences

- Two new long-lived signing secrets: the Sparkle Ed25519 key and (already
  planned) the Windows certificate, whose subject must not change. A lost
  Sparkle key can be replaced only through Sparkle's key rotation, which
  needs an update signed by the same Developer ID team, so the offline
  copy matters.
- `release.yml` grows a feed step per platform, and its draft now carries
  `appcast.xml`, `DevVault.appinstaller` and a `.zsync`. The release
  checklist in `docs/release.md` checks them before Publish.
- An update check becomes the second kind of network traffic. The README,
  CHANGELOG and Settings say exactly what it sends and to whom.
- The README's *Security model* section gains the update channel: who
  holds which key, and what each OS verifies before installing.
