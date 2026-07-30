# WT-033A — Product State Authority Specification

**Step:** S-01  
**Status:** Proposed Phase 2 authority contract; pending approval  
**Repository branch:** `main`  
**Repository baseline:** `a20b83c570157038cb85b0b3efb49a24cf8ccc50`  
**Specification date:** 2026-07-30  
**Implementation authorization:** None  
**Change boundary:** This document only

## Contract Basis

This specification defines the approved target Product State architecture for WT-033 Phase 2 work. It is an engineering contract, not an implementation design. It does not choose Swift types, APIs, files, schema attributes, indexes, migration stages, framework mechanisms, or project configuration.

The governing sources, in authority order for their respective concerns, are:

1. `docs/Audits/1.0.3/WT-030_ArchitectureSummary.md` and `docs/Audits/1.0.3/WT-030A_ProductStateUXAudit.md` for the approved Orthogonal Product Lifecycle and cross-domain boundaries.
2. `docs/ImplementationSpecifications/1.0.3/WT-032A_ProductState_Phase0DecisionSpecification.md` for binding Product State decisions D-01 through D-37.
3. `docs/ImplementationPlans/1.0.3/WT-031A_ProductStateImplementationPlan.md` for dependency order, cutover strategy, and implementation boundaries.
4. `docs/ImplementationSpecifications/1.0.3/WT-032B_ProductState_Phase1ImplementationSpecification.md` for the completed behavior-preserving Phase 1 boundary and its current-behavior characterization contract.
5. `docs/Specifications/WT-033A_ProductStateAuthorityDiscovery.md` for current repository authority, writer, reader, `ModelContext`, dependency, and risk findings.

WT-032A resolves the policy questions that WT-030A and WT-031A left open. This document restates those approved outcomes as target authority contracts and does not reopen them. Current behavior described by WT-032B or S-00 is evidence to replace safely, not target authority.

Normative terms have their usual contract meaning:

- **must** and **must not** are required for conformance;
- **may** identifies a permitted option inside the fixed authority boundary;
- **authority** is the sole owner allowed to decide a lifecycle state;
- **projection** is a read-only, rebuildable representation of authoritative state;
- **command** is a named, user-authorized request to an authority;
- **transaction owner** is the boundary responsible for validating and committing one user intent atomically.

---

## 1. Executive Summary

### 1.1 Purpose

WayTask Product State is a composition of independent lifecycles. Product identity, Product Library membership, named-list membership and resolution, plan validity, Session execution and outcome, Product History, Catalog lifecycle, Product Knowledge, saved-location evidence, notifications, AI recognition, and Map presentation each have a distinct owner.

This specification establishes:

- exactly one authority for every Product State lifecycle;
- named command ownership for every authoritative mutation;
- read-only query projections for every consumer surface;
- atomic transaction, revision, failure, and recovery rules;
- integration contracts that prevent consumers from becoming authorities;
- the migration and compatibility boundary for one coherent cutover; and
- invariants and acceptance criteria for all later WT-033 implementation work.

### 1.2 Goals

The target architecture must:

1. preserve stable user Product identity and the existing durable removed tombstone;
2. make list membership and resolution exact to one named list entry;
3. enforce at most one current entry for each `(list ID, Product ID)`;
4. make list revisions durable, monotonic, and transaction-owned;
5. make plans explicit projections of one list revision and exact entry set;
6. keep collection provisional and Session-scoped;
7. reconcile every Session line through an explicit atomic Finish;
8. record immutable Product-UUID history events without overclaiming purchase;
9. preserve Catalog and Product Knowledge independence;
10. route all mutations through named domain commands;
11. make all screen and integration reads consume scoped projections;
12. remove legacy completion and compatibility values from authority at one cutover;
13. remain offline-first, deterministic, recoverable, privacy-safe, accessible, and platform-neutral.

### 1.3 Non-goals

This specification does not:

- implement or authorize code;
- define a global Product status or a flat Product State enum;
- design a SwiftData schema, repository API, command signature, migration stage, or file plan;
- redefine WT-032A D-01 through D-37;
- define the full WT-031B Shopping Session background, expiration, geofence-ledger, battery, or synchronization design;
- define Community Feedback, Cloud sync, Android implementation, retail inventory truth, or physical privacy erasure;
- authorize compatibility storage removal in v1.0.3;
- prescribe general UI styling beyond the approved semantic and authority boundaries.

---

## 2. Product State Philosophy

### 2.1 Single Source of Truth

Single source of truth means one scoped authority per lifecycle, not one database record or global boolean for the whole application.

For any state-bearing value, the system must be able to answer:

1. which lifecycle owns it;
2. which identity and scope it applies to;
3. whether it is authoritative, derived, transient, or historical;
4. which named command may change it;
5. which transaction commits it; and
6. which projections may read it.

No Product is globally needed, completed, collected, purchased, planned, or recommended. These meanings belong respectively to a named list entry, Session line, historical event, plan, or recommendation projection.

### 2.2 Lifecycle Ownership

Lifecycle owners are orthogonal:

- Product owns stable user identity and user-owned attributes.
- Product Library lifecycle owns active or removed membership.
- A named Shopping List owns its metadata and durable content revision.
- A Shopping List Entry owns exact-list membership, quantity, order, notes, and needed/resolved state.
- A Shopping Plan owns a rebuildable projection of one list revision.
- A Shopping Session owns its frozen execution snapshot, lines, provisional collection, and final outcomes.
- Product History owns immutable named outcome events.
- Catalog owns published Catalog Truth.
- Product Knowledge owns bundled and learned recognition knowledge.
- Saved Locations own location/store-note evidence.
- Notifications and Map own platform/presentation state only.
- AI recognition owns transient candidate evidence only.

An owner may reference another lifecycle by stable identity or immutable snapshot. A reference never transfers authority.

### 2.3 Read Versus Write Separation

Write rules:

- Every authoritative mutation must enter through a named command.
- Only the owning command boundary and its persistence boundary may write lifecycle state.
- Views, ViewModels, Map, notifications, scanner, AI, store recommendations, and background adapters may initiate commands but may not write lifecycle fields directly.
- Direct `ModelContext` lifecycle mutation in presentation or integration code is prohibited.
- One user intent must not be assembled from independent view-level saves.

Read rules:

- Consumers use named, scoped projections.
- Queries may read durable state but must not save, insert, delete, repair, backfill, log private content, schedule integrations, or trigger a command.
- A query must not silently repair missing data or fall back to legacy authority.
- Projection identity and staleness must be explicit where the consumer depends on a list or Session revision.

### 2.4 Authority Principles

1. One authority owns each lifecycle.
2. Stable IDs connect authorities without merging them.
3. User intent is explicit and scoped.
4. Commands validate current identity, expected revision, and lifecycle preconditions.
5. Queries are side-effect-free.
6. Derived projections never become truth.
7. Catalog, Product Knowledge, Store evidence, and AI never decide user Product lifecycle.
8. Collection is not purchase.
9. History records no stronger claim than confirmed evidence supports.
10. Unknown and ambiguous legacy state remains explicit.
11. Local authoritative mutations are atomic.
12. External side effects reconcile after commit and are idempotent.
13. Core Product, list, and Session behavior remains usable without network access.
14. Compatibility may support transition but never co-own target meaning.
15. The released cutover must have no mixed authority.

---

## 3. Lifecycle Authorities

### 3.1 Authority Matrix

| Lifecycle | Owner | Responsibilities | Allowed writers | Allowed readers | Persistence owner | Transaction owner | Integration consumers |
|---|---|---|---|---|---|---|---|
| Product identity | User Product aggregate | Stable Product UUID, user-owned display/detail values, optional Catalog reference, saved display snapshots, provenance and timestamps | Create/acquire and explicit Product-edit commands | Library, list, plan, Session snapshot creation, history, Catalog presentation, discovery | Product repository boundary | Product command boundary | Camera, AI, Catalog, Product Knowledge, UI, plan, Map |
| Product Library | Product Library transition on the user Product | `active` or durable `removed(removedAt)`; removed discovery; explicit restoration | Create, Remove from Product Library, Restore to Product Library | Library and removed projections; acquisition match; list-command preconditions | Product repository boundary | Product State command boundary; removal coordinates affected lists | Camera, Catalog acquisition, Product UI, list chooser |
| Shopping Lists | Named Shopping List aggregate | Stable list ID, title, purpose, durable monotonic content revision, ordering scope | Named-list commands and list-entry commands that affect projection content | Shopping, Home, plan, Session start, Map, reminders | Shopping repository boundary | Named-list command boundary | Plan, Session, Map, notifications, discovery |
| Shopping List Entries | Entry identified by exact list ID and Product ID | Membership, quantity/unit, note, sort order, `needed` or `resolved(reason, effectiveAt, provenance)` | Add, update, resolve, reopen, remove, and atomic Finish reconciliation | Named-list, membership-action, plan-input, Session-source, Map/reminder projections | Shopping repository boundary | Named-list command boundary; Finish transaction for Session outcomes | Product UI, Shopping, Home, plan, Session |
| Shopping Plan | Plan projection/aggregate for one list revision | Source list ID/revision, exact included entry IDs, exclusions, generation state, recommendations, snapshot metadata | Plan generation/supersession boundary only; source commands make it stale by revision | Shopping, Home, Map, Session start, store recommendations | Plan repository or rebuildable cache boundary if later approved | Plan generation boundary; never a Product/list transaction owner | Map, Session, discovery, notifications |
| Shopping Session | One persisted Session aggregate and revision | Source list/revision, optional plan/store/stop snapshot, immutable lines, provisional collection, final outcomes, lifecycle | Start, explicit resume selection, collect/undo, assign outcome, Finish, Abandon; expiration commands remain WT-031B-owned | Session UI, Home resume, Finish review, Map, notification validation, history reconciliation | Shopping Session repository boundary shared with WT-031B | Session command boundary; Finish is the shared Product State/Session transaction | Map, reminders, notifications, history |
| Shopping History | Product History event authority | Immutable named events keyed by Product UUID with source list/entry/Session/line identity, time, provenance, and display snapshot | Only owning Product/list/Session commands append their required events; migration may append only approved `legacyMigration` events | Recent Products, history UI, personalization, replenishment projections, diagnostics aggregates | Product History repository boundary | Same transaction as the causal command | Product UI, discovery, AI recommendations, analytics under separate privacy policy |
| Catalog | Catalog publication authority | Versioned Catalog concepts, taxonomy, aliases, stable IDs, active/inactive/replaced/missing status, redirects | Approved Catalog publication process only | Product acquisition, Catalog search, Product display resolution, planning classification | Catalog repository/publication boundary | Catalog publication transaction, separate from user Product State | Camera, search, Product display, planning, store classification |
| Product Knowledge | Bundled and learned recognition-knowledge authority | Searchable recognition concepts and bounded learned recognition metadata | Approved Product Knowledge publication and learned-knowledge commands | Camera, autocomplete, recognition, classification | Product Knowledge repository boundary | Product Knowledge transaction, separate from Product lifecycle | Camera, AI recognition, acquisition |
| Saved Locations | Saved-location/store-note authority | Stable location identity, user label/profile, coarse/persisted location data under privacy policy, separate note/reminder evidence | Named saved-location create/edit/remove commands only | Map, store matching, reminder candidate generation | Saved-location repository boundary | Saved-location command boundary | Map, store recommendations, reminders |
| Notifications | Platform notification/reminder adapter | Permission/capability state, registration ledger, delivery request, validated deep-link presentation | Notification adapter may write only its own registration/delivery state after authoritative commit | Validated list/plan/Session reminder projections | Platform adapter storage, not Product State storage | Idempotent post-commit reconciliation | OS notifications, App navigation |
| AI Recognition | Transient recognition workflow | Candidate evidence, confidence, explanation, and user review state | Recognition pipeline writes transient workflow state only | Camera/acquisition presentation; confirmed candidate can be an input to a Product command | No Product State persistence | None until an explicit user command is submitted | Camera, acquisition UI |
| Map | Map presentation/projection | Selected map context, markers, estimated store matches, navigation state | Map may write presentation state and initiate named commands; it cannot write Product/list/Session lifecycle | Explicit selected-list, ready-plan, active-Session, saved-location, and store projections | Presentation/cache boundary only | No Product State transaction ownership | Store search, saved locations, notifications |
| Migration and recovery | One semantic migration coordinator | Legacy interpretation, normalization, exception ledger, invariant validation, completion marker, recoverable original-store boundary | Migration coordinator before writable target UI; target repair after cutover may repair only target graph under fixed rules | Startup gate, recovery UI, privacy-safe diagnostics | Persistence migration/recovery boundary | Semantic migration transaction owner | Startup, support/recovery |
| Compatibility | One-way transitional adapter | Target-derived legacy output or read-only archive during the permitted transition | Before cutover, target commands may produce a same-transaction mirror; after cutover, no authoritative writer | Migration, characterization, and explicitly bounded pre-cutover adapter only | Legacy storage boundary while retained | Never a transaction owner or decision owner | No authoritative consumer after cutover |

### 3.2 Product and Product Library Contract

Product identity and Library membership are related but distinct:

- Product UUID is stable for the life of the user Product.
- Product identity contains no list, plan, Session, completion, purchase, or recommended-store state.
- Library state is only Active or Removed for v1.0.3.
- Remove preserves Product identity, user fields, Catalog snapshots, Product Knowledge, history, and terminal references.
- Restore preserves the same Product UUID and creates no list membership.
- Archive and physical privacy erasure are not Product Library states.
- Catalog, scanner, AI, startup, migration, background work, and future synchronization may not restore automatically.

### 3.3 Shopping List and Entry Contract

- Any number of named lists may coexist.
- “Selected list” is presentation state, not lifecycle state.
- Entry identity is exact to one list and one Product.
- Entry lifecycle is Absent, Needed, or Resolved.
- Approved resolution reasons are `purchased`, `alreadyHave`, `noLongerNeeded`, and migration-only `legacyUnknown`.
- `unavailable`, `skipped`, and `carriedForward` leave the source entry Needed.
- Resolved entries remain in their named list and remain available through a Resolved projection.
- Reopen preserves the entry identity and earlier history event.
- Remove changes membership in exactly one list and never changes another list or Product Library state.
- Completed is retired as an editable Shopping-list concept.
- Recent Products is a read-only Product History projection.

### 3.4 Plan and Session Contract

- Every plan identifies exactly one source list, one source revision, and exact included entry IDs.
- A plan is rebuildable and never mutates Product or list state.
- Every v1.0.3 Session has exactly one source list and may include multiple planned store stops.
- Starting a Session freezes source entry/Product identity and approved display/store/plan snapshots.
- Later Product, Catalog, list, or plan changes do not rewrite that Session snapshot.
- New source-list entries may be added during a Session but do not enter the frozen Session.
- Captured source entries are protected from remove, resolve, reopen, and quantity edits outside Session commands while the Session is non-terminal.
- Collection is provisional and reversible.
- Finish requires an explicit final outcome for every line.
- Abandon is terminal, retains snapshot and provisional progress, and makes no list-resolution or purchase-history claim.

### 3.5 History and External-Domain Contract

- History events are immutable and keyed by stable Product UUID.
- Purchase is recorded only by successful explicit Finish confirmation.
- Legacy aggregate history remains labeled non-authoritative and cannot be joined by name or barcode alone.
- Catalog lifecycle never changes user Product lifecycle.
- Product Knowledge never becomes Product identity or shopping state.
- Saved-location relationships are evidence or notes, not Product/list/Session authority.
- Notifications, AI, Map, discovery, and store recommendations consume projections and cannot decide lifecycle state.

---

## 4. Command Architecture

### 4.1 Command Contract

Every authoritative command must conceptually carry:

- a stable command identity for safe retry;
- explicit user or approved system intent;
- the owning aggregate identity and scope;
- the expected aggregate or list/Session revision where applicable;
- deterministic input values and an effective time supplied by the command boundary;
- sufficient provenance to explain the transition.

Every command result must distinguish:

- committed change;
- idempotent no-op/already-present result;
- explicit conflict requiring user choice;
- validation rejection;
- missing or ambiguous identity;
- persistence/recovery unavailable;
- migration incomplete.

A success result is emitted only after the durable authoritative commit. A command is not permission for its caller to perform follow-up lifecycle writes.

There is no generic **Check Item** command. In a named list the explicit action is Resolve Need with a reason. In an active Session the explicit action is Mark Collected. These commands have different owners and effects.

### 4.2 Product and Library Commands

| Command category | Inputs | Outputs | Preconditions | Postconditions | Failure behavior | Ownership |
|---|---|---|---|---|---|---|
| Create/Acquire Product | Stable command ID; reviewed manual, scanner, AI, or Catalog evidence; explicit Library destination; Product values and provenance | Created Product; already-active Product; restore-required tombstone; ambiguous match; validation failure | Target migration complete; persistence durable; candidate reviewed as required; no unapproved identity guess | A new active Product exists, or an existing exact active Product is returned unchanged; no list/plan/Session/purchase mutation | No partial Product; no implicit restore; ambiguous identity requires user resolution; failed save reports no success | Product command owner |
| Edit Product / Rename Product | Product ID; explicit changed user-owned values; expected Product version/fingerprint if required | Updated Product snapshot or no-op | Product exists; edit is permitted for its Library state; active Session snapshots remain immutable | User Product fields change; relevant planning-input fingerprint changes when declared; no list revision is falsified | Existing snapshots and other lifecycles remain unchanged; save failure exposes no change | Product command owner |
| Remove from Product Library | Product ID; explicit confirmation; expected Product state; impact summary for all editable lists | Removed Product and affected-list summary, or active-Session conflict | Product Active; no non-terminal Session contains it; affected lists and expected revisions validate | Product becomes Removed; current entries are removed from all editable lists; each affected list revision advances once; required history events append | Any active Session, stale revision, validation, or save failure leaves Product and all lists unchanged | Cross-list Product State command owner |
| Restore to Product Library | Tombstoned Product ID; explicit restore confirmation | Restored same Product ID or conflict | Exact Product exists and is Removed; migration complete | Tombstone clears; restore event appends; user fields, snapshots, knowledge, and history remain; no list, plan, or Session is created | Active Product returns an idempotent/already-active result; missing/ambiguous Product is not fabricated; failure leaves tombstone | Product command owner |

Catalog snapshot refresh is not a Library transition. If a later approved workflow permits an explicit snapshot refresh, it must preserve Product UUID and every Product/list/Session/history lifecycle and must not be coupled to Restore.

### 4.3 Shopping List and Entry Commands

| Command category | Inputs | Outputs | Preconditions | Postconditions | Failure behavior | Ownership |
|---|---|---|---|---|---|---|
| Create Named List | Stable command ID; title/purpose; explicit user intent | New list identity and initial revision | Migration complete; title/purpose validation succeeds | One named list exists; no Product membership is inferred | No partial list; no default compatibility list is silently populated | Shopping List command owner |
| Rename Named List | List ID; new title; expected revision | Renamed list and resulting revision/no-op | List exists; expected revision matches | Title changes; revision advances once when title is a captured projection input | Stale revision or save failure leaves title/revision unchanged | Shopping List command owner |
| Add Product to List | List ID; Product ID; expected list revision; stable command ID; entry values | Created Needed entry or existing Needed no-op; explicit reopen-required result for Resolved | Product is Active; list exists/editable; no protected conflict | Exactly one Needed entry exists; change increments list revision once and appends need-added history; no-op causes no drift | Resolved entry never reopens silently; concurrency/retry cannot create duplicates; failure changes nothing | Shopping List Entry command owner |
| Update List Entry | Entry/list/Product identity; expected list revision; quantity/unit/order/note changes | Updated entry/revision or no-op | Entry exists; Product/list identities match; entry is not protected by non-terminal Session | Entry-owned values change; list revision advances once if projection-relevant | Active-Session conflict, stale revision, invalid values, or save failure leaves entry unchanged | Shopping List Entry command owner |
| Resolve List Need | Entry/list/Product identity; approved reason; effective time; provenance; expected revision | Resolved entry and revision | Entry is Needed; not mutation-protected by Session; reason is approved | Same entry becomes Resolved; reason/time/provenance persist; revision advances once; resolution event appends | No implicit purchase except `purchased` from atomic Finish; invalid/no-op/retry cannot duplicate history or revision | Shopping List Entry command owner; Finish owns Session-derived purchase resolution |
| Reopen List Need | Entry/list/Product identity; expected revision; explicit intent | Needed entry and revision or no-op | Entry is Resolved; not protected by Session | Same entry becomes Needed; earlier resolution history remains; reopen event appends; revision advances once | Add cannot substitute for Reopen; stale/conflict/save failure changes nothing | Shopping List Entry command owner |
| Remove Product from Named List | Entry/list/Product identity; expected revision; explicit scope | Membership removed and revision, or absent no-op | Entry belongs to the named list; not protected by Session | Only that entry becomes Absent; revision advances once; membership-removed history appends; Product and other lists remain unchanged | Retry on already-absent state is no-op; protected/stale/save failure leaves membership | Shopping List Entry command owner |

List close/delete lifecycle, if introduced later, requires a separate approved policy. This specification does not infer it from list kind or presentation.

### 4.4 Plan Commands

| Command category | Inputs | Outputs | Preconditions | Postconditions | Failure behavior | Ownership |
|---|---|---|---|---|---|---|
| Generate Plan | List ID; exact list revision; exact Needed entry IDs; declared planning input versions; requested planning context | Generating then Ready, Failed, or Stale plan result with included/excluded entries | Source projection is internally consistent and current | Ready plan records source identity/revision, exact entry IDs, exclusions, generation time, and recommendation snapshots; list remains unchanged | Failure records no Product/list mutation; source revision change makes result Stale rather than silently current | Plan generation owner |
| Supersede/Discard Plan | Plan identity and explicit presentation intent or newer source revision | Superseded/absent plan projection | Plan exists | Plan ceases to be offered as current; source list remains unchanged | Failure never changes Product/list state | Plan owner |

Plan invalidation is primarily a deterministic consequence of source revision or declared input mismatch. It is not an independent lifecycle write performed by views.

### 4.5 Session Commands

| Command category | Inputs | Outputs | Preconditions | Postconditions | Failure behavior | Ownership |
|---|---|---|---|---|---|---|
| Start Session | Stable command ID; source list ID/revision; exact source entries; optional current plan/store/stop snapshot | New active Session or explicit existing-session conflict | No unresolved migration block; source list/revision valid; exact entries are eligible; no other non-terminal Session unless user resolves conflict | One active Session freezes source identity, line IDs, Product snapshots, plan/store context, and initial revision | Never silently resumes/replaces different context; validation/save failure creates no Session | Session command owner shared with WT-031B |
| Resume Existing Session | Explicit selected Session ID and expected revision | Same active/expired Session context according to WT-031B policy | User selected the exact recovery candidate; Session is resumable | Opens or transitions only the selected Session as permitted; no list outcome is inferred | Ambiguous/missing/terminal state routes to safe recovery; no new Session | Session command owner |
| Mark Line Collected | Session/line IDs; expected Session revision | Updated Session line/revision or no-op | Session non-terminal; line belongs to snapshot; line is eligible | Line becomes Collected provisionally; Product, entry, list revision, and history remain unchanged | Stale/missing/save failure leaves Session and list unchanged | Session command owner |
| Undo Line Collection | Session/line IDs; expected Session revision | Remaining line/revision or no-op | Session non-terminal; line is Collected | Same line becomes Remaining; no Product/list/history mutation | Stale/missing/save failure changes nothing | Session command owner |
| Prepare/Change Finish Outcome | Session/line IDs; one approved proposed outcome; expected Session revision | Updated reconciliation draft or validation result | Session is in approved reconciliation flow; line exists; outcome valid | Review input changes only; no final line outcome, list state, history, or finished state becomes authoritative before Finish | Invalid or missing proposal blocks Finish; no implicit default; draft-persistence mechanics remain an implementation choice | Finish review boundary; authoritative ownership begins with Finish |
| Finish Session | Session ID/revision; complete line-outcome set; expected source identities/revisions; explicit confirmation | Finished Session, reconciled entries, revisions, history events, superseded plans | Session non-terminal; all lines resolved to approved outcomes; no unresolved legacy line or protected inconsistency | One commit writes final outcomes, maps entries, increments affected revision once, appends idempotent events, supersedes source plans, and marks Session Finished | Any validation/concurrency/save failure leaves Session active and all entries/revisions/history/plans unchanged; retry cannot duplicate effects | One shared Finish transaction owner across Session, list, plan, and history |
| Abandon Session | Session ID/revision; explicit confirmation | Abandoned Session | Session non-terminal and exact revision current | Session becomes terminal; snapshot and provisional progress remain; no entry resolution or purchase history is written | Failure leaves Session non-terminal; retry is idempotent | Session command owner |

The exact expiration and background lifecycle commands remain governed by WT-030B/WT-031B. They may not redefine Product, entry, collection, final outcome, or Finish semantics.

### 4.6 History and Saved-Location Commands

Product History exposes no arbitrary “write history” command to presentation or integrations. Required events are appended only within the causal Product, list, or Session transaction. Migration may append only events explicitly permitted by D-25 through D-32 with `legacyMigration` provenance.

Saved-location create, edit, and remove commands own only location/store-note state. They may initiate a separate named Product/list command after explicit user intent, but they may not toggle compatibility completion, resolve an entry, restore a Product, or alter a Session.

### 4.7 Command Initiators

UI, Home, Map, notification actions, Camera, scanner, AI, Catalog search, discovery, store recommendations, and future Cloud adapters may submit an approved command. They must:

- identify the exact command and scope;
- supply or obtain current owning identity/revision;
- preserve required user confirmation;
- display only the committed result;
- handle conflicts without performing fallback writes;
- never translate stale payload content directly into lifecycle state.

---

## 5. Query Architecture

### 5.1 Query Rules

Every Product State query is:

- read-only;
- scoped by authoritative identity or an explicitly safe browse scope;
- deterministic for the same committed state and declared inputs;
- free of persistence writes, repair, backfill, network mutation, telemetry side effects, and OS scheduling;
- explicit about revision, staleness, omissions, and unresolved records;
- forbidden from consulting legacy authority after cutover.

Queries may read persisted records. “No persistence” means query execution never inserts, deletes, saves, normalizes, or updates those records.

### 5.2 Required Read Projections

| Projection | Authoritative inputs | Output contract | Primary consumers | Forbidden behavior |
|---|---|---|---|---|
| Product Library | Active Product identities and user-owned snapshots | Stable ordered active Products; optional scoped list-membership action state | Products, Home, acquisition | No completion/collected/purchase flag; no implicit restore |
| Removed Products | Removed Product identities and removal time | Recoverable Products with explicit restore availability | Product Library recovery, acquisition conflict | No automatic expiry or list recreation |
| Product Acquisition Match | Exact supported identity evidence plus current Product lifecycle | `alreadyActive`, `restoreRequired`, `create`, or `ambiguous` semantic outcome | Camera, AI review, Catalog search, manual add | No name/barcode-only merge beyond approved exact identity; no mutation |
| Named List | List ID/revision, exact entries, Product display references | Needed and separately accessible Resolved entries, quantity/order/note, reason/time | Shopping, Home list card | No cross-list/global compatibility fallback |
| Product Membership Action | Product ID plus one named list ID/revision | Absent, Needed, or Resolved for that exact list; permitted action | Product action sheet, chooser | No context-free “in Shopping” state |
| Plan Input | One list ID/revision and its exact Needed entries | Eligible entry IDs plus explicit unresolved/excluded entries and declared input fingerprint | Planner, store recommendations | No global compatibility scan; no silent exclusion |
| Plan Status | Plan identity/source revision plus current declared inputs | Idle, Generating, Ready, Failed, or Stale with reason | Shopping, Home, Map, Session start | No list mutation or runtime UUID authority |
| Active Session Lookup | Non-terminal Session identities and revisions | Zero, one, or explicit multiple recovery candidates | Home, Shopping, startup recovery | No silent first-session reuse or discard |
| Session Snapshot | Exact Session/revision | Frozen source, stops, line identities/snapshots, provisional state, outcomes | Shopping Mode, Map, reminders | No live Product/Catalog rewrite of snapshots |
| Finish Review | Session snapshot plus explicit current validation | Every line, proposed outcome, missing/invalid outcomes, source conflicts | Finish UI | No default final outcome and no mutation |
| Product History | Immutable events for exact Product ID and safe aggregate derivations | Ordered named events; Recent Products/frequency projections with provenance | Products, personalization, AI recommendations | No purchase inference from checked/completed/collected |
| Catalog-Linked Product Presentation | User Product plus current Catalog reference/redirect and saved snapshot | Current Catalog metadata when valid, offline snapshot otherwise, status explanation | Product UI, acquisition, planning | Catalog state cannot mutate Product lifecycle |
| Product Knowledge Search | Bundled/learned knowledge query | Recognition/search candidates and provenance | Camera, autocomplete, AI recognition | No user Product identity or lifecycle claim |
| Map Shopping Context | Explicit selected-list projection, Ready plan, or active Session snapshot | Exact Product/entry/session IDs, display snapshots, recommendation context | Map, store search | No default all-incomplete compatibility set; no writes |
| Notification Opportunity | Exact list/plan/Session owner and revision | Eligible item IDs and compact presentation snapshots | Reminder/geofence adapter | No stale schedule and no authority in payload |
| Notification Route Validation | Payload owner/version plus current authority | Exact Session/list destination, stale-safe fallback, or suppression | App navigation | No lifecycle mutation from frozen names/IDs |
| Saved-Location Evidence | Saved-location identity and separate note/reminder evidence | Location profile and exact provable links with authority labels | Map, store recommendations, reminders | No shadow Shopping list or completion state |
| Discovery / Shopping Context | Scoped list/plan/Session projection plus published knowledge/store inputs | Explainable eligible Product set and uncertainty | Discovery, decision engine, AI context | No global completion truth; no mutation |
| Store Recommendation | Plan/list/Session projection plus saved-location and published Store evidence | Ranked estimated stores with coverage/exclusions | Shopping, Home, Map | No verified inventory claim; no list resolution |
| Migration Recovery | Migration version, invariant result, exception ledger, safe snapshots | Completion status and privacy-safe recovery candidates | Startup/recovery UI, diagnostics | No writable target projection before completion; no fabricated identity |

### 5.3 Projection Consistency

For one selected list revision:

```text
Shopping Needed entry IDs
  = Plan input entry IDs + explicitly reported unresolved exclusions
  = Map list-context entry IDs
  = non-Session notification opportunity entry IDs
```

An active Session replaces mutable list context with its frozen Session-line snapshot for Session-specific Map and reminder use. Projection differences must be explained by named exclusions, revision changes, or the Session snapshot; they may not arise from a second authority.

---

## 6. Transaction Rules

### 6.1 Atomicity

All authoritative local effects caused by one user intent must commit together or not occur:

- owned lifecycle state;
- affected durable revisions;
- required immutable history events;
- target-derived compatibility output, if temporarily permitted;
- authoritative plan invalidation/supersession metadata.

The caller must not show durable success before commit. Autosave timing, optimistic view state, or a later callback cannot define business success.

### 6.2 Consistency and Concurrency

- Commands validate stable identities and expected revisions before mutation.
- The command boundary serializes and transactionally enforces entry uniqueness and revision rules on every supported iOS version.
- A database constraint may provide defense but is never the sole invariant.
- Each changed list revision advances exactly once per transaction, regardless of how many entries in that list change.
- Idempotent retries and no-ops do not advance revisions or duplicate events.
- Product planning-input changes use a declared fingerprint/version; they do not mutate a list revision outside the list owner.
- Active Session snapshot protections are checked by every relevant Product/list command.

### 6.3 Required Transaction Boundaries

| User intent | Atomic authoritative scope |
|---|---|
| Create/acquire Product | Product identity and its acquisition provenance only; no list or Product History event is inferred |
| Add/resolve/reopen/remove/update entry | Exact entry, one list revision, and required event |
| Remove Product from Library | Session precondition, Product tombstone, all editable-list removals, one revision per affected list, required Product/list events |
| Restore Product | Product tombstone transition and restore event only |
| Start Session | Validated list/revision/plan identity and complete immutable Session snapshot |
| Collect/undo | Session line and Session revision only |
| Finish Session | Every line outcome, exact source-entry reconciliation, each affected list revision, required history events, source-plan supersession, final Session state |
| Abandon Session | Session terminal state/snapshot retention only |
| Semantic migration | Complete semantic version, normalized target state, exception ledger, final invariant validation, and completion marker |

### 6.4 Finish Reconciliation

The Finish transaction must:

1. validate the Session is non-terminal and at the expected revision;
2. validate every Session-line identity;
3. require one approved final outcome per line;
4. reject unresolved migrated lines or protected-source inconsistencies;
5. persist every final line outcome;
6. resolve source entries for `purchased`, `alreadyHave`, and `noLongerNeeded`;
7. retain source entries as Needed for `unavailable`, `skipped`, and `carriedForward`;
8. increment each affected list revision exactly once;
9. append idempotent named Product History events;
10. supersede source plans according to their list/revision contract;
11. mark the Session Finished with final revision/time;
12. commit once.

No final outcome removes a Product from the Library or changes another list.

### 6.5 Rollback and Failure Handling

- Validation failure performs no authoritative mutation.
- Save failure exposes no success and leaves every aggregate, revision, event, and plan validity unchanged.
- Retry uses stable command/event identity and cannot duplicate effects.
- In-memory or recreated storage cannot be presented as successful durable recovery.
- Migration failure preserves the recoverable original-store boundary and blocks writable target UI.
- A partially completed semantic migration is never exposed as writable.
- After target writes, operational rollback uses a forward-compatible build; an old-authority binary may not resume normal mutation.
- Restoring a pre-migration backup is explicit and warns that later user changes are lost.

### 6.6 External Side Effects

Notification scheduling, geofence registration, haptics, analytics, monitoring, and other operating-system or network side effects are outside the local business transaction.

They must:

- run only after a committed authoritative result;
- consume committed owner identity and revision;
- be idempotent and safely retryable;
- validate current context again before delivery or routing;
- never reverse, complete, or redefine the business transaction;
- use privacy-safe metadata.

---

## 7. Invariants

### 7.1 Authority and Identity

- **INV-01:** Each lifecycle has exactly one authority.
- **INV-02:** Product UUID is stable and is the user Product relationship identity.
- **INV-03:** Catalog identity never replaces Product UUID.
- **INV-04:** Product identity contains no global shopping, planned, recommended, collected, completed, or purchased state.
- **INV-05:** A reference or snapshot does not transfer lifecycle ownership.
- **INV-06:** No presentation or integration layer directly persists Product/list/Session/history lifecycle state.
- **INV-07:** No query mutates, repairs, backfills, schedules, or persists.

### 7.2 Product Library

- **INV-08:** Library state is Active or Removed only.
- **INV-09:** Remove creates a durable tombstone and retains identity, user fields, snapshots, knowledge, history, and terminal references.
- **INV-10:** Restore is explicit, preserves Product UUID, and creates no list membership.
- **INV-11:** Catalog, scanner, AI, startup repair, migration, background work, and synchronization never restore implicitly.
- **INV-12:** Catalog inactive, replaced, or missing status never removes a user Product.
- **INV-13:** Non-terminal Session reference blocks Product Library removal.

### 7.3 Lists and Entries

- **INV-14:** Every membership and entry command identifies one named list.
- **INV-15:** At most one current entry exists for each exact `(list ID, Product ID)`.
- **INV-16:** Entry existence is the only current membership authority.
- **INV-17:** Entry state is Needed or Resolved with approved reason, time, and provenance.
- **INV-18:** `legacyUnknown` is migration-only and never means purchased.
- **INV-19:** A list A transition produces no lifecycle or revision change in list B.
- **INV-20:** Reopen preserves entry identity and prior resolution history.
- **INV-21:** Remove from a named list preserves Product Library and history.
- **INV-22:** A projection-affecting transaction increments its list revision exactly once; a no-op increments it zero times.
- **INV-23:** Captured active-Session entries cannot be removed, resolved, reopened, or quantity-edited outside Session commands.

### 7.4 Plans, Sessions, and History

- **INV-24:** Every plan identifies one source list/revision and exact entry IDs.
- **INV-25:** Plan generation changes no Product or list state.
- **INV-26:** Every v1.0.3 Session identifies exactly one source list and freezes its execution snapshot.
- **INV-27:** Product, Catalog, list, or plan changes never rewrite a started Session snapshot.
- **INV-28:** Collection changes only Session-local execution state.
- **INV-29:** Collected never means purchased.
- **INV-30:** Finish assigns and persists one approved final outcome for every line or refuses to finish.
- **INV-31:** Abandon performs no list resolution or purchase-history write.
- **INV-32:** Purchase history is appended only by explicit successful Finish confirmation.
- **INV-33:** History events are immutable, Product-UUID keyed, and retained across list removal, Library removal/restoration, and Catalog changes.
- **INV-34:** A failed or retried command never duplicates history events or revision increments.

### 7.5 Integrations, Migration, and Recovery

- **INV-35:** Map and notification Product sets come from the same named list/plan/Session source.
- **INV-36:** Saved Locations never own Product, list, plan, or Session lifecycle.
- **INV-37:** AI, Camera, scanner, discovery, and store recommendations may propose or initiate but never silently commit lifecycle state.
- **INV-38:** Notifications and payloads never become state authorities.
- **INV-39:** Store recommendations remain estimates and never resolve entries.
- **INV-40:** Migration never infers purchase, Product completion, Catalog identity, restoration, or membership from ambiguous legacy evidence.
- **INV-41:** Missing/unprovable references are preserved as explicit exceptions and excluded from active authority.
- **INV-42:** Target writable UI is unavailable until semantic migration completes and all invariants validate.
- **INV-43:** After cutover, authoritative legacy reader and writer counts are zero.
- **INV-44:** Compatibility retention never permits reverse synchronization or runtime fallback.
- **INV-45:** No local command reports success before durable commit.
- **INV-46:** Core Product, list, and active Session behavior does not require network access.

---

## 8. Integration Contracts

### 8.1 Camera and Scanner

Camera/scanner output is acquisition evidence. It may provide an image-derived candidate, barcode observation, confidence, or exact Catalog candidate to the Product acquisition command.

It must:

- preserve a user review/confirmation boundary;
- default acquisition to Product Library only;
- return already-active, restore-required, create, or ambiguous outcomes;
- require a separate explicit Restore for a tombstone;
- require a separate explicit Add to Named List command after creation/restore;
- never increment a list revision for Library-only acquisition;
- never infer purchase or list membership.

### 8.2 AI Recognition

AI may recognize, rank, classify, explain, or propose a command. It may not:

- create, restore, remove, resolve, reopen, collect, purchase, or finish silently;
- infer purchase from legacy completion or collection;
- treat confidence as identity or truth;
- bypass exact identity, user intent, or current revision validation.

A reviewed AI candidate enters the same Product or list command used by manual input. AI-specific persistence remains transient or Product Knowledge-owned until that command commits.

### 8.3 Catalog

Catalog is read-only input to user Product State:

- Catalog owns stable concept IDs, taxonomy, aliases, status, and redirects.
- Product owns its Catalog reference and saved offline snapshot.
- Exact canonical Catalog identity may support deduplication.
- Catalog inactive/replaced/missing status does not remove, restore, resolve, reopen, collect, or purchase.
- Redirect resolution preserves user Product UUID and history.
- Catalog snapshot refresh, if later authorized, is a separate metadata action and never a lifecycle side effect.

### 8.4 Product Knowledge

Product Knowledge provides bundled and learned recognition/search evidence. It:

- remains independent of Product UUID and Library lifecycle;
- may help recognize or prefill a candidate;
- is retained when a Product is removed/restored;
- cannot create membership, resolution, Session outcome, purchase history, or Catalog Truth;
- cannot be silently merged with Product History.

### 8.5 Shopping Plan

Shopping Plan consumes exactly one list revision and explicit entry IDs. It:

- declares included and unresolved/excluded entries;
- records enough input identity to detect staleness;
- provides recommendations, not Product truth;
- supplies an immutable snapshot to Session start;
- never writes list or Product state;
- becomes Stale when a declared source input changes.

### 8.6 Map

Map consumes one explicit context:

- selected named-list projection;
- current Ready plan; or
- active Session snapshot.

Map displays Product/store estimates and may initiate a named command. It must not fall back to global compatibility items, toggle lifecycle fields, treat store likelihood as availability truth, or use saved locations as a shadow Shopping list.

### 8.7 Notifications and Geofencing

Notification/reminder context must carry or resolve:

- payload format identity;
- owning list, plan, or Session identity;
- owning revision/snapshot version;
- compact reminder/store identity;
- safe deep-link target.

Before scheduling, delivery, action handling, or routing, the adapter validates current owner and revision. A valid active-Session notification opens that exact Session. A non-Session list reminder opens its named list. Stale or unknown context is suppressed or opens a safe Shopping state with an explanation. Payload content cannot mutate Product State.

### 8.8 Saved Locations

Saved Locations own location/store-note data and privacy-governed coordinates. Legacy `ShoppingItem` relationships are preserved only as evidence/archive during migration.

Target behavior:

- reminder eligibility comes from a revisioned list/plan/Session projection;
- only exact provable Product/list links may be mapped;
- unprovable notes remain explicitly non-authoritative;
- saved-location UI has no Product lifecycle toggle;
- any requested Product/list change uses the same named domain command as its owner surface.

### 8.9 Shopping History

History is a transactional output of named commands and a read-only input to Recent Products, personalization, and replenishment projections.

- Events must retain outcome meaning and provenance.
- Aggregates may be derived for performance.
- Legacy aggregates remain labeled compatibility input.
- History never decides current Library, list, plan, Session, or Catalog state.
- Personalization cannot upgrade an aggregate or observation into purchase truth.

### 8.10 Discovery and Decision Support

Discovery and decision engines consume explicit list/plan/Session projections, Catalog/Product Knowledge, and bounded context. They may rank and explain possibilities. They must expose unresolved exclusions and uncertainty and may only initiate a user-authorized named command.

### 8.11 Store Recommendations

Store recommendation boundaries consume scoped entry IDs, Catalog classification, saved-location evidence, and published Store evidence. They:

- return estimated matches and coverage;
- retain uncertainty and source scope;
- do not claim live inventory without a separate truth source;
- do not resolve, collect, purchase, or remove Products;
- cannot rewrite an active plan or Session snapshot.

### 8.12 Home and Other Presentation Surfaces

Home list cards open their exact named list. Session resume surfaces open the exact Session. Product, Shopping, Home, Map, and notification surfaces must display the same scoped meaning and use the approved vocabulary:

- Product Library, Needed, Resolved, Remaining, Collected, Purchased, Already Have, No Longer Needed, Unavailable, Skipped, Carry Forward, Removed from Library, Restore, Reopen, and Finish Shopping.

Product Library has no lifecycle checkmark. List and Session controls pair text with any icon/color, preserve scope under Dynamic Type and RTL, and expose object, scope, state, and result to accessibility.

The binding v1.0.3 base vocabulary is:

| Semantic meaning | English | Hebrew |
|---|---|---|
| Product Library | Product Library | ספריית המוצרים |
| Shopping List | Shopping List | רשימת קניות |
| Needed | Needed | דרוש |
| Resolved | Resolved | טופל |
| Remaining | Remaining | נותר |
| Collected | Collected | נאסף |
| Purchased | Purchased | נרכש |
| Already Have | Already Have | כבר יש לי |
| No Longer Needed | No Longer Needed | כבר לא דרוש |
| Unavailable | Unavailable | לא זמין |
| Skipped | Skipped | דילוג |
| Carry Forward | Carry Forward | העברה להמשך |
| Keep Needed | Keep Needed | השאר כדרוש |
| Removed from Library | Removed from Library | הוסר מהספרייה |
| Restore to Product Library | Restore to Product Library | שחזור לספריית המוצרים |
| Reopen | Reopen | פתיחה מחדש |
| Finish Shopping | Finish Shopping | סיום הקנייה |
| Legacy reason unknown | Legacy reason unknown | סיבת מצב קודם אינה ידועה |

Sentence-level inflection may adapt to context but must not change these meanings. “Checked,” “complete Product,” and “incomplete Product” are not approved Product State terms.

---

## 9. Migration Compatibility

### 9.1 Migration Owner

One Product State semantic migration coordinator runs after physical schema evolution and before writable target Product State UI. It exclusively owns:

- pre-migration inventory and recoverable original-store protection;
- deterministic legacy interpretation;
- entry normalization and exact-reference aliasing;
- legacy Session normalization;
- history preservation;
- exception classification;
- target invariant validation;
- atomic semantic completion marking;
- privacy-safe aggregate diagnostics.

Runtime views, startup backfill, Catalog repair, and compatibility services must not reinterpret target lifecycle meaning.

### 9.2 Required Legacy Interpretation

- Exact entry existence establishes exact-list membership.
- Legacy unchecked entry becomes Needed.
- Legacy checked entry becomes Resolved `legacyUnknown`.
- Compatibility completion never overrides an exact entry.
- Compatibility state without an entry creates no Product completion, membership, resolution, or purchase.
- Duplicate grouping uses exact list ID and Product UUID only.
- For an exact duplicate group, the survivor is the earliest `createdAt` entry, with lexicographically smallest UUID as the tie-breaker.
- The duplicate survivor retains the earliest creation time, maximum valid positive quantity, and minimum valid sort order; quantity is never summed.
- The duplicate survivor is Needed if any duplicate was Needed; otherwise it is Resolved `legacyUnknown`.
- Exact old-entry references are rebound through a recorded old-entry-ID-to-survivor-ID alias; non-survivors are removed only after reference validation and original-store protection.
- Every duplicate merge is recorded without private content and a second migration run causes no data or timestamp drift.
- Rows that differ in exact list ID or Product UUID are not duplicates and become exceptions.
- Missing relationships repair only through an exact stored Product UUID.
- Missing/unprovable Product or list identity becomes an exception; text matching is prohibited.
- A legacy Session line resolves first by exact compatibility UUID, then by exact source list ID, then by exact entry alias; zero or multiple matches produce an unresolved snapshot line.
- Legacy Session UUID, context, times, display snapshots, item IDs, and collected IDs are preserved; collected IDs remain provisional evidence and never final outcomes.
- Every legacy non-terminal Session remains a recovery candidate; the user explicitly selects one to resume or abandons candidates before normal shopping.
- Completed/Recent records become read-only legacy activity archive.
- Legacy Product History aggregates remain unchanged and non-authoritative unless an exact durable Product UUID link is already proven.
- Tombstones remain Removed; current list/non-terminal Session contradictions become exceptions and never cause restoration.

### 9.3 Temporary Legacy Compatibility

Before cutover, legacy values may be read only by:

- semantic migration;
- Phase 1 characterization;
- an explicitly bounded one-way compatibility adapter.

If an internal pre-release mirror is necessary:

- the target command decides and commits first;
- the legacy value is derived from the target in the same transaction;
- reverse synchronization is prohibited;
- the mirror cannot choose a list, restore/remove a Product, resolve/reopen an entry, or record purchase;
- target code never falls back to legacy values when target data is absent.

### 9.4 Cutover Expectations

The released authority cutover is one coherent boundary:

1. target schema and semantic migration complete successfully;
2. all target invariants validate;
3. every authoritative writer uses a named target command;
4. every consumer uses target projections;
5. Map, notifications, saved locations, scanner, Catalog acquisition, history, and Session integrations have moved together;
6. legacy-authority read and direct-write counts are zero;
7. target writable UI opens only after the above conditions hold.

No released state may mix target Shopping/list authority with legacy Map, notification, Session, or UI authority.

### 9.5 Backward Compatibility and Removal Conditions

- Physical legacy fields/models may remain read-only through v1.0.3 for support and forward-compatible rollback.
- Physical retention does not retain semantic authority.
- Old payloads are parsed defensively only through stable migration mappings and current-state validation.
- An old-authority binary may not reopen a target-written store for normal mutation.
- Physical compatibility removal requires a later separately approved schema release.
- Removal requires proven zero authoritative readers/writers, migrated-store recovery, protected rollback, and complete regression evidence.
- There is no reverse migration that reconstructs legacy truth from target state.

### 9.6 Migration Failure and Recovery

- A recoverable copy/fingerprint boundary covers the original store and sidecars before semantic writes.
- Failure leaves that boundary intact, reports non-success, and blocks writable target UI.
- Empty-store recreation or in-memory fallback is never described as successful migration.
- Interrupted migration is idempotent and resumes from stable migration identity and validated state, not wall-clock time.
- Unresolved exceptions remain preserved and visible through a safe recovery projection.
- After successful target writes, rollback is forward-compatible; explicit backup restoration warns of later-data loss.

---

## 10. Acceptance Criteria

### 10.1 Specification Approval Checklist

- [x] Purpose, goals, and non-goals are explicit.
- [x] One source of truth per lifecycle is defined.
- [x] Read and write responsibilities are separated.
- [x] Product, Library, lists, entries, plan, Session, history, Catalog, Product Knowledge, saved locations, notifications, AI, Map, migration, and compatibility owners are defined.
- [x] Allowed writers, readers, persistence owners, transaction owners, and integration consumers are defined.
- [x] Product, list, plan, Session, history, and saved-location command categories are defined.
- [x] Command inputs, outputs, preconditions, postconditions, failure behavior, and ownership are defined conceptually.
- [x] Every query projection is read-only and side-effect-free.
- [x] Atomicity, revision, idempotency, rollback, failure, recovery, and external-effect rules are defined.
- [x] Target invariants are explicit and testable.
- [x] All required integration contracts are defined.
- [x] Migration compatibility, cutover, backward compatibility, and removal conditions are defined.
- [x] WT-032A D-01 through D-37 are preserved and traceable.
- [x] S-00 duplicated-write, direct-write, mixed-authority, transaction, and recovery findings have target boundaries.
- [x] No implementation API, Swift code, schema design, migration stage, project change, or file plan is introduced.
- [ ] Product/Architecture approval has been recorded.
- [ ] A later implementation specification resolves the technical implementation choices without changing this contract.

### 10.2 Conformance Gates for Later WT-033 Work

Later WT-033 implementation work is conformant only when it proves:

1. every production mutation is routed through the owning named command;
2. production views and integrations have zero direct lifecycle persistence writes;
3. every query is side-effect-free and scoped;
4. entry uniqueness, expected revision, and command idempotency hold under concurrency and retry;
5. list A changes do not alter list B;
6. Product removal/restoration, active-Session protection, and all-list effects match this contract;
7. plan/list/Map/notification identity parity holds;
8. Session collection remains isolated and Finish reconciles every line atomically;
9. Product History never overclaims purchase;
10. Catalog, Product Knowledge, saved locations, scanner, AI, Map, and notifications remain non-authoritative;
11. migration is conservative, idempotent, fail-closed, and recoverable;
12. compatibility readers/writers reach zero authority at cutover;
13. accessibility/localization semantics remain scoped and explicit;
14. current Phase 1 characterization is replaced only where the approved target intentionally changes behavior;
15. repository, migration, regression, performance, privacy, and rollback evidence passes before release.

### 10.3 Open Questions

No Product State architecture or policy question remains open inside this specification. WT-032A D-01 through D-37 are binding.

The following are intentionally unresolved implementation choices and may not alter the authority contract:

- exact SwiftData models, fields, relationships, indexes, and migration stages;
- exact repository, command, query, and transaction APIs;
- exact serialization mechanism for command concurrency and revision enforcement;
- exact original-store/sidecar protection procedure and exception-ledger representation;
- exact notification payload encoding and legacy support duration;
- production-scale release thresholds beyond the recorded Phase 1 baseline;
- exact sentence-level English/Hebrew copy and bidirectional QA;
- future privacy erasure, Archive, Cloud/Android synchronization, and compatibility-storage removal release.

These choices require later approved specifications before production implementation.

---

## 11. Out of Scope

This specification does not define:

- Swift or any other implementation language code;
- concrete protocols, methods, parameters, return types, dependency injection, or actor/threading design;
- files, target membership, Xcode settings, packages, feature flags, or build configuration;
- SwiftData entity/attribute/relationship/index design;
- a V4 or later schema or any migration stage;
- exact migration batching, disk-space, file-copy, or sidecar algorithms;
- exact exception-ledger storage or recovery-screen implementation;
- full Shopping Session background execution, expiration policy, reminder budgets, battery/thermal behavior, or multi-device leases;
- notification/geofence platform mechanics or payload binary format;
- Product privacy erasure, legal retention, backup retention, or account policy;
- Cloud synchronization or conflict resolution;
- Android persistence or UI implementation;
- Community Feedback, moderation, trust, or publication implementation;
- retail SKU, price, inventory, availability, or purchase-verification truth;
- autonomous AI mutation policy;
- Catalog content, icon, alias, or taxonomy changes;
- list archive/close/delete policy not already approved;
- general UI redesign;
- analytics taxonomy or production telemetry;
- performance optimization or capacity guarantees;
- physical compatibility-storage removal.

---

## 12. Traceability

### 12.1 Section-to-Authority Matrix

| Specification section | WT-030 authority | WT-031A authority | WT-032A decisions | WT-032B / Phase 1 evidence | WT-033A S-00 discovery |
|---|---|---|---|---|---|
| 1. Executive Summary | Summary §§2–4, 6, 10; WT-030A §§13, 17 | §§1–2, 5, 6, 9 | D-01–D-37 collectively | §§1–4, 13–15 | §§1, 5–7 |
| 2. Product State Philosophy | Summary §§2–3, 6, 10; WT-030A §13.1 | §§4–6 | D-01, D-03, D-06, D-08, D-12, D-33, D-35–D-37 | Current/target distinction in §§1–4 | §§1, 4–7 |
| 3. Lifecycle Authorities | Summary §§4.1, 6; WT-030A §§13.2–13.10 | §§5.1–5.7, 11 | D-01–D-24, D-32–D-36 | Baseline authority inventory §4 | §§1–5 |
| 4. Command Architecture | Summary §§3, 6, 10; WT-030A §§13.11, 15 | §§5, 8–11 | D-02–D-18, D-20–D-23, D-35–D-37 | CB/KD characterization §4 | §§2, 4, 6 |
| 5. Query Architecture | Summary §§3, 6, 10; WT-030A §§13.10, 15.3, 15.5 | §§5.4, 6, 11 | D-01, D-08, D-10–D-14, D-19–D-23, D-33 | Consumer baseline §§4–5 | §§3, 5–6 |
| 6. Transaction Rules | Summary principles 3, 4, 8, 11; WT-030A §§13.11–13.12, 15.4, 17 | §§6–7, 13–14 | D-09, D-11, D-13–D-17, D-24, D-26, D-34–D-37 | Persistence/repair baseline §§4–7 | §§2, 4, 6 |
| 7. Invariants | Summary §§3, 10; WT-030A §§13.12, 18 | §§5–7, 12 | D-01–D-37 | Exit/definition evidence §§14–15 | §§1, 6–8 |
| 8. Integration Contracts | Summary §§2, 4, 6, 10; WT-030A §§14, 15.5, 16.4–16.14 | §§10–11, 15–16 | D-01, D-03, D-06, D-11–D-14, D-16–D-23, D-31, D-33, D-36 | Consumer/diagnostic baseline §§4–7 | §§2–5 |
| 9. Migration Compatibility | Summary principles 5, 11; WT-030A §17 | §§6–7, 9 | D-18, D-24–D-34, D-37 | Migration fixtures/evidence §§4–6, 10 | §§1–6 |
| 10. Acceptance Criteria | Summary §§10–12; WT-030A §18 | §§12, 18–19 | D-01–D-37 | §§10, 14–18 | §8 |
| 11. Out of Scope | Summary §§9, 12; WT-030A §§2, 19 | §§2, 16–17 | §2.2, §19; D-18, D-33–D-34 boundaries | §2.2 | §7 and S-00 disposition |
| 12. Traceability | Summary §§4, 6–8 | §§12, 15, 18 | §17; D-01–D-37 | §17 | §§1–8 |

### 12.2 WT-032A Decision Coverage

| Decisions | Contract location |
|---|---|
| D-01–D-03 | §§2–5, 7–8: no global completion; explicit entry resolution; collection remains Session-local |
| D-04–D-05 | §§3.4, 4.5, 6.4, 7.4: complete Finish outcomes and distinct Abandon |
| D-06–D-07 | §§3.1, 3.5, 4.6, 5.2, 7.4, 8.9: immutable UUID-keyed history and retention |
| D-08–D-10 | §§3.3, 4.3, 5.2, 7.3: multiple lists, uniqueness, retained Resolved entries, explicit Reopen |
| D-11–D-12 | §§3.1, 3.3–3.4, 4.3–4.5, 5.2–5.3, 6.2: durable list revision and immutable plan/Session snapshots |
| D-13–D-14 | §§3.4, 4.3, 4.5, 5.2, 7.3–7.4: active-Session edit protection and explicit start conflict |
| D-15–D-18 | §§3.2, 4.2, 6.3, 7.2: recoverable all-list removal, active-Session block, explicit indefinite Restore, no erasure command |
| D-19, D-20, D-21, D-22, D-23 | §§3.3–3.5, 5.2, 8: Completed/Recent retirement, semantic presentation/routing, explicit acquisition, saved-location separation |
| D-24–D-27 | §9: one migration owner, deterministic flags/duplicates, exact-reference orphan policy |
| D-28, D-29, D-30, D-31, D-32 | §§4.5, 5.2, 9.2: legacy Session recovery, multiple candidates, archives/history, tombstone exceptions |
| D-33–D-34 | §§2.4, 6.5, 7.5, 9.3–9.6: zero legacy authority, original-store protection, forward-compatible rollback |
| D-35–D-37 | §§4, 6, 7: atomic commands, atomic Finish, command-level uniqueness/revision enforcement |

### 12.3 S-00 Finding Resolution Map

| S-00 current finding/risk | Target contract response |
|---|---|
| Compatibility item is a shared cross-surface authority | §§2–3 and 9 make compatibility one-way/transitional and require zero authority at cutover |
| Product/list/session/history writes are distributed | §§3–4 assign named owners and command-only writes |
| Direct SwiftUI `ModelContext` mutations bypass services | §§2.3, 7.1, and 10.2 prohibit presentation lifecycle persistence |
| Entry checked and compatibility completion express competing truths | §§3.3, 4.3, and 7.3 make the entry lifecycle sole list authority |
| Missing duplicate invariant | §§4.3, 6.2, and 7.3 require exact uniqueness under concurrency/retry |
| Runtime list revision and plan invalidation are view-driven | §§3.1, 4.3–4.4, 5.2, and 6.2 assign durable revision ownership |
| Session start silently reuses context and Finish changes only header | §§4.5 and 6.4 require explicit conflict handling and atomic reconciliation |
| History aggregates can overclaim completion | §§3.5, 5.2, 7.4, and 8.9 restrict history to named evidence |
| Barcode/Catalog acquisition can restore implicitly | §§4.2 and 8.1–8.3 require `restoreRequired` and explicit Restore |
| Startup backfill co-owns semantic repair | §9 gives interpretation and completion to one pre-UI migration owner |
| Saved locations own a parallel compatibility lifecycle | §§3.1, 4.6, 5.2, and 8.8 separate location evidence from Product State |
| Map/notification payloads can become stale authority | §§5.2–5.3 and 8.6–8.7 require owner/revision validation |
| External effects are split from local commits | §6.6 defines idempotent post-commit reconciliation |
| Recovery can expose empty or ephemeral state as success | §§6.5 and 9.6 prohibit false durable success |
| Raw `ModelContext` coupling obscures transaction ownership | §§2.3, 3.1, 4, and 6 place persistence behind owning command/repository boundaries |

### 12.4 Approval Disposition

The Product State authority contract is complete for S-01 review. No approved WT-032A decision has been changed, and no current legacy behavior has been promoted to target architecture.

Approval of this document permits later WT-033 implementation specifications to consume it. Approval alone does not authorize production, test, schema, migration, project, package, localization, Catalog, or prior-document changes.
