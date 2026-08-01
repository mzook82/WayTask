# WT-033A T-07 Product and Shopping-List Semantic Migration Evidence

## Terminal Decision

`T-07 COMPLETE — READY FOR REVIEW`

This evidence covers execution step T-07 only. No T-08 Session, history,
archive, or location semantic conversion; T-09 startup activation; candidate
promotion; production caller conversion; or commit was performed.

## Starting Repository Gate

The mandatory pre-write gate was completed before implementation:

| Check | Result |
|---|---|
| Branch | `main` |
| Starting commit | `d5830065e84f77bc1e4dd6ddf7a68c0076d07882` |
| Starting worktree | Clean |
| `main` versus `origin/main` | Exact match at the starting commit |
| T-01 | `d81df92` committed |
| T-02 | `d16852e` committed |
| T-03 | `f048e47` committed |
| T-04 | `0d4e0a8` committed |
| T-05 | `78961f1` committed |
| T-06 | `d583006` committed |

The final review worktree remains on the same uncommitted `main` commit and
`origin/main` still resolves to the same commit. No fetch, merge, rebase,
checkout, or commit occurred.

## S-02 Authority and Footprint

The approved WT-033A S-02 roadmap is
`docs/Specifications/WT-033A_ProductStateTechnicalImplementation.md`, SHA-256:

```text
49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361
```

Its exact T-07 row is:

> T-07 | Migrate Products, lists, entries, revisions, duplicates, exact
> relationships, and tombstone contradictions | TC-13; TC-09; migration
> tests/fixtures | UUIDs/snapshots/tombstones preserved; all flag combinations
> deterministic; exact duplicates merge per D-26; no name/barcode guessing;
> second pass stable | Discard candidate and retry from protected original |
> D-15, D-17–D-18, D-24, D-25, D-26, D-27, D-32, D-37

This matches the execution instruction. S-02 assigns no evidence filename, so
the authorized fallback filename is used.

Final footprint:

- `WayTask/Persistence/WayTaskProductStateMigration.swift`: T-07-only TC-13
  Product/list semantic normalization, owned inactive V4 candidate writing,
  reopen/reconciliation, artifacts, status, receipt, and failure handling;
- `WayTaskTests/Persistence/WayTaskProductListSemanticMigrationTests.swift`:
  32 T-07-owned tests and synthetic fixtures;
- `docs/ImplementationEvidence/1.0.3/WT-033A_T07_ProductListSemanticMigration.md`:
  this evidence.

No TC-09 edit was required. The committed inactive V4 declarations in
`WayTask/Models.swift` already contain the approved Product, list, entry,
revision, lifecycle, resolution, Catalog snapshot, and relationship fields.
Adding another declaration would duplicate the T-02 graph. TC-09 and
`WayTask/Persistence/WayTaskSchema.swift` therefore remain byte-identical.

The synchronized Xcode group discovered and compiled the new test file. The
project file was not changed.

## Protected Source and Candidate Ownership

T-07 accepts only a committed T-06 receipt with foundation status
`foundation_validated`, completion
`candidate_ready_for_semantic_migration`, physical candidate schema V3,
inactive target schema V4, and a valid TC-13 ownership marker. It does not
accept a source URL independently and does not use the application-default
store.

Before semantic work, TC-13:

1. identifies the database component from the T-06 source inventory;
2. re-inventories and fingerprints the protected database and every present
   `-wal`, `-shm`, or `-journal` sidecar through the read-only byte boundary;
3. verifies the T-06 physical candidate inventory and fingerprint;
4. reads Product/list compatibility data only from the owned V3 physical
   candidate using an explicit URL and `allowsSave: false`;
5. writes only beneath the ownership-marked T-06 attempt directory;
6. re-inventories and fingerprints the source after semantic completion.

The source is never opened by the T-07 SwiftData boundary. It is never
migrated, repaired, renamed, replaced, truncated, deleted, or promoted. Tests
retain real synthetic SQLite WAL and SHM sidecars and compare the complete
component byte map before and after both success and failure.

The semantic target is the separate owned file
`product-list-semantic-v4.store`, next to the existing owned V3
`candidate.store`. Its sidecars are automatically contained by the marked
attempt directory and are enumerated recursively. Additional owned artifacts
are:

- `.wt033a-tc13-owner.json`;
- `migration-manifest.json`;
- `migration-exceptions.json`;
- `product-list-aliases.json`;
- `product-list-semantic-summary.json`.

No promotion, replacement, default-store, or live-startup API exists in the
T-07 implementation.

## Stage, Attempt, and Fingerprints

The deterministic semantic stage version is:

```text
wt033a.tc13.t07.product-list.v1
```

Its identity is SHA-256 over that version, the committed T-06 foundation stage
identity, source semantic schema V3, and candidate semantic schema V4. The
attempt identity remains the T-06 deterministic attempt identity and therefore
binds source inventory/fingerprint, stage, and caller seed.

The manifest and privacy-safe semantic summary record semantic stage identity,
attempt identity, physical candidate fingerprint, stable post-reopen V4 target
fingerprint, semantic digest, counts, exception/overflow totals, and completion
flags. The semantic digest is SHA-256 of the sorted-key, millisecond-date JSON
projection of the normalized Product/list/entry graph.

The target is reopened with an explicit URL and `allowsSave: false`. TC-13
then proves exact snapshot equality, digest equality, UUID uniqueness,
relationship uniqueness, referential integrity, and revision invariants. Two
consecutive post-reopen inventories must have the same fingerprint, accounting
for SQLite's first-reopen WAL finalization while still rejecting later drift.

Success advances only to:

```text
product_list_semantic_migration_complete
```

The receipt and summary continue to report:

- `promotionAuthorized == false`;
- `startupActivationAuthorized == false`;
- `sessionHistoryLocationSemanticMigrationComplete == false`.

## Product Identity and Snapshot Mapping

For each safely identified legacy Product:

- `Product.id` is copied exactly; name, barcode, display order, and relationship
  order never create identity;
- target Product revision is deterministically initialized to `1`;
- any valid `deletedAt` evidence produces `removed` lifecycle and is never
  cleared; the earliest non-fabricated removal time is preserved;
- name, image data, brand, category, barcode, image URL, source value, creation
  time, and update time are preserved as display/evidence fields, not identity;
- the exact Catalog identifier is retained only when already present as a
  nonempty, unmodified identifier; invalid/ambiguous identity is classified;
- Catalog display name, locale, category, icon, and update snapshots are copied
  as snapshots and never promoted to identity;
- legacy Product fields not represented in the approved target graph remain in
  the owned V3 physical candidate and produce `unsupported_record` evidence;
- a missing Product UUID is excluded and recorded as
  `missing_product_identity`; it is never merged by name or barcode.

Product Library lifecycle is independent of list membership and all legacy
checked/completed flags.

## Complete Legacy Flag Matrix

The D-25 mapping is explicit and deterministic:

| `isChecked` | compatibility `isCompleted` | Product lifecycle | Entry lifecycle | Resolution | Revision | Evidence |
|---|---|---|---|---|---:|---|
| `false` | `false` | Preserved active/removed | `needed` | None | List `1` | No flag exception |
| `false` | `true` | Preserved active/removed | `needed` | None | List `1` | `legacy_flag_contradiction` |
| `true` | `false` | Preserved active/removed | `resolved` | `legacyUnknown`, deterministic effective time, `legacyMigration` provenance | List `1` | Compatibility evidence retained |
| `true` | `true` | Preserved active/removed | `resolved` | `legacyUnknown`, deterministic effective time, `legacyMigration` provenance | List `1` | Compatibility evidence retained |

No combination infers purchase, completion, outcome, history, provenance, or
global Product authority. Compatibility records influence only contradiction
classification and the approved legacy-unknown entry resolution.

## Lists, Entries, Relationships, and Revisions

Weekly/current Shopping Lists preserve their exact UUID, title, purpose,
earliest creation time, latest update time, and receive one durable initial
revision of `1`. Completed and Recent archive lists and their entries are
counted as deferred T-08 evidence and are not converted.

Entries preserve exact entry UUID where present, exact stored list UUID, exact
stored Product UUID, quantity, deterministic sort value, creation time, and the
D-25 lifecycle mapping. Missing entry identity, list identity, Product
identity, or a broken relationship is classified; no name/barcode repair and no
first/default/latest/global list selection exists. An exact stored Product UUID
may remain authoritative when the relationship object disagrees, with an
`ambiguous_relationship` exception as required by D-27.

The second-pass reconciliation requires:

- one Product row per Product UUID;
- one list row per list UUID and exactly revision `1`;
- one entry UUID per target entry;
- one membership edge per exact list UUID/Product UUID pair;
- every entry linked to exactly one target list and Product;
- exact Product/list/entry counts and semantic digest.

Any uniqueness, count, revision, dangling relationship, or digest failure stops
before promotion and discards the candidate attempt.

## D-26 Duplicates, Aliases, and Tombstones

Canonical selection is independent of source enumeration order:

- same-UUID Product rows are ordered by earliest creation time and then source
  row UUID; compatible display/Catalog snapshots merge, required fields are
  preserved, and the strongest tombstone evidence wins without Restore;
- same-UUID list rows require compatible title/kind, use the same deterministic
  ordering, and produce one list/revision;
- entry rows merge only inside the exact `(list UUID, Product UUID)` group;
  survivor is earliest creation time then lexicographically smallest entry UUID,
  quantity is maximum positive finite value, sort order is minimum finite
  value, creation time is earliest, and lifecycle is `needed` if any row is
  unchecked, otherwise resolved `legacyUnknown`;
- duplicate relationship edges produce one target entry and never leak across
  lists;
- same-name or same-barcode records with different Product UUIDs remain
  separate;
- incompatible snapshots, identity collisions, unsupported list kinds, and
  other truth-requiring ambiguity stop semantic completion.

Each approved merge emits a deterministic alias/evidence record with kind,
source and canonical UUIDs, privacy-safe evidence digest, and stable ordinal.
Every merge also records `duplicate_merge`. Equivalent compatibility rows are
deduplicated as evidence; contradictory compatibility states are classified.

Mixed active/removed duplicate evidence records an ambiguity while preserving
removed lifecycle. A removed Product referenced by one or more active entries
remains removed and each exact reference records
`tombstone_active_reference`. T-07 never invokes Restore or clears a tombstone.

## Exception Ledger and Privacy

T-07 uses the bounded T-06 ledger categories:

- `unsupported_record`;
- `ambiguous_record`;
- `legacy_flag_contradiction`;
- `duplicate_merge`;
- `missing_product_identity`;
- `missing_list_identity`;
- `ambiguous_relationship`;
- `tombstone_active_reference`.

Facts are sorted by category and safe SHA-256 digest before recording. Entry
UUIDs, ordinals, occurrence counts, category totals, overflow totals, and
overflow category totals are deterministic. Capacity overflow never removes
the aggregate occurrence/category evidence.

The ledger, aliases, manifest, summary, receipts, and diagnostics contain no
raw Product name, note, barcode, image, coordinates, source row, attachment,
credential, account identifier, or error text. Synthetic tests place private-
looking names and barcodes in input and prove they do not appear in the encoded
ledger. All diagnostic artifacts remain inside the owned attempt directory.

## V1/V2/V3 and Second-Pass Proof

Physical focused fixtures are synthetic and task-owned. Each fixture is first
built in its own temporary builder root, closed, and then database/WAL/SHM bytes
are copied to a distinct protected-source root. T-06 physically migrates the
owned copy to V3; T-07 reads that V3 candidate and writes/reopens the separate
inactive V4 target.

V1, V2, and V3 focused paths all passed, preserving Product, list, entry,
Catalog, flag, relationship, and source-sidecar assertions. No metadata-writing
probe was added to production, tests, project files, or repository scope.

The stability test clones one closed protected fixture byte-for-byte into two
independent source roots, uses independent candidate roots, and compares:

- target Products, lists, entries, and relationships;
- revisions and canonical selections;
- aliases and exception summaries;
- semantic digests;
- before/after source database and sidecar bytes.

Both results are identical and neither source changes.

## Failure, Cleanup, and Rollback

T-07 adds deterministic classifications for physical-candidate read,
normalization, target creation, target reopen, target validation, and target
fingerprint failures. Exception-ledger write failure remains the T-06
classification.

Every semantic failure uses the T-06 rollback boundary:

1. candidate resources leave scope;
2. the exact attempt parent, deterministic name, and owner marker are validated;
3. only the marked attempt directory and its candidate sidecars/artifacts are
   deleted;
4. the protected source and all sidecars are re-inventoried and fingerprinted
   through the read-only byte boundary;
5. deterministic non-success is returned with triggering, terminal, rollback,
   source-byte, and candidate-remains classification.

Injected creation and reopen failures prove source immutability and owned-only
cleanup. An unowned neighboring file remains present. No failed candidate can
become live because no promotion/replacement operation exists.

Review rollback is to discard these uncommitted T-07 changes. At runtime,
retry begins from the protected original through a fresh T-06 attempt; a T-07
candidate is never repaired or promoted.

## Focused Qualification

Exact selector for both authoritative runs:

```text
-only-testing:WayTaskTests/WayTaskProductListSemanticMigrationTests
```

| Run | DerivedData | Result bundle | Passed | Failed | Skipped |
|---|---|---|---:|---:|---:|
| Focused A | `/private/tmp/WT033A-T07-Focused-A` | `/private/tmp/WT033A-T07-Focused-A.xcresult` | 32 | 0 | 0 |
| Focused B | `/private/tmp/WT033A-T07-Focused-B` | `/private/tmp/WT033A-T07-Focused-B.xcresult` | 32 | 0 | 0 |

Both `xcresulttool` summaries report `Passed`, zero expected failures, and
independent DerivedData/result bundles. Each run creates clean UUID-named
protected-source and candidate roots and removes its synthetic fixture roots.

Development preflights are not counted. A preflight identified expected SQLite
WAL finalization at the first target reopen; validation was corrected to
establish and then prove a stable post-reopen fingerprint. No legacy fixture,
expectation, or semantic rule was weakened.

## Affected Regression Qualification

The affected run selected:

- `WayTaskProductStateMigrationFoundationTests`;
- `WayTaskSchemaMigrationTests`;
- `ProductStatePersistenceGraphTests`;
- `ProductStatePersistenceCharacterizationTests`;
- `ProductStateCharacterizationSupportSelfTests`;
- `ProductStateRepositoryTests`;
- `ProductLibraryDeletionPersistenceTests`;
- `AddProductSaveCoordinatorTests`;
- `ProductCatalogMigrationTests`;
- `ProductCatalogCompatibilityLayerTests`;
- `CatalogProductPersistenceServiceTests`;
- `CatalogProductCompatibilityTests`;
- `ShoppingWorkspaceUXTests`;
- `StartupPersistenceResilienceTests`;
- `StartupRepairIdempotencyTests`.

Result: **108 passed, 0 failed, 0 skipped, 0 expected failures**.

This directly covers T-06, schema migration, target persistence,
characterization/support, repositories, deletion/tombstones, Catalog
migration/persistence/compatibility, Shopping persistence behavior, startup
resilience, and startup repair/idempotency.

## Exact Phase 1 Gate

The exact six selectors were:

- `ProductStateCharacterizationSupportSelfTests`;
- `ProductStateDomainCharacterizationTests`;
- `ProductStatePersistenceCharacterizationTests`;
- `ProductStateConsumerCharacterizationTests`;
- `ProductStateDiagnosticsCharacterizationTests`;
- `ProductStatePerformanceBaselineTests`.

Result: **49 passed, 0 failed, 0 skipped, 0 expected failures**. No profile,
fixture, threshold, or expectation was changed.

## Complete Target and Builds

| Gate | Result |
|---|---|
| Complete unfiltered serial `WayTaskTests` | 454 passed, 0 failed, 0 skipped, 0 expected failures |
| Generic iOS unsigned Debug build | Succeeded, exit `0` |
| Generic iOS unsigned Release build | Succeeded, exit `0` |

The complete total is the committed T-06 total of 422 plus exactly 32 T-07
tests. It collected metrics from all six performance tests.

An initial complete-target attempt using parallel simulator clones was rejected
as qualification evidence after Xcode reported simulator launch denial on two
clones. It was an infrastructure-only attempt, not a test assertion or product
regression. The authoritative replacement used a clean DerivedData root, clean
result bundle, one serial simulator destination, and passed all 454 tests in
1,197.126 seconds.

## Hash, Static, and Scope Audit

Protected/final SHA-256 values before evidence creation:

| Artifact | SHA-256 | Result |
|---|---|---|
| `WayTask.xcodeproj/project.pbxproj` | `9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f` | Unchanged |
| `Package.resolved` | `42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244` | Unchanged |
| `WayTask/Models.swift` | `74062d07cd3b1546ec11ad8a550223ff4b33b646715c0aa61a8f57e38b2a345c` | Unchanged |
| `WayTaskSchema.swift` | `90841edae9796af551c453f6a3bcb65737db975a61a05505ccdb3bcef0e8f9b8` | Unchanged |
| TC-13 committed T-06 baseline | `b5c5b2d7ff1d6578ba97b67366a3d7940419ad8e54adee77fc2786e51cd39a74` | Authorized T-07 extension only |
| TC-13 final T-07 source | `c89948aff3373e9b686677f412e30b50e85f254dacf2a5efe6e7b98c7aa0966d` | T-07 output |
| T-06 focused tests | `702f6e7690b954a2dc93862d3f7c53254d4fb5ab1cebde5b488f78740e1d139a` | Unchanged |
| T-06 evidence | `f803d6c30e37c1777953383f25ad7a93c560909a9a1d09f655e39fcab5625383` | Unchanged |
| T-07 focused tests | `e9d6a7d305b57cfb565f46431f87ec66fadd92eff0971ecd5006b4bc36a64d97` | T-07 output |

The committed T-01 through T-05 evidence hashes also remain exact:

```text
d9f62bb63a5510633425d4bf055f2e911b4011f76ccd2eb36f421d550291410b  T-01
f39525267de1902c07a3d2c3f44ae26483b220ca5646789638981a589ef01dc3  T-02
c2338f096f9132351095e484cc17feb495a8c9c62e7444f81b551e79509a9bb5  T-03
86ecf19cf81b32913ca3dcfc5d90b5384150dcd5a214b3021c745ea20746ede2  T-04
43fda677a9fdc546341173db6f491d6f134db1ac62e0181a727b9d8233455d10  T-05
```

Static/repository audit results:

- V3 remains the live schema and production migration-plan endpoint;
- V4 remains inactive and is opened only at the explicit owned target URL;
- no production call site invokes T-07;
- no promotion, replacement, startup, UI, ViewModel, Service, Map, Camera,
  notification, AI, Catalog repository, Product Knowledge repository, network,
  telemetry, or Sentry dependency was added;
- no Session/history/archive/location semantic fetch/write mapping exists;
- no Product name/barcode identity comparison, tombstone clearing, explicit
  Restore, or legacy-Boolean Product authority exists;
- the only filesystem removal in TC-13 is the pre-existing T-06
  ownership-validated candidate cleanup;
- no `fatalError` exists in the production migration source;
- no project, package, localization, asset, startup, or production caller file
  changed;
- `git diff --check` passes.

## Temporary-Artifact Cleanup

After result extraction, the explicitly named T-07 DerivedData roots, result
bundles, rejected parallel preflight artifacts, and compile preflight root under
`/private/tmp` were removed. No wildcard, source store, repository file, or
unowned path is part of that cleanup. Test-owned synthetic roots and store
sidecars were already removed by test teardown. A final `/private/tmp` audit
found no `WT033A-T07-*` artifact.

The review worktree intentionally retains only the three authorized T-07 paths
listed above. Nothing has been committed.

`T-07 COMPLETE — READY FOR REVIEW`
