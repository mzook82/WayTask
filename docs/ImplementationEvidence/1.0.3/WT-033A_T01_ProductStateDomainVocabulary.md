# WT-033A T-01 — Product State Domain Vocabulary Evidence

**Product:** WayTask iOS
**Version:** 1.0.3
**Execution step:** T-01 only
**Evidence date:** 2026-07-31
**Implementation status:** Complete; awaiting review
**Later-step authorization:** None

---

## Executive Summary

T-01 added the pure, platform-neutral Product State and Shopping Session
vocabulary and a deterministic invariant validator authorized by WT-033A S-01,
S-02, and the approved WT-031B contract. It also added two T-01-owned XCTest
suites. The new files are discovered by the existing synchronized source and
test roots; `project.pbxproj` remains unchanged.

No existing application caller uses the new vocabulary. No persistence,
repository, transaction, schema, migration, UI, infrastructure, Catalog,
Product Knowledge, package, localization, or project behavior changed. T-02
and later steps were not started.

Final qualification passed:

- both isolated focused runs: 22 of 22 tests;
- five frozen Phase 1 Product State suites plus support self-tests: 49 of 49;
- complete unfiltered `WayTaskTests` target: 362 of 362;
- generic unsigned Debug and Release builds: exit 0.

The terminal decision is **T-01 COMPLETE — READY FOR REVIEW**.

---

## Starting Repository State

The repository was inspected before the first T-01 write.

| Field | Starting value |
|---|---|
| Branch | `main` |
| Upstream | `origin/main` |
| Ahead / behind | `0 / 0` |
| Full commit SHA | `d32e6d33474adf948f70f97085ddc611a71b6f5c` |
| Staged paths | 0 |
| Tracked modified paths | 0 |
| Untracked paths | 0 |
| T-01 production paths | Absent |
| T-01 test paths | Absent |

There was no overlapping work at the authorized paths. The approved WT-031B
specification and Dependency Re-Gate were already present in the clean HEAD.

---

## Authorized and Created Files

### Production

| File | Purpose |
|---|---|
| `WayTask/ProductState/Domain/ProductStateDomain.swift` | Pure identities, lifecycle values, snapshots, outcomes, history meanings, revisions, commands, and semantic results |
| `WayTask/ProductState/Domain/ProductStateInvariantValidator.swift` | Pure audit inputs, transition descriptions, invariant codes, and deterministic validation |

### Tests

| File | Tests | Purpose |
|---|---:|---|
| `WayTaskTests/ProductState/ProductStateTransitionTests.swift` | 10 | Vocabulary completeness and allowed transition semantics |
| `WayTaskTests/ProductState/ProductStateInvariantValidatorTests.swift` | 12 | Forbidden transitions, invariant categories, determinism, and code uniqueness |

### Evidence

| File | Purpose |
|---|---|
| `docs/ImplementationEvidence/1.0.3/WT-033A_T01_ProductStateDomainVocabulary.md` | This T-01 execution record |

These five files are the complete repository change set. No existing file was
edited.

---

## Domain Concepts Implemented

### Product and Product Library

- `ProductStateProductID` is the stable user Product identity.
- `ProductStateCatalogID` is an optional reference and cannot substitute for
  Product identity.
- `ProductLibraryLifecycle` contains only `active` and `removed`.
- `ProductLibraryAction` distinguishes removal from explicit restoration.
- Product snapshots contain no list, shopping, completion, purchase, plan, or
  Session state.

### Shopping Lists and Entries

- `ProductStateListID` is stable and `ProductStateListRevision` is durable and
  monotonic in meaning.
- `ProductStateListEntryIdentity` binds a stable entry ID to one exact list and
  Product.
- Entry lifecycle contains `needed` and `resolved` only; absence of an entry is
  the membership authority.
- Resolution reasons are Purchased, Already Have, No Longer Needed, and
  migration-only Legacy Unknown.
- Resolution values carry effective time and explicit user, Session Finish, or
  legacy-migration provenance.
- Reopen is a distinct action and retains the entry identity.

### Shopping Plans

- A plan has stable identity, one source list, one exact source revision, exact
  included entry identities, and explicit exclusions.
- Status covers Idle, Generating, Ready, Failed, and Stale.
- Failure and staleness carry neutral domain reason values.

### Shopping Sessions

- Lifecycle is exactly Active, Expired, Finished, or Abandoned.
- Finished and Abandoned are terminal; Expired remains resumable.
- Recovery open is represented as a no-state-change action, not a Recovered
  lifecycle state.
- Execution state is Remaining or Collected and remains separate from final
  outcome.
- Native final outcomes are exactly Purchased, Already Have, No Longer Needed,
  Unavailable, Skipped, and Carried Forward.
- Legacy Unknown exists only as a migration disposition; the final-outcome type
  cannot represent it.
- Stable Session, snapshot, stop, and line identities are distinct.
- A Session carries one source-list identity, exact-or-legacy source revision,
  Session revision, migration condition, stop identities, and frozen line
  snapshots.
- Migration conditions are Native, Legacy Mapped, Legacy Incomplete, and
  Legacy Unresolved.

### History

- History events have stable event and Product identities.
- Event meanings distinguish need, membership, Library, and Session outcome
  facts.
- Events carry user-command, successful-Session-Finish, or legacy-migration
  provenance and a deterministic effective time supplied at the boundary.
- Purchase and normal Session-outcome provenance are restricted to successful
  explicit Finish.

### Commands and Revisions

- Commands have stable identity.
- Expected revisions and revision scope/value concepts are explicit.
- Command effects describe revision changes and immutable history-event IDs.
- Semantic results distinguish Committed, No-op, Conflict, Validation Failure,
  and Unavailable.
- No repository, transaction-coordinator, persistence, or framework API was
  designed by T-01.

---

## Invariant Inventory

The validator emits 40 unique `ProductStateInvariantCode` values. It collects
codes in a set and returns them sorted by raw value, so a violation code appears
at most once and ordering is deterministic.

| Category | Invariant codes and meaning |
|---|---|
| Authority boundary | `missingAuthorityForLifecycle`, `multipleAuthoritiesForLifecycle`, `externalAuthorityClaim`, `compatibilityAuthorityClaim` |
| Product identity and Library | `productIdentityChanged`, `catalogIdentitySubstitutedForProduct`, `globalProductShoppingState`, `implicitProductRestore`, `invalidProductLibraryTransition` |
| List membership and resolution | `duplicateCurrentListEntry`, `entryMembershipWithoutEntry`, `entryListScopeMismatch`, `crossListMutation`, `reopenChangedEntryIdentity`, `invalidEntryTransition`, `legacyUnknownOutsideMigration`, `purchasedResolutionWithoutFinish` |
| Session authority and snapshot | `multipleNativeNonTerminalSessions`, `nativeSessionMissingStop`, `duplicateSessionLineIdentity`, `invalidSessionLineSnapshot`, `invalidSessionTransition`, `invalidSessionRevision`, `immutableSessionSnapshotChanged` |
| Execution and terminal meaning | `collectedTreatedAsPurchased`, `provisionalExecutionHasFinalEffects`, `finishedSessionMissingFinalOutcome`, `nonFinishedSessionHasFinalOutcome`, `nativeSessionHasLegacyDisposition`, `abandonedSessionHasListResolutionMeaning`, `abandonedSessionHasPurchaseHistoryMeaning` |
| Immutable history | `duplicateHistoryEventIdentity`, `historyEventMutated`, `purchaseHistoryWithoutFinish`, `sessionOutcomeHistoryWithoutFinish` |
| Idempotent commands | `noOpCommandHasEffects`, `invalidCommittedRevisionChange`, `duplicateRevisionEffect`, `commandRetryChangedResult`, `duplicateHistoryEffect` |

Together these express the required categories:

1. exactly one authority per lifecycle;
2. stable Product identity and non-substitutable Catalog identity;
3. no global Product shopping/completion state;
4. explicit Product restoration only;
5. one current entry per exact list/Product pair and entry-owned membership;
6. list isolation and identity-preserving Reopen;
7. Collected is provisional and never Purchased or a final side effect;
8. one valid outcome per native Finished line;
9. Legacy Unknown and compatibility values have no native target authority;
10. Abandon creates no list-resolution or Product History meaning;
11. native Session snapshot meaning is immutable;
12. retries/no-ops cannot duplicate revisions or history effects;
13. History is immutable and purchase requires successful Finish provenance;
14. presentation and integrations own no domain lifecycle.

The validator has no clock, random source, global state, I/O, repository,
framework callback, or external service. All times and identities are supplied
as values, making validation pure and repeatable.

---

## Test Environment

| Component | Value |
|---|---|
| Xcode | 26.6, build 17F113 |
| Simulator | iPhone 17 Pro, iOS 26.5, build 23F77 |
| Simulator UDID | `DE30E799-0496-4818-851D-FF613F62FCD3` |
| Simulator architecture | `arm64` |
| Test configuration | Debug, serial (`-parallel-testing-enabled NO`) |
| Code signing | Disabled |
| Result environment | WayTask built with macOS 26.6 |

All authoritative qualification artifacts were created below the isolated root
`/private/tmp/WT033A-T01-FINAL-20260731.erpoNc`. The two focused runs used
different DerivedData directories. The Phase 1 and complete-target commands
used a regression-only DerivedData directory and separate result bundles.

---

## Focused T-01 Tests

### Exact selectors

Both final focused runs used:

```text
-only-testing:WayTaskTests/ProductStateTransitionTests
-only-testing:WayTaskTests/ProductStateInvariantValidatorTests
```

The exact command shape for run 1 was:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet test \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=DE30E799-0496-4818-851D-FF613F62FCD3' \
  -derivedDataPath /private/tmp/WT033A-T01-FINAL-20260731.erpoNc/DerivedData-Focused-1 \
  -resultBundlePath /private/tmp/WT033A-T01-FINAL-20260731.erpoNc/Focused-1.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:WayTaskTests/ProductStateTransitionTests \
  -only-testing:WayTaskTests/ProductStateInvariantValidatorTests \
  CODE_SIGNING_ALLOWED=NO
```

Run 2 was identical except that `DerivedData-Focused-2` and
`Focused-2.xcresult` were used. Therefore each run began from a separate clean,
isolated build state.

### Results

| Suite | Tests per run |
|---|---:|
| `ProductStateTransitionTests` | 10 |
| `ProductStateInvariantValidatorTests` | 12 |
| **Total** | **22** |

| Run | Passed | Failed | Skipped | Expected failures | Result |
|---|---:|---:|---:|---:|---|
| Focused 1 | 22 | 0 | 0 | 0 | Passed |
| Focused 2 | 22 | 0 | 0 | 0 | Passed |

Coverage includes every vocabulary case, allowed and forbidden transitions,
migration-only restrictions, Remaining/Collected versus final outcomes,
Finished/Abandoned/Expired semantics, list isolation, Product restoration,
identity stability, snapshot meaning, history provenance, revision/history
idempotency, deterministic failures, and invariant-code uniqueness.

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

The command used a separate `Phase1.xcresult`, the approved simulator, Debug
configuration, serial execution, and `CODE_SIGNING_ALLOWED=NO`.

| Required suite | Passed | Failed | Skipped |
|---|---:|---:|---:|
| `ProductStateCharacterizationSupportSelfTests` | 4 | 0 | 0 |
| `ProductStateDomainCharacterizationTests` | 12 | 0 | 0 |
| `ProductStatePersistenceCharacterizationTests` | 15 | 0 | 0 |
| `ProductStateConsumerCharacterizationTests` | 6 | 0 | 0 |
| `ProductStateDiagnosticsCharacterizationTests` | 5 | 0 | 0 |
| `ProductStatePerformanceBaselineTests` | 7 | 0 | 0 |
| **Product State subtotal** | **49** | **0** | **0** |

The privacy-safe result summary reported `Passed`, 49 total tests, zero skips,
and zero expected failures. XCTest execution elapsed 1,197.579 seconds.

### Complete target

The complete command was unfiltered: it contained no `-only-testing`,
`-skip-testing`, or test-plan exclusion.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet test \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=DE30E799-0496-4818-851D-FF613F62FCD3' \
  -derivedDataPath /private/tmp/WT033A-T01-FINAL-20260731.erpoNc/DerivedData-Regression \
  -resultBundlePath /private/tmp/WT033A-T01-FINAL-20260731.erpoNc/AllTests.xcresult \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
```

| Scope | Passed | Failed | Skipped | Expected failures | Result |
|---|---:|---:|---:|---:|---|
| Complete `WayTaskTests` target | 362 | 0 | 0 | 0 | Passed |

The result is the 340-test T-00 baseline plus the 22 T-01 tests. XCTest
execution elapsed 1,236.266 seconds. Six unchanged tests collected performance
metrics.

The only emitted compile diagnostics were the already documented unused
test-local `legacyByID` warning in
`WayTaskTests/ProductCatalog/ProductCatalogMigrationTests.swift:136` and the
existing Sentry debug-symbol build-phase dependency-analysis note. No file was
changed in response.

---

## Generic Unsigned Builds

Debug:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Debug \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/WT033A-T01-FINAL-20260731.erpoNc/DerivedData-Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Release used the same command with `Release` and `DerivedData-Release`.

| Build | Exit | Result |
|---|---:|---|
| Generic unsigned Debug | 0 | Passed |
| Generic unsigned Release | 0 | Passed |

Successful generic builds prove automatic production-file discovery. Focused
test discovery proves automatic test-file discovery. No project membership
change was required.

---

## Framework and Import Audit

| File | Imports |
|---|---|
| `ProductStateDomain.swift` | `Foundation` only |
| `ProductStateInvariantValidator.swift` | None |

Foundation is used only for neutral `UUID` and `Date` values. A case-insensitive
source audit found no SwiftUI, SwiftData, CoreLocation, MapKit,
UserNotifications, AVFoundation, Network/URLSession, Sentry, Product Catalog,
Product Knowledge, repository, transaction-coordinator, `ModelContext`,
`@Model`, or presentation `View` dependency in either production file.

The production files contain value types and deterministic functions only.
They perform no persistence, schema, migration, UI, package, localization,
network, notification, location, Camera, AI, Catalog, or Product Knowledge
work.

---

## Protected Hash and Repository Scope Audit

All individual protected hashes recorded by T-00 and the Dependency Re-Gate
were recomputed after final builds. Governing inputs, frozen production and
persistence sources, the project and resolved package, the Phase 1 fixture,
support, and five characterization suites all match their approved values. The
T-00 and Re-Gate evidence files additionally match their bytes in the clean
starting HEAD.

Important identities include:

| Protected item | Current SHA-256 | Result |
|---|---|---|
| WT-031B implementation specification | `98184b50823fca859a28322b1e9ecf7e75577b14085bbefffe4a3db0f2e1be10` | Match |
| WT-033A S-01 | `2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c` | Match |
| WT-033A S-02 | `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361` | Match |
| WT-033A T-00 | `fb5f55885414c7b98c25968483182224bbba55ab27f7db17d2a895be9b59aa98` | Match |
| WT-033A Dependency Re-Gate | `e95dab4801a535798fbbcfc10017cb9872c92dd1d0ca2351223f8ed2638b295c` | Match |
| `WayTask.xcodeproj/project.pbxproj` | `9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f` | Match |
| `Package.resolved` | `42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244` | Match |

The T-00 `WayTaskStartupPersistence.swift` ledger transcription remains the
known 63-character defect documented by the Dependency Re-Gate. Its valid
current SHA-256 is
`9eaf9dd7f95e96249d117a414084cdbdbb564bfb413a247f036bde29b55a7bd7`,
which matches the byte-stable re-gate value.

Protected tracked-baseline aggregates also match:

| Aggregate | Files | SHA-256 | Result |
|---|---:|---|---|
| Tracked T-00 `WayTaskTests/**` baseline | 41 | `920957649d9b1bfa0e5dd67a3529ab3a9483e8696dee1aee20b3c00457cc4316` | Match |
| Product Catalog/Product Knowledge source and tests | 43 | `a2c919c3ba6658e914c15513eefc7c25978c328bccacaebc8bd390e2b88cbb03` | Match |
| Xcode project including resolved package | 5 | `457f704643e8b6aaf12279cc0a549913bce87797d21267b04fb27ab1848e15d2` | Match |

The protected test aggregate intentionally uses the tracked T-00 path set; the
two new authorized untracked T-01 test files are listed separately in this
evidence.

Final scope facts:

- branch and HEAD remain `main` at
  `d32e6d33474adf948f70f97085ddc611a71b6f5c`;
- upstream remains aligned at `0 / 0`;
- staged and tracked modified path counts remain zero;
- exactly two authorized production files, two authorized test files, and this
  evidence document are untracked;
- no existing source, test, fixture, schema, migration, project, package,
  localization, Catalog, Product Knowledge, or prior document changed;
- `git diff --check` and the explicit whitespace audit are clean.

---

## Qualification Notes

1. The first pre-qualification focused compile exposed a test-only local name
   shadowing a deterministic ID helper. It executed no tests and was corrected
   only in the authorized new validator test file. All final qualification was
   then run from a new isolated root after the validator contract audit.
2. Initial sandboxed CoreSimulator discovery and result-summary extraction were
   denied by host service/cache permissions. The same read-only discovery and
   summary operations succeeded with approved Xcode/CoreSimulator access.
3. The contract audit made missing lifecycle authority, duplicate revision
   scope effects, and provisional execution side effects explicit before final
   qualification. The full final matrix above was rerun after those changes.

These notes did not require or produce any protected-file modification.

---

## Temporary Artifact Cleanup

The pre-qualification root
`/private/tmp/WT033A-T01-20260731.1S5O7G` and the final qualification root
`/private/tmp/WT033A-T01-FINAL-20260731.erpoNc` were deleted after extracting
privacy-safe summaries. Explicit absence checks passed for both paths.

No DerivedData, `.xcresult`, temporary store, sidecar, attachment, or generated
test/build artifact remains in the repository or either T-01 temporary root.

---

## Rollback Instructions

Before commit, rollback is deletion of only these five untracked files:

```text
WayTask/ProductState/Domain/ProductStateDomain.swift
WayTask/ProductState/Domain/ProductStateInvariantValidator.swift
WayTaskTests/ProductState/ProductStateTransitionTests.swift
WayTaskTests/ProductState/ProductStateInvariantValidatorTests.swift
docs/ImplementationEvidence/1.0.3/WT-033A_T01_ProductStateDomainVocabulary.md
```

The now-empty `WayTask/ProductState/Domain` and `WayTask/ProductState`
directories may then be removed. No schema, migration, project, package, or
persistent-store rollback is required because T-01 changed none.

---

## Terminal Decision

T-01 COMPLETE — READY FOR REVIEW
