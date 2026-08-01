# WT-033A T-11 — Named List and Entry Command Authority

**Execution date:** 2026-08-01 (Asia/Hebron)

**Starting branch:** `main`

**Starting commit:** `d83d4559b42b0cf93acb2539c5dc3068dfd66d7d`

**Starting status:** clean; `HEAD`, `main`, and `origin/main` were identical

**Commit status:** review worktree only; T-11 was not committed

## Authority and Footprint Gate

Before any write, the repository was clean and the committed sequence was
verified as T-01 `d81df92`, T-02 `d16852e`, T-03 `f048e47`, T-04 `0d4e0a8`,
T-05 `78961f1`, T-06 `d583006`, T-07 `3ef06c5`, T-08 `0d4153e`, T-09
`f1f1bf5`, and T-10 `d83d455`. The governing S-02 SHA-256 was
`49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361`.
The earlier, incorrect T-11 List-lifecycle instruction was blocked before any
write. The corrected instruction matched S-02 and the governing S-01 contract.

The exact S-02 T-11 assignment was:

> T-11 | Convert list/entry commands, durable revision, uniqueness, history
> effects, and one-way compatibility output | TC-04–TC-08, TC-10;
> `ShoppingListService.swift`; list tests | Add/no-op/Reopen semantics, resolve
> reasons, one-list remove, entry update, revision exactly once, concurrent
> uniqueness, required entry events in the same transaction, target→legacy
> only | Disable target callers; retain target entries/events; adapter remains
> non-authoritative; no reverse sync | D-02, D-06–D-11, D-13, D-19, D-33,
> D-35, D-37

This matched the corrected execution instruction. S-02 assigned no evidence
filename, so the authorized fallback filename is used here. The final footprint
is:

- TC-04 Named List/Entry command authority additions in
  `WayTask/ProductState/Application/ProductStateCommandCoordinator.swift`;
- new TC-08 one-way compatibility output in
  `WayTask/ProductState/Persistence/ProductStateCompatibilityAdapter.swift`;
- target-only adapters in `ShoppingListService.swift`;
- focused list/entry command tests in
  `WayTaskTests/ProductState/ProductStateNamedListEntryCommandAuthorityTests.swift`;
- this evidence document.

TC-05 transaction ownership, TC-07 repositories, and TC-10 UUID-keyed history
persistence were reused unchanged. The broader TC-06 query/projection boundary
remains assigned to T-13 and was not introduced. File-system synchronization
compiled and ran both new Swift files without a `project.pbxproj` edit. No
schema, startup, migration, application-root, UI, ViewModel, Service beyond the
authorized `ShoppingListService` adapter, Map, Camera, notification, AI,
network, telemetry, localization, asset, Catalog repository, Product Knowledge
repository, package, or dependency source changed.

## Command Authority and Write Gate

`ProductStateNamedListCommandAuthority` is the single T-11 mutation entry for
Named Lists and their exact entries. It receives the composed TC-07 repository
bundle and committed TC-05 transaction coordinator; it does not import
SwiftData, construct a context/container, or save independently. It exposes
only Create/Rename Named List and Add/Update/Resolve/Reopen/Remove Entry. There
is no Remove, Restore, Close, or Delete List operation or policy.

The authority has three explicit write states:

| State | Result |
|---|---|
| `writableTarget` | Allows an explicitly composed target command transaction |
| `migrationIncomplete` | Rejects before repository mutation with deterministic non-success |
| `nonDurable` | Rejects before repository mutation and cannot claim durable success |

No startup, application root, UI, ViewModel, or other production consumer
constructs the authority. `ShoppingListService` target methods require an
authority to be injected explicitly and have no current caller. Existing V3
methods remain unchanged, V3 remains the live schema, V4 remains inactive, and
T-21 remains the only release cutover.

Every entry command carries exact List, Product, and Entry UUIDs. Every
revision-sensitive command carries one expected List revision. The authority
verifies that T-04 staged exactly one authorized state effect and the exact
required event count before TC-05 can commit. Only TC-05 `committed` or
`reconciledCommitted` dispositions can report durable success. Validation,
conflict, no-op, rollback, and unknown results cannot report durable success.

## Create and Rename Named List

Create accepts a caller-supplied stable List UUID, validated title, authorized
named-list purpose, stable command UUID, and effective time. It creates exactly
one empty Named List at durable revision one. Repeating the same exact identity,
title, and purpose is a no-op; an existing conflicting identity is rejected.
No Product membership or default compatibility list is inferred.

Rename loads exactly one List by UUID, requires its exact expected revision,
validates the new title, and preserves the List UUID, purpose, relationships,
and timestamps not owned by the command. An effective rename increments the
List revision once. An identical title is a no-op with no revision drift. The
`completed` and `recent` archive purposes are not mutable Named Lists.

## Add, No-op, and Explicit Reopen

Add requires an active Product UUID, exact named List UUID and expected
revision, caller-supplied Entry UUID, valid quantity/unit/note/order values, and
stable command/event UUIDs. A successful Add creates one Needed entry,
increments the List revision once, and appends one `needAdded` Product-UUID
history event in the same TC-05 transaction.

If the exact Product/List membership already has one Needed entry, Add returns
that authoritative Entry UUID as a deterministic no-op. The caller-supplied new
Entry UUID does not replace it, no revision advances, and no event appears. If
the exact membership is Resolved, Add returns `reopenRequired` and changes
nothing. Only the explicit Reopen command can preserve that exact Entry UUID,
return it to Needed, clear its current resolution fields, increment the List
revision once, and append the `needReopened` event while retaining earlier
history.

Duplicate Entry rows or ambiguous Product/List/Entry identity are deterministic
conflicts. Serialized retry tests prove that one exact active membership exists
per Product/List pair and no duplicate revision or event is introduced.

## Entry Update, Resolve, and One-List Remove

Update requires the exact Entry/List/Product identity and List revision. It can
change only the authorized Entry-owned quantity, unit, note, and sort order.
An effective update increments the List revision exactly once; an identical
update is a no-op. It does not change Product lifecycle or another list.

Direct T-11 Resolve accepts only the approved user reasons `alreadyHave` and
`noLongerNeeded`. It preserves the Entry UUID, records the explicit reason,
effective time, and provenance, advances the List revision once, and appends
one `needResolved` event atomically. It never infers purchase. `purchased`
remains reserved for the later atomic Finish authority, and `legacyUnknown`
remains migration-only.

Remove requires the exact Entry/List/Product identity and expected List
revision. It deletes membership from that one named list, increments only that
List revision once, and appends one `needRemoved` event in the same transaction.
The Product remains active and entries in every other list remain unchanged.
A retry after the exact membership is absent is a no-op. No Product tombstone
or List lifecycle state is introduced.

A non-terminal Session line that captured the Entry blocks Update, Resolve,
Reopen, and Remove. Stale revision, removed Product, invalid values, missing or
ambiguous identity, malformed state, and protected Session conflicts change
nothing.

## History, Atomicity, and Rollback

Add, Resolve, Reopen, and Remove each stage their exact UUID-keyed entry-history
event alongside the Shopping state effect. TC-05 owns the single save and final
invariant check. Event IDs are caller supplied, stable, and tied to the causal
command, Product, source List, and source Entry. Update and List Create/Rename
do not fabricate events not required by the authority contract.

Focused save-failure injection proves List insertion, Entry insertion,
resolution, revision, and history changes all roll back together. A malformed
prepared effect set is rejected and rolled back before durable success. Unknown
or unreconciled results cannot be reported as committed. No target method has
an independent save or compatibility fallback.

## One-Way Compatibility Output

`ProductStateCompatibilityAdapter` is a bounded TC-08 read/derivation boundary.
After an eligible authoritative command result, it queries only the exact target
List and Entry UUIDs and emits deterministic legacy-facing membership data:

| Target state | Output |
|---|---|
| Needed exact entry | `presentNeeded`, legacy entry check `false` |
| Resolved exact entry | `presentResolved`, legacy entry check `true` |
| Exact one-list removal | `absent`, no entry check value |

The adapter never scans for a first/default/selected list and never writes to a
legacy or target model. Because Product-level `isCompleted` cannot represent
independent state in multiple named lists, its compatibility value is always
unavailable (`nil`) rather than fabricated. Counters expose target reads and
emissions; legacy reads, legacy writes, and reverse synchronization remain
zero. There is no reverse API and no production target consumer activation.

## Deterministic and Privacy-Safe Diagnostics

The encodable diagnostic contains only command/request/authoritative UUIDs,
bounded operation/outcome/failure/durability enums, before/after List revisions,
required event count, and a durable-success Boolean. It contains no Product or
List name, barcode, note, image, coordinates, account identifier, path, source
row, attachment, credential, raw persistence record, or raw error. Equivalent
clean fixtures produce identical state, outcomes, compatibility values,
revisions, event IDs, and diagnostics.

## Focused Qualification

Both authoritative runs used the iPhone 17 Pro iOS 26.5 simulator with separate
clean DerivedData roots and result bundles. Focused fixtures used named,
isolated, in-memory V4 configurations with deterministic UUIDs/timestamps and
no application-default, protected source, migration-candidate, or user store
URL.

| Run | Result | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| Focused A | 16 passed | 0 | 0 | 0 |
| Focused B | 16 passed | 0 | 0 | 0 |

The focused suite covers write/operation gates; Create/Rename identity,
revision, no-op, and stale behavior; archive-purpose rejection; Add identity,
fields, revision, event, and compatibility output; exact existing-Needed no-op;
explicit Reopen; Entry update/no-op; approved resolution reasons; one-list
Remove/retry; duplicate ambiguity and serialized uniqueness; non-terminal
Session protection; atomic save-failure rollback; deterministic one-way
compatibility; privacy-safe diagnostics; equivalent-fixture repeatability; and
static absence of List lifecycle, startup activation, reverse sync, or default
store construction.

Development preflights were used only for defect discovery and are not counted
as qualification evidence.

## Regression and Build Matrix

| Gate | Result | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| Affected command/transaction/repository/list/history/Catalog/migration/startup bundle | 314 passed | 0 | 0 | 0 |
| Exact six-suite Phase 1 gate | 49 passed | 0 | 0 | 0 |
| Complete unfiltered `WayTaskTests` | 539 passed | 0 | 0 | 0 |
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

The affected qualification included the new suite; command pipeline, TC-05
transaction, repositories, invariant validation, transitions, persistence graph,
T-10 Product Command Authority, characterization/support, Shopping UX, Product
deletion, Add/Catalog persistence and compatibility, legacy Product creation,
Catalog migration/personalization, T-06/T-07/T-08 migration, T-09/startup
resilience and repair, schema migration, and Sentry stability suites. All
authoritative qualification runs passed on their first execution.

Xcode emitted the existing Sentry XCFramework identity/dependency-analysis
note. The committed Phase 1 startup-repair baseline remained the expected
long-running performance test and passed in both Phase 1 and complete-target
runs. No new compiler error, warning source, dependency, or build setting was
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
| TC-05 transaction coordinator | `3ae8e4aadd9e427de50cdca0d20fe7037a5cdb546043d63f9dcd9f3c9d3d264a` | Unchanged |
| TC-07 repositories | `e549cd17859e9eac584a493e3b2654fb000d59cd2d6bf6d4a191bb11094d5262` | Unchanged |
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
| T-10 focused tests | `9447478c6658b52e77fba644bbf73aa537c13fa16d46a75aa5275e7b6c661682` | Unchanged |
| T-06 evidence | `f803d6c30e37c1777953383f25ad7a93c560909a9a1d09f655e39fcab5625383` | Unchanged |
| T-07 evidence | `afc64b50be550223df3b5dad29957b7c7c560bb2dea36ad70726a0882174aa1e` | Unchanged |
| T-08 evidence | `78680732e834dd588bc7a51c02e7b6591951f77c9b21cb60ed6ab434c077b129` | Unchanged |
| T-09 evidence | `4fcfb535f959032064ea7cf4601afaf6a8189bf75da2cc45be630b56e22f8bd5` | Unchanged |
| T-10 evidence | `a44553f2ac95b26d9b4de2a83ba958f8a5489968ac1354d78249e65caa32b0e1` | Unchanged |

Committed T-01 through T-05 evidence remained exact:

```text
d9f62bb63a5510633425d4bf055f2e911b4011f76ccd2eb36f421d550291410b  T-01
f39525267de1902c07a3d2c3f44ae26483b220ca5646789638981a589ef01dc3  T-02
c2338f096f9132351095e484cc17feb495a8c9c62e7444f81b551e79509a9bb5  T-03
86ecf19cf81b32913ca3dcfc5d90b5384150dcd5a214b3021c745ea20746ede2  T-04
43fda677a9fdc546341173db6f491d6f134db1ac62e0181a727b9d8233455d10  T-05
```

Final T-11 implementation/test hashes before evidence creation:

```text
f60370efa34561812e14cb0a79f0a97cbcefdd6d6a358770db2500230abe5c3a  ShoppingListService.swift
1ad6040d128a5303e9ec9bde0cfb9887186590dcc7b576286d3a5c169f27a3a4  WayTask/ProductState/Application/ProductStateCommandCoordinator.swift
b87704f97c2abde73b2dda0c426a51f7cb47e4f5c0f3e627dffd75ed39c3f14c  WayTask/ProductState/Persistence/ProductStateCompatibilityAdapter.swift
df2eaee4b41302a16cab6501d6d295b11e3907a5f0faf01205670e6cf109d51f  WayTaskTests/ProductState/ProductStateNamedListEntryCommandAuthorityTests.swift
```

The authorized T-11 extensions intentionally change the T-10 final hashes for
TC-04 and `ShoppingListService.swift`. The other protected T-10 implementation
paths remain exact: Add Product coordinator
`e11ffae04689771361c8f3575e5f263389def81e140cbfb60787b341db40c50d`,
Catalog Product persistence
`ae00814765cb6d8dda338182f40a5758269f675f5acac42c4efac0df698705c3`,
and TC-07 repositories
`e549cd17859e9eac584a493e3b2654fb000d59cd2d6bf6d4a191bb11094d5262`.

Static and repository audits prove:

- `HEAD`, `main`, and `origin/main` remain
  `d83d4559b42b0cf93acb2539c5dc3068dfd66d7d`;
- the diff contains only the four T-11 implementation/test paths plus this
  evidence document;
- V3 remains `currentSchema`; V4 remains target-only and inactive;
- no startup, application-root, UI, ViewModel, or other production consumer
  references the new authority or target-only adapters;
- no List Remove/Restore/Close/Delete lifecycle operation or policy exists;
- no reverse compatibility API, legacy write, target write-back, global list
  scan, name/barcode identity inference, implicit Reopen, purchase inference,
  Product tombstone, candidate promotion, or source replacement API was added;
- no independent save, default-store construction, SQLite metadata probe,
  `fatalError`, or protected source/candidate store access exists in T-11;
- no schema, migration, startup, project, package, localization, asset, Map,
  Camera, notification, AI, Catalog repository, Product Knowledge repository,
  network, telemetry, or Sentry change exists;
- `project.pbxproj` and all protected T-06 through T-10 paths outside the exact
  authorized TC-04/`ShoppingListService` extensions are identical to `HEAD`;
- `git diff --check` passes.

## Cleanup and Review Rollback

All focused/regression fixtures were isolated in-memory containers or
suite-owned simulator-temporary fixtures. No application-default, protected
source, or migration-candidate store was opened by T-11 code or tests. After
result extraction, every enumerated `WT033A-T11-*` DerivedData directory,
result bundle, temporary store, sidecar, cloned package, log attachment, and
build product was deleted. Repository and `/private/tmp` searches confirm that
no T-11-owned temporary artifact, `.xcresult`, or DerivedData directory remains.

Before commit, review rollback is source-only: restore
`ShoppingListService.swift` and
`WayTask/ProductState/Application/ProductStateCommandCoordinator.swift` to
`HEAD`; delete
`WayTask/ProductState/Persistence/ProductStateCompatibilityAdapter.swift`,
`WayTaskTests/ProductState/ProductStateNamedListEntryCommandAuthorityTests.swift`,
and this evidence document. This removes the uncalled forward-compatible
authority/adapters without changing committed V3 behavior or any retained
T-06–T-10 migration, startup, Product command, or target-data declaration.

## Terminal Decision

T-11 COMPLETE — READY FOR REVIEW
