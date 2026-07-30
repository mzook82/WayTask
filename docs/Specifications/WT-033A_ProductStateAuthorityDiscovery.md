# WT-033A — Product State Authority Discovery

**Step:** S-00  
**Status:** Architectural discovery complete; implementation not authorized  
**Repository branch:** `main`  
**Repository commit:** `a20b83c570157038cb85b0b3efb49a24cf8ccc50`  
**Discovery date:** 2026-07-30  
**Change boundary:** This document only

## Discovery Basis

This is a read-only discovery of the current shipped implementation. It does not redefine Product State, approve a current defect, design a schema, or authorize Phase 2 code.

The architectural authority reviewed for this discovery is:

1. `docs/Audits/1.0.3/WT-030_ArchitectureSummary.md`
2. `docs/Audits/1.0.3/WT-030A_ProductStateUXAudit.md`
3. `docs/ImplementationPlans/1.0.3/WT-031A_ProductStateImplementationPlan.md`
4. `docs/ImplementationSpecifications/1.0.3/WT-032A_ProductState_Phase0DecisionSpecification.md`
5. `docs/ImplementationSpecifications/1.0.3/WT-032B_ProductState_Phase1ImplementationSpecification.md`
6. `docs/ImplementationEvidence/1.0.3/WT-031A_Phase1_ProductStateBaseline.md` as verified Phase 1 evidence, not as an architectural decision source.

The source of truth for current behavior in this document is the production Swift source at the repository commit above. “Verified” means directly observed in source. “Architectural interpretation” means a conclusion drawn by comparing the verified source with WT-030 through WT-032. Target decisions are referenced by their stable WT-032A identifiers, D-01 through D-37, but are not represented as implemented.

The inventory boundary includes persisted models, shipped schemas, migration and startup recovery, direct SwiftData access, Product/list/session/history services, SwiftUI readers and writers, Product Catalog and Product Knowledge, scanner/camera acquisition, AI recognition, Shopping Plan and store classification, Map/location, geofencing/notifications, and diagnostic consumers.

Static inventory totals at this baseline:

| Inventory measure | Verified count |
|---|---:|
| Production Swift files returned by the broad Product State/type or `ModelContext` candidate scan | 44 |
| Production Swift files containing at least one of the five principal state fields | 24 |
| `ShoppingItem.isCompleted` lexical occurrences / files | 67 / 19 |
| `ShoppingListEntry.isChecked` lexical occurrences / files | 37 / 7 |
| `legacyShoppingItemID` lexical occurrences / files | 80 / 9 |
| `Product.deletedAt` lexical occurrences / files | 20 / 7 |
| `AppStateManager.shoppingListRevision` lexical occurrences / files | 4 / 2 |
| SwiftUI `@Environment(\.modelContext)` declarations | 9 |
| SwiftUI `@Query` declarations | 37 |
| Explicit `ModelContext` fetch call sites | 21 |
| Direct insert / delete / save primitive call sites | 16 / 8 / 26 |

The 26 save primitives comprise 25 explicit `modelContext.save()` calls and the catalog persistence service’s injected default `try $0.save()` boundary. Insert, delete, and save total 50 direct persistence primitive call sites. This is a lexical call-site count, not a transaction count; SwiftData autosave can also persist model mutations without an explicit `save()` at the mutation site.

The 44-file candidate scan was deliberately broad. Inspection excluded `WayTaskDesignSystem.swift`, whose only match is the presentation-only text “Product action,” from Product State authority. `WayTask/ProductKnowledge/Application/ProductKnowledgeError.swift` is retained only as an adjacent bundled-knowledge validation/error boundary; it does not read or write user Product State.

---

## 1. Executive Summary

WayTask does not currently have one Product State authority. It has a graph of partially scoped authorities connected by compatibility identifiers and interpreted differently by consumers.

The current durable foundations that align with the approved architecture are:

- `Product.id` is the stable user Product identity.
- `Product.deletedAt` is the durable active/removed Product Library lifecycle.
- `Product.catalogProductIDRawValue` and the saved catalog snapshot fields preserve the separation between user Product identity and Catalog identity.
- `ShoppingListEntry` existence is the current named-list membership record.
- `ShoppingSession` persists session-local item and collected identifier arrays.
- Catalog and Product Knowledge remain separate from user Product lifecycle.

The principal mixed-authority paths are:

- `ShoppingListEntry.isChecked` represents current entry-level checked state.
- `ShoppingItem.isCompleted` is a shared compatibility flag used as a global active/completed filter by Product, Home, Shopping, plan, trip, discovery, Map, location, notification, and session paths.
- `Product.legacyShoppingItemID` and `ShoppingListEntry.legacyShoppingItemID` connect Product/list records to that shared compatibility record.
- Product/list mutations are performed by services and by SwiftUI views directly.
- `ShoppingPlan` is an in-memory compatibility-item projection without a durable source-list revision or exact source-entry set.
- `ShoppingSession` stores compatibility-item UUID arrays and Finish changes only the session header.
- `ProductHistory` aggregates by barcode or normalized name and can infer completion recency from the compatibility flag.
- `GeoLocation.shoppingItems` creates a parallel writable location-owned compatibility lifecycle.
- startup repair remains an active runtime writer that creates default lists, creates or reconnects Products, repairs relationships, normalizes catalog snapshots, and removes tombstoned Weekly entries.

Current authority by lifecycle:

| Lifecycle | Current durable or runtime owner | Other current writers/readers | Architectural status |
|---|---|---|---|
| Product identity | `Product.id` | acquisition, catalog persistence, startup repair, Product UI | Stable current foundation |
| Product Library | `Product.deletedAt` | model helpers, deletion service, barcode/catalog acquisition | Correct field ownership; restore callers are mixed |
| Named-list membership | `ShoppingListEntry` existence | `ShoppingListService`, `ContentView`, startup repair | Scoped record exists; write ownership is distributed |
| Entry resolution | `ShoppingListEntry.isChecked` | service reopen and direct Shopping UI toggle | Current authority coexists with compatibility completion |
| Compatibility activity/completion | `ShoppingItem.isCompleted` | services, Shopping UI, Content reset, location UI; many consumers | Current legacy cross-surface authority; known defect |
| Plan | runtime `ShoppingPlan` and `ShoppingPlanGenerationState` | Product/Shopping/Home/Map paths | Derived runtime authority without durable list revision |
| Session | `ShoppingSession` header and encoded UUID arrays | `ShoppingSessionService`, Product/Shopping UI | Session-local collection exists; final reconciliation does not |
| History | `ProductHistory` aggregate | `ShoppingMemoryService`, personalization | Separate durable data, not UUID-first event authority |
| Catalog | bundled `CatalogProduct` graph | catalog loader/search/validator/resolver; Product snapshot persistence | Independent Catalog authority retained |
| Recognition knowledge | SwiftData `ProductKnowledge` | `ProductKnowledgeService`, camera, settings | Separate learned recognition authority |
| Saved location | `GeoLocation` and `shoppingItems` relationship | Map, Settings, Product, location detail, debug seed | Parallel location/store-note authority |
| Notifications/geofencing | serialized item/list/store snapshot and OS registrations | `LocationManager`, `GeofenceNotificationService`, `AppStateManager` | Derived integration snapshot can become stale |
| Migration/recovery | versioned schemas, migration plan, startup bootstrap/backfill | container, quarantine, repair | Physical migration and semantic runtime repair are separate owners |

The central architectural fact is that the compatibility record is simultaneously a persistence model, a projection, a session input, a planning input, a Map/location input, a notification input, and a history signal. That causes the current system to violate the approved one-authority-per-lifecycle principle even though several underlying identities and boundaries are sound.

---

## 2. Write Authority Inventory

### 2.1 Persisted model and schema boundaries

| File / symbol | Type | Persisted responsibility | Authority observation |
|---|---|---|---|
| `WayTask/Models.swift:4-68` — `GeoLocation` | Current SwiftData model | Saved-location/store-note identity, coordinate, and cascading compatibility-item relationship | Owns a parallel location relationship; it is not Product/list lifecycle authority |
| `WayTask/Models.swift:70-188` — `ShoppingItem` | Current SwiftData compatibility model | Compatibility identity, copied display/acquisition fields, quantity, global `isCompleted`, and optional location relationship | Durable current legacy compatibility authority consumed across surfaces |
| `WayTask/Models.swift:190-551` — `Product` | Current SwiftData Product model | Stable user identity, Library tombstone, acquisition/display fields, optional Catalog identity and saved snapshots, legacy item link | Owns current Product identity and Library lifecycle; model methods also mutate display/link/lifecycle state |
| `WayTask/Models.swift:553-591` — `ShoppingList` | Current SwiftData list model | Stable list identity, title, kind, default-list marker, timestamps | Owns current list metadata but has no durable content revision |
| `WayTask/Models.swift:593-626` — `ShoppingListEntry` | Current SwiftData entry model | Exact list and Product IDs, Product relationship, legacy item ID, quantity, checked state, sort order | Owns current exact-list membership and entry-local resolution data |
| `ProductHistory.swift:4-39` — `ProductHistory` | Current SwiftData history model | Barcode/name-keyed aggregate, recency/frequency, source, and optional last-completed date | Separate durable aggregate; not UUID-first immutable Product event history |
| `ShoppingSession.swift:4-72` — `ShoppingSession` | Current SwiftData session model | Active/finished header, comma-encoded item and collected-item UUID arrays, optional list/store snapshot | Owns current session-local collection state; stores compatibility IDs rather than normalized lines/outcomes |
| `WayTask/Persistence/WayTaskSchemaV1.swift:4-115` — `WayTaskSchemaV1` | Frozen shipped schema | V1 Product and entry shapes plus shared persisted models | Physical legacy schema; not a runtime mutation authority |
| `WayTask/Persistence/WayTaskSchema.swift:6-142` — `WayTaskSchemaV2` | Frozen shipped schema | V2 Product Catalog snapshot fields and entry shape plus shared persisted models | Physical legacy schema; not a runtime mutation authority |
| `WayTask/Persistence/WayTaskSchema.swift:144-214` — `WayTaskSchemaV3`, `WayTaskSchemaMigrationPlan`, `WayTaskModelContainer` | Current schema, migration, and container composition | Current model graph; V1→V2 and V2→V3 lightweight stages; default and in-memory container construction | Physical persistence authority; semantic legacy interpretation remains in startup repair |

### 2.2 Durable Product, list, compatibility, session, and history writers

| File / symbol | Type | Responsibility | Mutation performed |
|---|---|---|---|
| `WayTask/Models.swift:377-418` — `Product.refresh(from:)` | Entity mutator | Synchronize an unlinked active Product from a compatibility item | Rewrites Product display/acquisition fields, `legacyShoppingItemID`, and `updatedAt`; refuses catalog-linked or tombstoned Products |
| `WayTask/Models.swift:420-470` — `Product.refresh(from:fallbackImageData:)` | Entity mutator | Refresh an unlinked active Product from a recognition candidate | Rewrites Product display, image, source, search, and timestamp fields |
| `WayTask/Models.swift:472-488` — `markDeletedFromLibrary`, `restoreToLibrary` | Entity lifecycle mutator | Product Library lifecycle | Sets or clears `deletedAt` and updates `updatedAt` |
| `WayTask/Models.swift:584-589` — `ShoppingList.kind` setter | Entity mutator | Change current persisted list kind | Rewrites `kindRawValue` and `updatedAt` |
| `ShoppingListService.swift:68-109` — `addManualItem`, `addRecognizedProduct`, `addManualProduct` | Domain/persistence service | Create compatibility items or user Products | Inserts and saves `ShoppingItem` or `Product`; compatibility insert may attach to a location, record memory/knowledge, and invoke startup backfill |
| `ShoppingListService.swift:112-148` — `upsertRecognizedProduct` | Product acquisition service | Barcode/candidate Product upsert | Fetches unlinked Products; may explicitly clear a tombstone on barcode match, refresh Product fields, insert a Product, learn Product Knowledge, and save |
| `ShoppingListService.swift:151-191` — `addProductToShopping` | List mutation service | Add or reuse a Product in one named list | Silently reopens an existing entry, reopens or creates a compatibility item, rewrites Product/entry compatibility IDs, creates a `ShoppingListEntry`, saves, and records memory/knowledge |
| `ShoppingListService.swift:194-210` — `removeProductFromShopping` | List mutation service | Remove Product membership from one named list | Marks each linked compatibility item completed, deletes matching entries, and saves |
| `ShoppingListService.swift:232-250,328-377` — compatibility creation and refresh helpers | Compatibility writer | Materialize and synchronize compatibility state | Inserts `ShoppingItem`, appends it to a `GeoLocation`, reopens it, refreshes copied Product fields, and rewrites compatibility links |
| `ShoppingListService.swift:409-455` — `ProductLibraryDeletionService.delete` | Product Library mutation service | Current Product Library removal | Tombstones Product, finds Weekly list IDs, marks linked compatibility items completed, deletes matching Weekly entries, and saves; it does not inspect active sessions |
| `ShoppingListService.swift:464-738` — `ShoppingListBackfillService` | Startup repair writer | Default-list and legacy graph repair | Creates/normalizes Weekly, Completed, and Recent lists; repairs Product/entry/item links; creates Products for supported active legacy states; normalizes catalog snapshots; completes compatibility items and removes Weekly entries for tombstones; saves |
| `WayTask/Persistence/CatalogProductPersistenceService.swift:106-218` — `save`, `restore` | Catalog acquisition persistence service | Exact Catalog Product persistence | Returns active exact matches; otherwise restores a matching tombstone and rewrites its snapshot, or inserts a new Product; saves through an injected boundary |
| `WayTask/Persistence/CatalogProductPersistenceService.swift:274-319` — `CatalogProductRestoreSnapshot.restore` | Failure rollback mutator | Restore in-memory state after a failed catalog save | Rewrites the Product tombstone, timestamps, display fields, source, and complete catalog snapshot to their pre-save values |
| `WayTask/ProductCatalog/ShoppingItemCatalogResolver.swift:114-166` — `repairCanonicalMetadata` | Catalog metadata repair writer | Normalize a Product’s explicit Catalog identity and saved snapshots | May rewrite Catalog Product ID, snapshot fields, Product category, and snapshot update time; invoked by startup backfill |
| `WayTask/ProductCatalog/ShoppingItemCatalogResolver.swift:168-243` — `hydrate` | Compatibility metadata writer | Project Product Catalog identity into compatibility items | Mutates only the compatibility model’s three transient catalog fields; clears them when no exact Product link is available |
| `ShoppingSessionService.swift:24-82` — `startShopping`, `createOrResumeShoppingSession` | Session persistence service | Start or reuse a Shopping Session | Returns the newest active session before validating requested context; otherwise filters incomplete compatibility items, inserts a session snapshot/header, and saves |
| `ShoppingSessionService.swift:100-129` — `markItemCollected`, `markItemRemaining` | Session mutation service | Session-local collection state | Adds/removes compatibility-item UUIDs in encoded session arrays and saves |
| `ShoppingSessionService.swift:135-149` — `finishShopping` | Session mutation service | Current Finish behavior | Sets `isActive = false`, stamps `finishedAt`, and saves; it does not reconcile list entries, list revision, history, or plan |
| `ShoppingMemoryService.swift:12-86` — `recordProductAdded`, `update` | History persistence service | Current shopping-memory aggregation | Inserts or updates `ProductHistory` by barcode/name key, increments frequency/recency, and can write `lastCompletedDate` from `ShoppingItem.isCompleted` |
| `ProductKnowledgeService.swift:35-209` — `learn` and lookup helpers | Recognition-knowledge service | Persist learned recognition metadata | Inserts or updates `ProductKnowledge`, increments use metadata, and saves; it is adjacent knowledge, not Product lifecycle authority |

### 2.3 Direct SwiftUI and application-layer writers

| File / symbol | Type | Responsibility | Mutation performed |
|---|---|---|---|
| `ProductListView.swift:1487-1548` | UI command initiator | Start/collect/finish a current session | Passes the view-owned `ModelContext` to `ShoppingSessionService` |
| `ProductListView.swift:1551-1699` | UI command initiator | Product acquisition, Product Library removal, list add/remove | Dispatches to `AddProductSaveCoordinator`, `ProductLibraryDeletionService`, and `ShoppingListService`; separately mutates runtime plan state |
| `ProductListView.swift:1733-1828` — image/location helpers | Direct UI writer | Product image caching and compatibility synchronization | Rewrites Product image/timestamp, copies Product fields into every linked compatibility item, removes item/location relationships, and explicitly saves |
| `ProductListView.swift:2112-2126` — `assign(_:to:)` | Direct UI writer | Assign a compatibility item to a saved location | Removes existing location relationships, inserts a new `GeoLocation`, appends the item, saves, and changes Map focus |
| `WayTask/ShoppingWorkspaceView.swift:1426-1484` | UI command initiator | Session start, collection, Finish | Passes the view-owned context to `ShoppingSessionService`; clears runtime plan state after Finish |
| `WayTask/ShoppingWorkspaceView.swift:1535-1585` | Direct UI lifecycle writer | Entry resolution, compatibility mirroring, quantity | Directly toggles `entry.isChecked`, mirrors `item.isCompleted`, rewrites quantity, saves, and changes runtime plan/revision state |
| `WayTask/ContentView.swift:232-244` | Startup UI initiator | Runtime backfill | Calls `ShoppingListBackfillService` from the root view even though startup bootstrap also runs repair |
| `WayTask/ContentView.swift:391-412` — `startFreshWeeklyShopping` | Direct UI lifecycle writer | Reset current Weekly entries | Marks linked compatibility items completed, directly deletes entries, saves, and changes runtime plan/revision state |
| `WayTask/ContentView.swift:678-906` — `ProductShoppingSelectionSheet` | UI command initiator | Batch add Products to one list | Passes its environment context to `ShoppingListService` once per selected Product and separately signals runtime invalidation |
| `WayTask/LocationDetailView.swift:22-50,83-115` | Direct UI lifecycle writer | Location-owned compatibility items | Directly toggles completion, appends newly constructed items to the location relationship, removes relationships, and deletes items; persistence can rely on autosave where no explicit save appears |
| `WayTask/MainMapView.swift:381-449` | Direct UI persistence writer | Saved-location creation and verification | Inserts, saves, fetch-verifies, and deletes a `GeoLocation`; refreshes geofences and Map projection after persistence |
| `SettingsView.swift:244-255,410-438` | Direct UI persistence writer | Saved-location CRUD | Directly deletes, inserts, or rewrites `GeoLocation` fields and saves |
| `CameraView.swift:877-946` | Acquisition UI initiator | Barcode lookup and recognized Product save | Reads learned Product Knowledge and calls `ShoppingListService.upsertRecognizedProduct`; then signals a Shopping-list change even though the persisted destination is Product Library |
| `DebugSeedStoreService.swift:19-58` | Debug-only direct writer | Seed a synthetic/debug saved store | Fetches, creates or rewrites a `GeoLocation`, and saves when the debug gate is enabled |

### 2.4 Coordinators, runtime writers, and external side effects

| File / symbol | Type | Responsibility | Mutation performed |
|---|---|---|---|
| `WayTask/Persistence/AddProductSaveCoordinator.swift:30-164` | Acquisition coordinator | Route Catalog versus custom Product saves | Passes `ModelContext` to the catalog persistence or manual Product writer and validates exact persisted Catalog identity; it does not itself call a persistence primitive |
| `WayTask/AppStateManager.swift:337-554` | Runtime state manager | Selected list, library IDs, plan, staleness, navigation | Replaces the in-memory `shoppingListRevision` UUID, creates/clears runtime plans, and changes plan state; none of these values is a durable list-domain revision |
| `WayTask/AppStateManager.swift:556-726` | Runtime integration router | Notification/nearby-opportunity navigation | Parses snapshot metadata and updates selected list, Map focus, and navigation context; it does not validate a durable list revision |
| `MapViewModel.swift:157-970` | Runtime projection writer | Map stores, products, selection, filters, and shared-plan application | Mutates in-memory Map projection from compatibility items, saved locations, store results, or runtime plan |
| `WayTask/LocationManager.swift:54-482` | OS integration writer | Geofence registration and nearby-notification scheduling | Filters compatibility items, creates candidates, starts/stops monitored regions, and submits notification requests; it does not persist Product/list/session lifecycle |
| `GeofenceNotificationService.swift:34-161,164-358` | Notification snapshot writer | Encode/decode reminder context and build notification requests | Serializes store/location/list/item snapshot data, applies cooldown state, and constructs local notification content; it does not mutate SwiftData Product State |
| `CameraViewModel.swift`, `WayTask/ProductKnowledge/Presentation/AddProductAutocompleteViewModel.swift` | Transient acquisition state | Recognition and selection workflow | Mutate only in-memory candidate/selection/presentation state; durable mutation begins only after a UI caller invokes a persistence service |
| `AIProductRecognitionService.swift`, `GeminiProductRecognitionService.swift`, `ProductRecognitionService.swift`, `OpenFoodFactsProvider.swift` | Acquisition evidence providers | Produce recognition candidates | Return transient `ProductCandidate`/`RecognitionResult` values; they have no `ModelContext` and do not directly mutate Product State |

### 2.5 Write-authority conclusions

Verified facts:

- Product/list/session/history persistence is not controlled through one command surface.
- Dedicated services exist, but views can bypass them for checked/completed state, quantity, entry deletion, Product display synchronization, and location relationships.
- Product acquisition has three durable routes: manual Product creation, barcode/candidate upsert, and exact Catalog Product persistence.
- both barcode and Catalog acquisition can restore a tombstone in current code.
- startup repair and root-view backfill can both execute graph repair.
- runtime invalidation is a separate view-driven step after many persistence mutations.

Architectural interpretation:

- `ShoppingListService`, `ProductLibraryDeletionService`, `ShoppingSessionService`, `ShoppingMemoryService`, `CatalogProductPersistenceService`, and `AddProductSaveCoordinator` are the existing service-shaped seams most closely aligned with future authority boundaries.
- Their existence does not currently prevent direct writers, guarantee a single transaction across adjacent lifecycles, or make compatibility state derived-only.

---

## 3. Read Authority Inventory

### 3.1 SwiftData query consumers

| File | Consumer | Data read |
|---|---|---|
| `ProductListView.swift:14-25` | Product Library, Product actions, planner/session presentation | All compatibility items; active Products (`deletedAt == nil`); locations; history; sessions; lists; entries |
| `WayTask/HomeView.swift:11-21` | Home summary, plan, recent Products, session progress | Compatibility items; active Products; locations; sessions; lists; entries |
| `WayTask/ShoppingWorkspaceView.swift:12-22` | Shopping list, plan, store recommendations, session UI | Compatibility items; locations; sessions; active Products; lists; entries |
| `WayTask/ContentView.swift:20-30` | Startup/backfill, recovery, geofence refresh | Compatibility items; locations; sessions; active Products; lists; entries |
| `WayTask/ContentView.swift:682-689` — `ProductShoppingSelectionSheet` | Product-to-list chooser | Active Products, lists, entries |
| `WayTask/MainMapView.swift:12-20` | Map and saved-location presentation | Locations, compatibility items, active Products, entries |
| `WayTask/BetaDiagnosticsView.swift:63-65` | Diagnostic summary | Lists, entries, locations; checked/needed counts and signatures |
| `SettingsView.swift:13-14` | Settings and custom stores | Locations and learned `ProductKnowledge` records |

These 37 declarations are direct SwiftData read surfaces. `@Query` supplies live models to views, which then compute Product State independently rather than consuming one authoritative read projection.

### 3.2 Domain, persistence, and repair readers

| File | Consumer | Data read |
|---|---|---|
| `WayTask/Models.swift` | Entity computed properties and conversions | Product tombstone, Catalog link/snapshot, search/source fields; entry/list identifiers; compatibility metadata |
| `ShoppingListService.swift:112-209` | Product acquisition and list mutation | All Products, entries, compatibility items, Product/list/legacy IDs, tombstone, checked/completed state |
| `ShoppingListService.swift:419-455` | Product Library deletion | Lists and kinds, entries, compatibility items, Product identity |
| `ShoppingListService.swift:468-767` | Startup repair | Full Product/list/entry/compatibility graph, Catalog identifiers, tombstones, checked/completed state, orphan relationships |
| `WayTask/Persistence/CatalogProductPersistenceService.swift:106-164` | Exact Catalog Product save | Products by exact Catalog ID; active/tombstoned status and snapshot state |
| `WayTask/ProductCatalog/ShoppingItemCatalogResolver.swift` | Catalog compatibility and repair | Explicit Catalog IDs, Product snapshots, Product/entry legacy links, transient compatibility Catalog fields |
| `ShoppingSessionService.swift` | Session lookup and lifecycle | Active session header, requested compatibility items, completion, item/collected UUID arrays, list/store snapshot |
| `ShoppingMemoryService.swift` | Current history lookup/personalization input | Compatibility name/barcode/source/completion and `ProductHistory` aggregate fields |
| `ProductKnowledgeService.swift` | Learned recognition lookup | Barcode/name knowledge keys and learned display/recognition metadata |
| `WayTask/Persistence/WayTaskSchemaV1.swift` | Frozen V1 schema reader | V1 Product/entry shape and the shared V1 persisted model graph |
| `WayTask/Persistence/WayTaskSchema.swift` | Schema/container composition | Frozen V2 shape, current V3 model graph, migration stages, default store URL, and container configuration |
| `WayTask/Persistence/WayTaskStartupPersistence.swift` | Store open, repair, and recovery | Container-open result, repair result, store/sidecar presence, privacy-safe diagnostic categories |

### 3.3 Product, Shopping, plan, history, and discovery consumers

| File | Consumer | Data read |
|---|---|---|
| `ProductListView.swift:1335-1465,1701-1803` | Product filters and compatibility presentation | Selected-list entry membership, Product/entry legacy IDs, compatibility completion, Product tombstone, history aggregation |
| `WayTask/HomeView.swift:400-523,602-617,734-806` | Home counts, plan input, recent Product cards, location stores | Entry checked state, compatibility completion, list kinds, session arrays, Product identity/display, location relationships |
| `WayTask/ShoppingWorkspaceView.swift:515-654,801-982,1105-1206` | Shopping rows and planning | Selected-list entries, Product relationships, legacy compatibility links, checked/completed state, runtime plan/session/store context |
| `WayTask/ContentView.swift:178-210,415-470` | Refresh signatures and integration inputs | Compatibility completion/display/Catalog data, location item relationships, session active/collected fields |
| `WayTask/AppStateManager.swift:119-272` — `ShoppingPlan` | Runtime Shopping Plan | Incomplete compatibility items, item/display/Catalog fields, stores, buying options, coverage, generated time, content signature |
| `DecisionEngine.swift:36-55` | Discovery decision engine | `ShoppingContext.hasActiveShoppingItems`, incomplete context item IDs, nearby-store matches |
| `DiscoverViewModel.swift:27-143` | Discover presentation | Incomplete `ShoppingContextItem` values and matching store item names |
| `ShoppingContext.swift:23-102` | AI/discovery snapshot DTO | Item UUID/name/completion/hints and surrounding location/store/user context |
| `ShoppingIntentMatcher.swift:291-1138` | Product classification and plan/store intent | Compatibility item Catalog identity, metadata and hints; incomplete eligible/unresolved/relevant sets |
| `ShoppingTripService.swift:13-82` | Store coverage planning | Incomplete compatibility items and resolved store relevance |
| `BuyingOptionsService.swift` | Buying option projection | Shopping request, compatibility items, grouped intents, stores, and user location |
| `StoreCoverage.swift`, `BuyingOptionsSheet.swift` | Plan result presentation | Matched/missing compatibility items, store coverage, active trip items |
| `WayTask/ProductCatalog/ProductCatalogPersonalization.swift:120-260` | Catalog ranking personalization | Products, list entries, Product History; exact Catalog IDs and normalized-name fallback |

### 3.4 Map, store, location, notification, and presentation consumers

| File | Consumer | Data read |
|---|---|---|
| `StoreSearchService.swift:30-342` — `StoreResolutionEngine` | Store-resolution boundary | Incomplete compatibility items, intent groups, saved locations, item names, location metadata, provider results |
| `StoreSearchService.swift:345-441` | Local/MapKit store search | Store-resolution requests, Product/store intent, provider results |
| `StoreRankingService.swift` | Store ranking | Resolved Product intent profiles, saved-location evidence, category/reality signals, store/item coverage |
| `MapViewModel.swift:247-970` | Map projection | Compatibility completion, plan items, saved-location relationships, store item names, Product display names, selected store/navigation context |
| `WayTask/MainMapView.swift` | Map composition | Live SwiftData queries, runtime plan, Catalog-hydrated compatibility items, Map projection and notification context |
| `WayTask/LocationManager.swift` | Geofence and nearby detection | Incomplete compatibility items, eligible intents, saved locations, current location, list ID |
| `GeofenceNotificationService.swift` | Notification payload/service | Store/location identity, item names and compatibility IDs, optional list ID, source type, distance, coordinate, notification type |
| `WayTask/AppStateManager.swift:657-720` | Notification deep-link consumer | Item/list/store/location snapshots from notification `userInfo` |
| `MapBottomSheet.swift`, `WayTaskMapView.swift`, `ProductAnnotation.swift` | Map presentation | `MapViewModel` store/product projection and likely-item labels; no direct persistence |
| `WayTask/LocationDetailView.swift` | Saved-location item UI | `GeoLocation.shoppingItems`, item display/image/completion |

### 3.5 Catalog, Product Knowledge, camera, scanner, and AI consumers

| File | Consumer | Data read |
|---|---|---|
| `WayTask/WayTaskApp.swift:20-85` | Application composition | Startup persistence result and bundled Catalog availability |
| `WayTask/ProductCatalog/CatalogProduct.swift` | Catalog record model | Stable Catalog identity, canonical/display/category metadata, active/replacement lifecycle |
| `WayTask/ProductCatalog/ProductCatalogService.swift` | Catalog loader | Bundled Catalog/taxonomy resources and validated Catalog products |
| `WayTask/ProductCatalog/ProductCatalogSearch.swift` | Catalog search actor | Active Catalog products, names/aliases/keywords/categories, personalization profile |
| `WayTask/ProductCatalog/ProductCatalogValidator.swift`, `ProductCatalogCompatibilityDecoder.swift` | Catalog validation/migration boundary | Catalog schema/version, stable IDs, active/replacement state, taxonomy and compatibility metadata |
| `WayTask/ProductKnowledge/Application/ProductKnowledgeRepository.swift`, `.../InMemoryProductKnowledgeRepository.swift`, `.../ProductKnowledgeSearch.swift` | Read-only Product Knowledge boundary | Bundled Product entities, names, categories, icons, and search results; no user Product lifecycle |
| `WayTask/ProductKnowledge/Application/ProductKnowledgeError.swift` | Bundled-knowledge validation/error boundary | Validation codes and privacy-safe resource/schema/taxonomy failure categories; no user Product State |
| `WayTask/ProductKnowledge/Presentation/AddProductAutocompleteViewModel.swift` | Product acquisition presentation | Catalog/knowledge search results, transient selection, Product-derived personalization passed from Product UI |
| `WayTask/Persistence/AddProductSaveCoordinator.swift` | Acquisition persistence routing | Catalog/custom selection and exact resolved Catalog identity |
| `CameraView.swift` | Scanner/acquisition UI | Barcode result, learned Product candidate, recognition candidate, captured image state |
| `CameraViewModel.swift` | Recognition workflow | Barcode/photo/AI recognition results and transient Shopping context |
| `AIProductRecognitionService.swift`, `GeminiProductRecognitionService.swift`, `ProductRecognitionService.swift` | AI recognition providers | Image/barcode acquisition evidence; they return candidates and do not read persisted Product State |
| `OpenFoodFactsProvider.swift` | External barcode data provider | Barcode request and remote Product metadata; returns transient candidates and does not read SwiftData |

### 3.6 Diagnostics and existing characterization readers

| File | Consumer | Data read |
|---|---|---|
| `WayTask/BetaDiagnosticsView.swift`, `WayTask/BetaDiagnostics.swift` | In-app diagnostics | Aggregate list/entry/location/plan/session/store/notification counts and state signatures |
| `WayTask/SentryReportingService.swift` | Monitoring boundary | Allowlisted operation/category/area and numeric context; no direct Product State persistence |
| `WayTaskTests/ProductState/` | Phase 1 characterization only | Synthetic current domain, persistence, consumer, diagnostic, and performance behavior; test code is not production authority |

At the inspected commit, the Product State Phase 1 test area contains five characterization suites, one support self-test suite, one support file, and one fixture manifest. It provides 49 Product State test selectors in total. These tests characterize current behavior and known defects; passing them does not approve the legacy authority model.

---

## 4. ModelContext Access Inventory

### Classification meaning

- **Expected:** Direct persistence access belongs to application persistence composition or to a separate, already bounded non-Product-lifecycle store.
- **Transitional:** Direct access exists in current code but crosses a view, compatibility, debug, or runtime-repair boundary that WT-030 through WT-032 do not accept as final Product State authority.
- **Candidate for Authority:** An existing service/coordinator boundary is shaped like the future owner of a lifecycle, although its current behavior and transaction scope do not yet satisfy the approved target.

| File / component | Direct access | Classification | Basis |
|---|---|---|---|
| `WayTask/Persistence/WayTaskStartupPersistence.swift:142-155` | Creates a `ModelContext`, disables autosave, and runs repair | Expected | Persistence composition owns store opening and must invoke controlled recovery/repair; the current repair semantics remain separate from target migration |
| `WayTask/WayTaskApp.swift` | Owns and injects `ModelContainer`; no direct `ModelContext` operations | Expected | Application composition boundary |
| `ProductKnowledgeService.swift` | Typed context; ProductKnowledge fetch/insert/save | Expected | Separate learned-recognition store, not Product/list/session lifecycle |
| `ShoppingListService.swift:61-407` | Typed context; Product, entry, compatibility and history/knowledge fetch/insert/delete/save | Candidate for Authority | Existing Product/list service seam, but current methods combine acquisition, compatibility, history, and repair side effects |
| `ShoppingListService.swift:409-455` — `ProductLibraryDeletionService` | Typed context; list/entry/item fetch, tombstone, delete, save | Candidate for Authority | Existing Product Library command-like boundary; current scope is Weekly-only and has no active-session guard |
| `ShoppingSessionService.swift` | Typed context; active-session fetch, insert, session mutation, save | Candidate for Authority | Existing Session service boundary; current model and Finish behavior remain legacy |
| `ShoppingMemoryService.swift` | Typed context; history fetch/insert/update/save | Candidate for Authority | Existing history service boundary; current aggregation is not UUID-first event history |
| `WayTask/Persistence/CatalogProductPersistenceService.swift` | Typed context; exact Product fetch, insert/delete, injected save | Candidate for Authority | Strong exact-ID Catalog acquisition boundary; current path can restore implicitly |
| `WayTask/Persistence/AddProductSaveCoordinator.swift` | Passes typed context to catalog/manual writers | Candidate for Authority | Existing acquisition orchestration seam; it does not yet express all explicit lifecycle outcomes |
| `ShoppingListService.swift:464-738` — `ShoppingListBackfillService` | Typed context; full-graph fetch, insert/delete/update/save | Transitional | Runtime repair currently interprets and mutates live Product/list/compatibility state; WT-032A assigns semantic migration to one pre-UI owner |
| `ProductListView.swift` | One environment context; service calls plus direct Product/compatibility/location writes and three saves | Transitional | View owns persistence context and can compose state outside a command boundary |
| `CameraView.swift` | One environment context; ProductKnowledge read and Product upsert service calls | Transitional | View passes raw persistence context across acquisition boundaries |
| `WayTask/ContentView.swift` | Two environment contexts across root and chooser; direct entry delete/save, startup repair, batch service writes | Transitional | Root/chooser views participate in lifecycle and repair persistence |
| `WayTask/ShoppingWorkspaceView.swift` | One environment context; session/list service calls plus direct checked/completed/quantity save | Transitional | Primary lifecycle UI directly mutates co-authoritative fields |
| `WayTask/LocationDetailView.swift` | One environment context; direct item delete and autosaved model/relationship mutations | Transitional | Location UI owns a parallel compatibility lifecycle |
| `WayTask/MainMapView.swift` | One environment context; location fetch/insert/delete/save | Transitional | Map UI directly owns saved-location persistence |
| `SettingsView.swift` / `CustomStoreEditorView` | Two environment contexts; direct location insert/delete/update/save | Transitional | Settings UI directly owns saved-location persistence |
| `DebugSeedStoreService.swift` | Typed context; location fetch/insert/update/save | Transitional | Debug-only persistence path outside a production authority boundary |

### Direct-access concentration

| Component | Fetch | Insert | Delete | Explicit `modelContext.save()` |
|---|---:|---:|---:|---:|
| `ShoppingListService.swift` including deletion/backfill | 13 | 8 | 3 | 8 |
| `ShoppingSessionService.swift` | 1 | 1 | 0 | 4 |
| `ShoppingMemoryService.swift` | 2 | 1 | 0 | 2 |
| `ProductKnowledgeService.swift` | 1 | 1 | 0 | 2 |
| `CatalogProductPersistenceService.swift` | 1 | 1 | 1 | 0 direct; injected save boundary |
| `ProductListView.swift` | 0 | 1 | 0 | 3 |
| `MainMapView.swift` | 2 | 1 | 1 | 1 |
| `SettingsView.swift` | 0 | 1 | 1 | 2 |
| `ContentView.swift` | 0 | 0 | 1 | 1 |
| `ShoppingWorkspaceView.swift` | 0 | 0 | 0 | 1 |
| `LocationDetailView.swift` | 0 | 0 | 1 | 0 |
| `DebugSeedStoreService.swift` | 1 | 1 | 0 | 1 |

The fetch column includes multiline `modelContext.fetch` chains in startup backfill. `CameraView` and `AddProductSaveCoordinator` pass a context without calling a persistence primitive directly, and startup creates a context under the local name `context`.

Architectural interpretation: a view having `@Query` is not itself a direct `ModelContext` mutation, but the combination of 37 live queries with view-local joins and 9 environment contexts means both read policy and write policy are distributed across presentation code.

---

## 5. Dependency Map

### 5.1 Current dependency graph

```text
Bundled Catalog / Product Knowledge / scanner / AI / barcode provider
          │                         │
          │ candidates and IDs      │ learned recognition
          ▼                         ▼
AddProductSaveCoordinator ──► CatalogProductPersistenceService
          │                         │
          └──────────────► ShoppingListService
                                      │
                         ┌────────────┼──────────────┐
                         ▼            ▼              ▼
                     Product   ShoppingListEntry  ShoppingItem
                         │       │ productID       ▲  isCompleted
                         │       │ legacy item ID  │
                         └───────┴─────────────────┘
                                      │
                 ┌────────────────────┼──────────────────────┐
                 ▼                    ▼                      ▼
          ShoppingPlan          ShoppingSession         ProductHistory
          runtime items         encoded item IDs        barcode/name aggregate
                 │                    │                      │
                 └────────────┬───────┴──────────────┬───────┘
                              ▼                      ▼
                     Product/Home/Shopping       personalization
                              │
                 ┌────────────┼───────────────────────────┐
                 ▼            ▼                           ▼
             Map/store   GeoLocation.shoppingItems   notifications/geofences
                 │            │                           │
                 └────────────┴─────────► AppStateManager ◄┘

SwiftData V1 → V2 → V3 migration
          │
          ▼
WayTaskStartupPersistenceBootstrap
          │
          ▼
ShoppingListBackfillService ──► Product / lists / entries / compatibility /
                                Catalog snapshots / tombstone cleanup
```

### 5.2 Dependency inventory

| Boundary | Depends on | Downstream dependents | Current authority effect |
|---|---|---|---|
| `Product` | SwiftData, `ProductSource`, optional Catalog identity/snapshot | entries, Product UI, compatibility materialization, personalization, Catalog resolver | Owns identity and tombstone; display state is copied into compatibility records |
| `ShoppingList` | SwiftData | Product/Shopping/Home UI, entries, notifications | Owns ID/title/kind/default metadata; has no durable content revision |
| `ShoppingListEntry` | Product UUID/relationship, list UUID, legacy item UUID | Product membership UI, Shopping rows, Home counts, compatibility resolver, backfill | Owns exact-list membership and current checked/quantity/order state |
| `ShoppingItem` | SwiftData; optionally copied from Product | list service, plans, sessions, history, decision/discovery, store matching, Map, location, notifications | Acts as shared cross-surface authority despite being designated compatibility debt |
| `ShoppingPlan` | compatibility items, intent matcher, stores, buying options, trip coverage | Shopping UI, Home, Map | Runtime projection; filters completion and lacks durable list revision/entry IDs |
| `ShoppingSession` | compatibility-item IDs, optional list/store snapshot | Product/Shopping/Home UI, launch recovery, geofence refresh signature | Owns current active/collected arrays; not normalized to lines/outcomes |
| `ProductHistory` | compatibility item name/barcode/source/completion | Product indicators, Catalog personalization | Current aggregate can influence Catalog result ranking |
| `ProductKnowledge` | recognition candidates or compatibility items | camera barcode lookup, settings, legacy knowledge search | Separate learned-recognition authority; not stable user Product identity |
| Bundled Product Catalog | packaged resources and taxonomy | autocomplete, resolver, persistence request, classification, icons | Independent Catalog Truth; only explicit ID resolution is used for Catalog linking |
| `ShoppingItemCatalogResolver` | bundled Catalog, Product snapshot, Product/entry legacy links | repair, Product/Shopping/Home/Map classification and icon presentation | Repairs persisted Product Catalog snapshots and hydrates transient compatibility metadata |
| `ShoppingListService` | raw `ModelContext`, history, knowledge, resolver, backfill | Product UI, chooser, camera, tests | Current broad mutation hub, but not exclusive |
| `ProductLibraryDeletionService` | raw `ModelContext`, list kinds, entries, compatibility | Product UI | Current Product Library removal hub |
| `ShoppingSessionService` | raw `ModelContext`, compatibility completion, Sentry boundary | Product and Shopping UI | Current Session mutation hub |
| `ShoppingMemoryService` | raw `ModelContext`, compatibility values | list service, Product UI, personalization | Current history read/write hub |
| SwiftUI views and `@Query` | SwiftData environment and runtime services | visible Product State and user actions | Reconstruct projections and may write fields directly |
| `AppStateManager` | runtime plans, notifications, nearby detection | every primary tab, Map navigation | Owns presentation selection/invalidation and integration routing, not durable domain state |
| Store classification stack | compatibility items, Catalog resolver, saved locations, providers | plan, Home, Map, nearby notifications | Reads current completion to decide eligible item sets |
| Map/location stack | compatibility items, locations, plans, current location | Map UI, geofences, notifications | Both consumes Product State and writes a parallel saved-location relationship |
| Scanner/camera/AI stack | camera/barcode/image/network evidence, learned knowledge | Product acquisition service | Produces candidate evidence; durable authority begins only at persistence call |
| Notification/geofence stack | compatibility items, locations, optional list ID, runtime location | OS regions/requests and `AppStateManager` route | Persists no lifecycle but carries frozen Product/list/store context |
| Persistence startup | current schema/migration plan, default store, quarantine and repair | entire app model container | Can replace a failed store or use an in-memory store and then run repair |

### 5.3 Architectural boundaries already present

Verified boundaries that should remain conceptually distinct:

- user Product UUID versus Catalog Product ID;
- active/removed Product Library state versus Catalog active/inactive/replacement state;
- bundled Product Knowledge versus mutable learned Product Knowledge;
- camera/AI recognition state versus persisted Product state;
- estimated store/recommendation output versus Product/list truth;
- session-local collected identifiers versus list checked state;
- application navigation/selection versus persisted list membership.

Verified boundary gaps:

- there is no user Product repository abstraction;
- service protocols generally accept a raw `ModelContext`;
- views can write the same persisted entities that services write;
- no single read-projection layer owns Product/list/session joins;
- no single semantic-migration coordinator exists beyond the physical migration plan plus runtime backfill;
- no durable list revision connects lists, plans, Map, and notification snapshots.

---

## 6. Architectural Risks

This section records risk only. It does not prescribe an implementation.

| Risk | Verified source evidence | Consequence | WT trace |
|---|---|---|---|
| Duplicated mutation policy | Entry/list/compatibility state is written by `ShoppingListService`, `ShoppingWorkspaceView`, `ContentView`, `LocationDetailView`, startup repair, and Product UI synchronization | Equivalent user actions can produce different adjacent side effects | KD-01, KD-12; D-01, D-02, D-35 |
| Direct view writes | Primary SwiftUI surfaces mutate checked/completed/quantity, delete entries/items, and create/update locations | Presentation code bypasses shared lifecycle preconditions and transaction policy | KD-12; D-20, D-23, D-35 |
| Shared compatibility coupling | One `ShoppingItem` can be referenced by Product and entries in multiple lists; list removal completes it | A mutation scoped to one list can change consumers for another list or global surfaces | KD-01, KD-02; D-08, D-10, D-33 |
| Ownership ambiguity | `ShoppingListEntry.isChecked` and `ShoppingItem.isCompleted` both describe resolved/active-like state | Consumers choose different truths and contradictory states remain representable | KD-01, KD-12; D-01, D-02 |
| Missing uniqueness invariant | No shipped schema enforces one entry per `(shoppingListID, productID)`; the service uses first-match behavior | Duplicate memberships can persist and survive reopen | KD-03; D-09, D-26, D-37 |
| Split transaction boundaries | Product/list mutation, compatibility mirroring, history/knowledge recording, plan invalidation, geofence refresh, and UI success occur in multiple saves/callbacks | Partial failure can leave adjacent lifecycles or projections inconsistent | D-35, D-36 |
| View-driven invalidation | `shoppingListRevision` is a runtime UUID and callers separately invoke `shoppingListDidChange` | Out-of-band writes may not invalidate a plan; unrelated Product actions can invalidate it | KD-04, KD-05; D-11, D-12 |
| Implicit Product restoration | Barcode upsert and exact Catalog persistence clear tombstones | A Product can return to the active Library without a distinct restore outcome | KD-08; D-17, D-22 |
| Session context reuse | start returns the first active session before validating requested list, store, or item set | A new user intent can silently resume unrelated context | KD-06; D-14, D-29 |
| Incomplete Finish boundary | Finish writes only `isActive` and `finishedAt` | List entries, compatibility completion, plan, history, and remaining-item disposition can disagree after Finish | KD-09; D-03, D-04, D-36 |
| History overstatement | `ProductHistory` is keyed by barcode/name and can derive `lastCompletedDate` from compatibility completion | History and personalization can treat ambiguous compatibility evidence as stronger lifecycle evidence | KD-10, KD-11; D-06, D-07, D-31 |
| Runtime repair as live writer | startup and root-view paths run `ShoppingListBackfillService`; it creates and rewrites Products/lists/links | Migration interpretation and ongoing runtime state repair are not cleanly separated | D-24-D-28, D-30, D-32 |
| Catalog repair writes during startup | backfill calls `repairCanonicalMetadata` on active Catalog-linked Products | Catalog snapshot mutation is coupled to general Product State startup repair | D-22, D-24 |
| Parallel location lifecycle | `GeoLocation.shoppingItems` can create, toggle, and delete compatibility items outside Product/list services | Map/location state can contradict Product Library and named-list state | D-23 |
| Stale integration snapshots | notification/geofence identifiers carry item names/IDs and optional list ID but no durable list revision | A later tap or region event may represent an obsolete Product/list set | KD-12; D-12, D-21 |
| Recovery truthfulness | store-open/repair failure can quarantine, recreate a persistent store, or fall back to memory | The visible application may operate on a new or non-durable graph after failure | D-24, D-34 |
| Full-graph scans | core services/backfill and several views load all Products, entries, compatibility items, lists, or locations and filter in memory | Authority work and projection cost grow with the whole graph and can hide scope errors |
| Implicit autosave | some relationship/field mutations have no explicit save at the mutation site | Persistence timing and failure ownership are harder to reason about |
| Raw-context coupling | service APIs and views pass `ModelContext` throughout the application | Storage mechanics, transaction ownership, and presentation are tightly coupled |
| Integration side effects after local writes | geofence, notification, Sentry, Map, haptics, and plan state are updated separately from SwiftData | External state can lag or lead the durable local result |

---

## 7. Phase 2 Recommendations

These recommendations state architectural direction only. They do not select files, Swift types, schema fields, migration mechanics, or implementation sequencing beyond the already approved WT-031/WT-032 direction.

1. Preserve one authority per lifecycle: Product identity and Library lifecycle, named-list membership/resolution, list revision, plan projection, session line/outcome, Product History, Catalog lifecycle, and saved-location/reminder evidence must remain explicitly separate.
2. Preserve the current stable foundations: user Product UUID, durable tombstone, exact Catalog ID and saved snapshots, Catalog independence, and Product Knowledge separation.
3. Make named domain commands the only Product/list/session/history mutation entry points. Views, Map, notifications, scanner, AI, and recovery presentation should initiate or consume commands rather than write lifecycle fields.
4. Establish scoped read projections so Product, Shopping, Home, Map, notifications, and AI context consume the same named list or session source instead of reconstructing state from global compatibility fields.
5. Treat compatibility storage as migration evidence or one-way derived output only, with zero authority at the approved cutover. Physical retention must not preserve semantic authority.
6. Keep acquisition evidence separate from lifecycle decisions. Scanner, barcode, Catalog, and AI results should identify create/already-present/restore-required outcomes without silently deciding Library restoration or list membership.
7. Keep Catalog and Product Knowledge as independent inputs. Catalog lifecycle and learned recognition must not remove, restore, resolve, purchase, or otherwise decide user Product State.
8. Place Product/list/history changes caused by one user intent inside one authoritative local transaction, and keep OS integrations as idempotent post-commit consumers.
9. Use one semantic migration owner before writable target Product State. Runtime views and general startup repair should not co-own legacy interpretation.
10. Preserve ambiguous legacy evidence conservatively and keep exceptions explicit. Compatibility completion, checked state, names, and barcodes must not be promoted to stronger Product, purchase, or Catalog truth.
11. Make list/plan/session/notification identity and revision scope explicit so stale inputs can be detected rather than inferred from runtime UUID invalidation or frozen names.
12. Remove Product lifecycle persistence access from SwiftUI presentation boundaries as authority is established, while retaining read-only presentation dependencies only through scoped projections.
13. Preserve the single coherent authority cutover required by WT-031A and D-33; do not release a mixed target/legacy authority state.

These directions consume WT-032A D-01 through D-37. They do not add a new decision.

---

## 8. Acceptance Checklist

### Governing references

- [x] WT-030 Product State architecture and audit reviewed.
- [x] WT-031 Product State implementation plan reviewed.
- [x] WT-032 Phase 0 decisions and Phase 1 implementation specification reviewed.
- [x] Phase 1 evidence used only to corroborate current repository facts.

### Inventory completeness

- [x] Complete durable and runtime write-authority inventory recorded.
- [x] Complete SwiftData `@Query`, service, projection, UI, integration, Catalog, scanner, AI, history, and recovery read inventory recorded.
- [x] All direct `ModelContext` environment, service, coordinator, startup, and debug boundaries classified as Expected, Transitional, or Candidate for Authority.
- [x] Current model, schema V1/V2/V3, migration-plan, startup-repair, quarantine, and in-memory-fallback boundaries recorded.
- [x] Product, Product Library, Shopping List, ShoppingListEntry, compatibility ShoppingItem, Plan, Session, History, Catalog, Product Knowledge, Map/location, notification/geofencing, scanner/acquisition, AI, and migration/recovery lifecycles represented.
- [x] Dependency map includes ViewModels, services, repositories, SwiftData, and feature integrations.

### Risk and recommendation boundaries

- [x] Duplicated mutations documented.
- [x] Direct writes and bypassed layers documented.
- [x] Ownership ambiguity documented.
- [x] Transaction and recovery risks documented.
- [x] Recommendations state architectural direction only.
- [x] No implementation model, API, schema, migration, file plan, or production change is designed here.
- [x] Current legacy behavior is not approved as target behavior.

### Repository boundary

- [x] Discovery commands were read-only.
- [x] No production file was modified.
- [x] No test file was modified.
- [x] No SwiftData schema or migration was modified.
- [x] No Xcode project, package, localization, Catalog, or prior WT document was modified.
- [x] The only file introduced by WT-033A S-00 is `docs/Specifications/WT-033A_ProductStateAuthorityDiscovery.md`.

## Reproducible Inventory Commands

Run from the repository root:

```sh
git branch --show-current
git rev-parse HEAD
git status --short --untracked-files=all

rg -l --glob '*.swift' --glob '!WayTaskTests/**' \
  'ShoppingItem|ShoppingListEntry|ProductHistory|ShoppingSession|\bProduct\b|ModelContext' . \
  | sort

for property in isCompleted isChecked legacyShoppingItemID deletedAt shoppingListRevision
do
  rg -o --glob '*.swift' --glob '!WayTaskTests/**' \
    "\b${property}\b" . | wc -l
  rg -l --glob '*.swift' --glob '!WayTaskTests/**' \
    "\b${property}\b" . | wc -l
done

rg -n -F '@Environment(\.modelContext)' \
  --glob '*.swift' --glob '!WayTaskTests/**' .

rg -n --glob '*.swift' --glob '!WayTaskTests/**' \
  '@Query|FetchDescriptor<(Product|ShoppingItem|ShoppingList|ShoppingListEntry|ShoppingSession|ProductHistory|GeoLocation|ProductKnowledge)>' .

rg -n --glob '*.swift' --glob '!WayTaskTests/**' \
  '\bmodelContext\.(insert|delete|save|fetch)\s*\(|\.fetch\s*\(|ModelContext\s*\(' .

rg -n --glob '*.swift' --glob '!WayTaskTests/**' \
  '(\.isCompleted\s*=|\.isCompleted\.toggle|\.isChecked\s*=|\.isChecked\.toggle|restoreToLibrary\(|markDeletedFromLibrary\(|\.legacyShoppingItemID\s*=|\.quantity\s*=|\.itemIDs\s*=|\.collectedItemIDs\s*=|\.isActive\s*=|\.finishedAt\s*=)' .

git diff --name-only
git diff --cached --name-only
git status --short --untracked-files=all
```

## S-00 Disposition

Product State Authority discovery is complete at commit `a20b83c570157038cb85b0b3efb49a24cf8ccc50`.

The current codebase has enough verified boundary information to prepare a Phase 2 implementation specification, but this document authorizes no implementation. Approval is required before any production, test, schema, migration, project, package, localization, Catalog, or prior documentation change.
