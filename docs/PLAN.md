# DevVault: build plan, A to Z

This is the working plan for DevVault v1. The product spec is *Plan v1.1* (summarised below). The UI is `design/DevVault.fig`: pages **Desktop · bc_ui** (frames D00–D07) and **Mobile · bc_ui** (B1–B4).

Progress is tracked on the Claude WM board (`.taskboard/tasks.json`) with **one card per milestone**. This document is the detailed breakdown behind those cards. Sub-task IDs (`M0-01`, `P1-18`…) are used in branch names, PR titles and card details.

---

## 1. Product summary

- A local-first Flutter app for macOS, Windows, Linux, iOS and Android. It stores developer credential files as **typed records** and encrypts everything end to end.
- Sync goes through storage the user owns (S3-compatible: AWS S3, Cloudflare R2, Backblaze B2, MinIO). There is no server of ours.
- **Principle: the app only shows facts.** Metadata and dates come from the file itself or from the user. Nothing is guessed, defaulted or inferred.
- **Out of scope for v1:** browser extension/autofill, team sharing, iCloud, web app, Go CLI, revocation checks, and hiding object sizes or counts from the storage provider.

### Decisions already made
| Topic | Decision |
|---|---|
| Hosting / review | Private GitHub repo, one PR per sub-task |
| Board granularity | One card per milestone (8 cards); detail lives here |
| Theme | bc_ui dark + light, `ThemeMode.system`, accent `#0485F7` |
| Default storage suggestion | Cloudflare R2 (no egress fees, conditional writes, `auto` region) |
| Argon2 parallelism | p = 1 (libsodium limitation), see ADR-0003 |
| Still open | Personal tool vs. base of a paid team product (format is ready either way: `vault_type`) |

---

## 2. Architecture

### Repo layout (pub workspace)
```
DevVault/
├─ pubspec.yaml            # app "devvault" + workspace: [packages/*]
├─ lib/                    # Flutter app (see below)
├─ packages/
│  ├─ vault_core/          # pure Dart: crypto, format, model, HLC, store, index, merge, sync engine
│  ├─ cred_parsers/        # pure Dart: .p8 .cer .p12 .mobileprovision .jks firebase gcp oauth
│  └─ vault_s3/            # pure Dart: SigV4 signer + S3 StorageBackend
├─ tools/vectorcheck/      # Go: independent verifier of the format test vectors (seed of the Go CLI)
├─ integration_test/       # 5-platform round-trip
├─ test/                   # app unit/widget/golden tests
├─ docs/ PLAN.md, format/SPEC.md, format/vectors/, adr/, s3-compat.md, acceptance/
├─ design/                 # DevVault.fig + PNG exports
├─ assets/fonts/           # Inter 400/500/600/700, JetBrains Mono 400/500
└─ .github/workflows/      # checks.yml, core-matrix.yml, roundtrip.yml
```
If a workspace root that is also the Flutter app causes tooling trouble, the app moves to `apps/devvault/`. That decision is recorded in ADR-0001.

### App layout (follows invoice-app conventions)
```
lib/
  main.dart                 # init before first frame, ProviderScope(overrides: [...]), START dart-define
  app/   app.dart router.dart routes.dart theme.dart layout.dart desktop_shell.dart mobile_shell.dart lock_gate.dart
  core/  expiry_rules.dart notification_plan.dart vault_tree.dart search_query.dart      # pure logic
  data/  providers.dart (single file) vault_session.dart settings_store.dart filters.dart
  services/ crypto_init keychain biometric_key clipboard_guard idle_lock file_import file_export notifications s3_credentials sync_service window
  shared/ ui.dart (barrel: bc_ui + lucide + app widgets) widgets/{type_icon_tile, mono_text, secret_row, provenance_label, expiry_card, confirm_dialog, pane}
  features/ unlock/ create_vault/ recovery/ vault/ import/ export/ conflicts/ expiry/ settings/ pairing/ apps/
```
- **State:** flutter_riverpod 3 with hand-written Notifiers. Services are providers overridden in `main()` and in tests.
- **Routing:** go_router 18, a `Routes` abstract final class and `rootNavigatorKey`. **Every route uses `pageBuilder` returning a `MaterialPage`**; otherwise go_router falls back to `NoTransitionPage`. Desktop uses a three-pane `StatefulShellRoute` (D03); iOS/Android use a mobile shell with a floating `BCBottomNav` (B2).
- **UI:** bc_ui 0.7.0 only, with colours from `context.bcTheme` and no literal colours. Screens import `shared/ui.dart` only. JetBrains Mono for IDs and fingerprints (`MonoText`). `TypeIconTile` is drawn with the soft status tokens.
- **Dialogs:** D04 and D05 are `showDialog` + `BCDialog`, not routes.

### Packages (versions to re-check at `pub add`)
| Area | Packages |
|---|---|
| App (known good, from invoice-app) | bc_ui ^0.7.0, flutter_riverpod ^3.4, go_router ^18.0, lucide_icons_flutter ^3.1, path_provider, intl, uuid, file_picker ^13, share_plus ^13, local_auth ^3, flutter_local_notifications ^22, timezone, flutter_timezone, pdf, printing |
| App (verify) | flutter_secure_storage ^10, window_manager, desktop_drop / super_drag_and_drop, biometric_storage, qr_flutter, mobile_scanner |
| vault_core | sodium ^4 (libsodium built by native-asset hooks, incl. Argon2id via sumo and HKDF-SHA256), crypto, collection, meta |
| cred_parsers | pointycastle ^4 (ASN.1, PKCS#12 KDF, RC2, 3DES, AES, PBKDF2), xml, crypto, convert |
| vault_s3 | http, xml, crypto (hand-written SigV4; no AWS SDK) |
| Dev | flutter_lints ^6, lints, test, integration_test, flutter_launcher_icons |

### Crypto summary (full detail in `docs/format/SPEC.md`)
- **Keys:**
  - Master password → Argon2id (ops=3, mem=64 MiB, p=1, 16 B salt, params in vault.json) → KEK_pw.
  - Recovery key (256-bit) → HKDF-SHA256 (salt=vault_id, info=`devvault/v1/recovery-kek`) → KEK_rec.
  - Both KEKs wrap a random 256-bit **VK**.
- **Cipher:** XChaCha20-Poly1305-IETF with a random 24 B nonce per write. AAD = `vault_id|object_id|object_type|format_version`.
- **Envelope:** `"DVLT"(4) | format_version u8 | object_type u8 | nonce(24) | ciphertext+tag`.
- **Recovery key encoding:** Crockford base32 plus a 4-character checksum, shown in groups of four (`K7QF-2M9X-…`). The parser is lenient and reports where a typo is.
- **Key handling:** keys are held as sodium `SecureKey` and disposed on lock. Dart cannot zero heap memory, so the risk is reduced (index dropped on lock, secrets decrypted lazily) and documented rather than hidden.

---

## 3. Definition of done (every PR)
1. `flutter analyze --no-fatal-infos` is clean, and `flutter test` plus `dart test` in every package are green in CI.
2. New logic has unit tests. Crypto and format code also has **negative** tests (tampering, AAD swap, wrong key).
3. UI tasks add or update goldens, checked visually against the frame in `design/DevVault.fig`. Sizes: mobile 390×844 @2x, desktop 1440×900.
4. No secret appears in logs, exceptions, toasts, `toString()` or crash output. Tests grep for fixture secrets.
5. SPEC and ADRs are updated whenever the format or a crypto decision changes.
6. Branch name is `<milestone>/<nn>-<slug>` and the PR title is `M0-02 · …`. The board card status follows the contract in `.taskboard/README.md`.

---

## 4. Milestones and sub-tasks
Format: **ID · title** (estimate). **D:** dependencies. **AC:** acceptance criteria.

### M0 · Scaffold: Flutter + bc_ui, workspace, CI
- **M0-01 · Git + GitHub** (0.5d).
  - `git init -b main` and a `.gitignore`.
  - Private repo `kmrifat/devvault` with protected `main` (PR plus green checks).
  - Link the repo in Claude WM.
  - AC: the first commit contains the existing `CLAUDE.md`, `.taskboard/` (its own `.gitignore` respected) and `design/`, unchanged.
- **M0-02 · Flutter app + workspace** (1d). D: M0-01.
  - `flutter create --org com.binarycastle --project-name devvault --platforms macos,windows,linux,ios,android .`
  - `sdk: ^3.13.4`, `workspace:` listing the three package skeletons, each with one smoke test.
  - AC: `flutter pub get` resolves; `flutter run -d macos` works; `dart test` passes in each package; CLAUDE.md is untouched.
- **M0-03 · Platform enablement** (1d). D: M0-02.
  - macOS 11+: sandbox, `files.user-selected.read-write`, `network.client`, keychain access group.
  - iOS 15+: `NSFaceIDUsageDescription`.
  - Android minSdk 24: `FlutterFragmentActivity`, `allowBackup=false`, data-extraction rules exclude everything.
  - Windows/Linux runners: title "DevVault", 1280×800.
  - AC: an empty app builds on all 5 platforms.
- **M0-04 · Theme + fonts** (0.5d). D: M0-02.
  - `AppTheme.dark()/light()` from `BCTheme` with accent `#0485F7`, plus the dark hairline `fieldShadow` (gogarage pattern). `ThemeMode.system`.
  - Inter and JetBrains Mono registered; `AppText.mono`.
  - AC: goldens render Inter; the dark field ring is visible.
- **M0-05 · Router + adaptive shells** (1.5d). D: M0-04.
  - Routes: `/unlock`, `/create`, `/create/recovery-kit`, `/recover`, `/vault` (query `item, app, platform, env, tag, q`), `/vault/item/:id`, `/expiry`, `/settings`, `/settings/sync`, `/settings/security`, `/pair`.
  - Desktop three-pane shell placeholder and mobile bottom-nav shell, selected in `layout.dart`.
  - AC: tests reach every route in both layouts and assert every page is a `MaterialPage`.
- **M0-06 · Shared UI kit** (1d). D: M0-04.
  - `shared/ui.dart` barrel.
  - `TypeIconTile`, `MonoText` (middle ellipsis), `SecretRow` (mask, reveal, copy), `ProvenanceLabel` ("From certificate" / "Set by you" / "Expiry unknown"), `ExpiryCard` stub, `ConfirmDialog`.
  - AC: widget tests plus goldens for every type tile, in dark and light.
- **M0-07 · main + app shell** (0.5d). D: M0-05.
  - `main()` initialises the window (desktop), settings and device id before the first frame.
  - `providers.dart` stubs: clock, deviceId, settingsStore, crypto.
  - Builder: `BCToastProvider` wrapping a `LockGate` placeholder.
  - AC: boots to `/unlock` on every platform; tests can override every service.
- **M0-08 · Test helpers + golden harness** (1d). D: M0-06, M0-07.
  - `test_overrides.dart` and `pumpBC()`.
  - `test/screenshots/harness.dart` copied from invoice-app, with mobile and desktop presets.
  - AC: goldens for both shells are generated deterministically.
- **M0-09 · CI** (1d). D: M0-02, M0-08.
  - `checks.yml` (ubuntu): pub get, libsodium-dev, analyze, flutter test, dart test packages.
  - `core-matrix.yml`: vault_core on macOS, Windows and Ubuntu.
  - `roundtrip.yml`: stub.
  - AC: green on the first PR, including a libsodium smoke test on all three hosts.
- **M0-10 · Docs** (0.5d). D: M0-05.
  - README (build steps, Linux deps).
  - A project section in `CLAUDE.md` **below** the WM block: conventions, the facts-only rule, security rules, and the frame → file map.
  - ADR-0001.
  - AC: a fresh clone can follow the README to green tests.

### P0 · Vault core: crypto, format spec, test vectors
**Gate:** round-trip tests pass on all 5 platforms, and a password change rewrites only `vault.json`.
- **P0-01 · SPEC.md v1** (1.5d).
  - Layout; vault.json schema; envelope; canonical AAD; item/app JSON; HLC encoding; recovery-key encoding; versioning (refuse a higher major version, keep unknown fields); 25 MiB attachment limit; a conformance section for the Go CLI.
  - ADR-0002 and ADR-0003.
- **P0-02 · VaultCrypto on sodium 4** (1d).
  - Interface: random, AEAD, pwhash, hkdf, keyed hash, sha256.
  - `sodium` 4 builds libsodium with native-asset hooks, so the same code runs in `dart test` and in the app (ADR-0002); no loader or sodium_libs needed.
  - A deterministic RNG for vectors only, which cannot be used in release builds.
  - Keys as `SecureKey`.
- **P0-03 · Argon2id + KdfParams** (1d).
  - Defaults ops=3, mem=64 MiB, p=1.
  - Header bounds (mem 8 MiB–1 GiB, ops 1–10) block a memory DoS from a tampered header.
  - Runs in an isolate.
  - AC: RFC 9106 / libsodium vectors pass; the UI isolate isn't blocked; under 1.5 s on a mid-range Android phone.
- **P0-04 · AEAD envelope + AAD** (1d). AC: flipping a bit, changing a header byte, or swapping object_id, object_type, vault_id or version **each** fail.
- **P0-05 · VK + password wrap + vault.json codec** (1d). Canonical (sorted) JSON that keeps unknown fields. AC: round-trip; a wrong password raises a typed `WrongPassword`.
- **P0-06 · Recovery key** (1d). AC: RFC 5869 HKDF vectors pass; a one-character typo is detected and located; the recovery key alone unwraps the VK.
- **P0-07 · Hybrid logical clock** (0.5d). `{wallMs, counter, deviceId}` with sortable string encoding. AC: property tests for monotonicity, total order and receive ≥ both inputs.
- **P0-08 · Item/App model + schema v1** (1.5d).
  - Types: `apple_auth_key`, `apple_certificate`, `provisioning_profile`, `android_keystore`, `firebase_config`, `gcp_service_account`, `oauth_client`, `generic_file`, `generic_secret`, `app`.
  - A secret-field registry; invariant `expires_at ⇒ expires_source ∈ {file, user}`; a reserved `conflict` slot.
- **P0-09 · Local file store** (1d). Atomic write (temp file, fsync, rename), write-once blobs, an injectable write log. AC: a write killed halfway never leaves a partial file (including on Windows).
- **P0-10 · Vault facade** (1.5d). `create`, `unlock`, `unlockWithRecovery`, `lock`, `putItem` (bumps HLC rev), `addAttachment` (sha256, random-UUID blob), `readAttachment` (verifies sha256), and `deleteItem` (writes a tombstone).
- **P0-11 · In-memory index** (1d).
  - Indexes by id, the App→Platform→Env tree, tags and expiry order.
  - Search tokens come from **non-secret** fields only.
  - A quarantine list for objects that won't decrypt.
  - AC: 1,000 items unlock in under 1 s on desktop; a test shows secrets never match a search.
- **P0-12 · Password change + recovery reset** (0.5d). AC: the write log shows exactly one write, to `vault.json`.
- **P0-13 · VK rotation** (1.5d).
  - Re-encrypt items and tombstones; blobs go to new UUIDs.
  - vault.json is written last.
  - A resumable journal.
  - AC: a crash at any step either resumes or leaves the vault unlocking with the old VK.
- **P0-14 · Test vectors + Go verifier** (1.5d). `tool/gen_vectors.dart` plus a `mini-vault/` fixture; `tools/vectorcheck` in Go (x/crypto). AC: Go and Dart agree byte for byte, and this runs in CI.
- **P0-15 · 5-platform round-trip** (1.5d). An `integration_test` run on macOS, iOS sim, Windows, Linux (xvfb) and Android emulator, with an Argon2 benchmark per platform and a vault created on macOS opened on Windows. **This is the gate.**

### P1a · Desktop: unlock, vault three-pane, items, lock
- **P1-01 · Vault session + lock-aware routing** (1d). States: noVault, locked, unlocking, unlocked. Redirects send noVault to `/create` and locked to `/unlock`, and a deep link resumes after unlock.
- **P1-02 · D01 Create password** (1d). Two `BCPasswordInput`s, at least 12 characters, a strength hint, Argon2 progress. The password is not kept after use.
- **P1-03 · D02 Recovery kit** (1d). Grouped key in mono; copy via the clipboard guard and Save .txt. The user must confirm before continuing, and the key is shown only once.
- **P1-04 · D00 Unlock** (0.5d). Inline error, backoff after 5 failures, a recovery link.
- **P1-05 · Recovery unlock + reset** (0.5d). AC: the recovery key alone can set a new password (end-to-end widget test).
- **P1-06 · D03 Sidebar** (1d). `BCNavDrawer`: All, Expiring, Expired, Conflicts, the App→Platform→Env tree with counts, Tags, and Quarantine (only if non-empty).
- **P1-07 · D03 Item list** (1d). `BCListGroup` rows with `TypeIconTile`; the expiry chip appears only when an expiry exists; sort; arrow-key navigation; `BCEmptyState`; smooth scrolling with 1k rows.
- **P1-08 · D03 Detail pane** (1.5d).
  - Expiry `BCCard` with a `ProvenanceLabel`, or no card when there is no expiry.
  - Fields with `SecretRow` / `MonoText`; attachment actions; notes; meta.
  - AC: matches the D03 golden; every fact shown traces to a field or file.
- **P1-09 · Item create/edit/delete** (1.5d). A form driven by the type registry. User-set expiry gives `expires_source=user` and "Set by you". Delete asks for confirmation and writes a tombstone.
- **P1-10 · Apps management** (0.5d). CRUD for apps (name, bundle_ids, package_names, icon); assign items; renaming updates the tree.
- **P1-20 · Search** (0.5d). `BCSearchField`, ⌘F, and a ⌘K quick-open; it combines with sidebar filters. AC: secrets are not searchable; results within 16 ms for 1k items.
- **P1-21 · Clipboard guard** (0.5d). Clears after 30 s (configurable) **only if the clipboard is unchanged**; also on lock and quit. A "clears in 30s" toast.
- **P1-22 · Auto-lock** (1d). Idle timer (default 5 min), plus sleep/screen lock and ⌘L. Locking disposes keys, drops the index and clears the clipboard. AC: nothing from the vault can be reached through providers after lock.
- **P1-23 · Settings (general/security)** (1d). Theme, auto-lock, clipboard timeout, change password (verifies that only vault.json is written), show vault id, reveal folder.

### P1b · Parsers, import (D04) and byte-exact export
- **P1-11 · Parser framework** (1d). `ParseResult{type, facts[source=file], secretsNeeded, expiresAt?, warnings}`. Detection uses extension, filename and magic bytes; unknown input or any exception becomes `generic_file`; runs in an isolate. AC: fuzzing never throws.
- **P1-12 · .p8** (0.5d). PKCS#8 EC P-256; Key ID only from the `AuthKey_XXXXXXXXXX.p8` filename; no expiry.
- **P1-13 · X.509 / .cer** (1d). DER/PEM; CN, OU (team), serial, validity dates, SHA-1/SHA-256; Apple cert type from the CN prefix and Apple OIDs. AC: fingerprints equal `openssl x509 -fingerprint`.
- **P1-14 · PKCS#12** (2d). MAC check; PBES2/AES plus legacy RC2-40/3DES cert bags; the leaf goes to X.509. A wrong password gives `needsPassword`. Fixtures: openssl default and `-legacy`.
- **P1-15 · .mobileprovision** (1d). CMS → plist. Name, UUID, team, bundle id, ExpirationDate. Type comes from ProvisionsAllDevices, ProvisionedDevices and get-task-allow. Developer certificate SHA-1s are read. **The signature is not verified, and the UI never claims it is.**
- **P1-16 · Android keystores** (2d).
  - JKS (`FEEDFEED`) and JCEKS (`CECECECE`): aliases, cert chains, store-password integrity check, key-password check.
  - PKCS12 keystores go to P1-14.
  - AC: fingerprints equal `keytool -list -v`; store and key password errors are reported separately; certs are listed even without a password.
- **P1-17 · Firebase / GCP / OAuth** (1d). `google-services.json` (multi-client: the user picks one), `GoogleService-Info.plist`, service-account JSON (`private_key` is secret), `client_secret_*.json`.
- **P1-18 · D04 Import dialog** (2d).
  - Entry points: drop onto the window, ⌘I or the toolbar.
  - Parsed facts are read-only and marked "From file".
  - Required user fields (e.g. Team ID `[A-Z0-9]{10}`), purpose `BCToggleButtonGroup`, password prompts, App/Platform/Env `BCSelect`.
  - A duplicate sha256 offers Open existing, Replace or Import anyway.
  - AC: matches the D04 golden; every fixture imports; failures import as Generic File with no invented fields.
- **P1-19 · Export** (1d). Save-as with the original filename, plus optional drag-out. The sha256 is checked before writing. AC: exported bytes match the imported sha256 for every fixture, including under the macOS sandbox.

### P1c · macOS dogfood gate (2 weeks)
- **P1-24 · Signed + notarized macOS build** (1d + 14 days). Dogfood checklist: create, import every type, export, search, auto-lock, clipboard. Bugs are triaged as they come.

### P2 · Sync over S3 (R2 default), conflicts, Windows/Linux
- **P2-01 · StorageBackend + fakes** (1d).
  - Interface: `list/get/put(ifMatch|ifNoneMatchAny)/delete`, with typed errors.
  - `MemoryBackend` (fault injection) and `LocalDirBackend`.
  - A shared conformance suite every backend must pass.
- **P2-02 · SigV4 signer** (1d). Path-style and virtual-host addressing; region `auto` for R2. AC: the AWS SigV4 test suite passes.
- **P2-03 · S3Backend** (1.5d).
  - ListObjectsV2 with paging; conditional PUT/DELETE.
  - Error mapping: 412 and 409 retried; 403/404; 429/5xx with backoff.
  - Request log without bodies or credentials.
  - AC: the conformance suite passes against MinIO in CI.
- **P2-04 · Capability probe** (1d). If-None-Match and If-Match probes; a write-then-verify fallback with a visible warning. `docs/s3-compat.md` covers AWS S3, R2, B2 and MinIO.
- **P2-05 · Device sync state** (0.5d). `.sync/state.json` (etag, rev, dirty set) and encrypted base snapshots for 3-way merge.
- **P2-06 · Merge engine** (2d).
  - Field-level 3-way merge. When both sides change the same field, the item is flagged as a conflict and both values are kept. An edit beats a delete. Attachments are unioned.
  - ADR-0004.
  - AC: a 3-device random-edit property test where **no secret is ever dropped**.
- **P2-07 · Sync engine** (2d). Pull, then push (blobs, then items with If-Match, then tombstones); a 412 triggers pull, merge and retry, at most 5 times; vault.json is written with a conditional write. AC: two devices converge; a password change shows a single PUT, of `vault.json`.
- **P2-08 · Triggers + status** (1d). Sync on unlock, 2 s after an edit, every 60 s while focused, and ⌘R. A status line shows synced, syncing, offline or error.
- **P2-09 · D07 Sync settings** (1.5d). Provider `BCRadioGroup` with **R2 preselected**; endpoint, region, bucket, prefix, keys and path-style; test connection runs the probe; credentials go to the OS keychain under `s3:<vault_id>`, never into the vault. AC: matches the D07 golden; a grep test finds no credentials in any vault file.
- **P2-10 · Join an existing vault** (1d). On D01, "I have a vault in S3": pick a `vault.json`, unlock, then a full pull.
- **P2-11 · D05 Conflict dialog** (1.5d). Conflict badge, sidebar section and banner. Fields side by side, a `BCRadio` per field, and "Keep both". Nothing is resolved without an explicit choice.
- **P2-12 · Blob GC** (0.5d). A blob is deleted only if nothing references it (items, conflicts, recent tombstones) and it is more than 30 days old. Runs once a day; supports a dry run.
- **P2-13 · Windows + Linux bring-up** (2d). Credential Manager on Windows and libsecret on Linux, with a degraded mode when no keyring is available; Ctrl shortcuts; packaging (MSIX/zip, AppImage/tarball).
- **P2-14 · P2 gate** (1d). An acceptance run against MinIO and R2, written up in `docs/acceptance/p2.md`:
- **P2-15 · Adopt a rotated key** (1d). After a rotation on another device (P4-08), sync stops; the master password must open the bucket's new `vault.json` (SPEC §4.4). Unsynced local edits are rescued with the old key, merged on top of the bucket's vault and pushed; the new copy is built aside and swapped in only when complete.
  - the S3 request log for a password change;
  - objects unreadable without the VK;
  - AAD swap test (copy `items/a.enc` over `b.enc`);
  - concurrent offline edits.

### P3 · Mobile iOS + Android
- **P3-01 · B2 Vault list** (1.5d). `BCSliverAppHeader`, `BCSearchField`, type-group `BCTabs`, grouped `BCListGroup`, floating `BCBottomNav`, pull to refresh.
- **P3-02 · B3 Detail + share export** (1d). The decrypted temp file goes to `share_plus` and is deleted afterwards; the cache is wiped at launch; "Save to Files".
- **P3-03 · B4 Import sheet + Open in** (1.5d). Pick a file or paste a secret, using the same parse pipeline. iOS document types/UTIs and Android VIEW/SEND intents; a file is held until unlock.
- **P3-04 · Biometric-bound VK** (2d). Keychain `SecAccessControl .biometryCurrentSet` / Keystore `setUserAuthenticationRequired` (BIOMETRIC_STRONG). The key is invalidated when enrolment changes and removed on password change or rotation. Also covers macOS Touch ID.
- **P3-05 · B1 Face ID unlock** (0.5d). Automatic prompt, password fallback.
- **P3-06 · Mobile privacy** (1d). Lock in the background; blur in the iOS app switcher and `FLAG_SECURE` on Android; sensitive clipboard (iOS `localOnly` + expiration, Android `EXTRA_IS_SENSITIVE`).
- **P3-07 · Mobile sync** (1d). On unlock, resume, edit and pull. **No background sync.** D07 reflowed for mobile.
- **P3-08 · P3 gate** (1d). TestFlight and Play internal testing; device matrix (iOS 15 and latest, Android API 24 and latest); same password on all 5 platforms. Written up in `docs/acceptance/p3.md`.

### P4 · Polish: expiry + notifications, recovery PDF, QR pairing, v1 release
- **P4-01 · Expiry rules** (0.5d). Pure function with a 30-day window; uses only `expires_at`; status carries the source. Tested across time zones and DST.
- **P4-02 · D06 Expiry dashboard** (1d). Groups: Expired, within 30 days, Later, and No expiry (count only). Desktop D06 plus the mobile Expiry tab.
- **P4-03 · Notifications (≤2 per item)** (1.5d). Two notifications: on entering the window and on the expiry day, both at 09:00 local. Deterministic ids and a delivered ledger. Rescheduling is debounced. AC: provably at most 2 per item, across restarts and edits.
- **P4-04 · Import replacement** (1d). Keeps the item id and tags, swaps the file, sets the new expiry and resets the ledger, so the warning state clears.
- **P4-05 · Recovery kit PDF/print** (1d). Requires re-authentication; nothing is cached except the file the user saves.
- **P4-06 · QR pairing** (2d). The QR holds the S3 config plus credentials encrypted under Argon2id(an 8-character code shown next to it), and expires after 10 minutes. **The VK is never in the QR**; the master password is still required.
- **P4-07 · More parsers** (1.5d). PEM bundles, OpenSSH private keys (fingerprint from `ssh-keygen -lf`), APNs `.pem`.
- **P4-08 · Rotation UI + a11y + icon** (1d). Rotate the vault key from Settings → Security; accessibility pass; app icon.
- **P4-09 · v1 acceptance + release** (1.5d). `docs/acceptance/v1.md` maps every v1 criterion to a test; signed builds for all 5 platforms.

**Later:** iCloud backend, Go CLI (grows out of `tools/vectorcheck`), team vaults (`vault_type` reserved, per-vault VK wrapped to members' public keys).

**Critical path:** M0-02 → P0-02…P0-05 → P0-10 → P0-11 → P1-01 → P1-08 → P1-18 → P2-07 → P2-14 → P3-07 → P4-09.

---

## 5. Risks
| Risk | Mitigation |
|---|---|
| JKS/JCEKS parsing in Dart (no library, proprietary KeyProtector) | Test-first against keytool fixtures. Certs in JKS are plaintext, so fingerprints and expiry work without a password. JCEKS key-password check is optional. |
| libsodium on 5 platforms (sodium 4 compiles it with build hooks: needs a C toolchain incl. Android NDK; Argon2id in isolates) | P0-02 and P0-15 early; `VaultCrypto` interface keeps call sites independent of the library; vault_core CI on macOS, Windows and Linux. |
| Argon2 p=1 vs. planned p=4 | ADR-0003. Params live in vault.json so they can be raised later; matches Go `argon2.IDKey(threads=1)`. |
| macOS sandbox + keychain (`-34018` unsigned, drag-out) | Entitlements in M0-03; dogfood signed builds only; Save-as is the guaranteed export path. |
| S3 conditional-write variance (AWS 409, B2/MinIO support) | Capability probe, write-then-verify fallback with a warning, MinIO conformance in CI, field merge as a second line of defence. |
| Dart can't zero memory | `SecureKey` for VK/KEKs; drop the index on lock; decrypt secrets lazily on reveal; documented in SPEC/README. |
| Linux without a Secret Service; Windows Credential Manager limits | Detect and degrade (ask every session); stored items are small. |
| Biometrics (local_auth is only a UI prompt) | Bind the VK through keychain/keystore access control; invalidate on enrolment change. |
| Desktop notifications maturity | A pure notification plan plus a ledger make the ≤2 rule testable without the OS. |
| PKCS#12 variants (legacy RC2, empty vs. null password) | Multiple fixtures; try both; fall back to Generic File plus the stored password. |
| Taskboard integrity | Append-only rows, fresh UUIDs, atomic rename, keep `tombstones`. |
