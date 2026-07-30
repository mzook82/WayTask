# WT-033A — Product State Technical Implementation Specification

**Step:** S-02  
**Status:** Proposed technical roadmap; pending approval  
**Repository branch:** `main`  
**Repository baseline:** `a20b83c570157038cb85b0b3efb49a24cf8ccc50`  
**Specification date:** 2026-07-30  
**Implementation authorization:** None  
**Change boundary:** This document only

## Governing Contract

This document translates the approved Product State Authority Contract into an implementation roadmap. It defines production component responsibilities, dependency directions, repository roles, command/query/transaction pipelines, migration and cutover stages, expected file ownership, validation, and rollback boundaries.

It does not contain Swift, method signatures, concrete API types, schema declarations, migration code, tests, project changes, or implementation authorization.

The governing inputs are:

1. `docs/Audits/1.0.3/WT-030_ArchitectureSummary.md`
2. `docs/Audits/1.0.3/WT-030A_ProductStateUXAudit.md`
3. `docs/ImplementationPlans/1.0.3/WT-031A_ProductStateImplementationPlan.md`
4. `docs/ImplementationSpecifications/1.0.3/WT-032A_ProductState_Phase0DecisionSpecification.md`
5. `docs/ImplementationSpecifications/1.0.3/WT-032B_ProductState_Phase1ImplementationSpecification.md`
6. `docs/Specifications/WT-033A_ProductStateAuthorityDiscovery.md`
7. `docs/Specifications/WT-033A_ProductStateAuthoritySpecification.md`

The S-01 Authority Specification is controlling for target ownership, command semantics, query semantics, transactions, invariants, integrations, and compatibility. Current behavior from S-00 and WT-032B is baseline evidence only. No roadmap choice may redefine WT-032A D-01 through D-37.

---

## 1. Executive Summary

### 1.1 Implementation Goals

WT-033A implementation must replace the current distributed Product State writers and readers with:

- a platform-neutral Product State domain vocabulary and invariant boundary;
- one application command route for every authoritative mutation;
- repository boundaries that isolate persistence mechanics;
- one transaction coordinator for cross-lifecycle commits;
- side-effect-free scoped query projections;
- durable list revision and immutable plan/Session source identity;
- conservative, recoverable semantic migration;
- one-way temporary compatibility output;
- post-commit infrastructure reconciliation;
- a single released authority cutover with zero legacy-authority readers and writers.

The implementation must preserve stable Product, list, entry, Session, Catalog, Product Knowledge, and supported snapshot identities while intentionally replacing the current mixed-authority behavior characterized in Phase 1.

### 1.2 Implementation Constraints

All later implementation execution must preserve these constraints:

1. S-01 ownership and invariants are fixed.
2. Product State cannot ship partially converted.
3. No production View or ViewModel may write lifecycle persistence directly.
4. No integration may mutate Product State except through a named application command.
5. Repositories do not make lifecycle decisions.
6. Queries do not mutate, repair, backfill, schedule, or save.
7. One command uses one transaction scope; participating repositories may not save independently.
8. Session and Finish integration must be co-reviewed with WT-031B and use one shared line/outcome authority.
9. Catalog and Product Knowledge remain independent.
10. Migration is staged, deterministic, idempotent, fail-closed, and original-store recoverable.
11. Compatibility has one-way transitional behavior only and zero authority at cutover.
12. Physical legacy storage removal is not part of this implementation.
13. Existing Phase 1 evidence remains the pre-change baseline.
14. No Xcode project edit is expected for files placed under the file-system-synchronized `WayTask` and `WayTaskTests` roots.

### 1.3 Engineering Assumptions

The roadmap assumes:

- the current shipped persistence baseline remains `WayTaskSchemaV3`, with V1 and V2 frozen for migration;
- the application and unit-test roots remain file-system-synchronized;
- the implementation introduces the next versioned Product State persistence representation only in its authorized schema step;
- every mutation participating in one local transaction can share one persistence transaction scope;
- command execution can be serialized sufficiently to enforce uniqueness and expected revisions on every supported iOS version;
- a protected original store and sidecars can be retained while migration runs against a separately validated candidate/working copy;
- target query projections can be built from scoped repository reads without scanning every compatibility item;
- the Phase 1 Functional and Reference profiles remain available for regression and performance comparison;
- no UI-test target currently exists, so accessibility evidence uses unit/presentation tests plus named manual device checks unless a separate project-change authorization creates one;
- full Shopping Session lifecycle mechanics remain a WT-031B dependency, while Product State owns the shared source-entry, line-outcome, and Finish contract;
- exact method signatures, protocol syntax, field encodings, and framework-specific concurrency primitives are chosen only inside later authorized execution steps and may not weaken this roadmap.

If transaction serialization, candidate-store migration, or WT-031B compatibility cannot be proven, implementation stops before writable target state.

---

## 2. Target Components

### 2.1 Component Inventory

Paths marked **proposed** do not exist at the S-02 baseline. They identify expected responsibility homes, not Swift declarations or APIs.

| ID | Component / expected home | Purpose | Responsibility | Dependencies | Ownership |
|---|---|---|---|---|---|
| TC-01 | **Proposed:** `WayTask/ProductState/Domain/ProductStateDomain.swift` | Shared target vocabulary | Product Library state, entry state/reasons, Session outcome vocabulary, history-event meanings, revision/snapshot identity concepts | S-01 §§2–4; D-01–D-23 | Domain |
| TC-02 | **Proposed:** `WayTask/ProductState/Domain/ProductStateInvariantValidator.swift` | Central invariant evaluation | Validate lifecycle ownership, identity, uniqueness, revisions, active-Session protection, complete Finish outcomes, and compatibility exclusion | TC-01; repository snapshots | Domain |
| TC-03 | **Proposed:** `WayTask/ProductState/Application/ProductStateCommands.swift` | Describe application command categories and semantic results | Represent named Product, Library, list, entry, Session integration, and saved-location intents without persistence behavior | TC-01; S-01 §4 | Application |
| TC-04 | **Proposed:** `WayTask/ProductState/Application/ProductStateCommandCoordinator.swift` | Single application mutation entry | Gate commands, load current state, invoke domain validation, coordinate transactions, return committed/conflict/failure outcomes | TC-02, TC-03, TC-05, repositories | Application |
| TC-05 | **Proposed:** `WayTask/ProductState/Application/ProductStateTransactionCoordinator.swift` | Own local transaction scope | Provide one transaction to all participating repositories, enforce revision/idempotency rules, commit once, and emit committed metadata | Repository implementations; persistence container | Application/Persistence boundary |
| TC-06 | **Proposed:** `WayTask/ProductState/Application/ProductStateQueries.swift` | Build read-only projections | Library, removed, acquisition match, named list, membership action, plan input/status, Session, Finish review, history, Map, reminder, discovery, store, and recovery projections | Repositories; TC-01 | Application read boundary |
| TC-07 | **Proposed:** `WayTask/ProductState/Persistence/ProductStateRepositories.swift` | Product, Shopping, History, Session, Plan, and Saved Location persistence adapters | Scoped loads and transaction-bound persistence; no business-policy decisions; no independent save | Current/next schema; TC-05 | Persistence |
| TC-08 | **Proposed:** `WayTask/ProductState/Persistence/ProductStateCompatibilityAdapter.swift` | Temporary one-way compatibility output | Derive permitted legacy values from committed target state before cutover; count reads/writes; prohibit reverse synchronization | TC-04, TC-05; legacy models | Transitional persistence |
| TC-09 | `WayTask/Models.swift` | Current Product/list/location models and future target persistence graph | Preserve Product UUID/tombstone/Catalog snapshots; represent approved list revision and entry lifecycle in the authorized schema step; demote compatibility models | TC-01; migration | Persistence model |
| TC-10 | `ProductHistory.swift` | Current aggregate and future target history persistence | Preserve legacy aggregate and support immutable Product-UUID events without inferring purchase | TC-01; History Repository; migration | History persistence |
| TC-11 | `ShoppingSession.swift` | Current Session persistence and WT-031B integration point | Represent shared source-list/revision, immutable lines/snapshots, provisional collection, and final outcome concepts only under the co-approved Session design | WT-031B; TC-01; migration | Session persistence |
| TC-12 | `WayTask/Persistence/WayTaskSchema.swift` | Versioned schema and model container composition | Keep V2/V3 frozen; add the authorized next schema/stage; include target graph only after schema review | TC-09–TC-11; migration design | Persistence composition |
| TC-13 | **Proposed:** `WayTask/Persistence/WayTaskProductStateMigration.swift` | One semantic migration owner | Inventory, protected candidate-store flow, deterministic mapping, duplicate aliasing, Session/history/archive/location handling, exception ledger, validation, completion marker | V1/V2/V3; next schema; Phase 1 fixtures | Migration |
| TC-14 | `WayTask/Persistence/WayTaskStartupPersistence.swift` | Startup store and recovery gate | Run physical and semantic migration before writable UI; expose durable/degraded/failure status; prevent empty/ephemeral false success | TC-12, TC-13 | Persistence startup |
| TC-15 | `ShoppingListService.swift` and `ProductLibraryDeletionService` | Current broad mutation services | Become application command adapters or be reduced behind TC-04; no independent compatibility/UI policy; all-list removal and active-Session protection | TC-04–TC-07 | Application compatibility during conversion |
| TC-16 | `ShoppingSessionService.swift` | Current Session mutation service | Move to normalized Session command ownership, explicit conflicts, collection isolation, and shared Finish transaction | TC-04–TC-07; WT-031B | Session application |
| TC-17 | `ShoppingMemoryService.swift` | Current aggregate history service | Consume committed history events and derive safe aggregates; retain labeled legacy reads only during transition | History Repository; TC-08 | History application |
| TC-18 | **Proposed:** `WayTask/ProductState/Infrastructure/ProductStatePostCommitReconciler.swift` | Reconcile external side effects | Receive committed identities/revisions and idempotently refresh reminders, geofences, navigation invalidation, and privacy-safe diagnostics | TC-04, TC-05, TC-06; platform adapters | Infrastructure |
| TC-19 | `WayTask/Persistence/AddProductSaveCoordinator.swift` and `CatalogProductPersistenceService.swift` | Current acquisition persistence | Route candidates through Product commands; preserve exact Catalog identity; return restore-required without restoring | TC-04; Catalog Repository | Application/Persistence integration |
| TC-20 | Product Catalog files under `WayTask/ProductCatalog/` | Catalog Truth | Continue versioned Catalog loading/search/validation/redirect ownership; expose read-only inputs | Existing Catalog components | Catalog infrastructure |
| TC-21 | Product Knowledge files under `WayTask/ProductKnowledge/` plus `ProductKnowledgeService.swift` | Recognition knowledge | Continue bundled and learned knowledge ownership; supply candidates without Product lifecycle writes | Existing Product Knowledge components | Knowledge infrastructure |
| TC-22 | `WayTask/AppStateManager.swift` | Presentation/navigation state | Hold selected list, active route, and non-authoritative UI state; remove runtime revision authority; validate notification routes through queries | TC-06, TC-18 | Presentation application state |
| TC-23 | `ProductListView.swift`, `WayTask/HomeView.swift`, `WayTask/ContentView.swift` | Product/Home/root presentation | Render projections, submit commands, remove direct persistence and backfill, expose explicit restore/removal/list scope | TC-04, TC-06 | Presentation |
| TC-24 | `WayTask/ShoppingWorkspaceView.swift` | Shopping/plan/Session presentation | Render named-list and Session projections; submit entry/plan/Session commands; no direct checks/completion/save | TC-04, TC-06, TC-16 | Presentation |
| TC-25 | `MapViewModel.swift`, `WayTask/MainMapView.swift`, `WayTask/LocationDetailView.swift` | Map/location presentation | Consume explicit list/plan/Session/location projections; remove global compatibility fallback and lifecycle toggles | TC-06; Saved Location Repository | Presentation |
| TC-26 | `WayTask/LocationManager.swift`, `GeofenceNotificationService.swift` | Location/notification infrastructure | Consume revisioned reminder projection; reconcile registrations post-commit; validate stale payloads and routes | TC-06, TC-18; WT-031B | Infrastructure |
| TC-27 | Camera and recognition files | Acquisition presentation/infrastructure | Produce reviewed evidence, submit Product commands, show exact created/already-active/restore-required outcome | TC-04; TC-19–TC-21 | Presentation/Infrastructure |
| TC-28 | Plan/discovery/store services: `ShoppingTripService.swift`, `ShoppingIntentMatcher.swift`, `ShoppingContext.swift`, `DecisionEngine.swift`, `DiscoverViewModel.swift`, `StoreSearchService.swift`, `StoreRankingService.swift`, `BuyingOptionsService.swift` | Derived decision support | Consume scoped query/plan input, retain uncertainty, never filter by legacy completion or write lifecycle state | TC-06; Catalog/Knowledge/Location reads | Application read consumers |
| TC-29 | Existing `WayTask/SentryReportingService.swift` and startup diagnostics | Privacy-safe operational evidence | Report allowlisted command/migration/projection categories, counts, timing, durability mode, and failure class only | TC-13, TC-14, TC-18 | Infrastructure |

### 2.2 Component Construction Rules

- Domain components contain no SwiftUI, SwiftData, Core Location, notification, network, Catalog loader, or Sentry dependency.
- Application components operate through repository responsibilities and never receive a presentation-owned persistence context.
- Repository implementations receive transaction scope from the coordinator and never decide user intent.
- Infrastructure receives committed envelopes or read projections; it never opens a Product State write transaction.
- Migration is not implemented as a View, query side effect, Catalog repair, or compatibility backfill.
- Existing services may be adapted incrementally internally, but by cutover they cannot remain alternative authorities.
- New files under `WayTask/` and `WayTaskTests/` are expected to be discovered by synchronized groups without `project.pbxproj` edits. Any discovery failure is a stop condition, not permission to change the project silently.

---

## 3. Authority Layers

### 3.1 Layer Responsibilities

| Layer | Owns | May communicate with | Must not communicate with directly |
|---|---|---|---|
| Presentation | Rendering, accessibility state, local drafts, user intent capture, navigation | Application commands and queries; platform presentation adapters | SwiftData/`ModelContext`, repositories, migration, compatibility writer, direct OS reminder mutation |
| Application | Command orchestration, query orchestration, transaction ownership, conflict/result mapping, post-commit dispatch | Domain, repository responsibilities, transaction coordinator, infrastructure ports | View state mutation, direct Catalog publication, unscoped legacy fallback |
| Domain | Lifecycle vocabulary, command policy, invariants, revision/outcome rules, immutable projection semantics | Pure domain values supplied by Application | SwiftData, SwiftUI, Core Location, notifications, network, Sentry, files |
| Persistence | Repository implementations, versioned models, store/container, migration storage, transaction-bound reads/writes | Application transaction scope, Domain semantics, startup/migration | Presentation, OS notifications, user-intent decisions |
| Infrastructure | Catalog/Knowledge loaders, Camera/AI providers, Map/store providers, notifications/geofences, diagnostics | Application queries/commands, post-commit reconciler, platform frameworks | Direct Product State writes, migration interpretation, independent list/session filtering |

### 3.2 Allowed Communication Directions

```text
Presentation
    ├── command intent ──> Application Command Coordinator
    └── read request ────> Application Query Boundary

Application Command Coordinator
    ├── validates with ──> Domain
    ├── coordinates ────> Transaction Coordinator
    ├── reads/writes ───> Repository Responsibilities
    └── after commit ───> Post-Commit Reconciler

Application Query Boundary
    ├── reads ──────────> Repository Responsibilities
    └── builds ─────────> Read-Only Projections

Persistence Implementations
    └── conform to ─────> Domain ownership and transaction rules

Infrastructure
    ├── supplies evidence/results ──> Application
    └── consumes projections/envelopes <── Application

Startup Bootstrap
    └── gates Application availability through Migration/Recovery
```

No reverse arrow grants authority. In particular:

- Presentation cannot skip Application and write Persistence.
- Infrastructure cannot skip Application and change Domain state.
- Persistence cannot infer commands from stored values.
- Queries cannot call commands.
- Post-commit reconciliation cannot reopen the committed transaction or compensate by changing Product State.
- Catalog and Product Knowledge can supply evidence but cannot call repository writes directly.

### 3.3 Composition Boundary

Application startup composes:

- the target model container and durability status;
- repository implementations over that container;
- one command coordinator and transaction coordinator;
- one query boundary;
- read-only Catalog and Product Knowledge dependencies;
- post-commit infrastructure adapters.

Presentation receives only the command/query/application state needed for its surface. Migration/recovery status is established before writable presentation is enabled.

---

## 4. Repository Design

“Repository” in this specification means a persistence responsibility boundary. It does not require one protocol or file per entity and does not authorize method signatures. The combined implementation may live in `ProductStateRepositories.swift` where transaction sharing benefits from one narrow boundary.

### 4.1 Product Repository

Responsibilities:

- load Product by stable UUID and exact approved acquisition identity;
- read active and removed Library scopes;
- persist Product creation, user edits, tombstone, and restore inside a supplied transaction;
- preserve user fields, images, Catalog references/snapshots, timestamps, and identity;
- expose planning-input version/fingerprint data where declared;
- never write list, Session, history, Catalog Truth, or Product Knowledge.

It must not:

- restore from barcode/Catalog/AI evidence without an explicit Restore command;
- match identity by unapproved name/category similarity;
- independently save or publish success.

### 4.2 Shopping Repository

Responsibilities:

- load named lists and exact entries by list/Product/entry identity;
- provide scoped Needed and Resolved reads;
- enforce transaction-level uniqueness and expected list revision with the coordinator;
- persist entry membership, quantity/unit/note/order, resolution, and durable list revision;
- locate all editable entries affected by Product Library removal;
- identify entries protected by non-terminal Sessions through the Session boundary;
- never consult compatibility completion as target authority.

It must not:

- mutate another list for a one-list command;
- silently reopen a Resolved entry;
- create compatibility records as decision owners;
- save outside the command transaction.

### 4.3 History Repository

Responsibilities:

- append immutable, idempotent history events within the causal command transaction;
- load Product-UUID event timelines and bounded aggregate inputs;
- preserve legacy aggregate rows separately and label their provenance;
- prevent duplicate event identity during retry;
- retain events across list removal, Library removal/restore, and Catalog change.

It must not:

- infer purchase from checked, completed, collected, finished header, Catalog, recommendation, or legacy archive state;
- attach legacy aggregate rows by name or barcode alone;
- accept arbitrary presentation-originated history writes.

### 4.4 Session Repository

Responsibilities:

- load exact non-terminal Session/recovery candidates and revisions;
- persist source list/revision, immutable line/Product/entry snapshots, provisional execution state, final outcomes, and lifecycle;
- validate protected Product/entry references for Product/list commands;
- participate in the shared Finish transaction;
- preserve legacy Session evidence and unresolved migrated lines.

It must not:

- silently choose the first active Session;
- rewrite snapshots from current Product/Catalog/list state;
- treat collection as purchase;
- finalize independently of list/history reconciliation.

The detailed Session representation and full lifecycle remain co-owned by the approved WT-031B implementation specification.

### 4.5 Catalog Repository

Responsibilities:

- load and search published Catalog concepts, taxonomy, statuses, and redirects;
- resolve exact canonical Catalog identity;
- supply current metadata and saved-snapshot comparison inputs;
- remain read-only with respect to user Product State.

It must not:

- insert, restore, remove, resolve, collect, or purchase a user Product;
- overwrite user Product snapshots except through a separately approved Product metadata command;
- infer user identity from Catalog lifecycle.

Existing Product Catalog repositories/services remain the preferred implementation unless a measured requirement demands a narrower adapter.

### 4.6 Product Knowledge Repository

Responsibilities:

- load bundled knowledge and bounded learned recognition metadata;
- provide search/recognition candidates with provenance;
- persist only approved learned-knowledge state;
- remain independent of Product Library, list, Session, and history.

It must not:

- become the user Product repository;
- resolve or purchase list/Session state;
- use recognition confidence as an authoritative identity mutation.

The current Product Knowledge repository boundary is retained.

### 4.7 Supporting Repository Responsibilities

Plan persistence/cache responsibility, if used, stores only rebuildable plan identity, source revision, exact entry IDs, exclusions, and recommendation snapshots. It never owns list membership.

Saved Location persistence owns location/store-note data only. It may expose exact links to projection builders but never writes Product/list/Session lifecycle.

All repository implementations:

- share the transaction scope supplied by TC-05 for one command;
- separate read-only query use from transaction-bound mutation use;
- return data or persistence failures without mapping them to user success;
- do not emit OS side effects or telemetry containing private content;
- remain inaccessible to presentation code.

---

## 5. Command Pipeline

### 5.1 Pipeline Stages

1. **Intent capture:** Presentation or an approved integration submits one named command with exact scope and user confirmation.
2. **Input normalization:** Application validates command identity, scope, provenance, deterministic time, and required expected revision.
3. **Availability gate:** Startup/migration status confirms durable target state is writable. Degraded or migration-incomplete modes reject durability-sensitive commands truthfully.
4. **Authoritative load:** Repositories load the minimum Product/list/entry/Session/history state required by the command.
5. **Domain validation:** TC-02 checks lifecycle preconditions, exact identity, active-Session protection, allowed outcome, uniqueness, and revision.
6. **Conflict classification:** Stale revision, existing Resolved entry, active Session, duplicate retry, tombstone, ambiguity, or missing record becomes an explicit semantic result.
7. **Transaction begin:** TC-05 opens one local transaction scope and binds all participating repositories to it.
8. **Authoritative mutation:** Owning repositories stage only the state authorized by the command.
9. **Revision/event effects:** Affected list revisions and required immutable events are staged once. Optional target-derived compatibility output is staged last inside the same transaction while permitted.
10. **Invariant validation:** The complete staged result is checked before commit.
11. **Single commit:** TC-05 commits once. Repository-local saves are prohibited.
12. **Committed result:** TC-04 emits success only after the commit and includes authoritative identities/revisions required by projections and post-commit work.
13. **Projection refresh:** Revision-keyed caches are invalidated or superseded using committed metadata. Queries rebuild lazily or immediately according to consumer need.
14. **Infrastructure reconciliation:** TC-18 idempotently reconciles reminders, geofences, navigation availability, and privacy-safe diagnostics.
15. **Completion presentation:** The initiator renders the committed result or explicit conflict/failure. It performs no follow-up lifecycle write.

### 5.2 Failure Pipeline

| Failure point | Required response |
|---|---|
| Invalid/ambiguous input | Reject before transaction; preserve state; require user resolution where applicable |
| Migration/durability unavailable | Block writable target action; show truthful recovery/degraded state |
| Identity not found | Return exact missing context; never fabricate by text match |
| Stale revision | Return current owner/revision information sufficient to refresh; do not auto-retry a changed user intent |
| Active-Session conflict | Return exact Session conflict and approved Resume/Finish/Abandon/Cancel route |
| Idempotent retry | Return prior/no-op semantic result; no revision or history drift |
| Persistence failure before commit | Roll back staged changes and expose no success |
| Unknown commit result | Reconcile by stable command/event identity before retry; never issue a blind duplicate command |
| Post-commit infrastructure failure | Keep business commit; record safe retry work keyed by committed identity/revision |
| Projection rebuild failure | Preserve authoritative state; expose unavailable/stale projection without legacy fallback |

### 5.3 Pipeline Ownership

- Presentation owns intent and result display.
- Application owns sequencing and semantic failure mapping.
- Domain owns validation rules.
- Transaction Coordinator owns atomicity.
- Repositories own persistence mechanics only.
- Query boundary owns projection refresh.
- Infrastructure owns idempotent post-commit effects.

---

## 6. Query Pipeline

### 6.1 Projection Creation

1. Consumer requests a named projection with explicit Product/list/plan/Session/location scope.
2. Query boundary checks any cache using authoritative identity plus revision/fingerprint.
3. Repositories load a consistent read snapshot of only the required records.
4. Projection builder maps domain state into immutable read values.
5. The builder validates source identity, revision, exact entry set, exclusions, and snapshot provenance.
6. Invalid or missing references become explicit unavailable/exception elements rather than silent omission.
7. The complete projection is returned and may be cached by identity/revision.

### 6.2 Caching

- Caching is optional and never required for correctness.
- Cache keys include every authoritative identity/revision/fingerprint on which the projection depends.
- A cache may be reused only while those inputs match.
- A cache miss or invalidation causes a rebuild, not a legacy fallback.
- Cached projections are immutable.
- Cached plan/store recommendations retain uncertainty and source scope.
- Image or large display data is excluded from state-only caches unless the visible projection requires it.
- No cache writes Product State or advances a revision.

### 6.3 Consistency and Revision Validation

- Named-list projections read one list revision.
- Plan input and Plan status compare exact source list/revision and declared Product input fingerprints.
- Session projections read the frozen Session revision/snapshot, not live Product/list values.
- Map and reminder projections carry the owner/revision from their list, plan, or Session source.
- Notification routing revalidates the current owner/revision before navigation.
- A revision mismatch returns Stale, Unavailable, or a safe current destination; it never reconstructs authority from frozen names.
- Read consistency mechanisms may vary by repository implementation, but a projection must not combine records from incompatible revisions.

### 6.4 No-Mutation Rule

A query may not:

- call a command;
- create, insert, delete, save, normalize, repair, or backfill;
- update last-access time in Product State;
- schedule a notification or geofence;
- initialize transport or log private Product content;
- restore a tombstone;
- create a missing Product/list relationship;
- derive target state from `ShoppingItem.isCompleted`, entry `isChecked`, or legacy UUID arrays after cutover.

---

## 7. Transaction Coordinator

### 7.1 Responsibilities

TC-05 must:

- serialize conflicting commands for the same owned scope;
- establish one transaction context for all participating repositories;
- load or revalidate expected identities/revisions inside that scope;
- provide stable command identity for retry reconciliation;
- stage mutations, revision increments, history events, and temporary compatibility output;
- validate final invariants;
- commit once;
- roll back the entire staged mutation on failure;
- return committed identity/revision metadata;
- never invoke external side effects inside the transaction.

### 7.2 Atomic Boundaries

| Command family | Participating responsibilities |
|---|---|
| Product create/edit | Product; declared planning-input version when applicable |
| Restore | Product plus History |
| Add/resolve/reopen/remove/update entry | Shopping plus History |
| Remove Product from Library | Product, Shopping across all editable lists, Session precondition, History, Plan supersession metadata |
| Start Session | Shopping source validation, Plan snapshot read, Session |
| Collect/undo | Session only |
| Finish | Session, Shopping, History, Plan supersession metadata |
| Abandon | Session only |
| Semantic migration completion | Migration state, all target repositories, exception ledger, final invariant marker |

Temporary compatibility output, if enabled, participates in the same command transaction but remains target-derived and non-authoritative.

### 7.3 Conflict Handling

Conflicts are semantic results, not generic save retries:

- expected list or Session revision mismatch;
- exact entry already Needed;
- exact entry Resolved and requires Reopen;
- Product already Active;
- Product Removed and requires Restore;
- non-terminal Session protects Product/entry;
- another non-terminal Session conflicts with Start;
- ambiguous acquisition identity;
- unresolved migration exception;
- persistence mode is non-durable or migration incomplete.

The coordinator never resolves these conflicts by silently selecting a record, reopening, restoring, discarding progress, changing scope, or falling back to compatibility.

### 7.4 Idempotency

- Every mutating command has stable identity.
- Every required history event is uniquely tied to the causal command and subject.
- Repeating a committed command returns the committed/no-op result.
- Repeating an uncommitted failed command may retry after current revision validation.
- Unknown commit result is resolved by command/event identity lookup before another mutation.
- A retry never creates a duplicate entry, event, Session, revision increment, or external registration.

### 7.5 Rollback

- In-memory staged values are invalid after rollback and must be reloaded before presentation.
- No repository may commit early.
- No post-commit envelope is emitted after rollback.
- Projection caches are not advanced on failure.
- External effects are not used to compensate for a failed business transaction.
- Failure diagnostics contain command category, scope type, stage, and durability mode only; no private values.

The implementation step for TC-05 must prove the selected SwiftData/concurrency mechanism on every supported iOS version before other command writers are converted.

---

## 8. Migration Strategy

### 8.1 Execution Order

The production migration path is:

1. block writable target UI;
2. inventory current schema, store/sidecars, record counts, stable IDs, and free-space requirements;
3. create and validate a recoverable original-store boundary;
4. create a candidate/working-copy store with all required sidecars;
5. perform physical versioned-schema migration only on the candidate;
6. initialize semantic migration identity, version, and exception recording;
7. migrate Product identity, tombstones, Catalog snapshots, named lists, entries, explicit list revision baselines, and exact relationships;
8. merge exact duplicates and record aliases;
9. migrate legacy Session evidence, Product History aggregates, Completed/Recent archive rows, saved-location evidence, and tombstone contradictions;
10. generate unresolved exception records without guessing or deleting;
11. validate counts, stable IDs, uniqueness, references, revisions, snapshots, Sessions, history, tombstones, and exceptions;
12. rerun semantic stages or validators to prove idempotency;
13. mark semantic migration complete in the same durable boundary as final validation;
14. promote the validated candidate through the approved store replacement boundary;
15. reopen using the target model and validate again;
16. enable target writable UI only after success.

Exact filesystem operations and schema declarations are specified and proven in their authorized execution steps. They may not weaken the protected-candidate flow.

### 8.2 Deterministic Semantic Rules

Migration consumes D-24 through D-32 exactly:

- entry existence owns membership;
- unchecked entry becomes Needed;
- checked entry becomes Resolved `legacyUnknown`;
- compatibility completion never overrides an entry or creates purchase/membership;
- exact duplicate groups use the approved survivor, quantity, order, state, alias, and audit rules;
- only an exact stored Product UUID repairs a relationship;
- zero/multiple legacy Session mappings remain unresolved lines;
- all legacy non-terminal Sessions remain recovery candidates;
- Completed/Recent become read-only archive evidence;
- legacy history aggregates remain unchanged and non-authoritative without a proven UUID link;
- tombstones remain Removed and contradictory live references become exceptions.

### 8.3 Compatibility Adapter

The adapter has three implementation modes:

| Mode | Allowed behavior |
|---|---|
| Migration/characterization | Read legacy values for deterministic conversion and Phase 1 verification |
| Internal target validation | Produce target-derived compatibility output inside the target transaction; count access; prohibit reverse writes |
| Cutover | No authoritative reader or direct writer; physical data read-only and inaccessible to runtime decisions |

The adapter:

- never selects a list;
- never restores/removes a Product;
- never resolves/reopens an entry;
- never assigns a Session outcome;
- never writes history;
- never supplies fallback values to target queries.

### 8.4 Legacy Retirement and Cutover

Retirement proceeds by consumer group:

1. target migration and repositories;
2. Product/list commands;
3. target projections and plan;
4. Product/Home/Shopping presentation;
5. scanner/Catalog/Knowledge acquisition;
6. Map/location/discovery/store consumers;
7. Session/Finish;
8. notifications/geofences;
9. static zero-reader/zero-writer enforcement;
10. single release cutover.

Every internal stage may coexist only behind a non-released development boundary. No partially converted authority set is releasable.

### 8.5 Rollback Boundaries

- Before candidate promotion: discard only the owned candidate and retry from the untouched protected original.
- After candidate promotion but before target user writes: restore the validated original through the approved recovery flow.
- After target user writes: never reopen with a legacy-authority binary; use a forward-compatible disabled/fix build.
- Backup restoration after target writes is a separate explicit destructive recovery with a later-data-loss warning.
- Compatibility retention is not reverse migration.
- Physical compatibility removal occurs only in a later approved schema release.

### 8.6 Migration Stop Conditions

Stop before writable target UI when:

- original store/sidecar protection cannot be proven;
- disk space is insufficient for the protected candidate strategy;
- schema version or migration identity is unknown;
- counts or stable IDs do not reconcile;
- uniqueness or revision invariants fail;
- a tombstone is restored;
- a legacy ambiguity would require text matching or fabricated truth;
- an unresolved Session line would be silently dropped;
- exception records cannot be preserved;
- second-pass semantic output drifts;
- the target store cannot reopen deterministically;
- rollback drill fails.

---

## 9. Implementation Order

### 9.1 Phase Summary

| Phase | Steps | Outcome |
|---|---|---|
| A — Foundation | T-00…T-05 | Execution boundary, target domain concepts, persistence graph, repository roles, and proven transaction coordinator |
| B — Migration and startup | T-06…T-09 | Protected candidate-store migration, complete semantic conversion, and fail-closed startup gate |
| C — Domain authority | T-10…T-13 | Product/list/history commands and scoped query projections operate without legacy authority |
| D — Consumer conversion | T-14…T-18 | Plan, acquisition, Product/Home, Shopping, Map/location/discovery/store use target boundaries |
| E — Session and infrastructure | T-19…T-20 | Shared Session/Finish authority and revisioned notification/geofence reconciliation |
| F — Cutover and qualification | T-21 | Zero legacy authority, full qualification, single release cutover |

### 9.2 Execution Steps

Every path below is an expected future path. No file is changed by S-02.

| Step | Goal | Files expected | Acceptance criteria | Rollback strategy | Authority trace |
|---|---|---|---|---|---|
| T-00 | Establish implementation baseline, protected hashes, allowed footprint, toolchain, and WT-031B dependency gate | No production changes; implementation evidence document authorized later | Clean/recorded baseline; Phase 1 suites/builds pass; S-01 hash fixed; no overlapping user work; stop conditions recorded | Documentation/evidence removal only | D-01–D-37; S-01 §§10–12 |
| T-01 | Add pure target vocabulary and invariant validation without persistence or consumer conversion | New TC-01, TC-02; target unit tests under `WayTaskTests/ProductState/` | Domain compiles without UI/SwiftData/infrastructure imports; all state/outcome/invariant cases represented; current app behavior unchanged | Remove new domain/test files | D-01–D-23, D-35–D-37 |
| T-02 | Add the authorized next persistence graph while freezing V1/V2/V3 | `WayTask/Models.swift`, `ProductHistory.swift`, co-approved `ShoppingSession.swift`, `WayTask/Persistence/WayTaskSchema.swift`; schema tests | Prior schemas byte/source unchanged; target graph represents contract; no target UI/writer enabled; current-store characterization still passes | Remove next schema/stage and target-only persistence declarations before any migrated store is produced | D-02, D-06, D-11–D-12, D-24, D-33, D-37 |
| T-03 | Introduce repository responsibility boundary and scoped reads | New TC-07; existing Catalog/Knowledge repositories retained; repository tests | Presentation cannot access repository boundary; scoped Product/list/history/Session reads work; no repository saves independently; Catalog/Knowledge remain separate | Remove new adapter and restore call sites; no data conversion yet | D-01, D-06–D-12, D-22–D-23 |
| T-04 | Introduce command descriptions/coordinator with no production UI caller | New TC-03, TC-04; command validation tests | Every S-01 command category has semantic outcome/conflict coverage; no direct production caller converted; no API reaches legacy fallback | Remove new application files/tests | D-02–D-18, D-22, D-35 |
| T-05 | Prove the transaction coordinator, serialization, rollback, and idempotency mechanism | New TC-05; repository integration tests | One transaction spans required repositories; stale/conflict/save/unknown-result cases are deterministic; no partial save; supported-iOS proof for D-37 | Remove coordinator/integration wiring; no target production writer enabled | D-09, D-11, D-35–D-37 |
| T-06 | Implement protected original/candidate-store and semantic migration foundation | New TC-13; `WayTask/Persistence/WayTaskSchema.swift`; migration support tests | Source store/sidecars unchanged; candidate isolated; stage identity and exception recording deterministic; failed candidate never replaces source | Delete only owned candidate artifacts; reopen protected original | D-24, D-34 |
| T-07 | Migrate Products, lists, entries, revisions, duplicates, exact relationships, and tombstone contradictions | TC-13; TC-09; migration tests/fixtures | UUIDs/snapshots/tombstones preserved; all flag combinations deterministic; exact duplicates merge per D-26; no name/barcode guessing; second pass stable | Discard candidate and retry from protected original | D-15, D-17–D-18, D-24, D-25, D-26, D-27, D-32, D-37 |
| T-08 | Migrate Sessions, history, Completed/Recent archive, saved-location evidence, and exceptions | TC-10, co-approved TC-11, TC-13; migration tests | All Session evidence/candidates retained; collected not promoted; legacy aggregates unchanged; archives read-only; exceptions complete/privacy-safe | Discard candidate; no partial promotion | D-03–D-07, D-19, D-23, D-28–D-32 |
| T-09 | Gate startup on migration completion and truthful durability/recovery state | TC-14; `WayTask/WayTaskApp.swift`, `WayTask/ContentView.swift`; startup resilience tests | Writable target UI unavailable before success; no root-view backfill; empty/in-memory state not reported durable; reopen and rollback drills pass | Forward-compatible startup gate disables target UI; protected original retained | D-24, D-27, D-29, D-32, D-34 |
| T-10 | Convert Product acquisition, edit, Library removal, and Restore to command authority | TC-04–TC-07, TC-10; `ShoppingListService.swift` — `ProductLibraryDeletionService`; TC-19; Product command tests | Explicit create/already-active/restore-required; Restore preserves ID/no lists; all-list removal and active-Session block atomic; required remove/restore events append in the same transaction; no implicit restore | Disable new command callers; forward-compatible target data/events retained | D-06–D-07, D-15–D-18, D-22, D-35 |
| T-11 | Convert list/entry commands, durable revision, uniqueness, history effects, and one-way compatibility output | TC-04–TC-08, TC-10; `ShoppingListService.swift`; list tests | Add/no-op/Reopen semantics, resolve reasons, one-list remove, entry update, revision exactly once, concurrent uniqueness, required entry events in the same transaction, target→legacy only | Disable target callers; retain target entries/events; adapter remains non-authoritative; no reverse sync | D-02, D-06–D-11, D-13, D-19, D-33, D-35, D-37 |
| T-12 | Complete immutable history queries and safe aggregate derivation | TC-06, TC-10; `ShoppingMemoryService.swift`; Catalog personalization; history tests | Causal command events remain immutable and Product-UUID keyed; read projections/aggregates use named provenance; no purchase inference; legacy aggregate isolated; retry no duplicates | Disable event-derived consumers; retain target events/history without legacy reactivation | D-06–D-07, D-30–D-31, D-35–D-36 |
| T-13 | Add complete side-effect-free query/projection boundary and optional revision cache | New TC-06; projection tests | All S-01 projections exist; no mutation; scoped queries; list/plan/Map/reminder parity; stale revision explicit; no global compatibility scan | Disable cache and rebuild directly; remove target presentation callers if needed | D-01, D-08, D-10–D-12, D-19–D-23, D-33 |
| T-14 | Convert Shopping Plan and derived decision/store inputs | `WayTask/AppStateManager.swift`, `ShoppingTripService.swift`, `ShoppingIntentMatcher.swift`, `ShoppingContext.swift`, `DecisionEngine.swift`, `DiscoverViewModel.swift`, `StoreSearchService.swift`, `StoreRankingService.swift`, `BuyingOptionsService.swift`; plan tests | Plan holds list/revision/exact entries/exclusions; staleness deterministic; all decision/store inputs scoped; library-only unrelated change does not stale | Disable target plan presentation internally; no list authority rollback | D-01, D-08, D-11–D-12, D-23, D-33 |
| T-15 | Convert scanner, Camera, Catalog acquisition, and Product Knowledge integration | Camera/recognition files; TC-19–TC-21; scanner/catalog tests | Library-only default; exact outcomes; explicit Restore and separate Add to List; no Catalog/Knowledge lifecycle write; unrelated plan unchanged | Disable converted acquisition surface; target Product records remain valid | D-01, D-17, D-22, D-35 |
| T-16 | Convert Product Library, chooser, Home, and root presentation | `ProductListView.swift`, `WayTask/HomeView.swift`, `WayTask/ContentView.swift`, `WayTask/AppStateManager.swift`; Product/Home/presentation tests | Projections only; named list scope; no lifecycle checkmark; removed surface/Restore; no direct `ModelContext` mutation/backfill; routes exact | Internal feature disable; command/query authority remains intact | D-01, D-08, D-15–D-22, D-33 |
| T-17 | Convert Shopping presentation and plan controls | `WayTask/ShoppingWorkspaceView.swift`; Shopping UX tests | Needed/Resolved/reason semantics; command-only quantity/resolve/reopen/remove; exact list/revision; no `isChecked`/`isCompleted` authority | Disable converted UI internally; preserve target store/commands | D-02, D-08–D-13, D-19–D-20, D-33 |
| T-18 | Convert Map, saved locations, discovery, store recommendations, and reminder input creation | TC-25, TC-28; `WayTask/LocationManager.swift` input boundary; Map/location/consumer tests | Explicit list/plan/Session context; no global fallback; saved-location notes separated; store estimates read-only; parity/exclusions proven | Disable shopping Map/reminder feature internally; preserve domain authority | D-01, D-11–D-13, D-21, D-23, D-33 |
| T-19 | Integrate co-approved normalized Session lifecycle, conflict handling, collection isolation, and atomic Finish | TC-11, TC-16, TC-04–TC-07; Session/Finish tests | Exact source snapshot; no silent reuse; protected entries; all outcomes; Finish one commit; Abandon no list/purchase effect; relaunch stable | Forward-compatible Session feature disable; never reopen with legacy Session writer | D-03–D-05, D-12, D-13, D-14, D-15, D-16, D-28–D-29, D-32, D-36 |
| T-20 | Convert notification/geofence payload validation and post-commit reconciliation | New TC-18; TC-26; `WayTask/AppStateManager.swift`; notification tests | Owner/revision payload; pre-delivery/tap validation; exact route; stale suppression/safe fallback; idempotent disarm/register; no lifecycle mutation | Disable scheduling/actions; keep committed Product State; retry ledger safely | D-11–D-12, D-21, D-23, D-33, D-36 |
| T-21 | Enforce zero legacy authority, run full qualification, and perform the single release cutover | TC-08 removal from runtime access; all changed production/tests/evidence; no physical storage deletion | Legacy reader/writer counters zero; all target suites and regressions pass; Debug/Release builds; migration/recovery/rollback/privacy/a11y/localization/performance gates pass; one coherent authority enabled | Forward-compatible disable/fix build only; explicit protected-backup recovery when approved | D-01–D-37; WT-030A AC-01…AC-47 |

### 9.3 Execution Discipline

- Only one step is authorized at a time.
- Every step records initial/final branch, commit, status, protected hashes, commands, builds/tests, and changed paths.
- A step may touch only its approved expected paths and test/evidence paths.
- Unexpected current behavior is verified against Phase 1 evidence; production is not changed merely to satisfy an assumed expectation.
- Each step stops on schema drift, project drift, unrelated overlap, private data, default-store test access, non-deterministic fixtures, failed rollback, or authority-contract conflict.
- No step after T-09 may enable a target writer unless migration and transaction gates pass.
- T-14 through T-20 are internal conversion stages and are not independently releasable.
- T-21 is the only authority cutover.

---

## 10. Test Strategy

### 10.1 General Rules

For every implementation step:

- add target tests before or with the target behavior;
- run the smallest focused suite twice from clean synthetic state;
- run all directly affected existing suites;
- run the five Phase 1 Product State characterization suites;
- update or retire a current-legacy expectation only when the step intentionally replaces that exact behavior and the change is traceable to D-01…D-37;
- never weaken an unrelated regression to make target work pass;
- use isolated in-memory or working-copy stores, never the application default store;
- retain deterministic IDs/timestamps/order and privacy-safe evidence;
- perform the generic unsigned application build when production compilation changes;
- remove DerivedData, result bundles, stores, sidecars, and attachments after evidence extraction.

### 10.2 Step-by-Step Test Matrix

| Step | Unit tests | Integration tests | Characterization treatment | Required regression |
|---|---|---|---|---|
| T-00 | None new | Baseline full target/build execution | All Phase 1 suites frozen and passing | Complete `WayTaskTests`; generic Debug/Release builds |
| T-01 | Domain vocabulary, allowed/forbidden transitions, all invariant categories | Domain values compile in application/test targets without framework leakage | No current expectation changes | Product State five suites; Product Catalog/Knowledge domain suites |
| T-02 | Target persistence defaults and representation validation | Next-schema container, prior schema freeze, supported reopen | Phase 1 V1/V2/V3 expectations remain unchanged | `WayTaskSchemaMigrationTests`, persistence/resilience suites |
| T-03 | Repository scoping and prohibited independent-save behavior | Shared transaction-scope repository reads/writes against isolated stores | No current behavior retired | Persistence, Catalog repository, Product Knowledge repository suites |
| T-04 | Every command semantic result, precondition, conflict, no-op | Coordinator with fake/isolated repository boundaries; no production caller | No current legacy test changed | Domain characterization and acquisition/list regressions |
| T-05 | Revision conflict, idempotency, event uniqueness, rollback | Cross-repository single-commit and save/unknown-result failure injection | No current expectation changed | Persistence characterization twice; startup resilience |
| T-06 | Migration stage identity, exception categories, source/candidate fingerprints | V1/V2/V3 candidate-store physical migration and failure before promotion | Existing migration characterization remains baseline | Schema migration, support self-tests, startup resilience |
| T-07 | Flag matrix, duplicate merge, aliases, tombstone exception rules | V1/V2/V3 Product/list semantic migration twice; source immutable | Add target migration assertions; retain legacy source fixture expectations | Persistence characterization, deletion/catalog suites |
| T-08 | Session mapping, archive/history/location exception rules | Active/finished/missing-line/multiple-session candidate migration | Retain current source snapshots; add target semantic snapshots | Persistence/domain/consumer characterization; location/session regressions |
| T-09 | Startup state machine and write gate | Successful, interrupted, failed, insufficient/recovery/degraded launches | Diagnostic sequence changes only with explicit target trace | Startup resilience, startup repair, Sentry stability |
| T-10 | Product create/edit/remove/restore transitions and required remove/restore events | All-list removal, active-Session conflict, Catalog/barcode tombstone acquisition, atomic Product/history failure | Retire CB-05/CB-06/CB-07 and KD-07/KD-08 expectations only when target tests pass | Deletion, Catalog persistence/compatibility, legacy creation, history |
| T-11 | Add/no-op/Reopen/resolve/remove/update, revision, uniqueness, events, list isolation | Concurrent retry/save failure, atomic Shopping/history effects, and one-way adapter in isolated store | Retire CB-01…CB-04 and KD-01…KD-04 only for converted target callers | Domain/persistence characterization; Shopping UX; history |
| T-12 | Event projection, provenance, retention, aggregate derivation | Committed command events through history query/personalization boundaries | Retire CB-08/KD-10/KD-11 only when target history proves no overclaim | History, Catalog personalization, persistence characterization |
| T-13 | Every projection, ordering, optional/empty semantics, cache key/staleness | Shopping/plan/Map/reminder ID parity and stale reads | Consumer characterization remains until each consumer converts | Consumer/performance characterization; Map/Catalog/Knowledge |
| T-14 | Plan input/status/stale/exclusion rules | Planner/trip/context/discovery/store pipeline from exact list revision | Replace KD-04/KD-05/KD-12 plan expectations intentionally | Shopping Classification/UX, consumer/performance suites |
| T-15 | Acquisition outcome and confirmation presentation state | Manual/custom/Catalog/barcode/AI-reviewed create/already-active/restore-required | Replace implicit-restore characterization with explicit target assertions | Catalog, Product Knowledge, scanner-adjacent suites |
| T-16 | Product/membership/removed/Home projection logic | Product/Home/chooser command/query flow and exact navigation | Replace Product-card/mixed-reader current assertions for converted surfaces | Domain/consumer; Shopping UX; accessibility/manual checks |
| T-17 | Needed/Resolved/quantity/list action presentation logic | Shopping command/query/plan flow; no direct persistence | Replace checked/completed UI expectations for converted surface | Shopping UX/classification, domain/consumer/performance |
| T-18 | Map/location/store/discovery projection and exclusion rules | Map/list/plan/Session parity; saved-location isolation; no real network/geofence | Replace CB-12/KD-12 only for converted consumers | Map, consumer, classification, location-related suites |
| T-19 | Session start conflict, collect/undo, outcomes, Abandon, Finish mapping | File-backed recovery and single-commit Finish with injected failures | Retire CB-09…CB-11 and KD-06/KD-09 only after target Session suite passes | Domain/persistence/consumer; WT-031B Session suites |
| T-20 | Payload owner/revision validation, route fallback, post-commit retry | Notification/geofence registration with fakes only; no real delivery/region | Replace CB-15 payload authority expectation while retaining legacy parse cases | Diagnostics/consumer, Sentry, location/notification suites |
| T-21 | Static forbidden-reader/writer checks and invariant audit | All target suites together, complete test target, migration/recovery/rollback, two performance runs | Every retired characterization has D-ID and replacement evidence; remaining legacy archive tests labeled | Every repository test; Debug/Release builds; privacy/a11y/localization/manual matrix |

### 10.3 Required New Test Areas

Expected future target test paths under the synchronized `WayTaskTests` root include:

- `WayTaskTests/ProductState/ProductStateTransitionTests.swift`
- `WayTaskTests/ProductState/ListIsolationTests.swift`
- `WayTaskTests/ProductState/ProductStateProjectionParityTests.swift`
- `WayTaskTests/ProductState/ProductStateTransactionTests.swift`
- `WayTaskTests/Persistence/ProductStateSemanticMigrationTests.swift`
- `WayTaskTests/ShoppingSession/SessionOutcomeReconciliationTests.swift`
- `WayTaskTests/Notifications/ProductStateNotificationIntegrationTests.swift`
- `WayTaskTests/Scanner/ProductStateScannerIntegrationTests.swift`

Exact creation is authorized only by the corresponding execution step. Existing tests remain unchanged until a traced target transition requires an intentional expectation update.

Because no UI-test target exists at the S-02 baseline, accessibility/localization validation uses:

- unit/presentation semantics in `WayTaskTests/ShoppingUX/`;
- target projection/command result copy tests;
- named manual English/Hebrew, RTL, Dynamic Type, VoiceOver, Switch Control, hardware keyboard, target-size, non-color, and Reduce Motion evidence.

Creating a UI-test target or modifying `project.pbxproj` requires separate explicit authorization and is not assumed by this roadmap.

### 10.4 Static Enforcement

Cutover validation must fail if production code:

- reads or writes `ShoppingItem.isCompleted` as Product State authority;
- reads or writes legacy `ShoppingListEntry.isChecked` as target authority;
- uses legacy UUID arrays for target Session/Map/notification selection;
- creates or mutates a target entry outside the command/repository boundary;
- clears a tombstone outside explicit Restore;
- mutates lifecycle state from a View/ViewModel;
- creates list/plan/Session context without owning identity/revision;
- writes History outside the causal command transaction;
- allows a repository to save independently inside a coordinated command;
- queries all compatibility items to answer a scoped Product State question.

### 10.5 Performance and Privacy

- Compare target Functional and Reference profiles to the authoritative Phase 1 baseline using the same environment and measurement semantics.
- AC-43 requires no more than 10% p95 state-projection regression on the approved production-scale fixture and oldest supported device.
- Performance is never used to weaken correctness or recovery.
- Diagnostics contain only stage, command/projection category, safe record counts, durations, revision-mismatch counts, durability mode, and failure class.
- Tests and attachments contain synthetic values only.
- No Product name, note, barcode, image, precise coordinate, credential, token, account/user identifier, or raw store content enters diagnostics.

---

## 11. Risks

These are implementation risks, not architecture alternatives.

| Risk | Implementation consequence | Required mitigation / stop condition |
|---|---|---|
| Supported SwiftData versions cannot enforce the planned uniqueness/revision mechanism directly | Duplicate entries or lost updates under concurrency | Prove command-level serialization in T-05; database constraint is defense only; stop if D-37 cannot be met |
| Participating repositories accidentally use separate contexts or saves | Partial Product/list/history/Session commit | One coordinator-supplied transaction scope; injected failure tests; stop on any partial visibility |
| Versioned schema freezes drift while adding the next graph | Existing stores may become unidentifiable or unmigratable | Protected source hashes and schema tests; never edit V1/V2/V3 declarations |
| Candidate-store copy/promotion misses a sidecar or metadata file | Source corruption or incomplete migration | Enumerate/fingerprint exact store family; validate candidate and original before promotion; stop on mismatch |
| Migration loads large images/full graphs | Launch memory/latency failure | Identity/state-only fetches, measured bounded batches if required, no image loading unless semantically necessary |
| Semantic migration is not reentrant | Interrupted launch causes data/timestamp drift | Stable migration identity, deterministic aliases/events/times, second-pass digest tests |
| Exception ledger cannot render safely | User data becomes hidden or developers are tempted to guess | Preserve safe snapshots and counts; block writable target UI when required recovery cannot be exposed |
| WT-031B develops a different line/revision/Finish model | Competing Session authority or impossible atomic Finish | Co-review T-02, T-08, and T-19; stop until one shared contract exists |
| Existing broad services retain hidden save paths | Alternative authority survives conversion | Static call-site enforcement and direct-writer inventory after every consumer step |
| Phase 1 characterization is edited prematurely | Baseline evidence is lost or defects become ambiguous | Add target tests first; retire only exact traced current expectations at their conversion step |
| Projection cache omits a dependency | Stale plan/Map/notification content appears current | Explicit cache dependency inventory and parity tests; cache may be disabled without correctness loss |
| Post-commit reconciler retries out of order | Geofence/notification state lags or duplicates | Key work by owner/revision, make newer revisions supersede older, test failure/reordering |
| Catalog persistence continues implicit restore | Tombstone can bypass Product commands | Route all Product persistence through acquisition command; explicit restore-required tests |
| Product/Shopping presentation conversion is incomplete | Direct persistence or legacy fallback remains reachable | Consumer-by-consumer static audit; no partial release before T-21 |
| File-system synchronization does not discover a proposed path | Pressure to edit project settings outside scope | Verify discovery before creating code; stop and request explicit project-change authority |
| No UI-test target limits automation | Accessibility regressions could escape unit coverage | Named manual/device evidence plus presentation-semantic tests; separate approval required for a new target |
| Full migration or scoped queries regress performance | Release qualification fails | Compare exact Phase 1 profile; optimize only measured bottlenecks without changing authority |
| Diagnostics include record content | Privacy breach | Allowlist only, sentinel scans, Sentry/no-network regression, immediate stop on leakage |
| Forward rollback build is not retained | Migrated users cannot recover safely | Build and dry-run forward-compatible disable path before T-21 |
| Untracked/unrelated repository work overlaps an execution path | User changes may be overwritten or audit invalidated | Preflight every step; stop on overlap and request direction |

---

## 12. Exit Criteria

WT-033A implementation is complete only when every condition below is satisfied.

### 12.1 Architecture and Ownership

- [ ] TC-01 through TC-29 responsibilities are implemented or explicitly proven unnecessary without leaving an unowned requirement.
- [ ] Every lifecycle has one and only one authority.
- [ ] All Product/list/Session/history mutations enter through named commands.
- [ ] Production presentation and integration code has zero direct lifecycle persistence writes.
- [ ] Repository implementations make no lifecycle policy decisions and perform no independent coordinated save.
- [ ] Queries are read-only, scoped, deterministic, and free of legacy fallback.
- [ ] Catalog, Product Knowledge, saved locations, Map, notifications, scanner, AI, discovery, and store recommendations remain non-authoritative.

### 12.2 Domain and Transaction Correctness

- [ ] Product UUID, tombstone, Catalog snapshots, Product Knowledge, and history retention are preserved.
- [ ] Entry uniqueness and expected revisions are enforced under concurrency and retry.
- [ ] List A mutations do not change list B.
- [ ] Product removal affects all editable lists atomically and is blocked by non-terminal Session references.
- [ ] Restore is explicit, preserves UUID, and creates no list membership.
- [ ] Every plan identifies one list/revision and exact entry IDs.
- [ ] Session snapshots are immutable and collection remains provisional.
- [ ] Finish assigns every outcome and commits Session/list/revision/history/plan effects once.
- [ ] No command reports success before durable commit.
- [ ] External effects are post-commit and idempotent.

### 12.3 Migration and Recovery

- [ ] Frozen V1/V2/V3 declarations and protected hashes remain unchanged.
- [ ] The next schema and semantic migration have explicit approval and complete evidence.
- [ ] Original store and sidecars remain recoverable on every tested failure.
- [ ] Product/list/entry/Session/history/location/archive/exception counts reconcile.
- [ ] Stable IDs, snapshots, tombstones, quantities, ordering, and supported relationships survive.
- [ ] Duplicate, orphan, flag, Session, history, archive, and tombstone rules match D-24…D-32.
- [ ] A second migration/validation pass has identical semantic output.
- [ ] Failed migration never exposes writable target, empty-store success, or silent in-memory durability.
- [ ] Forward-compatible rollback and explicit backup restoration procedures are validated.

### 12.4 Consumer and Cutover

- [ ] Product, Home, Shopping, Plan, Map, location, discovery, store, scanner, Session, and notification consumers use target projections/commands.
- [ ] Shopping/Plan/Map/notification identity parity holds with explicit exclusions.
- [ ] Notification and geofence contexts validate owner/revision before use.
- [ ] Current legacy reader count and direct-writer count are zero.
- [ ] Compatibility storage is read-only/non-authoritative and remains physically present until a later schema release.
- [ ] One coherent release enables target readers and writers; no partial surface set ships.

### 12.5 Validation and Evidence

- [ ] All 22 execution steps T-00 through T-21 are complete, bounded, and evidenced.
- [ ] Every intentionally changed Phase 1 characterization maps to an approved decision and target replacement test.
- [ ] All target unit/integration/migration/consumer/Session/notification/static suites pass twice from clean state where required.
- [ ] All five Phase 1 Product State suites and all named existing regressions pass or have an approved traced retirement.
- [ ] The complete `WayTaskTests` target passes with exact totals recorded.
- [ ] Generic unsigned Debug and Release application builds pass.
- [ ] Performance qualification meets the approved AC-43 comparison using the controlled Phase 1 protocol.
- [ ] English/Hebrew, RTL, Dynamic Type, VoiceOver, Switch Control, keyboard, target-size, non-color, and Reduce Motion evidence passes.
- [ ] Diagnostics/privacy allowlist and no-network/no-Sentry-private-data checks pass.
- [ ] No unapproved project, package, Catalog content, Product Knowledge content, or unrelated repository change exists.
- [ ] Temporary DerivedData, result bundles, stores, sidecars, exported attachments, and migration candidates are removed.
- [ ] Rollback and feature-disable drills pass.
- [ ] Final implementation evidence is complete, deterministic, reproducible, and privacy-safe.

### 12.6 Terminal Condition

Approval of this S-02 roadmap permits later step-specific implementation authorization to be prepared. It does not itself authorize code, tests, schema, migration, project, package, localization, Catalog, or prior-document changes.

WT-033A implementation may be declared complete only after T-21 satisfies every exit criterion above and an explicit terminal audit approves the single authority cutover.
