# WT-033A T-06 — Protected Candidate-Store Migration Foundation Evidence

## Executive Summary

T-06 introduced TC-13 as the single inactive Product State semantic migration
owner and established the protected original/candidate-store foundation needed
by later T-07 and T-08 semantic conversion. The implementation inventories and
fingerprints an explicit source store and every recognized SQLite sidecar,
resolves source schema metadata through an immutable read-only SQLite
connection, creates only attempt-owned candidate artifacts, physically migrates
V1/V2/V3 candidate copies to the shipped V3 representation, reopens and
validates the candidate, and fails before any promotion boundary.

The original URL is never passed to SwiftData or Core Data. Candidate failure
removes only the exact marked attempt directory and revalidates source bytes
through the read-only inventory boundary. A candidate can be returned only as
`candidateReadyForSemanticMigration`; semantic conversion remains incomplete
and promotion is always unauthorized.

T-07 Product/list conversion and T-08 Session/history/archive/location
conversion were not implemented. V4 remains inactive, the live application
continues to use V3, and no startup or production caller was added. Both
focused runs, affected regressions, the exact Phase 1 gate, all 422 unfiltered
tests, and generic unsigned Debug and Release builds passed.

## Starting State and Authorization Gate

The required read-only gate completed before the first repository write.

| Check | Verified value | Result |
|---|---|---|
| Branch | `main` | Pass |
| Starting commit | `78961f1ada46e39ed45b9a9ff2a15992e8f323ae` | Pass |
| Starting `git status --short` | Empty | Pass |
| `HEAD`, `main`, `origin/main` | Same commit | Pass |
| T-01 | `d81df92` committed | Pass |
| T-02 | `d16852e` committed | Pass |
| T-03 | `f048e47` committed | Pass |
| T-04 | `0d4e0a8` committed | Pass |
| T-05 / starting HEAD | `78961f1` committed | Pass |
| Synchronized application/test roots | Present in `project.pbxproj` | Pass |
| Project edit required | No | Pass |

An exploratory `/private/tmp` metadata probe was proposed during design but
was canceled before creation. Read-only verification found neither its source
path nor its proposed fixture directory, and the repository remained clean.
All eventual metadata-format proof used the authorized T-06 test file and
disposable synthetic fixture roots only.

Toolchain used for qualification:

- Xcode 26.6;
- Apple Swift 6.3.3;
- iPhone 17 Pro simulator, iOS 26.5, arm64;
- generic iOS unsigned Debug and Release configurations.

## Exact S-02 Authority and Footprint

S-02 §2 assigns TC-13 to
`WayTask/Persistence/WayTaskProductStateMigration.swift` as the one semantic
migration owner. S-02 §8 requires the protected original/candidate execution
order, deterministic stage/exception foundation, validation, and rollback.
S-02 §9.2 assigns T-06 only:

- new TC-13;
- T-06 additions to `WayTask/Persistence/WayTaskSchema.swift`;
- migration support tests;
- implementation evidence.

Its acceptance criteria are unchanged source store/sidecars, an isolated
candidate, deterministic stage identity and exception recording, and failure
that never replaces the source. Its rollback is deletion of only owned
candidate artifacts followed by protected-original reopen/revalidation. The
execution instruction matched this authority exactly.

The final footprint is:

| Path | T-06 action | SHA-256 after implementation |
|---|---|---|
| `WayTask/Persistence/WayTaskProductStateMigration.swift` | Created as TC-13 | `b5c5b2d7ff1d6578ba97b67366a3d7940419ad8e54adee77fc2786e51cd39a74` |
| `WayTask/Persistence/WayTaskSchema.swift` | Added only the inactive candidate physical plan | `90841edae9796af551c453f6a3bcb65737db975a61a05505ccdb3bcef0e8f9b8` |
| `WayTaskTests/Persistence/WayTaskProductStateMigrationFoundationTests.swift` | Created; 21 T-06-owned tests | `702f6e7690b954a2dc93862d3f7c53254d4fb5ab1cebde5b488f78740e1d139a` |
| `docs/ImplementationEvidence/1.0.3/WT-033A_T06_ProtectedCandidateStoreMigrationFoundation.md` | Created | This evidence |

File-system synchronization compiled both new Swift files without modifying
`project.pbxproj`.

## Source and Candidate Ownership Model

### Protected source

The request supplies one explicit source-store URL. TC-13 performs only these
operations against it:

1. enumerate the database and recognized sidecar URLs;
2. inspect regular-file/readability/size/mtime metadata;
3. stream bytes through SHA-256 using read-only `FileHandle` access;
4. read `Z_METADATA.Z_PLIST` through SQLite opened with
   `SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX` and URI
   parameters `mode=ro&immutable=1`;
5. repeat the byte inventory/fingerprint after metadata discovery, after
   physical candidate migration, on final success, and during failure
   rollback.

The source URL is never supplied to `ModelContainer`, a migration plan, a save
context, a repair service, or any replacement/quarantine API. Failed or
unreadable source inspection never becomes an empty-store interpretation.

### Task-owned candidate

The caller supplies an existing explicit candidate root distinct from the
source directory. TC-13 derives the attempt directory as:

```text
<candidate-root>/wt033a-tc13-<64-hex-attempt-identity>/
```

Every attempt contains:

- `.wt033a-tc13-owner.json` with exact stage and attempt identity;
- `migration-manifest.json` with safe stage state;
- `migration-exceptions.json` with the bounded privacy-safe ledger;
- `candidate.store` and only its candidate-owned SQLite sidecars.

The owner validates the exact parent, deterministic directory name, and marker
contents before removing an interrupted or completed attempt. A mismatched or
unmarked pre-existing directory is an ownership conflict and is never deleted.
Artifact enumeration walks the entire owned attempt, including hidden files.
No move, rename, replace, destroy, promotion, default-store, quarantine, or
source-deletion operation exists in TC-13.

Destination capacity is an injected capability. The live gate requires the
larger of 4 MiB or three times total source-component bytes before creating the
attempt. An unknown/failed capacity read is fail-closed.

## Store and Sidecar Inventory Rules

The deterministic component roles and exact paths are:

| Role | Path rule |
|---|---|
| Database | Exact supplied source/candidate store URL |
| Write-ahead log | Store path plus `-wal` |
| Shared memory | Store path plus `-shm` |
| Rollback journal | Store path plus `-journal` |

The database must exist, be a readable regular file, and be non-empty. Every
present sidecar must be a readable regular file. WAL and SHM must either both
be present or both absent; a rollback journal cannot coexist with WAL/SHM.
Any unknown sibling beginning with the store name plus `-` is an explicit stop
condition. Each component is size/mtime checked before and after hashing so a
change during inspection cannot be accepted.

Tests prove exact database/WAL/SHM discovery, per-component byte counts and
digests, aggregate fingerprint stability, fingerprint sensitivity to one
sidecar-byte change, inconsistent-sidecar rejection, and byte equality before
and after both success and failure.

## Stage, Attempt, and Fingerprint Identity

### Schema identity

The allowlist is exact:

- `WayTaskSchemaV1@1.0.0`;
- `WayTaskSchemaV2@2.0.0`;
- `WayTaskSchemaV3@3.0.0`;
- inactive semantic target `WayTaskSchemaV4@4.0.0`.

The physical candidate stage accepts V1/V2/V3 only and ends at V3. Missing,
multiple, malformed, unknown, or unsupported persistent version identifiers
are non-success stop conditions.

### Deterministic identities

The stage identity is SHA-256 over the canonical tuple:

```text
wt033a.tc13.t06.foundation.v1 | exact source schema | exact V3 candidate schema
```

The attempt identity is SHA-256 over:

```text
stage identity | source aggregate fingerprint | caller-supplied attempt seed
```

Equivalent inputs produce the same 64-hex identities and attempt path. A
repeated interrupted attempt with a valid ownership marker is removed and
recreated under that same deterministic identity.

### Fingerprints and status

Each component fingerprint is SHA-256 over exact bytes. The store fingerprint
is SHA-256 over the ordered component role, byte count, and component digest;
absolute paths and private contents are excluded. The copied pre-migration
candidate must exactly equal the source component manifest. After physical
migration and read-only reopen, two independent candidate inventories must
produce the same fingerprint or the attempt fails and is removed.

The candidate manifest records these deterministic status values:

1. `candidate_created`;
2. `source_copied`;
3. `physical_migration_completed`;
4. `candidate_reopened`;
5. `foundation_validated`.

Success completion is only `candidate_ready_for_semantic_migration`. Failure
is `failed_before_promotion`. Both receipt types return
`promotionAuthorized == false`; success also returns
`semanticConversionCompleted == false`.

## Exception Categories and Privacy Limits

T-06 defines only the ledger foundation and deterministic categories required
by later semantic work:

- `unsupported_record`;
- `ambiguous_record`;
- `legacy_flag_contradiction`;
- `duplicate_merge`;
- `missing_product_identity`;
- `missing_list_identity`;
- `ambiguous_relationship`;
- `tombstone_active_reference`;
- `unresolved_session_line`;
- `multiple_session_candidates`;
- `legacy_archive_unresolved`;
- `legacy_history_unlinked`;
- `saved_location_unresolved`.

Ledger callers provide a `WayTaskMigrationSafeDigest`, never diagnostic text.
The ledger stores only SHA-256 digests, deterministic category, stable ordinal,
deterministic UUID, and occurrence count. A repeated category/digest increments
the existing entry without changing its ordinal. New entries beyond capacity
increment total and per-category overflow counts, so unsupported or ambiguous
occurrences cannot be silently dropped.

The candidate JSON uses sorted keys and remains inside the owned attempt.
Tests use synthetic private-looking names, barcodes, notes, and coordinates and
prove none appears in the manifest, ledger, or diagnostic projection. TC-13
imports no UI, location, notification, camera, network, telemetry, Sentry,
Catalog, or Product Knowledge dependency.

T-06 does not record Product names, notes, barcodes, images, raw rows,
attachments, precise coordinates, credentials, tokens, account identifiers,
or error descriptions.

## V1/V2/V3 Physical Migration Proof

`WayTaskProtectedCandidatePhysicalMigrationPlan` is separate from the live
application plan and contains only the frozen V1→V2 and V2→V3 lightweight
stages. It stops at V3.

For each V1, V2, and V3 test:

1. SwiftData creates a synthetic builder store in a test-owned directory;
2. the closed builder database/sidecars are copied byte-for-byte to a distinct
   protected-source directory;
3. TC-13 inventories and fingerprints that protected copy;
4. TC-13 copies it into the marked candidate attempt;
5. only the candidate is opened using the candidate physical plan;
6. the candidate is dropped and reopened using V3 with `allowsSave: false`;
7. counts for all eight V3 entities are validated;
8. Product/list/entry UUIDs and legacy fields are read back unchanged;
9. source database and sidecar bytes are compared to their pre-run snapshot;
10. the owned candidate is removed.

All three paths proved V3 candidate identity and reopen. No V4 model container,
V3→V4 stage, semantic Product/list mapping, duplicate merge, tombstone repair,
Session conversion, history/archive conversion, or location conversion ran.

## Failure-Before-Promotion and Rollback Proof

The 21 focused tests cover deterministic handling of:

| Condition | Proven result |
|---|---|
| Missing source | `missing_source`; no candidate created |
| Unreadable source | `unreadable_source`; no empty-store inference |
| Unknown schema | `unknown_schema_identity` |
| Unsupported schema | `unsupported_schema_identity` |
| Missing/inconsistent sidecars | `inconsistent_source_inventory` |
| Insufficient capacity | `insufficient_destination_space` before copy |
| Candidate creation failure | `candidate_creation_failed`; owned directory removed if created |
| Physical migration failure | `physical_migration_failed`; candidate removed |
| Candidate reopen failure | `candidate_reopen_failed`; candidate removed |
| Candidate validation failure | `validation_failed`; candidate removed |
| Source fingerprint drift | `source_fingerprint_drift`; no success/promotion |
| Candidate fingerprint drift | `candidate_fingerprint_mismatch`; candidate removed |
| Exception-ledger write failure | `exception_ledger_write_failed`; candidate removed |
| Interrupted owned attempt | Exact marker validated, old attempt removed, deterministic retry succeeds |
| Cleanup failure | Terminal `cleanup_failed` retains the triggering classification and reports remaining artifacts |

Rollback before promotion is implemented as:

1. allow candidate SwiftData/container scope to close;
2. validate the exact attempt parent/name/marker;
3. delete only that attempt directory;
4. re-inventory and re-fingerprint the source through the read-only byte
   boundary;
5. return deterministic non-success with trigger, terminal, and rollback
   classification.

Success cleanup uses the same ownership proof and reports that it did not
access the source. Tests place an unowned neighbor beside the attempt and prove
cleanup leaves the neighbor and source intact. No failure receipt authorizes
promotion, and no failed candidate can replace the source because no promotion
or replacement operation exists.

## Focused T-06 Qualification

Selector for both authoritative runs:

```text
-only-testing:WayTaskTests/WayTaskProductStateMigrationFoundationTests
```

| Run | Clean DerivedData | Separate result bundle | Passed | Failed | Skipped |
|---|---|---|---:|---:|---:|
| Focused 1 | `/private/tmp/WT033A-T06-Focused1-DerivedData` | `/private/tmp/WT033A-T06-Focused1.xcresult` | 21 | 0 | 0 |
| Focused 2 | `/private/tmp/WT033A-T06-Focused2-DerivedData` | `/private/tmp/WT033A-T06-Focused2.xcresult` | 21 | 0 | 0 |

Every test creates UUID-named clean source and candidate roots beneath the
test process temporary directory and removes the complete fixture root with
`defer`. The two Xcode invocations used separate DerivedData and result bundles.
Both authoritative `xcresulttool` summaries reported `Passed`, 21 total tests,
zero failures, zero skips, and zero expected failures.

Development preflights are not counted as qualification evidence. One early
preflight exposed that the test fixture builder itself had written directly at
the later protected fixture URL; the tests were corrected to build elsewhere
and copy closed bytes into the protected directory. A substring assertion that
mistook `removeItem` for `moveItem` was also corrected. No existing test,
production behavior, semantic rule, or threshold was weakened.

## Affected Regression Qualification

The affected gate used these exact selectors:

- `WayTaskTests/WayTaskSchemaMigrationTests`;
- `WayTaskTests/ProductStatePersistenceGraphTests`;
- `WayTaskTests/ProductStateCharacterizationSupportSelfTests`;
- `WayTaskTests/StartupPersistenceResilienceTests`;
- `WayTaskTests/StartupRepairIdempotencyTests`;
- `WayTaskTests/ProductCatalogMigrationTests`.

Result: **33 passed, 0 failed, 0 skipped**.

This includes the required existing schema migration suite, Product State
support self-tests, startup resilience, startup repair/idempotency, inactive
target persistence graph, and existing Catalog migration characterization.
Existing migration characterization remains the baseline; no existing test or
fixture was modified.

## Exact Phase 1 Gate

The authoritative selectors were exactly:

- `WayTaskTests/ProductStateCharacterizationSupportSelfTests`;
- `WayTaskTests/ProductStateDomainCharacterizationTests`;
- `WayTaskTests/ProductStatePersistenceCharacterizationTests`;
- `WayTaskTests/ProductStateConsumerCharacterizationTests`;
- `WayTaskTests/ProductStateDiagnosticsCharacterizationTests`;
- `WayTaskTests/ProductStatePerformanceBaselineTests`.

Result: **49 passed, 0 failed, 0 skipped**. The serial run completed in
1,226.850 seconds. No profile, fixture, threshold, selector, or expectation was
changed.

## Complete Target and Builds

| Gate | Result |
|---|---|
| Complete unfiltered `WayTaskTests` target | 422 passed, 0 failed, 0 skipped, 0 expected failures |
| Generic iOS unsigned Debug build | `BUILD SUCCEEDED` |
| Generic iOS unsigned Release build | `BUILD SUCCEEDED` |

The complete target total is the committed T-05 total of 401 plus exactly 21
new T-06 tests. It ran serially with parallel testing disabled and completed in
1,202.850 seconds.

Debug and Release used separate clean DerivedData roots:

```text
/private/tmp/WT033A-T06-Debug-DerivedData
/private/tmp/WT033A-T06-Release-DerivedData
```

The only compilation diagnostics were the existing unused test-local
`legacyByID` warning in
`WayTaskTests/ProductCatalog/ProductCatalogMigrationTests.swift:136` and the
existing Sentry debug-symbol script dependency-analysis note. No file was
changed in response.

## Protected Hash and Scope Audit

### Project and package

| Protected path | Starting/final SHA-256 | Result |
|---|---|---|
| `WayTask.xcodeproj/project.pbxproj` | `9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f` | Unchanged |
| `WayTask.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | `42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244` | Unchanged |

### Frozen persistence/startup files

| Protected path | Final SHA-256 | Result |
|---|---|---|
| `WayTask/Persistence/WayTaskSchemaV1.swift` | `a82370847be17b15d15bebfd7aae72c48b98141f1fd2f346bb6afa8b33ff7a56` | Unchanged |
| `WayTask/Persistence/WayTaskStartupPersistence.swift` | `9eaf9dd7f95e96249d117a414084cdbdbb564bfb413a247f036bde29b55a7bd7` | Unchanged |
| `WayTask/Models.swift` | `74062d07cd3b1546ec11ad8a550223ff4b33b646715c0aa61a8f57e38b2a345c` | Unchanged |
| `ProductHistory.swift` | `57dd2b13e4e68d2292e5b45f5fe090f3b64344fe4c777a91f19cc47961e8da8c` | Unchanged |
| `ShoppingSession.swift` | `61310856a980c965fdbad9993f74054c6713071995f38a26384b75607e594383` | Unchanged |

`WayTaskSchema.swift` changed only at the explicitly authorized T-06 location:
26 inserted lines define the separate inactive V1→V2→V3 candidate physical
plan. The existing V2/V3 declarations, live `WayTaskSchemaMigrationPlan`,
`currentSchema == WayTaskSchemaV3`, inactive V4 schema accessor, and live
container composition are unchanged.

### T-01 through T-05 implementation/evidence

| Protected path | SHA-256 | Result |
|---|---|---|
| `WayTask/ProductState/Domain/ProductStateDomain.swift` | `4fb347ce5d8f780351e6f0fe7e1aad158279cbddc02e87eed8f10836c71c6ce8` | Unchanged |
| `WayTask/ProductState/Domain/ProductStateInvariantValidator.swift` | `4eda9aba6f76b75576426c67786e3245e10beaefce481944df24f6e49b4a25f4` | Unchanged |
| `WayTask/ProductState/Persistence/ProductStateRepositories.swift` | `3bc37ffe5e09c1ef0bd412dbf81f55616899c1165d1b3a2b1dd26282a80c3482` | Unchanged |
| `WayTask/ProductState/Application/ProductStateCommands.swift` | `58e70e75cb74d5d5c43cac4074e8dd5c045805d28f0d9b5093c3f7758180c177` | Unchanged |
| `WayTask/ProductState/Application/ProductStateCommandCoordinator.swift` | `d116fb6bda22faebd7ccc17679bf7e46ff554a4031b5648f77e5f268132f80b2` | Unchanged |
| `WayTask/ProductState/Application/ProductStateTransactionCoordinator.swift` | `3ae8e4aadd9e427de50cdca0d20fe7037a5cdb546043d63f9dcd9f3c9d3d264a` | Unchanged |
| T-01 evidence | `d9f62bb63a5510633425d4bf055f2e911b4011f76ccd2eb36f421d550291410b` | Unchanged |
| T-02 evidence | `f39525267de1902c07a3d2c3f44ae26483b220ca5646789638981a589ef01dc3` | Unchanged |
| T-03 evidence | `c2338f096f9132351095e484cc17feb495a8c9c62e7444f81b551e79509a9bb5` | Unchanged |
| T-04 evidence | `86ecf19cf81b32913ca3dcfc5d90b5384150dcd5a214b3021c745ea20746ede2` | Unchanged |
| T-05 evidence | `43fda677a9fdc546341173db6f491d6f134db1ac62e0181a727b9d8233455d10` | Unchanged |

`git diff --exit-code` over the protected files above passed. The prior
T-02-owned `WayTaskSchema.swift` baseline hash was
`68ffde0c4ed52051278311eb75d550545390c3ce943903a9d531011d0a8f4391`;
its change to the final hash is exactly the authorized 26-line T-06 addition.

### Static scope conclusions

- no `project.pbxproj`, package, entitlement, localization, Catalog, Product
  Knowledge, or asset change;
- no `WayTaskStartupPersistence`, `WayTaskApp`, `ContentView`, View,
  ViewModel, Service, Map, Camera, notification, AI, Catalog, Product
  Knowledge, network, telemetry, or Sentry caller/dependency;
- no production call to `WayTaskProductStateMigration`;
- no candidate promotion, source replacement, store destruction, source move,
  quarantine, or source deletion API;
- V3 remains the live schema and V4 remains inactive for application startup;
- no V3→V4 live stage and no T-07/T-08 semantic conversion;
- no application-default store URL is used by TC-13;
- no existing migration/startup/Phase 1 expectation changed;
- `git diff --check` passed for tracked and new T-06 content.

## Temporary-Artifact Cleanup

After extracting all authoritative `xcresulttool` summaries, the following
T-06-only artifact classes were explicitly deleted:

- focused/preflight/affected/Phase 1/full result bundles;
- focused/affected/Phase 1/full/build DerivedData roots;
- the T-06 cloned source-package cache;
- the failed sandbox-build result bundle;
- all test-created source stores, candidate stores, SQLite sidecars, manifests,
  ledgers, and attempt directories through per-test teardown.

Final searches under `/private/tmp` found no T-06 candidate store, source
fixture, SQLite sidecar, DerivedData root, result bundle, or attachment.

## Review Rollback Instructions

No commit was created. Before any promotion or target write exists, T-06 can be
rolled back by removing only:

```text
WayTask/Persistence/WayTaskProductStateMigration.swift
WayTaskTests/Persistence/WayTaskProductStateMigrationFoundationTests.swift
docs/ImplementationEvidence/1.0.3/WT-033A_T06_ProtectedCandidateStoreMigrationFoundation.md
```

and deleting only the 26-line
`WayTaskProtectedCandidatePhysicalMigrationPlan` addition from
`WayTask/Persistence/WayTaskSchema.swift`. No data rollback, source-store
repair, project edit, package change, startup change, or consumer rollback is
required because T-06 has no production caller and cannot promote a candidate.

## Terminal Decision

T-06 COMPLETE — READY FOR REVIEW
