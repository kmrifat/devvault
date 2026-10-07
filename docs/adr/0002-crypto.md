# ADR-0002: Crypto primitives and library

- Status: Accepted (2026-10-07, P0-01)

## Context
The vault has to be readable on five platforms, by a future Go CLI, and
mustn't depend on hand-rolled cryptography. The format contract is
`docs/format/SPEC.md`.

## Decision
- **Library: libsodium through the `sodium` Dart package (v4).**
  - v4 builds libsodium from source with Dart's native-asset build hooks, both
    for `dart test` and for the Flutter app on all five platforms.
  - So `vault_core` uses it directly. There's no `sodium_libs` plugin, no
    system libsodium and no injected crypto adapter needed.
  - Argon2id lives in the package's *sumo* API (`SodiumSumoInit`).
- **Encryption:** XChaCha20-Poly1305-IETF with a random 24-byte nonce per
  write. Random 192-bit nonces are safe across devices that have no
  coordinating server, unlike AES-GCM's 96-bit nonces.
- **AAD:** `vault_id|object_id|object_type|format_version`, built from where
  the object was found. An object copied into another slot fails to decrypt.
- **Password KDF:** Argon2id (ADR-0003).
- **Recovery KEK:** HKDF-SHA256 (libsodium `crypto_kdf_hkdf_sha256`) over the
  256-bit recovery key, salt = vault id, info = `devvault/v1/recovery-kek`.
- **Key fingerprint `vk_id`:** keyed BLAKE2b-256, pinned per device. A replaced
  vault key is detected instead of silently used (SPEC §4.4).
- **Key handling:** keys live in libsodium `SecureKey` memory (locked, wiped on
  dispose) and are disposed on lock. Dart can't reliably zero ordinary heap
  memory, so decrypted records are dropped on lock and secrets are decrypted
  lazily, and the residual risk is documented rather than hidden.

## Consequences
- Builds need a C toolchain: Xcode on Apple platforms, MSVC on Windows, clang
  or gcc on Linux, and the NDK for Android. CI runners have these.
- The first build of a package that uses `sodium` compiles libsodium, which
  takes about a minute. The result is cached afterwards.
