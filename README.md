# DevVault

A local-first, end-to-end encrypted vault for developer credential files:
Apple `.p8` keys, `.p12` certificates, provisioning profiles, Android
keystores, Firebase / GCP / OAuth JSON, and plain secrets.

DevVault stores each one as a **typed record**: the facts read from the file
(key ID, team, bundle ID, fingerprints, real expiry date) plus the original
file, byte for byte. It syncs through an S3-compatible bucket **you own**
(Cloudflare R2, AWS S3, Backblaze B2, MinIO). There is no DevVault server.

> **The app only shows facts.** Metadata and dates come from the file or from
> you. Nothing is guessed, defaulted or inferred.

Runs on macOS, Windows, Linux, iOS and Android (Flutter + [bc_ui]).

## Status

Under active development. See [`docs/PLAN.md`](docs/PLAN.md) for the full
plan and milestone breakdown, and the Claude WM board (`.taskboard/`) for
progress.

## Build and run

Requirements: Flutter **3.47.5** stable (Dart 3.13).

```sh
flutter pub get
flutter run -d macos          # or windows, linux, an iOS simulator, an Android device
flutter run -d macos --dart-define=START=/vault   # open any route directly
```

Platform notes:

| Platform | Notes |
|---|---|
| macOS 12+ | Sandboxed. Keychain storage (P1) needs a signed build with a development team. |
| iOS 15+ | Face ID unlock (P3). |
| Android 7.0+ (API 24) | App data is excluded from Google backup and device transfer. |
| Windows 10+ | |
| Linux | Install build deps: `sudo apt install ninja-build libgtk-3-dev libsecret-1-dev libsodium-dev` |

## Tests

```sh
flutter analyze
flutter test --exclude-tags golden     # unit + widget tests
flutter test --tags golden             # screenshots (macOS only)
flutter test --tags golden --update-goldens
(cd packages/vault_core && dart test)  # each package has its own tests
```

Golden screenshots live in [`screenshots/`](screenshots), named after the
design frame they implement (`D03-…` desktop, `B2-…` mobile). Fonts render
differently on Linux, so goldens are generated and checked on macOS only.

## Layout

| Path | What lives there |
|---|---|
| `lib/app/` | App widget, theme, router, routes, desktop and mobile shells |
| `lib/core/` | Pure app logic (expiry rules, notification plan, filters) |
| `lib/data/` | Providers (`providers.dart`) and app state |
| `lib/services/` | Platform services: window, device id, keychain, clipboard, files |
| `lib/shared/` | `ui.dart` barrel and shared widgets |
| `lib/features/` | One folder per flow: screens and their widgets |
| `packages/vault_core/` | Pure Dart: crypto, vault format, items, sync engine |
| `packages/cred_parsers/` | Pure Dart: credential file parsers |
| `packages/vault_s3/` | Pure Dart: SigV4 + S3 storage backend |
| `design/` | `DevVault.fig` (OpenPencil) with the Desktop and Mobile bc_ui pages |
| `docs/` | Plan, format spec, ADRs |

## Security model (short version)

- A master password (Argon2id) and a one-time recovery key each wrap a random
  vault key. Every item and file is encrypted with XChaCha20-Poly1305, bound
  to its slot by associated data.
- The storage provider sees encrypted objects with random names. It can see
  how many there are and how big they are, not what's in them.
- Not protected: malware on an unlocked device. Dart can't reliably wipe
  memory, so DevVault limits exposure with auto-lock and clipboard clearing
  instead of claiming otherwise.

Details: `docs/format/SPEC.md` (P0) and [`docs/adr/`](docs/adr).

[bc_ui]: https://pub.dev/packages/bc_ui
