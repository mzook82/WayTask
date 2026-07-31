# WT-033A T-04 — Command Pipeline Foundation Evidence

## Executive Summary

T-04 introduced the inactive, deterministic Product State command-description
and command-preparation foundation assigned by the approved S-02 roadmap. The
new pipeline accepts explicit commands, validates command identity, scope and
expected revision, performs exact scoped loads through the T-03 repository
boundaries, applies T-01 domain invariants, classifies the semantic result, and
stages caller-owned repository changes where T-04 can do so safely.

The pipeline has no durable-success result and no durable commit mechanism.
It does not create a `ModelContext`, save, commit, roll back, retry, activate V4,
or call UI, startup, migration, integration, Catalog, or Product Knowledge
code. No existing production caller uses it. Current behavior therefore
remains unchanged.

All required focused, directly affected, Phase 1, complete-target, Debug, and
Release gates passed. Repository and protected-file audits passed.

## Starting State and Authorization Gate

The mandatory pre-write gate was performed before any T-04 file was created.

| Check | Evidence | Result |
|---|---|---|
| Branch | `main` | Pass |
| Starting commit | `f048e47f71ea30d071c57540ff702e9ed8cf3a24` | Pass |
| Starting `git status --short` | Empty | Pass |
| `HEAD...origin/main` | `0 0` | Pass |
| T-01 commit | `d81df92e6d9cb568e7de2e5b4b51b1cdc88cb404` | Committed |
| T-02 commit | `d16852e881ce16aeb1d4334f85d87c9e13e61219` | Committed |
| T-03 commit / starting HEAD | `f048e47f71ea30d071c57540ff702e9ed8cf3a24` | Committed |
| Repository overlap | None | Pass |

Toolchain used for qualification:

- Xcode 26.6, build `17F113`;
- Apple Swift 6.3.3;
- iPhone 17 Pro simulator, iOS 26.5;
- unsigned generic iOS builds.

## Exact S-02 T-04 Authority and Footprint

S-02 section 9.2 defines T-04 as:

> Introduce command descriptions/coordinator with no production UI caller.

It assigns new components TC-03 and TC-04 and command validation tests. Its
acceptance boundary requires every S-01 command category to have semantic
outcome/conflict coverage, no direct production caller to be converted, and no
API to reach a legacy fallback. The prompt matches that boundary.

S-02 component inventory assigns these exact production homes:

- TC-03: `WayTask/ProductState/Application/ProductStateCommands.swift`;
- TC-04: `WayTask/ProductState/Application/ProductStateCommandCoordinator.swift`.

S-02 assigns durable transaction ownership, commit-once behavior, rollback,
serialization and idempotency proof to TC-05/T-05. It assigns production
Product conversion to T-10, list/entry conversion to T-11, plan consumers to
T-14, saved-location consumers to T-18, and Shopping Session/atomic Finish to
T-19. T-04 does not cross any of those boundaries.

The approved T-04 footprint is therefore exactly:

| Path | Status | Ownership |
|---|---|---|
| `WayTask/ProductState/Application/ProductStateCommands.swift` | Created | TC-03 |
| `WayTask/ProductState/Application/ProductStateCommandCoordinator.swift` | Created | TC-04 |
| `WayTaskTests/ProductState/ProductStateCommandPipelineTests.swift` | Created | T-04 tests |
| `docs/ImplementationEvidence/1.0.3/WT-033A_T04_CommandPipelineFoundation.md` | Created | T-04 evidence |

File-system synchronization discovered both production files and the test
file. `project.pbxproj` was not modified.

## Command Vocabulary

TC-03 represents all 23 S-01 categories:

- Product/Library: Create Product, Edit Product, Remove from Library, Restore;
- named list/entry: Create List, Rename List, Add, Update, Resolve, Reopen, and
  Remove from the exact named list;
- plan: Generate and Supersede;
- Session: Start, Resume, Mark Collected, Undo Collection, Prepare Finish
  Outcome, Finish, and Abandon;
- saved location: Create, Edit, and Remove.

Every command carries a stable command identity, a neutral effective time, an
explicit intent-derived scope, and an expected revision when its owning scope
requires one. Exact identities are used for Product, list, entry, plan,
Session, Session line, history event, and saved location values.

The pure shape validator reports a deterministic, lexically sorted, duplicate-
free set of codes for invalid command identity, invalid scope, absent,
unexpected, invalid or mismatched expected revision, source-revision mismatch,
invalid time/name/source/entry values, invalid resolution reason, invalid
source entries, incomplete Finish input, missing confirmation, or invalid
history-event identity.

Direct list resolution rejects `Purchased`, because only explicit successful
Finish can create purchase meaning, and rejects `Legacy Unknown`, because it is
migration-only. Mark Collected, proposed Finish outcome, and final Finish remain
distinct commands and meanings.

## Pipeline Stages

TC-04 performs these stages in order:

1. Accept one explicit `ProductStateCommand` value.
2. Run pure shape validation before any repository load.
3. Validate required expected-revision shape and ownership scope.
4. Load only the exact Product, list/entry, history, or active/expired Session
   state needed through injected T-03 repository protocols.
5. Classify missing, duplicate, protected, removed, and stale state explicitly.
6. Apply the T-01 invariant validator to Product and list-entry transitions.
7. Produce one deterministic semantic result.
8. For authorized preparation paths, ask injected repositories to stage
   caller-constructed V4 values and return an exact staged-effect description.

The implemented preparation paths cover Create/Edit/Restore Product,
Create/Rename Named List, and Add/Update/Resolve/Reopen/Remove exact list entry.
They enforce exact-list isolation, explicit restoration, stable identities,
revision match, one-revision advancement, protected-entry checks, resolution
rules, and required staged history meaning.

Remove Product from Library is described and shape-validated but returns
`unavailable(.unsupportedOperation)` until T-10 supplies its cross-list atomic
policy. Plan, Session (including Finish), and saved-location commands are also
described and shape-validated but return that same explicit unavailable result
until their approved later steps. This is deliberate semantic classification,
not a legacy fallback or implied success.

## Result Semantics

The T-04 prepared result is separate from T-01's approved durable command
result vocabulary and has exactly five states:

| Result | Meaning |
|---|---|
| `staged` | The injected caller-owned repository scope contains prepared, unsaved changes and an exact effect description. |
| `noOp` | The target authoritative state already has the requested meaning; no stage or revision/history drift occurs. |
| `conflict` | The command is stale, missing, duplicate, removed, reopen-required, or protected by an active/expired Session. |
| `validationFailure` | Shape or approved T-01 invariant validation rejected the command before durable authority changed. |
| `unavailable` | Repository state cannot be loaded or the command belongs to an approved later execution step. |

`ProductStatePreparedCommandResult.claimsDurableSuccess` is unconditionally
`false`. T-04 cannot construct or emit T-01's `.committed` result. Stable command
identity is preserved in every classification.

## Proof That No Durable Commit Occurs

- Both T-04 production files import only `Foundation`.
- The coordinator receives T-03 repositories by injection; it does not accept,
  construct, own, or expose a `ModelContext`.
- There is no `save`, commit, rollback, transaction, autosave, retry, or
  independent-context API or implementation.
- A focused test stages a Product in one context and proves a second context for
  the same container cannot observe it before an external save.
- The same test proves the staging context has changes while the returned result
  still makes no durable-success claim.
- Repeated identical commands against equivalent isolated inputs return equal
  classifications and equal staged-effect meaning.
- T-05 remains the sole roadmap step authorized to add durable transaction and
  commit behavior.

## Focused T-04 Tests

Test selector for both clean runs:

`-only-testing:WayTaskTests/ProductStateCommandPipelineTests`

| Run | Isolated DerivedData | Result bundle | Passed | Failed | Skipped |
|---|---|---|---:|---:|---:|
| Focused 1 | `/private/tmp/WT033A-T04-Focused-Run1-20260731/DerivedData` | `Focused1.xcresult` | 13 | 0 | 0 |
| Focused 2 | `/private/tmp/WT033A-T04-Focused-Run2-20260731/DerivedData` | `Focused2.xcresult` | 13 | 0 | 0 |

The 13 tests cover:

- all 23 approved command categories and stable command identity;
- deterministic, sorted, duplicate-free validation classifications;
- invalid/missing scope and expected revision;
- revision match, no-op and stale conflict;
- repository unavailability;
- exact-list isolation and no global completion authority;
- explicit restoration and Product identity preservation;
- direct-Purchased and migration-only Legacy Unknown rejection;
- Resolve/Reopen identity, revision and staged-history meaning;
- Collected/proposed outcome/Finish separation and Finish deferral;
- repeatable staged meaning with no durable-success claim;
- second-context invisibility before external save;
- no context/save/commit or forbidden framework/integration dependency.

Authoritative `xcresulttool` summaries reported `Passed`, with 13 total tests,
zero failures, zero skips, and zero expected failures for each run.

## Directly Affected Regression Tests

The exact selectors were:

- `WayTaskTests/ProductStateTransitionTests`;
- `WayTaskTests/ProductStateInvariantValidatorTests`;
- `WayTaskTests/ProductStatePersistenceGraphTests`;
- `WayTaskTests/ProductStateRepositoryTests`.

Result: **36 passed, 0 failed, 0 skipped**.

This gate covers the T-01 vocabulary/invariants, T-02 inactive graph, and T-03
repository contracts directly consumed by T-04.

## Exact Six-Suite Phase 1 Gate

The exact selectors were:

- `WayTaskTests/ProductStateSupportSelfTests`;
- `WayTaskTests/ProductStateDomainCharacterizationTests`;
- `WayTaskTests/ProductStatePersistenceCharacterizationTests`;
- `WayTaskTests/ProductStateConsumerCharacterizationTests`;
- `WayTaskTests/ProductStateDiagnosticsCharacterizationTests`;
- `WayTaskTests/ProductStatePerformanceBaselineTests`.

Result: **49 passed, 0 failed, 0 skipped**.

## Complete Regression and Build Results

| Gate | Result |
|---|---|
| Complete unfiltered `WayTaskTests` target | 389 passed, 0 failed, 0 skipped |
| Generic iOS unsigned Debug build | `BUILD SUCCEEDED` |
| Generic iOS unsigned Release build | `BUILD SUCCEEDED` |

The complete run's authoritative result bundle is `Passed`. Xcode retried one
transient simulator test-runner launch denial during parallel execution; the
completed result contained all 389 tests and no failed or skipped test.

Build commands used separate clean DerivedData roots:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WayTask.xcodeproj -scheme WayTask -configuration Debug -destination generic/platform=iOS -derivedDataPath /private/tmp/WT033A-T04-Debug-20260731 CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WayTask.xcodeproj -scheme WayTask -configuration Release -destination generic/platform=iOS -derivedDataPath /private/tmp/WT033A-T04-Release-20260731 CODE_SIGNING_ALLOWED=NO build
```

No existing test was changed to obtain a pass.

## Inactivity and Forbidden-Dependency Audit

| Audit | Result |
|---|---|
| Production references to T-04 types outside the two T-04 files | None |
| Existing UI/View/ViewModel/Service/startup/migration caller converted | None |
| Save, commit, rollback, transaction or retry implementation | None |
| Independently constructed persistence context | None |
| SwiftUI/SwiftData/platform/network/Sentry import | None; `Foundation` only |
| Catalog loader/Product Knowledge service dependency | None |
| UI, notification, Map, Camera, AI or telemetry effect | None |
| V3 compatibility read/write or legacy fallback | None |
| Current schema | `WayTaskSchemaV3` |
| V4 in migration plan | Absent; plan contains V1, V2 and V3 only |
| V4 target graph activation | Inactive test-only repository preparation |

The only migration-named value encountered by the coordinator is T-01's
approved `legacyMigration` resolution provenance when interpreting an inactive
V4 target entry for invariant validation. It is a domain provenance value, not
a startup/migration component reference, migration behavior, or compatibility
authority. Native commands cannot create Legacy Unknown or that provenance.

## Protected Hash and Repository Scope Audit

Governing and project hashes after all tests/builds:

| Protected item | SHA-256 | Result |
|---|---|---|
| WT-031B specification | `98184b50823fca859a28322b1e9ecf7e75577b14085bbefffe4a3db0f2e1be10` | Match |
| WT-033A S-01 | `2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c` | Match |
| WT-033A S-02 | `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361` | Match |
| WT-033A T-00 | `fb5f55885414c7b98c25968483182224bbba55ab27f7db17d2a895be9b59aa98` | Match |
| Dependency Re-Gate | `e95dab4801a535798fbbcfc10017cb9872c92dd1d0ca2351223f8ed2638b295c` | Match |
| `project.pbxproj` | `9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f` | Match |
| `Package.resolved` | `42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244` | Match |

T-01 through T-03 protected implementation hashes:

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

`git diff --name-only HEAD -- <all T-01/T-02/T-03/project/package paths>`
returned no path. The T-01, T-02, and T-03 evidence documents also match their
committed `HEAD` bytes. No prior source, test, evidence, project, package,
schema, migration, startup, localization, Catalog, or Product Knowledge file
changed.

T-04 implementation hashes before creation of this evidence document:

| File | SHA-256 |
|---|---|
| Command descriptions | `58e70e75cb74d5d5c43cac4074e8dd5c045805d28f0d9b5093c3f7758180c177` |
| Command coordinator | `d116fb6bda22faebd7ccc17679bf7e46ff554a4031b5648f77e5f268132f80b2` |
| Command pipeline tests | `0ca2960d15e2db0c3a26c00fd1d57bab596ffc8866159b0112364e7133501c85` |

`git diff --check` passed. Final changed scope contains only the four authorized
T-04 paths listed above.

## Temporary Artifact Cleanup

After recording the authoritative result summaries, the isolated smoke,
focused, affected, Phase 1, complete-target, Debug, and Release artifacts under
these task-owned roots were removed:

- `/private/tmp/WT033A-T04-Smoke`;
- `/private/tmp/WT033A-T04-Focused-Run1-20260731`;
- `/private/tmp/WT033A-T04-Focused-Run2-20260731`;
- `/private/tmp/WT033A-T04-Debug-20260731`;
- `/private/tmp/WT033A-T04-Release-20260731`.

No task-generated DerivedData or result bundle remains in the repository.

## Rollback Instructions

T-04 is not committed. To roll it back, remove only these four untracked files:

1. `WayTask/ProductState/Application/ProductStateCommands.swift`;
2. `WayTask/ProductState/Application/ProductStateCommandCoordinator.swift`;
3. `WayTaskTests/ProductState/ProductStateCommandPipelineTests.swift`;
4. this evidence document.

If the now-empty `WayTask/ProductState/Application/` directory remains, it may
also be removed. No tracked source, schema, migration, project, package, or
test restoration is required.

## Terminal Decision

T-04 COMPLETE — READY FOR REVIEW
