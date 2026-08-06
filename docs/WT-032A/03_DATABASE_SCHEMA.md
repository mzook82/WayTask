# Database Schema

The source of truth is the versioned migration
`supabase/migrations/20260806000100_wt032a_account_sync_foundation.sql`.
It applies to local or explicitly linked staging only in WT-032A.

## Resource graph

| Table | Identity and ownership | Important constraints | Deletion |
|---|---|---|---|
| `profiles` | PK `id`; `id = owner_user_id`; both reference Auth user | locale allowlist, display name 1–120 | client tombstone/update; hard delete trusted path |
| `user_preferences` | UUID PK; one row per owner | locale, metric/imperial, ISO currency shape, timezone shape | tombstone |
| `shopping_lists` | Existing local UUID PK; `(id, owner)` unique | title 1–120, purpose allowlist | tombstone; entries restrict hard delete |
| `personal_products` | Existing local UUID PK; `(id, owner)` unique | name 1–200, source/lifecycle/barcode/catalog ID, optional image metadata | lifecycle plus tombstone |
| `shopping_list_entries` | Existing local UUID PK | composite owner FKs to list and product, quantity, unit, lifecycle/provenance consistency | tombstone; no hard delete |
| `saved_stores` | Existing local UUID PK | coordinate/radius/text/source/URL validation; explicit precision consent marker | tombstone |
| `notification_preferences` | UUID PK; one row per owner | quiet-hours consistency, timezone, radius | tombstone |
| `device_installations` | installation UUID PK; `(id, owner)` unique | iOS only, semver shape, locale, hash-only push token | revoke then tombstone |
| `sync_mutations` | mutation UUID PK | owner-device composite FK; unique owner/device/idempotency key; SHA-256/count/size/status consistency | immutable client receipt |
| `catalog_releases` | release UUID PK | name/version/SHA-256/publish/withdraw consistency | trusted admin only |
| `waytask_admin.migration_audit` | server UUID PK | not in exposed schema and no client privileges | trusted admin only |

Every private row has `owner_user_id uuid not null references auth.users(id)`.
User-visible names are never identity. All sync candidates use `created_at`,
`updated_at`, server-managed positive `revision`, and where relevant
`deleted_at`. A before trigger rejects changes to ID, owner, or creation time and
increments revision on update.

Composite foreign keys prevent a child from naming a list, product, or device
owned by another user even if policy code regresses. Parent-child RLS repeats
the ownership check, providing defense in depth.

## Deliberate exclusions

Shopping sessions, session stops/lines, immutable product history, images in
Storage, the shared product catalog, sharing/collaboration, store reports, and
account-deletion jobs are not first-sync tables. `catalog_releases` exposes
release metadata only. No Edge Function is added in this sprint.

## Limits

- list name 1–120 characters; product name 1–200; note 2,000;
- quantity `numeric(12,3)`, 0.001–999,999.999;
- mutation batch 1–500 rows and metadata-declared payload 1–1,048,576 bytes;
- image metadata reserves JPEG/PNG/HEIC/WebP, 10 MiB and 12,000 px limits, but
  Storage upload is disabled/out of scope;
- timestamps are `timestamptz`; clients use RFC 3339 and server timestamps for
  ordering; UUID columns provide syntactic UUID enforcement.

## Delete behavior

Auth identity deletion cascades private rows only through a trusted deletion
orchestration. Ordinary clients cannot hard-delete any first-version table.
Entries/products use `RESTRICT` relationships so an accidental parent delete
cannot silently erase child meaning. The account-deletion server path must
order child deletion explicitly inside a retryable job.
