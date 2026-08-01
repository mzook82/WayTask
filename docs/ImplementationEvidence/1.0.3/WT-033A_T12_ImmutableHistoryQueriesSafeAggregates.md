# WT-033A T-12 — Immutable History Queries and Safe Aggregates

## Terminal Decision

T-12 COMPLETE — READY FOR REVIEW

## Starting State and Authority

Execution began on `main` at
`0ba9cfdac4c68c2e101d0777ace6c3f3e214dd29`. The working tree was clean,
`HEAD`, `main`, and `origin/main` were identical, and the contiguous T-01
through T-11 implementation commits were present. No commit was created by
T-12.

The controlling S-02 row is:

> T-12 | Complete immutable history queries and safe aggregate derivation |
> TC-06, TC-10; `ShoppingMemoryService.swift`; Catalog personalization;
> history tests | Causal command events remain immutable and Product-UUID
> keyed; read projections/aggregates use named provenance; no purchase
> inference; legacy aggregate isolated; retry no duplicates | Disable
> event-derived consumers; retain target events/history without legacy
> reactivation | D-06–D-07, D-30–D-31, D-35–D-36

The execution instruction matched that authority. D-07 makes retention
unambiguous: v1.0.3 retains local history without automatic expiry; physical
privacy erasure remains separately unapproved and out of scope.

## Final Footprint

Only the following T-12-authorized paths changed or were added:

- new TC-06 history slice:
  `WayTask/ProductState/Application/ProductStateQueries.swift`;
- T-12 read-only Shopping Memory extension:
  `ShoppingMemoryService.swift`;
- T-12 Catalog-personalization history input and named provenance:
  `WayTask/ProductCatalog/ProductCatalogPersonalization.swift`;
- focused history qualification:
  `WayTaskTests/ProductState/ProductStateImmutableHistoryQueriesTests.swift`;
- this evidence document.

TC-10 `ProductHistory.swift` already contains the co-approved legacy aggregate
and target immutable-event declarations and was sufficient without change.
File-system synchronization compiled both new Swift files automatically.
`project.pbxproj`, schema, migration, startup, package, localization, assets,
UI, ViewModels, Map, Camera, notification, AI, network, telemetry, and Sentry
files did not change.

## Immutable Causal-Event Query Boundary

`ProductStateHistoryQueryBoundary` accepts one exact Product UUID and delegates
only to the scoped `HistoryRepository` read. Persistence rows are immediately
copied into immutable value snapshots. The boundary exposes no SwiftData
container/context, default-store construction, save, insert, delete, repair,
normalization, staging, or mutation operation.

Each projection preserves the authorized stable fields:

- event and Product UUID;
- named meaning plus the retained raw bounded vocabulary value;
- explicit resolution reason or Session final outcome;
- exact source List, Entry, Session, line, and causal command UUIDs when
  present;
- occurrence timestamp;
- immutable display-snapshot UUID;
- named and retained provenance;
- an explicit aggregate-contribution disposition.

Canonical ordering is occurrence time, event UUID, then a deterministic
identity-only tie breaker. `oldestFirst` and `newestFirst` are exact reversals
of that canonical sequence. Equivalent repository enumeration produces an
identical projection.

Query evaluation does not mutate committed events. Tests snapshot persisted
rows before and after queries and prove that the in-memory context has no
changes. Product identity remains the exact Product UUID and is never derived
from a name, barcode, Catalog text, List title, display snapshot, or order.

## Retry, Replay, and Deduplication

All retained rows remain visible in the immutable projection. Duplicate event
UUIDs are labeled `duplicateEventIdentity`; different event UUIDs repeating the
same exact causal command identity are labeled `duplicateCausalReplay`.
Aggregate contribution is accepted at most once per event/cause.

Native user-command causal identity includes Product UUID, command UUID,
meaning/reason, exact source List UUID, and exact Entry UUID where required.
Native Finish causal identity additionally includes Session UUID, line UUID,
explicit final outcome, and the exact source List/Entry UUIDs. Missing or
malformed causal identity is retained as unsupported evidence and contributes
no semantic aggregate. Equivalent replay and reopen queries therefore create
neither events nor duplicate aggregate contribution.

## Named Provenance and Legacy Isolation

History projections distinguish:

- `nativeUserCommand`;
- `nativeSessionFinish`;
- `legacyMigration`;
- `retainedLegacyAggregate`;
- `unsupported`.

Provenance counts are deterministic and separately reported. Legacy migration
events are retained and counted only as migration evidence; they are not
promoted into native user/Finish meanings. Legacy `ProductHistory` aggregate
rows remain separate `ProductStateLegacyHistoryAggregateEvidence` values with
their original observation count, dates, interval, completion-compatible
timestamp, and optional already-proven Product UUID. No native event is
fabricated from a legacy row.

Legacy aggregate evidence is never linked by name or barcode. Shopping Memory
accepts it only when an exact proven Product UUID equals the requested Product
UUID; unlinked or different-Product evidence is explicitly rejected.

## Retention and Bounded Queries

The explicit policy is `retainAllNoAutomaticExpiryV103`. A positive query
limit bounds only returned rows. The boundary reports retained, returned, and
omitted counts, and derives its aggregate from all retained rows for the exact
Product. It performs no deletion, expiry, rewrite, repair, or compaction.
Invalid limits fail deterministically without a repository write or fallback.

## Safe Aggregate Derivation and Purchase Boundary

Aggregate derivation is side-effect free and preserves unknown/unsupported
evidence explicitly. It separately counts native user commands, native Finish
events, migration evidence, supported need/list/Product meanings, Session
outcomes, duplicates, and unsupported evidence.

Purchase is never inferred from acquisition, `needAdded`, entry resolution,
collection, list membership/removal, Product lifecycle, display interaction,
name, barcode, Catalog match, legacy flags, or legacy aggregate data. A
confirmed purchase contributes only from an exact `sessionOutcome/purchased`
event with `sessionFinish` provenance and complete command, source List,
source Entry, Session, and line UUIDs. User-command `purchased`, legacy
completion evidence, incomplete Finish identity, and unsupported rows retain
evidence but contribute zero confirmed purchases.

Catalog personalization uses only exact native Product-to-Catalog identity and
the safe `needAdded` count/date as a non-purchase selection signal. Conflicting
exact Product/Catalog identities are rejected. Replay uses conservative maximum
evidence rather than addition, so a duplicate input cannot increase ranking.
Legacy aggregates remain a normalized-name compatibility record with
`retainedLegacyAggregate` provenance, no Catalog identity, and no native event
authority. Native and legacy profile provenance remains visible even when a
read profile encounters both.

## Shopping Memory and Catalog Inactivity

`ShoppingMemoryService.targetHistoryMemory` consumes only the read-only query
protocol and separately carries exact-linked legacy evidence. An unavailable
or invalid native query propagates failure and does not reactivate legacy
history as fallback authority. The existing V3 Shopping Memory writer remains
unchanged for current behavior; the target method performs no write.

`ProductCatalogTargetHistoryBuilder` produces bounded, deterministically
ordered, provenance-aware input records. It mutates no Product, Catalog, List,
Entry, Session, or History state. Existing legacy Catalog-personalization
callers retain their behavior through the default
`legacyCompatibilityObservation` provenance.

Static reference scans prove no startup, `WayTaskApp`, `ContentView`,
`ProductListView`, or other production target consumer constructs
`ProductStateHistoryQueryBoundary`. The new event-derived paths remain
disabled as required by S-02.

## Diagnostics and Privacy

Diagnostics are Codable value records limited to Product UUID, bounded outcome
and failure enums, retention policy, provenance enums, and aggregate/input/
returned/rejected/duplicate counts. Repository errors map to
`repositoryReadFailed`; raw errors are not retained.

Focused privacy tests encode diagnostics containing private sentinel names and
Catalog display text and prove those values and exact Catalog identity are
absent. No diagnostic contains Product/List names, barcodes, notes, images,
coordinates, account identifiers, file paths, raw rows, attachments,
credentials, raw errors, or private Catalog display text.

## Focused Qualification

Both authoritative runs used the iPhone 17 Pro iOS 26.5 simulator with
separate clean DerivedData and result-bundle roots. Fixtures used named,
isolated, in-memory V4 configurations and deterministic UUIDs/timestamps; no
application-default, protected source, migration candidate, or user-store URL
was opened.

| Run | Result | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| Focused A | 18 passed | 0 | 0 | 0 |
| Focused B | 18 passed | 0 | 0 | 0 |

The suite covers exact immutable fields, Product-UUID scoping, canonical
ordering, bounded/no-expiry retention, event-ID and causal-replay deduplication,
named provenance, Finish purchase identity, unsupported evidence, equivalent
enumeration, read failure, Shopping Memory legacy isolation, Catalog exact
identity, deterministic bounds/replay/conflict handling, diagnostics privacy,
production inactivity, no default-store access, and absence of the complete
T-13 boundary.

Development preflights were used only for defect discovery and are not counted
as qualification evidence.

## Regression and Build Matrix

| Gate | Result | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| Affected history/Catalog/Shopping Memory/persistence/command/transaction/migration/startup bundle | 335 passed | 0 | 0 | 0 |
| Exact six-suite Phase 1 gate | 49 passed | 0 | 0 | 0 |
| Complete unfiltered `WayTaskTests` | 557 passed | 0 | 0 | 0 |
| Generic iOS unsigned Debug build | Succeeded, exit 0 | — | — | — |
| Generic iOS unsigned Release build | Succeeded, exit 0 | — | — | — |

The exact Phase 1 selectors were
`ProductStateCharacterizationSupportSelfTests`,
`ProductStateDomainCharacterizationTests`,
`ProductStatePersistenceCharacterizationTests`,
`ProductStateConsumerCharacterizationTests`,
`ProductStateDiagnosticsCharacterizationTests`, and
`ProductStatePerformanceBaselineTests`. The full result reports six tests
collecting performance metrics. No existing test, fixture, expectation,
profile, threshold, or performance baseline changed.

The affected qualification included T-12; TC-03/TC-04 commands; TC-05
transactions; TC-07 repositories; invariants and transitions; persistence
graph and characterization; T-10 Product commands; T-11 List/Entry commands;
Shopping UX; Product deletion; Add/Catalog persistence and compatibility;
legacy Product creation; Catalog migration/personalization; T-06/T-07/T-08
migration; T-09/startup resilience and repair; schema migration; and Sentry
stability.

The complete target emitted two transient parallel-simulator worker launch
diagnostics. Xcode recovered without a rerun: the command exited zero and the
authoritative result bundle reports all 557 tests passed with zero failed or
skipped tests. These were infrastructure retry diagnostics, not assertions or
repository regressions.

## Hash, Static, and Scope Audit

Protected/final SHA-256 values before evidence creation:

| Artifact | SHA-256 | Result |
|---|---|---|
| S-02 roadmap | `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361` | Unchanged |
| `project.pbxproj` | `9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f` | Unchanged |
| `Package.resolved` | `42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244` | Unchanged |
| `WayTaskSchema.swift` | `90841edae9796af551c453f6a3bcb65737db975a61a05505ccdb3bcef0e8f9b8` | Unchanged |
| TC-13 migration | `1c79711332281f4b24af81696c7242784596bcdaa8b92f35fb17b9ca757418e8` | Unchanged |
| TC-14 startup | `f1729caf5c33cc7de19b0cd751ae0fdb6480190a4773ec8bf37e589fcd59b849` | Unchanged |
| TC-05 transactions | `3ae8e4aadd9e427de50cdca0d20fe7037a5cdb546043d63f9dcd9f3c9d3d264a` | Unchanged |
| TC-07 repositories | `e549cd17859e9eac584a493e3b2654fb000d59cd2d6bf6d4a191bb11094d5262` | Unchanged |
| TC-10 `ProductHistory.swift` | `57dd2b13e4e68d2292e5b45f5fe090f3b64344fe4c777a91f19cc47961e8da8c` | Unchanged |
| TC-11 `ShoppingSession.swift` | `86c66430467c2b8b15a104c11cf0394709d4767a2e3ba7d1fbd2e711222eb8d5` | Unchanged |
| `WayTaskApp.swift` | `5a460b45f2922c096ee1a81ddd7da27fe13df49c50d632d1b5c91d568bb04251` | Unchanged |
| `ContentView.swift` | `2d30601201a2eac39673128cdac0f19907a7fe3ef7fc3e93c826d2943a3f70fc` | Unchanged |
| T-06 tests | `702f6e7690b954a2dc93862d3f7c53254d4fb5ab1cebde5b488f78740e1d139a` | Unchanged |
| T-07 tests | `e9d6a7d305b57cfb565f46431f87ec66fadd92eff0971ecd5006b4bc36a64d97` | Unchanged |
| T-08 tests | `385d7f4e48f58668b756138cddd2791044d180163dbe42cd8521b3ae2c8b8e5a` | Unchanged |
| T-09 tests | `02b1eacf1f76941eac6c438b88f5f5d931b8a4ff405353d37393a32b34cd76c2` | Unchanged |
| T-10 tests | `9447478c6658b52e77fba644bbf73aa537c13fa16d46a75aa5275e7b6c661682` | Unchanged |
| T-11 tests | `df2eaee4b41302a16cab6501d6d295b11e3907a5f0faf01205670e6cf109d51f` | Unchanged |
| T-06 evidence | `f803d6c30e37c1777953383f25ad7a93c560909a9a1d09f655e39fcab5625383` | Unchanged |
| T-07 evidence | `afc64b50be550223df3b5dad29957b7c7c560bb2dea36ad70726a0882174aa1e` | Unchanged |
| T-08 evidence | `78680732e834dd588bc7a51c02e7b6591951f77c9b21cb60ed6ab434c077b129` | Unchanged |
| T-09 evidence | `4fcfb535f959032064ea7cf4601afaf6a8189bf75da2cc45be630b56e22f8bd5` | Unchanged |
| T-10 evidence | `a44553f2ac95b26d9b4de2a83ba958f8a5489968ac1354d78249e65caa32b0e1` | Unchanged |
| T-11 evidence | `7b5674dc721281d549b4da542c735da5986ab84db53a5db1fddf559c57177335` | Unchanged |

Final T-12 implementation/test SHA-256 values before evidence creation:

```text
20660f1608a5ca4d499c09062fa31c9a0d5f6363ce8df08913d3364fafb5a3a6  ShoppingMemoryService.swift
656546d6a770ee5658d6aaf71f34ff450ff4215da6a068aae95981800a2cbb1d  WayTask/ProductCatalog/ProductCatalogPersonalization.swift
0721d8f2828fde4b55ac3dc62ef421204b1edfd850fdc1575af91c94bc576eda  WayTask/ProductState/Application/ProductStateQueries.swift
c5a15b9bb62c5ab4999774390d561e2024dbd932aeca7cd1c66d79793c4fc35e  WayTaskTests/ProductState/ProductStateImmutableHistoryQueriesTests.swift
```

The pre-T-12 hashes for the two authorized extensions were
`2e6af1e5e99e85a1a43c613a30d2da504f96c1a7eea876cc31bf3785a464fb6a`
for `ShoppingMemoryService.swift` and
`cc0969559cf22755c2984ce83c32b31de184b874df90b84931745869c986ec8a`
for Catalog personalization. Existing Catalog-personalization tests remain
unchanged at
`dbc8562995fbfb3e70f4bc6a1e70557addf30f3118b78f2bb044f854a3a3a5d4`.

Static and repository audits prove:

- `HEAD`, `main`, and `origin/main` remain
  `0ba9cfdac4c68c2e101d0777ace6c3f3e214dd29`;
- V3 remains `currentSchema`; V4 remains target-only and inactive;
- no startup, migration, schema, candidate promotion, source replacement,
  production write cutover, or target UI activation exists;
- no complete T-13 query/projection boundary or revision cache exists;
- no committed causal event mutation, deletion, repair, or replacement exists;
- no Product/name/barcode/List-name identity inference exists in the target
  history boundary;
- no legacy aggregate creates a native event or indistinguishable native
  authority;
- no purchase is inferred outside exact, complete native Finish evidence;
- no new repository, default-store access, write path, dependency, network,
  telemetry, Sentry, localization, or asset change exists;
- all protected T-06 through T-11 paths are byte-identical to `HEAD`;
- `git diff --check` and untracked-file whitespace checks pass.

## Cleanup and Review Rollback

After extracting the authoritative totals, every enumerated
`/private/tmp/WT033A-T12-*` DerivedData directory, result bundle, preflight
root, cloned package, build product, attachment, and log was deleted. A final
exact-prefix search reports no remaining T-12 temporary root. Repository
searches report no `.xcresult`, DerivedData, SQLite/store sidecar, or other
task-owned test artifact. No test or production path opened the
application-default, protected migration source, or candidate store.

Before commit, review rollback is source-only: restore
`ShoppingMemoryService.swift` and
`WayTask/ProductCatalog/ProductCatalogPersonalization.swift` to `HEAD`; delete
`WayTask/ProductState/Application/ProductStateQueries.swift`,
`WayTaskTests/ProductState/ProductStateImmutableHistoryQueriesTests.swift`, and
this evidence document. The target paths are not called by production, so this
removes the T-12 read boundary without changing V3 behavior or deleting any
retained target event/history data.
