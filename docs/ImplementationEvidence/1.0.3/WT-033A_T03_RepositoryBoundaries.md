# WT-033A T-03 — Repository Boundaries Evidence

**Product:** WayTask iOS

**Version:** 1.0.3

**Execution step:** T-03 only

**Evidence date:** 2026-07-31

**Implementation status:** Complete; awaiting review

**Later-step authorization:** None

---

## Executive Summary

T-03 adds the inactive target repository boundary defined by WT-033A S-01 and
S-02. One new persistence component defines `ProductRepository`,
`ShoppingRepository`, `HistoryRepository`, and `ShoppingSessionRepository`,
plus private SwiftData adapters and a composition bundle for one caller-owned
`ModelContext`.

The repositories implement only identity-scoped persistence loads and staged
insert/delete mechanics for the approved V4 graph. They make no business-policy
decision, build no application query projection, execute no command, and expose
no save, commit, rollback, migration, startup, or external-side-effect
operation. Autosave is disabled for the supplied context, so a later authorized
transaction coordinator must own the single commit.

The boundary is inactive. No production caller references it, the application
continues to use the existing V3 startup graph and current services, and no
current behavior was retired or changed.

Qualification passed:

- both clean isolated focused runs: 8 of 8 tests;
- directly affected persistence, schema, Catalog, and Product Knowledge suites:
  35 of 35;
- five Phase 1 Product State suites plus support self-tests: 49 of 49;
- complete `WayTaskTests` target: 376 of 376;
- generic unsigned Debug and Release builds: exit 0;
- repository inactivity, forbidden-dependency, protected-hash, scope, and
  cleanup audits: pass.

The terminal decision is **T-03 COMPLETE — READY FOR REVIEW**.

---

## Starting Repository State

The repository was inspected before the first T-03 write.

| Field | Starting value |
|---|---|
| Branch | `main` |
| Upstream | `origin/main` |
| Ahead / behind | `0 / 0` |
| Full commit SHA | `d16852e881ce16aeb1d4334f85d87c9e13e61219` |
| Staged paths | 0 |
| Tracked modified paths | 0 |
| Untracked paths | 0 |

The approved T-01 and T-02 implementation/evidence were present at the clean
starting commit. There was no repository overlap.

---

## Authorized Change Set

| File | Status | Purpose |
|---|---|---|
| `WayTask/ProductState/Persistence/ProductStateRepositories.swift` | Created | TC-07 repository responsibilities, scoped SwiftData adapters, and inactive shared-context composition |
| `WayTaskTests/ProductState/ProductStateRepositoryTests.swift` | Created | Eight T-03-owned deterministic scoping, staging, isolation, and inactivity tests |
| `docs/ImplementationEvidence/1.0.3/WT-033A_T03_RepositoryBoundaries.md` | Created | This execution record |

No existing production, test, schema, migration, startup, project, package,
localization, Catalog, Product Knowledge, ViewModel, Service, integration, or
prior documentation file changed.

The synchronized production and test roots discovered both Swift files. No
`project.pbxproj` edit was required.

---

## Repository Contract

### ProductRepository

Responsibilities are limited to:

- load target Products by exact stable Product UUID;
- load Products by explicit `ProductLibraryLifecycle` value;
- return deterministic ordered rows without hiding duplicate/corrupt matches;
- stage insertion of a caller-constructed Product.

It does not create, edit, remove, restore, match, merge, or decide Product
identity or Library lifecycle. It exposes no physical Product delete operation,
consistent with durable tombstone ownership.

### ShoppingRepository

Responsibilities are limited to:

- load one exact named list identity;
- load entries by exact `(entry ID, list ID)`;
- load deterministic entries for one exact list;
- load entries for one exact `(list ID, Product ID)` pair;
- stage caller-constructed list/entry insertion;
- stage list/entry deletion for a later command-owned transaction.

Every membership read names a list. There is no global Shopping scan,
compatibility fallback, selected-list inference, uniqueness repair, lifecycle
transition, revision update, or cross-list policy.

### HistoryRepository

Responsibilities are limited to:

- load event rows by exact stable event UUID;
- load deterministic immutable-event rows for one exact Product UUID;
- stage insertion of a caller-constructed target history event.

It exposes no delete, mutation, purchase inference, legacy promotion,
aggregation, or retention-policy operation.

### ShoppingSessionRepository

Responsibilities are limited to:

- load Session rows by exact stable Session UUID;
- load Session rows for one explicit lifecycle value;
- load deterministic lines, stops, and migration-exception evidence by exact
  Session UUID;
- stage insertion of a caller-constructed Session aggregate.

It implements no Start, Resume, Collect, Undo, Finish, Abandon, expiration,
recovery, migration mapping, outcome assignment, or conflict policy. It exposes
no Session deletion operation.

### Shared persistence scope

`ProductStateRepositories` composes all four adapters over exactly one supplied
`ModelContext`. Construction disables context autosave. The context remains
private to the adapter access object after composition.

The boundary provides only fetch, stage-insert, and Shopping stage-delete
mechanics. It deliberately contains no `save`, `commit`, `rollback`, or
transaction-coordinator method. Tests prove that staged operations across all
four repositories are invisible to a second context until an external owner
explicitly saves the shared context, and that staged deletion behaves the same
way.

This is the T-03 persistence responsibility needed by later authorized steps;
it does not implement the T-05 transaction coordinator.

---

## Determinism and Scoped Reads

Every multi-row load declares stable ordering:

| Repository result | Ordering |
|---|---|
| Products | `createdAt`, then stable Product UUID |
| Shopping Lists | `createdAt`, then stable list UUID |
| Shopping Entries | `sortOrder`, then stable entry UUID |
| History Events | `occurredAt`, then stable event UUID |
| Sessions | `startedAt`, then stable Session UUID |
| Session Lines | `sortOrder`, then stable line UUID |
| Session Stops | `sortOrder`, then stable stop UUID |
| Migration Exceptions | `ordinal`, then stable exception UUID |

Identity methods return arrays rather than silently selecting one record. This
keeps duplicate or contradictory storage visible to the later invariant and
command boundaries instead of making the repository a policy owner.

The T-03 loads are persistence scoping operations, not the application Queries
owned by TC-06/T-13. No Library, list, membership-action, plan, Finish-review,
Map, notification, discovery, Store, or recovery projection was introduced.

---

## Inactivity and Dependency Audit

Static source/reference audits prove:

- all `ProductStateRepositories` and required repository protocol references
  occur only in the new persistence file and T-03 test file;
- no current production source constructs or calls the repositories;
- startup persistence is unchanged and does not reference the repository layer;
- the migration plan and migration code are unchanged and do not reference it;
- `WayTaskModelContainer.currentSchema` remains V3;
- V4 remains absent from `WayTaskSchemaMigrationPlan`;
- no existing Service, ViewModel, View, Map, notification, Camera, AI,
  Catalog, or Product Knowledge implementation references the boundary;
- the production file imports only Foundation and SwiftData;
- no SwiftUI, Core Location, MapKit, UserNotifications, AVFoundation, network,
  Sentry, ViewModel, startup, or migration implementation dependency exists;
- no model-context save/transaction call and no save/commit/rollback method
  exists in the production component.

Repository tests construct only explicit in-memory V4 containers. They never
open the application default store.

---

## Focused T-03 Tests

### Exact selector

Both focused runs used:

```text
-only-testing:WayTaskTests/ProductStateRepositoryTests
```

The command shape was:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet test \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=DE30E799-0496-4818-851D-FF613F62FCD3' \
  -derivedDataPath /private/tmp/WT033A-T03-20260731.Xf1N9H/DerivedData-Focused-1 \
  -resultBundlePath /private/tmp/WT033A-T03-20260731.Xf1N9H/Focused-1.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:WayTaskTests/ProductStateRepositoryTests \
  CODE_SIGNING_ALLOWED=NO
```

Run 2 used separate clean `DerivedData-Focused-2` and
`Focused-2.xcresult` paths.

| Run | Passed | Failed | Skipped | Expected failures | Result |
|---|---:|---:|---:|---:|---|
| Focused 1 | 8 | 0 | 0 | 0 | Passed |
| Focused 2 | 8 | 0 | 0 | 0 | Passed |

Coverage includes all four repositories, exact-identity scoping, deterministic
ordering, same-Product cross-list isolation, history provenance scoping,
Session-owned row scoping, shared-context staging, no independent save, staged
deletion, read-only repeatability, and target-schema inactivity.

---

## Directly Affected Regression

Exact selectors:

```text
-only-testing:WayTaskTests/ProductStatePersistenceGraphTests
-only-testing:WayTaskTests/WayTaskSchemaMigrationTests
-only-testing:WayTaskTests/ProductCatalogServiceTests
-only-testing:WayTaskTests/InMemoryProductKnowledgeRepositoryTests
```

| Suite | Passed | Failed | Skipped |
|---|---:|---:|---:|
| `ProductStatePersistenceGraphTests` | 6 | 0 | 0 |
| `WayTaskSchemaMigrationTests` | 5 | 0 | 0 |
| `ProductCatalogServiceTests` | 12 | 0 | 0 |
| `InMemoryProductKnowledgeRepositoryTests` | 12 | 0 | 0 |
| **Total** | **35** | **0** | **0** |

This gate proves the T-02 graph remains valid, prior schema behavior remains
frozen, and the separate Catalog and Product Knowledge repository authorities
remain unchanged.

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

The result bundle reported 49 passed, zero failed, zero skipped, and zero
expected failures. XCTest execution elapsed 1,188.273 seconds.

### Complete test target

The complete command selected the entire `WayTaskTests` target with Debug
configuration, the approved simulator, serial execution, disabled signing,
isolated Derived Data, and a separate result bundle.

| Scope | Passed | Failed | Skipped | Expected failures | Result |
|---|---:|---:|---:|---:|---|
| Complete `WayTaskTests` target | 376 | 0 | 0 | 0 | Passed |

This is the approved 368-test T-02 baseline plus eight T-03 tests. XCTest
execution elapsed 1,227.623 seconds. Six unchanged tests collected performance
metrics.

The only compile diagnostics during test qualification were the pre-existing
unused test-local `legacyByID` warning in
`WayTaskTests/ProductCatalog/ProductCatalogMigrationTests.swift:136` and the
existing Sentry debug-symbol build-phase dependency-analysis note. No file was
changed in response.

---

## Generic Unsigned Builds

Debug command shape:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Debug \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/WT033A-T03-20260731.Xf1N9H/DerivedData-Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Release used the same command with `Release` and `DerivedData-Release`.

| Build | Exit | Result |
|---|---:|---|
| Generic unsigned Debug | 0 | Passed |
| Generic unsigned Release | 0 | Passed |

Both clean builds emitted no build warning or error output.

---

## Protected Hash and Repository Scope Audit

Important protected hashes after qualification:

| Protected item | SHA-256 | Result |
|---|---|---|
| WT-031B implementation specification | `98184b50823fca859a28322b1e9ecf7e75577b14085bbefffe4a3db0f2e1be10` | Match |
| WT-033A S-01 | `2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c` | Match |
| WT-033A S-02 | `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361` | Match |
| T-02 `WayTask/Models.swift` | `74062d07cd3b1546ec11ad8a550223ff4b33b646715c0aa61a8f57e38b2a345c` | Match |
| T-02 `ProductHistory.swift` | `57dd2b13e4e68d2292e5b45f5fe090f3b64344fe4c777a91f19cc47961e8da8c` | Match |
| T-02 `ShoppingSession.swift` | `61310856a980c965fdbad9993f74054c6713071995f38a26384b75607e594383` | Match |
| T-02 `WayTaskSchema.swift` | `68ffde0c4ed52051278311eb75d550545390c3ce943903a9d531011d0a8f4391` | Match |
| T-02 graph tests | `236759039eb8bb92923e48735b844259436c2d5ea79e632b010e60378395662f` | Match |
| T-02 evidence | `f39525267de1902c07a3d2c3f44ae26483b220ca5646789638981a589ef01dc3` | Match |
| Startup persistence | `9eaf9dd7f95e96249d117a414084cdbdbb564bfb413a247f036bde29b55a7bd7` | Match |
| Frozen V1 schema | `a82370847be17b15d15bebfd7aae72c48b98141f1fd2f346bb6afa8b33ff7a56` | Match |
| `project.pbxproj` | `9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f` | Match |
| `Package.resolved` | `42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244` | Match |

T-03 implementation hashes before this evidence file was created:

| File | SHA-256 |
|---|---|
| Repository boundary | `3bc37ffe5e09c1ef0bd412dbf81f55616899c1165d1b3a2b1dd26282a80c3482` |
| Repository tests | `cb543c80300248dfa65a582a2b7d4499ff9efa375c93f3b78434c1490f757573` |

Final scope facts:

- branch and HEAD remain `main` at
  `d16852e881ce16aeb1d4334f85d87c9e13e61219`;
- upstream remains aligned at `0 / 0`;
- no staged path or tracked modification exists;
- exactly the repository file, T-03 test file, and this evidence document are
  new;
- no existing production or test file changed;
- `git diff --check` passed;
- explicit trailing-whitespace audit passed;
- explicit repository-call-site and forbidden-dependency audits passed.

---

## Temporary Artifact Cleanup

All test/build artifacts were created below
`/private/tmp/WT033A-T03-20260731.Xf1N9H`.

After extracting privacy-safe test summaries and build exits, that exact root
was deleted. An explicit `test ! -e` absence check passed. No T-03 Derived Data,
`.xcresult`, temporary store, sidecar, attachment, or generated test/build
artifact remains in the repository or temporary root.

---

## Rollback Instructions

Before commit, rollback is deletion of only these three new files:

```text
WayTask/ProductState/Persistence/ProductStateRepositories.swift
WayTaskTests/ProductState/ProductStateRepositoryTests.swift
docs/ImplementationEvidence/1.0.3/WT-033A_T03_RepositoryBoundaries.md
```

The now-empty `WayTask/ProductState/Persistence` directory may then be removed.
No persistent-store, schema, migration, startup, data, project, package, or
localization rollback is required because T-03 changed none and the repository
tests used in-memory stores only.

---

## Terminal Decision

T-03 COMPLETE — READY FOR REVIEW
