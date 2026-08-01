# WT-033A T-10 — Product Command Authority

**Execution date:** 2026-08-01 (Asia/Hebron)

**Starting branch:** `main`

**Starting commit:** `f1f1bf5d4359fb3eb1a1dc9c673ef447bd3d6d70`

**Starting status:** clean; `HEAD`, `main`, and `origin/main` were identical

**Commit status:** review worktree only; T-10 was not committed

## Authority and Footprint Gate

Before any write, the repository was clean and the committed sequence was
verified as T-01 `d81df92`, T-02 `d16852e`, T-03 `f048e47`, T-04 `0d4e0a8`,
T-05 `78961f1`, T-06 `d583006`, T-07 `3ef06c5`, T-08 `0d4153e`, and T-09
`f1f1bf5`. The governing S-02 SHA-256 was
`49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361`.

The exact S-02 T-10 assignment was:

> T-10 | Convert Product acquisition, edit, Library removal, and Restore to
> command authority | TC-04–TC-07, TC-10; `ShoppingListService.swift` —
> `ProductLibraryDeletionService`; TC-19; Product command tests | Explicit
> create/already-active/restore-required; Restore preserves ID/no lists;
> all-list removal and active-Session block atomic; required remove/restore
> events append in the same transaction; no implicit restore | Disable new
> command callers; forward-compatible target data/events retained | D-06–D-07,
> D-15–D-18, D-22, D-35

This matched the execution instruction. S-02 assigned no evidence filename, so
the authorized fallback filename is used here. The final footprint is:

- TC-04 Product command preparation and the single T-10 command entry:
  `WayTask/ProductState/Application/ProductStateCommandCoordinator.swift`;
- TC-07 exact Product and Product-entry repository queries:
  `WayTask/ProductState/Persistence/ProductStateRepositories.swift`;
- TC-15 target-only acquisition/removal adapters:
  `ShoppingListService.swift`;
- TC-19 target-only acquisition adapters:
  `WayTask/Persistence/AddProductSaveCoordinator.swift` and
  `WayTask/Persistence/CatalogProductPersistenceService.swift`;
- focused Product command tests:
  `WayTaskTests/ProductState/ProductStateProductCommandAuthorityTests.swift`;
- this evidence document.

File-system synchronization compiled and ran the new test file without a
`project.pbxproj` edit. TC-05 transaction ownership and TC-10 history
persistence were reused unchanged. No startup, migration, schema, UI,
ViewModel, Map, Camera, notification, Catalog repository, Product Knowledge,
network, telemetry, or Sentry source changed.

## Command Authority and Write Gate

`ProductStateProductCommandAuthority` is the sole new T-10 Product mutation
entry. It receives the already composed TC-07 repository bundle and the
committed TC-05 transaction coordinator; it does not import SwiftData, create
a persistence context, or save independently.

The authority has three explicit write states:

| State | Result |
|---|---|
| `writableTarget` | Allows an explicitly composed target command transaction |
| `migrationIncomplete` | Rejects before repository access with a deterministic non-success result |
| `nonDurable` | Rejects before repository access and cannot claim durable success |

No production startup, application root, UI, ViewModel, or service constructs
the authority. The target-only service methods require an authority to be
injected explicitly and have no current caller. The committed V3 service
methods remain unchanged, V3 remains the live schema, and V4 remains inactive.
This is the forward-compatible T-10 rollback boundary required by S-02; later
consumer-conversion and release-cutover steps remain unstarted.

Only TC-05 dispositions `committed` and `reconciledCommitted` can produce a
durable success. Rolled-back, unknown, rejected, validation, conflict, and
unavailable results never report success. One command supplies one expected
Product revision, one effective timestamp, and stable command/Product/event
identities.

## Add and Acquisition Semantics

Acquisition accepts explicit reviewed evidence and a caller-supplied stable
Product UUID. Exact matches are the union of:

- the supplied Product UUID;
- an exact Catalog Product identifier, when supplied;
- an exact barcode, when supplied.

Product name, display text, snapshot text, list position, and enumeration order
are never identity inputs. Zero exact matches stage one new active Product with
revision one and no list membership. One exact active match returns
`alreadyActive` without a commit. One exact removed Product with a valid
tombstone returns `restoreRequired` without restoring. Multiple distinct exact
matches return an ambiguity conflict. A malformed lifecycle/tombstone state is
rejected rather than guessed.

Catalog acquisition preserves the exact Catalog ID plus reviewed display name,
locale, category ID/display name, icon key, image, and snapshot timestamp. The
custom and recognition adapters forward reviewed snapshots only. None of the
adapters contains an implicit restore branch or an independent save.

## Edit, Remove, and Restore Semantics

Edit requires an active Product and the exact expected Product revision. It
preserves the Product UUID, tombstone fields, Catalog identity, and Catalog
snapshots while incrementing the Product revision exactly once. Stale or
removed Products are deterministic non-success outcomes.

Library removal performs the following inside one TC-05 transaction:

1. loads exactly one active Product at its expected revision;
2. inventories every target entry for the Product and resolves each exact list;
3. preserves Completed/Recent archive evidence while identifying every editable
   list membership;
4. requires a unique, exact expected revision for every affected editable list;
5. rejects duplicate/missing list or entry identity;
6. rejects when an active or expired Session line references the Product or any
   of its source entries;
7. stages the Product tombstone and increments its revision once;
8. deletes every editable membership and increments each affected list revision
   once; and
9. appends one UUID-keyed `productRemovedFromLibrary` history event.

The Product, entries, list revisions, and removal event commit or roll back
together. Archive entries are retained as evidence and do not become active
membership authority.

Restore requires an explicitly removed lifecycle plus a non-null removal
timestamp and explicit restore intent. It preserves the Product UUID and
fields, clears only the tombstone through the approved transition, increments
the Product revision once, appends the required UUID-keyed restore event in the
same transaction, preserves existing history, and creates no list or entry.
An active Product is a no-op; malformed removed state is rejected. No
acquisition path invokes Restore.

## Rollback and Deterministic Diagnostics

The committed TC-05 coordinator remains the only commit/rollback owner. Focused
failure injection proves acquisition, edit, removal, and Restore save failures
restore the staged Product/list/entry/history state and never claim success.
Unknown or unreconciled commit results also cannot be reported as durable.

The encodable command diagnostic contains only command/request/authoritative
UUIDs, bounded operation/outcome/failure/durability enums, before/after
revisions, aggregate affected-list/event counts, and a durable-success Boolean.
It contains no Product name, barcode, note, image, Catalog display snapshot,
coordinates, account identifier, path, source row, attachment, credential, or
raw error. Equivalent clean fixtures produce identical outcomes, revisions,
state summaries, and diagnostics.

## Focused Qualification

Both authoritative runs used the iPhone 17 Pro iOS 26.5 simulator with
separate clean DerivedData roots and result bundles. Focused fixtures used
isolated in-memory target containers with deterministic identities and no
application-default, protected source, migration-candidate, or user store URL.

| Run | Result | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| Focused A | 19 passed | 0 | 0 | 0 |
| Focused B | 19 passed | 0 | 0 | 0 |

The 19 tests cover write gating; manual and Catalog creation; exact active and
restore-required acquisition; exact ambiguity and prohibition of name matching;
edit revisions/conflicts/rollback; atomic all-list removal; exact impact and
stale-list conflicts; active/expired Session protection; removal rollback;
explicit Restore/no-list behavior; malformed tombstone and Restore rollback;
privacy-safe diagnostics; target adapters; equivalent-fixture determinism; and
static absence of startup activation or an alternate target mutation caller.

Development preflights were used only for defect discovery and are not counted
as qualification evidence.

## Regression and Build Matrix

| Gate | Result | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| Affected Product/list/history/Catalog/migration/startup bundle | 278 passed | 0 | 0 | 0 |
| Exact six-suite Phase 1 gate | 49 passed | 0 | 0 | 0 |
| Complete unfiltered `WayTaskTests` | 523 passed | 0 | 0 | 0 |
| Generic iOS unsigned Debug build | Succeeded, exit 0 | — | — | — |
| Generic iOS unsigned Release build | Succeeded, exit 0 | — | — | — |

The exact Phase 1 selectors were
`ProductStateCharacterizationSupportSelfTests`,
`ProductStateDomainCharacterizationTests`,
`ProductStatePersistenceCharacterizationTests`,
`ProductStateConsumerCharacterizationTests`,
`ProductStateDiagnosticsCharacterizationTests`, and
`ProductStatePerformanceBaselineTests`. The complete result bundle reports six
tests collecting performance metrics. No existing test, fixture, profile,
threshold, or expectation changed.

The affected qualification included the new suite; command pipeline,
transaction, repository, validator, transition, persistence graph, persistence
characterization, consumer, diagnostics, and support suites; deletion;
Add/Catalog persistence and compatibility; legacy creation; Catalog migration
and personalization; Shopping UX; T-06/T-07/T-08 migration; T-09/startup
resilience and repair; and schema migration.

The first affected attempt reported 277 passes and one failure in the committed
`testFailedWorkingCopyOpenDoesNotMutateSourceFixture` fingerprint check. No
T-10 source was present in its stack or fixture path, and neither that test nor
its support code had changed. A fresh isolated diagnostic run passed 1/1. The
complete affected matrix was then repeated from a new clean DerivedData/result
root and passed 278/278; the same baseline test also passed in both the exact
Phase 1 and complete-target runs. This non-reproducing synthetic-fixture result
was not counted as qualification and no expectation was weakened. The committed
performance fixture emitted its existing SQLite open-descriptor cleanup log
after passing; this was confined to its owned simulator-temporary directory and
did not involve a Product command or application store.

Xcode also emitted the existing Sentry XCFramework identity/dependency-analysis
note. No new compiler error, warning source, dependency, or build setting was
introduced.

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
| TC-14 startup gate | `f1729caf5c33cc7de19b0cd751ae0fdb6480190a4773ec8bf37e589fcd59b849` | Unchanged |
| `WayTaskApp.swift` | `5a460b45f2922c096ee1a81ddd7da27fe13df49c50d632d1b5c91d568bb04251` | Unchanged |
| `ContentView.swift` | `2d30601201a2eac39673128cdac0f19907a7fe3ef7fc3e93c826d2943a3f70fc` | Unchanged |
| T-06 focused tests | `702f6e7690b954a2dc93862d3f7c53254d4fb5ab1cebde5b488f78740e1d139a` | Unchanged |
| T-07 focused tests | `e9d6a7d305b57cfb565f46431f87ec66fadd92eff0971ecd5006b4bc36a64d97` | Unchanged |
| T-08 focused tests | `385d7f4e48f58668b756138cddd2791044d180163dbe42cd8521b3ae2c8b8e5a` | Unchanged |
| T-09 focused tests | `02b1eacf1f76941eac6c438b88f5f5d931b8a4ff405353d37393a32b34cd76c2` | Unchanged |
| T-06 evidence | `f803d6c30e37c1777953383f25ad7a93c560909a9a1d09f655e39fcab5625383` | Unchanged |
| T-07 evidence | `afc64b50be550223df3b5dad29957b7c7c560bb2dea36ad70726a0882174aa1e` | Unchanged |
| T-08 evidence | `78680732e834dd588bc7a51c02e7b6591951f77c9b21cb60ed6ab434c077b129` | Unchanged |
| T-09 evidence | `4fcfb535f959032064ea7cf4601afaf6a8189bf75da2cc45be630b56e22f8bd5` | Unchanged |

Committed T-01 through T-05 evidence remained exact:

```text
d9f62bb63a5510633425d4bf055f2e911b4011f76ccd2eb36f421d550291410b  T-01
f39525267de1902c07a3d2c3f44ae26483b220ca5646789638981a589ef01dc3  T-02
c2338f096f9132351095e484cc17feb495a8c9c62e7444f81b551e79509a9bb5  T-03
86ecf19cf81b32913ca3dcfc5d90b5384150dcd5a214b3021c745ea20746ede2  T-04
43fda677a9fdc546341173db6f491d6f134db1ac62e0181a727b9d8233455d10  T-05
```

Final T-10 implementation/test hashes before evidence creation:

```text
75f4c7618eb243eb8cc9cdc804bdd78de87964c014b34e64a4f897e57c10b9d6  ShoppingListService.swift
e11ffae04689771361c8f3575e5f263389def81e140cbfb60787b341db40c50d  WayTask/Persistence/AddProductSaveCoordinator.swift
ae00814765cb6d8dda338182f40a5758269f675f5acac42c4efac0df698705c3  WayTask/Persistence/CatalogProductPersistenceService.swift
0170f488aa61895a3ea63acdfc61cec0db470823a03428c295d0c5802561d890  WayTask/ProductState/Application/ProductStateCommandCoordinator.swift
e549cd17859e9eac584a493e3b2654fb000d59cd2d6bf6d4a191bb11094d5262  WayTask/ProductState/Persistence/ProductStateRepositories.swift
9447478c6658b52e77fba644bbf73aa537c13fa16d46a75aa5275e7b6c661682  WayTaskTests/ProductState/ProductStateProductCommandAuthorityTests.swift
```

Static and repository audits prove:

- `HEAD`, `main`, and `origin/main` remain
  `f1f1bf5d4359fb3eb1a1dc9c673ef447bd3d6d70`;
- V3 remains `currentSchema`; V4 remains target-only and inactive;
- no startup, application-root, UI, ViewModel, or other production caller
  references the new authority or target adapter methods;
- no independent repository save, alternate Product mutation owner, implicit
  Restore, Product-name identity, candidate promotion, or source replacement
  API was added;
- no migration, schema, startup, target UI, Session redesign, T-11 list-command
  behavior, project, package, localization, asset, Catalog repository, Product
  Knowledge repository, Map, Camera, notification, AI, network, telemetry, or
  Sentry dependency change exists;
- `project.pbxproj` and all T-06 through T-09 protected paths are identical to
  `HEAD`;
- `git diff --check` passes.

## Cleanup and Review Rollback

All test stores were either isolated in-memory containers or suite-owned
simulator-temporary fixtures. No application-default, protected source, or
migration-candidate store was opened by the new T-10 suite or command code.
After result extraction, every `WT033A-T10-*` DerivedData directory, result
bundle, temporary store, sidecar, cloned package, log attachment, and build
product was deleted. No task-owned temporary artifact remains.

Before commit, review rollback is source-only: restore the five modified
production files to `HEAD`, delete
`WayTaskTests/ProductState/ProductStateProductCommandAuthorityTests.swift`, and
delete this evidence document. This removes the uncalled forward-compatible
authority and adapters; committed V3 behavior, protected T-06–T-09 migration
and startup work, and all retained target data declarations remain unchanged.

## Terminal Decision

T-10 COMPLETE — READY FOR REVIEW
