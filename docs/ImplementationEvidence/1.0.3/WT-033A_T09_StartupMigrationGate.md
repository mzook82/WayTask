# WT-033A T-09 — Startup Migration Gate

**Execution date:** 2026-08-01 (Asia/Hebron)

**Starting branch:** `main`

**Starting commit:** `0d4153eb39908d1f87950e947fa000cd0836dde9`

**Starting status:** clean; `HEAD`, `main`, and `origin/main` were identical

**Commit status:** review worktree only; T-09 was not committed

## Authority and Footprint Gate

Before any write, the repository was clean and the committed sequence was
verified as T-01 `d81df92`, T-02 `d16852e`, T-03 `f048e47`, T-04 `0d4e0a8`,
T-05 `78961f1`, T-06 `d583006`, T-07 `3ef06c5`, and T-08 `0d4153e`.
The governing S-02 SHA-256 was
`49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361`.

The exact S-02 T-09 assignment was:

> T-09 | Gate startup on migration completion and truthful
> durability/recovery state | TC-14; `WayTask/WayTaskApp.swift`,
> `WayTask/ContentView.swift`; startup resilience tests | Writable target UI
> unavailable before success; no root-view backfill; empty/in-memory state not
> reported durable; reopen and rollback drills pass | Forward-compatible
> startup gate disables target UI; protected original retained | D-24, D-27,
> D-29, D-32, D-34

This matched the execution instruction. S-02 assigned no evidence filename, so
the authorized fallback filename is used here. The final footprint is:

- TC-14: `WayTask/Persistence/WayTaskStartupPersistence.swift`;
- startup root: `WayTask/WayTaskApp.swift`;
- root gate presentation and removal of root-view backfill ownership:
  `WayTask/ContentView.swift`;
- focused startup tests:
  `WayTaskTests/Persistence/StartupMigrationGateTests.swift`;
- this evidence document.

File-system synchronization compiled and ran the new Swift test file without a
`project.pbxproj` edit. TC-13 and all T-06/T-07/T-08 production migration
sources remain unchanged.

## Startup State Machine and Write Gate

TC-14 now defines the eight required deterministic states:

| State | Meaning | Application content | Writable V4 / target UI / promotion |
|---|---|---|---|
| `startupReady` | Persistent V3 is available, or verified rollback recovery reopened it | V3 only | Disabled |
| `migrationRequired` | Complete migration evidence is absent | Blocked | Disabled |
| `migrationRunning` | An explicit migration trace is active | Blocked | Disabled |
| `migrationInterrupted` | Original and rollback are verified, but a safe retry is required | Blocked | Disabled |
| `migrationFailed` | A classified validation/reopen/integrity/fingerprint/space failure occurred with verified rollback | Blocked | Disabled |
| `recoveryRequired` | Source, rollback, candidate, or user recovery evidence is unresolved | Blocked | Disabled |
| `degradedMode` | Only non-durable or unavailable storage is available | Blocked | Disabled |
| `migrationSucceeded` | Candidate completion, integrity, fingerprints, reopen, original, and rollback are all verified | Blocked pending later cutover | Disabled |

`WayTaskStartupMigrationGateDecision` exposes separate legacy-V3 content,
writable-target, target-UI, and candidate-promotion decisions. T-09 permits
legacy application content only for `startupReady` plus a persistent V3 store.
The three target/cutover decisions are unconditionally false because T-09 is
pre-promotion and pre-consumer-conversion.

The production migration trace defaults to `targetInactive`, preserving the
committed V3 live schema and current production source boundary. Every
explicit target migration trace is evaluated before TC-14 can open or repair
the application default store. A blocked trace receives only an isolated
in-memory presentation container; this container is labelled
`protectedStoreNotOpened` and cannot be reported as durable application data.
No T-06/T-07/T-08 migrator is invoked and no candidate URL is opened by the
production startup path.

`WayTaskApp` now retains the gate decision and presents onboarding or
`ContentView` only when persistent V3 content is authorized. Every other state
receives a read-only migration/recovery gate view. Failure to initialize even
the isolated presentation container produces a deterministic unavailable
decision rather than `fatalError` or an empty-data success.

## Completion, Integrity, and Fingerprint Verification

The completion boundary requires all of the following before it can report
`migrationSucceeded`:

- explicit migration completion;
- candidate integrity verification;
- source and candidate fingerprint verification;
- deterministic candidate reopen verification;
- protected-original verification;
- rollback-state verification;
- zero unresolved recovery candidates;
- no promotion authorization and no target-schema activation.

Incomplete evidence yields `migrationRequired`. Integrity, fingerprint, and
reopen failures retain distinct deterministic classifications. Recovery
candidates yield `recoveryRequired` while preserving their count. An input
claiming promotion or target activation fails closed as unauthorized. Even a
fully verified candidate remains staged: writable V4, target UI, and promotion
all stay disabled.

## Recovery and Degraded Startup

Interrupted and failed traces must prove both the protected original and the
rollback state. Missing original verification yields
`protectedOriginalUnavailable`; missing rollback verification or remaining
candidate artifacts yields `rollbackUnverified`. A verified recovery-complete
trace may reopen and repair the persistent V3 store, after which the result is
`startupReady` for V3 only.

The prior startup resilience path remains available when migration is inactive,
but its outcomes are now truthful at the app boundary:

- a recreated persistent store is `recoveryRequired`, never durable success;
- an in-memory fallback is `degradedMode`, never durable success;
- inability to create any presentation storage remains degraded and blocks
  application content;
- no implicit fallback changes a migration state.

The root-view `ensureDefaultListsAndBackfill`/Catalog hydration ownership was
removed from `ContentView`. The existing TC-14 startup repair remains the one
startup repair owner, so the root cannot backfill after the gate has admitted
content.

## Diagnostics and Privacy

The gate adds migration-gate, validation, recovery, and complete stages to the
existing startup diagnostic vocabulary. The committed diagnostic sequence is
unchanged for the inactive V3 path; S-02-authorized sequence changes occur only
for an explicit target trace.

The encodable migration diagnostic contains only bounded enums, booleans, and
non-negative aggregate counts: state, durability, safe failure category,
completion/integrity/fingerprint/reopen/original/rollback flags, recovery
count, exception/overflow counts, and candidate-artifact count. It contains no
paths, store rows, Product names, barcodes, notes, images, coordinates,
credentials, account identifiers, raw exception content, attachments, or
localized error text. Existing startup error domains remain sanitized through
the committed allowlist boundary.

## Reopen, Rollback, and Source-Protection Proof

Focused tests inject every store factory and count all calls. They prove that
required, running, interrupted, failed, recovery-required, and completed
candidate traces do not open, repair, quarantine, replace, or otherwise touch
the application default store. Only a recovery-complete trace with verified
original, verified rollback, and no remaining candidate artifact may reopen
persistent V3; it performs the existing TC-14 repair exactly once.

T-09 creates no file-backed fixture, synthetic probe, source store, candidate
store, sidecar, manifest, or ledger. All focused gate containers are in-memory
and injected. Therefore the startup work cannot mutate a protected migration
source/candidate, and no candidate cleanup or promotion API was introduced.
The committed T-06 rollback and T-07/T-08 semantic migration sources are
unchanged byte-for-byte.

## Focused Qualification

Both authoritative runs used the iPhone 17 Pro iOS 26.5 simulator with
separate clean DerivedData roots and result bundles.

| Run | Result | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| Focused A | 24 passed | 0 | 0 | 0 |
| Focused B | 24 passed | 0 | 0 | 0 |

The 24 focused tests cover the exact state vocabulary, inactive V3 behavior,
required/running/interrupted/failed/recovery/degraded/succeeded states,
insufficient space, rollback, recreated and in-memory storage, completion,
candidate integrity, source/candidate fingerprints, candidate reopen,
recovery counts, unauthorized promotion/activation, bounded privacy-safe
diagnostics, explicit no-default-store/no-repair/no-quarantine behavior,
recovery reopen, presentation failure, unchanged inactive diagnostics, root
gating, and static absence of V4/migrator/promotion/backfill/`fatalError`.

Development preflights were used only for defect discovery and are not counted
as qualification evidence.

## Regression and Build Matrix

The affected bundle selected the focused T-09 suite; existing startup
resilience, startup-repair/idempotency, and Sentry stability suites; Product
State diagnostics/persistence characterization; schema migration; and the
committed T-06, T-07, and T-08 migration suites.

| Gate | Result | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| Affected startup/migration regression bundle | 147 passed | 0 | 0 | 0 |
| Exact six-suite Phase 1 gate | 49 passed | 0 | 0 | 0 |
| Complete unfiltered `WayTaskTests` | 504 passed | 0 | 0 | 0 |
| Generic iOS unsigned Debug build | Succeeded, exit 0 | — | — | — |
| Generic iOS unsigned Release build | Succeeded, exit 0 | — | — | — |

The exact Phase 1 selectors were
`ProductStateCharacterizationSupportSelfTests`,
`ProductStateDomainCharacterizationTests`,
`ProductStatePersistenceCharacterizationTests`,
`ProductStateConsumerCharacterizationTests`,
`ProductStateDiagnosticsCharacterizationTests`, and
`ProductStatePerformanceBaselineTests`. All six performance tests collected
metrics. No existing test, profile, fixture, threshold, or expectation changed.

The only compiler warning was the pre-existing unused `legacyByID` local in
`ProductCatalogMigrationTests.swift`; T-09 did not change that file. Xcode also
reported the existing Sentry-symbol build-phase dependency-analysis note.

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
| TC-11 `ShoppingSession.swift` | `86c66430467c2b8b15a104c11cf0394709d4767a2e3ba7d1fbd2e711222eb8d5` | Unchanged |
| TC-13 migration foundation | `1c79711332281f4b24af81696c7242784596bcdaa8b92f35fb17b9ca757418e8` | Unchanged |
| T-06 focused tests | `702f6e7690b954a2dc93862d3f7c53254d4fb5ab1cebde5b488f78740e1d139a` | Unchanged |
| T-07 focused tests | `e9d6a7d305b57cfb565f46431f87ec66fadd92eff0971ecd5006b4bc36a64d97` | Unchanged |
| T-08 focused tests | `385d7f4e48f58668b756138cddd2791044d180163dbe42cd8521b3ae2c8b8e5a` | Unchanged |
| T-06 evidence | `f803d6c30e37c1777953383f25ad7a93c560909a9a1d09f655e39fcab5625383` | Unchanged |
| T-07 evidence | `afc64b50be550223df3b5dad29957b7c7c560bb2dea36ad70726a0882174aa1e` | Unchanged |
| T-08 evidence | `78680732e834dd588bc7a51c02e7b6591951f77c9b21cb60ed6ab434c077b129` | Unchanged |
| TC-14 T-09 source | `f1729caf5c33cc7de19b0cd751ae0fdb6480190a4773ec8bf37e589fcd59b849` | Authorized T-09 output |
| `WayTaskApp.swift` | `5a460b45f2922c096ee1a81ddd7da27fe13df49c50d632d1b5c91d568bb04251` | Authorized T-09 output |
| `ContentView.swift` | `2d30601201a2eac39673128cdac0f19907a7fe3ef7fc3e93c826d2943a3f70fc` | Authorized T-09 output |
| T-09 focused tests | `02b1eacf1f76941eac6c438b88f5f5d931b8a4ff405353d37393a32b34cd76c2` | T-09 output |

Committed T-01 through T-05 evidence remained exact:

```text
d9f62bb63a5510633425d4bf055f2e911b4011f76ccd2eb36f421d550291410b  T-01
f39525267de1902c07a3d2c3f44ae26483b220ca5646789638981a589ef01dc3  T-02
c2338f096f9132351095e484cc17feb495a8c9c62e7444f81b551e79509a9bb5  T-03
86ecf19cf81b32913ca3dcfc5d90b5384150dcd5a214b3021c745ea20746ede2  T-04
43fda677a9fdc546341173db6f491d6f134db1ac62e0181a727b9d8233455d10  T-05
```

Static and repository audits prove:

- V3 remains the live production schema; V4 remains inactive;
- no candidate promotion, source replacement, V4 writer, target consumer, or
  T-06/T-07/T-08 production migrator call exists in the startup path;
- explicit target traces cannot open, repair, quarantine, or silently fall
  back to the application default store;
- recreated/empty and in-memory results are blocked from durable application
  content and writable Product State behavior;
- no root-view backfill remains in `ContentView`;
- no Shopping UI, ViewModel, Service, Product/List/Session consumer, Map,
  Camera, notification, AI, Catalog repository, Product Knowledge repository,
  network, telemetry, localization, asset, package, or Sentry dependency
  changed;
- no file-backed metadata probe, `fatalError`, startup target activation, or
  candidate promotion API was added;
- `git diff --check` passes.

## Temporary-Artifact Cleanup and Review Rollback

After extracting the totals and hashes above, every explicitly named
`/private/tmp/WT033A-T09-*` DerivedData root and result bundle is removed.
T-09 owns no store fixture, source, candidate, sidecar, manifest, ledger, or
attachment. A final repository and temporary-root audit must find no T-09
store, sidecar, DerivedData directory, result bundle, or attachment.

Review rollback is source-only: discard the three tracked T-09 production
diffs and remove the untracked T-09 test and evidence document. No migration
store or candidate can be affected because T-09 added none and activated no
migrator or promotion path.

`T-09 COMPLETE — READY FOR REVIEW`
