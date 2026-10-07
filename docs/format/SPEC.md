# DevVault vault format, version 1

Status: **v1, in development**. This document is the contract between the
DevVault app (`packages/vault_core`), the future Go CLI and any other client.
A change to anything here is a format change: it needs a SPEC update and new
test vectors (`docs/format/vectors/`) in the same PR.

The key words MUST, MUST NOT, SHOULD and MAY are used as in RFC 2119.

---

## 1. Goals and threat model

A vault holds a single user's developer credentials: typed records ("items")
and the original files they came from ("blobs"). The same layout is used on
local disk and in the user's S3-compatible bucket.

**Protects against:**
- the storage provider;
- a leaked bucket, or stolen S3 credentials;
- a stolen, locked device.

Without the master password or the recovery key, no item, field, file name or
file content can be read.

**Detects:**
- any modified ciphertext, header or associated data;
- an object moved into another object's slot (AAD binding);
- a wholesale replacement of the vault key, via the device-pinned key
  fingerprint (§4.4).

**Does not protect against:**
- Malware on an unlocked device. Dart cannot reliably zero memory, so
  clients limit exposure (auto-lock, clipboard clearing, dropping decrypted
  state on lock) rather than claim otherwise.
- **Metadata leaks:** the provider sees the number of objects, their sizes,
  when they change, and the vault id.
- Rollback of a single object to an older, still-valid version by someone
  with bucket write access. Sync detects it as a stale write (§7); it is not
  cryptographically prevented in v1.

---

## 2. Primitives

All primitives come from libsodium 1.0.20 or later. Clients MUST NOT
substitute their own implementations of these algorithms.

| Purpose | Primitive | libsodium API |
|---|---|---|
| Password KDF | Argon2id v1.3 | `crypto_pwhash` with `ALG_ARGON2ID13` |
| Recovery KDF | HKDF-SHA256 (RFC 5869) | `crypto_kdf_hkdf_sha256_extract` / `_expand` |
| Encryption | XChaCha20-Poly1305-IETF | `crypto_aead_xchacha20poly1305_ietf_*` |
| Key fingerprint | BLAKE2b-256, keyed | `crypto_generichash` |
| File integrity | SHA-256 | (any implementation) |
| Randomness | OS CSPRNG | `randombytes_buf` |

Sizes:
- keys are 32 bytes;
- nonces are 24 bytes, freshly random for every encryption;
- the AEAD tag is 16 bytes;
- the Argon2id salt is 16 bytes.

Random nonces are safe across devices: with 192 bits, collisions are not a
practical concern even though no server coordinates the devices. This is why
XChaCha20 is used rather than AES-GCM (96-bit nonces).

---

## 3. Layout

```
<vault_id>/
  vault.json                 plaintext header (§4)
  items/<object_id>.enc      encrypted item record (§6.1)
  apps/<object_id>.enc       encrypted app record (§6.2)
  blobs/<object_id>.enc      encrypted file bytes, immutable (§6.3)
  tombstones/<object_id>.enc encrypted deletion marker (§6.4)
```

- `vault_id` and every `object_id` are random **UUIDv4**, lowercase, in
  canonical 8-4-4-4-12 form. Object ids are never derived from content: a
  content hash would reveal that two items hold the same file.
- A tombstone's `object_id` is the id of the item or app it deletes.
- **Blobs are immutable.** Replacing a file writes a new blob under a new id
  and points the item at it. Unreferenced blobs are garbage-collected after a
  grace period (P2).
- Local storage mirrors this layout. Device-local state (sync bookkeeping,
  the pinned key fingerprint) lives **outside** the `<vault_id>/` tree and is
  never uploaded:
  - `<vault_id>.rotation`: the key-rotation journal (§9);
  - `<vault_id>.sync/state.json`: the etag and `rev` of every remote object
    as last synced, the keys changed locally since, and the storage's
    probed capabilities;
  - `<vault_id>.sync/base/<path>`: each object's ciphertext exactly as last
    synced, the common ancestor for a three-way merge. It is already
    encrypted and bound to its slot, so it needs no further protection.

---

## 4. `vault.json`

UTF-8 JSON, the only plaintext object. It holds everything needed to derive
the vault key, and nothing about the contents.

```json
{
  "format": "devvault",
  "format_version": 1,
  "vault_type": "personal",
  "vault_id": "7f3c2d9e-1b4a-4c8f-9e2d-5a6b7c8d9a1e",
  "created_at": "2026-10-07T09:00:00Z",
  "kdf": {
    "alg": "argon2id13",
    "ops_limit": 3,
    "mem_limit": 67108864,
    "salt": "<base64, 16 bytes>"
  },
  "wrapped_vk_password": "<base64 envelope>",
  "wrapped_vk_recovery": "<base64 envelope>",
  "vk_id": "<hex, 32 bytes>"
}
```

| Field | Rule |
|---|---|
| `format` | MUST be `"devvault"`. |
| `format_version` | Integer. Readers MUST refuse a version they don't know. |
| `vault_type` | `"personal"` in v1. Reserved for team vaults later. |
| `kdf.alg` | MUST be `"argon2id13"`. |
| `kdf.ops_limit` | Integer, **1 ≤ ops ≤ 10**. Default 3. |
| `kdf.mem_limit` | Bytes, **8 MiB ≤ mem ≤ 1 GiB**. Default 64 MiB. |
| `kdf.salt` | Standard base64 with padding, exactly 16 bytes. |
| `wrapped_vk_*` | Standard base64 of an envelope (§5). Object type `vk_wrap_password` / `vk_wrap_recovery`; object id = `vault_id`. |
| `vk_id` | Fingerprint of the vault key (§4.4). |

- Readers MUST reject KDF parameters outside these bounds **before**
  running the KDF. This stops a tampered header from forcing a device to
  allocate gigabytes of memory.
- Parallelism is always 1, because libsodium's Argon2id has no parallelism
  setting (ADR-0003).
- Writers MUST preserve fields they don't understand when rewriting
  `vault.json`.

### 4.1 Vault key (VK)

32 random bytes, generated once when the vault is created. It encrypts every
item, app, blob and tombstone. Changing the password does not change the VK.

### 4.2 Password wrap

```
KEK_pw = Argon2id(password = UTF-8(NFC(master password)),
                  salt = kdf.salt, ops = kdf.ops_limit, mem = kdf.mem_limit,
                  out = 32 bytes)
wrapped_vk_password = envelope(type = vk_wrap_password, id = vault_id,
                               key = KEK_pw, plaintext = VK)
```

The password is normalised to Unicode NFC so the same password typed on
different platforms gives the same key. A password change picks a new salt
and new KDF parameters and rewraps the VK. **It rewrites only
`vault.json`.**

### 4.3 Recovery wrap

```
recovery_key = 32 random bytes, shown to the user once (§8)
PRK     = HKDF-SHA256-Extract(salt = UTF-8(vault_id), IKM = recovery_key)
KEK_rec = HKDF-SHA256-Expand(PRK, info = "devvault/v1/recovery-kek", L = 32)
wrapped_vk_recovery = envelope(type = vk_wrap_recovery, id = vault_id,
                               key = KEK_rec, plaintext = VK)
```

The recovery key has 256 bits of entropy, so no slow KDF is needed. Unlocking
with it MAY be followed by setting a new password (§4.2).

### 4.4 Key fingerprint and pinning

```
vk_id = hex(BLAKE2b-256(key = VK, message = UTF-8("devvault/v1/vk-id")))
```

After a successful unlock a client MUST check that `vk_id` matches the
unwrapped VK, and SHOULD remember `vk_id` per vault on the device.

**Why pinning matters:** someone with bucket write access could replace both
wrapped keys with wraps of a VK of their own under a password of their
choosing. They can't decrypt the existing items, but a device that accepted
the new key would encrypt **new** items to them.

**What clients do:**
- If a pinned `vk_id` changes, the client MUST NOT write anything with the new
  key until the user confirms the change.
- The confirmation SHOULD say that the vault key was rotated on another device,
  or that the bucket may have been tampered with.

A legitimate VK rotation (§9) changes `vk_id` too, so the user on every other
device is asked once.

---

## 5. Envelope

Every `.enc` object and every wrapped key uses the same binary envelope:

```
offset  size  field
0       4     magic            "DVLT" (0x44 0x56 0x4C 0x54)
4       1     format_version   0x01
5       1     object_type      see table
6       24    nonce            random
30      n+16  ciphertext       XChaCha20-Poly1305-IETF(plaintext) || tag
```

| `object_type` | Code | Name in AAD | Plaintext |
|---|---|---|---|
| item | `0x01` | `item` | item JSON (§6.1) |
| app | `0x02` | `app` | app JSON (§6.2) |
| blob | `0x03` | `blob` | raw file bytes |
| tombstone | `0x04` | `tombstone` | tombstone JSON (§6.4) |
| VK, password wrap | `0x05` | `vk_wrap_password` | 32-byte VK |
| VK, recovery wrap | `0x06` | `vk_wrap_recovery` | 32-byte VK |

**Associated data**, UTF-8, no trailing newline:

```
AAD = vault_id "|" object_id "|" object_type_name "|" format_version
e.g. "7f3c2d9e-1b4a-4c8f-9e2d-5a6b7c8d9a1e|0d1c…|item|1"
```

A reader MUST take `vault_id`, `object_id` and `object_type` from **where it
found the object**, not from the object itself:
- `vault_id` comes from the vault being opened;
- `object_id` comes from the file name;
- `object_type` comes from the folder.

The reader MUST then:
1. Check that the envelope's magic, version and type byte match, and reject
   it otherwise.
2. Decrypt with the AAD built from those values.

So an object copied into another slot, another type's folder or another vault
fails to decrypt.

Any failure (bad magic, unknown version or type, short input, or
authentication failure) is reported as one error. Clients MUST NOT reveal
which check failed in user-facing messages, and SHOULD quarantine the
object instead of crashing.

---

## 6. Records

Records are UTF-8 JSON objects. Common rules:

- `schema` is the record schema version, `1` in this spec. A reader that
  meets a higher `schema` MUST keep the record unchanged (read-only) rather
  than rewrite it with fields missing.
- Writers MUST preserve unknown fields when updating a record.
- Timestamps are RFC 3339 in UTC with a `Z`, e.g. `2026-10-07T09:00:00Z`.
  Fractional seconds are allowed.
- `rev` is a hybrid logical clock value (§7). `device_id` is the writing
  device's UUID.

### 6.1 Item

```json
{
  "schema": 1,
  "id": "0d1c5e7a-…",
  "type": "android_keystore",
  "title": "Upload keystore",
  "app_id": "a1b2…",
  "platform": "android",
  "environment": "production",
  "tags": ["release", "signing"],
  "fields": {
    "alias":          { "value": "upload", "source": "file" },
    "sha256":         { "value": "FA:C6:…", "source": "file" },
    "store_password": { "value": "…", "source": "user", "secret": true }
  },
  "attachments": [
    { "blob_id": "9e8d…", "filename": "kitchenly-upload.jks",
      "mime": "application/octet-stream", "size": 2614,
      "sha256": "3f9a0c7e…b81dc21e" }
  ],
  "expires_at": "2051-01-14T00:00:00Z",
  "expires_source": "file",
  "notes": "Upload key only.",
  "created_at": "2025-02-03T10:00:00Z",
  "updated_at": "2026-09-12T08:30:00Z",
  "rev": "001757665800000-00000-<device_id>",
  "device_id": "…",
  "conflict": null
}
```

| Field | Rule |
|---|---|
| `type` | One of the wire names in §6.5. An unknown type MUST be kept and shown as a generic item, not dropped. |
| `app_id`, `platform`, `environment` | Optional. `platform` and `environment` are free strings; clients suggest `ios`, `android`, `macos`, `web`, `server` and `production`, `staging`, `development`. |
| `fields` | Map of field key → `{value, source, secret?}`. `source` is `"file"` (parsed from an attachment) or `"user"` (typed in). `secret: true` marks values that are masked, never indexed for search and copied only through the clipboard guard. |
| `attachments[].sha256` | Lowercase hex SHA-256 of the **plaintext** file. Export MUST verify it. |
| `expires_at` / `expires_source` | Both present or both absent. `expires_source` is `"file"` or `"user"`, never anything else. **There is no inferred expiry.** |
| `conflict` | `null`, or the remote version kept by a sync conflict (P2, ADR-0004). |

### 6.2 App

```json
{ "schema": 1, "id": "a1b2…", "name": "Kitchenly",
  "bundle_ids": ["com.kitchenly.app"], "package_names": ["com.kitchenly.app"],
  "icon_blob_id": null,
  "created_at": "…", "updated_at": "…", "rev": "…", "device_id": "…" }
```

### 6.3 Blob

The plaintext is the original file, byte for byte. Its name and type live in
the referencing item's attachment entry, not in the blob. Maximum plaintext
size in v1 is **25 MiB**: blobs are sealed in one AEAD call.

### 6.4 Tombstone

```json
{ "schema": 1, "id": "0d1c…", "kind": "item",
  "deleted_at": "2026-10-07T09:00:00Z", "rev": "…", "device_id": "…" }
```

`kind` is `"item"` or `"app"`. Writing a tombstone removes the record file.
Blobs are left for garbage collection.

### 6.5 Item types

| Wire name | File(s) | Expiry from |
|---|---|---|
| `apple_auth_key` | `.p8` | none (doesn't expire) |
| `apple_certificate` | `.p12`, `.cer` | certificate `notAfter` |
| `provisioning_profile` | `.mobileprovision` | plist `ExpirationDate` |
| `android_keystore` | `.jks`, `.keystore`, PKCS#12 | certificate `notAfter` |
| `firebase_config` | `google-services.json`, `GoogleService-Info.plist` | none |
| `gcp_service_account` | service-account `.json` | none in file; user may set one |
| `oauth_client` | `client_secret_*.json` | none |
| `ssh_key` | OpenSSH private key (`id_ed25519`, `id_rsa` …) | none (OpenSSH keys don't expire) |
| `generic_file` | anything | user only |
| `generic_secret` | none (typed in) | user only |

---

## 7. Hybrid logical clock (`rev`)

```
rev = wall_ms (15 decimal digits, zero-padded)
      "-" counter (5 decimal digits, zero-padded)
      "-" device_id
e.g.  001759827600000-00000-2530b979-e992-4aaf-8aac-52a2ce7abaf4
```

- Plain string comparison of two revs gives their causal order. The device
  id breaks ties.
- On every local write:
  - `wall_ms = max(previous.wall_ms, now)`;
  - `counter` increments when `wall_ms` didn't advance, and resets to 0 when it did.
- On reading a remote rev:
  - the local clock moves to `max(local, remote)` and then ticks;
  - a remote `wall_ms` more than 24 hours ahead of the local clock is accepted
    but reported, because it points at a wrong clock.

Sync (P2) uses `rev` and S3 conditional writes to detect concurrent edits; see
ADR-0004 for the merge rules.

---

## 8. Recovery key encoding

The 32-byte recovery key is shown and typed as text:

```
checksum = first 20 bits of SHA-256(recovery_key)
text     = Crockford-base32(recovery_key || checksum bits), 56 characters
shown    = 14 groups of 4 joined by "-", e.g. K7QF-2M9X-RT4C-…
```

- **Alphabet:** Crockford base32, `0123456789ABCDEFGHJKMNPQRSTVWXYZ`.
- **Bit layout:** 256 key bits followed by 20 checksum bits, read most
  significant bit first. That's 276 bits; the 4 trailing pad bits are zero, so
  the whole is 280 bits, or 56 characters.
- **Parsing:**
  - case-insensitive;
  - `I` and `L` read as `1`, `O` reads as `0`;
  - spaces and `-` are ignored.
- A checksum mismatch is reported as "this recovery key has a typo" before any
  decryption is attempted.

---

## 9. Operations

| Operation | Objects written |
|---|---|
| Create vault | `vault.json` |
| Change password / reset after recovery | `vault.json` only |
| Add or edit an item | `items/<id>.enc`, plus a new blob when a file is added or replaced |
| Delete an item | `tombstones/<id>.enc`, and `items/<id>.enc` is removed |
| Replace the recovery key | `vault.json` only |
| Rotate the vault key | journal (device-local), every blob re-encrypted under a **derived new** id, every item, app and tombstone re-encrypted in place, `vault.json` written **last**, then the journal and old blobs deleted |

**Rotation rules:**
- Rotation needs the master password. It creates a new VK **and a new
  recovery key**: after a suspected compromise the old recovery key must stop
  working.
- Before touching any object, the client writes a device-local journal next
  to (not inside) the `<vault_id>/` folder, holding the new VK and new
  recovery key:
  ```
  journal = nonce(24) || XChaCha20-Poly1305(new_vk || new_recovery_key,
            AAD = "devvault/v1/rotation-journal|" vault_id "|" old vk_id,
            key = old VK)
  ```
- **Blobs** are re-encrypted under derived ids:
  `new_id = UUIDv4 bits over BLAKE2b-256(key = new VK,
  "devvault/v1/rotated-blob|" old_id)`. A resumed rotation finds the blobs it
  already wrote.
- **Records:** each item, app and tombstone is opened with the old VK (or
  skipped if the new VK already opens it), item attachments are pointed at
  the derived blob ids, and the record is re-encrypted in place.
- `vault.json` is written last: new KDF salt, both wraps for the new VK, a
  new `vk_id`. Then the journal and the old blobs are deleted.
- **Resuming:** a password unlock that finds a journal it can open finishes
  the rotation and offers the new recovery key to the user. A journal that
  the current VK can't open belongs to a rotation that already replaced
  `vault.json`, and is deleted.
- **Crash safety:**
  - a crash before the journal lands leaves the vault untouched;
  - a crash at any later point is finished on the next unlock.
- A recovery key can also be replaced on its own (`vault.json` only).

**Local writes:**
- A local write MUST be atomic: write a temporary file in the same folder,
  flush it to disk, then rename it over the target.
- A reader MUST never see a partly written object.

---

## 10. Conformance

A conforming reader:

1. Parses `vault.json` and rejects unknown `format` / `format_version` and
   out-of-bounds KDF parameters.
2. Derives KEK_pw (or KEK_rec), opens the wrapped VK, and checks `vk_id`.
3. Opens every `items/`, `apps/` and `tombstones/` object using AAD built from
   its location, and quarantines anything that fails.
4. Opens blobs on demand and verifies the attachment's `sha256`.
5. Keeps unknown fields and unknown types.

The test vectors in `docs/format/vectors/` (P0-14) cover every step above,
plus a complete `mini-vault/` that a conforming reader can unlock with the
password `correct horse battery staple`.
