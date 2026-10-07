# Pairing payload (P4-06)

A device that already syncs a vault can hand its sync storage settings and
keys to a new device as a QR code. This is the format of what the QR holds.
It is a contract between devices: changing it needs a new version prefix.

## What it is, and isn't

- It carries **only** the storage settings (provider, account, endpoint,
  region, bucket, prefix, path style) and the S3 access keys.
- It **never** carries the vault key, the master password or any vault
  content. The new device still has to enter the master password to open
  the vault it finds in the bucket (the P2-10 join flow).
- It is sealed under an 8-character code shown next to the QR, and it
  expires ten minutes after it was made.

## Text

```
devvault-pair:1:<base64url(envelope JSON), no padding>
```

## Envelope

| Key | Value |
|---|---|
| `vault_id` | The vault's UUID (lower case, canonical). |
| `expires_at` | RFC 3339 UTC with `Z`, whole seconds: creation + 10 minutes. |
| `salt` | 16 random bytes, base64url. |
| `ops`, `mem` | Argon2id costs. Written as 3 and 64 MiB; readers accept 1–10 and 8–64 MiB and refuse anything else before deriving. |
| `nonce` | 24 random bytes, base64url. |
| `box` | XChaCha20-Poly1305-IETF of the contents, base64url (ciphertext ‖ 16-byte tag). |

- **Key:** Argon2id v1.3, parallelism 1, 32 bytes, over the UTF-8 code
  (normalised, below) with `salt`, `ops`, `mem`.
- **Associated data:** UTF-8 of
  `devvault/v1/pair|<vault_id>|<expires_at>|<ops>|<mem>`, exactly as
  written in the envelope. Changing any of them breaks the seal.

## Contents (the plaintext)

```json
{
  "settings": { "provider": "r2", "account_id": "…", "endpoint": "",
                "region": "", "bucket": "…", "prefix": "", "path_style": true },
  "access_key_id": "…",
  "secret_access_key": "…",
  "session_token": "…"            // only for temporary credentials
}
```

`settings` is `SyncSettings.toJson()` (`lib/data/sync_setup.dart`).

## Code

8 characters from Crockford base32, `0123456789ABCDEFGHJKMNPQRSTVWXYZ`
(40 random bits), shown as `ABCD-EFGH`. A reader normalises what is typed:
upper case, drop spaces and dashes, `O`→`0`, `I`/`L`→`1`.

## Reading

1. Refuse anything without the prefix, or an envelope that doesn't parse
   or has out-of-range costs.
2. Refuse when now is more than 2 minutes past `expires_at`, or
   `expires_at` is more than 12 minutes ahead (10 minutes plus skew).
3. Derive the key, open the box. A failure says only "that code doesn't
   match"; nothing about the contents is revealed.

## Test vector

`test/pairing_test.dart` pins a payload made with a seeded random source
(`devvault pairing vector`), vault `7f3c2a10-4b5d-4e6f-8a9b-0c1d2e3f4a5b`,
`now = 2026-10-08T09:00:00Z`, `ops = 1`, `mem = 8 MiB`, and checks that it
opens with its code.
