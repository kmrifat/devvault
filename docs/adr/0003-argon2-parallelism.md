# ADR-0003: Argon2id with parallelism 1

- Status: Accepted (2026-10-07, P0-01)

## Context
Plan v1.1 suggested about 64 MiB, t=3, p=4. libsodium's `crypto_pwhash`
(ALG_ARGON2ID13) has no parallelism parameter and always runs with p=1. A
pure-Dart Argon2 with p=4 is far too slow on mobile.

## Decision
- Default `alg=argon2id13, ops_limit=3, mem_limit=64 MiB, salt=16 bytes`,
  stored in `vault.json`.
- Readers accept `ops_limit` from 1 to 10 and `mem_limit` from 8 MiB to 1 GiB,
  and reject anything outside before deriving. That stops a tampered header
  from forcing a huge allocation.
- The params travel with the vault, so they can be raised later. Go's
  `argon2.IDKey(…, threads=1)` reproduces it for the CLI.

## Measurements
| Device | ops=3, mem=64 MiB |
|---|---|
| MacBook (Apple silicon), Dart VM | 164 ms |

Other platforms are benchmarked in P0-15. If low-end Android goes over about
1.5 s, lower `ops_limit` rather than `mem_limit`.
