# WT-033A T-13 — Query and Projection Boundary Evidence

## Starting Repository and Authority Gate

Execution began on `main` at
`be42530066c7b2c2b3ba5b12691c7971fc0652b4`. The worktree was clean,
`HEAD`, `main`, and `origin/main` were identical, and the contiguous T-01
through T-12 commits were present. No commit was created by T-13.

The governing S-02 SHA-256 was
`49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361`.
The exact S-02 assignment was:

> T-13 | Add complete side-effect-free query/projection boundary and optional
> revision cache | New TC-06; projection tests | All S-01 projections exist;
> no mutation; scoped queries; list/plan/Map/reminder parity; stale revision
> explicit; no global compatibility scan | Disable cache and rebuild directly;
> remove target presentation callers if needed | D-01, D-08, D-10–D-12,
> D-19–D-23, D-33

This matched the execution instruction. S-02 makes the revision cache
optional and explicitly permits direct rebuild as the rollback/correctness
path. No cache was activated.

## Final Footprint

Only the following T-13-authorized paths changed or were added:

- the existing TC-06 history slice was extended into the complete boundary in
  `WayTask/ProductState/Application/ProductStateQueries.swift`;
- focused qualification was added in
  `WayTaskTests/ProductState/ProductStateQueryProjectionBoundaryTests.swift`;
- this evidence document.

No schema, migration, startup, command authority, transaction coordinator,
repository, application root, UI, ViewModel, Map, Camera, notification,
Session service, Shopping Plan consumer, Catalog repository, Product Knowledge
repository, package, project, localization, asset, network, telemetry, or
Sentry path changed.

## Projection Boundary

TC-06 now exposes every S-01 required projection while preserving the already
qualified T-12 immutable Product History boundary:

| Projection group | T-13 boundary |
|---|---|
| Product | Product Library, Removed Products, exact Product Acquisition Match, Catalog-linked presentation |
| List | exact Named List, exact Product/List Membership Action, Plan Input |
| Plan | Plan Status with source/list/input dependency validation |
| Session | Active Session Lookup, frozen Session Snapshot, Finish Review |
| History/Knowledge | immutable Product History retained from T-12; versioned Product Knowledge Search evidence |
| Shared contexts | Map Shopping Context and Notification Opportunity from exact list, plan, or Session ownership |
| Routing/evidence | Notification Route Validation and exact Saved-Location Evidence |
| Decision support | scoped Discovery/Shopping Context and estimated Store Recommendations |
| Recovery | migration version/invariant/exception-ledger recovery projection |

Top-level projections carry a common immutable metadata envelope containing
the exact owner scope, source revisions/snapshot identity where applicable,
freshness, named provenance, explicit omissions, and cache policy. Every
Product reference is an exact persisted or caller-declared Product UUID.
Names, barcodes, Catalog text, notes, and snapshots are never used to invent a
Product relationship.

The boundary imports Foundation only. It receives the existing read-capable
repository responsibilities and exposes no persistence context, container,
transaction coordinator, save, insert, stage, delete, repair, normalization,
compatibility fallback, OS scheduling, network, or telemetry operation.
Repository rows are copied immediately into immutable values.

## Deterministic Ordering and Reads

Canonical ordering is explicit and total:

- Product Library uses creation time then Product UUID;
- Removed Products use removal time descending then Product UUID;
- list entries use list-owned sort order, Entry UUID, then a stable value-only
  tie breaker for corrupt duplicate identity evidence;
- active Sessions use start time, Session UUID, then frozen-state tie values;
- Session lines/stops use snapshot sort order, exact UUID, then frozen values;
- migration exceptions use ordinal, UUID, then safe evidence values;
- Product Knowledge candidates use confidence descending, evidence UUID, then
  snapshot/provenance values;
- store estimates use covered Product count descending, confidence descending,
  Store ID, evidence time, then exact covered Product IDs;
- acquisition evidence, omissions, location links, publication versions, and
  stale reasons are canonicalized before projection.

The same committed state and declared inputs therefore produce the same value
projection regardless of repository enumeration order. Equivalent reads do
not alter source rows. The real in-memory SwiftData qualification snapshots
Product/list/entry state and row counts before and after library, named-list,
and membership queries; `ModelContext.hasChanges` remains false.

## Optional, Empty, and Unresolved Semantics

- Empty Product Library, Removed Products, Active Session, Product Knowledge,
  Store Recommendation, and entry collections return successful empty
  projections.
- Optional list membership scope, Catalog publication evidence, Product UUID
  on pre-acquisition Knowledge browse, Product/list/entry links, snapshot
  values, and resolution/Session evidence remain optional; they are not
  synthesized.
- A missing singular Product, List, Session, or required plan owner returns
  explicit unavailable metadata.
- Multiple authoritative matches return an explicit ambiguous result or
  unavailable authority; no first-row selection is authoritative.
- Missing/removed/ambiguous Products, malformed entries, unresolved Session
  lines, invalid snapshot references, explicit plan exclusions, and unproven
  saved-location links remain visible through named qualification/omission
  records.
- Finish Review supplies no default final outcome. Every missing or invalid
  line remains explicit and prevents a Ready result.
- Repository failure returns unavailable and never falls back to V3
  compatibility state.

## Revision, Staleness, and Cache Semantics

List reads publish the durable current revision and compare an optional
expected revision. Session reads publish the durable Session revision and
frozen snapshot UUID. Revision mismatches return a value marked Stale rather
than silently treating frozen input as current.

Plan Status validates all declared dependencies: source List identity,
source revision, exact included Entry IDs, and declared input fingerprint.
Map and reminder projections retain the same owner/revision or Session
snapshot identity. Notification routing revalidates the exact current
List/Plan/Session owner and routes only current active context; stale payloads
produce an explained safe Shopping route and missing authority is suppressed.

`ProductStateProjectionCachePolicy.disabledDirectRebuild` is the only T-13
cache policy. Each request reads and rebuilds directly; qualification proves a
second identical request performs a second repository read and returns the
same projection. There is no cache store, cache write, invalidation callback,
revision advancement, or cache-backed fallback.

## Scoped Queries and Projection Parity

Persistence reads use only:

- the explicitly safe Active/Removed Product Library browse scope;
- exact Product UUID, exact Catalog identity, or exact barcode acquisition
  evidence;
- exact List UUID, `(List UUID, Product UUID)`, or `(Entry UUID, List UUID)`;
- exact Session UUID/lifecycle and exact Session-owned lines, stops, and
  exceptions;
- exact Product UUID for immutable history.

TC-06 never calls the repository's all-list Product-entry read and never scans
legacy compatibility items. External Catalog, Product Knowledge,
saved-location, Store, plan, and recovery data enter only as explicit versioned
evidence values; no T-14 consumer is called or activated.

One snapshot-built List parity projection proves:

```text
Named List Needed Entry IDs
  = Plan Input eligible IDs + named exclusion IDs
  = Map list-context Entry IDs
  = non-Session Notification Opportunity Entry IDs
```

The qualification fixture contains valid, explicitly excluded, and unresolved
Product references and proves all Needed Entry IDs remain accounted for.
Session Map/reminder context uses only frozen Session lines.

## Qualification

Development preflights were used only for defect discovery and are not counted
below. After behavior and expectations were frozen, every authoritative run
passed on its first execution on an iPhone 17 Pro simulator running iOS 26.5:

| Gate | Passed | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| Focused projection qualification, run 1 | 19 | 0 | 0 | 0 |
| Focused projection qualification, run 2 | 19 | 0 | 0 | 0 |
| Affected query/history/repository/command/consumer/performance/Map/Catalog/Knowledge/Shopping bundle | 360 | 0 | 0 | 0 |
| Exact six-suite WT-032B Phase 1 gate | 49 | 0 | 0 | 0 |
| Complete unfiltered `WayTaskTests` | 576 | 0 | 0 | 0 |
| Generic iOS unsigned Debug build | Succeeded | — | — | — |
| Generic iOS unsigned Release build | Succeeded | — | — | — |

The affected and complete result bundles each report six tests collecting
performance metrics. The exact Phase 1 selectors were
`ProductStateCharacterizationSupportSelfTests`,
`ProductStateDomainCharacterizationTests`,
`ProductStatePersistenceCharacterizationTests`,
`ProductStateConsumerCharacterizationTests`,
`ProductStateDiagnosticsCharacterizationTests`, and
`ProductStatePerformanceBaselineTests`.

No existing test, fixture, expectation, threshold, or performance profile
changed. Xcode repeated the committed unused-value warning at
`ProductCatalogMigrationTests.swift:136` and the existing Sentry build-phase
note; neither protected file changed and no new T-13 warning was introduced.

## Protected Hash Audit

Protected/final SHA-256 values before evidence creation:

| Artifact | SHA-256 | Result |
|---|---|---|
| S-00 Authority Discovery | `16e336f54a4cb644465f1836e9d97410bffc1044de4322581398ab3f8517b920` | Unchanged |
| S-01 Authority Specification | `2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c` | Unchanged |
| S-02 Technical Roadmap | `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361` | Unchanged |
| `project.pbxproj` | `9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f` | Unchanged |
| `Package.resolved` | `42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244` | Unchanged |
| `WayTaskSchema.swift` | `90841edae9796af551c453f6a3bcb65737db975a61a05505ccdb3bcef0e8f9b8` | Unchanged |
| TC-13 migration | `1c79711332281f4b24af81696c7242784596bcdaa8b92f35fb17b9ca757418e8` | Unchanged |
| TC-14 startup | `f1729caf5c33cc7de19b0cd751ae0fdb6480190a4773ec8bf37e589fcd59b849` | Unchanged |
| TC-05 transaction coordinator | `3ae8e4aadd9e427de50cdca0d20fe7037a5cdb546043d63f9dcd9f3c9d3d264a` | Unchanged |
| TC-07 repositories | `e549cd17859e9eac584a493e3b2654fb000d59cd2d6bf6d4a191bb11094d5262` | Unchanged |
| TC-10 `ProductHistory.swift` | `57dd2b13e4e68d2292e5b45f5fe090f3b64344fe4c777a91f19cc47961e8da8c` | Unchanged |
| TC-11 `ShoppingSession.swift` | `86c66430467c2b8b15a104c11cf0394709d4767a2e3ba7d1fbd2e711222eb8d5` | Unchanged |
| `WayTaskApp.swift` | `5a460b45f2922c096ee1a81ddd7da27fe13df49c50d632d1b5c91d568bb04251` | Unchanged |
| `ContentView.swift` | `2d30601201a2eac39673128cdac0f19907a7fe3ef7fc3e93c826d2943a3f70fc` | Unchanged |
| T-12 `ShoppingMemoryService.swift` | `20660f1608a5ca4d499c09062fa31c9a0d5f6363ce8df08913d3364fafb5a3a6` | Unchanged |
| T-12 Catalog personalization | `656546d6a770ee5658d6aaf71f34ff450ff4215da6a068aae95981800a2cbb1d` | Unchanged |
| T-12 focused tests | `c5a15b9bb62c5ab4999774390d561e2024dbd932aeca7cd1c66d79793c4fc35e` | Unchanged |

All committed focused-test hashes from T-06 through T-11 also remain exact:

```text
702f6e7690b954a2dc93862d3f7c53254d4fb5ab1cebde5b488f78740e1d139a  T-06
e9d6a7d305b57cfb565f46431f87ec66fadd92eff0971ecd5006b4bc36a64d97  T-07
385d7f4e48f58668b756138cddd2791044d180163dbe42cd8521b3ae2c8b8e5a  T-08
02b1eacf1f76941eac6c438b88f5f5d931b8a4ff405353d37393a32b34cd76c2  T-09
9447478c6658b52e77fba644bbf73aa537c13fa16d46a75aa5275e7b6c661682  T-10
df2eaee4b41302a16cab6501d6d295b11e3907a5f0faf01205670e6cf109d51f  T-11
```

Committed evidence hashes from T-06 through T-12 remain exact:

```text
f803d6c30e37c1777953383f25ad7a93c560909a9a1d09f655e39fcab5625383  T-06
afc64b50be550223df3b5dad29957b7c7c560bb2dea36ad70726a0882174aa1e  T-07
78680732e834dd588bc7a51c02e7b6591951f77c9b21cb60ed6ab434c077b129  T-08
4fcfb535f959032064ea7cf4601afaf6a8189bf75da2cc45be630b56e22f8bd5  T-09
a44553f2ac95b26d9b4de2a83ba958f8a5489968ac1354d78249e65caa32b0e1  T-10
7b5674dc721281d549b4da542c735da5986ab84db53a5db1fddf559c57177335  T-11
8839e642b1d6cd41684c75919b213035bd9f4fbdd6d1d47063979f9bf41c7e51  T-12
```

Final T-13 implementation/test hashes before evidence creation:

```text
92e10ebd622314f026ccd83f92b88f7d863a5a21c532246c9969fae9c97b5b37  WayTask/ProductState/Application/ProductStateQueries.swift
df2956e2b542267c36e4c2aa4722b47ae6fab14ae792b84eed529a560689fc1b  WayTaskTests/ProductState/ProductStateQueryProjectionBoundaryTests.swift
```

The TC-06 path intentionally extends its T-12 history-only hash
`0721d8f2828fde4b55ac3dc62ef421204b1edfd850fdc1575af91c94bc576eda`.
No other T-12 implementation/test path changed.

## Scope and Inactivity Audit

Static and repository audits prove:

- `HEAD`, `main`, and `origin/main` remain
  `be42530066c7b2c2b3ba5b12691c7971fc0652b4`;
- the final source/test/evidence footprint is exactly the three paths listed
  above;
- `project.pbxproj` has no diff and synchronized groups discovered both Swift
  changes;
- V3 remains `currentSchema`; V4 remains the inactive target schema;
- no production file constructs `ProductStateQueryBoundary`; only the new
  qualification suite does;
- no Shopping Plan, Home, Shopping UI, Map, Camera, notification, Session, or
  other T-14-or-later consumer was converted or activated;
- the complete query boundary contains no SwiftData import, `ModelContext`,
  default-store access, transaction coordinator, persistence save/delete,
  repository stage call, compatibility item, checked/completed authority, or
  global Product-entry scan;
- Product History remains the unchanged T-12 Product-UUID boundary and no
  purchase is inferred by T-13;
- no reverse compatibility synchronization, Product identity inference,
  Purchase inference, schema/startup/migration change, dependency, project,
  localization, asset, network, telemetry, or Sentry change exists;
- `git diff --check` and the untracked-test trailing-whitespace audit pass.

## Cleanup and Review Rollback

After totals and hashes were extracted, the exact 16 enumerated
`/private/tmp/WT033A-T13-*` DerivedData roots, result bundles, package checkout,
build products, logs, and preflight artifacts were deleted. Final repository
and `/private/tmp` searches report no T-13 result bundle, DerivedData, SQLite
store/sidecar, or task-owned test artifact. No qualification opened the
application-default, protected migration-source, or migration-candidate store.

Before commit, review rollback is source-only: restore the TC-06 query file to
`HEAD`, then delete the focused test and this evidence document. No production
caller exists, so rollback changes no V3 behavior, target data, migration,
startup, command authority, or consumer.

## Terminal Decision

T-13 COMPLETE — READY FOR REVIEW
