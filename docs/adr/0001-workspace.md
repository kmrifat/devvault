# ADR-0001: Pub workspace with the app at the root

- Status: Accepted (2026-10-07)

## Context
The vault format is a contract that has to outlive the Flutter app. A future Go CLI and other clients will read the same files. Crypto and format code should be testable with plain `dart test` on every desktop OS, with no Flutter engine. The parsers and the S3 client carry heavier dependencies and change at a different pace from the core.

## Decision
Use one repository and one Dart pub workspace (Dart 3.6 or later):
- The Flutter app `devvault` lives at the repo root, so `flutter run`, `flutter test`, CI and the `.taskboard`/`CLAUDE.md` paths stay conventional.
- `packages/vault_core` is pure Dart: crypto, format, model, HLC, store, index, merge, sync engine and the `StorageBackend` interface.
- `packages/cred_parsers` is pure Dart: the credential file parsers.
- `packages/vault_s3` is pure Dart: SigV4 signing and the S3 backend.

If tooling has trouble with a workspace root that is also a Flutter app, the app moves to `apps/devvault/` and this ADR is updated.

## Consequences
- vault_core cannot import Flutter. Native crypto comes in through a `VaultCrypto` interface (see ADR-0002).
- Each package has its own `analysis_options.yaml` and tests, and CI runs `dart test` per package.
