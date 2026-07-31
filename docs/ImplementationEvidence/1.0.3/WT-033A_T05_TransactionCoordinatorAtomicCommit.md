# WT-033A T-05 — Transaction Coordinator & Atomic Commit Evidence

## Executive Summary

T-05 introduced the inactive Product State transaction coordinator assigned by
the approved S-02 roadmap. It accepts the prepared result produced by T-04,
verifies that the shared SwiftData context contains exactly the declared staged
effects, validates the final command-effect receipt, performs at most one
atomic save, and maps durable success only after that save is known to have
committed.

The coordinator owns rollback and unknown-result reconciliation. A stable
command identity is attached to SwiftData persistent history before the save.
An unknown result is checked from a fresh read context against both that exact
transaction identity and the complete expected effect state; the coordinator
never retries the save. Definite failures roll back all staged Product,
Shopping, and History changes. Inconsistent or unresolvable results never claim
durable success.

Repositories remain passive and unchanged. No production caller uses the new
coordinator, V4 remains inactive, and current application behavior is
unchanged. All focused, affected, Phase 1, complete-target, Debug, and Release
qualification gates passed.

## Starting State and Authorization Gate

The mandatory gate was completed before creating any T-05 file.

| Check | Evidence | Result |
|---|---|---|
| Branch | `main` | Pass |
| Starting commit | `0d4e0a82b84b79bd871e6e83c8ed3b442ae3e80e` | Pass |
| Starting `git status --short` | Empty | Pass |
| `HEAD...origin/main` | `0 0` | Pass |
| T-01 commit | `d81df92e6d9cb568e7de2e5b4b51b1cdc88cb404` | Committed |
| T-02 commit | `d16852e881ce16aeb1d4334f85d87c9e13e61219` | Committed |
| T-03 commit | `f048e47f71ea30d071c57540ff702e9ed8cf3a24` | Committed |
| T-04 commit / starting HEAD | `0d4e0a82b84b79bd871e6e83c8ed3b442ae3e80e` | Committed |
| Repository overlap | None | Pass |

Toolchain used for qualification:

- Xcode 26.6, build `17F113`;
- Apple Swift 6.3.3;
- iPhone 17 Pro simulator, iOS 26.5;
- unsigned generic iOS Debug and Release builds.

## Exact S-02 T-05 Authority and Footprint

S-02 section 2 assigns TC-05 to
`WayTask/ProductState/Application/ProductStateTransactionCoordinator.swift`
and defines it as the owner of one local transaction scope, revision and
idempotency enforcement, commit-once behavior, and committed metadata.

S-02 section 7 requires TC-05 to serialize conflicting commands, bind all
participating repositories to one transaction context, revalidate staged
identity/revision meaning, retain stable command identity, validate final
invariants, commit once, roll back the complete mutation on failure, and keep
external effects outside the transaction. S-02 section 9.2 assigns T-05 the
proof of serialization, rollback, idempotency, deterministic stale/save/unknown
handling, no partial save, and supported-iOS behavior with no target production
writer. The execution prompt matches this boundary exactly.

The approved footprint is therefore:

| Path | Status | Ownership |
|---|---|---|
| `WayTask/ProductState/Application/ProductStateTransactionCoordinator.swift` | Created | TC-05 |
| `WayTaskTests/ProductState/ProductStateTransactionCoordinatorTests.swift` | Created | T-05 repository integration tests |
| `docs/ImplementationEvidence/1.0.3/WT-033A_T05_TransactionCoordinatorAtomicCommit.md` | Created | T-05 evidence |

File-system synchronization discovered the new source and test files. No
project-file edit was required.

## Transaction Contract

### Input and Ownership

The coordinator accepts only `ProductStatePreparedCommandResult`, preserving
the T-04 distinction among staged success, no-op, conflict, validation failure,
and unavailable. It does not implement command policy, command preparation,
queries, startup, migration, or external effects.

All mutations must already be staged through the T-03 repositories against the
same caller-supplied `ModelContext`. The production transaction scope disables
autosave, inventories the actual inserted, changed, and deleted V4 models, and
requires an exact match with the declared effects. An unknown model, unrelated
staged change, duplicate effect, conflicting revision effect, duplicate history
identity, missing staged change, or final semantic mismatch rejects the entire
prepared result before save.

### Atomic Commit

The commit path is:

1. build a deterministic receipt from the declared staged effects;
2. reject duplicate effects, more than one revision meaning for an owned
   scope, invalid revision movement, or duplicate history identities;
3. run the T-01 invariant validator against the proposed committed receipt;
4. reconcile stable command identity before a new save;
5. require an exact staged-model inventory and final effect-state match;
6. set the context author to the stable command UUID;
7. invoke the sole `modelContext.save()` call;
8. return committed identity, revision, and history metadata only after the
   save succeeds.

One SwiftData save spans every participating repository because every staged
model belongs to the same coordinator-supplied context. Repositories have no
save, commit, rollback, or transaction implementation. There is no early save,
second save, retry loop, compensation, partial-success result, or external
effect inside the transaction.

### Rollback and Unknown Results

- Prepared conflict, validation failure, or unavailable state rolls back any
  accidental staging and preserves the semantic result.
- A no-op succeeds without a save only when the scope has no staged changes;
  otherwise it rolls back and returns unavailable.
- A definite save failure calls `rollback()` and returns a non-durable
  unavailable result.
- An unknown save result first rolls back the local context, then uses a fresh
  read-only context to fetch persistent history for the exact command author
  and to evaluate every declared effect.
- Exactly one matching transaction plus all effects committed maps to
  `reconciledCommitted` without another save.
- No transaction plus every effect still at its pre-commit state maps to a
  rolled-back unavailable result.
- Partial, duplicate, contradictory, or unreadable reconciliation maps to
  `outcomeUnknown` and never claims durable success.

Repeating an already committed prepared command is therefore reconciled by its
stable command identity and exact effect state. The duplicate local stage is
rolled back; no second revision, history event, or transaction is written.

### Durable Result Mapping

| Prepared or persistence condition | Durable mapping | Save count | Durable-success claim |
|---|---|---:|---|
| Valid staged result; save succeeds | `committed` | 1 | Yes |
| Same command already committed | `reconciledCommitted` | 0 | Yes |
| Clean no-op | `noCommitRequired` | 0 | No |
| Conflict / validation / unavailable | semantic rejection plus rollback | 0 | No |
| Definite save failure | `rolledBack(.saveFailed)` | 1 attempted | No |
| Unknown, proven not committed | `rolledBack(.saveFailed)` | 1 attempted | No |
| Unknown, inconsistent or unreadable | `outcomeUnknown` | 1 attempted | No |

Only T-05 constructs the T-01 `.committed` result, and only the committed or
reconciled-committed dispositions make `claimsDurableSuccess` true.

## Serialization and Supported-iOS Proof

The coordinator and transaction scope are synchronously `@MainActor` isolated.
This conservatively serializes every target command commit and therefore every
conflicting command for the same owned scope; there is no actor suspension
inside the commit path.

The project deployment target is iOS 26.5. The local iOS 26.5 SDK declares
`ModelContext.author`, persistent-history descriptors, and
`ModelContext.fetchHistory` available from iOS 18. The save, rollback, change
inventory, and autosave APIs are also available throughout the supported
deployment range. Focused simulator execution plus clean generic Debug and
Release compilation prove the selected mechanism on the project's only
supported iOS target, satisfying S-02's D-37 gate.

## Focused T-05 Tests

The selector for both clean runs was:

`-only-testing:WayTaskTests/ProductStateTransactionCoordinatorTests`

| Run | Isolated DerivedData | Result bundle | Passed | Failed | Skipped |
|---|---|---|---:|---:|---:|
| Focused 1 | `/private/tmp/WT033A-T05-Focused-Run1-20260731/DerivedData` | `Focused1.xcresult` | 12 | 0 | 0 |
| Focused 2 | `/private/tmp/WT033A-T05-Focused-Run2-20260731/DerivedData` | `Focused2.xcresult` | 12 | 0 | 0 |

The 12 focused tests cover:

- exactly one save and one persistent-history transaction;
- atomic Shopping revision, entry resolution, and History insertion;
- definite failure rollback with no partial revision, entry, history, or
  transaction visibility;
- unknown-before-save, unknown-after-save, and inconsistent-unknown mapping;
- stable command retry reconciliation without a second commit or revision;
- duplicate history identity rejection;
- duplicate/conflicting revision and history effect rejection;
- unrelated staged-model rejection;
- stale conflict and clean no-op behavior without save;
- deterministic durable-result claims and rollback counts;
- `MainActor` serialization, one save site, passive repositories, supported
  deployment target, no production caller, and no forbidden dependency.

Both authoritative `xcresulttool` summaries reported `Passed`, 12 total tests,
zero failures, zero skips, and zero expected failures.

## Affected Regression Tests

The affected gate used these exact selectors:

- `WayTaskTests/ProductStateTransitionTests`;
- `WayTaskTests/ProductStateInvariantValidatorTests`;
- `WayTaskTests/ProductStatePersistenceGraphTests`;
- `WayTaskTests/ProductStateRepositoryTests`;
- `WayTaskTests/ProductStateCommandPipelineTests`;
- `WayTaskTests/StartupPersistenceResilienceTests`;
- `WayTaskTests/StartupRepairIdempotencyTests`;
- `WayTaskTests/WayTaskSchemaMigrationTests`.

Result: **64 passed, 0 failed, 0 skipped**.

No existing test or fixture was modified to obtain a pass.

## Persistence Characterization and Phase 1 Gates

S-02 requires persistence characterization twice. The first standalone run of
`WayTaskTests/ProductStatePersistenceCharacterizationTests` passed **15/15**.
The second run was the same 15-test suite inside the authoritative exact
six-suite Phase 1 gate.

The exact authoritative Phase 1 selectors were:

- `WayTaskTests/ProductStateCharacterizationSupportSelfTests`;
- `WayTaskTests/ProductStateDomainCharacterizationTests`;
- `WayTaskTests/ProductStatePersistenceCharacterizationTests`;
- `WayTaskTests/ProductStateConsumerCharacterizationTests`;
- `WayTaskTests/ProductStateDiagnosticsCharacterizationTests`;
- `WayTaskTests/ProductStatePerformanceBaselineTests`.

Result: **49 passed, 0 failed, 0 skipped**.

An initial T-05 invocation used the stale short selector
`ProductStateSupportSelfTests`. Xcode ignored that nonexistent class and
produced a 45-test bundle containing only five suites. Detailed result
inspection detected the omission. That bundle was rejected and is not counted;
the corrected 49-test bundle above contains all six suites and is the sole
authoritative Phase 1 result.

## Complete Regression and Build Results

| Gate | Result |
|---|---|
| Complete unfiltered `WayTaskTests` target | 401 passed, 0 failed, 0 skipped |
| Generic iOS unsigned Debug build | `BUILD SUCCEEDED` |
| Generic iOS unsigned Release build | `BUILD SUCCEEDED` |

The complete target ran sequentially with test parallelism disabled and its
authoritative result bundle reported `Passed`, 401 total tests, zero failures,
zero skips, and zero expected failures. Expected Core Data errors emitted by
the malformed-store characterization fixture were followed by a passing
`testFailedWorkingCopyOpenDoesNotMutateSourceFixture` result.

The build commands used separate clean DerivedData roots:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WayTask.xcodeproj -scheme WayTask -configuration Debug -destination generic/platform=iOS -clonedSourcePackagesDirPath /private/tmp/WT033A-T05-Smoke/SourcePackages -derivedDataPath /private/tmp/WT033A-T05-Debug-20260731 CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WayTask.xcodeproj -scheme WayTask -configuration Release -destination generic/platform=iOS -clonedSourcePackagesDirPath /private/tmp/WT033A-T05-Smoke/SourcePackages -derivedDataPath /private/tmp/WT033A-T05-Release-20260731 CODE_SIGNING_ALLOWED=NO build
```

## Inactivity, Ownership, and Forbidden-Dependency Audit

| Audit | Result |
|---|---|
| Production references to T-05 types outside the T-05 source file | None |
| Existing production caller converted | None |
| Coordinator save sites | Exactly one `modelContext.save()` |
| Repository save/commit/rollback ownership | None; T-03 file unchanged |
| Coordinator transaction mutation contexts | One caller-supplied context; no independent mutation context |
| Fresh context use | Read-only command/effect reconciliation only |
| Autosave | Disabled on the coordinator context |
| Retry or second-save behavior | None |
| UI/View/ViewModel/Service/startup/migration reference | None |
| Map/Camera/Notifications/AI/Catalog/Product Knowledge/telemetry effect | None |
| Production imports | `Foundation`, `SwiftData` only |
| V3 current schema | Unchanged and live |
| V4 migration-plan membership | Absent; plan still contains V1, V2, V3 only |
| V4 production activation | None |
| Project/package/localization changes | None |

The transaction scope recognizes the inactive V4 migration-exception model
only so an unrelated staged instance can be rejected by the exact change
inventory. It performs no migration behavior and does not modify migration or
startup code.

## Protected Hash and Repository Scope Audit

Governing and project hashes after all tests and builds:

| Protected item | SHA-256 | Result |
|---|---|---|
| WT-031B specification | `98184b50823fca859a28322b1e9ecf7e75577b14085bbefffe4a3db0f2e1be10` | Match |
| WT-033A S-01 | `2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c` | Match |
| WT-033A S-02 | `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361` | Match |
| WT-033A T-00 | `fb5f55885414c7b98c25968483182224bbba55ab27f7db17d2a895be9b59aa98` | Match |
| Dependency Re-Gate | `e95dab4801a535798fbbcfc10017cb9872c92dd1d0ca2351223f8ed2638b295c` | Match |
| `project.pbxproj` | `9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f` | Match |
| `Package.resolved` | `42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244` | Match |

T-01 through T-04 protected implementation hashes:

| Protected path | SHA-256 | Result |
|---|---|---|
| T-01 domain vocabulary | `4fb347ce5d8f780351e6f0fe7e1aad158279cbddc02e87eed8f10836c71c6ce8` | Match |
| T-01 invariant validator | `4eda9aba6f76b75576426c67786e3245e10beaefce481944df24f6e49b4a25f4` | Match |
| T-01 transition tests | `ba53a7f302a7e036aa110adcd285d3873464eb696b128b389c03e0ba55e9f6c8` | Match |
| T-01 invariant tests | `f50b324283a66322e9d5bb00e73de3c762777660474577eed37eeb75862bbf56` | Match |
| T-02 `Models.swift` | `74062d07cd3b1546ec11ad8a550223ff4b33b646715c0aa61a8f57e38b2a345c` | Match |
| T-02 `ProductHistory.swift` | `57dd2b13e4e68d2292e5b45f5fe090f3b64344fe4c777a91f19cc47961e8da8c` | Match |
| T-02 `ShoppingSession.swift` | `61310856a980c965fdbad9993f74054c6713071995f38a26384b75607e594383` | Match |
| T-02 schema composition | `68ffde0c4ed52051278311eb75d550545390c3ce943903a9d531011d0a8f4391` | Match |
| T-02 graph tests | `236759039eb8bb92923e48735b844259436c2d5ea79e632b010e60378395662f` | Match |
| T-03 repository boundary | `3bc37ffe5e09c1ef0bd412dbf81f55616899c1165d1b3a2b1dd26282a80c3482` | Match |
| T-03 repository tests | `cb543c80300248dfa65a582a2b7d4499ff9efa375c93f3b78434c1490f757573` | Match |
| T-04 command descriptions | `58e70e75cb74d5d5c43cac4074e8dd5c045805d28f0d9b5093c3f7758180c177` | Match |
| T-04 command coordinator | `d116fb6bda22faebd7ccc17679bf7e46ff554a4031b5648f77e5f268132f80b2` | Match |
| T-04 command pipeline tests | `0ca2960d15e2db0c3a26c00fd1d57bab596ffc8866159b0112364e7133501c85` | Match |

The committed T-01, T-02, T-03, and T-04 evidence documents also remain
unchanged, with respective hashes
`d9f62bb63a5510633425d4bf055f2e911b4011f76ccd2eb36f421d550291410b`,
`f39525267de1902c07a3d2c3f44ae26483b220ca5646789638981a589ef01dc3`,
`c2338f096f9132351095e484cc17feb495a8c9c62e7444f81b551e79509a9bb5`,
and `86ecf19cf81b32913ca3dcfc5d90b5384150dcd5a214b3021c745ea20746ede2`.

T-05 implementation hashes before creation of this evidence document:

| File | SHA-256 |
|---|---|
| Transaction coordinator | `3ae8e4aadd9e427de50cdca0d20fe7037a5cdb546043d63f9dcd9f3c9d3d264a` |
| Transaction coordinator tests | `175b692c6a2dcff3793d77fadb462070b0a218ea1e9f72627b3ec43831d4a9da` |

`git diff --exit-code HEAD -- <all protected T-01–T-04, project, and package
paths>` returned no difference. Source import, production-caller, repository
ownership, forbidden-reference, and trailing-whitespace audits returned no
unexpected match. Final repository scope contains only the three authorized
T-05 paths.

## Temporary Artifact Cleanup

After recording all authoritative result summaries, the task-owned smoke,
focused, affected, persistence, Phase 1, complete-target, Debug, and Release
artifacts under these roots were removed:

- `/private/tmp/WT033A-T05-Smoke`;
- `/private/tmp/WT033A-T05-Focused-Run1-20260731`;
- `/private/tmp/WT033A-T05-Focused-Run2-20260731`;
- `/private/tmp/WT033A-T05-Debug-20260731`;
- `/private/tmp/WT033A-T05-Release-20260731`.

No T-05 DerivedData or result bundle remains in the repository.

## Rollback Instructions

T-05 is not committed. To roll it back, remove only these three untracked
files:

1. `WayTask/ProductState/Application/ProductStateTransactionCoordinator.swift`;
2. `WayTaskTests/ProductState/ProductStateTransactionCoordinatorTests.swift`;
3. this evidence document.

No tracked source, test, schema, migration, project, package, localization, or
prior evidence restoration is required.

## Terminal Decision

T-05 COMPLETE — READY FOR REVIEW
