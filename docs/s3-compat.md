# S3 compatibility

DevVault syncs through any S3-compatible bucket you own. Sync is safe
between devices only if the store enforces **conditional requests**, so
that two devices can't silently overwrite each other's changes:

| Operation | Header | Used for |
|---|---|---|
| Create only if absent | `PUT` + `If-None-Match: *` | new items, apps, tombstones, a new vault |
| Update only if unchanged | `PUT` + `If-Match: <etag>` | edited items and `vault.json` |
| Delete only if unchanged | `DELETE` + `If-Match: <etag>` | removing an object a tombstone replaces |

## The app doesn't assume, it probes

Providers add these features at different times and in different ways, so
DevVault never relies on a list like the one below. **Test connection**
(Settings → Sync storage) runs `S3Backend.probe` against your bucket. The
probe uses a scratch object under the vault's prefix and removes it
afterwards. For each operation above it checks that a stale condition is
refused and a current one is accepted, and stores the result with the
sync settings.

Anything the store doesn't enforce is emulated by `VerifyingBackend`: it
reads, checks, writes, and reads back to confirm. That narrows a race to the
moment between the check and the write but can't close it, so Settings
shows a warning for each gap:

- *Conditional writes not enforced*: two devices saving at the same moment
  could overwrite each other.
- *Conditions on deletes ignored*: a change made on another device at the
  same moment could be removed. (`S3Backend.delete` always checks the
  etag with a `HEAD` first and still sends `If-Match`.)

## What has been verified here

Only results this project has measured are listed. "Not yet probed" means
nobody has run the probe against that provider from this repo yet; it is
not a claim that the feature is missing.

| Provider | Create if absent | Update if unchanged | Delete if unchanged | How verified |
|---|---|---|---|---|
| MinIO `RELEASE.2025-09-07T16-13-09Z` | ✅ enforced | ✅ enforced | ❌ ignored (deletes anyway) | CI (`.github/workflows/s3.yml`) and locally; the conformance suite plus the probe |
| Cloudflare R2 (default in the app) | not yet probed | not yet probed | not yet probed | P2-14 acceptance run |
| AWS S3 | not yet probed | not yet probed | not yet probed | P2-14 acceptance run |
| Backblaze B2 (S3 API) | not yet probed | not yet probed | not yet probed | — |

Other differences worth knowing, all handled in `S3Backend`:

- A `PUT` with `If-Match` on a key that no longer exists answers **404
  NoSuchKey** (MinIO, verified), not 412. DevVault treats it as the same
  lost race.
- A conditional write racing another may answer **409
  ConditionalRequestConflict**. DevVault retries with backoff, then treats it
  as a lost race.
- Path-style addressing (`https://endpoint/bucket/key`) is the default,
  because most S3-compatible stores need it. R2 signs with region `auto`.

## Running the checks yourself

MinIO no longer publishes community images or binaries, so build the
pinned release from source (Go 1.24+), as CI does:

```bash
GOBIN=$PWD/minio-bin go install github.com/minio/minio@RELEASE.2025-09-07T16-13-09Z
MINIO_ROOT_USER=devvault MINIO_ROOT_PASSWORD=devvault-secret \
  ./minio-bin/minio server /tmp/minio-data --address 127.0.0.1:19010 &
curl --aws-sigv4 "aws:amz:us-east-1:s3" --user devvault:devvault-secret \
  -X PUT http://127.0.0.1:19010/devvault   # create the bucket

cd packages/vault_s3
S3_TEST_ENDPOINT=http://127.0.0.1:19010 S3_TEST_BUCKET=devvault \
S3_TEST_ACCESS_KEY=devvault S3_TEST_SECRET_KEY=devvault-secret \
dart test
```

The same variables point the suite at any other provider. Use a scratch
bucket: the run writes and deletes about a thousand small objects under a
`conformance-<timestamp>/` prefix.
