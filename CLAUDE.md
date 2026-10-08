<!-- workflow-manager:begin -->
## Claude WM

This repository is tracked on a Claude WM board. `.taskboard/tasks.json`
is the shared task list: rows with `"requested": true` are work assigned to
you, and you report progress by setting a row's `status` to `in_progress`
when you start and `review` when you open a PR.

Read `.taskboard/README.md` for the full contract, and `.taskboard/example.json`
for a complete valid file, **before** touching `tasks.json`. Nothing in it
is validated: a wrong status, a re-minted `id` or a dropped `tombstones`
key is accepted and quietly means something else. Never create
`tasks.json` yourself — the app writes it.
<!-- workflow-manager:end -->

## Project

DevVault: a local-first, end-to-end encrypted vault for developer credential
files. Flutter app (macOS, Windows, Linux, iOS, Android) on **bc_ui 0.7.0**.
The plan and every sub-task live in `docs/PLAN.md`; board cards are one per
milestone (M0, P0, P1a, P1b, P1c, P2, P3, P4).

### Rules that matter most

- **Facts only.** Show what the file says or what the user typed. Never
  guess, default or infer metadata or dates. `expires_at` is set only from
  the file or explicit user input, and always carries its source.
- **Secrets never leak:** not into logs, exceptions, toasts, `toString()`,
  search indexes or analytics. Copy secrets only through the clipboard guard.
- **Format changes are contract changes.** Anything that touches
  `packages/vault_core` serialization or crypto updates `docs/format/SPEC.md`
  and the test vectors in the same PR.

### Conventions

- Screens import `package:devvault/shared/ui.dart` only (bc_ui, Lucide,
  theme helpers, shared widgets). Desktop screens on the native design
  (N-frames, docs/design/desktop.md) import
  `package:devvault/shared/desktop_ui.dart` instead: controls drawn by each
  OS's kit, colours from `context.desktopColors`, sizes from
  `DesktopMetrics`. Colours come from `context.bcTheme` or
  `context.appColors`; never hard-code a colour, radius or duration.
- Use the `bc-ui` skill and read the component reference before writing a
  bc_ui widget. Don't write props from memory.
- Routes: every path is in `lib/app/routes.dart`. Every route uses
  `pageBuilder` returning a `MaterialPage` (see `lib/app/router.dart`).
- State: flutter_riverpod 3 with hand-written Notifiers. All providers live in
  `lib/data/providers.dart`. Anything that needs I/O is loaded in `main()` and
  passed in with overrides; tests override the same providers
  (`test/test_overrides.dart`).
- Layout: desktop OSes use the three-pane shell (`DesktopShell`), phones use
  `MobileShell`, chosen by `AppLayout`.
- Tests: `test/<topic>_test.dart`; `pumpBC()` for widgets, `testApp()` for
  the whole app; goldens via `shot()` in `test/screenshots/harness.dart`,
  tagged `golden`, named after the design frame (e.g. `D03-vault`).

### Design frames → code

| Frame | Screen | Milestone |
|---|---|---|
| D00 / B1 | Unlock | P1-04 / P3-05 |
| D01 | Create vault: password | P1-02 |
| D02 | Recovery kit | P1-03 |
| D03 / B2 / B3 | Vault: sidebar, list, detail | P1-06…P1-08 / P3-01, P3-02 |
| D04 / B4 | Import | P1-18 / P3-03 |
| D05 | Sync conflict | P2-11 |
| D06 | Expiry dashboard | P4-02 |
| D07 | Settings: sync storage | P2-09 |

### Workflow

- One branch and PR per sub-task: branch `<milestone>/<nn>-<slug>`
  (e.g. `p0/04-aead-envelope`), PR title `P0-04 · …`.
- Before every PR: `dart format`, `flutter analyze` (no issues),
  `flutter test --exclude-tags golden`, `TZ=UTC flutter test --tags golden`, and
  `dart test` in each package.
- Board: a milestone card goes `in_progress` when its first sub-task starts,
  `review` when its last PR is open, and `done` once merged.
