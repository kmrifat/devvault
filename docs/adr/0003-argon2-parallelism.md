# ADR-0003: Argon2id with parallelism 1

- Status: Proposed (decided in P0-03)

## Context
Plan v1.1 suggested about 64 MiB, t=3, p=4. libsodium's `crypto_pwhash` (ALG_ARGON2ID13) has no parallelism parameter and always runs with p=1. A pure-Dart Argon2 with p=4 is far too slow on mobile.

## Decision (draft)
Default to `alg=argon2id13, ops=3, mem=64 MiB, p=1, salt=16 bytes`, stored in `vault.json`. The params travel with the vault, so they can be raised later. Go's `argon2.IDKey(..., threads=1)` reproduces it for the future CLI.

## Consequences
The cost of each unlock is benchmarked per platform in P0-15. If low-end Android goes over about 1.5 s, lower `ops` rather than `mem`.
