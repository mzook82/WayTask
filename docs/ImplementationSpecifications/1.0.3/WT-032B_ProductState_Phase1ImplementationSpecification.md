# WT-032B — Product State Phase 1 Implementation Specification

**Product:** WayTask iOS  
**Version:** 1.0.3  
**Document type:** Implementation specification only  
**Phase:** WT-031A Phase 1 — Characterization and safety baseline  
**Status:** Final  
**Implementation authorization:** Not granted by this document

---

## 1. Executive Summary

WT-031A Phase 1 establishes the behavior-preserving safety baseline required before Product State authority, persistence, migration, or user experience can change.

The current application distributes Product State across `Product.deletedAt`, `ShoppingListEntry.isChecked`, `ShoppingItem.isCompleted`, `ShoppingListEntry.legacyShoppingItemID`, in-memory shopping-list revision state, Shopping Plan projections, Shopping Session identifier arrays, and Product History aggregates. WT-030A approved an orthogonal lifecycle architecture, and WT-032A resolved the implementation-blocking semantics. Phase 1 does not implement that architecture. It makes the current implementation observable and reproducible so later phases can distinguish intentional target changes from accidental regressions.

Phase 1 shall add only:

- deterministic, synthetic Product State fixture infrastructure in the test target;
- explicit characterization of current domain, persistence, migration, consumer, session, and deletion behavior;
- test-only diagnostic and privacy assertions;
- repeatable projection and repair performance measurements;
- a repository inventory and baseline evidence record.

Phase 1 shall not modify production source, existing schemas, migration logic, application behavior, project settings, localization, UI, or existing test expectations. Known current defects shall be captured as current-behavior facts and marked for replacement in later phases; they shall not be reclassified as approved behavior.

The implementation sequence is intentionally additive. Each step produces an independently removable test or documentation artifact, validates its prerequisites, and stops on any unexpected production or repository change.

---

## 2. Scope

### 2.1 In scope

Phase 1 specifies:

1. A frozen inventory of current Product State readers, writers, persistence fields, migrations, repairs, consumers, and tests.
2. Synthetic fixture cases covering current V1, V2, and V3 persistence shapes and the current runtime model.
3. Characterization of:
   - Product identity and library tombstoning;
   - Shopping-list entry creation, checking, removal, duplication, and legacy mirroring;
   - multi-list interaction through shared compatibility state;
   - Product History aggregation and retention;
   - catalog and scanner-adjacent Product restoration behavior;
   - Shopping Plan filtering and snapshot limitations;
   - Shopping Session start, collection, finish, and coexistence behavior;
   - Map, location, geofence, and notification Product context;
   - startup repair, store recovery, and current migrations.
4. Privacy-safe test diagnostics that expose case identifiers, counts, digests, durations, and failure categories without exposing Product names, barcodes, notes, precise coordinates, contributor data, or image content.
5. Baseline measurements for current Product projections, startup repair, active-session lookup, and library filtering.
6. A Phase 1 evidence record containing the verified inventory, environment, commands, results, semantic fixture digests, and performance observations.
7. Exact execution, validation, and rollback procedures.

### 2.2 Out of scope

Phase 1 shall not:

- add the approved orthogonal domain model;
- create or change a SwiftData schema or migration stage;
- alter `ShoppingItem.isCompleted`, `ShoppingListEntry.isChecked`, or `legacyShoppingItemID`;
- add durable Shopping-list revisions;
- change Finish, restore, deletion, history, duplicate, multi-list, session, Map, notification, scanner, or catalog behavior;
- introduce domain commands, authority adapters, or compatibility cutover logic;
- change UI indicators, labels, navigation, accessibility behavior, or localization;
- add production diagnostics, Sentry events, logging, feature flags, or telemetry;
- modify the Xcode project, scheme, test plan, build settings, dependencies, or target membership;
- use real user data, a production store, production analytics, or network services;
- authorize Phase 2 or production implementation.

The target Product State behavior remains governed by WT-030A and WT-032A. Phase 1 assertions describe the current baseline only.

---

## 3. Phase 1 Objectives

### 3.1 Primary objectives

Phase 1 shall:

1. Enumerate every verified Product State authority path before any authority changes.
2. Make current data preservation and known contradictions executable.
3. Provide file-backed migration inputs for all shipped schema versions.
4. Prove that characterization infrastructure cannot modify source fixtures or user data.
5. Establish privacy-safe diagnostic conventions for later Product State work.
6. Record reproducible baseline counts, semantic digests, and p50/p95 measurements.
7. Leave the application binary and runtime behavior unchanged.

### 3.2 Success condition

Phase 1 succeeds when a clean checkout can reproduce the same current-behavior results from synthetic inputs, all current readers and writers are accounted for, the full pre-existing test suite still passes, and repository validation proves that only the approved Phase 1 test and evidence artifacts changed.

### 3.3 Non-goal

Passing Phase 1 does not mean current behavior is correct. It means the current behavior is sufficiently characterized to support a controlled transition in later approved specifications.

---

## 4. Current Repository Baseline

### 4.1 Verified project and test structure

| Area | Current verified baseline |
|---|---|
| Application project | `WayTask.xcodeproj` |
| Shared scheme | `WayTask` |
| Unit-test target | `WayTaskTests` |
| Test source membership | `WayTaskTests` is a file-system-synchronized group; files and resources placed below it are discovered without editing `project.pbxproj` |
| Existing test inventory | 33 Swift test files, 291 `test…` methods, one JSON test resource |
| Existing file-backed persistence coverage | Seven file-backed model-container configurations in persistence tests |
| Existing explicit performance calls | Two, both in Product Knowledge search tests |
| Existing XCTest attachments | None |
| Current shipped schema | `WayTaskSchemaV3`; V1 and V2 remain present for migration |
| Monitoring integration | Sentry package is configured; current stability tests validate privacy defaults and metadata allowlisting |

Counts above are the verified starting baseline for this specification. Phase 1 execution shall recalculate and record them rather than assuming they remain unchanged.

### 4.2 Verified persistence and domain authority

| Concern | Current verified owner or representation | Baseline implication |
|---|---|---|
| Product identity | `Product.id` | UUID stability must be characterized and preserved |
| Library membership | `Product.deletedAt` | Tombstoning is the current library-removal authority |
| Named-list membership | `ShoppingListEntry` | Entry state coexists with compatibility state |
| Entry resolution | `ShoppingListEntry.isChecked` | Current local list resolution flag |
| Compatibility completion | `ShoppingItem.isCompleted` | Global flag is read and written by multiple unrelated surfaces |
| Entry-to-compatibility link | `ShoppingListEntry.legacyShoppingItemID` | Current compatibility bridge |
| Shopping-list revision | Runtime `shoppingListRevision` in application state | Not durable in the current persistence model |
| Shopping Plan | Projection containing Product/item snapshots but no authoritative durable source-list revision contract | Current filtering and staleness behavior must be recorded |
| Shopping Session line state | UUID collections for item and collected identifiers | Collection is session-local, but Finish does not reconcile all target lifecycles |
| Product History | Aggregation by barcode or normalized name plus completion-compatible inputs | It is not yet UUID-first immutable history |
| Catalog identity | Catalog linkage and Product display snapshots | Existing validated catalog ownership is retained |
| Location context | Saved-location/Product relationships and compatibility filters | Location does not own Product State, but currently consumes global completion |

### 4.3 Verified reader and writer concentration

The Phase 1 inventory shall treat the following verified paths as the minimum set. The execution inventory may add paths but may not silently omit any of these:

- `ShoppingItem.isCompleted` is referenced in Product, Home, Shopping, decision, discovery, Map, location, store search, context, session, trip, and application-state paths.
- `ShoppingListEntry.isChecked` is referenced by list services, Shopping workspace UI, Home, diagnostics, and schema/model definitions.
- `ShoppingListEntry.legacyShoppingItemID` is referenced by list services, Product and Shopping UI, catalog resolution, model definitions, and all three schema generations.
- `Product.deletedAt` is read or written by Product library, catalog persistence, barcode upsert, startup repair, and persistence tests.
- `ModelContext.save`, `insert`, and `delete` calls occur in services and views; direct UI persistence remains a current authority risk.
- Current direct mutations of completion or checked state exist in `ShoppingListService`, `ShoppingWorkspaceView`, `ContentView`, and `LocationDetailView`.
- Product State consumers include `DecisionEngine`, `DiscoverViewModel`, `MapViewModel`, `StoreSearchService`, `ShoppingContext`, `ShoppingIntentMatcher`, `ShoppingTripService`, `ShoppingSessionService`, `AppStateManager`, and Product/Shopping/Map views.

The evidence record shall contain exact file paths, line references, property access categories, and counts obtained at Phase 1 execution time.

### 4.4 Verified current behaviors to preserve during Phase 1

The following are current-behavior baselines. “Preserve” means Phase 1 must not change them; it does not mean they are approved target semantics.

| Baseline ID | Current verified behavior |
|---|---|
| CB-01 | Adding a Product to Shopping creates or uses current compatibility state and a named-list entry through `ShoppingListService`. |
| CB-02 | Adding an already checked entry can silently reopen that entry. |
| CB-03 | Removing a Product from one current list can complete the shared compatibility item used by another list. |
| CB-04 | Persistence currently permits duplicate logical entries because target uniqueness is not schema-enforced. |
| CB-05 | Product library removal tombstones the Product and removes applicable Weekly memberships while retaining Completed/Recent references and history. |
| CB-06 | Product library removal does not currently enforce the WT-032A active-session deletion block. |
| CB-07 | Barcode upsert and explicit catalog Product persistence can implicitly restore a tombstoned Product. |
| CB-08 | Product History currently aggregates by barcode or normalized name and can infer recency/completion from compatibility fields. |
| CB-09 | Starting a Shopping Session while one is active can return the existing active session without validating a new source context. |
| CB-10 | Collecting a line changes session-local identifier arrays and does not itself change list resolution or Product History. |
| CB-11 | Finishing a session changes session header/lifecycle state but does not perform the approved atomic Finish reconciliation. |
| CB-12 | Shopping Plan, Shopping Trip, Map, location, and related consumers can filter or interpret Products through `ShoppingItem.isCompleted`. |
| CB-13 | Startup repair creates or repairs default list and compatibility relationships and is expected to be idempotent for supported current states. |
| CB-14 | Missing Product references are not indiscriminately recreated; existing Product relationships can be repaired. |
| CB-15 | Geofence/notification context currently carries store and item/list snapshot data in notification identifiers and payload metadata. |
| CB-16 | V1 and V2 stores migrate to the current V3 model, whose Product addition is `deletedAt`, while existing Product UUIDs and supported data remain stable. |

### 4.5 Existing defects to preserve temporarily

These are known current inconsistencies, not approved behavior:

| Defect ID | Current inconsistency | Approved later direction | Phase 1 treatment |
|---|---|---|---|
| KD-01 | Global `ShoppingItem.isCompleted` conflates list and cross-surface state. | D-01, D-02, D-33 | Assert current output and label the test `CurrentLegacy`; replace after authority cutover. |
| KD-02 | A change in one named list can affect another through a shared compatibility item. | D-08, D-10 | Characterize with a two-list fixture. |
| KD-03 | Duplicate logical list entries are possible. | D-09, D-26, D-37 | Preserve and measure current behavior; do not add uniqueness enforcement. |
| KD-04 | List revision is not durable. | D-11 | Record source inventory; do not add a revision field. |
| KD-05 | Shopping Plan lacks the approved immutable list/revision/entry source contract. | D-12 | Characterize current snapshot contents only. |
| KD-06 | Active-session context can be reused without the approved conflict decision. | D-14, D-29 | Characterize current service response. |
| KD-07 | Product removal is not blocked by an active session. | D-16 | Characterize without changing deletion. |
| KD-08 | Catalog and scanner/barcode paths can implicitly restore a Product. | D-17, D-22 | Characterize both restore paths. |
| KD-09 | Finish is not the approved atomic reconciliation. | D-03, D-04, D-35, D-36 | Characterize session header and unchanged list/history state. |
| KD-10 | Product History is not UUID-first immutable event ownership. | D-06, D-07, D-31 | Characterize key selection and retention. |
| KD-11 | Completed/Recent can act as persisted membership and inferred state. | D-19, D-30 | Characterize current repair and retention behavior. |
| KD-12 | Consumer filtering and UI indicators derive from mixed fields. | D-20, D-21 | Characterize consumer inputs and current presentation semantics where testable. |

Tests covering these defects shall use names and failure messages that say “current legacy behavior.” Later implementation specifications must explicitly replace or retire the affected assertions when the corresponding authority changes. Phase 1 characterization must never be cited as approval to retain the defect.

---

## 5. Characterization Strategy

### 5.1 Test taxonomy

Phase 1 shall use five complementary suites:

1. **Domain characterization:** current commands, direct writes, list interaction, deletion, restore, history, and session behavior.
2. **Persistence characterization:** V1/V2/V3 data shapes, store reopening, repair idempotency, tombstones, duplicates, orphans, and migration working-copy safety.
3. **Consumer characterization:** current Plan, Trip, Map, location, geofence/notification, and catalog/custom Product consumption.
4. **Diagnostic characterization:** current startup diagnostic sequences, privacy allowlists, redaction, and safety of new test artifacts.
5. **Performance baseline:** repeatable measurements of representative current projections and repair paths.

### 5.2 Synthetic fixture manifest

One versioned JSON manifest shall define logical test cases. It shall contain only stable synthetic UUIDs, synthetic timestamps, enumerated field values, case identifiers, current expected results, and known-defect identifiers.

Required case coverage:

| Fixture case | Required state |
|---|---|
| `flags-00` | `isChecked == false`, `isCompleted == false` |
| `flags-01` | `isChecked == false`, `isCompleted == true` |
| `flags-10` | `isChecked == true`, `isCompleted == false` |
| `flags-11` | `isChecked == true`, `isCompleted == true` |
| `multi-list-shared-compatibility` | Two lists point to entries related through one compatibility item |
| `duplicate-entry` | Two logical entries have the same Product/list identity under current persistence |
| `tombstone-weekly-completed-recent` | Tombstoned Product referenced by current system lists and history |
| `tombstone-active-session` | Tombstoned or removal-target Product referenced by an active session |
| `orphan-existing-product-id` | Broken relationship with an existing Product UUID available for repair |
| `orphan-missing-product` | Reference to a Product UUID that does not exist |
| `completed-recent-only` | Product retained only through current Completed/Recent projections |
| `active-session-collected` | Active session with collected and remaining identifier sets |
| `finished-session-no-reconcile` | Finished header with current unchanged list/history compatibility state |
| `session-missing-item` | Session snapshot refers to an unavailable current item |
| `location-compatibility` | Saved location relationships include complete/incomplete compatibility items |
| `catalog-active` | Active catalog-backed Product with catalog snapshots |
| `catalog-tombstone` | Tombstoned catalog-backed Product |
| `custom-product` | Product without catalog identity |
| `history-compatibility-key` | History grouping exercises barcode and normalized-name behavior |

The manifest shall declare `expectationKind: "currentBehavior"` and may reference `knownDefectID`. It shall not contain target expected values, proposed schemas, production user data, real barcodes, real store coordinates, or private notes.

### 5.3 Canonical semantic snapshot

Binary SwiftData stores are not stable golden files. The test support layer shall therefore derive a canonical semantic snapshot after each operation or migration:

- records sorted by entity kind and stable UUID;
- relationship identifiers sorted deterministically;
- dates encoded in ISO 8601 UTC with fixed precision;
- enum and Boolean values encoded explicitly;
- optional values distinguished from empty values;
- byte/image content represented only by length and a synthetic-data digest;
- no filesystem path, random identifier, locale-dependent string, or store-internal identifier included.

The snapshot shall be serialized with sorted JSON keys and hashed with SHA-256. Both the semantic JSON and digest may be attached to local test results only when they contain synthetic data. The Phase 1 evidence record shall store case IDs, record counts, and digests; it shall not copy full fixture payloads unnecessarily.

### 5.4 Required domain characterization tests

The domain suite shall include at least:

- current add creates one entry and one compatibility representation;
- add to a checked entry silently reopens the current entry;
- remove from one list affects only the entry operation requested but currently completes shared compatibility state;
- direct persistence currently permits duplicate logical entries;
- library removal deletes current Weekly membership while retaining Completed/Recent/history references;
- removal with an active session is not currently blocked;
- barcode upsert currently restores a tombstone;
- catalog Product persistence currently restores a tombstone;
- history uses current barcode/name aggregation;
- session start currently returns an existing active session;
- session collection remains isolated from list and history state;
- current Finish changes session lifecycle state without target reconciliation.

Each test shall:

1. cite one or more CB/KD identifiers;
2. build state through current production APIs where such APIs exist;
3. use direct model construction only to reach otherwise valid persisted legacy states;
4. assert both the changed field and adjacent unchanged fields;
5. avoid asserting target behavior;
6. clean up its isolated container and temporary files.

### 5.5 Required persistence and migration characterization

The persistence suite shall:

- generate isolated file-backed V1, V2, and V3 stores using the repository’s frozen shipped schema types;
- copy each source store into a unique working directory before opening or migrating it;
- characterize all four `isChecked`/`isCompleted` combinations;
- verify Product UUID and catalog snapshot stability across current supported migrations;
- verify duplicate logical entries survive current persistence/reopen behavior;
- verify current repair of relationships when the Product UUID exists;
- verify current non-recreation behavior when the Product UUID is missing;
- verify Completed/Recent-only and history references survive current repair where existing tests establish that behavior;
- verify current tombstone repair does not unexpectedly resurrect explicitly removed Products;
- verify active and finished Shopping Session identifier arrays survive reopen;
- verify saved-location relationships survive reopen;
- run current repair twice and prove equal canonical semantic digests;
- prove that a failed or interrupted test opening attempt cannot mutate the read-only source fixture.

The suite shall not add a migration stage, infer target V4 data, or encode unresolved target-schema design.

### 5.6 Required consumer characterization

The consumer suite shall characterize, without UI redesign:

- Shopping Plan input filtering based on current compatibility completion;
- Shopping Trip and Shopping Context filtering;
- current Map/store recommendation Product inclusion inputs;
- saved-location compatibility filtering;
- geofence and notification Product/list snapshot round-trip;
- catalog-backed, tombstoned catalog-backed, and custom Product identity presentation inputs;
- stale or missing Product references where current consumers already tolerate them.

If a consumer cannot be tested without creating a production hook or changing behavior, it shall be recorded in the evidence inventory as source-characterized and deferred to the first phase that legitimately changes that boundary.

### 5.7 Current UI characterization boundary

Phase 1 shall not add UI behavior or snapshot-test dependencies. It shall:

- inventory Product Library, Shopping, Map, notification, scanner, and history presentation readers;
- test pure presentation values or existing view-model outputs where already injectable;
- record indicator meanings and direct persistence actions in the evidence document;
- rely on the full existing test suite for current UI regression.

New UI test targets, accessibility identifiers, dependency injection, or view restructuring are out of scope because each would change production or project structure.

---

## 6. Test Infrastructure Specification

### 6.1 Proposed support file

**Proposed:** `WayTaskTests/ProductState/Support/ProductStateCharacterizationSupport.swift`

This test-target-only support file shall provide:

- stable synthetic UUID, date, locale, and calendar factories;
- manifest loading through `Bundle(for:)`;
- in-memory current-schema container construction;
- isolated file-backed V1, V2, V3, and current-container construction;
- source-fixture creation followed by mandatory working-copy isolation;
- canonical semantic snapshot and digest generation;
- deterministic entity counts and relationship summaries;
- temporary-directory ownership and cleanup, including store sidecar files;
- privacy-safe XCTest attachment helpers;
- monotonic timing sample collection and percentile calculation;
- fixture-profile builders for functional and reference-scale runs.

It shall not:

- compile into the application target;
- use swizzling;
- add production protocols or hooks;
- connect to a network;
- initialize Sentry transmission;
- read the user’s Application Support directory;
- mutate process-global locale or time zone;
- use random input without a stored seed;
- persist secrets or user data.

### 6.2 Fixture resource

**Proposed:** `WayTaskTests/ProductState/Fixtures/product-state-current-behavior-v1.json`

The resource shall:

- use schema version `1` for the test manifest format;
- contain the cases in Section 5.2;
- use reserved synthetic namespaces for names and identifiers;
- contain no live Catalog Product, store, or location identifiers;
- include a human-readable purpose and CB/KD references for every case;
- include expected current semantic counts and field values;
- fail decoding on unknown required fields;
- be validated by a dedicated manifest self-test.

Because `WayTaskTests` is a file-system-synchronized project group, the resource shall be added below that directory without modifying `project.pbxproj`. Phase 1 must stop if the resource is not copied into the test bundle automatically; modifying project settings is not an allowed workaround.

### 6.3 Container isolation

Every test container shall:

1. allocate a unique directory under the test process’s temporary directory;
2. create or copy only synthetic stores into that directory;
3. close all container/model-context references before cleanup;
4. remove only its owned directory;
5. never use `$HOME`, the application’s default store URL, a shared fixture URL, or an unresolved glob;
6. fail with a privacy-safe case ID if cleanup cannot be proven.

File-backed migration tests shall calculate a source semantic digest before copying, run only against the working copy, then verify the source digest and file metadata remain unchanged.

### 6.4 Determinism

The support layer shall fix:

- UUIDs from the manifest or a deterministic counter;
- dates relative to a fixed UTC epoch;
- calendar to Gregorian and time zone to GMT for fixture calculations;
- ordering before every comparison;
- performance fixture seeds;
- test case names and record counts.

No assertion shall depend on localized display ordering, current time, device region, network availability, or SwiftData internal row order.

### 6.5 Fixture profiles

Two explicit profiles shall be used:

| Profile | Purpose | Shape |
|---|---|---|
| Functional | Fast correctness and migration execution | 25 Products, 3 named lists, 20 entries, 25 compatibility items, 10 history records, one session |
| Reference | Repeatable observation, not a supported maximum | 2,000 Products, 20 named lists, 10,000 entries, 2,000 compatibility items, 5,000 history records, one 500-line session, 20 saved locations with 50 relationships |

The reference profile is a baseline workload, not a product limit or performance acceptance threshold. Any later capacity claim requires a separately approved requirement.

### 6.6 Test execution grouping

Proposed XCTest classes:

- `ProductStateDomainCharacterizationTests`
- `ProductStatePersistenceCharacterizationTests`
- `ProductStateConsumerCharacterizationTests`
- `ProductStateDiagnosticsCharacterizationTests`
- `ProductStatePerformanceBaselineTests`

The first four shall run in the standard full suite. Performance tests may be separately invoked for controlled Release-configuration measurement, but their fixture-building and correctness assertions shall remain runnable in the standard suite at functional scale.

The proposed test selector inventory is fixed as follows. A selector may be split only when required to isolate a different shipped schema generation; any split selector shall retain the same requirement and traceability identifiers.

| Test class | Required proposed selectors |
|---|---|
| `ProductStateDomainCharacterizationTests` | `testCurrentLegacyAddCreatesEntryAndCompatibilityItem`; `testCurrentLegacyAddToCheckedEntryReopensEntry`; `testCurrentLegacyRemoveFromOneListCompletesSharedCompatibilityItem`; `testCurrentLegacyPersistenceAllowsDuplicateLogicalEntries`; `testCurrentLegacyLibraryRemovalRemovesWeeklyButRetainsCompletedRecentAndHistory`; `testCurrentLegacyLibraryRemovalDoesNotBlockActiveSession`; `testCurrentLegacyBarcodeUpsertRestoresTombstone`; `testCurrentLegacyCatalogPersistenceRestoresTombstone`; `testCurrentLegacyHistoryAggregatesByBarcodeThenNormalizedName`; `testCurrentLegacySessionStartReturnsExistingActiveSession`; `testCurrentSessionCollectionDoesNotMutateListOrHistory`; `testCurrentLegacySessionFinishChangesHeaderWithoutReconciliation` |
| `ProductStatePersistenceCharacterizationTests` | `testManifestLoadsAllRequiredCases`; `testCurrentSchemaPersistsAllCheckedCompletedCombinations`; `testV1WorkingCopyMigratesToCurrentSemanticSnapshot`; `testV2WorkingCopyMigratesToCurrentSemanticSnapshot`; `testV3WorkingCopyReopensWithCurrentSemanticSnapshot`; `testCurrentLegacyDuplicateEntriesSurviveReopen`; `testStartupRepairReconnectsExistingProductReference`; `testStartupRepairDoesNotRecreateMissingProduct`; `testStartupRepairPreservesCompletedRecentAndHistoryReferences`; `testStartupRepairPreservesTombstoneWithoutResurrection`; `testCurrentSessionArraysSurviveReopen`; `testSavedLocationRelationshipsSurviveReopen`; `testStartupRepairSecondPassHasIdenticalSemanticDigest`; `testMigrationWorkingCopyDoesNotMutateSourceFixture`; `testFailedWorkingCopyOpenDoesNotMutateSourceFixture` |
| `ProductStateConsumerCharacterizationTests` | `testCurrentPlanInputExcludesCompletedCompatibilityItems`; `testCurrentTripAndContextUseCompatibilityCompletion`; `testCurrentMapAndStoreInputsUseCompatibilityCompletion`; `testCurrentSavedLocationFilteringUsesCompatibilityCompletion`; `testCurrentGeofenceNotificationPayloadRoundTripsLegacySnapshot`; `testCatalogCustomAndStaleIdentitiesRemainDistinguishable` |
| `ProductStateDiagnosticsCharacterizationTests` | `testCurrentStartupDiagnosticSuccessSequence`; `testCurrentStartupDiagnosticRecoverySequence`; `testCurrentStartupDiagnosticMetadataUsesAllowlist`; `testProductStateAttachmentsExcludePrivateSentinels`; `testCharacterizationDoesNotInitializeDiagnosticTransport` |
| `ProductStatePerformanceBaselineTests` | `testFunctionalProfileProjectionCorrectness`; `testReferenceSelectedListProjectionBaseline`; `testReferenceLibraryFilteringBaseline`; `testReferencePlanInputProjectionBaseline`; `testReferenceActiveSessionLookupBaseline`; `testReferenceStartupRepairBaseline`; `testReferenceProfileSemanticDigestIsStable` |

Test-type classification:

- domain selectors are unit/characterization tests with isolated in-memory persistence;
- persistence selectors are integration, migration-fixture, recovery, and regression-fixture tests;
- consumer selectors are integration/characterization tests across existing service boundaries;
- diagnostic selectors are diagnostic unit/integration and redaction tests;
- performance selectors are correctness-backed observational performance tests.

No proposed selector is a target-architecture acceptance test. Later behavior-changing specifications shall name the legacy selector they replace, update, or retire.

---

## 7. Diagnostics Specification

### 7.1 Production boundary

Phase 1 shall add no production diagnostic event, log field, Sentry breadcrumb, metric, tracing span, reporter, feature flag, or telemetry call. Existing production diagnostic behavior remains unchanged.

Current startup persistence diagnostics shall be characterized through their existing injected reporting closure or current test boundary. Tests shall not transmit data.

### 7.2 Test diagnostic envelope

Test-only results and attachments may contain:

- fixture case ID;
- CB/KD/decision identifiers;
- schema generation;
- entity and relationship counts;
- semantic digest;
- elapsed duration and percentile;
- operation stage;
- result category;
- synthetic error domain and code.

They shall not contain:

- Product names or user notes;
- barcodes;
- Shopping-list titles;
- Store names;
- precise latitude or longitude;
- file paths outside the owned temporary directory;
- raw image data;
- authentication data;
- Sentry credentials;
- full persisted records;
- device or account identifiers.

### 7.3 Existing production diagnostic characterization

The diagnostics suite shall verify the current startup diagnostic contract:

- expected stage and outcome ordering for success and recovery paths;
- allowlisted metadata only;
- redaction of injected private sentinel strings;
- no Product, barcode, location, or note fields in ordinary startup metadata;
- current recovery action and quarantined-component counts;
- no network send from characterization tests.

### 7.4 Attachment policy

XCTest attachments shall:

- use JSON with sorted keys;
- use `.keepAlways` only for failed correctness cases or controlled performance evidence;
- use `.deleteOnSuccess` for verbose diagnostic snapshots;
- identify synthetic data explicitly;
- be scanned by a diagnostics test using sentinel private strings that must not appear.

The evidence document may include safe aggregate results from attachments. It shall not embed raw `xcresult` contents.

### 7.5 Baseline metrics

For the Reference profile, Phase 1 shall record:

- selected-list entry projection duration;
- Product Library active/tombstone filtering duration;
- current Shopping Plan input projection duration;
- active Shopping Session lookup duration;
- current startup repair duration;
- fixture store size before and after current repair;
- peak test-process memory if available through supported XCTest metrics;
- semantic record counts before and after each operation.

Measurement protocol:

1. Record commit, Xcode, Swift, macOS, simulator runtime, simulator device, architecture, configuration, and thermal state.
2. Use Release configuration for the controlled performance run.
3. Build the fixture once per measured operation unless fixture construction is the operation under measurement.
4. Run three warm-up samples.
5. Run thirty measured samples.
6. Use a monotonic clock.
7. Record p50, p95, minimum, maximum, and sample count.
8. Do not establish pass/fail timing thresholds in Phase 1.

Correctness failures, memory exhaustion, store corruption, or non-deterministic digests are failures. Timing variation alone is observational until a later approved specification defines regression thresholds.

---

## 8. Repository Changes

### 8.1 Allowed Phase 1 implementation footprint

Only the following new files are permitted by this specification:

1. `WayTaskTests/ProductState/Support/ProductStateCharacterizationSupport.swift`
2. `WayTaskTests/ProductState/Fixtures/product-state-current-behavior-v1.json`
3. `WayTaskTests/ProductState/ProductStateDomainCharacterizationTests.swift`
4. `WayTaskTests/ProductState/ProductStatePersistenceCharacterizationTests.swift`
5. `WayTaskTests/ProductState/ProductStateConsumerCharacterizationTests.swift`
6. `WayTaskTests/ProductState/ProductStateDiagnosticsCharacterizationTests.swift`
7. `WayTaskTests/ProductState/ProductStatePerformanceBaselineTests.swift`
8. `docs/ImplementationEvidence/1.0.3/WT-031A_Phase1_ProductStateBaseline.md`

All eight paths are proposed. No existing repository file is to be modified during Phase 1.

### 8.2 Explicitly prohibited repository changes

Phase 1 shall not change:

- any file below the production application source roots;
- `WayTask.xcodeproj/project.pbxproj`;
- shared schemes, test plans, entitlements, Info.plist files, or package dependencies;
- `Models.swift`, `WayTaskSchema.swift`, `WayTaskSchemaV1.swift`, or any other schema/migration file;
- existing test files or fixtures;
- Catalog artifacts;
- localization resources;
- previous WT documents;
- generated source or checked-in build artifacts.

### 8.3 Evidence document contract

The proposed baseline evidence document shall record:

- repository commit and clean/dirty state;
- pre-existing unrelated changes, without modifying or claiming ownership of them;
- execution environment;
- exact inventory commands and classified results;
- protected-file hashes;
- fixture manifest digest;
- semantic fixture digests;
- focused and full test commands and outcomes;
- migration and diagnostic validation outcomes;
- performance profile and p50/p95 results;
- known failures or environment limitations;
- final changed-file audit.

It shall be evidence, not a new architecture or decision document.

---

## 9. File-by-File Specification

### 9.1 Test support and fixture

#### Proposed — `WayTaskTests/ProductState/Support/ProductStateCharacterizationSupport.swift`

- **Current responsibility:** File does not exist. Related helpers are currently local to individual persistence tests.
- **Exact Phase 1 change:** Add test-only deterministic fixture, container, snapshot, digest, cleanup, diagnostic attachment, and percentile helpers described in Section 6.
- **Implementation order:** Step E-03.
- **Dependencies:** E-01 inventory; E-02 decoded manifest contract; existing V1/V2/V3 schema types; XCTest; CryptoKit/Foundation as already available platform frameworks.
- **Validation:** Manifest self-test; one in-memory container smoke test; one file-backed store-copy test; source fixture digest unchanged; cleanup directory absent after test.
- **Tests:** Support self-tests are placed in the domain or persistence characterization suites; no production test hook.

#### Proposed — `WayTaskTests/ProductState/Fixtures/product-state-current-behavior-v1.json`

- **Current responsibility:** File does not exist.
- **Exact Phase 1 change:** Add the synthetic current-behavior cases in Section 5.2.
- **Implementation order:** Step E-02.
- **Dependencies:** Verified test group resource synchronization; CB/KD inventory.
- **Validation:** JSON parsing; manifest schema version; uniqueness of case and UUID identifiers; no forbidden keys or private sentinel data; resource is found in the test bundle without project changes.
- **Tests:** Manifest decode and privacy validation.

### 9.2 Domain characterization

#### Proposed — `WayTaskTests/ProductState/ProductStateDomainCharacterizationTests.swift`

- **Current responsibility:** File does not exist; current behavior is spread across catalog, deletion, Shopping service, and UX tests.
- **Exact Phase 1 change:** Add the domain tests in Section 5.4, explicitly labeled as current behavior.
- **Implementation order:** Step E-04.
- **Dependencies:** E-02 and E-03; current service APIs and model initializers.
- **Validation:** Focused suite passes twice from clean synthetic state; all adjacent-state assertions pass; no network or default application store access.
- **Tests:** Add/reopen/remove, duplicate, tombstone, implicit restore, history key, active-session reuse, collection isolation, current Finish.

### 9.3 Persistence and migration

#### Proposed — `WayTaskTests/ProductState/ProductStatePersistenceCharacterizationTests.swift`

- **Current responsibility:** File does not exist; current migration and repair coverage resides mainly in `WayTaskSchemaMigrationTests`, `StartupRepairIdempotencyTests`, `ProductLibraryDeletionPersistenceTests`, and startup resilience tests.
- **Exact Phase 1 change:** Add cross-lifecycle file-backed V1/V2/V3 characterization and canonical semantic digests without changing existing tests.
- **Implementation order:** Step E-05.
- **Dependencies:** E-02 through E-04; shipped schemas and current migration plan; isolated working-copy helper.
- **Validation:** Every schema fixture opens or migrates as currently supported; source stores remain unchanged; repeated repair digests match; focused suite passes serially and under normal test parallelization.
- **Tests:** Flag matrix, UUID/snapshot stability, duplicates, orphans, Completed/Recent-only references, tombstones, sessions, locations, repair idempotency, source-fixture immutability.

### 9.4 Product State consumers

#### Proposed — `WayTaskTests/ProductState/ProductStateConsumerCharacterizationTests.swift`

- **Current responsibility:** File does not exist; relevant behavior is distributed among Product Catalog, Product Knowledge, Map, Shopping Classification, and Shopping UX tests.
- **Exact Phase 1 change:** Add tests for current Plan, Trip, Context, Map/store input, saved-location, geofence/notification, and catalog/custom identity consumption where existing seams permit.
- **Implementation order:** Step E-06.
- **Dependencies:** E-02 through E-05; verified current consumer APIs.
- **Validation:** Focused suite passes with all four compatibility-flag combinations and stale-reference cases; payload round-trip is deterministic.
- **Tests:** Current completion filtering, plan input, trip/context inclusion, location relationships, geofence payload, catalog/custom/stale identity.

### 9.5 Diagnostic characterization

#### Proposed — `WayTaskTests/ProductState/ProductStateDiagnosticsCharacterizationTests.swift`

- **Current responsibility:** File does not exist; startup and Sentry privacy behavior is covered by existing persistence and monitoring tests.
- **Exact Phase 1 change:** Add Product State-specific assertions for current startup diagnostic sequences and privacy of new test diagnostics.
- **Implementation order:** Step E-07.
- **Dependencies:** E-03 support; existing startup diagnostic injection and Sentry stability boundaries.
- **Validation:** Private sentinel scan passes; no network request is emitted; attachment keys match the allowlist; existing `SentryStabilityTests` continue to pass.
- **Tests:** Diagnostic stage/outcome, recovery counts, redaction, safe failure envelope, attachment policy.

### 9.6 Performance characterization

#### Proposed — `WayTaskTests/ProductState/ProductStatePerformanceBaselineTests.swift`

- **Current responsibility:** File does not exist; Product State has no dedicated p50/p95 baseline suite.
- **Exact Phase 1 change:** Add functional correctness checks and controlled Reference-profile measurements from Section 7.5.
- **Implementation order:** Step E-08.
- **Dependencies:** E-03 support; E-04 through E-07 correctness suites passing; controlled test environment.
- **Validation:** Fixture digest is stable across two builds; sample counts equal 30; all timing values are finite and non-negative; correctness results match non-performance suites.
- **Tests:** List projection, library filtering, plan input, active-session lookup, startup repair, optional supported memory metric.

### 9.7 Evidence

#### Proposed — `docs/ImplementationEvidence/1.0.3/WT-031A_Phase1_ProductStateBaseline.md`

- **Current responsibility:** File does not exist.
- **Exact Phase 1 change:** Record the baseline evidence contract in Section 8.3.
- **Implementation order:** Create in E-01; complete and verify in E-09 and E-10.
- **Dependencies:** Repository inspection and all later validation results.
- **Validation:** Every result links to an exact command, suite, environment, or digest; no private data; changed-file list matches Section 8.1.
- **Tests:** Manual evidence review plus repository/path/hash validation.

### 9.8 Existing files retained without change

The following verified ownership and test boundaries are retained:

- shipped schema and migration files;
- `ShoppingListService`, Product library deletion service, catalog persistence service, session/trip services, Map/location services, startup repair and recovery;
- existing Product, Shopping, Map, notification, scanner, and history views/view models;
- existing migration, repair, deletion, catalog, Shopping UX, Product Knowledge, Map, monitoring, and resilience tests;
- the Xcode project and shared scheme.

Phase 1 adds observation around these boundaries; it does not refactor them.

---

## 10. Validation Strategy

### 10.1 Preflight validation

Before adding any Phase 1 artifact:

1. Record the repository commit and `git status --short`.
2. Record all pre-existing changed and untracked paths.
3. Confirm all governing WT documents and the Product Specification are readable.
4. Confirm the target test group is file-system synchronized.
5. Confirm a supported Xcode toolchain and an available iOS Simulator destination.
6. Resolve Swift package dependencies using the repository’s existing configuration.
7. Run the current build and full test suite without Phase 1 artifacts.
8. Stop if the baseline fails for a Product State reason not already documented.

An infrastructure failure may be documented and retried in a valid environment. It may not be bypassed by changing project settings.

### 10.2 Build validation

At E-00, E-03, and E-10, run a generic non-signing application build using a unique derived-data directory:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Debug \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/WayTask-WT031A-P1-Build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The command is illustrative of required parameters; the evidence record shall capture the exact executed command and toolchain path.

### 10.3 Unit and characterization validation

Use one recorded available Simulator UDID; do not assume a device name:

```text
xcodebuild test \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<recorded-UDID>' \
  -derivedDataPath /private/tmp/WayTask-WT031A-P1-Tests \
  -resultBundlePath /private/tmp/WayTask-WT031A-P1-Tests.xcresult
```

Run focused suites after each addition with `-only-testing`, then run:

- all five new Product State suites;
- existing `WayTaskSchemaMigrationTests`;
- existing `StartupRepairIdempotencyTests`;
- existing `ProductLibraryDeletionPersistenceTests`;
- existing `CatalogProductPersistenceServiceTests`;
- existing `CatalogProductCompatibilityTests`;
- existing `LegacyProductCreationCharacterizationTests`;
- existing `StartupPersistenceResilienceTests`;
- existing `SentryStabilityTests`;
- existing Product Catalog, Product Knowledge, Shopping UX/Classification, Map, and location-related suites;
- the complete `WayTaskTests` target.

### 10.4 Migration validation

Migration validation shall prove:

- V1→current and V2→current behavior using synthetic working copies;
- V3/current reopen behavior;
- Product UUID and supported snapshot stability;
- all four compatibility flag combinations are observed;
- source fixture immutability;
- repair idempotency;
- failed working-copy handling cannot alter the source fixture;
- no new schema or migration identifier appears in the repository diff.

### 10.5 Diagnostics validation

Diagnostics validation shall:

- run the new diagnostic suite;
- run existing monitoring and startup resilience suites;
- scan safe attachments using injected sentinel values;
- prove no Sentry/network transmission;
- confirm the evidence document contains only aggregate/synthetic data;
- confirm no production diagnostic source changed.

### 10.6 Performance validation

Run the Reference profile in a controlled Release-configuration test invocation. Record environment and thirty samples after three warm-ups. Execute the complete measurement twice. The second run’s semantic digests and record counts must equal the first run.

Phase 1 does not fail on a newly observed slow p95 unless execution is non-terminating, resource-exhausting, corrupting, or non-deterministic. Slow results shall be recorded as later optimization evidence, not “fixed” in Phase 1.

### 10.7 Repository validation

Final validation shall prove:

- only the eight paths in Section 8.1 changed during Phase 1 implementation;
- no pre-existing unrelated work was altered;
- no production source, schema, project, scheme, existing test, existing fixture, Catalog artifact, localization, or previous WT document changed;
- no build output or `xcresult` was added to the repository;
- all protected governing-document hashes remain unchanged;
- Phase 1 source additions are included only in `WayTaskTests`;
- the application build product is behaviorally identical at source level because no production input changed.

---

## 11. Rollback Strategy

### 11.1 Rollback boundary

The entire Phase 1 footprint is additive and limited to the eight proposed files in Section 8.1. The rollback boundary is therefore the pre-Phase-1 repository snapshot plus the recorded list of pre-existing unrelated changes.

No Product store, migration, schema, or production compatibility field is changed, so no user-data rollback is required.

### 11.2 Rollback triggers

Rollback the current step, and stop, if:

- a production, schema, project, existing test, or prior WT file must be edited to make the step pass;
- a test touches the application’s default store or any non-synthetic data;
- a source fixture changes after a migration test;
- test diagnostics expose a forbidden field;
- fixture output is non-deterministic after environmental causes are excluded;
- the baseline behavior changes rather than merely becoming observed;
- pre-existing test behavior changes unexpectedly;
- automatic test-target discovery requires a project-setting change;
- a new test causes unrecoverable global state or persistent cross-test interference.

### 11.3 Rollback procedure

For a failed step:

1. Stop test execution and close all containers.
2. Preserve privacy-safe failure evidence outside the repository.
3. Identify the exact files introduced by that step.
4. Restore those files from the pre-step patch/snapshot or remove only the newly proposed paths after verifying their exact names.
5. Do not use a broad reset, recursive workspace deletion, or an operation that touches pre-existing user changes.
6. Clear only the step-owned derived-data and temporary test directories.
7. Re-run repository validation and the last passing focused suite.

For full Phase 1 rollback, remove or restore only the eight proposed files, then run the preflight build and full baseline suite.

### 11.4 Validation after rollback

Rollback is complete only when:

- `git status --short` matches the recorded pre-step state;
- protected hashes match;
- no Phase 1 resource remains in the test bundle;
- the generic application build passes;
- the pre-existing full test suite returns to its recorded baseline;
- no temporary synthetic store remains in the step-owned directory.

---

## 12. Risks

| Risk | Consequence | Mitigation | Stop/rollback condition |
|---|---|---|---|
| Current defects become mistaken for requirements | Later architecture cutover is blocked by legacy assertions | CB/KD labels, “current legacy” test naming, explicit retirement ownership | Any assertion is described as approved target behavior |
| Fixture encodes an assumed rather than verified state | False confidence or misleading migration input | Derive every expected result from verified current source plus a passing baseline run | Fixture cannot be traced to source and a test |
| Shared source fixture is mutated | Non-repeatable migration results | Mandatory per-test working copy and source digest | Any source hash or metadata changes |
| Test uses real user data | Privacy and integrity violation | Synthetic-only namespaces; no application default store | Any non-synthetic identifier or user path is accessed |
| Parallel tests collide | Flaky or corrupt baselines | Unique directories and stable case ownership | Cross-test record or filesystem interference |
| SwiftData binary files are treated as golden truth | OS/toolchain-dependent false failures | Canonical semantic snapshots instead of binary checksums | Assertion depends on raw database bytes |
| Diagnostic attachments leak sensitive fields | Privacy regression | Explicit allowlist and sentinel scan | Any forbidden value appears |
| Performance results are overinterpreted | Premature optimization or unsupported limits | Label Reference profile observational; no Phase 1 thresholds | Result is used as a capacity guarantee |
| Test target discovery fails | Pressure to modify project settings | Preflight resource check and stop condition | `project.pbxproj` change would be required |
| Existing tests are edited to make new tests pass | Baseline is rewritten | New files only; full diff audit | Any existing test changes |
| Characterization requires production injection | Runtime behavior changes during preparation | Use existing seams or record source-only characterization | Production source edit is proposed |
| Repository contains unrelated user changes | Accidental overwrite or false verification | Record pre-state and compare only scoped paths | Phase 1 overlaps an unrelated modified path |
| Toolchain/simulator unavailable | Incomplete validation | Record environment and rerun without altering project | Final evidence lacks build/full-suite results |
| Fixture scale exhausts CI resources | Phase cannot run reliably | Separate Functional and Reference profiles | Functional suite becomes unstable or non-terminating |

---

## 13. Dependencies

### 13.1 Governing architecture and decisions

- `docs/Audits/1.0.3/WT-030A_ProductStateUXAudit.md`
- `docs/Audits/1.0.3/WT-030_ArchitectureSummary.md`
- `docs/ImplementationPlans/1.0.3/WT-031A_ProductStateImplementationPlan.md`
- `docs/ImplementationSpecifications/1.0.3/WT-032A_ProductState_Phase0DecisionSpecification.md`
- the repository’s current Product Specification

WT-032A decisions D-01 through D-37 are target semantics. Phase 1 uses them to identify what must be characterized and later replaced; it does not enact them.

### 13.2 Repository dependencies

- existing V1, V2, and V3 SwiftData schema declarations and migration plan;
- current Product, Shopping-list, compatibility, Plan, Session, History, Catalog, Map, location, notification, scanner, repair, and recovery implementations;
- existing XCTest target and file-system-synchronized group behavior;
- existing migration, repair, deletion, catalog, monitoring, resilience, Shopping, Map, and Product Knowledge tests;
- Foundation, XCTest, SwiftData, and platform cryptographic hashing available to the test target.

### 13.3 Environment dependencies

- the repository-supported Xcode and Swift toolchain;
- a supported iOS Simulator runtime and destination;
- adequate temporary disk capacity for isolated file-backed fixtures;
- package dependencies resolvable through the existing project;
- a controlled environment for Reference-profile performance observations.

### 13.4 Downstream dependencies

Phase 2 schema and migration work depends on:

- the complete reader/writer inventory;
- V1/V2/V3 synthetic input fixtures;
- canonical semantic snapshot tooling;
- migration source-copy safety;
- recorded known-legacy behavior;
- stable baseline metrics and test commands.

Phase 1 does not make Phase 2 changes permissible by itself.

---

## 14. Phase Exit Criteria

All criteria are mandatory:

- [ ] All current Product State readers and writers are enumerated with exact paths and classified by lifecycle.
- [ ] Every CB behavior and KD defect in Section 4 has executable coverage or a documented, justified source-only characterization.
- [ ] The fixture manifest covers the required cases and contains only synthetic data.
- [ ] V1, V2, V3, and current-schema file-backed fixtures run from isolated working copies.
- [ ] Source fixture immutability is proven.
- [ ] Canonical semantic snapshots are deterministic across two clean executions.
- [ ] Current repair is characterized for idempotency.
- [ ] Current Product UUID and catalog snapshot preservation is characterized.
- [ ] Current duplicate, orphan, tombstone, Completed/Recent, history, session, and location states are represented.
- [ ] Product State consumer characterization covers Plan, Shopping, Map/location, notification/geofence, and catalog/custom identity paths to the extent allowed without production changes.
- [ ] Test diagnostics pass privacy and no-network validation.
- [ ] Functional and Reference fixture profiles are recorded.
- [ ] p50/p95 baseline observations and environment metadata are recorded.
- [ ] The generic application build passes.
- [ ] All focused suites pass.
- [ ] All listed existing regression suites pass.
- [ ] The complete `WayTaskTests` target passes.
- [ ] No production, schema, project, existing test, localization, Catalog, or prior WT file changed.
- [ ] Only the eight proposed Phase 1 artifacts changed.
- [ ] The evidence record is complete, reproducible, and privacy-safe.

Any unchecked criterion prevents Phase 1 completion.

---

## 15. Definition of Done

Phase 1 is done only when:

1. The implementation footprint exactly matches Section 8.1.
2. Every new test identifies whether it asserts a stable current behavior or a known legacy defect.
3. No new test claims target architecture is implemented.
4. The fixture and support layer reproduce current state without using real user data.
5. Migration fixtures are safe, isolated, and reusable by later specifications without modification of shipped schemas.
6. Full build, focused test, migration, diagnostic, performance, and repository validation evidence exists.
7. The complete pre-existing suite passes without edits.
8. Rollback has been dry-reviewed against the actual changed paths.
9. The application’s production source inputs are unchanged.
10. The evidence record clearly states that Phase 1 changed observability only, not behavior or authority.

Completion of this definition does not authorize production implementation or an authority cutover.

---

## 16. Implementation Execution Order

### E-00 — Establish the execution boundary and validate the pre-Phase baseline

- **Prerequisite:** Approved governing documents are present and readable; an implementation operator has separate authorization to execute Phase 1.
- **Files modified:** None.
- **Actions:**
  1. Record commit, branch, repository status, and pre-existing changed/untracked paths.
  2. Hash governing WT documents, Product Specification, project file, schemas, and existing test tree.
  3. Record Xcode, Swift, macOS, simulator runtime/device, and package-resolution state.
  4. Verify file-system-synchronized test group behavior.
  5. Run the generic build and complete pre-Phase test suite.
- **Validation before continuing:** Baseline build and test results are recorded; no Product State failure is unexplained; no file changed during validation.
- **Rollback point:** E-00 has no repository mutation. Remove only its temporary derived data if execution stops.

### E-01 — Create the static inventory and baseline evidence record

- **Prerequisite:** E-00 passes.
- **Files modified:** Proposed `docs/ImplementationEvidence/1.0.3/WT-031A_Phase1_ProductStateBaseline.md`.
- **Actions:**
  1. Record the E-00 environment and repository baseline.
  2. Inventory exact reads, writes, direct `ModelContext` mutations, schema fields, migration stages, repair paths, UI consumers, and existing tests.
  3. Classify every path by Product, list entry, compatibility, Plan, Session, History, Catalog, Map/location, notification, or recovery lifecycle.
  4. Map each finding to CB/KD and WT-032A decision identifiers.
- **Validation before continuing:** Every minimum path in Section 4.3 is present; inventory commands are reproducible; evidence contains no private data or architectural reinterpretation.
- **Rollback point:** Remove only the proposed evidence file; confirm E-00 repository state.

### E-02 — Add and validate the synthetic fixture manifest

- **Prerequisite:** E-01 inventory is complete enough to verify every manifest expectation.
- **Files modified:** Proposed `WayTaskTests/ProductState/Fixtures/product-state-current-behavior-v1.json`.
- **Actions:**
  1. Add all cases from Section 5.2.
  2. Assign stable synthetic UUIDs and fixed timestamps.
  3. Record current expected fields, counts, CB/KD references, and `expectationKind`.
  4. Validate JSON syntax and forbidden-field policy with read-only tooling.
- **Validation before continuing:** Case IDs and UUIDs are unique; required coverage is complete; no target schema/value is encoded; test bundle discovery succeeds without a project edit.
- **Rollback point:** Remove only the proposed JSON resource and its owned empty directories; re-run repository scope validation.

### E-03 — Add deterministic characterization support

- **Prerequisite:** E-02 manifest is valid and bundle-discoverable.
- **Files modified:** Proposed `WayTaskTests/ProductState/Support/ProductStateCharacterizationSupport.swift`.
- **Actions:**
  1. Implement manifest decoding and validation.
  2. Implement deterministic in-memory and file-backed fixture builders.
  3. Implement mandatory source-to-working-copy migration isolation.
  4. Implement canonical semantic snapshot/digest and cleanup.
  5. Implement privacy-safe attachment and percentile helpers.
  6. Add support self-tests within the later owning suites or the same proposed test files; do not create an additional path.
- **Validation before continuing:** Generic build passes; manifest loads; in-memory smoke test passes; V3 working-copy smoke test passes; source digest is unchanged; cleanup is proven.
- **Rollback point:** Remove only the support file; keep E-02 only if it remains independently valid; otherwise roll back E-02 as well.

### E-04 — Add domain current-behavior characterization

- **Prerequisite:** E-03 support validations pass.
- **Files modified:** Proposed `WayTaskTests/ProductState/ProductStateDomainCharacterizationTests.swift`.
- **Actions:**
  1. Add list add/reopen/remove and multi-list shared compatibility tests.
  2. Add duplicate logical entry characterization.
  3. Add Product tombstone, active-session removal, and retained-reference tests.
  4. Add barcode and catalog implicit-restore characterization.
  5. Add current history-key behavior.
  6. Add active-session reuse, collection isolation, and Finish-header behavior.
- **Validation before continuing:** Domain suite passes twice from clean state; every test has CB/KD and decision traceability; no application store or network access; adjacent unchanged state is asserted.
- **Rollback point:** Remove only the domain test file; rerun E-03 support validation.

### E-05 — Add persistence and migration characterization

- **Prerequisite:** E-04 passes and current behavior expectations are executable.
- **Files modified:** Proposed `WayTaskTests/ProductState/ProductStatePersistenceCharacterizationTests.swift`.
- **Actions:**
  1. Add V1, V2, V3/current file-backed construction and reopen/migration cases.
  2. Add the four-flag compatibility matrix.
  3. Add Product UUID/catalog snapshot stability.
  4. Add duplicate, orphan, tombstone, Completed/Recent, history, session, and location persistence cases.
  5. Add repeated-repair semantic digest equality.
  6. Add source-fixture immutability and failed-working-copy safety.
- **Validation before continuing:** Focused suite passes twice; source hashes remain equal; no new schema identifier or migration stage exists; existing migration, repair, deletion, catalog, and resilience suites pass.
- **Rollback point:** Remove only the persistence characterization file; rerun E-04 and existing migration/repair suites.

### E-06 — Add cross-surface consumer characterization

- **Prerequisite:** E-05 persistence baseline passes.
- **Files modified:** Proposed `WayTaskTests/ProductState/ProductStateConsumerCharacterizationTests.swift`.
- **Actions:**
  1. Add current Plan, Trip, and Context filtering cases.
  2. Add Map/store and saved-location input cases using existing seams.
  3. Add geofence/notification Product/list snapshot round-trip.
  4. Add catalog-backed, tombstoned catalog-backed, custom, and stale identity cases.
  5. Record source-only gaps in the evidence file instead of adding production hooks.
- **Validation before continuing:** Consumer suite passes; four flag combinations and stale references are covered where applicable; no production file changed; existing Map, Product Catalog, Product Knowledge, Shopping Classification, and Shopping UX suites pass.
- **Rollback point:** Remove only the consumer characterization file; rerun E-05 focused validation.

### E-07 — Add diagnostic and privacy characterization

- **Prerequisite:** E-06 passes and the set of test attachment fields is final.
- **Files modified:** Proposed `WayTaskTests/ProductState/ProductStateDiagnosticsCharacterizationTests.swift`.
- **Actions:**
  1. Characterize current startup diagnostic stage/outcome sequences.
  2. Verify metadata allowlist and recovery counts.
  3. Inject private sentinel values and scan diagnostic envelopes/attachments.
  4. Prove tests do not initialize network transmission.
  5. Validate that failure descriptions use safe identifiers only.
- **Validation before continuing:** New diagnostics suite and existing Sentry/startup resilience suites pass; forbidden-value scan is empty; no production monitoring file changed.
- **Rollback point:** Remove only the diagnostics characterization file; rerun E-06 and existing monitoring tests.

### E-08 — Add and execute performance baseline tests

- **Prerequisite:** E-04 through E-07 correctness and privacy suites pass.
- **Files modified:** Proposed `WayTaskTests/ProductState/ProductStatePerformanceBaselineTests.swift`; update only the results section of the proposed evidence document.
- **Actions:**
  1. Add Functional-profile correctness checks.
  2. Add Reference-profile operations from Section 7.5.
  3. Execute three warm-ups and thirty measured samples in a controlled Release configuration.
  4. Repeat the controlled run.
  5. Record safe environment, counts, digests, p50, p95, minimum, maximum, and sample count.
- **Validation before continuing:** Both runs have equal semantic digests and counts; all samples are finite; no corruption, non-termination, or resource exhaustion; timing results are recorded without creating a threshold.
- **Rollback point:** Remove only the performance test file and its evidence results; retain earlier evidence sections; rerun the Functional profile.

### E-09 — Run integrated validation and complete evidence

- **Prerequisite:** E-08 passes.
- **Files modified:** Update only proposed `docs/ImplementationEvidence/1.0.3/WT-031A_Phase1_ProductStateBaseline.md`.
- **Actions:**
  1. Run all five new suites together.
  2. Run every named existing regression suite in Section 10.3.
  3. Run the complete `WayTaskTests` target.
  4. Run the generic application build.
  5. Complete migration, diagnostics, performance, and evidence matrices.
  6. Record any environment-only retry transparently.
- **Validation before continuing:** All required builds and tests pass; evidence links every result to a command/environment; no result is omitted or relabeled; no private data appears.
- **Rollback point:** Restore the evidence document to its E-08 state if evidence editing is invalid. Test failures require rollback to the first failing artifact, not editing current production behavior.

### E-10 — Perform final repository and rollback audit

- **Prerequisite:** E-09 passes completely.
- **Files modified:** Final verification entry in the proposed evidence document only.
- **Actions:**
  1. Compare current status with E-00.
  2. Confirm the changed path set exactly matches Section 8.1.
  3. Re-hash protected governing, source, schema, project, and existing test files.
  4. Confirm no derived data, store, or `xcresult` is tracked.
  5. Review each new assertion for “current” versus “target” wording.
  6. Dry-review rollback using exact paths without executing a destructive workspace operation.
- **Validation before continuing:** All Phase Exit Criteria and Definition of Done items are checked; protected hashes match; only permitted new files exist; the terminal result is recorded once in the evidence.
- **Rollback point:** If scope verification fails, roll back the responsible Phase 1 step. If responsibility cannot be isolated safely, roll back all eight proposed Phase 1 artifacts using the pre-Phase snapshot while preserving unrelated work.

---

## 17. Decision Traceability

### 17.1 Traceability conventions

- WT-030A references use the audit’s architectural subjects and acceptance areas because Phase 1 does not implement target semantics.
- WT-031A reference is Phase 1, “Characterization and safety baseline,” plus the relevant current inventory, risk, test, or performance section.
- WT-032A decisions identify the future semantic boundary that the current-behavior evidence protects.
- “Evidence only” means the step records a path but does not add a production change.

### 17.2 Execution-step traceability matrix

| Step | WT-030A origin | WT-031A Phase 1 requirement | WT-032A decisions characterized | Affected implementation files | Affected tests/evidence |
|---|---|---|---|---|---|
| E-00 | Current architecture, acceptance criteria, implementation gate | Prerequisite and safety baseline | D-01–D-37 collectively | None | Existing complete suite; preflight evidence |
| E-01 | Current lifecycle, transitions, user actions, indicators, cross-screen consistency, limitations | Enumerate all readers/writers and baseline counts | D-01–D-37; especially D-01, D-02, D-06, D-08, D-11, D-19, D-21, D-24, D-33 | Baseline evidence document | Static inventory and protected hashes |
| E-02 | Current state combinations, deletion/restoration, migration, multi-surface behavior | File-backed V1/V2/V3 and contradictory-state fixtures | D-01, D-02, D-08–D-12, D-15–D-19, D-22, D-25–D-32 | Fixture manifest | Manifest decode/privacy self-test |
| E-03 | Persistence, recovery, state representation | Reusable fixture and migration safety infrastructure | D-12, D-18, D-24–D-34 | Characterization support | Support smoke, isolation, snapshot, digest, cleanup self-tests |
| E-04 | Product lifecycle, transitions, user actions, Product History, deletion/restoration, Shopping completion | Current command and defect characterization | D-01–D-10, D-13–D-18, D-22, D-35–D-37 | Domain characterization tests | Domain suite; CB-01–CB-11; KD-01–KD-10 |
| E-05 | Persistence, migration, recovery, Catalog lifecycle | V1/V2/V3 fixture and contradictory persisted-state coverage | D-06–D-12, D-18–D-19, D-24–D-34 | Persistence characterization tests | Migration, repair, deletion, catalog, resilience suites |
| E-06 | Cross-screen consistency across Products, Shopping, Map, notifications; scanner/catalog integration | Consumer and projection characterization | D-01–D-03, D-11–D-14, D-19–D-23, D-33 | Consumer characterization tests | Consumer suite; existing Map, Catalog, Knowledge, Shopping suites |
| E-07 | UX clarity, privacy-sensitive indicators/notifications, reliability | Diagnostic baseline and redaction | D-20–D-23, D-34–D-37 | Diagnostics characterization tests | Diagnostic suite; existing Sentry and startup resilience suites |
| E-08 | Performance and reliability impact | Record current projections and p95 metrics | D-08–D-12, D-18, D-24, D-35–D-37 | Performance baseline tests; evidence results | Functional/reference performance suites |
| E-09 | Acceptance criteria and implementation gate | Integrated validation and complete baseline | D-01–D-37 collectively | Evidence document | All new, named regression, and complete test suites |
| E-10 | Architecture constraints, measurable acceptance, and implementation gate | Exit criteria, scope lock, rollback proof | D-33–D-37 and all protected target decisions | Evidence document verification entry | Repository audit and manual review artifact |

### 17.3 Requirement-to-file traceability

| Characterization subject | Current verified implementation area | Proposed Phase 1 test/evidence | Future decision consumer |
|---|---|---|---|
| No global Product completion | `ShoppingItem.isCompleted` readers/writers | Domain + Consumer suites; inventory | D-01; later Product State domain specification |
| Entry lifecycle and collected semantics | `ShoppingListEntry.isChecked`, session collected IDs | Domain + Persistence suites | D-02, D-03, D-04 |
| Abandon and Finish | Shopping Session finish/header behavior | Domain suite | D-05, D-35, D-36 |
| Product History | Current history aggregation and retention | Domain + Persistence suites | D-06, D-07, D-31 |
| Multiple lists and duplicates | Entry persistence and shared compatibility item | Domain + Persistence suites | D-08, D-09, D-10, D-26, D-37 |
| Revision and snapshots | Runtime list revision, current Plan/session snapshots | Inventory + Consumer + Persistence suites | D-11, D-12, D-13, D-14 |
| Removal, restore, deletion | Product tombstone, list service, catalog/barcode persistence | Domain + Persistence suites | D-15–D-18, D-22, D-32 |
| Completed/Recent | Startup repair and current system lists | Persistence suite | D-19, D-30 |
| UI, routing, Map, notifications | Product/Shopping views, location, geofence payload | Inventory + Consumer suite | D-20, D-21, D-23 |
| Migration ownership | V1/V2/V3 migration and startup repair | Persistence suite and fixture infrastructure | D-24–D-34 |
| Atomicity and concurrency | Current service save boundaries and direct writers | Inventory + Domain/Persistence suites | D-35–D-37 |

### 17.4 Traceability completion rule

An execution step is not complete if any of its tests, source findings, fixture cases, or evidence entries lacks:

- a current CB or KD identifier;
- a WT-030A architectural subject;
- the WT-031A Phase 1 requirement;
- at least one WT-032A decision that will consume the baseline;
- an exact current implementation or proposed test path.

Traceability records current evidence and future decision consumption. It does not move target authority into Phase 1.

---

## 18. Terminal Decision

**READY FOR IMPLEMENTATION**

This terminal value means the Phase 1 preparation specification is complete and executable. It does not authorize production code, test, schema, project, or repository changes; execution still requires the separately approved implementation authority and must remain within this document’s additive, behavior-preserving boundary.
