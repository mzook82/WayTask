# Guest-to-Account Migration

WT-032A implements states and contracts only. It does not upload, add local sync
fields, or modify ProductState V4.

## Required flow

1. User explicitly chooses an account action; normal use remains Guest Mode.
2. Future auth adapter verifies the session and creates/reads the owner profile.
   A verified identity changes state to **signed in/local not backed up**, not to
   “synced.”
3. Scanner reads ProductState through repositories in a consistent snapshot and
   builds a preview grouped by lists, entries, personal products, preferences,
   saved stores, excluded images, deferred history/sessions, and validation
   exceptions.
4. UI explains exactly what will be backed up, flags precise saved-store
   coordinates separately, and lets the user cancel before cloud commit.
5. On confirmation, create a migration manifest with dataset ID, owner, schema
   versions, record stable IDs/revisions, canonical hashes, batch order, and a
   migration UUID. Persist it in a sidecar/local schema approved for WT-032B.
6. Upload resumable batches through the trusted migration endpoint. Server
   derives owner from JWT, validates every row, upserts by stable UUID with
   create-only/base-revision rules, and writes an idempotent receipt.
7. After every timeout, query receipt/records; never infer failure from a lost
   response. Record accepted/rejected IDs and reasons without storing private
   server payloads as UI text.
8. Verify cloud counts, owner, parent relationships, UUIDs, canonical hashes,
   tombstones, and revisions. Partial success remains visible and resumable.
9. Mark only verified local records synchronized in the sync sidecar. Do not
   delete local ProductState rows or images.
10. Enter active offline-first sync. Local commands commit first; cloud delivery
    is queued and cannot block Shopping, Products, Camera, Scanner, or Map.

## Future local sidecar contract

| Field | Meaning |
|---|---|
| `local_id` | Existing ProductState UUID; immutable |
| `entity_type` | finite type allowlist |
| `cloud_id` | normally same UUID; nullable before first receipt |
| `owner_user_id` | verified target user, never UI input |
| `local_revision` | ProductState revision or sidecar monotonic entry revision |
| `cloud_revision` | last verified server revision |
| `base_cloud_revision` | revision on which next local edit is based |
| `last_synced_at` | server-confirmed timestamp, informational only |
| `sync_status` | local-only/pending/uploading/verified/conflict/rejected/tombstone |
| `deleted_at` | tombstone state |
| `mutation_id` / `idempotency_key` | durable retry identity |
| `payload_sha256` | canonical content identity, not content |

This must be introduced by a versioned, backup-tested local migration or a
separate atomic sidecar store. It cannot be transient memory. Entry rows need an
independent monotonic local sync revision because current V4 entries do not have
one.

## Recovery rules

- Cancellation before confirmation performs no cloud writes.
- Interruption preserves the manifest and verified receipts. Resume starts at
  the first unverified batch.
- Sign-out pauses delivery and preserves linked local data. New signed-out edits
  are local pending changes associated with that dataset, never reassigned to a
  later account without explicit choice.
- Session expiration pauses cloud access, not local access.
- Deleting the app can still lose records not verified in cloud; preview and
  progress UI must say so honestly.
- A validation-rejected local row stays local and appears in a recoverable review
  list. Migration completion cannot silently omit it.
