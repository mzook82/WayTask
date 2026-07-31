# WT-033A T-02 — Target Persistence Graph Evidence

**Product:** WayTask iOS

**Version:** 1.0.3

**Execution step:** T-02 only

**Evidence date:** 2026-07-31

**Implementation status:** Complete; awaiting review

**Later-step authorization:** None

---

## Executive Summary

T-02 adds the approved target Product State and Shopping Session persistence
representation as an inactive `WayTaskSchemaV4`. The graph represents stable
Product, list, entry, history-event, Session, line, stop, plan-snapshot,
migration, revision, outcome, snapshot, and identity concepts. It implements no
repository, query, command, transaction, migration, startup, or UI behavior.

The running application remains on `WayTaskSchemaV3`. The production migration
plan still registers only V1, V2, and V3, and its only stages remain V1→V2 and
V2→V3. `WayTaskSchemaV4` is reachable only through an explicitly named inactive
schema projection used by the T-02 tests. No production consumer references the
target schema, and no target persistent store was produced.

Qualification passed:

- focused T-02 persistence-graph suite: 6 of 6;
- five frozen Phase 1 Product State suites plus support self-tests: 49 of 49;
- complete `WayTaskTests` target: 368 of 368;
- generic unsigned Debug and Release builds: exit 0;
- protected-file, production-inactivity, repository-scope, and cleanup audits:
  pass.

The terminal decision is **T-02 COMPLETE — READY FOR REVIEW**.

---

## Starting Repository State

The repository was inspected before the first T-02 write.

| Field | Starting value |
|---|---|
| Branch | `main` |
| Upstream | `origin/main` |
| Ahead / behind | `0 / 0` |
| Full commit SHA | `d81df92e6d9cb568e7de2e5b4b51b1cdc88cb404` |
| Staged paths | 0 |
| Tracked modified paths | 0 |
| Untracked paths | 0 |

T-01 was present at the approved starting commit. There was no overlapping work
at any authorized T-02 path.

---

## Authorized Change Set

### Modified production files

| File | T-02 addition |
|---|---|
| `WayTask/Models.swift` | Target Product, Shopping List, and Shopping Entry declarations |
| `ProductHistory.swift` | Target immutable-event persistence representation |
| `ShoppingSession.swift` | Target Session, line, stop, and bounded migration-exception declarations |
| `WayTask/Persistence/WayTaskSchema.swift` | Inactive V4 registration and test-only inactive schema projection |

The production patch is additive: 517 insertions and zero deletions. Existing
V1/V2/V3 declarations and compatibility model declarations were not edited.

### Created test and evidence files

| File | Purpose |
|---|---|
| `WayTaskTests/ProductState/ProductStatePersistenceGraphTests.swift` | Six T-02-owned graph, relationship, round-trip, migration, vocabulary, and inactivity tests |
| `docs/ImplementationEvidence/1.0.3/WT-033A_T02_TargetPersistenceGraph.md` | This execution record |

The synchronized production and test roots discovered the Swift additions
automatically. `project.pbxproj` was not modified.

---

## Target Persistence Representation

### Registered target graph

`WayTaskSchemaV4` contains 12 persistent entity types:

1. existing compatibility `GeoLocation`;
2. existing compatibility `ShoppingItem`;
3. target `Product`;
4. target `ShoppingList`;
5. target `ShoppingListEntry`;
6. existing compatibility `ProductHistory` aggregate;
7. target `ProductHistoryEvent`;
8. existing read-only `ProductKnowledge` compatibility representation;
9. target `ShoppingSession`;
10. target `ShoppingSessionLine`;
11. target `ShoppingSessionStop`;
12. target `ProductStateMigrationException`.

Retained compatibility models have no target lifecycle authority. They remain
physically representable for later approved migration and rollback work under
D-24 and D-33.

### Product, Library, lists, entries, and history

| Concept | Representation |
|---|---|
| Product identity | Stable Product UUID independent of optional Catalog reference snapshots |
| Library | Product-owned `active`/`removed` lifecycle representation, optional removal time, explicit revision; no separate global completion state |
| Shopping List | Stable list UUID, durable revision, title/purpose snapshot, timestamps, cascading owned entries |
| Shopping Entry | Stable entry UUID plus exact list UUID and Product UUID; Needed/Resolved vocabulary; resolution reason, time, provenance, and identity evidence; quantity/unit/note/order |
| Product relationship | Entry-to-Product nullifying relationship preserves the entry record if a reference is unavailable; stable Product UUID remains explicit |
| History Event | Stable event and Product UUIDs; named meaning, resolution/outcome values, source list/entry/Session/line/command provenance, event time, and display snapshot identity |

The graph does not create a separate Library row because the approved Library
lifecycle belongs to the stable Product. It does not represent a global Product
shopping, purchase, or completion flag.

### Shopping Session graph

| Concept | Representation |
|---|---|
| Session identity | Stable Session UUID |
| Source | Exact source-list UUID plus nullable historical revision and explicit revision provenance |
| Session revision | Durable unsigned revision value separate from source-list revision |
| Lifecycle | Raw representation of Active, Expired, Finished, or Abandoned |
| Migration condition | Native, Legacy Mapped, Legacy Incomplete, or Legacy Unresolved |
| Frozen snapshot | Stable snapshot UUID, version, generation, deterministic content signature, source-plan identity/signature/evidence time |
| Session timing | Start, activation, last activity, expiry/end, expiry reason, and policy version |
| Lines | Session-owned cascading lines, each with stable line/Session/snapshot identity and available exact list-entry/Product/stop identities |
| Stops | Session-owned cascading stop snapshots with stable stop/Session/snapshot identity, order, store-reference provenance, display/location evidence, and transient scope |
| Exceptions | Session-owned bounded migration-exception rows with safe digest, category, ordinal/count, and optional Session/line identity |

Native line snapshots can represent exact immutable source-list, source-entry,
Product, optional Global Product Concept, stop, display, quantity, unit, note,
ordering, snapshot-version, and provenance meaning. Migration exceptions can
retain a line and safe evidence when exact legacy source or Product identity is
not provable.

Execution state (`remaining`/`collected`) is represented separately from the
six native final outcomes (`purchased`, `alreadyHave`, `noLongerNeeded`,
`unavailable`, `skipped`, and `carriedForward`). Migration-only
`legacyUnknown` has a separate legacy-disposition field and cannot appear in
the T-01 native final-outcome vocabulary.

### Relationships and ownership

| Owner / reference | Delete rule |
|---|---|
| Shopping List → entries | Cascade |
| Entry → Product | Nullify |
| History Event → Product | Nullify |
| Session → source list | Nullify |
| Session → lines | Cascade |
| Session → stops | Cascade |
| Session → migration exceptions | Cascade |
| Session Line → source entry, Product, stop | Nullify |

Explicit stable identity fields remain present alongside relationships so
history, snapshots, migration evidence, and conflict validation do not depend
on live object references.

---

## Inactivity and Behavior Boundary

The target representation is intentionally inert:

- `WayTaskModelContainer.currentSchema` still constructs V3;
- `WayTaskSchemaMigrationPlan.schemas` still contains exactly V1, V2, and V3;
- `WayTaskSchemaMigrationPlan.stages` still contains exactly V1→V2 and V2→V3;
- `makeDefault`, `makeInMemory`, and startup persistence continue to use
  `currentSchema` and the unchanged migration plan;
- V4 has no migration stage and is not activated at startup;
- the only `inactiveTargetProductStateSchema` caller is the T-02 test suite;
- the only V4 references outside its declarations are T-02 test references;
- no production `ModelContext`, fetch, save, command, query, repository, or
  transaction behavior was added;
- no UI, ViewModel, Service, Catalog, Product Knowledge, package,
  localization, or project file changed.

The four modified production files import only Foundation and SwiftData, as
they did before T-02. The T-02 declarations add no platform presentation,
location, notification, camera, network, telemetry, Catalog-loader, or Product
Knowledge-service dependency.

---

## Focused T-02 Validation

### Exact selector

```text
-only-testing:WayTaskTests/ProductStatePersistenceGraphTests
```

The command used Debug configuration, the approved iPhone 17 Pro / iOS 26.5
simulator, serial execution, disabled signing, isolated Derived Data, and its
own result bundle.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet test \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=DE30E799-0496-4818-851D-FF613F62FCD3' \
  -derivedDataPath /private/tmp/WT033A-T02-20260731.7KXxbi/DerivedData-Focused \
  -resultBundlePath /private/tmp/WT033A-T02-20260731.7KXxbi/Focused.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:WayTaskTests/ProductStatePersistenceGraphTests \
  CODE_SIGNING_ALLOWED=NO
```

| Suite | Passed | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| `ProductStatePersistenceGraphTests` | 6 | 0 | 0 | 0 |

The suite proves:

- V4 registration while the live graph remains V3;
- exact entity attributes and relationships;
- Product/Library/list/entry/history graph round-trip;
- native Session snapshot, ownership, relationship, revision, execution, and
  final-outcome round-trip;
- legacy-incomplete Session and unresolved-line evidence representation;
- exact agreement with the approved T-01 lifecycle, migration, execution, and
  outcome raw vocabulary.

All test containers were in-memory; the focused tests created no durable store.

---

## Phase 1 and Complete Regression

### Phase 1 exact selectors

```text
-only-testing:WayTaskTests/ProductStateCharacterizationSupportSelfTests
-only-testing:WayTaskTests/ProductStateDomainCharacterizationTests
-only-testing:WayTaskTests/ProductStatePersistenceCharacterizationTests
-only-testing:WayTaskTests/ProductStateConsumerCharacterizationTests
-only-testing:WayTaskTests/ProductStateDiagnosticsCharacterizationTests
-only-testing:WayTaskTests/ProductStatePerformanceBaselineTests
```

| Required suite | Passed | Failed | Skipped |
|---|---:|---:|---:|
| `ProductStateCharacterizationSupportSelfTests` | 4 | 0 | 0 |
| `ProductStateDomainCharacterizationTests` | 12 | 0 | 0 |
| `ProductStatePersistenceCharacterizationTests` | 15 | 0 | 0 |
| `ProductStateConsumerCharacterizationTests` | 6 | 0 | 0 |
| `ProductStateDiagnosticsCharacterizationTests` | 5 | 0 | 0 |
| `ProductStatePerformanceBaselineTests` | 7 | 0 | 0 |
| **Product State subtotal** | **49** | **0** | **0** |

The final dedicated result bundle reported 49 passed, zero failed, zero
skipped, and zero expected failures. XCTest execution elapsed 1,211.013
seconds.

An earlier non-authoritative selector check named the performance suite
`ProductStatePerformanceCharacterizationTests`; Xcode consequently selected
only the other five suites and reported 42 passed. The selector audit caught
the mismatch. The exact approved six-selector gate above was then run to
completion and is the only Phase 1 result used for acceptance. No source or
test file changed between these runs.

### Complete test target

The complete test command selected the entire `WayTaskTests` target and used
the same simulator, Debug configuration, serial execution, disabled signing,
isolated Derived Data, and a separate result bundle.

| Scope | Passed | Failed | Skipped | Expected failures | Result |
|---|---:|---:|---:|---:|---|
| Complete `WayTaskTests` target | 368 | 0 | 0 | 0 | Passed |

This is the approved 362-test T-01 total plus the six T-02-owned tests. XCTest
execution elapsed 1,221.699 seconds. Six unchanged tests collected performance
metrics.

The only compile diagnostics during test qualification were the pre-existing
unused test-local `legacyByID` warning in
`WayTaskTests/ProductCatalog/ProductCatalogMigrationTests.swift:136` and the
existing Sentry debug-symbol build-phase dependency-analysis note. No file was
changed in response.

---

## Generic Unsigned Builds

Debug and Release each used a separate clean Derived Data directory:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Debug \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/WT033A-T02-20260731.7KXxbi/DerivedData-Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Release used the same command with `Release` and `DerivedData-Release`.

| Build | Exit | Result |
|---|---:|---|
| Generic unsigned Debug | 0 | Passed |
| Generic unsigned Release | 0 | Passed |

Successful production and test compilation proves filesystem-synchronized
membership. No project-file edit was needed.

---

## Protected Hash and Repository Audit

The important protected hashes were recomputed after all qualification:

| Protected item | SHA-256 | Result |
|---|---|---|
| WT-031B implementation specification | `98184b50823fca859a28322b1e9ecf7e75577b14085bbefffe4a3db0f2e1be10` | Match |
| WT-033A S-01 | `2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c` | Match |
| WT-033A S-02 | `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361` | Match |
| WT-033A T-00 | `fb5f55885414c7b98c25968483182224bbba55ab27f7db17d2a895be9b59aa98` | Match |
| WT-033A Dependency Re-Gate | `e95dab4801a535798fbbcfc10017cb9872c92dd1d0ca2351223f8ed2638b295c` | Match |
| `WayTaskStartupPersistence.swift` | `9eaf9dd7f95e96249d117a414084cdbdbb564bfb413a247f036bde29b55a7bd7` | Match |
| `WayTaskSchemaV1.swift` | `a82370847be17b15d15bebfd7aae72c48b98141f1fd2f346bb6afa8b33ff7a56` | Match |
| `project.pbxproj` | `9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f` | Match |
| `Package.resolved` | `42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244` | Match |
| T-01 domain vocabulary | `4fb347ce5d8f780351e6f0fe7e1aad158279cbddc02e87eed8f10836c71c6ce8` | Match |
| T-01 invariant validator | `4eda9aba6f76b75576426c67786e3245e10beaefce481944df24f6e49b4a25f4` | Match |
| T-01 transition tests | `ba53a7f302a7e036aa110adcd285d3873464eb696b128b389c03e0ba55e9f6c8` | Match |
| T-01 validator tests | `f50b324283a66322e9d5bb00e73de3c762777660474577eed37eeb75862bbf56` | Match |

Final T-02 implementation hashes before this evidence file was created:

| File | SHA-256 |
|---|---|
| `WayTask/Models.swift` | `74062d07cd3b1546ec11ad8a550223ff4b33b646715c0aa61a8f57e38b2a345c` |
| `ProductHistory.swift` | `57dd2b13e4e68d2292e5b45f5fe090f3b64344fe4c777a91f19cc47961e8da8c` |
| `ShoppingSession.swift` | `61310856a980c965fdbad9993f74054c6713071995f38a26384b75607e594383` |
| `WayTask/Persistence/WayTaskSchema.swift` | `68ffde0c4ed52051278311eb75d550545390c3ce943903a9d531011d0a8f4391` |
| T-02 persistence graph tests | `236759039eb8bb92923e48735b844259436c2d5ea79e632b010e60378395662f` |

Repository scope facts:

- branch and HEAD remain `main` at
  `d81df92e6d9cb568e7de2e5b4b51b1cdc88cb404`;
- upstream remains aligned at `0 / 0`;
- no staged path exists;
- the only production modifications are the four authorized files;
- the only new test is the T-02-owned persistence graph suite;
- the only new documentation is this evidence record;
- all four production edits are additions with zero deleted lines;
- no existing test, Phase 1 fixture, startup file, earlier schema file,
  migration, UI, ViewModel, Service, Catalog, Product Knowledge, project,
  package, localization, governing document, or prior evidence changed;
- `git diff --check` passed;
- source-reference audit found no production V4 consumer.

---

## Temporary Artifact Cleanup

All qualification artifacts were created below the isolated root
`/private/tmp/WT033A-T02-20260731.7KXxbi`.

After result summaries and build exits were recorded, that exact root was
deleted. An explicit `test ! -e` absence check passed. No T-02 Derived Data,
`.xcresult`, temporary store, sidecar, attachment, or generated build/test
artifact remains in the repository or temporary root.

---

## Rollback Instructions

Before commit, rollback is limited to:

1. remove the appended V4 target declarations from `WayTask/Models.swift`,
   `ProductHistory.swift`, and `ShoppingSession.swift`;
2. remove `WayTaskSchemaV4` and
   `inactiveTargetProductStateSchema` from
   `WayTask/Persistence/WayTaskSchema.swift`;
3. delete the T-02 test and this evidence document.

No persistent-store, schema-migration, data, startup, project, package, or
localization rollback is required. V4 was never placed in the live schema or
migration plan, and every T-02 test container was in-memory.

---

## Terminal Decision

T-02 COMPLETE — READY FOR REVIEW
