# WT-031A — Product State Implementation Plan

**Product:** WayTask iOS  
**Release:** Version 1.0.3  
**Status:** Implementation planning only  
**Architecture authority:** `docs/Audits/1.0.3/WT-030A_ProductStateUXAudit.md` and `docs/Audits/1.0.3/WT-030_ArchitectureSummary.md`  
**Repository baseline inspected:** `35a0775`  
**Implementation authorization:** None

---

## Document Use and Evidence

This plan translates the approved WT-030A Orthogonal Product Lifecycle into a dependency-aware implementation sequence. It does not reopen the architecture decision, define a production schema, or authorize code changes.

Terms in this document have deliberate meanings:

- **Current verified** describes behavior observed in the repository at the baseline above.
- **Approved target** repeats a binding WT-030A or WT-030 Architecture Summary decision.
- **Planned** describes work that a later implementation specification must authorize and make technically exact.
- **Unresolved** identifies a decision that this plan does not invent.

The requested `Version_1.0.3_ProductSpec.md` is not present in the working tree. The available product specification is `design/v1.0/WayTask_Product_Specification_v1.0.pdf`; `docs/10_PRODUCT_SPECIFICATION.md` is empty. This plan therefore uses the available specification for established Product/Shopping intent and treats WT-030A plus the WT-030 Architecture Summary as the controlling Version 1.0.3 architecture. Reconciliation with an official Version 1.0.3 Product Specification is a release gate.

No production source, test, schema, project, catalog, or prior WT-030 document is modified by WT-031A.

---

## 1. Executive Summary

### Current implementation problem

WayTask has already separated reusable `Product` records from `ShoppingListEntry` records, but the cutover is incomplete. Product State is currently inferred from a combination of:

- `Product.deletedAt`;
- `ShoppingListEntry` existence and `isChecked`;
- compatibility `ShoppingItem.isCompleted`;
- runtime `ShoppingPlan` state;
- `ShoppingSession` arrays of compatibility-item UUIDs;
- view-local selection state; and
- saved-location `ShoppingItem` relationships.

These values are written and interpreted by multiple services and views. The most consequential defect is mixed authority: a list entry can say needed while its compatibility item says completed, and different screens resolve that contradiction differently. Product Library cards also use completion-style checkmarks to communicate list membership, which visually implies a global Product completion state that the approved architecture explicitly rejects.

### Approved target architecture

WT-030A approved the Orthogonal Product Lifecycle:

- `Product` owns stable user Product identity and active/removed library lifecycle.
- A named `ShoppingListEntry` owns membership, quantity, order, and needed/resolved state for exactly one list.
- A plan is a revisioned projection of one list.
- A session line owns collection and final outcome for one immutable session snapshot.
- Product History owns confirmed historical events.
- Catalog lifecycle is independent and cannot delete, restore, complete, or purchase a user Product.
- Map, notifications, scanner, Home, and AI are consumers or command issuers, never lifecycle authorities.

### Proposed implementation approach

The implementation should use a **single-release authority cutover** supported by internal migration stages:

1. resolve product-policy and migration blockers;
2. freeze characterization fixtures and performance baselines;
3. add the target persistent concepts and an idempotent semantic migration;
4. route every lifecycle mutation through named commands;
5. introduce one list/session projection consumed by all surfaces;
6. convert compatibility `ShoppingItem` output to a one-way derived adapter only;
7. integrate WT-031B’s session-line and atomic-finish contract;
8. switch Product, Shopping, Home, Map, notifications, scanner, and recovery together; and
9. retire legacy reads immediately, then physically remove compatibility storage only after its support gate.

There must be no released version in which a target field and a legacy field are both allowed to decide Product State.

### Expected phases

The plan defines eight controlled phases: decision closure, characterization, persistence preparation, domain authority, consumer conversion, session/reconciliation integration, migration/recovery qualification, and one final cutover. Intermediate work may exist on an internal branch, but it is not an acceptable user-visible partial release.

---

## 2. Scope

### 2.1 Included in WT-031A

WT-031A plans the Product State work approved by WT-030A:

- stable Product identity and catalog snapshot preservation;
- active/removed Product Library lifecycle;
- explicit restoration of the same Product UUID;
- named-list membership;
- list-entry needed/resolved lifecycle and outcome semantics;
- list revision ownership;
- plan identity contract: list ID, list revision, and included entry IDs;
- session-line Product/list-entry identity contract;
- atomic Finish Shopping reconciliation contract;
- Product History event boundary;
- removal of `ShoppingItem.isCompleted` from authority;
- one-way compatibility output and retirement;
- Product, chooser, Shopping, Home, Map, notification, saved-location, and scanner Product State integration;
- SwiftData migration, startup repair, failure handling, rollback, diagnostics, and data validation;
- English/Hebrew, RTL, Dynamic Type, VoiceOver, and non-color state semantics;
- performance, reliability, test, and rollout gates.

### 2.2 WT-031B boundary

WT-031B owns the full Shopping Session implementation specification, including:

- session lifecycle states, expiration, abandon/resume policy, and active-session conflict UX;
- persisted session stops and plan snapshot;
- background recovery, geofence registration ledger, permissions, battery, and thermal behavior;
- background-safe notification validation;
- offline session recovery and future sync metadata.

WT-031A defines the Product State contract that WT-031B must consume: immutable line identity/snapshots, per-line outcomes, exact source list/revision, and atomic reconciliation. Product State cannot be released until the compatible WT-031B session contract is approved and delivered. WT-031A does not duplicate or weaken WT-030B.

### 2.3 WT-031C boundary

WT-031C owns Community Feedback submission, outbox, moderation, trust, privacy, anti-abuse, and publication planning. WT-031A preserves stable Product/catalog/store references that future evidence may target. Community evidence must never write library, list, plan, session, history, or catalog truth directly.

### 2.4 Explicit exclusions

WT-031A does not plan:

- community-report schemas or backend services;
- cloud sync or conflict-resolution implementation;
- Android implementation;
- a future retail SKU layer;
- live inventory or price truth;
- AI implementation or autonomous state mutation;
- catalog content changes, icon redesign, alias expansion, or Product concept merges;
- general Shopping Session background/location implementation beyond the Product State integration contract;
- unrelated visual redesign.

### 2.5 Release-unit rule

The implementation phases are development dependencies, not independently shippable Product State variants. The public cutover is one coherent release after every authoritative writer and reader uses the approved model.

---

## 3. Current Implementation Inventory

### 3.1 Current authority and data inventory

| Concern | Current verified owner/data | Current behavior |
| --- | --- | --- |
| User Product identity | `Product.id: UUID` in `WayTask/Models.swift` | Stable UUID referenced by list entries; correct ownership and retained. |
| Library lifecycle | `Product.deletedAt` and `isDeletedFromLibrary` | `nil` means active; non-`nil` is a durable tombstone. This is the correct current foundation. |
| Catalog reference | `Product.catalogProductIDRawValue` plus catalog display/category/icon snapshots | Stable catalog reference and offline display snapshots are persisted on the user Product. Correct boundary and retained. |
| Legacy compatibility identity | `Product.legacyShoppingItemID`, `ShoppingListEntry.legacyShoppingItemID`, `ShoppingItem.id` | Bridges Product/list/session/planner code to a denormalized `ShoppingItem`; currently still required by most downstream flows. |
| List identity | `ShoppingList.id`, `title`, `kindRawValue`, `createdAt`, `updatedAt`, `isDefault` | Three kinds exist: `.weekly`, `.completed`, `.recent`. No durable semantic list revision exists. |
| List membership | `ShoppingListEntry` existence for `(shoppingListID, productID)` | Entry presence is used as membership, but uniqueness is enforced only by service lookup, not a global invariant. |
| List resolution | `ShoppingListEntry.isChecked` | Boolean checked state lacks reason, resolution time, and explicit semantics. |
| Compatibility completion | `ShoppingItem.isCompleted` | Used by planner, Home, Map, geofences, session creation, saved locations, and fallback flows as a global completion flag. |
| Plan | Runtime `ShoppingPlan` in `WayTask/AppStateManager.swift` | Holds compatibility items, stores, options, generation time, and content signature. It has no source list revision or entry IDs and is not persisted. |
| Plan invalidation | `AppStateManager.shoppingListRevision: UUID` and `markShoppingPlanStale` | Runtime change signal, not a durable list revision. Some unrelated library changes invalidate a plan; some direct mutations rely on view calls. |
| Session | `ShoppingSession` plus `ShoppingSessionService` | Persists active flag, start/finish time, comma-separated compatibility-item IDs and collected IDs, optional list/store snapshot. No line model or final outcome. |
| History | `ProductHistory` plus `ShoppingMemoryService` | Aggregate keyed by barcode or normalized name, updated on add-to-shopping. `lastCompletedDate` can be inferred from compatibility completion, not confirmed purchase. |
| Catalog truth | Bundled `CatalogProduct`, Product Knowledge repositories/search, validators | Read-only stable concept identity; active/inactive and replacement are separate from user state. Correct boundary and retained. |
| Recognition memory | SwiftData `ProductKnowledge` plus `ProductKnowledgeService` | Mutable barcode/name recognition cache; correctly separate from canonical catalog identity. |
| Saved-location items | `GeoLocation.shoppingItems` | Direct relationship to `ShoppingItem`; `LocationDetailView` can create, toggle, and delete this parallel lifecycle. |
| Recovery | `WayTaskStartupPersistenceBootstrap` plus `ShoppingListBackfillService` | Opens/migrates the store, then performs runtime graph repair. Store-open failure may quarantine and create a new persistent store or fall back to memory. |

### 3.2 Model and domain files

- `WayTask/Models.swift`
  - `GeoLocation`
  - compatibility `ShoppingItem`
  - `Product`
  - `ShoppingListKind`
  - `ShoppingList`
  - `ShoppingListEntry`
  - Product tombstone/restore and Product-to-compatibility conversion helpers.
- `ProductSource.swift`
  - acquisition channel; it is not identity or lifecycle state.
- `ProductHistory.swift`
  - aggregate shopping-memory record with no Product UUID relationship or event ledger.
- `ShoppingSession.swift`
  - current persisted session header and encoded item/collected UUID arrays.
- `ShoppingContext.swift`
  - transient AI/context DTO whose item includes another `isCompleted` boolean.
- `ProductCandidate.swift` and `BarcodeResult.swift`
  - transient acquisition evidence, not lifecycle records.

### 3.3 Persistence and migration files

- `WayTask/Persistence/WayTaskSchemaV1.swift`
  - exact shipped V1 Product and list-entry schema definitions.
- `WayTask/Persistence/WayTaskSchema.swift`
  - `WayTaskSchemaV2`, `WayTaskSchemaV3`, `WayTaskSchemaMigrationPlan`, and `WayTaskModelContainer`;
  - V1→V2 catalog-snapshot and V2→V3 tombstone migrations are lightweight.
- `WayTask/Persistence/WayTaskStartupPersistence.swift`
  - startup open, migration, repair, quarantine, new-store, and in-memory fallback paths.
- `WayTask/Persistence/AddProductSaveCoordinator.swift`
  - separates catalog save from manual save and returns typed outcomes.
- `WayTask/Persistence/CatalogProductPersistenceService.swift`
  - exact catalog-ID deduplication and snapshot persistence;
  - currently restores a catalog-linked tombstone implicitly when the same catalog item is saved.
- `ShoppingListService.swift`
  - `ShoppingListService`;
  - `ProductLibraryDeletionService`;
  - `ShoppingListBackfillService`.

### 3.4 Repositories and services

- `ShoppingListService.swift`
  - manual Product creation;
  - recognized Product upsert;
  - add/reopen/remove list entry;
  - creation and mutation of compatibility `ShoppingItem`;
  - Product Library tombstoning and Weekly-entry deletion;
  - startup repair/backfill.
- `ShoppingSessionService.swift`
  - create/resume the newest active session, collect/uncollect compatibility items, finish header.
- `ShoppingTripService.swift`
  - filters `ShoppingItem.isCompleted`, groups items, and creates store coverage.
- `ShoppingMemoryService.swift`
  - records add frequency and legacy completion aggregate.
- `ProductKnowledgeService.swift`
  - learned recognition cache.
- `WayTask/ProductCatalog/ShoppingItemCatalogResolver.swift`
  - ID-only legacy-to-current catalog crosswalk and compatibility hydration.
- Product Catalog and Product Knowledge service/search/validation files under:
  - `WayTask/ProductCatalog/`
  - `WayTask/ProductKnowledge/`.

### 3.5 State management and application lifecycle

- `WayTask/AppStateManager.swift`
  - selected list, current list, runtime plan and plan-generation state;
  - runtime staleness signal;
  - Map handoff;
  - nearby-opportunity state;
  - notification parsing and routing.
- `WayTask/WayTaskApp.swift`
  - startup persistence composition and read-only catalog search composition.
- `WayTask/ContentView.swift`
  - startup backfill triggers, selected-list flow, legacy-review `Start Fresh`, session routing, geofence input generation, and Product chooser.

### 3.6 Product and Shopping UI

- `ProductListView.swift`
  - active Product query, Product cards, add/remove-list actions, library deletion, Product image updates, scanner presentation, compatibility planning, and dormant/duplicate session UI code.
- `WayTask/ShoppingWorkspaceView.swift`
  - list chooser, list rows, direct entry toggles/quantity changes, compatibility adaptation, plan generation, Map handoff, store selection, session start/progress/finish.
- `WayTask/HomeView.swift`
  - list summaries, needed/completed counts, plan display, active session progress, scanner entry, recent Product cards, and fallback compatibility reads.
- `WayTask/ContentView.swift` / `ProductShoppingSelectionSheet`
  - initial/chooser selection state and batch add.

### 3.7 Map, notifications, and saved locations

- `WayTask/MainMapView.swift`
  - default Map classification from all compatibility items unless a shared plan exists.
- `MapViewModel.swift`
  - runtime Map products/stores, selected store, plan application, notification context, Apple Maps handoff.
- `MapBottomSheet.swift`
  - read-only likely-product labels and estimated-store language.
- `WayTask/LocationManager.swift`
  - permission/location ownership, geofence candidate resolution and registration.
- `GeofenceNotificationService.swift`
  - payload encoding/decoding, cooldown, notification generation.
- `WayTask/LocationDetailView.swift`
  - direct create/toggle/delete operations on location-owned compatibility items.

### 3.8 Scanner and Product creation

- `CameraView.swift`
  - recognition confirmation and persistence calls;
  - saves recognized/manual-barcode candidates to Product Library;
  - currently signals a Shopping-list change even for a library-only save.
- `CameraViewModel.swift`
  - recognition state and Product candidate confirmation;
  - correctly owns no SwiftData Product State;
  - success copy says “Saved to Product Library.”
- `WayTask/Persistence/AddProductSaveCoordinator.swift`
  - correct separation of catalog and manual creation.
- `ProductCandidate.swift`, `BarcodeResult.swift`, Product autocomplete/search files
  - transient acquisition state and stable catalog selection metadata.

### 3.9 Current tests and fixtures

Existing tests that must be retained and adapted:

- `WayTaskTests/Persistence/WayTaskSchemaMigrationTests.swift`
  - exact V1/V2/V3 graphs and file-backed migration with IDs, relationships, catalog snapshots, history, and session data.
- `WayTaskTests/Persistence/StartupRepairIdempotencyTests.swift`
  - partial repair, repeated launch, catalog metadata repair, and tombstone non-resurrection.
- `WayTaskTests/Persistence/StartupPersistenceResilienceTests.swift`
  - quarantine/new-store/in-memory recovery diagnostics.
- `WayTaskTests/Persistence/ProductLibraryDeletionPersistenceTests.swift`
  - durable tombstone, history retention, historical orphan behavior, barcode repair.
- `WayTaskTests/Persistence/CatalogProductPersistenceServiceTests.swift`
  - exact-ID dedupe, current explicit-add restoration behavior, rollback on failed save.
- `WayTaskTests/Persistence/CatalogProductCompatibilityTests.swift`
  - Product/entry/compatibility links and catalog snapshot protection.
- `WayTaskTests/Persistence/AddProductSaveCoordinatorTests.swift`
  - catalog/manual path separation and retry.
- `WayTaskTests/ProductKnowledge/LegacyProductCreationCharacterizationTests.swift`
  - current manual Product shape and entry compatibility.
- `WayTaskTests/ShoppingClassification/CanonicalCatalogSelectionFlowTests.swift`
  - stable catalog identity from Product through Shopping/planner/Map and semantic icons.
- `WayTaskTests/ShoppingClassification/OtherItemsClassificationTests.swift`
  - unresolved custom Product visibility and false-match prevention.
- `WayTaskTests/ShoppingUX/ShoppingWorkspaceUXTests.swift`
  - store-card and Product-label presentation only.
- `WayTaskTests/Map/MapBottomSheetProductLabelTests.swift`
  - Map Product-label layout only.
- Product Catalog/Product Knowledge suites
  - stable IDs, catalog migration, deactivation/replacement validation, search, localization, accessibility copy, and performance.

Verified test gaps:

- no focused `ShoppingSessionService` lifecycle/outcome tests;
- no atomic Finish Shopping reconciliation tests;
- no cross-list isolation transition suite;
- no Home/Product/Shopping/Map/notification projection parity suite;
- no geofence payload revision/staleness suite;
- no notification deep-link restoration suite;
- no scanner-to-library/list lifecycle integration suite;
- no Product History event-semantic suite;
- no accessibility UI suite for Product State controls;
- no corrupted Product State migration or semantic rollback suite.

---

## 4. Current Authority Problems

### 4.1 Architectural authority defects

| Problem | Verified evidence | Consequence | Planned correction |
| --- | --- | --- | --- |
| Entry and compatibility completion are co-authoritative | `ShoppingWorkspaceView` toggles `entry.isChecked` and mirrors `item.isCompleted`; services also write both | Interrupted/partial saves and alternative writers can disagree | Target entry or session line becomes sole authority; compatibility is one-way derived output only. |
| Global fallback overrides list scope | Home, Product, Shopping, planner, Map, location, and session paths filter all `ShoppingItem` records by `isCompleted` | A Product in one list can affect another list or global context | All reads require an explicit list projection or session snapshot. |
| List entry state is semantically compressed | `ShoppingListEntry.isChecked` has no reason/time | “Checked” can mean resolved, purchased, collected, or removed depending on screen | Explicit needed/resolved lifecycle with approved reason and timestamp. |
| Plan identity is incomplete | Runtime `ShoppingPlan` has no list revision or entry IDs | A plan cannot prove it matches the current list | Persist or expose list ID, revision, and exact entry IDs. |
| Plan invalidation has wrong scope | library-only saves call shopping-list change; list mutation relies on view signals | Unrelated Products stale plans, while out-of-band writes can leave stale plans “ready” | Revision increments inside the authoritative list transaction; plan validity derives from revision. |
| Session stores compatibility IDs, not immutable lines | `ShoppingSession.itemIDs` and `collectedItemIDs` are comma-separated `ShoppingItem.id` arrays | Missing items, list changes, catalog changes, and recovery lose meaning | WT-031B session lines reference source entry/Product IDs and own display snapshots/outcomes. |
| Finish does not reconcile | `ShoppingSessionService.finishShopping` only sets `isActive` and `finishedAt` | Collected/remaining lines do not create deterministic list/history outcomes | Atomic session + entry + history reconciliation, with every line assigned an approved outcome. |
| Views write lifecycle fields | `ShoppingWorkspaceView`, `ContentView`, and `LocationDetailView` mutate booleans/delete rows directly | Different UI surfaces implement different transition policies | Named commands become the only production mutation route. |
| Product removal assumes Weekly-only cleanup | `ProductLibraryDeletionService` deletes entries only for `.weekly` lists and completes linked compatibility items | Other active/custom lists and active sessions can retain unclear references | Apply the approved library-removal membership policy to every affected active list/session explicitly. |
| Product restoration is implicit in acquisition | recognized upsert and catalog save can clear tombstones | A removed Product can reappear without an explicit Restore decision | Acquisition returns a tombstone-match outcome; a separate explicit restore command preserves UUID and creates no list membership. |
| Runtime backfill still participates in lifecycle | `ShoppingListBackfillService` creates/links Products and entries on startup and is invoked after item changes | Startup repair can act like ongoing reverse synchronization | After cutover, repair validates/repairs target graph only; legacy import is migration-only and cannot restore or decide live state. |
| Product History is inferred from compatibility | `ShoppingMemoryService` can set `lastCompletedDate` from `ShoppingItem.isCompleted` | History can falsely imply completion/purchase | History records named confirmed events; legacy aggregate remains explicitly unverified. |
| Saved locations implement a parallel Product lifecycle | `LocationDetailView` creates, toggles, and deletes location `ShoppingItem` rows | Map/location state can bypass library/list commands | Either use Product/list commands or explicitly classify these as separate location notes under an approved policy. |
| Notification payload is frozen authority | payload contains compatibility Product names/IDs and optional list ID; event handling does not validate current revision | A stale notification can contradict Shopping | Payload identifies a revisioned projection/session and is revalidated before schedule and tap routing. |
| Degraded persistence is not user-visible | startup can continue in memory after store failure | UI can imply durable Product State when changes will disappear | Retain startup mode in app state, warn clearly, and disable claims/actions that require durability according to approved degraded-mode policy. |

### 4.2 UX inconsistencies caused by authority defects

- Product cards use an empty/filled circular checkmark for “not on/on selected Shopping list,” visually conflating reusable library membership with completion.
- “Already in Shopping” does not name the owning list.
- Removing from Shopping and checking/resolving are separate actions but share completion-style vocabulary.
- `ProductShoppingSelectionSheet` presents already-in-list and newly pending Products with the same filled checkmark and the same “Selected” accessibility value.
- Shopping shows “Checked,” “Needed,” “Collected,” and plan eligibility using overlapping booleans.
- Home counts entries by `isChecked` and then filters compatibility items by `isCompleted`, so one card may have two filters for one number.
- Map and notifications can show globally incomplete items that are not in the list identified by the payload.
- Completed and Recent appear as list kinds although their lifecycle and edit rules are not defined.
- Scanner success accurately says Product Library, but the code emits a Shopping-list change and the workflow offers no approved explicit restore/list continuation.

### 4.3 UX polish that is not an authority defect

Catalog icon specificity, input alignment, spacing, typography, and general visual styling may affect usability but do not determine Product State ownership. WT-031A changes these only where needed to remove a misleading lifecycle cue, preserve labels at Dynamic Type sizes, or meet accessibility/localization requirements. It does not authorize a general icon or form redesign.

---

## 5. Target Domain Model

This section is conceptual. Exact SwiftData attributes, indexes, relationships, raw-value encodings, and filenames require the later implementation specification.

### 5.1 Ownership model

| Concept | Approved owner | Planned semantics |
| --- | --- | --- |
| Product identity | User `Product` | Stable UUID, user-owned display/detail fields, optional stable catalog reference and snapshots. No global shopping/completion/purchase fields. |
| Library lifecycle | User library membership represented by `Product` tombstone | `active` or `removed`; current `deletedAt` may remain the durable representation because it already has correct ownership. Restore is explicit and keeps the same UUID. |
| Shopping-list membership | Named `ShoppingListEntry` | Entry existence means membership in exactly one `ShoppingList`. At most one current entry for `(listID, productID)`. |
| List need lifecycle | Named `ShoppingListEntry` | `needed` or `resolved`; resolved has an approved reason and time. Quantity/order are entry-owned. Reopen is a named transition. |
| List revision | `ShoppingList` | Monotonic durable revision changed in the same transaction as every membership/resolution/quantity/order mutation that affects projections. |
| Plan | Shopping plan aggregate/projection | Identifies source list ID/revision and exact included entry IDs; includes display/store snapshots needed for explanation and session start. A plan does not mutate entries. |
| Session line | Shopping Session | Immutable source entry/Product identity and display snapshot at start; current execution state and one final approved outcome. Collection is not purchase. |
| Product History | History/event owner | Named Product/list/session outcomes only; no stronger claim than the event actually confirms. Legacy aggregates remain labeled unverified until rebuilt from events. |
| Catalog reference | Catalog + saved Product snapshot | Catalog owns current concept truth; saved user Product owns its reference and offline snapshot. Catalog lifecycle never changes user lifecycle. |

### 5.2 Product identity and library lifecycle

Retain:

- `Product.id`;
- user images, names, brand/category/details, barcode, source, and timestamps;
- catalog Product ID and saved display/category/icon snapshots;
- `deletedAt` as the current durable tombstone foundation unless the implementation specification proves a separate membership record is required.

Planned commands:

- acquire/create Product;
- remove Product from Library;
- explicitly restore Product;
- edit Product attributes;
- explicitly refresh a catalog snapshot if a later approved workflow permits it.

Removal and restoration never infer list membership. Catalog deactivation, replacement, startup repair, recognition, and AI cannot call restoration implicitly.

### 5.3 Named Shopping-list entry lifecycle

Conceptual state:

```text
absent
  -> needed
  -> resolved(reason, resolvedAt)
  -> needed (approved reopen rule)
  -> absent (remove from this list)
```

The implementation specification must approve:

- resolution reason taxonomy;
- whether resolving outside a session is permitted;
- retention/hiding/projection behavior;
- reopen event preservation;
- duplicate-entry and conflict policy.

The current `isChecked` value may remain only as migration input or derived compatibility during the transition. It is not an acceptable target authority.

### 5.4 Plan projection

A ready plan must expose:

- plan ID and generation timestamp;
- source list ID;
- source durable list revision;
- exact included `ShoppingListEntry.id` values;
- Product IDs and selection-time display snapshots needed by the UI;
- surfaced exclusions/unresolved items;
- store recommendations and selected-store state;
- staleness reason.

Any mutation that changes the source projection invalidates the plan before Map, notification, or session use. A library-only change unrelated to included Products does not invalidate it.

### 5.5 Session-line outcome

WT-031A requires the Product State portion of the session contract:

- line ID;
- source entry ID and Product UUID when resolvable;
- immutable Product display/catalog snapshots;
- quantity;
- collected/not-collected execution state;
- final outcome from an approved taxonomy;
- outcome time and provenance sufficient for list/history reconciliation.

WT-031B owns the enclosing session, store/stop, recovery, expiration, background, and synchronization model. WT-031A must not implement a competing session-line store.

### 5.6 Product History

The target history boundary records named events such as Product added to a list, entry resolved/reopened/removed, and confirmed session outcomes. The exact event taxonomy follows approved Product policy.

Rules:

- `checked`, `collected`, `finished`, and `purchased` are never synonyms;
- a legacy `lastCompletedDate` cannot be promoted to purchase evidence;
- events reference stable Product UUID and relevant list/session IDs where available;
- catalog concept IDs are optional references, not event identity;
- aggregate frequency/recency views may be derived for performance.

### 5.7 Catalog references and snapshots

Retain the current correct boundary:

- deduplicate catalog-linked user Products only by exact canonical catalog ID;
- never match migration records by name/category similarity;
- preserve user Product UUID and snapshots through catalog rename/deactivation/replacement;
- resolve redirects without silently rewriting shopping state;
- keep unresolved custom Products unlinked;
- preserve Product Knowledge and learned recognition cache as separate concepts.

---

## 6. Authority Cutover Strategy

### 6.1 Cutover invariant

At every point in a released build, exactly one model decides each lifecycle:

- Library: Product tombstone.
- List membership/resolution: named list entry.
- Plan validity: list revision and plan source metadata.
- Collection/outcome: session line.
- History: named event.

Legacy values may exist physically after cutover, but they are outputs or archival migration evidence only.

### 6.2 Development stages

| Stage | Reads | Writes | User-visible release status |
| --- | --- | --- | --- |
| Baseline characterization | Existing authorities | Existing authorities | Current release only; no new target behavior. |
| Target persistence introduced internally | Existing behavior while migration is exercised in test/internal builds | Migration writes target fields; production commands remain gated | Not a Product State release. |
| Command/projection shadow validation | Target projection compared diagnostically with legacy output | Target commands write target; optional one-way compatibility mirror writes legacy output | Internal/QA only; legacy never writes back into target at runtime. |
| Full consumer conversion | Product/Shopping/Home/Map/notifications/scanner/session read target projection | Named target commands only | Eligible for release only when every consumer is converted. |
| Retirement | Target only | Target only | Legacy fields ignored; physical removal is a later compatible schema step. |

“Shadow” means comparison and diagnostics, not two authorities. UI decisions and domain results must still come from one selected authority in each build configuration.

### 6.3 Transitional reads

1. Before semantic migration, legacy fields may be read only by the migration/import routine.
2. After a store is marked migrated, production lifecycle queries read target data only.
3. A missing target relationship after migration becomes an explicit exception/repair result; code must not silently fall back to `ShoppingItem.isCompleted`.
4. Compatibility adapters may read the target projection to create `ShoppingItem`-shaped values for still-unconverted pure algorithms during internal development.
5. A compatibility object must never be queried to decide membership, plan eligibility, Map context, notification context, session line state, restore, or deletion after cutover.

### 6.4 Transitional writes

1. Named commands commit target state in one transaction.
2. If an internal compatibility mirror is temporarily necessary, it is updated from the committed target result in the same transaction or regenerated from that result.
3. There is no runtime `ShoppingItem`→entry reverse synchronization after migration.
4. Views, lifecycle callbacks, Map, notifications, scanner, and AI do not write target fields directly.
5. List revision increments inside the same authoritative command; a later view callback is not part of correctness.

### 6.5 Compatibility adapters

The adapter contract must be:

- target input only;
- deterministic and side-effect-free when used as a read model;
- catalog/display snapshots sourced from Product/entry/session data;
- explicit about list/session scope;
- incapable of restoring or deleting a Product;
- instrumented for remaining call-site counts;
- unavailable to new Product State features.

Planner/store-classification algorithms may temporarily receive adapted values, but eligibility is decided before adaptation by the target list/session projection.

### 6.6 Deprecation and final removal

Deprecation order:

1. prohibit new direct writers;
2. migrate persisted meaning;
3. remove legacy selection/filtering;
4. remove legacy Map/notification/session payload use;
5. remove runtime reverse backfill;
6. stop emitting the compatibility mirror;
7. retain physical fields/models read-only for the approved support window;
8. remove them only in a separately validated schema migration.

The support-window length is unresolved. Retaining a field does not retain its authority.

### 6.7 Rollback implications

- Before a user store is migrated, the feature can be disabled without data conversion.
- After migration writes a new schema, an older binary must not be assumed able to open the store.
- Release rollback therefore requires a forward-compatible build that understands the new schema and can disable the new UI without reverting to legacy authority.
- Restoring a pre-migration store backup is a separate user-data recovery action; it can discard post-migration changes and requires explicit policy.
- Semantic-migration failure must leave the original store recoverable. The existing “quarantine and create empty store” path is not an acceptable silent rollback for a Product State semantic migration.
- A post-cutover defect must be fixed forward unless an approved, tested full-store recovery path exists.

---

## 7. Data Migration Strategy

### 7.1 Records in scope

Migration must inspect and preserve:

- every `Product`, including tombstones;
- every `ShoppingList` and `ShoppingListEntry`;
- every compatibility `ShoppingItem`;
- `GeoLocation.shoppingItems` relationships;
- every `ShoppingSession`;
- every `ProductHistory`;
- every SwiftData `ProductKnowledge`;
- catalog reference/snapshot values;
- IDs, timestamps, quantities, order, images, and relationships;
- Completed/Recent historical references;
- startup-repair diagnostics relevant to exceptions.

### 7.2 Deterministic interpretation rules

| Legacy value | Safe interpretation | Prohibited inference |
| --- | --- | --- |
| `Product.deletedAt == nil` | Active library Product | Current Shopping membership or purchase state. |
| `Product.deletedAt != nil` | Removed/tombstoned Product | Archive, privacy erasure, or catalog deactivation. |
| `ShoppingListEntry` exists | Membership in that exact list | Membership in any other list. |
| `ShoppingListEntry.isChecked == false` | Candidate for `needed`, subject to contradiction validation | Not-collected or not-purchased. |
| `ShoppingListEntry.isChecked == true` | Ambiguous resolved-like legacy evidence | Purchased, collected, unavailable, or a specific reason. |
| `ShoppingItem.isCompleted` | Compatibility evidence used only to detect contradiction | Product completion, purchase, library removal, or list identity. |
| `ShoppingSession.collectedItemIDs` | Legacy collected evidence within that session if resolvable | Purchased or final outcome. |
| Completed/Recent entries | Historical references whose semantics must be approved | Automatically verified projections. |
| Missing Product relationship with stored `productID` | Explicit unresolved migration exception | Silent deletion or name-based replacement. |
| Catalog Product ID/snapshot | Preserve exactly; resolve only through stable ID/approved redirect | Re-identification from Product name/category/barcode. |

The final mapping of `isChecked`/`isCompleted` contradictions is unresolved. The approved rule must choose either conservative needed state or a resolved `legacyUnknown` state per defined evidence. It must never create a purchased outcome.

### 7.3 Stable identity and snapshot preservation

- Preserve every `Product.id` exactly.
- Preserve list, entry, session, history, knowledge, location, and compatibility UUIDs needed for reconciliation.
- Preserve Product user fields and image bytes.
- Preserve catalog Product ID and all saved display/category/icon snapshots without refresh.
- Preserve `deletedAt` and never call restore during migration.
- Preserve source and timestamps; migration metadata must not overwrite user `updatedAt`.
- Preserve orphan IDs as explicit exceptions rather than substituting a look-alike Product.

### 7.4 List membership and duplicate handling

Migration must enforce one current entry per `(listID, productID)`. Before code begins, an approved merge rule must define:

- which entry UUID survives;
- quantity reconciliation;
- needed/resolved conflict behavior;
- order/timestamp preservation;
- relationship repair;
- session references to a non-surviving entry;
- diagnostics and rollback.

No duplicate row may be silently deleted merely because it has a later timestamp. The migration report records counts by duplicate/conflict category.

### 7.5 Removed Products

- Tombstoned Products remain recoverable with the same UUID.
- Migration does not create an active Product from a compatibility item that points to a tombstone.
- Historical entries/history/knowledge survive.
- Active-list membership handling follows the unresolved Product-removal policy; migration must preserve ambiguous references until that policy is approved.
- No list is automatically repopulated on restore.

### 7.6 Legacy list completion

- Entry quantity, sort order, timestamps, list ID, and Product relationship are preserved.
- Checked/completed flags are migrated conservatively and counted.
- Checked state does not create purchase history.
- The implementation specification must define whether `.completed` and `.recent` are converted into projections, retained as legacy archives, renamed, or removed from UI.

### 7.7 Legacy sessions

In coordination with WT-031B:

- preserve session UUID, start/finish times, list/store fields, and active/finished evidence;
- map each compatibility item UUID through `ShoppingListEntry.legacyShoppingItemID` and `Product.legacyShoppingItemID` where unambiguous;
- preserve a missing/unresolvable item as an explicit unresolved session line with available snapshot evidence;
- map collected IDs only to legacy collected state, never purchase;
- do not fabricate list revision, resolution reason, unavailable/skipped outcome, or store truth;
- resolve multiple active sessions only through WT-031B’s approved observable policy.

### 7.8 Product History

- Preserve existing `ProductHistory` rows and aggregate values.
- Where one stable Product UUID can be proven from durable links, record that mapping without rewriting the aggregate’s historical claim.
- Do not treat `lastCompletedDate` as a purchase event.
- New named events begin at cutover unless an approved deterministic event reconstruction policy exists.
- Personalization that currently uses legacy history must remain deterministic and must not merge Products by ambiguous name.

### 7.9 Staging and idempotency

A staged semantic migration is likely required because the transition is not a lightweight field addition:

1. open the existing schema without exposing lifecycle UI;
2. capture pre-migration counts/checksums and a recoverable store boundary;
3. perform schema evolution;
4. normalize target relationships and states under an explicit migration version;
5. validate invariants;
6. mark completion atomically;
7. expose the app only after success.

Re-entry after interruption must detect completed work by stable migration metadata and content invariants, not by timestamps alone. Running migration/repair twice must produce zero count, identity, state, or timestamp drift.

### 7.10 Failure handling

- Fail closed before presenting a writable Product State UI if semantic migration is incomplete.
- Keep the original store and sidecars recoverable.
- Emit privacy-safe diagnostics: schema transition, stage, counts, exception categories, and deterministic failure code; do not emit Product names, barcodes, list contents, or precise location.
- Do not report a user mutation as durable in an in-memory store.
- Do not auto-create an empty store as if it were a successful Product State migration.
- Provide the approved retry/recovery/degraded-mode UX before release.

### 7.11 Migration test fixtures

Required fixtures:

- shipped V1, V2, and V3 file-backed stores;
- active and tombstoned Products;
- catalog-linked, custom, malformed-link, inactive/replaced, and missing-catalog Products;
- Products in zero, one, and multiple lists;
- every `isChecked`/`isCompleted` contradiction;
- duplicate `(listID, productID)` entries;
- missing Product relationships and orphan IDs;
- Completed/Recent-only history;
- active and finished sessions with collected/unresolved/missing items;
- saved-location compatibility items;
- interrupted migration at every stage;
- corrupted store and corrupted semantic row;
- repeated launch/migration;
- production-scale library/list/session fixture.

---

## 8. File-by-File Change Plan

Phase references use the sequence in Section 9. “Proposed” paths are candidates requiring confirmation in the later implementation specification; they do not exist today.

### 8.1 Models and domain types

| File/component | Current responsibility | Planned responsibility/change | Dependencies / phase | Tests affected |
| --- | --- | --- | --- | --- |
| `WayTask/Models.swift` — `Product` | User Product, catalog snapshots, tombstone, compatibility link | Retain UUID, snapshots, user fields, and `deletedAt`; prevent implicit restoration; remove lifecycle dependence on `legacyShoppingItemID`; expose library state without adding shopping/session state | Policy decisions; P3–P4 | deletion, restoration, catalog compatibility, transition tests |
| `WayTask/Models.swift` — `ShoppingItem` | Global denormalized Product plus `isCompleted` | Mark compatibility-only; no authority or direct UI writer; eventually remove after support gate | Cutover adapter; P3–P7 | legacy fixtures, retirement/no-read checks |
| `WayTask/Models.swift` — `ShoppingList` | List metadata and kind | Own durable monotonic revision; define allowed list-kind semantics after Product decision | List policy; P2–P3 | revision, list isolation, migration |
| `WayTask/Models.swift` — `ShoppingListEntry` | Membership, quantity, `isChecked`, Product relation | Own explicit needed/resolved lifecycle, reason/time/update metadata, and uniqueness invariant; retire `isChecked` authority | Resolution/duplicate policy; P2–P3 | transitions, duplicates, migration, query performance |
| `WayTask/Models.swift` — `GeoLocation` | Saved store with direct compatibility items | Stop owning a parallel Product lifecycle; retain store data while relationship is migrated or explicitly reclassified | Saved-location policy; P4 | Map/location migration tests |
| `ProductHistory.swift` | Barcode/name-keyed aggregate | Preserve legacy aggregate; add or relate approved named Product events without inventing history | Outcome taxonomy; P2–P5 | history semantics and migration |
| `ShoppingSession.swift` | Session header and encoded compatibility IDs | Evolve only under WT-031B; accept source list/revision and normalized line/outcome ownership required by WT-031A | WT-031B; P5 | session migration/recovery/finish |
| `ShoppingContext.swift` | AI/context DTO with `isCompleted` | Replace global completion with explicit scoped list/session presentation state; remain read-only context | Projection contract; P4 | AI-context fixture/no-authority tests |
| `ProductSource.swift` | Acquisition channel | Retain unchanged lifecycle meaning; ensure switches do not infer state from source | P3 | source regression |
| `ProductCandidate.swift`, `BarcodeResult.swift` | Transient acquisition evidence | Retain as non-authoritative input; carry only evidence/identity needed by save flow | P4 | scanner integration |
| **Proposed:** `WayTask/ProductState/ProductStateProjection.swift` | Does not exist; joins are duplicated in views | Central platform-neutral read models/builders for library cards, named-list entries, plan input, Map/notification context, and migration exceptions | Exact placement must be specified; P3 | projection parity and performance |

### 8.2 Persistence and migration

| File/component | Current responsibility | Planned responsibility/change | Dependencies / phase | Tests affected |
| --- | --- | --- | --- | --- |
| `WayTask/Persistence/WayTaskSchemaV1.swift` | Exact shipped V1 graph | Keep immutable as migration source fixture | P1 | exact-schema tests |
| `WayTask/Persistence/WayTaskSchema.swift` | V2/V3 schemas, migration plan, container | Add the approved next version/stages; include Product State models/fields/index strategy; keep prior schemas exact | Data decisions; P2 | schema graph and V1/V2/V3 file migrations |
| **Proposed:** `WayTask/Persistence/WayTaskProductStateMigration.swift` | Does not exist | Contain semantic graph migration, exception ledger, validation, idempotency, and stage diagnostics rather than expanding runtime backfill | Exact name/shape specified later; P2 | semantic migration/interruption/corruption |
| `WayTask/Persistence/WayTaskStartupPersistence.swift` | Open, migrate, repair, quarantine, recreate, memory fallback | Sequence schema + semantic migration before UI; preserve original store on Product State migration failure; expose durable/degraded mode to app state; disarm stale context as required | Recovery UX/policy; P2, P6 | resilience, degraded mode, failure truthfulness |
| `WayTask/Persistence/AddProductSaveCoordinator.swift` | Catalog/manual save routing | Retain separation; add typed “existing tombstone requires explicit restore” and destination outcome without implicit list mutation | Restore/scanner policy; P3–P4 | add/restore/retry |
| `WayTask/Persistence/CatalogProductPersistenceService.swift` | Exact-ID dedupe, insert, implicit tombstone restore | Retain exact-ID/snapshot behavior; return tombstone match without restoring; accept only explicit restore command after user confirmation | Restore wording/policy; P3 | catalog restoration and rollback |
| `ShoppingListBackfillService` in `ShoppingListService.swift` | Default-list creation and ongoing legacy graph repair | Split migration-only import from target graph validation; stop live reverse sync and resurrection paths after migrated marker; preserve idempotent safe metadata repair | P2–P3 | startup repair/no-resurrection |

### 8.3 Repositories and services

| File/component | Current responsibility | Planned responsibility/change | Dependencies / phase | Tests affected |
| --- | --- | --- | --- | --- |
| `ShoppingListService.swift` — `ShoppingListService` | Product acquisition plus list/compatibility writes | Retain existing boundary but expose named library/list commands; perform target-only mutations, revision increment, idempotent add/reopen, one-list remove, and typed outcomes; eliminate dual writes as authority | Domain policy; P3 | full transition matrix/list isolation |
| `ShoppingListService.swift` — `ProductLibraryDeletionService` | Tombstone Product, delete Weekly entries, complete compatibility item | Apply approved all-list/session policy; tombstone once; preserve history/knowledge/snapshots; no implicit physical deletion | Product removal policy; P3 | multi-list deletion, active session, relaunch |
| `ShoppingSessionService.swift` | Start/resume, collect, finish session header | Under WT-031B, operate normalized lines, explicit conflict decision, and atomic Finish reconciliation; never accept `ShoppingItem` authority | WT-031B + outcomes; P5 | session lifecycle/finish/recovery |
| `ShoppingTripService.swift` | Filters `ShoppingItem.isCompleted` and computes coverage | Accept an already-scoped plan-input projection; retain store-matching/ranking logic; never decide Product eligibility | Projection; P4 | planner parity/exclusions |
| `ShoppingMemoryService.swift` | Add-frequency and completion aggregate | Record/derive from named events; retain legacy aggregate as compatibility read where required; no `isCompleted` inference | History policy; P3–P5 | event and personalization tests |
| `ProductKnowledgeService.swift` | Learned recognition cache | Retain; accept target Product acquisition events without becoming identity/lifecycle authority | P3–P4 | recognition regression |
| `WayTask/ProductCatalog/ShoppingItemCatalogResolver.swift` | Legacy ID crosswalk and compatibility hydration | Retain stable ID-only resolution; move presentation resolution to Product/projection snapshots; stop mutating compatibility objects as lifecycle repair | P3–P4 | catalog identity/no-guess tests |
| Product Catalog/Product Knowledge repositories and validators | Read-only catalog/search truth | Retain current ownership; add no Product State writes | P1–P7 | existing catalog suites plus deactivation integration |

### 8.4 View models and shared state

| File/component | Current responsibility | Planned responsibility/change | Dependencies / phase | Tests affected |
| --- | --- | --- | --- | --- |
| `WayTask/AppStateManager.swift` | Selected list, runtime plan, staleness signal, Map/notification routing | Hold presentation/navigation state only; plan carries authoritative source metadata; selected-list changes do not rewrite domain; notification routing resolves a validated target projection | Projection + notification contract; P4–P5 | plan validity, routing, stale payload |
| `CameraViewModel.swift` | Recognition state | Retain recognition-only ownership; represent explicit save destination/restore decision in presentation state without persistence mutation | Scanner policy; P4 | scanner state/copy |
| `MapViewModel.swift` | Map projection, selected store, navigation | Consume plan/session/list projection; remove global `!isCompleted` fallback; remain read-only except explicit domain commands supplied by owner | P4–P5 | Map parity and stale context |
| Existing autocomplete view model under `WayTask/ProductKnowledge/Presentation/` | Search/selection state | Retain; surface typed active/already-active/tombstone acquisition outcomes and exact destination copy | P4 | autocomplete accessibility/save tests |

### 8.5 Product UI

| File/component | Current responsibility | Planned responsibility/change | Dependencies / phase | Tests affected |
| --- | --- | --- | --- | --- |
| `ProductListView.swift` | Library, cards, list membership, add/remove, deletion, images, compatibility planner/session code | Render library projection; remove completion circles; name list scope; send named commands; add explicit removal confirmation/restore entry point as approved; remove planner/session ownership and direct lifecycle writes | UX policy + projection; P4 | Product card semantics, removal/restore, a11y |
| `ProductListView.swift` — `ProductRowCard` | Displays Product with circular membership indicator | Separate reusable Product identity from named-list membership; use text/action semantics and decorative semantic icon only | P4 | snapshot/UI accessibility tests |
| `WayTask/ContentView.swift` | Startup repair, chooser, legacy review, geofence source, recovery routing | Move repair to startup coordinator; replace `Start Fresh` direct writes with command; provide scoped projection to geofences; recover session independently of notification authorization | P2, P4–P5 | startup, chooser, geofence, recovery |
| `ProductShoppingSelectionSheet` in `WayTask/ContentView.swift` | Batch selection with ambiguous filled checks | Distinguish already-in-list from pending addition; label Clear All scope; issue one idempotent command batch to one named list | P4 | chooser semantics/list isolation |
| `WayTask/HomeView.swift` | List counts, plan, recent Products, session progress | Consume list/session projections; remove dual filters and fallback compatibility lists; route cards to approved destination | Home navigation policy; P4–P5 | counts, routing, session progress |

### 8.6 Shopping UI

| File/component | Current responsibility | Planned responsibility/change | Dependencies / phase | Tests affected |
| --- | --- | --- | --- | --- |
| `WayTask/ShoppingWorkspaceView.swift` | Lists, direct checks/quantity writes, compatibility adaptation, plan/session UI | Use entry projection and named commands; show needed/resolved reason; generate from list revision; start immutable session snapshot; Finish through atomic reconciliation; remove `ShoppingItem` joining and direct writes | Resolution/session policies; P4–P5 | list transitions, plan, session, UX |
| `ShoppingWorkspaceListChip` and list summary presentation | Counts by `isChecked` | Count target needed/resolved states and disclose projection semantics for system lists | Completed/Recent policy; P4 | list-count parity |
| Shopping Mode rows in `WayTask/ShoppingWorkspaceView.swift` | Collects compatibility items by session UUID arrays | Render session lines and execution/final outcomes; collection remains session-only | WT-031B; P5 | collection/undo/finish |

### 8.7 Map and notifications

| File/component | Current responsibility | Planned responsibility/change | Dependencies / phase | Tests affected |
| --- | --- | --- | --- | --- |
| `WayTask/MainMapView.swift` | Default classification from all compatibility items; shared-plan mode | Require explicit plan/session/list context or a clearly non-shopping Map mode; no global Product State fallback | P4 | context parity/empty state |
| `MapViewModel.swift` | Map stores/products and notification materialization | Validate projection identity/revision; materialize snapshots without becoming authority | P4–P5 | Map/notification routing |
| `WayTask/LocationManager.swift` | Location and geofence registration from compatibility items | Accept bounded revisioned reminder projection from Shopping/Session owner; never query/decide Product State; reconcile registrations by projection identity | WT-031B; P5 | geofence parity/staleness |
| `GeofenceNotificationService.swift` | Encodes Product names/IDs in region identifier and schedules notifications | Use compact opaque projection/session identity and revision; validate against persistence before scheduling; no frozen payload authority | WT-031B; P5 | payload privacy, stale event, cooldown |
| `MapBottomSheet.swift` | Store/likely-Product presentation | Retain read-only estimated-language ownership; consume snapshots from owning projection | P4 | label/a11y regressions |
| `WayTask/LocationDetailView.swift` | Direct location item create/toggle/delete | Replace with approved Product/list commands or explicitly separate location notes; no lifecycle toggles | Saved-location decision; P4 | location isolation/migration |

### 8.8 Scanner and Product creation

| File/component | Current responsibility | Planned responsibility/change | Dependencies / phase | Tests affected |
| --- | --- | --- | --- | --- |
| `CameraView.swift` | Confirms candidate and saves Product | Issue acquisition command with explicit `libraryOnly` or `libraryAndList(listID)` destination; handle tombstone match with Restore confirmation; invalidate only affected list/plan | Scanner/restore policy; P4 | camera/barcode integration |
| `CameraViewModel.swift` | Recognition and success copy | Retain; expose exact destination/action result for English/Hebrew/VoiceOver | P4 | state/copy/accessibility |
| `WayTask/Persistence/AddProductSaveCoordinator.swift` | Catalog/manual persistence boundary | Return active-existing/tombstoned/restored/created typed outcomes; never silently add to Shopping | P3–P4 | save outcome tests |
| `ProductCandidate.swift`, `BarcodeResult.swift` | Transient evidence | Retain stable evidence; no Product State field added | P4 | recognition regressions |

### 8.9 History

| File/component | Current responsibility | Planned responsibility/change | Dependencies / phase | Tests affected |
| --- | --- | --- | --- | --- |
| `ProductHistory.swift` | Aggregate record | Preserve migrated aggregates; support approved event identity/relationship or a separately proposed event component | Outcome taxonomy; P2–P5 | migration and event semantics |
| `ShoppingMemoryService.swift` | Add-to-list frequency | Consume committed domain events; derive recency/frequency without inferring purchase | P3–P5 | history/personalization |
| Product Catalog personalization files | Use Product History for ranking | Retain deterministic behavior; prefer stable catalog/Product IDs; treat legacy name fallback as legacy only | P5–P6 | personalization regressions |

### 8.10 Tests and fixtures

| File/component | Planned change | Phase |
| --- | --- | --- |
| Existing Persistence tests listed in Section 3.9 | Preserve current assertions, add next-schema and semantic migration expectations | P1–P2, P6 |
| Existing Product Catalog/Product Knowledge suites | Add Product State non-interference and explicit restore expectations; do not weaken catalog contracts | P3–P6 |
| Existing Shopping/Map presentation tests | Convert fixtures from `ShoppingItem.isCompleted` to target projections; retain label/layout assertions | P4–P6 |
| **Proposed:** `WayTaskTests/ProductState/ProductStateTransitionTests.swift` | Every allowed/forbidden Product/list transition and named-command enforcement | P1, P3 |
| **Proposed:** `WayTaskTests/ProductState/ListIsolationTests.swift` | Same Product in multiple lists; no cross-list field/projection drift | P3 |
| **Proposed:** `WayTaskTests/ProductState/ProductStateProjectionParityTests.swift` | Shopping/plan/Map/notification ID equality and explicit exclusions | P3–P5 |
| **Proposed:** `WayTaskTests/Persistence/ProductStateSemanticMigrationTests.swift` | Contradictions, duplicates, orphans, tombstones, interruption, idempotency, rollback | P1–P2, P6 |
| **Proposed:** `WayTaskTests/ShoppingSession/SessionOutcomeReconciliationTests.swift` | Session isolation, every line outcome, atomic Finish, failure rollback | P5 |
| **Proposed:** `WayTaskTests/Notifications/ProductStateNotificationIntegrationTests.swift` | Revisioned payload, stale suppression, exact deep link | P5 |
| **Proposed:** `WayTaskTests/Scanner/ProductStateScannerIntegrationTests.swift` | Library-only, list destination, existing Product, tombstone/restore, stale payload | P4 |
| **Proposed:** `WayTaskUITests/ProductStateAccessibilityTests.swift` | English/Hebrew, RTL, VoiceOver semantics, Dynamic Type, target size, non-color state | P4–P6 |
| **Proposed:** shared platform-neutral transition fixtures | Future iOS/Android parity contract | P3, P6 |

### 8.11 Documentation

| File/component | Planned responsibility |
| --- | --- |
| `docs/ImplementationPlans/1.0.3/WT-031A_ProductStateImplementationPlan.md` | This planning artifact only. |
| Future approved WT-031A implementation specification | Must resolve blockers, freeze exact schema/API/file decisions, and authorize work. |
| Existing WT-030 documents | Remain unchanged and authoritative. |
| Product Specification | Must be reconciled/published for Version 1.0.3 before release. |
| Changelog, architecture, migration, accessibility, localization documentation | Updated only by later authorized implementation work after behavior is final. |

No general `ProductRepository` abstraction is planned solely for architectural purity. Existing SwiftData/service boundaries should be retained unless the implementation specification demonstrates that atomic commands or future storage backends require a narrower repository.

---

## 9. Implementation Phases

These phases describe later authorized work. None is authorized by this document.

### Phase 0 — Decision and specification gate

- **Objective:** Resolve every policy that changes data interpretation or user-visible outcomes.
- **Included:** Section 17 blocking decisions; exact target semantics; schema/migration/rollback design; WT-031B integration contract; Version 1.0.3 Product Specification reconciliation.
- **Prerequisites:** WT-030A and WT-030 Architecture Summary.
- **Migration impact:** None.
- **Validation:** Architecture review proves no decision changes WT-030A ownership.
- **Exit criteria:** All “blocking before implementation” and “blocking before migration” questions have approved answers in an implementation specification.
- **Rollback boundary:** Documentation only.

### Phase 1 — Characterization and safety baseline

- **Objective:** Make current data behavior, defects, and non-regression requirements executable.
- **Included:** file-backed V1/V2/V3 fixtures; contradictory-state fixtures; multi-list/session/history/catalog/location cases; current projection/performance measurements; static/direct-writer checks.
- **Prerequisites:** Phase 0 test semantics.
- **Migration impact:** None.
- **Validation:** Current build produces the expected characterized results, including known contradictions.
- **Exit criteria:** Every current writer/reader is enumerated; baseline counts/checksums and p95 projection metrics are recorded.
- **Rollback boundary:** Tests/fixtures only; production behavior unchanged.

### Phase 2 — Persistence and semantic migration foundation

- **Objective:** Add the target durable concepts and a safe idempotent migration.
- **Included:** next versioned schema; semantic migration stage; exception ledger; pre/post validation; original-store recovery boundary; startup durable/degraded mode propagation.
- **Prerequisites:** Approved mapping, duplicate, orphan, history, session, and rollback policies.
- **Migration impact:** First schema/semantic conversion; no UI cutover.
- **Validation:** All file-backed fixtures migrate twice without drift; interruption at each stage resumes or fails safely.
- **Exit criteria:** IDs, snapshots, tombstones, entries, sessions, and history reconcile; no target exception is silently discarded.
- **Rollback boundary:** Before completion marker, reopen original store; after completion, forward-compatible recovery build only.

### Phase 3 — Target commands and projections

- **Objective:** Establish one internal Product State authority.
- **Included:** named Product/list commands; list revision; target read projections; explicit restore outcome; history event boundary; one-way compatibility adapter; direct-writer prohibition.
- **Prerequisites:** Phase 2 model and migration.
- **Migration impact:** Migrated stores can be operated by target commands in internal builds.
- **Validation:** full transition matrix, idempotency, list isolation, atomic save-failure rollback, projection parity.
- **Exit criteria:** All Product/list mutations can be expressed without a legacy write; adapter is target→legacy only.
- **Rollback boundary:** Feature-disabled forward-compatible build can keep target schema but not revert authority.

### Phase 4 — Product, Shopping, Home, Map, notification-input, location, and scanner conversion

- **Objective:** Remove every Product/list consumer’s dependence on global compatibility state.
- **Included:** Product cards/chooser; Shopping entries/plans; Home counts; Map inputs; reminder projection creation; scanner destinations; saved-location boundary; localization/accessibility.
- **Prerequisites:** Phase 3 commands/projections and approved UX terminology.
- **Migration impact:** None beyond target writes.
- **Validation:** IDs match across Shopping→plan→Map→notification input; no direct lifecycle writes; no `isCompleted` selection.
- **Exit criteria:** Every non-session Product State surface reads target projection and issues commands only.
- **Rollback boundary:** Internal only until Phase 7; do not release a partially converted surface set.

### Phase 5 — WT-031B session and Finish reconciliation integration

- **Objective:** Complete the Product State contract through the shopping journey.
- **Included:** immutable session line snapshots; active-session conflict result; collect/undo isolation; final outcome assignment; atomic session/list/history finish; notification/session deep links.
- **Prerequisites:** Approved WT-031B implementation specification and Phase 4 projections.
- **Migration impact:** Legacy session arrays migrate to normalized lines conservatively.
- **Validation:** session recovery, missing items, conflicts, every final outcome, atomic failure, list/history reconciliation.
- **Exit criteria:** A session can start, recover, and finish without reading or writing compatibility completion.
- **Rollback boundary:** Session schema requires forward-compatible rollback; unfinished conversion cannot ship.

### Phase 6 — Migration, recovery, performance, accessibility, and localization qualification

- **Objective:** Prove release safety under realistic data and device conditions.
- **Included:** corrupted/interrupted stores; quarantine/degraded-mode behavior; production-scale fixtures; oldest-device measurements; Hebrew/English/RTL/Dynamic Type/VoiceOver; notification payload compatibility.
- **Prerequisites:** Phases 2–5 complete.
- **Migration impact:** Final migration implementation exercised against release-candidate binaries.
- **Validation:** Section 12 matrix and WT-030A AC-01…AC-47.
- **Exit criteria:** zero critical/high defects; performance gate met; rollback/recovery drill passed; Product and QA sign-off.
- **Rollback boundary:** Forward-fix build and approved original-store recovery procedure validated.

### Phase 7 — Single authority cutover and compatibility retirement

- **Objective:** Release the Orthogonal Product Lifecycle as one coherent authority.
- **Included:** enable target readers/writers together; disable all legacy lifecycle reads/writes; monitor privacy-safe exception counts; retain physical compatibility fields read-only for support window.
- **Prerequisites:** Phase 6 and implementation-release approval.
- **Migration impact:** User stores migrate before writable UI.
- **Validation:** release smoke matrix; no legacy-authority call-site; migration and projection telemetry within approved bounds.
- **Exit criteria:** every surface agrees on Product/list/session context; no mixed authority; support documentation available.
- **Rollback boundary:** forward-compatible disable/fix only. Physical compatibility removal is a later schema release after the approved window.

---

## 10. UI and UX Transition Plan

### 10.1 Product Library cards

- Remove empty/filled completion circles from Product cards.
- Present Product identity and catalog/category icon independently from lifecycle state.
- If list context is shown, name the list or provide an unambiguous scoped label/action.
- Use actions such as “Add to Weekly Shopping” / “Remove from Weekly Shopping” only after approved localization.
- Library removal is visually and verbally distinct from remove-from-list.
- Show tombstone restoration only in an approved removed-Product discovery surface or acquisition conflict.

### 10.2 Shopping entry state

- Display needed/resolved text and approved reason, not an unexplained checkmark.
- The control’s accessibility label includes Product name, list name, current state, and available action.
- Quantity/order changes are named list commands and advance list revision.
- Reopen exposes the approved rule and does not silently erase prior history.

### 10.3 Removing from Shopping

- Always target one named list.
- Remove membership without removing the Product from Library.
- If a session snapshot already contains the entry, apply WT-031B’s approved in-session policy; do not mutate the snapshot implicitly.
- Confirm only where the approved policy or destructive impact requires it; do not add friction solely for architecture.

### 10.4 Visual indicator vocabulary

| Meaning | Required presentation rule |
| --- | --- |
| Product identity/category | Semantic icon or photo plus text; never lifecycle authority. |
| In named list | Scoped text/action; not a completion circle. |
| Needed/resolved | Text and accessibility state; icon/color may reinforce only. |
| Pending chooser selection | Distinct from already-in-list; reversible before commit. |
| Session collected | Session-scoped label/control; does not say purchased. |
| Removed from Library | Explicit removed/tombstone language and Restore action. |
| Plan stale | Plan/list-revision message; not Product completion. |
| Catalog inactive/replaced | Catalog availability/update message; no lifecycle mutation. |

### 10.5 Restoration behavior

- Restore is an explicit user action.
- Restore preserves the same Product UUID, user fields, catalog snapshots, history, and knowledge.
- Restore does not recreate prior active-list memberships.
- Catalog add, barcode recognition, AI recognition, startup repair, and sync return a restore-required result rather than restoring automatically.
- Exact “Restore” versus “Add/Restore” wording remains a blocking Product decision.

### 10.6 Finished Shopping reconciliation

- Finish cannot complete while a session line lacks an approved outcome.
- The UI explains remaining-line choices without equating them with failure or purchase.
- One commit updates session final state, applicable list entries, and history.
- A failed commit leaves the session open and shows that no finish was saved.
- The success UI is derived from the committed result, not optimistic local state.

### 10.7 Empty, exception, and error states

- Empty Product Library: Product creation action; no Shopping-completion language.
- Empty named list: name the list and offer Product selection.
- Plan exclusion: identify unresolved entries rather than silently omitting them.
- Migration exception: preserve data and provide recovery/support path; never fabricate a Product.
- Save failure: keep state/draft and allow retry.
- In-memory/degraded mode: clearly state that changes will not survive exit before accepting durability-sensitive actions.
- Stale notification: open the owning current context if valid or explain that it changed; never reconstruct from frozen names alone.

### 10.8 Accessibility, localization, RTL, and Dynamic Type

Before release:

- all Product State strings exist in English and Hebrew localization resources;
- approved Hebrew terms cover Library, Shopping, Needed, Resolved, Remaining, Collected, Removed, Restore, Unavailable, Skipped, Carry Forward, and Finish;
- no raw enum value or hardcoded English fallback appears in production lifecycle UI;
- bidirectional Product names remain readable in RTL containers;
- Dynamic Type through accessibility sizes preserves the only state/scope label;
- every lifecycle target is at least 44×44 points;
- VoiceOver announces object, scope, state, and result;
- Switch Control and hardware-keyboard focus order are verified;
- state is not conveyed by icon, checkmark, or color alone;
- Reduce Motion does not hide state confirmation.

---

## 11. Map, Notification, and Scanner Integration

### 11.1 Integration authority flow

```text
Named Product/List Command
        -> committed Product/List state + list revision
        -> scoped projection
        -> Plan / Session snapshot
        -> Map and reminder projection
        -> notification payload identity
```

No arrow returns authority from Map, a payload, or scanner presentation into Product State without a named command and current-state validation.

### 11.2 Map Product context

- Default shopping Map context must be an explicit list projection, ready plan, or active session snapshot.
- Map receives Product/entry/session IDs and display snapshots appropriate to that source.
- Planner exclusions remain disclosed.
- Map cannot fall back to all global incomplete compatibility items.
- Store likelihood remains estimated and read-only; it does not resolve an entry.
- Saved-location actions either call the same domain commands or remain a clearly separate note feature after an approved policy.

### 11.3 Notification payload compatibility

Target payloads should identify:

- payload format version;
- owning list/plan/session ID;
- owning revision/snapshot version;
- compact store/reminder identity;
- deep-link target.

Product names and lifecycle state in a frozen region identifier are not authoritative. During a defined compatibility window:

- old payloads are parsed defensively;
- their legacy IDs are resolved only through stable migration mappings;
- current target state is validated before display/routing;
- stale/unresolvable payloads are suppressed or open a safe generic destination;
- no old payload can restore a Product, reopen an entry, or fabricate a session.

Exact compact payload and background behavior belong to WT-031B.

### 11.4 Scanner-created Products

- Scanner candidates enter the same Product acquisition command as manual/catalog search.
- Default destination remains Library-only unless the caller explicitly supplied a named list destination.
- A catalog/custom Product keeps stable Product identity and saved snapshots.
- Existing active Product returns an already-present outcome.
- Tombstone match requires explicit Restore.
- After restore, adding to a list is a separate explicit destination/command.
- Success/error/VoiceOver copy states exactly what was saved and where.
- Library-only scanning does not increment a list revision or stale an unrelated plan.

### 11.5 Stale and legacy payload behavior

- Unknown payload format: ignore lifecycle action and route safely.
- Missing owning list/session: show context-unavailable state; do not use global items.
- Revision mismatch: recompute or suppress according to WT-031B; do not present old Product set as current.
- Removed Product in an old payload: preserve tombstone; no implicit restore.
- Catalog replacement: resolve display/reference through catalog rules without changing Product/list/session state.

---

## 12. Testing Strategy

### 12.1 Test layers

| Layer | Required coverage | WT-030A criteria |
| --- | --- | --- |
| Domain unit/command | Library remove/restore; add/reopen/resolve/remove entry; duplicate prevention; forbidden cross-owner transitions; save failure | AC-01…AC-17, AC-45, AC-47 |
| State-transition matrix | Every Section 15 WT-030A allowed/forbidden transition, including idempotent retry and stale revision | AC-03…AC-05, AC-12…AC-13, AC-45 |
| Migration | V1/V2/V3; contradictions; duplicates; orphans; tombstones; sessions; history; interruption; repeat run | AC-09…AC-11, AC-39…AC-41, AC-46 |
| Persistence/recovery | cold/warm launch, failed save, corrupted rows/store, original-store recovery, in-memory warning | AC-27…AC-28, AC-39…AC-41 |
| List isolation | same Product active/resolved/removed in multiple lists; list-revision independence | AC-02…AC-03, AC-08, AC-13 |
| Plan | source list/revision/entry IDs, unrelated library edit, staleness before use, exclusions | AC-18…AC-21 |
| Session | immutable snapshot, conflict decision, collect/undo isolation, all outcomes, atomic Finish, recovery | AC-24…AC-30 |
| History | no purchased inference, event identity, legacy aggregate preservation, finish outcomes | AC-27, AC-30, AC-47 |
| Catalog | inactive/missing/replaced, snapshot stability, exact-ID dedupe, explicit restore | AC-09…AC-11, AC-31…AC-32 |
| Map/notification | ID parity, revision match, old/new payload, stale suppression, exact deep link | AC-21…AC-23 |
| Scanner | custom/catalog/existing/tombstone; Library-only/list destination; retry and copy | AC-10, AC-32…AC-34 |
| Localization/accessibility | English/Hebrew, RTL, bidirectional names, Dynamic Type, VoiceOver, target size, non-color state | AC-06…AC-07, AC-14…AC-17, AC-33, AC-35…AC-38 |
| Performance | scoped queries and projection baselines on production-scale fixtures/oldest device | AC-42…AC-43 |
| Cross-platform fixtures | platform-neutral commands/outcomes and vocabulary | AC-44…AC-47 |

### 12.2 Required domain transition cases

- Create custom Product; create catalog Product; exact catalog re-add.
- Attempt acquisition of a tombstone; cancel restore; restore; retry failed restore.
- Add one Product to lists A and B; resolve/remove/reopen in A; prove B unchanged.
- Add same Product twice to one list concurrently/serially; produce one membership.
- Remove Product from named list; Product remains active.
- Remove Product from Library with zero, one, and multiple active memberships and an active session.
- Catalog inactive/missing/replaced while Product is active, removed, in lists, and in a session.
- Edit Product display fields while plans/sessions hold snapshots.
- Mutate quantity/order/resolution and prove revision/plan staleness is atomic.
- Reject every direct or context-free global completion transition.

### 12.3 Session isolation and Finish cases

- Starting with conflicting active session returns explicit decision; it never silently resumes an unrelated session.
- Collect/undo changes only that session line.
- Source-list mutation after start follows approved snapshot policy.
- Finish with collected and remaining lines requires outcomes for all.
- Finish save failure leaves session/list/history unchanged.
- Successful Finish commits session/list/history together.
- Relaunch recovers the exact line set, store, list/revision, and outcomes.
- Missing Product/entry/catalog data renders the snapshot and records an exception rather than dropping the line.

### 12.4 Migration and rollback cases

- All combinations of `isChecked` and `isCompleted`.
- Duplicates with conflicting quantity, order, timestamps, and checked values.
- Tombstone with active compatibility item or active entry.
- Active Product with completed/recent-only entries.
- Orphan entry with stored Product UUID.
- Legacy session line referencing no current compatibility item.
- Failure before/after each migration stage and completion marker.
- Repeated migration and repair.
- Forward-compatible feature-disabled build opening a migrated store.
- Original-store recovery drill with post-migration changes explicitly accounted for.

### 12.5 UI regression and accessibility

Automated and manual tests must prove:

- no completion-style Product card circle;
- named list scope in actions;
- already-in-list and pending chooser states are distinct;
- Clear All scope is accurate;
- resolved reason remains available at large text sizes;
- Product/list/session meanings are announced correctly in both languages;
- RTL ordering and mixed Hebrew/English Product names remain understandable;
- no state depends on color;
- empty/error/degraded states are truthful.

### 12.6 Static enforcement

The implementation specification should define build/test checks that fail when production code:

- writes `isCompleted` or `isChecked` outside migration/compatibility code;
- filters Product State by `ShoppingItem.isCompleted`;
- mutates target lifecycle fields from a `View`;
- creates a `ShoppingListEntry` outside the approved command boundary;
- calls `restoreToLibrary` outside the explicit restore command/migration test;
- creates notification Product context without an owning projection revision.

### 12.7 Acceptance traceability

Each WT-030A AC-01…AC-47 must map to at least one automated test or a named manual/device test with owner and evidence artifact. No criterion may be closed solely by code review. AC-43 requires a recorded pre-cutover baseline before optimization; AC-44 requires a shared fixture contract even if Android execution is deferred.

---

## 13. Performance and Reliability

### 13.1 Migration cost

- Measure record counts and stage duration separately for Products, entries, compatibility items, sessions, history, locations, and exceptions.
- Avoid loading image blobs when identity/state migration does not need them.
- Use bounded fetch/save batches only if measured production-scale fixtures require them.
- Do not trade recoverability for launch speed.
- Migration runs before writable UI and reports progress only through an approved startup experience.

### 13.2 Launch-time impact

- Schema migration, semantic migration, and graph validation must be distinguished in diagnostics.
- Normal post-migration launches must not rerun full compatibility backfill.
- List/session recovery should query scoped active data, not scan the full Product library.
- Catalog loading remains independent and must not block restoration of user-owned snapshots.

### 13.3 SwiftData query impact

The implementation specification must validate support for efficient lookup by:

- `(listID, productID)` membership;
- `(listID, resolutionState, sortOrder)` needed/resolved projection;
- active/removed Product lifecycle;
- active session state/time;
- source list/revision for plan and reminder projection.

The exact SwiftData index/uniqueness design remains a technical decision. Correctness must still be enforced transactionally if platform constraints prevent a database constraint.

### 13.4 Memory impact

- Do not materialize every Product and compatibility item to render one list.
- Keep Product image data out of state-only projections unless the visible row needs it.
- Session snapshots are bounded by session lines and retain only approved display data.
- Map/notification projections contain the minimum scoped Product context.

### 13.5 Large libraries and multiple lists

Performance fixtures must include:

- large Product Library with few active-list entries;
- many named lists containing overlapping Products;
- long active list;
- long history;
- catalog-linked and custom Products;
- tombstones and migration exceptions.

The exact maximum supported sizes are unresolved. AC-43 uses the approved production-scale fixture and oldest supported device, with no more than 10% p95 projection regression from the recorded pre-cutover baseline.

### 13.6 Interrupted migration and idempotency

- Every stage is restartable or leaves the original store untouched.
- Commands are idempotent by stable IDs and expected revision.
- Retry after save failure cannot create duplicate entries/events.
- Completion markers are committed only after invariants pass.
- Startup repair after migration cannot oscillate timestamps or catalog snapshots.

### 13.7 Diagnostics

Required privacy-safe signals:

- schema/semantic migration stage and duration;
- counts before/after by record type;
- duplicates/orphans/contradictions by category;
- tombstone reactivation attempts blocked;
- legacy adapter reads/writes remaining;
- projection revision mismatches;
- failed command type and durability mode;
- stale notification/geofence suppressions.

Do not log Product names, barcodes, user list titles/content, photos, raw queries, or precise locations.

### 13.8 No speculative optimization

Use existing SwiftData/service boundaries first. Add batching, caching, new repositories, denormalized projections, or physical constraints only when required by an invariant or measured baseline. Architectural purity alone is not a reason to broaden the implementation.

---

## 14. Risks and Mitigations

| Risk | Impact | Mitigation / release gate |
| --- | --- | --- |
| Data loss | Products, entries, history, or sessions disappear | File-backed fixtures, pre/post counts, recoverable original store, exception preservation, failure-before-UI. |
| Incorrect legacy-state interpretation | False purchase/resolution claims | Approved deterministic conservative rule, contradiction fixtures, `legacyUnknown` only if approved, audit counts. |
| Mixed authority | Cross-screen disagreement persists | One release cutover, target-only reads after migrated marker, static direct-writer/legacy-filter checks. |
| Duplicate list entries | Ambiguous membership and outcomes | Transactional idempotent command, approved merge policy, invariant diagnostics, concurrent retry tests. |
| Product identity loss | Broken list/history/catalog references | Preserve UUIDs; never name-match; explicit orphan exceptions; exact-ID tests. |
| Catalog snapshot drift | User-visible names/icons change unexpectedly | Preserve selection snapshots; catalog repair cannot refresh lifecycle/snapshot without approved explicit policy. |
| Tombstone resurrection | Removed Product silently reappears | Explicit restore command only; catalog/recognition/startup tests; blocked restore diagnostics. |
| UI inconsistency | Checkmark/list/session meanings remain ambiguous | Shared projection/vocabulary; one consumer cutover; English/Hebrew accessibility matrix. |
| Notification incompatibility | Stale payload opens wrong list/Product set | Version/revision identity, persisted validation, safe legacy handling, exact deep-link tests. |
| Migration rollback failure | Older binary cannot open/write store | Forward-compatible rollback build; no old-schema assumption; recovery drill. |
| Startup recovery implies durability | User trusts changes made in memory | Expose persistence mode, user warning, restrict reminder/durable claims. |
| Session/list race | Finish or list edit loses an outcome | Immutable session snapshot, expected revisions, atomic Finish transaction, WT-031B conflict policy. |
| Product History overclaims purchase | AI/personalization learns false truth | Named events only; preserve legacy aggregate as unverified; no flag reconstruction. |
| Saved-location parallel state remains | Location screen bypasses commands | Decide Product-vs-note policy before implementation; migrate or explicitly isolate. |
| Incomplete test coverage | Regression appears only after migration | AC-01…AC-47 traceability, proposed missing suites, static enforcement, release-device matrix. |
| Performance regression | Slow launch/list rendering on existing devices | Baseline before work, scoped queries, image-free projections, AC-43 gate. |
| WT-031A/WT-031B contract drift | Two competing session-line models | One shared contract and co-reviewed implementation specifications; Product State release depends on WT-031B. |
| Missing Version 1.0.3 Product Specification | Plan conflicts with unpublished product policy | Reconcile/publish before release; WT-030 remains architecture authority meanwhile. |

---

## 15. Dependencies

### 15.1 Binding architecture dependencies

- `docs/Audits/1.0.3/WT-030A_ProductStateUXAudit.md`
  - official Orthogonal Product Lifecycle, transitions, UX rules, migration constraints, and AC-01…AC-47.
- `docs/Audits/1.0.3/WT-030_ArchitectureSummary.md`
  - cross-audit principles, authority boundaries, implementation order, and gate.
- WT-030B
  - durable/recoverable Shopping Session, immutable snapshots, line outcomes, notification/geofence authority.
- WT-030C
  - evidence-before-truth boundary; no Community report writes Product/catalog/store truth automatically.

### 15.2 Product/document dependencies

- Available Product Specification: `design/v1.0/WayTask_Product_Specification_v1.0.pdf`.
- Missing dependency: official Version 1.0.3 Product Specification.
- `docs/22_ROADMAP.md`.
- `docs/Specifications/ShoppingFlow_v1.md`.
- `docs/Specifications/SmartProductCreation.md`.
- `docs/Specifications/CanonicalProductCatalogSpecification.md`.
- `docs/Specifications/ProductSearchUXContract.md`.
- `docs/Architecture/CatalogAwarePersistenceArchitecture.md`.
- `docs/Architecture/ProductKnowledgeArchitecture.md`.
- `docs/Architecture/ProductKnowledgeMigrationStrategy.md`.
- `docs/Architecture/ProductEntityDataModel.md`.
- `docs/20_ARCHITECTURE.md`.
- `docs/15_ENGINEERING_BLUEPRINT.md`.
- `docs/60_CHANGELOG.md`, `CHANGELOG.md`, and `BETA_BACKLOG.md`.

Older documents that describe compatibility `ShoppingItem` or incremental dual-write migration are historical evidence, not authority where they conflict with WT-030A’s no-mixed-authority release rule.

### 15.3 Technical dependencies

- SwiftData’s supported versioned schema, custom migration, indexing, relationship, uniqueness, and rollback behavior on the minimum iOS version.
- Ability to preserve an original store and sidecars across semantic migration failure.
- Current stable Catalog Product ID, redirect, and snapshot contracts.
- Existing migration/deletion/catalog/backfill tests and file fixtures.
- A future approved WT-031A implementation specification with exact schema/API decisions.
- A compatible WT-031B implementation specification before Product State release.
- English/Hebrew Product terminology approval.
- Oldest-supported-device and production-scale performance fixtures.

### 15.4 Correct current components to retain

No architectural change is recommended for:

- stable user `Product.id`;
- durable `Product.deletedAt` tombstone concept;
- stable catalog Product ID plus user-owned snapshots;
- exact catalog-ID deduplication;
- custom Product remaining unlinked;
- catalog lifecycle remaining read-only/independent;
- Product Knowledge catalog and learned recognition cache remaining separate;
- scanner/camera recognition state remaining outside persistence;
- estimated Map/store presentation remaining read-only;
- Product Library creation remaining Library-only by default.

Changes are planned around these components only where current code violates explicit restore, scoped state, or command ownership.

---

## 16. Deferred Work

The following work is intentionally excluded, without deferring any required WT-030A Product State cutover:

- WT-031B background execution, battery/thermal, geofence ledger, session expiration, and full offline recovery implementation.
- WT-031C Community Feedback client, Cloud service, trust, moderation, privacy, and anti-abuse implementation.
- Cloud sync, multi-device conflicts, account model, and server schema.
- Android implementation; only shared transition fixtures/contracts are included now.
- AI implementation and autonomous workflow policy beyond command/confirmation boundaries.
- Future retail SKU/barcode/package identity layer.
- Live retailer inventory, price, route optimization, and purchase verification.
- Catalog content expansion, community publication tooling, and general icon-quality redesign.
- Archive state unless Product approves it as a distinct lifecycle.
- Physical removal of compatibility storage until the approved support window and separate schema gate.
- Product privacy-erasure implementation pending policy/legal approval.

---

## 17. Open Questions

No answer is invented below. Classification indicates the latest point by which an approved answer is required.

### 17.1 Blocking before implementation

| ID | Unresolved decision |
| --- | --- |
| BI-01 | What does resolving a list need mean before a session, and which reason taxonomy is approved? |
| BI-02 | Does “Collected” mean placed in basket only, and what user action—if any—confirms purchase? |
| BI-03 | Which outcomes are mandatory for remaining lines at Finish: carry forward, unavailable, skipped, keep needed, or another set? |
| BI-04 | How does an abandoned session differ from a finished session, and how is progress retained? |
| BI-05 | When removing a Product from Library, are active list memberships removed, confirmed individually, or a blocker? |
| BI-06 | Are Completed and Recent editable lists, verified system projections, legacy archives, or removed labels? |
| BI-07 | Can multiple Weekly/active lists exist, and can more than one be active? |
| BI-08 | Are resolved entries retained, hidden, moved, or projected elsewhere? |
| BI-09 | Does reopening preserve a prior resolution event, and what is the idempotent reopen rule? |
| BI-10 | Does restore add the Product to no list, as WT-030A recommends, and what exact confirmation is required? |
| BI-11 | What choices/warnings appear when an active session conflicts with a new start? |
| BI-12 | Can a source list be edited during an active session, and how does that affect immutable lines? |
| BI-13 | Can a supported session cover multiple lists or stores, or is Version 1.0.3 single-list/single-store? |
| BI-14 | What screen does a shopping notification open: owning list, plan, Map, or active session? |
| BI-15 | What screen does a Home list card open? |
| BI-16 | After scan save, is the default continuation Done, Scan Another, Add to named list, or a choice? |
| BI-17 | Is a removed catalog Product action labeled Restore, Add, or both? |
| BI-18 | May barcode recognition ever restore automatically? WT-030A requires explicit restoration; Product must approve the exact interaction. |
| BI-19 | Does list resolution retain a checkmark plus text, or use a different control? Product Library checkmarks are already prohibited. |
| BI-20 | What approved English/Hebrew terms map to every lifecycle state and outcome? |
| BI-21 | Are saved-location `ShoppingItem` records Products/list needs or a separate store-note concept? |
| BI-22 | What is the exact atomic boundary and owner shared by WT-031A list/history reconciliation and WT-031B session finalization? |
| BI-23 | Does SwiftData support the chosen uniqueness/revision design on every supported iOS version, or must service-level serialization remain the invariant? |

### 17.2 Blocking before migration

| ID | Unresolved decision |
| --- | --- |
| BM-01 | What deterministic rule maps each `isChecked`/`isCompleted` combination: needed, resolved `legacyUnknown`, or explicit exception? |
| BM-02 | What deterministic merge policy resolves duplicate `(listID, productID)` entries, including UUID, quantity, order, time, state, and session references? |
| BM-03 | How are orphan list entries with a stored Product UUID but missing relationship/Product preserved and presented? |
| BM-04 | How are compatibility items with no provable Product/list relationship classified? |
| BM-05 | How are existing active/finished session item and collected arrays mapped when zero, one, or multiple entries match? |
| BM-06 | How are multiple legacy active sessions resolved without silently discarding progress? |
| BM-07 | What happens to Completed/Recent records during migration once their product semantics are approved? |
| BM-08 | Which history mappings are provable enough to attach a Product UUID without name-based guessing? |
| BM-09 | What exact next schema version/stages, migration marker, exception ledger, and custom migration mechanism are supported? |
| BM-10 | How is the original store and all sidecars preserved, validated, and retried on semantic migration failure? |
| BM-11 | What forward-compatible rollback package is retained after migration, and what data-loss warning governs backup restoration? |
| BM-12 | Which active-list/session references to a tombstoned Product remain historical versus require an exception under the approved removal policy? |

### 17.3 Blocking before release

| ID | Unresolved decision |
| --- | --- |
| BR-01 | Is a Recently Removed surface required, and what are undo and tombstone-retention periods? |
| BR-02 | What is the Product privacy-erasure policy when history/session references exist? |
| BR-03 | What exact persistent-store recovery and in-memory-fallback message/action is approved? |
| BR-04 | Must plans persist before session start, or is deterministic regeneration sufficient? |
| BR-05 | What maximum Product/list/session sizes define the production-scale performance fixture? |
| BR-06 | What minimum catalog icon-specificity/quality threshold is required for the generic fallback? |
| BR-07 | What compatibility window and safe behavior apply to old notification/geofence payloads? |
| BR-08 | What current/target plan behavior applies when a Product’s user-owned display attributes change but entry identity does not? |
| BR-09 | What user-facing migration/recovery state appears if preserved exceptions cannot be rendered normally? |
| BR-10 | Where is the official Version 1.0.3 Product Specification, and does it introduce Product policy not present in the available v1.0 specification? |
| BR-11 | What localization owner approves lifecycle terminology and grammar in both English and Hebrew? |
| BR-12 | What analytics events are permitted for named outcomes, and what privacy-safe migration diagnostics may ship? |

### 17.4 Non-blocking follow-up

| ID | Unresolved decision |
| --- | --- |
| NF-01 | Is Archive a distinct future user need, and how would it differ from Removed? |
| NF-02 | What authority may future AI have for bulk list commands or session outcome suggestions? |
| NF-03 | Which confirmed outcomes may train replenishment recommendations? |
| NF-04 | What support window is required before compatibility `ShoppingItem` storage is physically removed? This does not delay removal of its authority. |
| NF-05 | When Cloud/Android work begins, what synchronization conflict policy and shared event serialization are approved? |
| NF-06 | Should a future explicit catalog snapshot-refresh/linking UI be provided? |

---

## 18. Implementation Readiness Checklist

This checklist must pass before any production code implementation begins under a later approved specification.

### Architecture compliance

- [x] WT-030A Orthogonal Product Lifecycle is identified as binding.
- [x] Product, list, plan, session, history, catalog, Map, notification, scanner, and Community boundaries are explicit.
- [x] No new Product State architecture is introduced.
- [x] Existing correct Product UUID, tombstone, catalog snapshot, and catalog-search ownership is retained.
- [ ] Every Phase 0 Product policy decision is approved.
- [ ] WT-031A and WT-031B share one approved session-line/Finish contract.

### Migration decisions

- [x] All current persisted record types and compatibility links are inventoried.
- [x] Stable IDs, snapshots, tombstones, history, and unresolved rows are preservation requirements.
- [x] No purchase or catalog identity may be inferred from legacy booleans/text.
- [ ] Ambiguous-state, duplicate, orphan, legacy-session, and Completed/Recent mappings are approved.
- [ ] Exact SwiftData schema/custom migration behavior is proven on supported iOS versions.
- [ ] Original-store recovery and forward-compatible rollback are approved.

### Authority cutover

- [x] One final public authority cutover is required.
- [x] Transitional reads/writes and one-way adapter rules are defined.
- [x] No legacy runtime fallback is permitted after migrated-store cutover.
- [ ] Static enforcement rules and adapter-retirement gate are frozen in the implementation specification.

### File inventory and ownership

- [x] Current files, types, services, views, persistence paths, and tests are verified.
- [x] Planned existing-file responsibility changes are mapped.
- [x] Proposed new components are clearly labeled.
- [ ] Exact new filenames/targets and project membership are approved only where a new component is justified.

### Test and rollout plan

- [x] AC-01…AC-47 test categories are mapped.
- [x] Migration, list/session isolation, history, catalog, Map, notification, scanner, localization, accessibility, performance, corruption, and rollback coverage is defined.
- [ ] Characterization fixtures and performance baselines exist.
- [ ] Every AC has an owned automated or manual evidence artifact.
- [ ] Single-release cutover and forward-fix drill are approved.

### Localization and accessibility

- [x] English/Hebrew, RTL, Dynamic Type, VoiceOver, target-size, and non-color requirements are included.
- [ ] Approved lifecycle/outcome terminology exists in both languages.
- [ ] Product/Design/Accessibility review accepts the Product card, chooser, list, session, error, and restoration semantics.

### Dependency resolution

- [x] WT-030A, WT-030B, WT-030C, Architecture Summary, catalog, persistence, and test dependencies are identified.
- [ ] Official Version 1.0.3 Product Specification is located/published and reconciled.
- [ ] WT-031B implementation specification is compatible and scheduled before the release cutover.
- [ ] SwiftData, minimum-iOS, diagnostics/privacy, and degraded-mode policies are confirmed.

---

## 19. Terminal Decision

**READY FOR IMPLEMENTATION SPECIFICATION**

WT-031A is complete as a file-level, migration-aware planning bridge from the approved WT-030A architecture. It does not authorize production code changes. A later implementation specification must resolve every blocking item in Section 17, complete every unchecked pre-code gate in Section 18, and preserve the single-release no-mixed-authority cutover before implementation can be authorized.

## Implementation Milestones

## Appendix A — Implementation Milestones

Phase 0
↓

WT-031A Specification Approved

↓

Phase 1
Characterization Complete

↓

Phase 2
Migration Ready

↓

Phase 3
Domain Authority Ready

↓

Phase 4
UI Conversion Ready

↓

Phase 5
Session Integration Ready

↓

Phase 6
Qualification Complete

↓

Phase 7
Single Authority Cutover

↓

WT-031A Complete
