# ADR-0004: Field-level 3-way merge, never drop a secret

- Status: Proposed (decided in P2-06)

## Decision (draft)
- Every record carries a hybrid-logical-clock `rev` and a `device_id`.
- Each device keeps an encrypted base snapshot of the last synced version of each item.
- On a 412 from a conditional write, the device pulls and merges `base` / `local` / `remote` field by field:
  - When only one side changed a field, that side wins.
  - When both sides made the same change, it's kept.
  - When both sides made different changes, the item keeps the local value and records the remote one in a `conflict` slot, which syncs to every device until the user resolves it in D05.
- An edit beats a delete; the delete is recorded on the conflict.
- Attachments are merged as a set union by blob id.
- **Invariant:** no secret value written by any device is ever silently dropped. A property test checks this.
