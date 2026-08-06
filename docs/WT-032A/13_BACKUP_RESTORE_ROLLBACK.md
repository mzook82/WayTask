# Backup, Restore, Migration, and Rollback Runbook

## Targets and authority

Production owner and backup/restore operator roles must be named before launch.
Only an authorized on-call/database operator with a recorded incident/change
ticket may initiate restore. App clients, support dashboards, and Edge Functions
cannot restore databases. Two-person approval is required for Production restore
or destructive migration.

Provisional objectives for first production design review: RPO ≤24 hours with
daily backups, RTO ≤8 hours for ordinary restore. If account/sync becomes a
material user backup, approve PITR and tighten objectives (proposed RPO ≤15 min,
RTO ≤4 hours) based on plan capability and tested timings; do not promise these
before a measured drill.

## Backup

- Confirm Supabase plan automatic backup frequency, encryption, geographic
  handling, retention, and restore method; record evidence, not assumptions.
- Take/export an explicit manual logical backup before any risky/data migration,
  record database version, migration head, schema digest, row counts, and owner
  counts, and test readability.
- Enable PITR before Production sync if approved objectives require it; document
  WAL retention/cost and the exact restore-point selection authority.
- Future Storage images need a separate versioned object backup/inventory. A DB
  backup containing paths is not an image backup.
- Backups are sensitive, access-controlled, encrypted, retention-limited, and
  excluded from development fixtures.

## Restore

1. Freeze or feature-flag cloud writes; Guest/local use continues.
2. Preserve incident evidence and choose a recovery point before the bad event.
3. Restore to a new isolated recovery project/database—never over the original
   first.
4. Apply/confirm code-compatible migrations and compare schema digest.
5. Validate Auth user references, per-table counts, distinct owners, orphan
   checks, revisions/tombstones, list-entry/product relationships, constraints,
   and readable Unicode.
6. Run the 50-test RLS suite as anonymous/User A/User B and direct-ID/filter
   attacks. Confirm the admin schema is not client-accessible.
7. Validate representative app reads with cloud writes still disabled.
8. Record actual recovery point, data gap, duration, operator and approvers.
9. Promote by controlled endpoint/project switch only after approval; rotate
   affected credentials and monitor backlog/conflicts.

## Schema change and rollback

- All changes are ordered Git migrations. Production Dashboard DDL is forbidden;
  emergency DDL must be captured immediately as a reviewed migration.
- Use expand → deploy compatible readers/writers → backfill/resume → verify →
  contract. New columns are nullable/default-compatible until old supported app
  builds are safe.
- Prefer roll-forward. Never edit an applied migration. Destructive contract
  migrations require explicit backup, restore evidence, old-client analysis and
  approval.
- Feature flags independently disable account UI, cloud writes, first migration,
  and any Edge endpoint. Read/local use remains available.
- Rollback can pause writes/migration, revert client behavior, disable an Edge
  deployment, or route to the last compatible schema. It must not downgrade or
  delete local ProductState.

## Repeatable restore drill

1. In staging, create User A and User B and distinct profiles/lists/products,
   child entries, preferences, stores, tombstones and mutation receipts.
2. Capture isolated snapshot/backup and timestamp it.
3. Add post-snapshot canary data, then simulate bounded deletion/corruption.
4. Restore the snapshot to a new recovery environment.
5. Verify expected pre-snapshot counts and absence of post-snapshot canary;
   owner IDs, FKs, constraints, revisions/tombstones, Unicode and hashes.
6. Run anonymous/A/B/admin RLS suite, direct-ID/filter/parent attacks, and app
   read-only smoke tests.
7. Record RPO gap, RTO duration, commands/tool versions, evidence, discrepancies,
   operator and approval. Open fixes and repeat until pass.

WT-032A defines this drill but has not executed a managed Supabase backup/restore;
that remains a hard Production blocker.
