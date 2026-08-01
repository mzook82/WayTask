# WT-033A T-08 — Session, History, Archive, and Saved-Location Semantic Migration

**Execution date:** 2026-08-01 (Asia/Hebron)

**Starting branch:** `main`

**Starting commit:** `3ef06c5bf0408b057bbe1f2eebbe508db1e4e629`

**Starting status:** clean; `HEAD`, `main`, and `origin/main` were identical

**Commit status:** review worktree only; T-08 was not committed

## Authority and Footprint Gate

Before any write, the repository was clean and the committed sequence was
verified as T-01 `d81df92`, T-02 `d16852e`, T-03 `f048e47`, T-04 `0d4e0a8`,
T-05 `78961f1`, T-06 `d583006`, and T-07 `3ef06c5`. The governing S-02 SHA-256
was `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361`.

The exact S-02 T-08 assignment was:

> T-08 | Migrate Sessions, history, Completed/Recent archive, saved-location
> evidence, and exceptions | TC-10, co-approved TC-11, TC-13; migration tests |
> All Session evidence/candidates retained; collected not promoted; legacy
> aggregates unchanged; archives read-only; exceptions complete/privacy-safe |
> Discard candidate; no partial promotion | D-03–D-07, D-19, D-23,
> D-28–D-32

This matched the execution instruction. S-02 assigned no evidence filename, so
the authorized fallback filename is used here. The final footprint is:

- TC-13: `WayTask/Persistence/WayTaskProductStateMigration.swift`;
- TC-11: `ShoppingSession.swift`, limited to making inactive V4
  `sourceListID` optional so missing legacy identity remains `nil` instead of
  being fabricated;
- T-08 tests:
  `WayTaskTests/Persistence/WayTaskSessionHistoryArchiveMigrationTests.swift`;
- this evidence document.

TC-10 `ProductHistory.swift` required no edit because its committed legacy
aggregate and inactive V4 event declarations already represent the approved
boundary. File-system synchronization compiled and ran the new Swift test file
without a `project.pbxproj` edit.

## Protected Source and Candidate Ownership

T-08 accepts only a committed T-07 receipt whose status and completion are
`product_list_semantic_migration_complete`, whose candidate is still owned by
the T-06 stage/attempt marker, and whose promotion/startup flags are false.
Before conversion it revalidates:

- the protected source database and exact sidecar inventory against the T-06
  source fingerprint;
- the task-owned V3 physical candidate against the T-06 candidate fingerprint;
- the inactive V4 target against the T-07 target fingerprint.

The protected original is never opened for semantic reads. T-08 reads only the
explicit T-06 physical-candidate URL with `allowsSave: false`. It appends only
to the explicit task-owned inactive V4 target URL. Every SwiftData
configuration in the migration boundary has an explicit URL; no application
default-store configuration is used.

On success the original database and every source sidecar are fingerprinted
again. On failure the T-06 ownership-checked rollback closes resources,
removes the whole marked attempt directory and only its enumerable artifacts,
and revalidates the protected source. There is no source rename, truncate,
repair, replacement, in-place migration, candidate promotion, or partial
promotion API.

## Stage, Attempt, and Fingerprint Identity

The deterministic T-08 stage version is
`wt033a.tc13.t08.session-history-archive-location.v1`. Its identity hashes the
version, exact T-07 semantic-stage identity and semantic digest, V3 source
schema identity, and inactive V4 candidate schema identity. The migration
retains the T-06 deterministic attempt identity, source fingerprint, physical
candidate fingerprint, and attempt ownership marker.

Successful completion records status and completion
`session_history_archive_location_semantic_migration_complete`. It writes the
T-08 semantic digest and final target fingerprint into the owned manifest and
summary. The final candidate fingerprint must match across two consecutive
post-reopen inventories. The receipt continues to report:

- Product/List semantic conversion complete;
- Session/history/archive/location semantic conversion complete;
- `promotionAuthorized == false`;
- `startupActivationAuthorized == false`.

## Session Mapping

- Every legacy Session UUID is preserved exactly. Every active claim remains a
  separate recovery candidate; unrelated Sessions are never selected or
  merged.
- Exact source-list UUID is preserved when present. Missing identity remains
  `nil`; source revision remains `nil` with `legacyUnknown` provenance.
- Active and unexpired evidence maps to `active`. At the inclusive 12-hour
  inactivity boundary it maps deterministically to `expired`; the approved
  72-hour maximum boundary is also retained by the policy calculation.
- Inactive plus finished evidence maps to `finished` with
  `legacyIncomplete`. Inactive plus unfinished evidence remains explicit
  `legacyInactive`/`legacyUnresolved`. Active plus finished evidence remains
  active and is classified as a lifecycle contradiction rather than silently
  reconciled.
- Line identities and snapshot identities are deterministic. A valid legacy
  compatibility UUID is resolved only through the exact source list, the
  exact legacy entry, and T-07 entry aliases. Zero or multiple exact matches
  create a visible unresolved line; no name or barcode matching is used.
- Collected tokens set execution evidence only. They never create final
  outcomes, purchases, history events, list resolution, or Product lifecycle
  authority. Foreign collected tokens and duplicates are preserved as
  privacy-safe exception evidence.
- Store UUID, display snapshot, and valid coordinates are preserved. Invalid
  or incomplete location evidence remains explicit and is never guessed.
- Tombstoned Products remain removed. A current/nonterminal Session reference
  is classified; no implicit Restore exists.

## History, Archive, and Saved-Location Mapping

Legacy `ProductHistory` aggregate UUIDs, keys, snapshots, dates, counts,
source values, interval, and legacy completion date are copied unchanged into
the inactive candidate. They are not attached to a target Product by name or
barcode. T-08 creates zero purchased `ProductHistoryEvent` records; unlinked
legacy aggregates receive explicit exception evidence.

Completed and Recent list and entry UUIDs, ordering, quantities, snapshots,
and relationship evidence are preserved as inactive V4 archive lists and
entries. Checked legacy archive evidence uses legacy-unknown resolution; it is
not purchase truth and is not writable production authority. Broken archive
relationships remain explicit rather than being dropped.

Saved `GeoLocation` identity, title, coordinates, radius, category, address,
notes, source type, and exact compatibility-item relationships are preserved
inside the candidate. Only exact UUID relationships are retained. An
unprovable relationship is classified as `saved_location_unresolved`; no
Product name, barcode, proximity, ordering, or first/default selection is
used.

The reopened semantic snapshot includes the complete T-07 Product/List base,
and equality plus the semantic digest prove that T-08 did not redesign or
drift the T-07 result.

## Exception and Privacy Proof

T-08 extends the T-06 bounded ledger with deterministic categories for
unresolved Session lines, multiple Session candidates, unresolved archives,
unlinked legacy history, unresolved saved locations, invalid/duplicate Session
tokens, foreign collected tokens, missing source-list identity, ambiguous
Session items, Session lifecycle contradictions, invalid Session stores,
tombstone active references, and Session exception overflow.

The general ledger retains its T-06 fixed capacity, stable category/digest
grouping, occurrence totals, category totals, and overflow totals. Per-Session
evidence retains at most 100 deterministic groups plus an explicit overflow
record. Duplicate token evidence records the complete stable ordinal set and
occurrence count. Invalid-token evidence contains only a keyed digest, ordinal,
byte length, and collection label; it contains no raw token.

Detailed T-08 exception evidence is encoded with sorted keys in the owned
candidate artifact `session-migration-exception-evidence.json`. The owned
summary is `session-history-archive-location-summary.json`. Neither diagnostics
nor evidence contain raw Product names, barcodes, notes, image bytes,
coordinates, source rows, or attachments. Private snapshots remain only in
the inactive candidate records whose purpose is evidence preservation.

## Physical, Reopen, Immutability, and Rollback Proof

The physical focused fixture is wholly synthetic and is created only beneath
an explicit random `/private/tmp/WT033A-T08-Test-*` root. It uses distinct
builder, protected-source, and candidate roots. The database, WAL, and SHM are
inventoried and copied while the synthetic builder is open; no application
store or repository fixture is opened. Teardown removes that entire synthetic
root.

The physical test advances a real T-06 V3 candidate through committed T-07 and
T-08, reopens the inactive V4 target, reconciles identities/counts/
relationships, validates its semantic digest and stable fingerprint, and
compares every protected source component byte-for-byte before and after.
The failure test injects a target write failure, proves a deterministic
non-success classification, proves that the whole candidate attempt is gone,
proves a neighboring unowned artifact remains, and rechecks every protected
source component byte-for-byte.

## Focused Qualification

Both authoritative runs used the iPhone 17 Pro iOS 26.5 simulator and separate
clean DerivedData and result-bundle roots. Each physical test also generated a
separate random protected-source fixture root and candidate root.

| Run | Result | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| Focused A | 26 passed | 0 | 0 | 0 |
| Focused B | 26 passed | 0 | 0 | 0 |

The focused tests cover Session lifecycle states and contradictions, missing
identity, exact and ambiguous line reconstruction, collected/non-purchase
behavior, foreign/duplicate/invalid tokens, every active candidate, revision
and activity initialization, store snapshots and invalid coordinates, legacy
history, Completed/Recent archives, exact and unresolved saved locations,
tombstones, bounded overflow, enumeration-order stability, inclusive expiry,
physical reopen, source and sidecar immutability, failure cleanup, and absence
of startup/promotion/default-store access.

Development preflights were used only for defect discovery and are not counted
as qualification evidence.

## Regression and Build Matrix

The affected bundle selected the committed T-06 and T-07 suites,
`WayTaskSchemaMigrationTests`, Product State graph/persistence/domain/
repository suites, Product deletion, Product Catalog migration and
personalization suites, Shopping workspace persistence/UX coverage, and both
startup resilience/repair suites.

| Gate | Result | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| Affected regression bundle | 134 passed | 0 | 0 | 0 |
| Exact six-suite Phase 1 gate | 49 passed | 0 | 0 | 0 |
| Complete unfiltered `WayTaskTests` | 480 passed | 0 | 0 | 0 |
| Generic iOS unsigned Debug build | Succeeded, exit 0 | — | — | — |
| Generic iOS unsigned Release build | Succeeded, exit 0 | — | — | — |

The exact Phase 1 selectors were
`ProductStateCharacterizationSupportSelfTests`,
`ProductStateDomainCharacterizationTests`,
`ProductStatePersistenceCharacterizationTests`,
`ProductStateConsumerCharacterizationTests`,
`ProductStateDiagnosticsCharacterizationTests`, and
`ProductStatePerformanceBaselineTests`. No profile, fixture, threshold, or
existing expectation changed. All six full-target performance tests collected
metrics.

During the unfiltered run CoreSimulator initially denied one parallel clone
launch. Xcode recovered within the same invocation; the command exited 0 and
the final result bundle independently confirms all 480 expected tests passed
with zero failures or skips. No test or assertion was omitted.

## Hash, Static, and Scope Audit

Protected/final SHA-256 values before evidence creation:

| Artifact | SHA-256 | Result |
|---|---|---|
| S-02 roadmap | `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361` | Unchanged |
| `WayTask.xcodeproj/project.pbxproj` | `9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f` | Unchanged |
| `Package.resolved` | `42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244` | Unchanged |
| `WayTask/Models.swift` | `74062d07cd3b1546ec11ad8a550223ff4b33b646715c0aa61a8f57e38b2a345c` | Unchanged |
| `WayTaskSchema.swift` | `90841edae9796af551c453f6a3bcb65737db975a61a05505ccdb3bcef0e8f9b8` | Unchanged |
| TC-10 `ProductHistory.swift` | `57dd2b13e4e68d2292e5b45f5fe090f3b64344fe4c777a91f19cc47961e8da8c` | Unchanged |
| TC-11 `ShoppingSession.swift` | `86c66430467c2b8b15a104c11cf0394709d4767a2e3ba7d1fbd2e711222eb8d5` | Authorized T-08 output |
| TC-13 committed T-07 baseline | `c89948aff3373e9b686677f412e30b50e85f254dacf2a5efe6e7b98c7aa0966d` | Authorized T-08 extension only |
| TC-13 final T-08 source | `1c79711332281f4b24af81696c7242784596bcdaa8b92f35fb17b9ca757418e8` | T-08 output |
| T-08 focused tests | `385d7f4e48f58668b756138cddd2791044d180163dbe42cd8521b3ae2c8b8e5a` | T-08 output |
| T-06 focused tests | `702f6e7690b954a2dc93862d3f7c53254d4fb5ab1cebde5b488f78740e1d139a` | Unchanged |
| T-07 focused tests | `e9d6a7d305b57cfb565f46431f87ec66fadd92eff0971ecd5006b4bc36a64d97` | Unchanged |
| T-06 evidence | `f803d6c30e37c1777953383f25ad7a93c560909a9a1d09f655e39fcab5625383` | Unchanged |
| T-07 evidence | `afc64b50be550223df3b5dad29957b7c560bb2dea36ad70726a0882174aa1e` | Unchanged |

Committed T-01 through T-05 evidence also remained exact:

```text
d9f62bb63a5510633425d4bf055f2e911b4011f76ccd2eb36f421d550291410b  T-01
f39525267de1902c07a3d2c3f44ae26483b220ca5646789638981a589ef01dc3  T-02
c2338f096f9132351095e484cc17feb495a8c9c62e7444f81b551e79509a9bb5  T-03
86ecf19cf81b32913ca3dcfc5d90b5384150dcd5a214b3021c745ea20746ede2  T-04
43fda677a9fdc546341173db6f491d6f134db1ac62e0181a727b9d8233455d10  T-05
```

Static and repository audits prove:

- V3 remains the live schema and production migration-plan endpoint; inactive
  V4 is opened only at the explicit owned candidate URL;
- the only T-08 production entry point is defined in TC-13 and invoked only by
  the T-08 tests;
- no production startup caller, promotion/replacement API, default-store
  access, UI, ViewModel, Service, Map, Camera, notification, AI, Catalog,
  Product Knowledge, network, telemetry, or Sentry dependency was added;
- no Product/List semantic redesign, Product name/barcode identity guessing,
  purchase inference, tombstone clearing, or implicit Restore exists;
- no project, package, localization, asset, startup, or production caller file
  changed;
- no `fatalError` exists in the production migration source;
- `git diff --check` passes.

The sole build warning was the pre-existing unused `legacyByID` local in
`ProductCatalogMigrationTests.swift`; T-08 did not change that file.

## Temporary-Artifact Cleanup and Review Rollback

After extracting the totals and hashes above, all explicitly named
`/private/tmp/WT033A-T08-*` DerivedData roots, result bundles, build outputs,
and development preflights are removed. Test-owned synthetic fixture roots,
stores, WAL/SHM sidecars, manifests, ledgers, and attachments are removed by
test teardown. A final audit must find no T-08 temporary artifact and no store,
sidecar, DerivedData directory, or result bundle in the repository.

Review rollback is source-only: discard the two tracked T-08 diffs and remove
the untracked T-08 test and evidence document. This cannot touch an original
store or candidate because no production caller was activated and all test
stores live only in disposable task-owned temporary roots.

`T-08 COMPLETE — READY FOR REVIEW`
