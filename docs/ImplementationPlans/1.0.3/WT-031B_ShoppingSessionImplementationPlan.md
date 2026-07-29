# WT-031B — Shopping Session Implementation Plan

**WayTask iOS — Version 1.0.3**  
**Status:** Implementation planning only  
**Architecture baseline:** WT-030B Session-Scoped Persistent Hybrid  
**Implementation authorization:** Not granted by this document  
**Permitted document change:** This file only

## Document Use and Evidence

This plan translates the approved Shopping Session architecture into implementation work. It does not reopen WT-030B, alter the architecture consolidated by WT-030, define production schema syntax, or authorize source changes.

The plan distinguishes four kinds of statement:

- **Current — verified:** observed in the repository as it exists at the time of this plan.
- **Approved:** binding behavior established by WT-030B and `WT-030_ArchitectureSummary.md`.
- **Planned:** the implementation work required to move from the verified current state to the approved state.
- **Unresolved:** a decision intentionally left open by WT-030B or by verified legacy-data ambiguity.

The controlling sources were read together:

- `docs/Audits/1.0.3/WT-030B_ShoppingSessionBackgroundAudit.md`;
- `docs/Audits/1.0.3/WT-030_ArchitectureSummary.md`;
- `docs/ImplementationPlans/1.0.3/WT-031A_ProductStateImplementationPlan.md`;
- the available repository Product Specification, `design/v1.0/WayTask_Product_Specification_v1.0.pdf`;
- the current persistence, lifecycle, Shopping, Map, Core Location, notification, store-resolution, diagnostics, and test implementation.

The repository does not currently contain a `Version_1.0.3_ProductSpec.md`; no such filename or content is assumed. The approved WT-030 architecture controls where the available v1.0 Product Specification describes earlier or deferred behavior.

---

## 1. Executive Summary

### 1.1 Current implementation problem

**Current — verified:** WayTask persists a minimal `ShoppingSession` row containing `isActive`, two comma-delimited `ShoppingItem` UUID arrays, optional list identity, and one selected-store snapshot. `ShoppingSessionService` starts a row, toggles collected IDs, and finishes it. A new Start silently returns the newest active row even when the requested list or store differs. There is no explicit expired or abandoned state, no durable plan or stop model, no source-list revision, no session-line snapshots, no reminder policy, no registration ledger, and no atomic Finish reconciliation.

Session persistence is therefore more durable than the in-memory Shopping Plan but less complete than the user-visible Shopping journey. After relaunch, the app can recover the IDs and selected store, but it cannot recover the exact execution plan, missing Product display context, stop assignments, remaining-line decisions, or reminder authority.

The current background system is independent of the session. `LocationManager` begins best-accuracy standard updates whenever location is authorized, refreshes regions from global open `ShoppingItem` data, calls foreground store resolution, embeds names, item IDs, list ID, coordinates, and a distance in each region identifier, and schedules an immediate local notification on entry. The callback does not re-read a persisted session. Notification taps trust the payload and open Map. Session recovery, conversely, waits for notification settings to leave `.notDetermined`. These paths mix session state, list state, runtime state, notification capability, and stale payload state.

### 1.2 Approved target architecture

**Approved:** WayTask adopts the **Session-Scoped Persistent Hybrid**:

- one durable Shopping Session is the business authority;
- app foreground, background, suspension, and termination are process states, never session states;
- a started session owns an immutable execution snapshot with stable lines and stops;
- explicit session states are `active`, `expired`, `finished`, and `abandoned`;
- exact committed progress is recoverable offline and independently of notification permission;
- expiration is deterministic from persisted policy and timestamps;
- location reminders are a local, derived, best-effort projection of one active session revision;
- region identifiers are compact and opaque;
- every region event revalidates persisted session, revision, expiry, preference, stop, and remaining lines;
- no planner, MapKit search, AI request, broad synchronization, or Product/list mutation runs in a background region callback;
- standard location is bounded to a visible foreground consumer; region monitoring is the default background proximity mechanism;
- finish, abandon, and expiration disarm regions and invalidate late events;
- passive nearby opportunities, if retained, are a separate opt-in feature and never session authority.

### 1.3 Proposed implementation approach

**Planned:** implement the approved architecture as one coordinated authority cutover:

1. freeze current behavior with characterization, migration, adapter, race, and energy baselines;
2. complete the WT-031A identity prerequisites: stable list-entry identity, durable list revision, immutable Product/display snapshot contract, and the shared Finish reconciliation boundary;
3. introduce the next versioned persistence model and conservatively migrate every legacy session without treating legacy arrays as runtime authority;
4. make `ShoppingSessionService` the command boundary over one durable aggregate and add a process-independent recovery coordinator;
5. make Home, Shopping, Map, and navigation consume session projections rather than `isActive` or the in-memory plan once a session has started;
6. replace global session-like regions with a desired-versus-actual reminder projection, compact registration ledger, platform adapter, and background validator;
7. cut every consumer and writer over together, disarm legacy regions, remove runtime fallbacks, and qualify offline recovery, migrations, races, accessibility, localization, battery, and device lifecycle behavior.

The plan does not require changing correct current responsibilities. Store search and trip scoring remain foreground plan-generation concerns. SwiftData remains the local durable store. Core Location region monitoring remains the background proximity primitive. `UNUserNotificationCenter` remains the delivery mechanism. Map remains a presentation/navigation surface. Sentry and beta diagnostics remain privacy-minimized observability sinks.

### 1.4 Expected phases

The implementation is divided into a decision/specification gate, characterization, WT-031A prerequisite integration, persistence and migration, session commands and recovery, reminder/background conversion, cross-surface conversion, qualification, and a single release cutover. Development may be internally incremental, but no public build may expose both legacy and target session authorities.

---

## 2. Scope

### 2.1 Included in WT-031B

WT-031B plans:

- session creation from a named list revision and a current plan;
- atomic creation of session, stops, lines, and execution snapshot;
- explicit `active`, `expired`, `finished`, and `abandoned` lifecycle;
- explicit Start conflict handling;
- line collection and undo;
- remaining-line reconciliation at Finish;
- session expiration, explicit Resume, and explicit Abandon;
- immutable plan/store/display snapshots;
- session and registration revisions;
- startup, warm-launch, cold-launch, scene, crash, migration, and partial-failure recovery;
- persistence mode handling, including recreated-store and in-memory degradation;
- bounded foreground location consumption;
- session-scoped region selection, registration, reconciliation, and removal;
- compact notification registration identity;
- background validation and notification projection;
- notification-tap validation;
- offline session execution;
- diagnostics, idempotency, race handling, rollback boundaries, and battery qualification;
- cross-surface session projections for Shopping, Home, Map, Settings, and notifications;
- compatibility handling for legacy session rows, region identifiers, and notification payloads;
- all tests needed to prove the WT-030B acceptance criteria.

### 2.2 WT-031A boundary

WT-031A owns:

- Product identity and library lifecycle;
- named Shopping-list entry lifecycle;
- stable `ShoppingListEntry` identity;
- the authoritative persisted list revision;
- plan projection identity against a list revision;
- Product and list snapshot semantics;
- list/history effects of Finish;
- removal, restoration, list isolation, and Product History semantics.

WT-031B consumes those contracts. It owns the session aggregate, frozen session lines and stops, session state transitions, recovery, expiration, and reminder projection. The two plans share exactly one session-line identity and one atomic Finish transaction boundary. WT-031B must not create parallel Product, list-entry, list-revision, or history authority.

### 2.3 WT-031C boundary

Community evidence, moderation, Catalog Truth, Store Truth publication, report trust, and feedback synchronization remain WT-031C work. A community or catalog update may make source data newer, but it cannot silently mutate an active session snapshot. Any future explicit session update must create a new session revision and reminder reconciliation.

### 2.4 Explicit exclusions

This plan does not authorize or define:

- production code, schema syntax, tests, project settings, entitlements, or commits;
- a new Product State architecture;
- a second Shopping Session architecture for multi-store use;
- continuous background GPS;
- periodic background polling as session authority;
- significant-location-change recomputation as session authority;
- calendar-triggered or AI-triggered automatic sessions;
- CloudKit or backend synchronization;
- multi-device notification ownership;
- Android implementation;
- passive nearby opportunities unless separately approved and specified;
- inventory certainty or automatic catalog/store truth changes;
- route optimization, SKU inventory, or retailer stock integration.

### 2.5 Release-unit rule

All production consumers must cross the authority boundary in one release unit. It is acceptable to develop target components behind non-production gates and to migrate data before UI cutover. It is not acceptable to ship a state where `isActive`, the legacy UUID arrays, global open `ShoppingItem` data, an in-memory `ShoppingPlan`, or a frozen notification payload can compete with the target session aggregate.

### 2.6 Planning-requirement coverage

| Required concern | Primary plan location |
|---|---|
| Session creation | Sections 5–7 and Phase 4 |
| Session restoration | Sections 6, 7, and 11 |
| Session persistence | Sections 5, 7, and 12 |
| Session expiration | Sections 6–8 |
| Session abandonment | Sections 6–7 |
| Session completion | Sections 6–7 and WT-031A Finish integration |
| Session recovery and startup recovery | Section 11 |
| Plan snapshots | Sections 5, 12, and 15 |
| Revision validation | Sections 5–7, 9, and 12 |
| Notification validation | Section 9 |
| Geofence validation | Sections 8–10 |
| App relaunch and scene restoration | Sections 6, 8, and 11 |
| Force quit behavior | Sections 6, 8, 11, and 17 |
| Offline execution | Section 15 |
| Migration | Section 12 and Phase 3 |
| Diagnostics | Sections 13, 16, and 17 |
| Recovery after partial failure | Sections 11–12 and 17 |
| Rollback | Sections 12, 14, 17, and 18 |
| Battery considerations | Sections 8, 10, 14, 16, and 17 |

---

## 3. Current Implementation Inventory

### 3.1 Current authority and data flow

**Current — verified:**

```text
ShoppingListEntry
     |
     | legacyShoppingItemID join
     v
ShoppingItem.isCompleted ----> AppStateManager.shoppingPlan (memory only)
     |                                      |
     | Start Shopping                       | Map presentation
     v                                      v
ShoppingSession                         MainMapView / MapViewModel
isActive + raw UUID arrays
     |
     +----> ShoppingWorkspaceView / HomeView

Global open ShoppingItem + GeoLocation + StoreResolutionEngine
     |
     v
LocationManager cached candidates
     |
     v
Core Location identifier containing context
     |
     v
GeofenceNotificationService ----> UN notification ----> AppStateManager ----> Map
```

The persisted session does not own the geofence or notification path. The runtime plan does not survive process death. The list-entry join depends on a legacy `ShoppingItem` identity. Each surface rebuilds some portion of Shopping context independently.

### 3.2 Models and domain types

| Path/type | Current — verified responsibility | Gap relevant to WT-031B |
|---|---|---|
| `ShoppingSession.swift` / `ShoppingSession` | SwiftData row with ID, start/finish timestamps, `isActive`, raw item/collected UUID strings, optional list ID, and one selected-store snapshot | No explicit lifecycle, revision, expiry, stops, durable plan, reminder policy, line snapshots, outcomes, or corruption visibility; malformed UUID tokens are silently dropped |
| `WayTask/Models.swift` / `ShoppingItem` | Legacy item identity, display fields, relationships to locations, and global `isCompleted` compatibility state | Currently leaks into plan, session, Map, geofence, and completion authority; target session may reference it only through migration/compatibility |
| `WayTask/Models.swift` / `ShoppingList`, `ShoppingListEntry` | Named list and Product membership; entry includes Product ID, optional legacy item ID, quantity, `isChecked`, order | Current persisted model has no authoritative monotonic list revision; WT-031A must establish it before session start validation |
| `WayTask/Models.swift` / `GeoLocation` and `MapViewModel.swift` / `RuntimeStore` (`MapStore`) | Saved and runtime store context, coordinates, radius, source, and display metadata | Runtime store data is rebuildable and may be unavailable later; started sessions need immutable stop snapshots |
| `AppStateManager.swift` / `ShoppingPlan` | In-memory plan request, items, stores, buying options, coverages, generation time, and content signature | No process durability, owning list revision, entry IDs, session ID/revision, or snapshot role |
| `ProductHistory.swift` / `ProductHistory` | Add-frequency memory and one last-completed timestamp | No session outcome history; Finish semantics belong to the WT-031A shared boundary |

### 3.3 Session services and Shopping flow

| Path/type | Current — verified behavior | Gap |
|---|---|---|
| `ShoppingSessionService.swift` / `ShoppingSessionServicing`, `ShoppingSessionService` | Starts or returns newest active row, fetches one active row, toggles collected IDs, finishes by setting `isActive = false` and `finishedAt`, saves immediately | Silent context conflict; commands do not validate state/revision; collect can append a foreign item; no abandon/expire/resume; mutation precedes save with no explicit rollback; no list/history reconciliation |
| `ShoppingTripService.swift` / `ShoppingTripService` | Scores foreground store coverage for non-completed `ShoppingItem` values | Correctly a plan-generation service; must not become session or background authority |
| `ShoppingListService.swift` | Manages Shopping lists and legacy entry compatibility/backfill | WT-031A must supply authoritative list revision and Finish operations; session code must call commands rather than mutate entry flags |
| `ShoppingMemoryService.swift` | Records add-frequency history keyed from legacy ShoppingItem data | Must not infer purchase from a session Finish; retain for add-memory until WT-031A history boundary replaces or adapts it |
| `StoreSearchService.swift` / `StoreResolutionEngine` | Resolves saved and MapKit/fallback stores for a foreground plan | Correct foreground ownership; currently called from geofence refresh and must be removed from background/reminder reconciliation |

### 3.4 UI, state management, and navigation

| Path/type | Current — verified behavior | Gap |
|---|---|---|
| `WayTask/ShoppingWorkspaceView.swift` | Selects list, joins entries to legacy items, generates plan, selects store, starts session, renders latest `isActive` row, toggles collected IDs, finishes, and opens Apple Maps | UI directly orchestrates persistence and runtime plan; no conflict/expiry/abandon/reconciliation screens; missing legacy items disappear from session display |
| `WayTask/HomeView.swift` | Finds newest `isActive` session, derives progress from raw arrays, otherwise shows runtime plan/list data | Duplicates session query/derivation; cannot express expired, abandoned, degraded, or reminder capability state |
| `WayTask/AppStateManager.swift` | Owns runtime plan, plan-generation state, tab routing, selected list, trip-map mode, notification delegate, and payload-derived Map context | Presentation state becomes de facto authority; list revision is an in-memory random UUID; notification taps do not load a session |
| `WayTask/ContentView.swift` | Runs backfill, refreshes global geofences/nearby opportunities, observes only `.active` scene transition, and performs one-time active-session routing | Recovery is a root-view side effect and waits for notification authorization; no expiration, conflict repair, degraded-store result, background cleanup, or process-independent handler |
| `WayTask/MainMapView.swift` | Applies runtime `ShoppingPlan`, global list items, or notification `StoreNavigationContext`; offers store navigation | Cannot recover a started session plan after relaunch and can display notification context unrelated to current session |
| `MapViewModel.swift` | Resolves, filters, scores, presents, and navigates runtime stores and active legacy items | Correct Map presentation/search role; must accept a session stop/line projection without owning session state |
| `WayTaskMapView.swift`, `MapBottomSheet.swift` | MapKit presentation and store/product labels | Correct presentation ownership; labels need session-scoped input when opened from a session |
| `SettingsView.swift` | Offers a manual notification-permission button and custom-store controls | No session reminder preference, capability explanation, or user-controlled location escalation flow |

### 3.5 Location and notification implementation

| Path/type | Current — verified behavior | Gap |
|---|---|---|
| `WayTask/LocationManager.swift` / `LocationManager` | Creates `CLLocationManager`, requests notification permission at initialization, starts best-accuracy standard location whenever authorized, automatically requests Always after When In Use, resolves up to 12 Shopping regions from global items, registers entry-only regions, and schedules notifications on entry | Location lifetime is not consumer-scoped; permission timing is not contextual; no session/revision validation or registration ledger; candidate resolution can invoke store work; desired and actual registrations are not durable |
| `GeofenceNotificationService.swift` / `ShoppingGeofenceCandidate`, `ShoppingGeofencePayload` | Encodes store/list/item names and IDs, coordinates, source, type, and frozen distance into the region identifier and notification payload | OS identifier is acting as stale context authority and exposes unnecessary human-readable data |
| `GeofenceNotificationService.swift` / `GeofenceNotificationService` | Requests authorization, applies store-only UserDefaults cooldown, builds availability-estimate copy, records cooldown before the request is added | Does not validate active session or eligible lines; cooldown can advance on failed scheduling; no session/revision idempotency |
| `AppStateManager` notification delegate | Parses userInfo, accepts a store ID, and opens Map context | No session/state/revision/expiry validation; valid session reminder and passive opportunity are not authoritative distinct paths |

### 3.6 Persistence, migration, startup, and recovery

| Path/type | Current — verified behavior | Gap |
|---|---|---|
| `WayTask/Persistence/WayTaskSchemaV1.swift` | Frozen v1 graph includes current `ShoppingSession` type | Legacy evidence must remain frozen and migratable |
| `WayTask/Persistence/WayTaskSchema.swift` / V2, V3, `WayTaskSchemaMigrationPlan` | V1→V2 and V2→V3 lightweight migrations; current V3 still uses the minimal session model | Target session aggregate requires a new frozen version and likely a custom semantic migration |
| `WayTask/Persistence/WayTaskStartupPersistence.swift` | Opens/repairs the store; on failure quarantines/recreates; finally offers in-memory fallback; returns persistence mode | Correct recovery foundation, but `WayTaskApp` discards the returned mode and session regions are not stopped on recreation/in-memory fallback |
| `WayTask/WayTaskApp.swift` | Starts diagnostics, obtains only `.modelContainer` from bootstrap, creates AppState and LocationManager, then renders UI | Cannot surface persistence degradation or initialize a minimal background event path separately from full UI/catalog startup |
| SwiftData save paths | Session service mutates tracked objects, then saves | A save error can leave in-memory values looking changed; no command result, rollback, revision compare, or idempotency record |

### 3.7 Capability and project configuration

**Current — verified:**

- `WayTask/Info.plist` contains When In Use and Always location usage descriptions plus notification usage copy.
- No `UIBackgroundModes`, `BGTaskSchedulerPermittedIdentifiers`, notification-service extension, or app entitlements file was found in the current target configuration.
- The project does not declare continuous background location.
- Core Location region monitoring is therefore the existing OS-managed background proximity mechanism; normal app suspension rules otherwise apply.
- The app does not implement a `BGAppRefreshTask`, significant-location-change service, background push path, or persisted background-work queue.

The absence of continuous background capability is correct for the approved default architecture and should be retained.

### 3.8 Current test and fixture coverage

**Current — verified:**

- `WayTaskTests/Persistence/WayTaskSchemaMigrationTests.swift` asserts the legacy `ShoppingSession` fields and migrates one finished v1 fixture.
- `WayTaskTests/Persistence/StartupPersistenceResilienceTests.swift` exercises open, repair, quarantine/recreation, in-memory fallback, and diagnostics behavior generically.
- `WayTaskTests/Persistence/StartupRepairIdempotencyTests.swift` covers current list repair idempotency.
- `WayTaskTests/ShoppingUX/ShoppingWorkspaceUXTests.swift` covers Shopping presentation policy but not the session lifecycle.
- `WayTaskTests/ShoppingClassification/OtherItemsClassificationTests.swift` exercises `ShoppingTripService` coverage behavior.
- Map tests cover product-label presentation, not session projections or notification validation.
- No direct `ShoppingSessionService` transition suite, expiration tests, session recovery tests, registration-ledger tests, region callback tests, notification race tests, force-quit field protocol, offline session suite, or battery baseline exists.

---

## 4. Current Authority Problems

### 4.1 Architectural authority defects

| ID | Verified defect | Consequence | Planned authority correction |
|---|---|---|---|
| AP-01 | `isActive` plus nullable `finishedAt` encode only an implicit two-state lifecycle | Expiration and abandonment cannot be represented; malformed combinations are possible | One explicit persisted session state with validated state/timestamp invariants |
| AP-02 | Item and collected membership are comma-delimited `ShoppingItem` ID arrays | No stable line identity, quantity, stop, Product snapshot, outcome metadata, or corruption visibility | Persisted session lines keyed to WT-031A entry/Product identity |
| AP-03 | Starting with any new context silently returns the newest active session | User may believe a different list/store was started | Explicit same-context Resume and different-context conflict decision |
| AP-04 | Multiple active rows are possible; readers select the newest | Older active rows remain authoritative to some future consumer and regions | Enforced single-active invariant plus observable migration/recovery policy |
| AP-05 | Runtime `ShoppingPlan` is richer than the persisted session and disappears after process death | Relaunch cannot reproduce the started journey | Atomic immutable plan/stop/line snapshot at Start |
| AP-06 | In-memory `shoppingListRevision` is a random UI token | It cannot validate persisted plans, sessions, notifications, or recovery | WT-031A persisted monotonic list revision consumed by plan/session |
| AP-07 | Collect can add an item not originally in the session | Session membership mutates accidentally and reminders can drift | Commands accept only stable existing session-line IDs at expected revision |
| AP-08 | Finish sets only a Boolean and timestamp | Remaining lines, list reconciliation, Product History, and success semantics are ambiguous | Explicit per-line reconciliation plus shared atomic WT-031A Finish transaction |
| AP-09 | Product/list compatibility flags influence planning, Map, regions, and session | State ownership is duplicated across lifecycles | Session commands consume immutable entry snapshots; compatibility fields are migration-only |
| AP-10 | Global open items, not the active session, drive regions | A user can receive reminders unrelated to the active trip | Session reminder projection derives solely from active session revision |
| AP-11 | Region identifiers contain the context later shown to users | Stale OS registrations can outlive session/list changes and leak labels | Compact opaque registration ID resolving to local persisted authority |
| AP-12 | Background entry does not open or validate the session | Finished, expired, changed, or missing sessions can still produce context | Background validator re-reads authority and suppresses on any mismatch |
| AP-13 | Cooldown is keyed only by store and recorded before scheduling succeeds | Independent contexts suppress each other; failed requests consume cooldown | Context-scoped ledger/idempotency updated only after successful scheduling |
| AP-14 | Notification tap opens payload-derived Map state | Delivered stale content can become current UI context | Revalidate; valid session reminder opens Shopping/current stop; stale result is safe and non-mutating |
| AP-15 | Recovery waits on notification permission | Denying or not yet answering reminders blocks durable session recovery | Domain recovery always runs first; capabilities are evaluated second |
| AP-16 | LocationManager starts best-accuracy updates without a visible consumer | Avoidable foreground battery/privacy cost | Consumer-scoped foreground location leases and explicit stop |
| AP-17 | Location authorization automatically escalates from When In Use to Always | Permission intent is not tied to a chosen reminder feature | In-context, user-initiated escalation with capability explanation |
| AP-18 | `ContentView` owns startup repair orchestration, region refresh, and routing | Domain recovery depends on view appearance and scene timing | Dedicated recovery/session coordinators; UI consumes typed results |
| AP-19 | Startup persistence mode is discarded | Recreated or nondurable stores can appear normal and arm regions | Propagate mode; disarm/suppress and surface degraded state |
| AP-20 | Save failure occurs after tracked-object mutation | UI may project uncommitted state | Transactional command boundary, context rollback/reload, typed failure |

### 4.2 Derived and mixed authority

The target must remove these current derivations:

- newest `ShoppingSession` where `isActive == true` as an implicit uniqueness policy;
- `remaining = itemIDs - collectedItemIDs` without explicit line outcomes;
- a missing `ShoppingItem` being silently omitted from session UI;
- an in-memory plan being accepted because its content signature appears unchanged;
- session context inferred from selected tab, selected list, trip-map mode, or notification userInfo;
- region eligibility inferred from every globally incomplete legacy item;
- reminder capability inferred from session existence;
- session recovery inferred from notification permission;
- expiration inferred from elapsed UI timers;
- finish inferred from all collected items or from `ShoppingItem.isCompleted`.

### 4.3 Correct ownership to retain

No change is recommended solely for architectural purity in these areas:

- SwiftData remains local persistent authority.
- `ShoppingTripService`, `StoreResolutionEngine`, and store ranking remain foreground plan-generation services.
- MapKit search and Apple Maps navigation remain Map/foreground integrations.
- Core Location region monitoring remains the default best-effort background proximity primitive.
- `UNUserNotificationCenter` remains notification scheduling and delivery.
- `WayTaskStartupPersistenceBootstrap` retains quarantine, recreation, and in-memory fallback mechanics.
- `WayTaskMapView` and `MapBottomSheet` remain presentation components.
- the existing conservative availability wording is retained, subject to session validation and localization.
- Sentry and beta diagnostics remain the observability channels, with identifiers hashed/aggregated and no Product names, coordinates, or notification copy added.
- the current absence of continuous background location, periodic background tasks, and unsupported force-quit guarantees is retained.

### 4.4 UX issues caused by architecture versus polish

Architecture-driven UX problems include silent wrong-session Resume, loss of the plan after relaunch, stale Map openings, inability to distinguish Finish/Abandon/Expire, missing lines disappearing, and session recovery being coupled to reminder permission. These require the authority changes in this plan.

Pure visual refinements—spacing, catalog icon rendering, input alignment, unrelated animation, and non-session card styling—are not WT-031B work. Session-state copy, capability copy, accessible labels, remaining-line reconciliation, and safe stale-notification results are in scope because they expose the approved lifecycle.

---

## 5. Target Session Domain Model

This section defines conceptual ownership only. Exact SwiftData annotations, storage layout, indices, relationship delete rules, and file splits require an approved implementation specification.

### 5.1 Aggregate ownership

```text
Shopping List + persisted revision       Foreground Shopping Plan
          \                                      /
           \ explicit Start at exact revision   /
            v                                  v
                 Shopping Session Aggregate
          +-------------+-------------+-------------+
          |             |             |             |
      Session header   Stops          Lines       Snapshot metadata
          |
          +----> lifecycle commands / recovery / UI projection
          |
          +----> desired Reminder Registration projection
                         |
                         v
                   Core Location / Notifications
```

The session aggregate is authoritative for a started journey. The source list remains authoritative for future shopping intent. The plan remains rebuildable before Start. Reminder registrations remain device-local projections. None may write another lifecycle except through an approved domain command.

### 5.2 Shopping Session

**Approved conceptual properties:**

- stable session ID;
- explicit state: `active`, `expired`, `finished`, or `abandoned`;
- `startedAt`, `lastActivityAt`, persisted expiration boundary/boundaries, and optional `endedAt`;
- source Shopping-list ID and source persisted revision;
- plan snapshot identity and content signature;
- reminder policy snapshot;
- current stop ID;
- monotonic domain revision;
- future sync metadata/tombstone semantics reserved without enabling Cloud.

**Planned invariants:**

- exactly one active session is permitted in the current local authority scope;
- state is the only lifecycle discriminator; compatibility flags are never read after cutover;
- `active` has no terminal `endedAt`;
- `expired` retains progress, has reminders disarmed, and can only Resume or Abandon;
- `finished` and `abandoned` have `endedAt` and are terminal;
- every command compares expected session ID/revision and increments revision on a successful business-state change;
- timestamps are supplied by an injectable clock and stored in a single canonical time basis;
- expiration policy values used by the session are durable so a later default change does not retroactively reinterpret an existing session;
- the header never stores Product completion or notification permission as business state.

### 5.3 Session Stop

**Approved conceptual properties:**

- stable stop ID and deterministic order;
- immutable store ID/reference plus display name, coordinates, source, and any necessary address snapshot;
- `planned`, `current`, `completed`, or `skipped` stop state;
- assigned session-line IDs;
- plan evidence timestamp and confidence snapshot;
- optional arrival and navigation timestamps.

**Planned invariants:**

- a single-store session is one stop in this model, not a different model;
- one stop is current at most;
- reminder eligibility uses the current and approved near-future stops within the region budget;
- store/catalog updates never rewrite a started stop;
- missing current store records do not erase the snapshot;
- stop transitions cannot mark lines purchased or mutate the source list.

### 5.4 Session Line

**Approved conceptual properties:**

- stable session-line ID;
- source Shopping-list entry ID;
- Product ID and Global Product Concept ID where available;
- immutable Product display snapshot sufficient for offline UI and notification copy;
- quantity snapshot;
- assigned stop ID;
- outcome: `remaining`, `collected`, `unavailable`, `skipped`, or `carriedForward`;
- outcome timestamp and optional actor/device metadata reserved for future synchronization.

**Planned invariants:**

- session line identity is the only target command key; legacy `ShoppingItem` UUID is migration evidence only;
- no missing source reference causes the line to be dropped;
- Collect is `remaining → collected`; Undo is `collected → remaining`;
- final outcomes are explicit and do not imply Product library state;
- Finish cannot leave a target-created line unresolved;
- the source list may change independently after Start;
- snapshots remain readable if Product, Catalog, Store, or list records later change or are unavailable.

### 5.5 Plan execution snapshot

The started-session snapshot includes:

- source list ID and exact revision;
- plan ID/content signature and generated/evidence timestamp;
- ordered stop snapshots;
- stable assignment of line IDs to stops;
- store evidence/confidence already available to the foreground plan;
- user-selected stop/store context;
- locale-independent identities plus localized display snapshots;
- enough data to recover Shopping Mode, progress, and Map/navigation offline.

The snapshot does not include a promise of inventory, live opening hours, a background MapKit result, or an AI-generated future action. Rebuilding a later plan does not alter the snapshot unless the user invokes a separately approved explicit Update Session command.

### 5.6 Reminder policy and capability projection

The session records the user’s reminder intent/policy snapshot, not OS permission truth. A separate capability projection derives:

- session active/inactive;
- notification authorization and quiet state;
- location authorization;
- Precise/approximate accuracy;
- region-monitoring availability and registration failures;
- Background App Refresh availability where it affects delivery messaging;
- foreground-only versus background-capable reminder behavior;
- reminder armed, degraded, unavailable, or expired.

Capability changes never demote or terminate the session. UI must be able to express, for example, “Shopping active — progress saved” and separately “Nearby reminder unavailable because Precise Location is off.”

### 5.7 Reminder Registration

**Approved conceptual properties:**

- compact opaque registration ID;
- session ID and session revision;
- stop/store ID;
- Core Location region identifier and notification request identity;
- desired/registered/suppressed/failed/removed status;
- created, updated, and registration-expiry timestamps;
- future device ID slot;
- last event and last successful notification timestamps;
- suppression/failure reason.

**Planned invariants:**

- it is local device projection state, never session or Product truth;
- one registration resolves to one current session revision and stop;
- human-readable Product/store content is loaded from persisted snapshots after validation;
- desired registrations are recomputable from the session;
- actual OS registrations are enumerated and reconciled;
- cooldown/idempotency scope includes feature, session, revision, stop/store, and event context;
- last-success time advances only after scheduling succeeds;
- terminal/expired session revisions have zero desired registrations.

### 5.8 Repositories, commands, projections, and adapters

The planned responsibility split is:

- **Session repository:** minimal local reads/writes, uniqueness queries, revision compare, aggregate loading, and background-safe lookup.
- **Session command service:** validates and atomically performs Start, Collect, Undo, Resume, Expire, Finish, and Abandon.
- **Recovery coordinator:** orders persistence-mode handling, migration/repair, session conflict checks, expiration, UI recovery result, capability evaluation, and registration reconciliation.
- **Session projection:** immutable view input for Home, Shopping, Map, and notification deep links.
- **Reminder coordinator:** computes desired registrations and reconciles them with the ledger and platform.
- **Location platform adapter:** owns `CLLocationManager` calls, region enumeration, registration/removal callbacks, permission state, and bounded foreground location leases.
- **Background session validator:** handles one compact event, reloads authority, validates, projects content, schedules idempotently, and returns promptly.
- **Notification router:** validates a delivered session reminder before navigation; keeps passive opportunity routing distinct.

Existing files may absorb these responsibilities where cohesion and testability remain clear. Proposed new files in Section 13 are candidates, not pre-authorized schema or abstraction decisions.

---

## 6. Session Lifecycle

### 6.1 State machine

**Approved:**

```text
No Session -- explicit Start --> Active
                                  |  \
                                  |   \---- explicit Finish ----> Finished
                                  |
                                  +-------- explicit Abandon ---> Abandoned
                                  |
                                  +-------- deterministic Expire -> Expired

Expired -- explicit Resume ------> Active
Expired -- explicit Abandon -----> Abandoned
```

`Finished` and `Abandoned` are terminal. `Expired` is persisted and resumable. App scene/process states do not appear in this machine.

### 6.2 Start

**Preconditions:**

1. the user explicitly chooses Start;
2. the source is one named Shopping list with a persisted revision;
3. at least one eligible list entry can become a session line;
4. the plan’s list ID, list revision, entry IDs, and content signature still match;
5. the selected stop/store context is adequate for the supported journey;
6. no existing active/expired conflict remains unresolved;
7. persistent authority is durable; in-memory mode follows the still-open degraded-mode product decision.

**Atomic result:**

- create one session header;
- create all lines with stable source IDs, Product/global-concept references where available, quantities, and display snapshots;
- create ordered stop snapshot(s) and assignments;
- store the plan identity/content signature and evidence;
- choose current stop;
- store timestamps, expiration policy snapshot, and initial revision;
- commit no partial aggregate if any validation/save fails.

After commit, UI projects the durable aggregate. Reminder enrollment is a separate capability result and may succeed, degrade, be declined, or fail without rolling back the session.

### 6.3 Existing-session conflict

| Existing authority | Requested context | Required presentation | Allowed command |
|---|---|---|---|
| None | Valid current plan | Start confirmation | Start |
| Active | Same session/list/plan context | Explicit Resume, not a new Start | Resume/open existing; state remains active |
| Active | Different list, revision, or plan/store context | Continue Existing, Finish Existing, Abandon Existing, or Cancel | Only the user-selected action |
| Expired | Any Start request | Explain saved progress; offer Resume or Abandon | Resume or Abandon; a new Start only after Abandon |
| Finished/Abandoned history only | Valid current plan | Normal new Start | Start |
| Multiple active legacy/recovery rows | Any | Recovery decision; no automatic Start | Approved recovery policy only |

The service returns a typed conflict result. It never substitutes another session for the requested Start.

### 6.4 Collect and Undo

Collect and Undo:

- require active state, stable session-line ID, expected session revision, and an allowed current outcome;
- update exactly one line and `lastActivityAt`;
- commit atomically and increment session revision;
- return an immutable updated projection;
- trigger reminder reconciliation after the commit because eligible remaining-line content may change;
- do not mutate Product, source list, other lists, plan evidence, or history;
- are idempotent for a repeated command with the same command/idempotency identity;
- fail visibly and reload committed authority on save/revision conflict.

Navigating to a stop may record a meaningful activity timestamp only if the open question is approved; merely foregrounding the app or receiving a location callback is not user activity.

### 6.5 Source list or plan changes while active

The active snapshot stays frozen. A source-list mutation:

- increments the WT-031A list revision;
- makes any future plan projection stale;
- does not add, delete, reorder, collect, or reassign active session lines;
- does not rewrite registered notification content in place;
- may result in a non-blocking “source list changed” explanation.

An explicit Update Session command is not assumed. If approved, it must validate a new plan, create a new session revision atomically, retain a trace of carried-forward line decisions, and reconcile all registrations. Until its policy is specified, the user finishes/abandons the session or continues with the frozen snapshot.

### 6.6 Finish

Finish is a user-confirmed transactional boundary:

1. load the active session at expected revision;
2. require an explicit final outcome for every line still `remaining`;
3. validate all outcomes and source identities;
4. atomically apply the WT-031A list-entry and Product History reconciliation policy;
5. set state `finished`, `endedAt`, final revision, and durable summary;
6. commit;
7. after authority commits, reconcile desired reminder registrations to zero and cancel known pending session notification requests;
8. suppress any late event by terminal state/revision validation.

If the atomic domain commit fails, the session remains active at the last committed revision and no success UI or history claim appears. Registration cleanup is retryable projection work; a cleanup failure does not roll back a committed Finish, because terminal-state validation still suppresses later events.

### 6.7 Abandon

Abandon:

- requires explicit user intent from active or expired;
- records terminal `abandoned` and `endedAt`;
- follows the still-open policy for retaining progress/history;
- never marks lines purchased or Product/list state complete by inference;
- releases the single-active invariant;
- makes desired session registrations empty and cancels known pending requests;
- retains enough summary/snapshot data for the approved history/retention policy.

### 6.8 Expire

Expiration uses the approved combination of:

- persisted `lastActivityAt`;
- a persisted inactivity threshold/policy;
- a persisted absolute maximum lifetime;
- a deterministic clock.

Evaluation occurs on cold launch, warm foreground, a background event, before any session command, and later on Cloud merge. No timer must fire while suspended. When due, an atomic command moves `active → expired`, increments revision, preserves line/stop progress, and makes desired reminders empty. The next user interaction offers Resume or Abandon; expiration never finishes or deletes the session.

Exact inactivity duration, absolute maximum duration, qualifying activity events, and retention are unresolved in Section 21.

### 6.9 Resume

Resume is explicit and allowed only from `expired`:

- revalidate snapshot integrity and source availability;
- retain committed line outcomes;
- apply the approved new expiration window policy;
- set `active`, retain the prior expiration audit evidence, establish new policy boundaries, update meaningful activity, and increment revision;
- re-evaluate reminder preference/capabilities;
- create fresh registrations for the new revision rather than trusting old ones.

Opening or foregrounding an already active session is presentation recovery, not a business-state Resume transition.

### 6.10 Process, scene, crash, reboot, and force quit

- **Background:** no session transition. Finish an already-started persistence command only within a short, bounded task if needed; cancel/checkpoint foreground planning; stop foreground standard location; leave OS regions registered.
- **Suspension/system termination:** committed aggregate remains. No timer or in-memory plan is relied upon.
- **Warm foreground:** reload authority, expire if due, reconcile capability/regions, and avoid forced rerouting if the user is already handling the session.
- **Cold manual launch:** recover exact committed progress and snapshot before optional network/store refresh.
- **Crash:** last committed command wins; uncommitted UI state is reloaded; reminder projection is recomputed.
- **Reboot:** the durable aggregate survives; OS region delivery remains best effort; manual launch reconciles.
- **Force quit:** progress remains saved, but reminders are explicitly described as unavailable/unreliable until manual reopen. No workaround or guarantee is allowed.

---

## 7. Session State Matrix

This matrix is the binding implementation reference for every session consumer. “Notifications” means session reminder notifications, not unrelated application notifications. “Geofence” means the device-local session reminder projection.

| State | Allowed transitions and commands | Notification behavior | Geofence behavior | Background behavior | Recovery behavior | Persistence invariant | Terminal? |
|---|---|---|---|---|---|---|---|
| **No Session** (absence, not a persisted state) | `Start → active` after all preconditions; view history; generate/rebuild a foreground plan | No session reminder may be generated or routed; passive opportunity, if separately approved, uses a distinct feature path | Desired session regions = zero; remove orphan session registrations during reconciliation | No session work; no polling, expiry timer, planner, or session callback context | Publish “none”; reconcile away orphan registrations; never infer a session from a payload or selected tab | No nonterminal aggregate exists; terminal history may remain | Not applicable |
| **Active** | Collect, Undo, navigate/current-stop actions, allowed stop progress; `Finish → finished`; `Abandon → abandoned`; deterministic `Expire → expired`; opening same context is explicit Resume/open with no state change; Update Session only if separately approved | Eligible only when reminder preference and capabilities allow; content derives from this session revision/stop/current remaining lines; quiet/cooldown/idempotency apply; tap revalidates then opens Shopping/current stop | Desired registrations computed within budget for current/approved near-future stops; reconcile on start, line/stop change, foreground, permission change, migration, and platform callbacks | App background causes no state change; standard location stops; OS regions remain; a region event performs minimal local validation only; no network/MapKit/AI | Restore exact lines/stops/snapshot; evaluate expiry first; project capability separately; recover even with notifications denied; repair or ask on invariant conflict | Full aggregate and policy durable; `endedAt == nil`; exactly one active in authority scope; all successful commands revisioned and atomic | **No** |
| **Expired** | `Resume → active`; `Abandon → abandoned`; read progress/history; no Collect/Undo/Finish until explicit Resume under the approved contract | No new session reminder; pending known requests canceled where possible; delivered tap shows safe expired context and Resume/Abandon choices | Desired registrations = zero; remove actual/ledger registrations; old revisions always suppress | Region events only validate, persist expiry if not already committed where safe, suppress, and return; no reminder delivery | Restore progress and snapshot; present explicit Resume or Abandon; never silently resume; evaluate storage integrity/capabilities only after domain recovery | Full aggregate remains durable; expiration timestamp/reason and revision recorded; no inferred outcomes; it is not active, but the unresolved-session gate blocks a new Start until explicit Resume or Abandon | **No — resumable** |
| **Finished** | No business-state transitions; view summary/history only; a separate valid plan can start a new session | No session reminder; known pending requests canceled; delivered/tapped old reminder resolves to safe “session ended” context without Map mutation | Desired registrations = zero; remove actual registrations; late callbacks suppressed by terminal state/revision | No background session work beyond fast stale-event suppression or cleanup reconciliation | Load only for history/deep-link resolution; never route as active; do not reconstruct missing successful outcomes | `endedAt` present; every target-created line has final outcome; WT-031A list/history effects committed in same domain transaction | **Yes** |
| **Abandoned** | No business-state transitions; view retained summary if policy allows; a separate valid plan can start a new session | No session reminder; known pending requests canceled; stale taps are safe and non-mutating | Desired registrations = zero; remove actual registrations; late callbacks suppressed | No background session work beyond fast stale-event suppression or cleanup reconciliation | Load only for retained history/deep-link resolution; never route as active; display no successful-trip claim | `endedAt` present; retention/progress follows approved policy; no Product/list purchase inference | **Yes** |

### 7.1 Transition command matrix

| Command | Valid source | Target | Required authority checks | Atomic domain effects | Post-commit projection work |
|---|---|---|---|---|---|
| Start | No active/expired conflict | Active | Named list/revision, eligible stable entries, current plan signature, stop selection, durable store | Insert complete header/stops/lines/snapshot at initial revision | Publish projection; optionally request permission; reconcile registrations |
| Collect | Active | Active | Expected session/revision, existing line, allowed outcome | Line to collected, outcome time, activity, revision | Recompute notification content/registrations |
| Undo | Active | Active | Expected session/revision, same line collected | Line to remaining, clear/replace outcome metadata, activity, revision | Reintroduce eligibility and reconcile |
| Expire | Active | Expired | Persisted policy says due; terminal state has not won | State, expiry record, revision; preserve progress | Desired registrations zero; cancel pending |
| Resume | Expired | Active | Explicit user action, snapshot valid enough, no active conflict | State, new policy boundaries/activity, revision | Fresh capability evaluation and registrations |
| Finish | Active | Finished | Expected revision; explicit final outcome for every remaining line; WT-031A reconciliation valid | Outcomes, terminal state/time/revision, list/history reconciliation | Remove registrations; cancel pending; publish summary |
| Abandon | Active or Expired | Abandoned | Explicit user action; expected revision | Terminal state/time/revision; approved retention policy | Remove registrations; cancel pending |
| Region event | Active only; no state transition except due expiry | Active or Expired | Registration exists; session/revision/policy/expiry/stop/line eligibility current | Optional expiry or event-ledger update only; never line/list mutation | Schedule validated notification, then commit success cooldown |
| Notification tap | Any persisted state; no state mutation by tap | Same | Resolve request/registration; reload session and state | None unless the user later chooses a command | Route active to Shopping/current stop; show safe result otherwise |

### 7.2 Cross-cutting precedence

When operations race:

1. committed terminal state wins over every reminder event;
2. a due Expire wins over a reminder but not over a Finish already committed;
3. revision mismatch suppresses background work and forces foreground commands to reload;
4. duplicate command/event idempotency returns the committed result without duplicating outcomes or notifications;
5. notification cleanup is eventually reconciled, but no cleanup failure can reactivate business state;
6. app scene state never changes these transition rules.

---

## 8. Background Execution Strategy

### 8.1 Supported execution model

**Approved:** the durable session survives because it is persisted, not because the app continuously executes. The implementation must be correct under suspension and process termination.

The planned execution classes are:

| Execution class | Allowed work | Prohibited work |
|---|---|---|
| Visible foreground Shopping/Map | User commands, bounded location, plan/store work, navigation, registration reconciliation | Treating scene state as session state |
| Foreground→background transition | Persist an already-issued command using only a short bounded continuation where necessary; cancel/checkpoint foreground-only plan work; release location consumers | Starting new planner/search/AI work; keeping standard location active by default |
| OS region callback/background launch | Resolve compact registration, minimally open local authority, validate one event, build from snapshot, schedule/suppress, record bounded ledger result | MapKit, StoreResolutionEngine, AI, broad sync, catalog refresh, UI routing, full startup sheets |
| Manual cold launch | Full ordered recovery, UI projection, capability and region reconciliation, optional foreground refresh after recovery | Requiring network or notification permission before recovering |
| Warm foreground | Re-read authority, expire if due, reconcile capabilities/regions, restore view state if appropriate | Blindly trusting an in-memory plan or automatically rerouting over current user work |

### 8.2 Scene lifecycle integration

`scenePhase` remains an input to operational coordination:

- `.active`: request a recovery/reconciliation pass and allow foreground location consumers;
- `.inactive`: stop issuing new expensive UI work and prepare to release consumers;
- `.background`: release standard location, cancel/checkpoint plan generation, allow only a bounded in-flight persistence completion, and do not mutate session state merely because the scene changed.

`ContentView` must stop implementing recovery logic directly. It should report scene events to a coordinator and render typed recovery/session projections. Multiple scenes or repeated `.active` callbacks must be idempotent.

### 8.3 Foreground location leases

Replace initialization-driven standard updates with an adapter-level consumer contract:

- planning may request a one-shot location;
- map recenter may request a one-shot or short visible stream;
- an actively visible Map may hold a scoped stream lease;
- accuracy and distance filter are selected per consumer at the lowest useful level;
- the adapter stops updates immediately when the final consumer releases;
- it does not set continuous background location or keep a standard stream for session persistence;
- duplicate consumers are reference-counted or otherwise deterministically coalesced;
- cancellation, scene background, and errors release the lease;
- tests use a fake clock and fake platform adapter.

Exact accuracy/distance settings are implementation-specification choices supported by energy measurements; `kCLLocationAccuracyBest` is not the default for every consumer.

### 8.4 Expiration without timers

The implementation persists enough policy/timestamps to calculate `isExpirationDue(now:)`. Evaluation is invoked:

- before returning an active aggregate from recovery;
- before each user command;
- on foreground activation;
- in the region-event validator;
- after future Cloud merges.

A foreground timer may update explanatory UI, but it is not authoritative and cannot be necessary for the transition. Expiration must be idempotent across repeated evaluations and backward clock movement must be handled by the clock policy selected in the implementation specification.

### 8.5 Region background launch

The app must be capable of initializing only the local session/reminder path for a background region delivery:

1. configure minimal diagnostics;
2. open the same versioned local store and retain persistence mode;
3. avoid catalog loading, onboarding, feature tours, nearby-opportunity refresh, and broad root-view work;
4. hand the registration identifier to the background validator;
5. finish after one schedule/suppress result.

The implementation specification must select the concrete SwiftUI/application-delegate integration supported by the deployment target. It must not assume that a full `WindowGroup` appearance or `ContentView.onAppear` will happen in time.

### 8.6 Force quit, reboot, and system termination contract

No code path may promise delivery after force quit. Product copy and tests must distinguish:

- **progress:** durable after every successful command;
- **regions:** best effort under normal OS lifecycle;
- **force quit:** reminder execution may not resume until the user manually opens the app;
- **reboot/system termination:** delivery remains OS-controlled; manual launch always reconciles;
- **background refresh disabled:** may reduce opportunities for background behavior, but does not cancel the session.

### 8.7 No new background capability by default

The approved implementation does not add:

- `UIBackgroundModes` continuous location;
- `BGAppRefreshTask` polling;
- significant-location-change session recomputation;
- background MapKit searches;
- silent push ownership;
- keepalive timers.

Any future addition requires a separate product/privacy/battery specification and may not become session authority.

---

## 9. Notification Strategy

### 9.1 Notification authority

A session notification is a projection of exactly:

- one persisted active session ID and revision;
- one current/eligible stop;
- currently remaining eligible session lines;
- the session reminder policy;
- current device capability and quiet/cooldown policy.

It does not derive from global open items, an in-memory plan, a region’s embedded Product names, or stale distance. Copy may continue to say “likely available” but never implies retailer inventory certainty.

### 9.2 Scheduling pipeline

```text
opaque registration ID
    -> registration ledger lookup
    -> session aggregate + expected revision
    -> expiration/state/preference/capability validation
    -> current stop + remaining line projection
    -> quiet/cooldown/idempotency decision
    -> UNNotificationRequest
    -> successful add
    -> commit last-success/cooldown metadata
```

Required validation:

1. identifier syntax and version are supported;
2. registration exists and is not removed/expired;
3. session exists;
4. session is `active`;
5. session revision equals registration revision;
6. expiration is not due; if due, apply/schedule idempotent expiration and suppress;
7. reminder preference still permits the event;
8. stop/store context matches;
9. at least one referenced/current eligible line remains;
10. this event/request idempotency key has not already succeeded;
11. quiet and cooldown policy allows presentation;
12. persistence mode is durable and authoritative.

Any missing or failed check suppresses contextual content. The open policy for a generic no-context failure message is recorded in Section 21; until explicitly approved, fail closed.

### 9.3 Payload and request identity

Planned session notification userInfo contains only stable routing identity needed to revalidate, such as a payload version, registration ID, session ID, expected revision, and notification feature type. Store/Product display content is rendered into notification title/body from the persisted snapshot at scheduling time but is not treated as routing authority.

Notification request identifiers are deterministic enough to:

- prevent duplicates for the same event context;
- cancel known pending requests on line/stop/session changes;
- keep different session revisions and passive opportunity features isolated;
- support safe cleanup after migration.

Human-readable names, coordinates, raw list contents, and frozen distance are removed from Core Location identifiers. UserInfo minimization is validated as a privacy test.

### 9.4 Cooldown and quiet behavior

The cooldown key must include the feature plus session/revision and stop/store context. It is written only after `UNUserNotificationCenter.add` reports success. A scheduling failure records a bounded diagnostic and remains retryable.

Quiet hours affect presentation only:

- they do not expire, pause, or mutate a session;
- they do not change region authority;
- delayed-versus-suppressed handling remains an open product decision;
- defaults and user configuration remain unresolved;
- tests use an injected clock/time zone and cover DST/local-time changes.

### 9.5 Notification tap routing

For a session reminder:

1. parse the minimal payload;
2. load the registration and session from local authority;
3. evaluate expiry and validate revision;
4. if active/current, publish a session navigation intent to Shopping Mode/current stop;
5. expose Map/navigation secondarily from the recovered stop snapshot;
6. if expired, finished, abandoned, missing, or superseded, show a localized safe contextual result and do not silently mutate selected list, runtime plan, or Map state.

The exact stale-tap surface is unresolved, but the safety behavior is not.

Passive nearby-opportunity notification taps, if that feature is retained, may open Map through a separately typed route. They cannot use the session category, session cooldown, or session command path.

### 9.6 Cancellation and delivered notifications

On Finish, Abandon, Expire, reminder opt-out, revision replacement, or store recovery:

- desired pending session requests become empty or are replaced;
- known pending request IDs are canceled;
- delivered notifications may be removed if product policy approves;
- every later tap still revalidates because delivery cannot be recalled reliably;
- cleanup failure is recorded and retried during reconciliation.

### 9.7 Permission timing and capability UX

Notification authorization is requested only:

- after explicit user interest in session reminders; or
- from a user-invoked Settings action.

Starting or recovering a session does not require authorization. Denial is not repeatedly prompted. UI states distinguish not determined, denied, allowed, quiet, and session-reminder unavailable, with an appropriate Settings route where the OS permits.

---

## 10. Geofencing Strategy

### 10.1 Desired versus actual state

The reminder coordinator computes a deterministic desired set from the active session. The location adapter enumerates actual WayTask-managed regions. The ledger records expected local projection state. Reconciliation compares all three:

```text
persisted session -> desired registrations
ledger            -> known attempted/result state
Core Location      -> actual monitored regions
```

Actions:

- desired but not actual: register if capable and within budget;
- actual but not desired: stop;
- actual with unknown/legacy identifier: stop under migration/cleanup policy;
- ledger registered but not actual: mark missing and retry if still desired;
- actual matching ID but wrong session revision: replace;
- failure: persist bounded status/reason and expose degraded capability, without changing session state.

Reconciliation runs after Start/Resume, line or stop changes, terminal/expiry transitions, manual launch, foreground, permission/accuracy change, monitoring callbacks, migration, and store recreation.

### 10.2 Region selection and budget

Retain a declared WayTask app budget below the iOS per-app region limit. The current maximum of 12 Shopping regions is a reasonable verified starting constraint, but the exact split between current/future session stops and a separately approved passive feature is an unresolved policy.

Selection must be deterministic and prioritize:

1. current stop;
2. approved near-future stops with remaining lines;
3. no terminal, expired, empty, or stale-revision stops.

The current 150–250 meter normalization may be retained only where the platform/device and store geometry support it; the implementation specification should define radius validation and tests. Registration does not claim immediate “already inside” delivery; any foreground `requestState` use must remain best-effort and cannot become notification authority.

### 10.3 Compact identifiers

The planned region identifier is:

- versioned;
- short enough for platform constraints;
- opaque;
- unique to one ledger registration;
- free of Product names, Store names, coordinates, list contents, and distance.

Decoding the ID alone yields no user-visible context. Resolution always goes through the local ledger and current session.

### 10.4 Location permission flow

Planned flow:

- request When In Use when the user invokes planning/Map behavior that needs location;
- explain background nearby reminders in the session reminder choice;
- request Always only after explicit user choice and OS-appropriate education;
- never automatically escalate in `locationManagerDidChangeAuthorization`;
- handle denial, reduced accuracy, restricted, and later Settings changes;
- do not repeatedly prompt;
- do not require Precise/Always to save progress or use Shopping manually.

The exact use of temporary full accuracy is unresolved. Copy must be localized and accurate for the supported OS.

### 10.5 Registration lifecycle and races

Registration calls are asynchronous. The ledger must distinguish desired, registering, registered, failed, removing, and removed/suppressed results without making those statuses business state.

Race rules:

- terminal state committed while registration is in flight: callback records result, then reconciliation removes it;
- old revision entry arrives after new revision: validator suppresses;
- monitoring failure: record reason, update capability, retry only under bounded policy;
- duplicate `didStartMonitoring`: idempotently converge;
- callback for unknown legacy region: suppress and cleanup;
- process death between desired-state commit and OS call: launch reconciliation resumes;
- process death after OS call but before ledger success: enumerate actual and converge.

### 10.6 Passive nearby opportunities

Current global regions and smart-nearby detection cannot be silently relabeled as session reminders. Before target cutover they must be either:

- removed; or
- separately approved as an explicit, named, opt-in passive feature with one source list/revision, its own ledger namespace, budget, cooldown, copy, Settings control, validation, and Map route.

The session architecture cannot depend on that decision. Session tests must prove zero passive registrations when passive behavior is unapproved or disabled.

### 10.7 Geofence content and offline behavior

Region registration requires only persisted stop coordinates and session identity. A callback requires only the local store. It must work without internet and must not refresh store opening hours, availability, or distance. If persisted coordinates are invalid, capability becomes unavailable for that stop; the session remains usable.

---

## 11. Recovery Strategy

### 11.1 Recovery coordinator contract

The coordinator executes in this strict order:

1. receive the `WayTaskStartupPersistenceResult`, including mode;
2. complete schema migration and graph repair;
3. load all resumable session candidates;
4. enforce or surface the single-active invariant;
5. validate aggregate structure, stop/line snapshots, source IDs, and unresolved migration evidence;
6. evaluate deterministic expiration;
7. publish a typed domain recovery result;
8. evaluate location/notification capabilities;
9. reconcile desired versus ledger versus actual registrations;
10. permit optional noncritical plan/store refresh only in foreground.

Notification authorization is not consulted before steps 1–7.

### 11.2 Recovery results

The UI should consume a small typed result such as:

- no resumable session;
- restored active session;
- expired session requiring Resume/Abandon;
- session conflict requiring recovery choice;
- recovered session with missing/unresolved legacy evidence;
- persistent store recreated and session authority unavailable;
- in-memory degraded mode;
- unrecoverable aggregate requiring support-safe handling.

The exact Swift type/name is proposed, not prescribed. A Boolean “has active” is insufficient.

### 11.3 Cold manual launch

Required sequence:

- recover last committed revision without network;
- restore session lines, outcomes, current stop, and plan/store snapshots;
- rebuild Shopping and Home projections;
- route to Shopping only according to approved launch/routing policy and without interrupting startup recovery/education;
- show session capability separately;
- reconcile regions;
- optionally refresh store data later in foreground without changing the snapshot.

Relaunch must not require the runtime `ShoppingPlan`, current legacy items, selected tab, or notification authorization.

### 11.4 Warm foreground and scene restoration

On scene activation:

- request an idempotent recovery pass;
- reload session authority rather than trusting cached revision;
- evaluate expiry;
- refresh the projection if another command changed it;
- keep current navigation if already displaying that session;
- otherwise make Resume discoverable without repeatedly forcing tab selection;
- reconcile permissions and registrations;
- discard any runtime plan whose list/revision/session binding is no longer valid.

SwiftUI navigation restoration remains presentation state. If a restored route names a session/stop that is no longer valid, the router uses the recovered aggregate and falls back safely.

### 11.5 Background wake

Background recovery is intentionally narrower:

- no root-view recovery result or navigation;
- resolve one registration and session;
- apply due expiration idempotently;
- validate or suppress one event;
- schedule at most the bounded intended notification work;
- persist a compact result;
- return.

If the store cannot open authoritatively, suppress contextual notification and defer full recovery until manual launch.

### 11.6 Crash and partial-command recovery

Every command must have a clear commit point:

- UI enters pending state;
- command validates expected revision;
- all domain writes occur in one transaction/context save;
- success returns the committed projection;
- failure rolls back/resets the context and returns a typed error;
- UI reloads authority and never displays the optimistic state as committed.

For commands that have post-commit projection work, such as region removal, persisted business state wins. Reconciliation completes projection work later. Diagnostics distinguish domain commit failure from reminder cleanup failure.

### 11.7 Persistent store quarantine and recreation

When startup recreates the store:

- propagate `.recreatedPersistentStore` to session recovery;
- enumerate and stop all WayTask-managed session and legacy regions;
- cancel known session notification requests where identifiable;
- reject contextual callbacks whose ledger/session authority no longer exists;
- show a durable-data recovery notice;
- do not present “no active trip” as proof that no prior trip existed;
- preserve quarantine according to the unresolved support/retention policy.

Restoration from quarantine is not invented by this plan; the implementation specification must decide supported tooling and UX before claiming recoverability.

### 11.8 In-memory fallback

When startup returns `.inMemoryFallback`:

- show an explicit nondurable-mode warning;
- do not arm session reminders against state that will disappear on exit;
- do not claim exact relaunch recovery;
- do not upload or mark data as durably saved;
- allow or block new sessions only according to the unresolved product policy;
- keep all existing OS session/legacy regions stopped and contextual callbacks suppressed.

### 11.9 Multiple-active and malformed recovery

The implementation must never silently select the newest row and discard or demote others. Migration/recovery should:

- detect all active candidates;
- preserve every aggregate/evidence record;
- apply the approved deterministic policy if one is selected before implementation;
- otherwise publish an explicit conflict decision;
- keep reminders disarmed until one authoritative active session is resolved;
- record privacy-safe diagnostics.

Malformed target aggregates are quarantined or marked unresolved at the aggregate level; valid lines are not silently discarded. Exact quarantine UI is an open release decision.

---

## 12. Persistence Strategy

### 12.1 Versioned persistence model

**Planned:** add a new frozen `VersionedSchema` after V3 and a migration stage from V3. V1, V2, and V3 definitions remain immutable. The target version includes the approved session aggregate and local reminder registration projection using the minimum storage shape needed to enforce Section 5.

Exact model classes, relationships, uniqueness constraints, raw-value storage, indices, and custom migration implementation are deferred to the implementation specification. The schema must support:

- complete aggregate creation in one save;
- fast lookup of the single active/expired candidate;
- stable session, stop, line, and registration IDs;
- lookup of registration by opaque identifier in a background callback;
- session and source-list revisions;
- terminal history without requiring live Product/store records;
- explicit invalid/migration-exception representation;
- bounded cleanup without cascading deletion of Product/list truth.

### 12.2 Records requiring migration

Migration must inspect:

- every legacy `ShoppingSession`;
- both raw UUID strings, including malformed, duplicate, empty, and foreign tokens;
- linked legacy `ShoppingItem` rows;
- `ShoppingListEntry` mappings through `legacyShoppingItemID`;
- Product mappings and display/catalog snapshots established by WT-031A;
- optional Shopping list ID;
- selected-store ID/name/coordinates;
- start/finish timestamps and `isActive`;
- multiple-active combinations;
- existing Core Location regions and pending notification identifiers during post-store reconciliation;
- list revision data introduced by WT-031A.

### 12.3 Conservative interpretation rules

| Legacy evidence | Planned interpretation |
|---|---|
| Valid session ID/start time | Preserve exactly |
| `isActive == true`, no contradictory terminal evidence | Active migration candidate, subject to multiple-active policy and expiration initialization |
| `isActive == false` with `finishedAt` | Legacy finished candidate |
| `isActive == false` without `finishedAt`, or active with terminal time | Explicit malformed/migration exception; do not invent Abandoned/Expired |
| Valid item token mapped to one stable list entry/Product | Create one session line preserving source identities and display snapshot |
| Collected token also present in item set | Outcome collected |
| Valid item token not collected | Outcome remaining unless legacy-finished policy resolves it explicitly |
| Collected token absent from item set | Preserve as unresolved foreign evidence; do not append silently or infer a Product |
| Invalid UUID token | Preserve bounded migration exception/diagnostic evidence; do not `compactMap` it away |
| Duplicate token | Deduplicate only under an explicit identity rule and record the duplicate; do not create duplicate purchases |
| Missing ShoppingItem/Product/entry | Create an unresolved line/evidence record with any available snapshot/ID; do not drop |
| Store name/coordinates present | Preserve immutable legacy stop snapshot after coordinate validation |
| Store context absent/invalid | Preserve session with degraded/no-navigation stop context; do not fabricate a store |
| No source list revision existed | Record a legacy/unknown revision provenance or migration-time binding according to the approved migration decision; never claim it was the historical revision |
| No plan snapshot existed | Build only the minimal legacy snapshot supported by persisted evidence and mark completeness/provenance; never reconstruct historical coverage/confidence from current network data |

### 12.4 Legacy finished-session ambiguity

Current Finish allowed uncollected IDs to remain while marking the session inactive. Target Finish requires every target-created line to have a final outcome. Migration cannot infer that an uncollected legacy line was unavailable, skipped, carried forward, or purchased.

Before migration implementation, approve one explicit representation and UI policy for legacy finished-but-unresolved lines. Acceptable planning constraints:

- preserve collected as collected;
- preserve other lines as unresolved legacy outcome/evidence;
- keep the session terminal for historical compatibility;
- exclude unresolved evidence from purchased/completed metrics;
- do not write source list/history effects retroactively;
- explain incomplete legacy history where shown.

Inventing a normal target outcome is prohibited.

### 12.5 Expiration initialization for migrated active sessions

Legacy sessions have `startedAt` but no `lastActivityAt`, expiration threshold, or absolute policy snapshot. The migration must not pretend recent activity. Before implementation, approve whether to:

- use the best persisted evidence time with explicit legacy provenance;
- immediately classify sufficiently old candidates as expired;
- require confirmation on first recovery;
- apply a bounded migration grace window.

Whatever policy is selected must be deterministic, offline, tested at exact boundaries, and observable. Reminders remain disarmed until migration and recovery validate the session and create a target revision.

### 12.6 Multiple active sessions

Migration detects, never hides, multiple active rows. It must preserve IDs, timestamps, lines, and snapshots while applying an approved policy. Possible mechanics—user choice, conservative expiry of all pending choice, or deterministic canonical selection plus explicit exception—must be decided before the migration is frozen. “Newest wins silently,” the current runtime behavior, is not permitted.

### 12.7 Migration staging and idempotency

The safe plan is:

1. characterize all legacy field combinations;
2. ship no schema until interpretation policies and fixtures are approved;
3. build the new schema and semantic migration in development;
4. migrate into target aggregate structures with provenance/exception state;
5. verify counts, IDs, references, and aggregate checksums;
6. run post-migration repair idempotently;
7. disarm all legacy regions before any target reminder is armed;
8. create target registrations only from a recovered active target revision;
9. mark migration/repair completion only after verification.

Migration and repair must be rerunnable without duplicate lines/stops/registrations or changed outcomes. Dataset size and duration are measured using large fixtures.

### 12.8 Failure handling

On migration/open/repair failure:

- do not replace the original persistent store with an empty “successful” state;
- use the existing quarantine/recreation pipeline and propagate its mode;
- record stage/outcome/error code without Product names or coordinates;
- suppress contextual regions/notifications when authority is unavailable;
- never arm target reminders in in-memory fallback;
- keep the user informed of degraded durability;
- retain quarantine according to approved policy.

### 12.9 Runtime transaction boundaries

The following must each be atomic domain operations:

- Start aggregate creation;
- Collect/Undo;
- Expire;
- Resume;
- Finish plus WT-031A list/history reconciliation;
- Abandon;
- explicit Update Session if later approved.

Registration reconciliation is a post-commit projection and uses its own small idempotent ledger writes. Notification scheduling success and cooldown recording form a bounded two-step operation with recovery semantics; the ledger must represent an unknown/in-flight result rather than assuming success.

### 12.10 Authority cutover and compatibility

**Transitional reads:**

- migration code may read legacy fields and payloads;
- characterization adapters may expose legacy data in non-production tests;
- the first target runtime read comes only from migrated target aggregates.

**Transitional writes:**

- before cutover, existing code writes only legacy state;
- after cutover, commands write only target state;
- no dual-write period is allowed in a released build;
- reminder projection writes only ledger/projection state, not compatibility arrays.

**Legacy payload adapter:**

- recognize old identifiers only to suppress/cleanup or, during a tightly bounded compatibility window, resolve them to one valid target session through persisted stable mapping;
- never use old names/IDs/distance as authority;
- if exact session/revision cannot be proven, suppress;
- remove the adapter and legacy registrations after telemetry and upgrade-window criteria are met.

**Final retirement:**

- `isActive`, raw ID arrays, current geofence payload authority, global session-like region refresh, and notification Map routing cease runtime use together;
- old frozen schema properties remain only where SwiftData migration compatibility requires them;
- static tests prevent new reads/writes outside migration code.

### 12.11 Rollback implications

A binary using the old schema cannot safely open a store upgraded to the new schema. Rollback means:

- stop release rollout before data migration if a blocker is found;
- use backup/quarantine fixtures for development recovery;
- prefer a forward-fix build that understands the new schema;
- never restore an older binary over a migrated live store as the user-facing rollback plan;
- ensure server/Cloud work remains disabled so local forward recovery is sufficient;
- document app-store phased-release pause and support steps before release.

The implementation specification must define release backup/quarantine retention and a tested forward-recovery procedure.

---

## 13. File-by-File Change Plan

Every path below is verified unless marked **Proposed**. “Change” means future implementation work, not authorization by this plan.

### 13.1 Models and domain types

| File/component | Current responsibility | Planned responsibility/change | Dependencies | Phase | Tests affected/planned |
|---|---|---|---|---|---|
| `ShoppingSession.swift` | Minimal V1–V3 SwiftData session model and raw UUID helpers | Preserve legacy shape for frozen schemas as required; define or host target session header, explicit state/revision/timestamps/policy, stops, lines, snapshot provenance, and invariants according to final schema design; remove silent malformed-token loss from migration path | WT-031A entry/Product identity; migration policies | 3 | Domain invariants, schema shape, corrupt raw values, all legacy combinations |
| `WayTask/Models.swift` / `ShoppingList`, `ShoppingListEntry`, `ShoppingItem` | List/Product compatibility and legacy item state | Consume WT-031A persisted list revision/entry identity; expose migration mapping only; do not add session state or reminder state | WT-031A Phases 2–3 | 2–3 | Revision/snapshot contract, migration mapping, no compatibility authority |
| `AppStateManager.swift` / `ShoppingPlan` | In-memory plan content | Carry list ID/revision, stable entry IDs, content signature, and snapshot inputs before Start; remain rebuildable and presentation-only after Start | WT-031A plan projection | 2, 6 | Revision mismatch, stale plan, session handoff |
| `ProductHistory.swift` | Add-frequency/completion metadata | Retain correct Product-history ownership; accept only the WT-031A Finish transaction effects, never a background/reminder inference | WT-031A history policy | 4 | Finish atomicity and outcome attribution |
| **Proposed:** target reminder registration persistent type, location chosen by implementation specification | No current ledger | Store compact registration/revision/status/timestamps/idempotency/suppression metadata as local projection | Target schema, location adapter | 3–5 | Schema/migration, reconciliation, crash windows |

### 13.2 Persistence and migration

| File/component | Current responsibility | Planned responsibility/change | Dependencies | Phase | Tests |
|---|---|---|---|---|---|
| `WayTask/Persistence/WayTaskSchemaV1.swift` | Frozen v1 graph | No behavioral change; retain byte/shape compatibility | None | 3 | Existing schema assertions remain |
| `WayTask/Persistence/WayTaskSchema.swift` | Frozen V2/V3, current schema, lightweight plan | Add a new frozen version and semantic migration stage; keep V1–V3 unchanged; set target current schema only at cutover | Final target persistence specification | 3 | V1/V2/V3→target; malformed/multiple/missing fixtures; downgrade rejection |
| `WayTask/Persistence/WayTaskStartupPersistence.swift` | Store open, repair, quarantine/recreation, in-memory fallback | Extend repair hook/coordinator input for session aggregate validation; keep recovery mechanics; return mode through app lifetime; invoke region cleanup through a later coordinator, not inside generic store code | Target schema, recovery result | 3–4 | Recovery ordering, mode propagation, repair idempotency, failure injection |
| `WayTask/WayTaskApp.swift` | Bootstraps store but discards mode | Retain full startup result; inject persistence mode and session/recovery dependencies; support minimal background session path without full catalog/UI work | Recovery/background integration choice | 4–5 | Cold/manual/background bootstrap, in-memory warning |
| **Proposed:** `WayTask/Persistence/ShoppingSessionMigrationRepair.swift` | No semantic session migration repair | Map legacy rows conservatively, verify aggregates, record provenance/exceptions, enforce idempotency; exact path/name subject to specification | Migration decisions | 3 | Exhaustive fixtures and interrupted repair |

### 13.3 Repositories and session services

| File/component | Current responsibility | Planned responsibility/change | Dependencies | Phase | Tests |
|---|---|---|---|---|---|
| `ShoppingSessionService.swift` | Direct fetch/mutate/save commands over raw arrays | Become the application command boundary for Start, Collect, Undo, Resume, Expire, Finish, Abandon; typed conflicts/results; expected revision; atomic rollback; no UI types; call shared WT-031A Finish transaction | Target aggregate/repository; WT-031A | 4 | Full state matrix, races, idempotency, fault injection |
| **Proposed:** `WayTask/ShoppingSession/ShoppingSessionRepository.swift` or repository responsibility within existing service | No isolated background-safe repository | Minimal aggregate and registration lookup, uniqueness checks, expected-revision save, immutable projections; keep the split only if it improves callback/recovery testability | SwiftData model | 3–4 | Query count, uniqueness, process-independent fetch |
| **Proposed:** `WayTask/ShoppingSession/ShoppingSessionRecoveryCoordinator.swift` | Recovery is view logic | Implement ordered recovery contract and typed result independent of notification permission | Startup result, command service, reminder coordinator | 4–5 | Cold/warm/conflict/expire/recreated/in-memory |
| `ShoppingListService.swift` | List commands/backfill | Retain list authority; expose WT-031A list revision and atomic Finish reconciliation API; never query region state | WT-031A | 2, 4 | Finish rollback, list isolation |
| `ShoppingTripService.swift` | Foreground plan coverage | Retain; consume stable plan inputs; no background/session mutation | WT-031A plan inputs | 2, 6 | Existing classification plus revision handoff |
| `ShoppingMemoryService.swift` | Legacy add-frequency history | Retain only correct add-memory behavior; remove any completion authority made obsolete by WT-031A | WT-031A | 4 | No session inference |
| `StoreSearchService.swift` / `StoreResolutionEngine` | Foreground store resolution | Retain foreground ownership; remove calls from session reminder refresh/callback paths; make cancellation explicit for backgrounding | Foreground location lease | 5–6 | Cancellation, no background invocation |

### 13.4 Background, location, and notification components

| File/component | Current responsibility | Planned responsibility/change | Dependencies | Phase | Tests |
|---|---|---|---|---|---|
| `WayTask/LocationManager.swift` | Permissions, continuous standard location, global region generation, smart nearby, callbacks, notification scheduling | Narrow to platform adapter/coordinator facade: contextual permission APIs, consumer-scoped location, compact region register/remove/enumerate, event forwarding; remove automatic Always escalation, global session-like candidate resolution, payload authority, and direct notification construction | Reminder coordinator/validator | 5 | Fake platform, leases, permissions, reconciliation, callbacks |
| `GeofenceNotificationService.swift` | Candidate/payload encoding, authorization, copy, cooldown | Replace session path with validated notification projection/scheduler using compact IDs and ledger; request permission contextually; record success after add; separate or retire passive payload path | Session repository, notification router | 5 | Payload privacy, validation, cooldown, failures, localization |
| **Proposed:** `WayTask/ShoppingSession/SessionReminderCoordinator.swift` | No desired-state owner | Derive desired registrations, enforce budget/priorities, reconcile ledger and actual OS regions, handle capability changes | Session projection, location adapter | 5 | Desired/actual convergence, budgets, races |
| **Proposed:** `WayTask/ShoppingSession/BackgroundSessionValidator.swift` | Region callback trusts identifier | Minimal local validation pipeline and idempotent scheduling/suppression | Repository, clock, notification scheduler | 5 | All validation failures, expiry/event and finish/event races |
| **Proposed:** `WayTask/ShoppingSession/SessionNotificationRouter.swift` | AppState parses payload into Map context | Revalidate taps and publish typed navigation result; keep passive route separate | Repository/recovery coordinator | 5–6 | Active/expired/terminal/missing/revision mismatch taps |
| `WayTask/Info.plist` | Usage descriptions; no background modes | Keep no continuous location mode; update only localized/accurate permission copy if approved; no capability addition under WT-031B | Product/legal copy approval | 5 | Static configuration assertions |
| `WayTask.xcodeproj/project.pbxproj` | Target configuration; no declared background mode found | Add source/test references only if project organization requires; do not add background modes/entitlements | File layout | 3–7 | Build/static configuration |

### 13.5 App state, UI, Map, and Settings

| File/component | Current responsibility | Planned responsibility/change | Dependencies | Phase | Tests |
|---|---|---|---|---|---|
| `WayTask/AppStateManager.swift` | Runtime plan, selection, notification delegate, Map route | Remain presentation/navigation state; hold immutable session recovery/navigation projections, not mutable session authority; delegate notification routing; invalidate stale runtime plans by persisted revision | Recovery/router | 4, 6 | No authority writes, routing results, stale plan |
| `WayTask/ContentView.swift` | Root queries, startup backfill, recovery, global geofence refresh, scene handling | Remove direct session query/routing and global session-like geofence refresh; forward lifecycle signals; render recovery/degraded decisions; ensure repeated appearances are idempotent | Recovery/reminder coordinators | 4–6 | Notification-independent recovery, scene matrix |
| `WayTask/ShoppingWorkspaceView.swift` | Plan/start/session commands and active UI | Consume session projection and typed commands; show conflict, expired, abandon, remaining-line reconciliation, save failure, offline snapshot, reminder capability, and legacy unresolved states; no raw-array derivation | Session service/recovery; WT-031A | 4, 6 | State UI, command pending/error, a11y/RTL |
| `WayTask/HomeView.swift` | Newest-`isActive` progress and runtime plan summary | Consume canonical session summary; distinguish Active/Expired and capability; route explicit actions; no raw queries | Session projection | 6 | Cross-screen state parity |
| `WayTask/MainMapView.swift` | Runtime plan/global item/notification Map contexts | Accept a recovered session stop/line projection when invoked from Shopping; do not become session authority; safe fallback for missing coordinates; discard stale notification context | Session router/projection | 6 | Relaunch Map context, stop changes, stale tap |
| `MapViewModel.swift` | Store search/presentation and runtime plan application | Retain Map ownership; add immutable session-stop projection input; suppress foreground store re-resolution when rendering frozen session context unless user explicitly refreshes | Session projection | 6 | Session vs plan modes, offline snapshot |
| `WayTaskMapView.swift`, `MapBottomSheet.swift` | Map presentation | Retain; render session-scoped line labels and uncertainty from projection; no commands except callbacks to owner | MapViewModel | 6 | Labels, Dynamic Type, RTL |
| `SettingsView.swift` | Notification permission and custom stores | Show session reminder preference/capabilities and user-controlled location/notification Settings paths; separate passive feature if approved; no repeated prompts | Capability projection | 5–6 | Permission states, localization, VoiceOver |

### 13.6 Diagnostics

| File/component | Current responsibility | Planned responsibility/change | Dependencies | Phase | Tests |
|---|---|---|---|---|---|
| `WayTask/BetaDiagnostics.swift` / `BetaDiagnosticsCenter` | Planner/geofence/notification debug events and UI | Add privacy-safe session transition, recovery result, desired/actual count, suppression reason, callback duration, and location-lease counters; remove Product/store names and exact coordinates from new telemetry | Stable diagnostic taxonomy | 1, 3–7 | Redaction, bounded cardinality, event sequences |
| `WayTask/SentryReportingService.swift` | Breadcrumbs/errors/startup diagnostics | Add aggregate operation/recovery/background failure categories with hashed/ephemeral identifiers and no snapshot content; distinguish domain commit vs projection cleanup | Diagnostics policy | 1, 3–7 | Monitoring stability/redaction |

### 13.7 Tests and fixtures

| Current/proposed path | Planned work |
|---|---|
| `WayTaskTests/Persistence/WayTaskSchemaMigrationTests.swift` | Extend with V1/V2/V3 target migrations; active/finished/malformed/missing/duplicate/foreign/multiple rows; snapshot provenance; registration cleanup |
| `WayTaskTests/Persistence/StartupPersistenceResilienceTests.swift` | Assert persistence mode reaches recovery; recreated/in-memory modes disarm and suppress; background open failure fails closed |
| `WayTaskTests/Persistence/StartupRepairIdempotencyTests.swift` | Add session aggregate and registration repair idempotency |
| `WayTaskTests/ShoppingUX/ShoppingWorkspaceUXTests.swift` | Extend presentation rules for all session states, conflict, remaining-line reconciliation, capability, offline/degraded, and error states |
| `WayTaskTests/Map/MapBottomSheetProductLabelTests.swift` | Add session snapshot labels, missing source, uncertainty, and localization cases |
| `WayTaskTests/Monitoring/SentryStabilityTests.swift` | Assert new diagnostics contain no names/coordinates/payload copy and remain bounded |
| **Proposed:** `WayTaskTests/ShoppingSession/ShoppingSessionStateMachineTests.swift` | Exhaustive state/command matrix and invariant tests |
| **Proposed:** `WayTaskTests/ShoppingSession/ShoppingSessionServiceTests.swift` | Transactions, conflicts, expected revision, idempotency, rollback, WT-031A Finish integration |
| **Proposed:** `WayTaskTests/ShoppingSession/ShoppingSessionRecoveryTests.swift` | Cold/warm/background/crash/recreated/in-memory/scene tests |
| **Proposed:** `WayTaskTests/ShoppingSession/SessionReminderCoordinatorTests.swift` | Desired/ledger/actual convergence, capacity, permission, and race tests |
| **Proposed:** `WayTaskTests/ShoppingSession/BackgroundSessionValidatorTests.swift` | One-event pipeline, all suppression reasons, no heavy dependencies, timing |
| **Proposed:** `WayTaskTests/ShoppingSession/SessionNotificationRouterTests.swift` | Active/expired/terminal/stale/missing/passive tap routing |
| **Proposed:** `WayTaskTests/Location/LocationConsumerLeaseTests.swift` | One-shot/stream ownership, release on background/cancel/error, no idle stream |
| **Proposed:** device/UI test plans | Relaunch, reboot, force quit, region delivery, permissions, Dynamic Type, VoiceOver, English/Hebrew/RTL, energy/thermal |

### 13.8 Documentation

Only a later approved implementation specification may authorize changes to production documentation. When implementation is authorized, documentation work should update:

- data ownership and state diagrams;
- permission and force-quit product promises;
- migration/recovery/support runbook;
- background capability and energy baseline;
- diagnostic field inventory and privacy review;
- test traceability;
- deferred passive/Cloud/Android contracts.

No WT-030 audit is modified by implementation work.

---

## 14. Implementation Phases

No phase below authorizes source changes. Each phase becomes executable only through an approved implementation specification.

### Phase 0 — Decision and implementation-specification gate

**Objective:** resolve every implementation/migration blocker without changing architecture.

**Included:** expiration durations and activity definition; Finish remaining-line choices; abandon/history retention; legacy finished outcome representation; multiple-active and missing-item migration; degraded-store behavior; reminder preference and permission timing; region budget; quiet hours; stale-tap UX; WT-031A shared contracts.

**Prerequisites:** WT-030B and this plan approved.

**Migration impact:** none.

**Validation:** decision log maps each answer to state matrix, persistence, UX, and tests.

**Exit criteria:** all “blocking before implementation” and “blocking before migration” questions in Section 21 have owners and approved answers; one implementation specification authorizes exact changes.

**Rollback boundary:** documentation only.

### Phase 1 — Characterization, adapters, and operational baseline

**Objective:** make current behavior and nonfunctional cost measurable before changing authority.

**Included:** characterization tests for legacy session start/collect/finish, payload parsing, current cooldown, startup recovery, location startup/authorization, current region signatures; test fakes for clock, location, notifications, persistence failure; device energy and thermal baseline; diagnostic redaction contract.

**Prerequisites:** approved test-only implementation specification.

**Migration impact:** none.

**Validation:** tests reproduce verified current behavior, including defects, without treating those defects as target acceptance.

**Exit criteria:** repeatable baseline on supported devices/OS, background callback harness, and complete legacy fixture corpus.

**Rollback boundary:** tests/instrumentation only.

### Phase 2 — WT-031A identity and plan prerequisites

**Objective:** establish the identities that a session freezes.

**Included:** consume stable Shopping-list entry IDs, persisted list revision, Product/global-concept references, immutable display snapshot contract, plan list/revision/entry identity, and shared list/history Finish transaction design.

**Prerequisites:** authorized WT-031A implementation through its prerequisite phases.

**Migration impact:** WT-031A-owned Product/list migration only.

**Validation:** plan cannot be current when list ID/revision/entry set differs; stable identities survive relaunch and Catalog/Product changes.

**Exit criteria:** session Start can be specified without legacy `ShoppingItem` or in-memory revision authority.

**Rollback boundary:** WT-031A forward-recovery boundary.

### Phase 3 — Target persistence and semantic migration

**Objective:** make the complete session and reminder projection durable without changing public UI authority yet.

**Included:** next frozen schema, target aggregate, registration ledger, semantic legacy migration, provenance/exception state, aggregate validators, repair idempotency, persistence mode propagation, repository reads/writes, legacy-region cleanup planning.

**Prerequisites:** Phases 0–2; migration fixtures and policies approved.

**Migration impact:** first target Shopping Session migration.

**Validation:** every fixture preserves IDs/evidence; no missing line drops; multiple-active policy observable; interruption/retry idempotent; large-store performance measured.

**Exit criteria:** target authority is durable and queryable in development; no production consumer dual-writes.

**Rollback boundary:** before enabling migration in a release; after migration, forward-fix only.

### Phase 4 — Session commands and recovery

**Objective:** implement the business lifecycle on the target aggregate.

**Included:** repository-backed Start/conflict, Collect, Undo, Expire, Resume, Finish, Abandon; expected revision/idempotency; transactional rollback; WT-031A reconciliation; recovery coordinator and typed results; degraded persistence behavior.

**Prerequisites:** Phase 3 and shared Finish contract.

**Migration impact:** migrated rows become inputs to recovery; no new legacy writes.

**Validation:** exhaustive state matrix; cold/warm/crash/failure tests; 100-cycle relaunch progress; terminal and revision precedence.

**Exit criteria:** one service/repository path can perform every approved lifecycle command without UI or reminder authority.

**Rollback boundary:** target components remain gated; do not expose mixed UI.

### Phase 5 — Background, reminder, notification, and location conversion

**Objective:** derive best-effort reminders from the durable session.

**Included:** contextual permission flow, foreground location leases, desired-state reminder coordinator, compact identifiers, ledger reconciliation, background validator, notification projection/scheduler, tap router, terminal cleanup, persistence-mode suppression, legacy-region removal.

**Prerequisites:** Phase 4; region budget/copy/quiet/stale-tap policies.

**Migration impact:** disarm legacy regions and create target registrations only after validated recovery.

**Validation:** desired/actual convergence; offline callbacks; finish/event, expiry/event, revision, permission, add-failure, and process-death races; static proof of no network/planner/AI in callback; energy benchmark.

**Exit criteria:** session reminders work only from validated active authority, and zero standard location consumers remain after foreground use.

**Rollback boundary:** feature remains gated; cleanup tool can remove all target/legacy regions.

### Phase 6 — Cross-surface UX and offline integration

**Objective:** make all user surfaces consume the same session projection.

**Included:** Shopping active/expired/conflict/reconciliation/abandon UI; Home summary; recovered Map stop; notification result routing; Settings capabilities; offline and missing-source states; scene integration; removal of root-view authority logic.

**Prerequisites:** Phases 4–5.

**Migration impact:** migrated exceptions become visible through safe UI.

**Validation:** cross-screen parity; exact offline relaunch; stale payload safety; English/Hebrew, RTL, Dynamic Type, VoiceOver; no raw-array or newest-active reads.

**Exit criteria:** Home, Shopping, Map, Settings, and notifications agree for every state in Section 7.

**Rollback boundary:** internal gate only; no public mixed behavior.

### Phase 7 — Reliability, battery, privacy, and release qualification

**Objective:** prove the complete release unit against WT-030B.

**Included:** all acceptance tests; supported-device background/reboot/force-quit field matrix; large-library/multi-list/multi-stop fixtures; migration performance; energy/thermal runs; privacy review; corrupted-data and recovery drills; rollout/forward-fix runbook.

**Prerequisites:** Phases 1–6 feature complete.

**Migration impact:** final rehearsal on production-shaped V1/V2/V3 stores and interrupted copies.

**Validation:** Section 17 acceptance trace passes; no serious/critical thermal state caused by test flow; measured idle location regression is zero; callback budget met.

**Exit criteria:** release checklist signed by Product, iOS, QA, privacy, localization/accessibility, and support owners.

**Rollback boundary:** stop rollout before migration exposure; after exposure use tested forward fix.

### Phase 8 — Single authority cutover and compatibility retirement

**Objective:** ship one coherent target authority.

**Included:** enable schema/session/recovery/reminder/UI paths together; stop legacy global session regions; stop legacy notification routing; eliminate runtime reads/writes of `isActive` and raw arrays; monitor migration/recovery/suppression/energy metrics; remove bounded adapter after upgrade criteria.

**Prerequisites:** Phase 7 complete and approved release specification.

**Migration impact:** live forward migration.

**Validation:** clean install, every supported upgrade path, offline first launch, relaunch, terminal cleanup, and field telemetry gates.

**Exit criteria:** no production code path treats legacy session fields, runtime plan, global items, or payload content as session authority.

**Rollback boundary:** phased-release pause and forward-fix procedure; no old-binary downgrade of migrated stores.

---

## 15. Offline Behavior

### 15.1 Offline session baseline

Once Start commits, the following must work without internet:

- load and present the exact session, stop, line, and Product display snapshots;
- Collect and Undo;
- Finish remaining-line reconciliation, subject only to local WT-031A authority;
- Abandon;
- deterministic Expire and explicit Resume;
- Apple Maps handoff when the device can handle the saved coordinates, without claiming route availability;
- local region validation and local notification content generation;
- cold/warm relaunch recovery;
- capability explanation and registration reconciliation against locally available OS state.

No command may wait for Catalog, store search, AI, Cloud, or community data.

### 15.2 Plan and store snapshot availability

The pre-Start plan may depend on current store-resolution inputs. At Start, the selected execution snapshot becomes durable. Offline UI must clearly distinguish:

- saved plan evidence time;
- immutable store/coordinate/display snapshot;
- availability estimate rather than inventory fact;
- current remaining lines;
- live data unavailable or not refreshed.

Store opening hours, websites, ratings, and current retailer facts are shown only if their snapshot policy is approved and their age/source is clear. An offline relaunch never substitutes current global map/list data for the session snapshot.

### 15.3 Starting while offline

The architecture permits local operation but WT-030B leaves plan freshness policy open. Before implementation, define:

- maximum acceptable saved-plan age;
- whether a user may explicitly Start from stale cached plan evidence;
- which stop/store fields are mandatory;
- how saved user-defined stores differ from transient MapKit results;
- whether a “continue with saved information” confirmation is required.

If preconditions cannot be proven, Start fails without a partial session. The app may still let the user manage the source list.

### 15.4 Region events offline

Existing valid target regions can generate a notification without connectivity because:

- the opaque ID resolves locally;
- state/revision/policy/line content is local;
- copy comes from snapshots;
- cooldown/idempotency is local.

If the store cannot be opened or the aggregate is unresolved, the callback suppresses. It does not queue a stale contextual notification for later.

### 15.5 Poor connectivity and recovered connectivity

Poor connectivity:

- does not delay session commands;
- may cancel/fail foreground store refresh;
- retains saved snapshot and an honest stale/offline label;
- does not trigger repeated network retries in background.

Recovered connectivity:

- may refresh rebuildable foreground plan/store information under user-visible policy;
- must not rewrite active session stops/lines automatically;
- must not replace notification context without explicit session revision change;
- may upload future idempotent operations only after Cloud architecture is approved.

### 15.6 Future synchronization boundary

Future sync requires immutable IDs, revisions, timestamps, actor/device metadata, and tombstone semantics reserved by the target model. WT-031B does not enable sync. A future merge must:

- preserve terminal monotonicity;
- not duplicate Finish/Abandon;
- resolve line outcome conflicts under an approved policy;
- keep device-local notification registrations out of Cloud business state;
- assign one notification-owning device or otherwise prevent duplicates;
- run expiration after merge;
- never let Community, Catalog, Store, or AI data silently rewrite an active snapshot.

---

## 16. Performance, Battery and Reliability

### 16.1 Persistence and launch performance

Measure, do not speculate:

- V1/V2/V3→target migration time and peak memory for small, typical, and large datasets;
- aggregate fetch time for no session, one active, long history, multiple legacy candidates, and corrupted references;
- recovery coordinator time before first stable UI projection;
- registration lookup latency during background callback;
- Finish transaction cost with a large line count;
- repair/reconciliation cost after interrupted migration.

Queries should load the one nonterminal aggregate and its bounded children rather than scan all Product/list/history data. History should be paged or summarized only if measurement demonstrates need. Background validation must not materialize the entire Product library.

### 16.2 Aggregate sizing

Snapshots increase durable storage by design. Keep them minimal but complete:

- stable IDs and quantity;
- required localized display fallback;
- selected store/stop coordinate and display fallback;
- evidence timestamp/confidence where already available;
- no images, large catalog records, MapKit objects, or redundant notification payload archives unless a documented requirement justifies them.

Test large lists and multi-stop plans. Avoid premature compression that harms migration or recovery clarity.

### 16.3 Location energy policy

Required energy invariants:

- no standard location stream at idle after initialization;
- no standard stream merely because a session is active;
- no standard stream after the last visible consumer releases;
- no continuous background location mode;
- no stationary screen-off polling, store resolution, planner, or AI work;
- region set stays within declared budget;
- terminal/expired sessions converge to zero session regions;
- repeated foreground events do not re-register unchanged desired state.

Compare target energy to the Phase 1 baseline using Instruments/Energy Log and supported physical devices. The release criterion is zero idle standard-location regression and a measured improvement over the current initialization-driven stream.

### 16.4 Thermal policy

The target session path should not cause serious or critical thermal state. Device qualification covers:

- long active foreground Map use;
- repeated planning and session start;
- rapid Collect/Undo with registration reconciliation;
- many simulated region callbacks;
- migration and startup repair;
- poor-connectivity retry conditions.

If thermal pressure rises, nonessential foreground refresh and diagnostics throttle/cancel. Business-state commits and minimal background validation remain bounded.

### 16.5 Background callback budget

Instrumentation records coarse duration buckets for:

- store open;
- registration/session fetch;
- validation;
- notification scheduling;
- ledger commit.

No exact location or Product content enters telemetry. The implementation specification must set a supported-device p95 budget comfortably within system-delivery constraints after measurement; WT-030B requires prompt completion, not an invented constant. Static dependency tests ensure callback composition cannot reach MapKit, planner, AI, Catalog refresh, or broad synchronization.

### 16.6 Reliability and idempotency

Reliability controls:

- expected session revision on every state-changing command;
- stable command/event idempotency keys;
- transaction rollback/reload on failure;
- monotonic terminal states;
- deterministic expiration;
- desired-state recomputation;
- enumeration-based region reconciliation;
- ledger representation of in-flight/unknown platform results;
- terminal-state validation at event and tap time;
- retry budgets rather than loops;
- typed recovery/degraded results;
- privacy-safe operation diagnostics.

### 16.7 Diagnostics requirements

Record:

- transition name, old/new state, outcome, and coarse line-count bucket;
- recovery type and persistence mode;
- migration provenance/exception count buckets;
- active-conflict count;
- desired/actual/registered region count;
- capability state and suppression reason enum;
- background callback outcome and duration bucket;
- notification add/cancel result;
- location consumer count and start/stop imbalance;
- cleanup/reconciliation convergence attempts.

Do not record:

- Product or Store names;
- exact coordinates or addresses;
- list contents;
- notification body/title;
- raw region/payload identifiers;
- barcodes;
- user-entered notes.

### 16.8 No optimization without evidence

Retain straightforward aggregate loading and reconciliation until measurements show a problem. Do not add background caches, polling, compressed opaque blobs, or duplicated summary authority merely to optimize an unmeasured path.

---

## 17. Testing Strategy

### 17.1 Test architecture

Tests require injectable boundaries for:

- clock and calendar/time zone;
- session repository/transaction executor;
- startup persistence mode;
- location authorization/accuracy/monitoring platform;
- actual monitored-region enumeration and callbacks;
- notification settings/add/remove APIs;
- foreground location consumer;
- app/scene lifecycle signal;
- connectivity state for foreground refresh;
- diagnostics sink.

Domain tests use no Core Location or notification singletons. Platform adapter tests use fakes. Physical-device field tests validate behaviors the simulator cannot guarantee.

### 17.2 Domain state-transition tests

Exhaustively test the Section 7 matrix:

- Start succeeds only with named list/revision, eligible lines, valid plan signature, selected context, and no conflict;
- partial Start save failure leaves no active header/stops/lines;
- same-context active Start returns explicit Resume conflict;
- different-context Start returns explicit choices and does not mutate;
- Collect/Undo allowed only on active existing line at expected revision;
- duplicate Collect/Undo is idempotent;
- foreign line and revision mismatch fail and reload;
- Active→Expired at exact inactivity and maximum-lifetime boundaries;
- Expired accepts only Resume/Abandon;
- Resume retains progress and creates a new revision/policy window;
- Finish requires every remaining line decision;
- Finish atomically commits session/list/history;
- Abandon is not Finish and creates no purchase claim;
- Finished/Abandoned reject every business command;
- app scene events never alter session state;
- terminal state wins against event/tap/cleanup races.

### 17.3 Snapshot, list, and Product isolation

Test:

- list mutation after Start leaves session lines/stops unchanged;
- Product rename, removal, Catalog deactivation/replacement, Global Product Concept change, and missing relationship preserve session display snapshot;
- session commands do not mutate Product library membership;
- Collect/Undo do not check/uncheck source list;
- one list/session cannot affect another list;
- plan revision mismatch blocks Start;
- active snapshot works with source list missing;
- Finish applies only the approved WT-031A effects;
- Community/AI inputs cannot change active session without explicit command.

### 17.4 Persistence and migration matrix

For each source schema V1, V2, and V3, cover:

- no sessions;
- one active;
- one finished collected;
- finished with uncollected lines;
- `isActive`/`finishedAt` contradictions;
- empty arrays;
- malformed UUID tokens;
- duplicate tokens;
- collected-not-in-item token;
- missing ShoppingItem;
- ShoppingItem without Product/list entry;
- Product/list entry without legacy item;
- missing list;
- invalid/missing store coordinates;
- one, two, and many active rows;
- large sessions;
- interrupted migration/repair and rerun;
- store-open failure, quarantine failure, recreation, and in-memory fallback;
- ID/timestamp/snapshot preservation;
- no retroactive list/history writes;
- legacy regions disarmed;
- target registration not armed before recovery.

Assert entity/relationship shape, counts, provenance, unresolved evidence, aggregate checksums, and idempotency. Assert that malformed evidence is not silently dropped.

### 17.5 Recovery and lifecycle matrix

| Scenario | Expected assertion |
|---|---|
| Warm foreground | Same committed revision, expiry evaluated, registrations reconciled, no forced duplicate route |
| Cold manual launch | Exact progress/snapshot restored without notification permission or network |
| App background/suspend | No session transition; foreground location released |
| System termination | Relaunch restores committed state |
| Crash after mutation before save | Old committed state shown; failed command not claimed |
| Crash after domain commit before region cleanup | Terminal/new revision shown; reconciliation completes cleanup |
| Reboot | Manual launch restores; reminder delivery described as best effort |
| Force quit | Progress restores on manual launch; no delivery guarantee asserted |
| Background region launch | Minimal path only; one validated schedule/suppress result |
| Store recreated | All WayTask regions stopped; contextual callbacks suppressed; recovery notice shown |
| In-memory fallback | Nondurable warning; no session reminder registrations |
| Multiple active | Explicit approved recovery outcome; no newest-row silent choice |

The Collect/Undo persistence test repeats at least 100 cold-launch cycles, matching WT-030B.

### 17.6 Geofence and registration tests

Test desired/ledger/actual reconciliation for:

- no session;
- active single-stop;
- active multi-stop within/over budget;
- current/future stop priority;
- line eligibility changes;
- unchanged desired state;
- permission not determined/When In Use/Always/denied/restricted;
- Precise and approximate accuracy;
- monitoring unavailable/failure;
- Background App Refresh states;
- Start/Resume and every terminal/expiry transition;
- app foreground and migration;
- unknown, legacy, malformed, missing-ledger, and wrong-revision region IDs;
- process death before and after OS registration call;
- duplicate callbacks;
- region-capacity exhaustion;
- deleted actual region and orphan actual region;
- passive feature disabled and separately namespaced if approved.

After convergence, actual session registrations must exactly equal desired registrations within platform-reported constraints.

### 17.7 Notification tests

For every event, assert validation of:

- session existence/state/revision;
- expiry;
- reminder preference;
- registration status;
- stop/store match;
- remaining eligible line IDs;
- quiet/cooldown;
- persistence mode;
- idempotency.

Also test:

- content comes from snapshot;
- inventory uncertainty retained;
- no frozen distance;
- no human-readable content in region ID;
- minimized userInfo;
- cooldown written only after successful add;
- add failure remains retryable;
- deterministic request cancellation;
- Finish/event, Expire/event, revision/event, and event/event races;
- tap on active/expired/finished/abandoned/missing session;
- session route opens Shopping/current stop;
- passive route remains Map-only and distinct;
- notification permission state does not affect session recovery.

### 17.8 Foreground location and background dependency tests

Test:

- initialization starts no standard stream;
- one-shot planning request ends;
- Map stream starts/stops with visible consumer;
- two consumers coalesce and the final release stops;
- background/cancellation/error releases all consumers;
- contextual permission calls never auto-escalate;
- no background mode is added;
- background validator dependency graph excludes StoreResolutionEngine, MapKit search, planner, AI, Catalog refresh, and Cloud;
- stationary screen-off test shows no standard GPS/planner/polling activity.

### 17.9 Offline and connectivity tests

Test:

- full session lifecycle offline;
- offline cold recovery with missing live Product/store data;
- valid region notification offline;
- store-open failure suppresses;
- plan-start freshness rules at exact boundaries once approved;
- poor connectivity cancellation;
- reconnection does not mutate snapshot or revision automatically;
- deferred future sync metadata does not create current behavior.

### 17.10 UI, localization, accessibility, and navigation tests

For Home, Shopping, Map, Settings, and notification result:

- Active, Expired, Finished history, Abandoned history, no session, conflict, missing snapshot, recreated store, in-memory mode, capability degraded, command pending, and save error;
- same state wording across surfaces;
- no icon or color is the only state cue;
- VoiceOver announces state, progress, line outcome, reminder capability, and actionable remedy separately;
- all actions have unambiguous labels/hints and logical focus order;
- English and Hebrew translations for states, capabilities, expiry/relative time, conflicts, remaining-line choices, force-quit limitation, and recovery;
- RTL layout and interpolation order;
- Dynamic Type through accessibility sizes without clipped actions or hidden state;
- notification tap/deep link does not change selected list/plan when invalid;
- stale navigation restoration falls back safely.

### 17.11 Performance, energy, thermal, and device field tests

Use physical supported devices for:

- migration duration/memory at production-shaped sizes;
- cold and warm recovery latency;
- background callback p50/p95 and failure path;
- idle foreground before/after energy comparison;
- visible Map energy;
- stationary screen-off active session;
- region entry under normal background, suspension, system termination, reboot, and force quit;
- Low Power Mode and approximate location;
- many rapid line changes;
- thermal state during worst supported foreground flow.

Release must show:

- zero standard-location consumers at idle;
- no serious/critical thermal state attributable to the tested session path;
- no polling/background planner work;
- region budget never exceeded;
- no notification after a terminal/expired state when validation runs;
- honest documented results where the OS does not guarantee delivery.

### 17.12 Corrupted-data, rollback, and forward-recovery tests

Inject:

- invalid state raw values;
- missing child rows;
- duplicate stop/line IDs;
- broken assignment/current-stop references;
- impossible terminal timestamps;
- revision regressions;
- notification ledger without session;
- session without registration ledger;
- interrupted notification add/result write;
- disk-full/save failure;
- failed migration and failed quarantine.

Assert safe quarantine/unresolved result, no contextual notification, no silent line loss, no false success, and a usable support diagnostic. Test phased-release pause and a forward-fix binary opening every target fixture. Do not test old-binary downgrade as supported.

### 17.13 WT-030B acceptance-criteria traceability

| WT-030B criteria | Planned proof |
|---|---|
| AC-01–AC-09: lifecycle, atomicity, isolation, recovery | Sections 17.2–17.5 domain, transaction, snapshot, and 100-cycle tests |
| AC-10–AC-14: capability-independent recovery, missing sources, migration/store modes | Sections 17.4–17.5 |
| AC-15–AC-22: foreground location, background limits, region convergence, capability, force quit | Sections 17.6, 17.8, 17.11 |
| AC-23–AC-30: notification authority, suppression, cleanup, cooldown, routing, copy, permission | Sections 17.7 and 17.10 |
| AC-31–AC-35: offline commands/snapshots/background content/sync/freshness | Sections 17.3 and 17.9 |
| AC-36–AC-40: bounded location, energy, thermal, callback work, baseline | Sections 17.8 and 17.11 |
| AC-41–AC-45: state/capability UX, nonvisual cues, EN/HE, Dynamic Type, RTL | Section 17.10 |
| AC-46–AC-50: shared fixtures, device-local capability, duplicate future notifications, external truth/AI isolation | Sections 17.2, 17.3, 17.6, and future-sync contract |

Acceptance is not established by unit tests alone. Platform delivery and force-quit cases require documented physical-device observations without converting best effort into a guarantee.

For deferred-platform criteria, the v1.0.3 implementation must create platform-neutral state-transition fixtures and prove that reminder capability/registration data is excluded from business/Cloud state. Future Android must run the same fixtures before parity is claimed. AC-48’s two-device delivery test cannot pass until the still-open reminder-owner/lease policy and Cloud implementation exist; it is a gate for that future feature, not permission to invent Cloud behavior in WT-031B. Until then, the current release must contain no Cloud notification-owner path capable of duplicating local proximity delivery. AC-34 is likewise exercised at the domain contract with simulated duplicate/idempotency inputs; actual queued network synchronization remains deferred.

---

## 18. Risks and Mitigations

| Risk | Evidence/impact | Mitigation | Release gate |
|---|---|---|---|
| Session progress loss | Current session lacks complete snapshot and save rollback | Atomic aggregate/commands, immutable snapshots, fault injection, 100 cold cycles | No failed command appears committed |
| Incorrect legacy interpretation | Legacy arrays/timestamps cannot express target outcomes | Conservative provenance, unresolved evidence, approved policies, exhaustive fixtures | Zero invented outcomes/dropped invalid tokens |
| Mixed authority | Current UI, plan, arrays, global items, payload all act as truth | Single cutover, no dual writes, static forbidden-read tests | No runtime legacy authority |
| Multiple active sessions | Current uniqueness is “newest fetch,” not enforced | Detect/preserve; approved observable resolution; reminders off until resolved | All fixtures produce explicit result |
| Product/list identity loss | Sessions store only legacy item IDs | WT-031A stable entry/Product IDs plus snapshot; preserve legacy evidence | ID/checksum tests pass |
| Plan snapshot drift | Runtime plan disappears and source data changes | Atomic immutable stop/line/plan snapshot and revision validation | Offline relaunch exact |
| Finish/list/history inconsistency | Current Finish is a Boolean save | Shared WT-031A atomic transaction, explicit line outcomes, rollback tests | No partial Finish |
| Stale notification | Current identifier/userInfo is context authority | Compact ID, repository validation, terminal/revision precedence | All stale/missing cases suppress |
| Orphan regions | OS state can outlive store/session | Desired/ledger/actual reconciliation and cleanup on every boundary | Convergence tests pass |
| Callback exceeds OS budget | Store open/migration/scheduling can be costly | Minimal repository, no heavy dependencies, duration instrumentation | Measured device budget approved |
| Battery regression | Current manager starts best-accuracy updates | Consumer leases, one-shot first, no background stream, energy gate | Zero idle stream/regression |
| Permission distrust | Current app auto-prompts notification and escalates Always | Explicit in-context choices, no repeat prompt, separate capability | UX/privacy sign-off |
| Store recreation creates stale alerts | Current persistence mode discarded; regions remain | Propagate mode, stop all managed regions, fail closed, recovery notice | Recreation field test |
| In-memory session falsely appears durable | Current fallback is transparent to app | Explicit degraded result; no reminders; approved Start policy | Nondurable mode tests |
| Save failure leaks optimistic mutation | SwiftData object changes before save | Transaction wrapper, rollback/reset/reload, pending UI | Fault tests |
| Migration performance harms launch | Semantic migration and snapshots add work | Production-shaped benchmarks, idempotent staged repair, progress/support policy | Latency/memory budget approved |
| Legacy notification compatibility lasts indefinitely | Old regions/payloads can remain | Bounded adapter, cleanup, telemetry threshold, removal milestone | Retirement criterion met |
| Localization/accessibility state confusion | New state and capability combinations add copy | Semantic vocabulary, EN/HE/RTL/VoiceOver/Dynamic Type matrix | Accessibility/localization sign-off |
| Future sync duplicates terminal actions/alerts | No owner/device contract yet | Stable IDs/revisions now; keep registrations local; defer sync and owner policy | Cloud remains disabled |
| Privacy leakage in identifiers/telemetry | Current identifiers include names/coordinates/distance | Opaque IDs, minimized userInfo, redaction tests | Privacy review passes |

---

## 19. Dependencies

### 19.1 Binding architecture dependencies

- **WT-030B** defines the Session-Scoped Persistent Hybrid, state machine, background/notification contract, recovery order, offline contract, and acceptance criteria. WT-031B may not reinterpret them.
- **WT-030 Architecture Summary** binds durable user-owned session state, immutable snapshots, derived reminders, OS-boundary isolation, platform neutrality, and the implementation gate.
- **WT-030A** binds orthogonal Product/list/plan/session ownership and Finish reconciliation.
- **WT-030C** binds evidence-before-truth; Community/Catalog/Store input cannot silently mutate an active session.

### 19.2 WT-031A implementation-plan dependencies

Blocking prerequisites from WT-031A:

- stable Product and `ShoppingListEntry` identity;
- persisted list revision and revision increment rules;
- plan list/revision/entry identity;
- Product display/catalog snapshot policy;
- migration mapping from legacy `ShoppingItem`;
- duplicate entry policy;
- session-line outcome ownership;
- atomic Finish list/history reconciliation;
- removed/missing Product behavior;
- no mixed Product State authority.

WT-031A Phase 5 and WT-031B Phase 4 must converge on one shared session-line model and one Finish transaction. Neither plan may independently implement a second copy.

### 19.3 Product Specification dependency

The available v1.0 Product Specification establishes the baseline concepts of a persistent Shopping trip, leaving/saving progress, Shopping Mode, and manual arrival while deferring automatic geofence arrival and broader offline/sync behavior. WT-030B is controlling where it refines those concepts into explicit lifecycle, best-effort reminders, and exact offline recovery.

No unavailable Version 1.0.3 Product Specification is assumed.

### 19.4 Technical dependencies

- SwiftData `VersionedSchema`, custom migration capability, transaction/save semantics, and testable container configuration;
- Core Location authorization, accuracy, region monitoring, region enumeration, callbacks, and OS limits;
- `UNUserNotificationCenter` settings, scheduling, cancellation, and delegate routing;
- supported SwiftUI scene/application integration for a minimal background location launch;
- existing MapKit/Apple Maps foreground behavior;
- existing persistence bootstrap/quarantine;
- diagnostics and privacy redaction;
- localization resources for English/Hebrew and RTL;
- physical supported devices for background and energy validation.

### 19.5 Organizational decisions and approvals

Required owners:

- Product: durations, activity events, conflict/expiry/abandon/Finish UX, passive feature, quiet hours, stale taps, offline Start, degraded mode;
- iOS architecture: schema/transaction, application lifecycle hook, location adapter, callback budget;
- QA: device/OS/background/force-quit matrix;
- Privacy/legal: permission copy, identifiers, diagnostics, retention;
- Accessibility/localization: semantic state/capability copy and EN/HE/RTL;
- Support/release: quarantine retention, migration failure, forward-fix and rollout procedure.

### 19.6 Correct current dependencies to retain

- `ShoppingTripService` and `StoreResolutionEngine` for foreground plan/store work;
- Core Location region monitoring for best-effort session proximity;
- UserNotifications for local delivery;
- SwiftData and startup quarantine/recovery;
- MapViewModel/MapKit for foreground store presentation/navigation;
- Sentry/BetaDiagnostics with stricter redaction.

---

## 20. Deferred Work

The following are intentionally deferred because WT-030B or the architecture summary deferred them:

- passive nearby opportunities, unless separately approved and specified;
- user-defined active hours;
- calendar-driven sessions;
- AI smart scheduling or automatic session actions;
- automatic inventory/store-truth updates;
- route optimization beyond the approved plan snapshot;
- SKU/inventory layer;
- Cloud/backend implementation;
- multi-device active-session scope, ownership, transfer, and notification coordination;
- Cloud conflict resolution for line outcomes and terminal actions;
- Android implementation and platform adapter;
- background push;
- background refresh/polling and significant-location-change strategies;
- continuous background location;
- automatic active-session mutation from Catalog, Community, Store Truth, Global Product Concepts, or AI;
- future explicit Update Session until its open policy is approved;
- moderation/community tooling;
- quarantine recovery tooling beyond the approved startup mechanics;
- advanced energy telemetry such as MetricKit until approved;
- automatic distance-based arrival as session truth.

Deferral does not permit a placeholder path to become authority. In particular, global passive regions, payload content, runtime plans, and AI/store refresh cannot fill a deferred gap.

---

## 21. Open Questions

All unresolved WT-030B questions are retained. Classification indicates when the answer is required; it does not invent the answer.

### 21.1 Blocking before implementation

| ID | Unresolved decision | Why it blocks |
|---|---|---|
| BI-01 | What inactivity duration applies to an active session? | Expiration policy, persisted fields, copy, and boundary tests require it |
| BI-02 | What absolute maximum session lifetime applies? | Same; prevents indefinite reminder authority |
| BI-03 | Does starting external navigation count as meaningful activity, and do any other stop actions count? | Defines `lastActivityAt` writes |
| BI-04 | What choices must the user make for every remaining line at Finish, and is bulk carry-forward allowed? | Defines Finish command/UI and WT-031A reconciliation |
| BI-05 | Is explicit “Update active session” included in v1.0.3; if so, what changes may it apply? | Affects command set, revisioning, registration replacement, and snapshot UX |
| BI-06 | Are reminders per-session, a persistent preference, or both? | Defines reminder policy storage and permission presentation |
| BI-07 | At what exact user action may WayTask request Always location access? | Defines permission coordinator and approved UX |
| BI-08 | May temporary full accuracy be requested; for which foreground context? | Defines capability and location adapter behavior |
| BI-09 | What region budget is allocated to active session versus any separately approved passive feature? | Defines deterministic registration selection |
| BI-10 | Are only current-stop regions armed, or may near-future stops also be armed? | Defines desired-state projection |
| BI-11 | Are quiet hours in v1.0.3; what defaults and controls apply? | Defines scheduling projection and Settings |
| BI-12 | During quiet hours, are events suppressed or delayed, and how is stale relevance revalidated? | Defines ledger/scheduling state |
| BI-13 | Is passive nearby shopping retained at all? | Current global regions must be removed or split at cutover |
| BI-14 | If retained, which one named list/revision owns passive reminders? | Required to avoid global/mixed authority |
| BI-15 | What copy explains Background App Refresh, Low Power Mode, reboot, and force-quit limits without overwhelming users? | Defines honest capability/limitation UX |
| BI-16 | Does a valid session notification tap open Shopping Mode directly or an intermediate store/session sheet? | Defines router result and UI navigation |
| BI-17 | What safe surface appears when a delivered notification is tapped after expiry/finish/abandon? | Defines stale-tap UX while safety remains fixed |
| BI-18 | If local authority cannot be opened in a callback, must WayTask always suppress or may it issue approved generic non-contextual copy? | Defines fail-closed scheduler behavior; contextual copy is prohibited |
| BI-19 | How many Product names, if any, appear in notification copy? | Content/snapshot/localization contract |
| BI-20 | Which notification actions, if any, are allowed? | Actions must not mutate session without validation/confirmation |
| BI-21 | What saved-plan freshness rule applies before Start? | Offline and stale-plan preconditions |
| BI-22 | Which saved-store fields and evidence are sufficient to generate an offline plan? | Defines offline planning input and stop snapshot validity |
| BI-23 | On recovered connectivity, is foreground store/plan refresh automatic or user-triggered? | Prevents implicit snapshot mutation and retry churn |
| BI-24 | How is a transient store whose identity cannot be resolved after relaunch represented? | Stop identity, Map fallback, and reminder eligibility |
| BI-25 | May a new session be started in in-memory fallback, or is Shopping read/manual-only until durable storage recovers? | Degraded-mode safety and UI |
| BI-26 | Is current distance omitted entirely from region notification copy, or may an event-time value be shown only when actually revalidated? | Registration-time distance is already prohibited; this decides the remaining content behavior |
| BI-27 | May the user explicitly Start from a stale cached plan, and what confirmation is required? | Defines stale offline Start validation and UX |

### 21.2 Blocking before migration

| ID | Unresolved decision | Why it blocks |
|---|---|---|
| BM-01 | How are multiple legacy active sessions resolved: user choice, deterministic canonical selection, expiry, or another observable policy? | Migration cannot enforce uniqueness without a non-destructive rule |
| BM-02 | How are missing legacy items displayed and retained? | Target must not drop them, but exact exception representation/UI is unspecified |
| BM-03 | How are legacy finished sessions with uncollected lines represented without inventing final outcomes? | Target terminal invariants and history metrics depend on it |
| BM-04 | What timestamp/provenance initializes `lastActivityAt` and expiration for legacy active rows? | Legacy rows have only `startedAt` |
| BM-05 | How is an absent historical list revision represented: unknown provenance, migration revision, or another explicit marker? | Must not falsely claim historical revision |
| BM-06 | What is the minimum legacy plan/stop snapshot completeness required to resume, and when must the row remain unresolved? | Determines migration success versus recovery decision |
| BM-07 | What bounded evidence is retained for invalid/duplicate/foreign UUID tokens? | Prevents silent loss while controlling privacy/storage |
| BM-08 | What quarantine retention and support-recovery policy applies after store recreation? | Rollback/support claims and cleanup depend on it |

### 21.3 Blocking before release

| ID | Unresolved decision | Why it blocks |
|---|---|---|
| BR-01 | How long are expired sessions retained? | Storage, history, UI, and privacy |
| BR-02 | How long are abandoned sessions and their progress retained? | Same, plus user expectations |
| BR-03 | Does Abandon write any Product History event, and how is it distinguished from successful Finish? | Prevents false learning |
| BR-04 | What visible recovery/quarantine notice and support action are required? | Store recreation cannot appear as normal empty state |
| BR-05 | What device-side energy diagnostics are allowed and how long are they retained? | Privacy and release monitoring |
| BR-06 | Is MetricKit included now or deferred? | Instrumentation scope |
| BR-07 | What callback p95, cold-recovery, and migration performance budgets are approved after baseline measurement? | Release gate needs measured thresholds |
| BR-08 | What exact force-quit and background-delivery wording is approved in Product/Settings/help copy? | Must avoid unsupported promises |
| BR-09 | What stale-snapshot age/source labels are required in Shopping and Map? | Offline explainability |
| BR-10 | What compatibility/telemetry threshold permits removal of the legacy payload adapter? | Prevents indefinite mixed compatibility |
| BR-11 | Are delivered session notifications removed on terminal transitions, and under what user-experience policy? | Cleanup and stale-tap behavior |
| BR-12 | What is the supported OS/device field matrix for reboot, force quit, Low Power Mode, approximate location, and Background App Refresh? | Physical qualification |
| BR-13 | Who signs the privacy review for compact identifiers, local ledger, retention, and diagnostic fields? | Privacy gate |
| BR-14 | Who signs English/Hebrew terminology for state, capability, expiry, reconciliation, and degradation? | Cross-screen/localization gate |

### 21.4 Non-blocking follow-up

| ID | Deferred question | Constraint already fixed |
|---|---|---|
| NF-01 | Is the one-active-session invariant per device, account, household, or shared list in a Cloud future? | v1.0.3 local implementation uses the approved local authority scope |
| NF-02 | Which device owns an active session’s background reminders? | Registrations remain device-local; Cloud is disabled |
| NF-03 | How is session ownership transferred between devices? | No current transfer |
| NF-04 | How are conflicting outcomes for the same line merged? | Stable IDs/revisions reserved; no current merge |
| NF-05 | Which timestamp/actor wins future conflicts? | No current Cloud authority |
| NF-06 | Will calendar behavior ever be offered? | It cannot start/expire/mutate current sessions automatically |
| NF-07 | What evidence may future AI use to recommend, but not execute, session actions? | Explicit user confirmation remains mandatory |
| NF-08 | How does Community freshness affect a future plan? | It cannot automatically mutate an active snapshot |
| NF-09 | How do Global Product Concept changes appear in active sessions? | Existing snapshot remains stable; explicit update only if approved |
| NF-10 | How are duplicate multi-device notifications prevented? | No Cloud notifications until owner policy exists |

### 21.5 Decision-control rule

Answers may choose parameters and UX within the approved architecture. They may not:

- remove durable session authority;
- make app process state a business state;
- let one payload or registration become truth;
- allow silent session conflicts;
- infer purchased outcomes;
- require network for committed session recovery;
- turn passive global reminders into session reminders;
- add unsupported background execution;
- let permission/capability cancel session progress;
- introduce dual runtime authority.

Any answer that would violate those constraints requires a new approved architecture decision, not an implementation-plan edit.

---

## 22. Implementation Readiness Checklist

Implementation may begin only when every applicable item is checked by the named owner in an approved implementation specification.

### Architecture compliance

- [ ] WT-030B state machine and Section 7 matrix are copied into the implementation specification without reinterpretation.
- [ ] Session, list, plan, reminder, capability, app lifecycle, Map, and notification ownership remain orthogonal.
- [ ] No continuous background location, polling, significant-change authority, background planner, or unsupported force-quit promise is introduced.
- [ ] Passive nearby behavior is either removed or separately approved/namespaced.
- [ ] One session model supports single- and multi-store use.

### WT-031A contract

- [ ] Stable Product and list-entry identities are approved and available.
- [ ] Persisted list revision semantics are implemented/specifiable.
- [ ] Plan identity includes list ID/revision and entry IDs.
- [ ] Product/store display snapshot policy is approved.
- [ ] Session line is shared, not duplicated.
- [ ] Atomic Finish list/history reconciliation is approved.
- [ ] Compatibility fields are migration-only after cutover.

### Lifecycle and UX decisions

- [ ] Inactivity and maximum lifetime values are approved.
- [ ] Meaningful activity events are enumerated.
- [ ] Finish remaining-line choices are approved.
- [ ] Abandon/expired retention and history behavior are approved.
- [ ] Existing-session conflict UX is approved.
- [ ] Update Session inclusion/exclusion is explicit.
- [ ] Valid, expired, terminal, and missing notification-tap UX is approved.
- [ ] In-memory/recreated-store UX is approved.

### Persistence and migration

- [ ] Exact target schema and transaction boundaries are specified.
- [ ] V1–V3 remain frozen.
- [ ] Multiple-active policy is approved.
- [ ] Missing/malformed/duplicate/foreign token policy is approved.
- [ ] Legacy finished unresolved-outcome policy is approved.
- [ ] Legacy activity/expiration initialization is approved.
- [ ] Plan/list revision provenance is explicit.
- [ ] Migration and repair are idempotent.
- [ ] Quarantine retention/support policy is approved.
- [ ] Forward-fix and phased-release rollback procedure is tested.

### Background, location, and notifications

- [ ] Minimal background application entry path is selected for the supported OS.
- [ ] Background dependency graph excludes MapKit search, planner, AI, Catalog refresh, and broad sync.
- [ ] Foreground location lease API and stop rules are specified.
- [ ] Notification and Always-location prompts are contextual and user-initiated.
- [ ] Region budget/current-vs-future priority is approved.
- [ ] Compact identifier and minimized userInfo pass privacy review.
- [ ] Desired/ledger/actual reconciliation is specified for every transition.
- [ ] Cooldown/quiet/idempotency behavior is approved.
- [ ] Cooldown advances only after scheduling success.
- [ ] Terminal/revision/expiry validation is mandatory at event and tap time.
- [ ] Store recreation/in-memory mode removes or suppresses all managed regions.

### File inventory and authority cutover

- [ ] Every verified file in Section 13 is assigned to an implementation owner.
- [ ] Every proposed file is either accepted with rationale or folded into an existing component without losing testability.
- [ ] Transitional reads are limited to migration/compatibility.
- [ ] No released dual writes exist.
- [ ] Home, Shopping, Map, Settings, ContentView, LocationManager, and notification delegate cut over together.
- [ ] Static rules identify forbidden runtime reads of legacy session fields/payload authority.
- [ ] Legacy region and notification cleanup has a bounded retirement criterion.

### Test and reliability plan

- [ ] State matrix has exhaustive transition fixtures.
- [ ] WT-030B AC-01–AC-50 map to executable evidence.
- [ ] V1/V2/V3 migration corpus covers ambiguity/corruption/multiple rows.
- [ ] 100 cold-cycle progress test is defined.
- [ ] Race, save failure, disk/store recovery, and interrupted migration tests are defined.
- [ ] Offline and reconnection tests are defined.
- [ ] Physical-device background/reboot/force-quit matrix is approved.
- [ ] Performance, callback, battery, and thermal baselines/budgets are approved.
- [ ] Diagnostics are redacted and bounded.

### Localization, accessibility, privacy, and support

- [ ] English and Hebrew semantic vocabulary is approved.
- [ ] RTL, interpolation, and Dynamic Type test cases exist.
- [ ] VoiceOver exposes state, progress, capability, and remedy independently.
- [ ] Permission, force-quit, stale-data, and degraded-mode copy is accurate.
- [ ] Retention and local identifier/ledger privacy review is complete.
- [ ] Support can distinguish migration failure, recreated store, in-memory mode, and reminder failure without Product/location content.

### Release gate

- [ ] An approved implementation specification explicitly authorizes the exact code/schema/test/project changes.
- [ ] No production implementation begins from this plan alone.
- [ ] All blocking-before-implementation and blocking-before-migration questions are closed.
- [ ] All blocking-before-release questions are closed before public cutover.
- [ ] Release uses one authority cutover and a tested forward-fix path.

---

## 23. Terminal Decision

**READY FOR IMPLEMENTATION SPECIFICATION.**

WT-031B provides a complete, dependency-aware plan for implementing the approved Session-Scoped Persistent Hybrid architecture, including the authoritative lifecycle matrix, durable aggregate and snapshot ownership, WT-031A integration boundary, migration and authority cutover, background/location/notification validation, recovery, offline behavior, file-level work, phased rollout, battery/reliability controls, acceptance testing, risks, dependencies, and unresolved decisions.

This decision authorizes preparation and approval of a detailed implementation specification only. It does **not** authorize production source changes, test changes, schema changes, project-setting changes, commits, rollout, or implementation. Production work remains blocked until the implementation specification resolves the classified blockers and explicitly grants that authority.

## Appendix A — Session Timeline

Shopping Plan

↓

Start

↓

Shopping Session

↓

Foreground

↓

Background

↓

Region Event

↓

Notification

↓

User Opens App

↓

Recovery

↓

Finish

↓

History
