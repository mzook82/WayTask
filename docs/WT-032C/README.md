# WT-032C — Guest → Account Migration Foundation

Status: **IMPLEMENTED, INERT, AND READY FOR SYNTHETIC STAGING QA** as of
2026-08-08.

This sprint implements the client and server migration foundation without
activating it. `WAYTASK_CLOUD_MIGRATION_ENABLED`, Sync, Secure AI, and all
Production cloud features remain OFF. No real ProductState content was uploaded,
relabelled, deleted, or migrated. The new SQL migration and Edge Function have
not been deployed to hosted WayTask Staging.

Real signed-session User A/User B isolation remains an explicit hard
pre-activation gate. Repository-role simulations and synthetic UUID tests do
not satisfy that gate.

## Baseline audit

- ProductState V4 is the active local authority in the promoted runtime store.
  Its `Product`, `ShoppingList`, and `ShoppingListEntry` records are read through
  a new point-in-time `ModelContext`; the migration foundation has no local
  delete or ownership-relabel operation.
- Map, notification, and geofence planning continue to consume ProductState V4.
  The migration scanner does not call or mutate those authorities.
- Camera/Scanner image and recognition artifacts, shopping sessions/history,
  precise `GeoLocation` content, legacy Product Knowledge, and catalog resources
  remain outside the first migration.
- WT-032A's public private-data tables retain owner RLS, composite parent/child
  ownership foreign keys, server-controlled revisions, validation constraints,
  and FORCE RLS. WT-032B/WT-032B.1 retain native Apple authentication,
  project-bound session restoration, ThisDeviceOnly Keychain storage, typed
  expiration recovery, and Apple-only hosted Auth.
- Sign-in formerly persisted `migrationPending` immediately. That violated the
  now-explicit preparation boundary and is corrected: a newly signed-in user
  remains `guestOnly` until separate migration consent/preparation. Existing
  persisted pending/linked bindings are preserved and never weakened.
- Sync can no longer promote a `migrationPending` dataset to linked. Only
  verified migration completion can make it linked, and Sync remains paused.

## First-migration inventory

| Category | Decision | Contract |
|---|---|---|
| Personal products | Included | Stable UUID, name, optional brand/category/barcode, known source, lifecycle/removal, catalog link, revision/timestamps as content |
| Product images/URLs | Excluded | No bytes, path, remote URL, or image metadata enters the manifest |
| Catalog display snapshots | Excluded | Rebuildable presentation metadata; only the validated stable catalog link moves |
| Named shopping lists | Included | Stable UUID, title, safe purpose, local revision/timestamps |
| Recent/completed/deleted archive lists | Excluded | Not part of the first active dataset migration |
| List entries | Included | Stable UUID and parent IDs, quantity/unit/note, needed/resolved state, safe resolution metadata, order, timestamps |
| Shopping sessions/history | Excluded | Includes session lines/stops, immutable history events, and legacy history |
| Saved stores/precise locations | Excluded | Requires a later location-specific consent and privacy contract |
| Notification/geofence state | Excluded | OS/runtime state is device-specific and rebuildable |
| Legacy/imported/unsafe rows | Excluded or blocking | No opportunistic conversion; an unsafe value that would make the approved dataset incomplete fails preview closed |
| Product Knowledge/catalog files | Excluded | Shared/server-derived or rebuildable data |

No durable notification preference represented in current ProductState V4 is
eligible in version 1. Saved-store and notification counts are therefore shown
as not included, not silently treated as migrated.

## State machine

```text
GuestLocal
  → AuthenticatedLocalUnlinked
  → MigrationPreviewAvailable
  → MigrationConsentRequired
  → MigrationPreparing
  → MigrationUploading
  → MigrationVerifying
  → MigrationCompleted (Sync remains OFF)

Uploading/Verifying
  → MigrationInterrupted → MigrationRecoverable → resume
  → MigrationConflict
  → MigrationRollbackRequired

Any activation failure → MigrationBlocked
```

Opening the account screen, sign-in, session restoration, Preview, and a generic
Continue action are not consent. Preview performs zero network requests. The
internal Staging UI presents counts, the exclusion summary, local-preservation
copy, account-switch warning, and a separate confirmation. With the current
gate values, confirmation stops at **Migration not enabled** before binding or
network access.

## Canonical manifest

Format version 1 uses sorted-key JSON, precomposed Unicode, lower-level stable
UUID ordering, integer epoch-millisecond content timestamps, and SHA-256.
Timestamps are content only; they are never identity or last-write-wins
authority.

The canonical dataset contains:

- format and ProductState schema versions;
- immutable authenticated target UUID and local dataset UUID;
- exact counts and deterministic entity records;
- included/excluded category allowlists;
- ordered batch descriptors with sequence, kind, record count, byte count, and
  payload SHA-256;
- a dataset fingerprint over the canonical dataset.

The random attempt UUID, retry count, receipts, and execution state live in the
protected ledger, outside canonical dataset identity. An unchanged dataset for
the same target produces the same manifest/fingerprint; a new attempt produces
new deterministic batch IDs without changing dataset identity.

## Binding, consent, and local mutation

Preview does not bind. Immediately after explicit consent and immediately
before preparation, the scanner regenerates the manifest. A fingerprint change
invalidates consent and returns to Preview.

Preparation atomically persists `migrationPending(dataSetID, targetUserID)` in
the existing protected ownership sidecar and writes a complete-file-protected,
mode-0600 migration ledger in Application Support. The approved canonical
snapshot is then stable even if ProductState changes later; later local changes
stay local and unsynchronized. Sign-out, expiration, relaunch, or a different
session cannot erase or retarget either binding.

`Guest → A → prepare → sign out → B`, interrupted A → B, and completed A → B
all fail closed. No request body has an authoritative target/owner field.

## Batching, idempotency, and resume

- Dependency order is personal products → shopping lists → entries → verify.
- Client, Edge, and database batches are at most 100 records and 1 MiB. The
  database derives the exact remaining count from the manifest and accepts
  only a full 100-row chunk or the final remainder; a 5,100-batch attempt cap
  bounds the maximum version-1 request sequence.
- `batchID = SHA256(attempt UUID | sequence | kind | canonical payload SHA256)`.
- The server independently hashes the parsed JSON, binds every row to
  `auth.uid()`, and stores client, server-payload, and post-insert row-state
  hashes plus exact row IDs in an owner-scoped receipt. The Edge boundary also
  verifies the canonical records against the declared client payload hash.
- An exact lost-response retry returns the same receipt and produces no second
  row. Changed content, sequence, kind, owner, or receipt is a typed conflict.
- The ledger saves each acknowledgement before advancing. Relaunch resumes only
  missing batches for the same authenticated UUID.
- The HTTPS transport requests a fresh eligible session per attempt and uses a
  bounded 3-attempt exponential delay. Authentication/conflict/validation
  failures do not retry; no infinite loop or retry storm exists.

## Server authority

The preferred boundary is the Staging `initial-migration` Edge Function plus
four narrow authenticated RPCs. The Edge Function and RPCs both fail closed.

- Edge execution requires server environment switch
  `WAYTASK_INITIAL_MIGRATION_ENABLED=true`; it is absent/OFF now.
- The private database control additionally requires a default-false
  deployment approval. Applying the schema alone cannot activate begin,
  upload, verify, or rollback authority in another project.
- Supabase verifies the bearer token; the function verifies it again through
  `/auth/v1/user`; each RPC derives the owner again from `auth.uid()`.
- iOS uses only the client-safe publishable key and a Keychain-backed access
  token. No service-role key, database password, Apple secret/private key, or
  refresh token enters a request or log.
- Unknown fields, target/owner fields, malformed UUID/hash/version/counts,
  oversized batches, out-of-order batches, missing/cross-owner parents, direct
  receipt mutation, and arbitrary completion are rejected.
- Database uniqueness permits only one first-migration attempt per owner and
  one immutable local dataset identity across owners, closing concurrent-device
  and A-to-B dataset-claim races.
- Except for the user's optional profile prerequisite, the remote account must
  be empty unless the exact same attempt/manifest is resuming. Unrelated
  preferences, saved stores, notification/device/sync rows, another
  attempt/device, or identity collision fails closed and preserves both sides.
- Attempt/receipt tables have ENABLE RLS + FORCE RLS and owner-select only.
  Direct client insert/update/delete is denied.

The migration SQL adds nullable attempt provenance to the three included public
tables. It does not weaken their existing RLS or ownership constraints.

## Verification, completion, and conflicts

HTTP 2xx is never completion. `initial_migration_verify` locks the attempt and
checks:

- exact attempt-owned product/list/entry counts;
- receipt record totals and ordered receipt IDs;
- every receipt's exact record-ID set and post-insert row-state hash;
- absence of unrelated owner rows introduced before finalization;
- authenticated owner UUID on every row;
- entry parent/product ownership and attempt provenance;
- absence of all product image fields.

Only the RPC may mark the remote attempt complete. Only a valid verification
response may mark the local ownership linked. A local persistence failure after
remote verification remains recoverable; it is not described as a remote
rollback.

Deterministic conflict rules are:

- empty remote account: begin;
- exact attempt/manifest/receipt: resume idempotently;
- partial exact attempt: resume from receipts;
- unrelated/pre-existing remote rows: conflict, preserve both;
- changed local data before first remote begin: invalidate consent;
- identity/catalog/personal-product collision: conflict, no overwrite;
- another device/attempt or account: conflict;
- stale/unsupported client: version/gate rejection.

No device-clock last-write-wins rule exists.

## Cancel, rollback, and preservation

- Before remote begin: consent can be cancelled; the immutable A binding stays.
  The Staging UI exposes this action after preparation and before the first
  hosted begin acknowledgement.
- After partial upload but before completion: the exact authenticated owner may
  call attempt-bound rollback. Rows are removed child-first, receipts/attempt
  last. There is no arbitrary row-ID hard-delete endpoint.
- After verified completion: client rollback is denied. Both local and remote
  data remain; recovery requires a future reviewed procedure.
- ProductState V4 is never deleted, replaced, or relabelled by this sprint.
  Migration completion does not make cloud data the runtime authority.

## Machine-checkable activation gate

Client activation requires every condition below; the server independently
requires an explicit Staging deployment approval, the corresponding control
row, and the Edge switch.

1. compiled internal Staging build;
2. environment exactly `staging` (Production has an unconditional deny);
3. authenticated Supabase UUID;
4. `WAYTASK_CLOUD_MIGRATION_ENABLED=YES`;
5. approved schema version 1;
6. hosted endpoint configured and enabled;
7. **real signed-session A/B isolation recorded PASSED**;
8. session refresh/revocation recovery gate recorded PASSED;
9. no unresolved migration security blocker.

Tracked Debug, Staging fallback, and Release values currently use schema `0`
and all four security switches `NO`; Migration itself is `NO`. Even an isolated
feature-flag flip remains blocked. Production also fails the environment check
and has no credentials.

## Privacy and errors

There is no payload logging. Diagnostics may record only an opaque attempt ID,
batch number/count, category counts, typed state/error, duration bucket, and
retry count. Tokens, Apple material, Private Relay email, names, list/product
content, images, coordinates, payloads, and privileged credentials are banned.

Client UI maps failures to safe Offline, Session expired, Account conflict,
Preview changed, Recoverable service error, Rollback required, or Security gate
blocked copy. Provider, HTTP, JWT, SQL, Supabase, and stack details never reach
the user. The Edge boundary collapses database detail into a small status/code
allowlist, and iOS maps validation and verification failures into separate typed
recovery states.

## Validation evidence

### Locally proven

- Clean disposable PostgreSQL rebuild applied all five local migrations.
- Prior suites remained green: authorization/RLS 50/50, constraints 30/30,
  identity inputs 26/26, Secure-AI quota 8/8.
- New migration server suite: 22/22, covering default OFF, anonymous/direct
  mutation denial, server-derived owner, forged owner rejection, exact duplicate
  idempotency, order/parent enforcement, A/B attempt isolation, rollback,
  verification-only completion, single-owner/dataset identity, row ownership,
  declared-count/batch quotas, and RLS/FORCE RLS.
- Edge validation contract: 6/6, including canonical payload-hash verification.

### Simulator proven

- Final migration client suite passed 16/16, including protected-ledger
  mode/round-trip, deterministic international/multi-list fixtures,
  resolved-entry proof, permanent A binding, interrupted retry, cancellation,
  rollback, verification failure, and ProductState preservation.
- Before the last narrowly scoped server/UI hardening, the selected related
  account/session/configuration/Keychain/ProductState/Map tests passed 51/51;
  the final changed migration/account coordinator selection passed 23/23, and
  the final migration-only confirmation passed 16/16.
- ProductState remains present across success, interruption, verification
  failure, cancellation, and rollback. A ProductState Map/geofence runtime test
  passed; no Map/location/geofence source changed.

### Build proven

- Generic unsigned `WayTask-Staging` build passed with bundle
  `h.WayTask.staging`.
- Generic unsigned Production/Release boundary build passed with bundle
  `h.WayTask`.
- Built configuration assertions show Staging Accounts only; Migration, Sync,
  Secure AI, every migration activation input, and every Production cloud flag
  resolve OFF. Tracked-source and both final built-app secret scans passed.

### Hosted Staging not executed in WT-032C

The new SQL migration and Edge Function are not deployed, the server switches
remain absent/OFF, and no synthetic or real row was written. Existing hosted
18/18 Auth/Data API and 56/56 RLS evidence remains the WT-032B.1 baseline, not
proof of the undeployed WT-032C endpoint.

## Remaining risks and gates

- Real signed User A/User B symmetric isolation and account switching remain
  externally unproven and block activation.
- The new migration SQL/function must be reviewed, pushed through the approved
  migration path to WayTask Staging only, then revalidated with synthetic users
  and fixtures after separate approval.
- Server rate/abuse telemetry beyond bounded sequential batches requires the
  synthetic hosted QA review.
- Hosted interruption, token refresh during a batch, function timeout, and
  pre-completion rollback require synthetic Staging evidence.
- Apple account-change/server-to-server lifecycle remains the named later
  pre-Production compliance/backend slice.
- Migration completion deliberately does not activate Sync or switch the local
  runtime authority.

## Kill switches and rollback

Disable any one of: the iOS Migration flag, schema approval, endpoint approval,
A/B gate, session-recovery gate, blockers-clear gate, server migration switch,
or private server control. Production remains independently denied. Before a
verified synthetic completion, roll back only the exact attempt through the
owner-bound RPC; never manually edit hosted schema or add permissive cleanup RLS.

See [synthetic/manual QA](MANUAL_QA.md).
