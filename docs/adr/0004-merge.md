# ADR-0004: Field-level three-way merge, never drop a secret

- Status: Accepted (P2-06)
- Code: `packages/vault_core/lib/src/sync/merge.dart`
- Tests: `packages/vault_core/test/merge_test.dart`

## Context

Devices edit offline and sync through a bucket with no server logic. The only
coordination is S3 conditional writes: a push with `If-Match` fails with 412
when another device wrote first. The device that loses that race has to
combine the two versions itself, and it must never lose a credential.

## Decision

- Every record carries a hybrid-logical-clock `rev` and a `device_id`.
- Each device keeps the ciphertext of every object as it last synced it
  (`<vault_id>.sync/base/`, SPEC §3). Decrypted, that is the common ancestor.
- On a lost race the device pulls and merges `base` / `local` / `remote`
  field by field (`mergeItems`):
  - When only one side changed a value, that side wins.
  - When both made the same change, it's kept.
  - When both changed the same value differently, the item keeps the
    **local** value and records the remote record in `conflict.versions`.
    The device doing the merge pushes the result, so every device converges
    on it.
  - An **edited field beats a removed one**; removing what the other side
    left unchanged removes it.
  - Tags merge as sets: additions from both sides, minus removals from the
    base.
  - Attachments merge as a **union** by blob id. A file is never dropped by
    a merge.
  - Expiry is merged as one value: date and source together.
  - Without a base (joining a vault, or a lost base), every difference is a
    conflict.
- **An edit beats a delete** (`resolveDeletion`). If the item changed since the
  base, it stays and the deletion is recorded in `conflict.deletions`;
  otherwise the delete wins.
- Conflicts **accumulate**: merging adds to `versions` and `deletions`,
  unique by `rev`, and never replaces them. Only an explicit choice in D05
  (P2-11) clears a conflict.
- Apps hold nothing secret and have no conflict slot. A clash keeps the
  local value, and identifier lists merge as sets (`mergeApps`).

## Invariant

**No secret value written by any device is silently dropped.** After any
merge, every secret value that either side changed from the base is in the
merged fields or in a kept conflict version. `merge_test.dart` checks this
on 2,000 random concurrent edit pairs, and on 200 random three-device runs
that sync through one remote copy, which must also converge. Removing the
line that records the losing version makes the property test fail.

## Consequences

- Conflicted items are larger until resolved. Each kept version is a full
  record.
- Which value is shown first depends on which device merged. Both are kept,
  and the user chooses.
- A device that loses its base merges as if joining: more conflicts, no
  loss.
