# ADR-0002: Crypto primitives and library

- Status: Proposed (decided in P0-01)

## Decision (draft)
- **Library:** libsodium. vault_core uses the pure-Dart `sodium` FFI package; the app injects a `sodium_libs` instance. No hand-written primitives.
- **AEAD:** XChaCha20-Poly1305-IETF with a random 24-byte nonce per write. Random 192-bit nonces carry no reuse risk across devices that have no coordinating server.
- **AAD:** `vault_id|object_id|object_type|format_version`, which binds every ciphertext to its slot.
- **Password KDF:** Argon2id. Parameters are stored in `vault.json`; see ADR-0003.
- **Recovery KEK:** HKDF-SHA256 (RFC 5869) over the 256-bit recovery key, with salt = vault_id and info = `devvault/v1/recovery-kek`.
- **Key handling:** keys are held in sodium `SecureKey` and disposed on lock. Dart cannot reliably zero heap memory, so we mitigate (auto-lock, clipboard clear, dropping the index) rather than claim otherwise.
