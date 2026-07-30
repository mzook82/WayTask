# WT-033A T-00 Product State Implementation Baseline

## Record status

This document records WT-033A execution step T-00 only. T-00 performed
repository inspection, dependency review, baseline execution, protected-hash
verification, and temporary-artifact cleanup. It did not authorize or perform
T-01, production implementation, test changes, schema or migration changes,
project or package changes, Catalog or Product Knowledge changes, localization
changes, or commits.

Evidence was collected on 2026-07-30. Repository facts are labeled **verified**.
Architectural conclusions derived by comparing approved documents are labeled
**gate interpretation**. Passing characterization tests preserve current
behavior evidence; they do not approve known defects or claim that target
Product State authority exists.

## Repository baseline

### Branch, commit, and starting status

| Field | Verified value |
|---|---|
| Branch | `main` |
| Upstream | `origin/main` |
| Ahead / behind | `0 / 0` |
| Full commit SHA | `a20b83c570157038cb85b0b3efb49a24cf8ccc50` |
| Staged paths | 0 |
| Tracked modified paths | 0 |
| Untracked paths | 4 |
| Evidence collection interval | 2026-07-30T20:16:42Z through 2026-07-30T20:53:49Z |

The exact starting `git status --short --untracked-files=all` was:

```text
?? docs/Milestones/WayTask_Phase1_Completion.md
?? docs/Specifications/WT-033A_ProductStateAuthorityDiscovery.md
?? docs/Specifications/WT-033A_ProductStateAuthoritySpecification.md
?? docs/Specifications/WT-033A_ProductStateTechnicalImplementation.md
```

These four paths pre-existed T-00. They were read where governing input was
required and were otherwise left byte-for-byte untouched. No uncommitted path
existed under `WayTask/`, `WayTaskTests/`, `WayTask.xcodeproj/`, package paths,
Catalog, Product Knowledge, localization, schema, or migration paths.

The three WT-033A S-00 through S-02 documents are approved inputs supplied in
the working tree but are not tracked by the current commit. Their exact hashes
are protected below. This status is disclosed rather than represented as a
committed Git baseline.

### Exact allowed-change boundary

The only repository path authorized for T-00 is:

```text
docs/ImplementationEvidence/1.0.3/WT-033A_T00_ProductStateImplementationBaseline.md
```

At completion, the repository differs from the starting status only by this
new evidence document. There are no staged or tracked modifications. Removal
of this one document independently restores the exact starting repository
status.

### Future T-01 overlap check

S-02 identifies T-01 production responsibilities TC-01 and TC-02 at these
proposed paths:

```text
WayTask/ProductState/Domain/ProductStateDomain.swift
WayTask/ProductState/Domain/ProductStateInvariantValidator.swift
```

Both paths are absent. `git status` limited to `WayTask/ProductState` and
`WayTaskTests/ProductState` was empty. Existing tracked Phase 1 Product State
fixture, support, and characterization files are protected baseline artifacts,
not overlapping user changes. No T-01 implementation or target test file was
created.

## Protected-hash baseline

Hashes use SHA-256 over exact file bytes after test/build cleanup.

### Governing architecture, plans, decisions, and specifications

| Protected file | SHA-256 |
|---|---|
| `docs/Audits/1.0.3/WT-030_ArchitectureSummary.md` | `21aa18de727ad392dbd3f6b3845c283d45522df2c21022c554dd3a502979e586` |
| `docs/Audits/1.0.3/WT-030A_ProductStateUXAudit.md` | `752695899449581256e8826b1318b9aa63b7d361a8a4b1bc2de2af0afb8cf032` |
| `docs/Audits/1.0.3/WT-030B_ShoppingSessionBackgroundAudit.md` | `e97e4884e5e983fabfe6db0402d6794ca4bd4173c13cd9d07f9e10059089bae1` |
| `docs/Audits/1.0.3/WT-030C_CommunityFeedbackAudit.md` | `1623704bccdf805f8a3e012ea8e39ee4462c15e4e8ee32a068240e9e5b2aefab` |
| `docs/ImplementationPlans/1.0.3/WT-031A_ProductStateImplementationPlan.md` | `7321482546b6985ace7aee999c1a195ed1b295dda3af1bb57c6e670c5cc6d06a` |
| `docs/ImplementationPlans/1.0.3/WT-031B_ShoppingSessionImplementationPlan.md` | `1431167d7113078102d4a63d676b4a68c620d7018c228c423af6f3681f0c040d` |
| `docs/ImplementationSpecifications/1.0.3/WT-032A_ProductState_Phase0DecisionSpecification.md` | `c1d43c3037651f59cb3e8bd680ef3fe4e7e8f3306ed038abf2c710a8462d1abd` |
| `docs/ImplementationSpecifications/1.0.3/WT-032B_ProductState_Phase1ImplementationSpecification.md` | `25824516c1d0602281fe8000dd1a5c81cc12ddd9b3ba68b3da5d5b82097b1fb7` |
| `docs/Specifications/WT-033A_ProductStateAuthorityDiscovery.md` | `16e336f54a4cb644465f1836e9d97410bffc1044de4322581398ab3f8517b920` |
| `docs/Specifications/WT-033A_ProductStateAuthoritySpecification.md` | `2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c` |
| `docs/Specifications/WT-033A_ProductStateTechnicalImplementation.md` | `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361` |
| `design/v1.0/WayTask_Product_Specification_v1.0.pdf` | `a8ef365c558730dd9aaf9b1544315f5da677e1bfc86cae6b7acd8dd726d4f61b` |

WT-032A contains the complete unique decision set D-01 through D-37.

### Frozen persistence, project, and package sources

| Protected file | SHA-256 |
|---|---|
| `WayTask/Models.swift` | `f95ef54ada32d9fccd9eea8851feb407cdc57da27a45288675ef1c9afa6544db` |
| `ProductHistory.swift` | `aad103cee3f5f119ed77a9b892e40f3d5ff74aba8004f5730f12ea8b4cc37bba` |
| `ShoppingSession.swift` | `fff17fbd92c8a666864979c8b8e40202c36ce9a6b4caece9e8d5af8022ae0961` |
| `WayTask/Persistence/WayTaskSchemaV1.swift` | `a82370847be17b15d15bebfd7aae72c48b98141f1fd2f346bb6afa8b33ff7a56` |
| `WayTask/Persistence/WayTaskSchema.swift` | `bc9a5cf075275e5b40242b5109d9b2eddc50a49bbe44b3f8b01279db159fe27e` |
| `WayTask/Persistence/WayTaskStartupPersistence.swift` | `9eaf9dd7f95e96249d117a414084cdbdb564bfb413a247f036bde29b55a7bd7` |
| `WayTask.xcodeproj/project.pbxproj` | `9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f` |
| `WayTask.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | `42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244` |

The prior V1 and V2/V3/current representations remain frozen. No new schema,
migration identifier, persistence model, project membership entry, package
pin, or build setting was added.

### Phase 1 evidence and characterization baseline

| Protected file | SHA-256 |
|---|---|
| `docs/ImplementationEvidence/1.0.3/WT-031A_Phase1_ProductStateBaseline.md` | `11e68f63a3c3e85061254adbada6fd7300145f380ed01151be84bb1873f11eb7` |
| `WayTaskTests/ProductState/Fixtures/product-state-current-behavior-v1.json` | `d55771a3a4b422cd63cd2e3ee3ebd8a288defb890be4859b3c5ee263445f3cae` |
| `WayTaskTests/ProductState/Support/ProductStateCharacterizationSupport.swift` | `1447a27623cff06c2fb06001090a59c2773d788ef2386d25c7912255294b72ab` |
| `WayTaskTests/ProductState/ProductStateDomainCharacterizationTests.swift` | `16494a775a4ba2ba4827ad84e20ccac81fb1256821be99df7a1f8403996f3989` |
| `WayTaskTests/ProductState/ProductStatePersistenceCharacterizationTests.swift` | `1cd006bb3916a931c2a116715acff76afae22f01737069a314a7929fbf846deb` |
| `WayTaskTests/ProductState/ProductStateConsumerCharacterizationTests.swift` | `84ba08ff731d51bbbd9cf52ce4bebfd3c7369fd37d4d2b19fb57d5147f935b0a` |
| `WayTaskTests/ProductState/ProductStateDiagnosticsCharacterizationTests.swift` | `7aabb53572a0eaa8950ece2a07254e9e038ac950c8d87fe15111b0f128882951` |
| `WayTaskTests/ProductState/ProductStatePerformanceBaselineTests.swift` | `d5739fab4e09e030118ccebd699fde0358013f888ccc53988f3fc57a9720c8dc` |

The tracked `WayTaskTests` tree aggregate is
`920957649d9b1bfa0e5dd67a3529ab3a9483e8696dee1aee20b3c00457cc4316`.
The tracked Product Catalog/Product Knowledge source-and-test aggregate is
`a2c919c3ba6658e914c15513eefc7c25978c328bccacaebc8bd390e2b88cbb03`.
The tracked Xcode project/package aggregate is
`457f704643e8b6aaf12279cc0a549913bce87797d21267b04fb27ab1848e15d2`.

## Production, test, project, package, and feature status

- **Verified:** the complete tracked repository had zero staged and zero
  unstaged changes before T-00 evidence creation.
- **Verified:** no production Swift file, existing test, fixture, schema,
  migration, project, scheme, test plan, package file, localization, Catalog
  artifact, or Product Knowledge artifact changed.
- **Verified:** `Package.resolved` format version is 3. It pins
  `sentry-cocoa` 9.21.0 at revision
  `53eb9bd5da18e208cfd80e86863d3f4c7ba21b1d`; successful test and generic
  builds resolved that unchanged pin.
- **Verified:** no root `Package.swift` or XCTest plan is present.
- **Verified:** a dry-run ignored-file audit found pre-existing local
  configuration, Xcode user data, filesystem metadata, and documentation
  screenshots. No ignored path was read for content, removed, or modified.

## Toolchain and execution environment

| Component | Verified value |
|---|---|
| Host | macOS 26.6, build 25G72 |
| Shell-reported host architecture | `x86_64` |
| Xcode | 26.6, build 17F113 |
| Swift | 6.3.3; `swiftlang-6.3.3.1.3 clang-2100.1.1.101` |
| Swift compiler target | `arm64-apple-macosx26.0` |
| Simulator | iPhone 17 Pro, iOS 26.5 (23F77) |
| Simulator UDID | `DE30E799-0496-4818-851D-FF613F62FCD3` |
| Simulator test architecture | `arm64` |
| Test configuration | Debug; serial (`-parallel-testing-enabled NO`) |
| Build configurations | Generic unsigned iOS Debug and Release |

The selected simulator, runtime, Xcode, Swift, and host versions match the
approved Phase 1 E-09 environment.

## File-system-synchronized discovery

`WayTask.xcodeproj/project.pbxproj` declares both `WayTask` and `WayTaskTests`
as `PBXFileSystemSynchronizedRootGroup` roots. The unfiltered build/test action
compiled and discovered the tracked Product State support file, bundled JSON
fixture, all five characterization suites, and all other test classes without
a project-file change. The generic Debug and Release application builds also
discovered the current production source root. File-system synchronization is
therefore verified for the present source/test layout; no project membership
edit is authorized for T-01.

## Phase 1 baseline reproducibility

### Exact complete-target command

The single unfiltered invocation below contains no `-only-testing`,
`-skip-testing`, or test-plan exclusion. It therefore exercised the five Phase
1 suites, the support self-tests, and the complete `WayTaskTests` target in one
run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet test \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=DE30E799-0496-4818-851D-FF613F62FCD3' \
  -derivedDataPath /private/tmp/WT033A-T00-20260730.n2wdSQ/DerivedData-Tests \
  -resultBundlePath /private/tmp/WT033A-T00-20260730.n2wdSQ/WayTaskTests.xcresult \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
```

### Exact results

| Required suite | Passed | Failed | Skipped |
|---|---:|---:|---:|
| `ProductStateCharacterizationSupportSelfTests` | 4 | 0 | 0 |
| `ProductStateDomainCharacterizationTests` | 12 | 0 | 0 |
| `ProductStatePersistenceCharacterizationTests` | 15 | 0 | 0 |
| `ProductStateConsumerCharacterizationTests` | 6 | 0 | 0 |
| `ProductStateDiagnosticsCharacterizationTests` | 5 | 0 | 0 |
| `ProductStatePerformanceBaselineTests` | 7 | 0 | 0 |
| **Required Product State subtotal** | **49** | **0** | **0** |
| **Complete WayTaskTests target** | **340** | **0** | **0** |

Xcode completed the test operation in 1,217.561 seconds with exit code 0.
The privacy-safe result summary reported `Passed`, 340 total tests, no expected
failures, and the selected iPhone 17 Pro/iOS 26.5/arm64 destination. These
totals exactly reproduce the approved E-09 complete-target baseline. The
committed performance selectors ran without altered profiles or thresholds;
their authoritative controlled Release observations remain the frozen Phase 1
evidence rather than being reinterpreted by T-00.

The build emitted the two already documented diagnostics: the unused
test-local `legacyByID` value at
`WayTaskTests/ProductCatalog/ProductCatalogMigrationTests.swift:136`, and the
Sentry debug-symbol upload phase dependency-analysis note. No file was changed
in response.

### Exact generic build commands and results

Debug:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Debug \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/WT033A-T00-20260730.n2wdSQ/DerivedData-Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Release:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -quiet \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Release \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/WT033A-T00-20260730.n2wdSQ/DerivedData-Release \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Both generic unsigned builds completed with exit code 0. The successful quiet
invocations emitted no production compile warning. No source, project, package,
or configuration change was used to obtain a pass.

## Infrastructure retries

1. The first sandboxed `simctl list devices available` inspection could not
   connect to CoreSimulatorService or write its simulator log. The same
   read-only inspection was repeated with simulator-service access and
   selected the approved shutdown simulator.
2. The complete test command itself passed on its first execution. No test was
   retried.
3. Initial sandboxed `xcresulttool` summary extraction could not create its
   internal `TestReport` cache. The same read-only extraction succeeded with
   result-bundle access. Raw result content is not embedded here.
4. The first sandboxed generic Debug build attempt exited 74 because Xcode
   services were unavailable and DNS could not resolve the pinned Sentry
   repository. It produced no repository change. The identical command
   succeeded with Xcode/package access. Release succeeded on its first
   authorized invocation.

These are recorded as environment restrictions, not product/test retries and
not hidden or relabeled as successful attempts.

## WT-031B dependency gate

### Current authority and approval status

**Verified:** the only current WT-031B authority is
`WT-031B_ShoppingSessionImplementationPlan.md`. Its status is “Implementation
planning only,” implementation authorization is “Not granted,” and its
terminal decision authorizes preparation of an implementation specification
only. The repository contains no WT-031B implementation specification.

**Verified:** WT-031B retains:

- 27 questions classified as blocking before implementation;
- 8 questions classified as blocking before migration;
- 14 questions classified as blocking before release; and
- 68 unchecked implementation-readiness items.

### Shared-definition disposition for T-02, T-08, and T-19

| Required shared definition | Verified document alignment | Gate disposition |
|---|---|---|
| Session source list and revision | WT-031B §§5.2, 5.5 and WT-032A D-12 require a frozen source list/revision snapshot. | Conceptually aligned, but exact persisted representation remains unauthorized. |
| Immutable Session lines | WT-031B §§5.4–5.5 and WT-032A D-12 require stable source-entry identity and immutable started snapshots. | Conceptually aligned, but no co-approved persistence graph exists. |
| Provisional collection | WT-031B §6.4 and WT-032A D-03 keep collection Session-local until Finish. | Aligned at decision level. |
| Final line outcomes | WT-032A D-04 defines explicit final outcomes, while WT-031B §5.4 still models `collected` in its outcome vocabulary and BI-04 remains open for remaining-line Finish choices. | Not proven as one implementation-grade definition. |
| Finish transaction ownership | WT-031B §6.6 and WT-032A D-36 require one atomic Session/list/history transaction. | Aligned at architecture level, but no co-approved coordinator/schema contract exists. |
| Abandon behavior | WT-032A D-05 and WT-031B §6.7 distinguish Abandon from Finish and preserve progress without list/purchase reconciliation. WT-031B BR-03 still records history behavior as unresolved. | Directionally aligned, not closed in current WT-031B approval state. |
| Recovery candidates | WT-032A D-28–D-29 and WT-031B §§11.2, 11.9 preserve unresolved/multiple candidates instead of silently selecting or deleting. WT-031B BM-01 through BM-08 retain exact migration/recovery policy gaps. | Safety rule aligned, exact candidate representation and resolution not approved. |

**Gate interpretation:** T-02, T-08, and T-19 cannot currently be shown to
share one approved implementation-grade definition across all seven required
areas. The conceptual boundaries are largely compatible, but they are not a
substitute for the co-approved WT-031B implementation specification required
by S-02.

### Stop conditions

Production work remains stopped until all of the following are true:

1. a WT-031B implementation specification is approved and explicitly
   authorizes its bounded source, persistence, migration, test, and project
   footprint;
2. the final line-outcome vocabulary and remaining-line Finish choices are
   harmonized with D-04 without reinterpretation;
3. T-02, T-08, and T-19 use one approved Session source revision, immutable
   line, provisional collection, final outcome, Finish, Abandon, and recovery
   candidate contract;
4. applicable WT-031B implementation and migration blockers are closed,
   including multiple-active recovery, missing evidence, legacy terminal
   unresolved outcomes, activity/expiration provenance, and historical list
   revision provenance; and
5. no new overlap or protected-hash drift is present when implementation is
   re-gated.

T-00 does not resolve or redesign any WT-031B question.

## Rollback and temporary-artifact boundaries

The exact owned root was:

```text
/private/tmp/WT033A-T00-20260730.n2wdSQ
```

It contained these top-level execution paths:

```text
DerivedData-Tests
WayTaskTests.xcresult
DerivedData-Debug
DerivedData-Release
```

The failed sandboxed Debug attempt additionally created:

```text
/private/var/folders/7_/qpclhzrj35sbwtl5_0xvkr4w0000gn/T/ResultBundle_2026-30-07_23-44-0049.xcresult
```

Before cleanup, test-owned Product State temporary-store roots were absent,
confirming self-cleanup of synthetic stores and sidecars. T-00 then removed
the exact owned root and the exact sandbox-error result bundle. Post-cleanup
checks confirmed both paths absent and found no `WT033A-T00-*` or
`WT032B-ProductState-*` residual root in the inspected temporary locations.
No broad repository, home-directory, user Application Support, or user-data
cleanup was performed.

T-00 rollback consists only of removing this evidence document. There is no
runtime, schema, migration, test, package, project, Catalog, Product Knowledge,
or localization dependency to undo.

## Final repository audit

- The branch and commit remain `main` at
  `a20b83c570157038cb85b0b3efb49a24cf8ccc50`.
- The original four untracked documentation paths remain untouched.
- The fifth and only T-00 repository difference is this approved evidence
  document.
- Staged and tracked modified path counts remain zero.
- Protected governing, persistence, project, package, Phase 1 support,
  fixture, suite, evidence, Catalog, and Product Knowledge baselines remain
  unchanged.
- No generated DerivedData, result bundle, store, sidecar, or attachment from
  T-00 remains.
- T-01 and all later implementation steps were not executed.

## Terminal T-00 decision

BLOCKED BEFORE T-01
