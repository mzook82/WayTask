# WT-030A - Product State UX Audit

**Product:** WayTask iOS

**Audit type:** Product architecture and UX

**Status:** Complete

**Audit date:** 2026-07-29

**Evidence baseline:** `main` at `35a0775`

**Implementation authorization:** None

**Terminal decision:** Approve the Orthogonal Product Lifecycle architecture in Section 13 as the official WayTask Product State standard.

---

## 1. Executive Summary

WayTask does not currently have one Product State model. It has several state owners that partially overlap:

- `Product.deletedAt` owns whether a user-library record is active or removed.
- The existence of a `ShoppingListEntry` owns membership in one shopping list.
- `ShoppingListEntry.isChecked` owns a per-list needed/checked state.
- Legacy `ShoppingItem.isCompleted` acts as a global compatibility state used by planning, Map, notifications, saved locations, and parts of Home.
- `ShoppingPlanGenerationState` owns a transient plan lifecycle.
- `ShoppingSession` owns an active/finished lifecycle and a separate set of collected item IDs.
- Catalog `isActive`, replacement metadata, and missing catalog records own catalog availability, not user Product state.

These values are not equivalent and cannot be collapsed safely into one flat enum. A single product can be:

- active in the Product Library;
- needed in Weekly Shopping;
- checked in another list;
- included in a ready plan;
- collected in an active session;
- linked to an inactive catalog concept;
- and represented by a globally completed compatibility item.

The implementation currently allows contradictory combinations because the per-list entry and the shared compatibility item are both writable. The highest-risk examples are:

1. Checking or removing a Product in one list writes `ShoppingItem.isCompleted`, which can hide the same Product from another list's Map, notifications, planner adapter, or Home projection.
2. Finishing Shopping closes only the session. It does not resolve shopping-list entries, record purchase outcomes, populate Completed/Recent, or reconcile remaining items.
3. The checkmark family means at least four different things: in-list membership, pending chooser selection, list checked, and session collected.
4. Map and notification inputs are commonly derived from all globally incomplete compatibility items while carrying the currently selected list ID. The item set and the labeled list can therefore disagree.
5. Product Library deletion is a durable soft deletion, but there is no visible confirmation, undo, removed-products view, or explicit restore action. Re-adding a catalog product or rescanning a matching barcode can restore it implicitly.

The approved v1 Product Specification says:

> Products are permanent. Lists are temporary. Plans are intelligent.

It also says the Product Library must not display shopping-completion checkmarks and that Product Cards never carry a completion checkbox. The current Product Library membership checkmark conflicts with that rule.

### Official recommendation

Adopt an **Orthogonal Product Lifecycle**:

- Product identity and reusable attributes are not shopping state.
- User-library membership is `active` or `removed`.
- Shopping membership and resolution are owned per list entry.
- Plan state is a rebuildable projection tied to a specific list revision.
- Session execution is owned per session line, with explicit outcomes.
- Purchase history is an event/history concept, never a global Product state.
- Recommended store is derived plan context, never Product state.
- Catalog active/inactive/replaced is catalog lifecycle, never user-library lifecycle.

All screens must read the same scoped projections and invoke the same domain actions. The legacy global completion flag must not be an authority in the official architecture.

### Terminal decision summary

| Decision | Result |
|---|---|
| One flat Product State enum | Rejected |
| Keep current dual state and change labels only | Rejected |
| Full event-sourced rewrite | Rejected for current product maturity |
| Orthogonal library, list, plan, session, and history state | **Approved** |
| Product globally becomes Purchased | Rejected |
| Recommended Store becomes Product state | Rejected |
| Catalog inactive deletes a saved Product | Rejected |
| Implementation under WT-030A | Not authorized |

---

## 2. Audit Mandate, Method, and Evidence

### 2.1 Scope

This audit covers every current Product lifecycle participant:

- Product creation, recognition, catalog selection, and scanning.
- Product Library display, membership actions, deletion, and restoration.
- Shopping lists, entries, quantities, checking, selection, and removal.
- Shopping Plan creation, invalidation, selection, and Map handoff.
- Shopping Session start, collection, recovery, navigation, and finish.
- Home, Products, Shopping, Map, saved-location, notification, and scanner representations.
- Catalog identity, catalog synchronization, Product Knowledge, and history.
- SwiftData schema migration, startup repair, store recovery, and in-memory fallback.
- Future AI, Android parity, accessibility, localization, and test implications.

### 2.2 Source-of-truth order

Where evidence conflicts, this audit uses the following order:

1. Current production implementation and tests at `35a0775`.
2. Current versioned architecture and specification documents.
3. Recent `docs/60_CHANGELOG.md` and WT-029 commit/test evidence.
4. The v1.0 Product Specification PDF.
5. Earlier audits and root changelogs.
6. Backlog language and historical planning documents.

Earlier audit statements that conflict with current code are treated as historical, not current behavior. In particular, WT-020 described physical Product deletion before WT-029 introduced durable `deletedAt` tombstones.

### 2.3 Evidence limitations

The following requested documents are not present in the working tree, Git history, `main`, or `origin/main`:

- `Version_1.0.3_ProductSpec.md`
- A pre-existing `WT-030A_ProductStateUXAudit.md` template
- Standalone WT-029 specification or audit documents

`docs/10_PRODUCT_SPECIFICATION.md` is empty, and `KNOW_ISSUES.md` contains no usable issue content. The Beta Feedback table in `BETA_BACKLOG.md` has no populated feedback rows.

This audit therefore uses:

- `design/v1.0/WayTask_Product_Specification_v1.0.pdf`;
- current implementation and tests;
- commits `1a34e17`, `aa867c0`, and `35a0775`;
- `docs/60_CHANGELOG.md`;
- `BETA_BACKLOG.md`;
- the Product, Shopping, catalog, architecture, and prior-audit documents available in the repository.

The beta observations named in the WT-030A request are treated as required audit inputs. Where the repository contains a matching backlog item, that is identified. Where it does not, the observation is analyzed against current behavior without inventing tester wording, date, or attribution.

### 2.4 Principal evidence reviewed

#### Product and shopping implementation

- `WayTask/Models.swift`
- `ShoppingListService.swift`
- `ProductListView.swift`
- `WayTask/ShoppingWorkspaceView.swift`
- `WayTask/ContentView.swift`
- `WayTask/HomeView.swift`
- `ShoppingSession.swift`
- `ShoppingSessionService.swift`
- `WayTask/AppStateManager.swift`
- `ShoppingTripService.swift`
- `ShoppingIntentMatcher.swift`
- `BuyingOptionsService.swift`
- `StoreCoverage.swift`

#### Map, location, and notification implementation

- `WayTask/MainMapView.swift`
- `MapViewModel.swift`
- `WayTaskMapView.swift`
- `MapBottomSheet.swift`
- `WayTask/LocationDetailView.swift`
- `WayTask/LocationManager.swift`
- `GeofenceNotificationService.swift`

#### Scanner, recognition, and AI implementation

- `CameraView.swift`
- `CameraViewModel.swift`
- `ProductCandidate.swift`
- `ProductRecognitionService.swift`
- `OpenFoodFactsProvider.swift`
- `GeminiProductRecognitionService.swift`
- `ProductKnowledge.swift`
- `ProductKnowledgeService.swift`
- `ProductHistory.swift`
- `ShoppingMemoryService.swift`

#### Catalog and persistence implementation

- `WayTask/Persistence/CatalogProductPersistenceService.swift`
- `WayTask/Persistence/AddProductSaveCoordinator.swift`
- `WayTask/Persistence/WayTaskSchema.swift`
- `WayTask/Persistence/WayTaskSchemaV1.swift`
- `WayTask/Persistence/WayTaskStartupPersistence.swift`
- `WayTask/ProductCatalog/ShoppingItemCatalogResolver.swift`
- `WayTask/ProductCatalog/ProductCatalogService.swift`
- `WayTask/ProductCatalog/CatalogProduct.swift`
- `WayTask/ProductCatalog/ProductCatalogSearch.swift`
- `WayTask/ProductCatalog/ProductCatalogPersonalization.swift`
- `WayTask/WayTaskApp.swift`

#### Tests used as behavioral evidence

- `WayTaskTests/Persistence/ProductLibraryDeletionPersistenceTests.swift`
- `WayTaskTests/Persistence/StartupPersistenceResilienceTests.swift`
- `WayTaskTests/Persistence/StartupRepairIdempotencyTests.swift`
- `WayTaskTests/Persistence/WayTaskSchemaMigrationTests.swift`
- `WayTaskTests/Persistence/CatalogProductPersistenceServiceTests.swift`
- `WayTaskTests/Persistence/CanonicalCatalogSelectionFlowTests.swift`
- `WayTaskTests/ShoppingUX/ShoppingWorkspaceUXTests.swift`
- `WayTaskTests/Map/MapBottomSheetProductLabelTests.swift`

#### Product and architecture documents

- `design/v1.0/WayTask_Product_Specification_v1.0.pdf`
- `docs/20_ARCHITECTURE.md`
- `docs/15_ENGINEERING_BLUEPRINT.md`
- `docs/60_CHANGELOG.md`
- `docs/55_SPRINTS.md`
- `docs/Product/ProductCatalog.md`
- `docs/Product/SmartProductKnowledge.md`
- `docs/Architecture/ProductEntityDataModel.md`
- `docs/Architecture/ProductKnowledgeArchitecture.md`
- `docs/Architecture/ProductKnowledgeMigrationStrategy.md`
- `docs/Architecture/CatalogAwarePersistenceArchitecture.md`
- `docs/Specifications/ProductSearchUXContract.md`
- `docs/Specifications/CanonicalProductCatalogSpecification.md`
- `docs/Specifications/ShoppingFlow_v1.md`
- `docs/100_SHOPPING_TRIPS.md`
- `docs/Audits/2026-07-19_ShoppingFlowAudit.md`
- `docs/Audits/2026-07-23_WT-020_ProductAudit.md`
- `BETA_BACKLOG.md`
- `CATALOG_FEEDBACK.md`
- `DECISIONS.md`
- `ROADMAP.md`
- `docs/40_AI_ROADMAP.md`
- root and documentation changelogs

---

## 3. Product State Terminology

The phrase "Product State" is overloaded. This audit establishes these terms:

| Term | Official meaning |
|---|---|
| Product identity | Stable identity and reusable product attributes. It is not a shopping status. |
| Library state | Whether the user currently keeps the Product in their personal library. |
| List membership | Whether a Product has an entry in one specific shopping list. |
| List-entry state | Whether that one list need is open or resolved. |
| Plan state | Lifecycle of a derived recommendation for a particular list revision. |
| Plan inclusion | Whether a list entry was included in a plan snapshot. |
| Recommendation | A derived store/route suggestion with confidence. |
| Session state | Lifecycle of one shopping execution. |
| Session-line state | Outcome of one Product within one session. |
| Purchase history | A historical event/outcome. It is not a durable state of a reusable Product. |
| Catalog state | Whether a canonical catalog concept is active, inactive, replaced, or missing. |
| Removed | A user-library tombstone retained for restoration, history, and synchronization. |
| Deleted | Reserved for physical erasure or a user-facing action whose exact retention semantics are disclosed. |
| Unknown | Missing/corrupt/unresolved data that must be repaired or presented as unavailable; not a normal Product state. |

The official architecture must never answer a scoped question with an unscoped boolean. For example:

- Not "Is Milk completed?"
- Instead "Is the Milk entry in Weekly Shopping resolved?"
- Or "Was Milk collected in session 123?"

---

## 4. Current Architecture

### 4.1 Current ownership graph

```text
Catalog ProductID and snapshots
              |
              v
Product (user-library UUID, deletedAt)
              |
              +------------------------+
              |                        |
              v                        v
ShoppingListEntry                 ProductHistory
(list, quantity, isChecked)       (frequency/recency)
              |
              v
ShoppingItem compatibility record
(copied attributes, global isCompleted)
      |             |              |
      v             v              v
Planner/Map     Notifications    ShoppingSession
                                  (collected IDs)
```

The intended Product -> ShoppingListEntry relationship is present, but downstream consumers still depend on the denormalized `ShoppingItem`.

### 4.2 Current state owners

| Owner | Persisted | Scope | Current values | Current authority |
|---|---:|---|---|---|
| `Product.deletedAt` | Yes | User library | `nil`, timestamp | Library visibility/removal |
| Catalog link on `Product` | Yes | Product identity | linked/unlinked plus snapshots | Catalog identity only |
| Catalog record | Bundled | Catalog | active/inactive/replaced/missing | Search/discovery eligibility |
| `ShoppingListEntry` existence | Yes | Product + list | present/absent | List membership |
| `ShoppingListEntry.isChecked` | Yes | Product + list | needed/checked | List review state |
| `ShoppingItem.isCompleted` | Yes | Compatibility item | incomplete/completed | Global legacy activity filter |
| `ShoppingPlanGenerationState` | No | Current app/list revision | idle/generating/ready/failed/stale | Plan presentation |
| Selected recommended store | Partly | Current plan/view | selected/unselected | Start-session context |
| `ShoppingSession.isActive` | Yes | Session | active/finished | Session lifecycle |
| `ShoppingSession.collectedItemIDs` | Yes | Session + item | remaining/collected | In-store collection |
| Completed/Recent list kinds | Yes | List shell | weekly/completed/recent | Labels and grouping only |
| Saved-location `ShoppingItem` | Yes | Location | incomplete/completed/deleted | Parallel location-owned lifecycle |

### 4.3 Current list kinds

`ShoppingListKind` contains:

- `weekly`
- `completed`
- `recent`

These are not three Product states. They are list classifications.

The startup backfill ensures default shells exist. Current shopping completion does not populate Completed or Recent, and finishing a session does not move entries between them. Because the Shopping UI treats the list chips generically, a user can select these shells and manually add/check entries, even though their names imply system-managed historical projections. Their semantics are therefore undefined and internally inconsistent.

### 4.4 Current Product states - real implementation

| Candidate state | Exists now? | Actual implementation |
|---|---:|---|
| Library only | Yes, derived | Active Product with no entry in the selected list |
| In Shopping | Yes, per list | Active Product with a `ShoppingListEntry` for the selected list |
| Shopping plan | Yes, derived/transient | Needed entry's compatibility item included in current `ShoppingPlan` |
| Recommended store | Yes, derived/transient | Store selected or recommended for a plan/session; not Product state |
| Purchased | No | No Product or list-entry purchase state and no purchase event |
| Collected | Yes, session-local | ShoppingItem ID in `ShoppingSession.collectedItemIDs` |
| Checked | Yes, per list | `ShoppingListEntry.isChecked == true` |
| Completed | Yes, but ambiguous | `ShoppingItem.isCompleted == true`; also a list kind; neither means confirmed purchase |
| Archived | No | No model, action, filter, or UI |
| Removed from library | Yes | `Product.deletedAt != nil`; hidden from normal Product queries |
| Restored | Yes as a transition | `deletedAt` cleared by catalog re-add or recognized barcode upsert |
| Physically deleted | Possible, not normal Product UX | Legacy/test/recovery paths can leave missing records |
| Unknown | Not modeled as a normal state | Invalid raw values, missing relationships, absent catalog data, or unresolved legacy links use fallback/repair behavior |

### 4.5 What "permanent Products" means today

The product principle is implemented as a durable library record, not literal immortality:

- Products remain after removal from Shopping.
- Shopping completion does not delete Products.
- Product Library removal now creates a tombstone.
- Product Knowledge and Product History survive library removal.
- Explicit re-add can restore the same Product identity.

The current swipe action is still presented as deletion and provides no recovery UI, so the durable behavior is more sophisticated than the visible UX.

---

## 5. Current Product Lifecycle

### 5.1 Creation and acquisition

#### Manual Add Product

```text
No user Product
  -> create Product
  -> active in Product Library
  -> no ShoppingListEntry
  -> no ShoppingItem
  -> no plan inclusion
```

Manual creation is library-only. Duplicate manual names are allowed. The view signals a shopping-list revision and marks the plan stale even though no list membership changed.

#### Catalog selection

```text
No matching catalog-linked Product
  -> create active Product with stable catalog ID and snapshots

Existing active Product with same catalog ID
  -> return "already in library"
  -> no Product mutation

Existing removed Product with same catalog ID
  -> restore same Product UUID
  -> refresh approved snapshots
  -> no automatic Shopping membership
```

Catalog selection deduplicates by stable catalog ID, not by name.

#### Barcode/camera/AI recognition

```text
Strong match to active unlinked Product
  -> refresh Product attributes

Strong barcode match to removed unlinked Product
  -> restore Product
  -> refresh attributes

No match
  -> create active Product
```

The scanner status says "Saved to Product Library" and closes. It does not add the Product to Shopping. The method name `addManualBarcodeProductToShoppingList` is inconsistent with its actual library-only behavior.

### 5.2 Adding to Shopping

For one selected list:

```text
Entry absent
  -> create ShoppingListEntry(isChecked: false, quantity: 1)
  -> create or reopen a compatibility ShoppingItem
  -> set ShoppingItem.isCompleted = false

Entry already present and checked
  -> retain the same entry
  -> set isChecked = false
  -> reopen the compatibility item

Entry already present and needed
  -> retain and refresh it
```

The Product remains active in the library. Adding to Shopping does not create a new Product.

### 5.3 Checking a Shopping entry

```text
needed <-> checked
```

The authoritative per-list transition is `ShoppingListEntry.isChecked.toggle()`. The view also writes:

```text
ShoppingItem.isCompleted = ShoppingListEntry.isChecked
```

Because multiple list entries may reference the same compatibility item, this mirrors a scoped state into an unscoped global boolean.

### 5.4 Removing from Shopping

```text
Entry present
  -> delete the selected list's entry
  -> mark its compatibility ShoppingItem completed
  -> keep Product active in library
```

This is a membership removal, not Product deletion and not confirmed purchase. If the compatibility item is shared with another list, the second list entry remains while downstream legacy consumers may treat it as completed.

### 5.5 Start Fresh

The legacy review's Start Fresh action:

- deletes all Weekly Shopping entries;
- marks their linked compatibility items completed;
- preserves Products;
- preserves other list entries;
- marks the plan stale.

### 5.6 Plan generation

Plan generation:

- reads the selected list;
- excludes checked entries;
- requires a compatibility ShoppingItem;
- resolves product intent;
- discovers and ranks stores;
- creates a runtime `ShoppingPlan`;
- does not mutate Product, list membership, checked state, or purchase history.

Plan states are:

```text
idle
  -> generating(preparing/finding/matching/calculating/ranking)
  -> ready
  -> failed

ready/failed/idle
  -> stale when relevant shopping data changes

any
  -> idle when cleared
```

The plan itself is not persisted. A selected store is view/runtime state until captured into a session.

### 5.7 Starting and running a Shopping Session

Starting Shopping:

- requires a ready, current plan and a selected store;
- collects globally incomplete compatibility item IDs from the selected list adapter;
- creates a persistent active session if none exists;
- returns an existing active session unchanged if one already exists;
- stores list and selected-store identity on a new session.

An existing active session is resumed even if the new request was for a different list, store, or item set. This prevents duplicate sessions but can silently ignore the user's newer context.

Within the session:

```text
remaining <-> collected
```

Collection writes only `ShoppingSession.collectedItemIDs`. It does not write:

- `ShoppingListEntry.isChecked`;
- `ShoppingItem.isCompleted`;
- Completed/Recent lists;
- `ProductHistory.lastCompletedDate`;
- a purchase event.

### 5.8 Finishing Shopping

Finish Shopping currently:

- sets `ShoppingSession.isActive = false`;
- sets `finishedAt`;
- saves;
- returns to the Shopping workspace;
- clears the transient plan from the Shopping workspace path.

It does not:

- mark collected list entries resolved;
- distinguish purchased, unavailable, skipped, or already owned;
- reconcile uncollected items;
- remove any Shopping membership;
- populate Completed or Recent;
- update the compatibility completion flag;
- create purchase history;
- alter Product Library state.

The same shopping list can therefore remain needed immediately after the user finishes Shopping.

### 5.9 Product Library removal

Swipe-to-delete calls the Product Library deletion service:

```text
active Product
  -> Product.deletedAt = now
  -> remove entries from every list whose kind is weekly
  -> mark linked compatibility items completed
  -> retain completed/recent entries
  -> retain ProductHistory and ProductKnowledge
```

The Product disappears because all normal Product queries filter `deletedAt == nil`.

There is no:

- confirmation;
- undo;
- Recently Removed screen;
- explicit Restore action;
- explanation that historical references survive.

### 5.10 Restoration

Restoration exists but is not a visible lifecycle:

- Selecting the same catalog concept restores a removed catalog-linked Product.
- Recognizing a matching barcode can restore a removed unlinked Product.
- Startup repair does not restore tombstones.

Restoration does not recreate removed Weekly Shopping memberships. Historical Completed/Recent references remain as stored.

### 5.11 Catalog synchronization

Catalog lifecycle is independent:

- Active catalog records can be offered in search.
- Inactive records are excluded from new search results.
- A saved Product linked to a now-inactive/missing catalog record remains active, renderable from snapshots, and addable to Shopping.
- Catalog rename/category/icon changes do not silently mutate saved Product snapshots.
- Stable catalog replacement metadata can resolve identity.

Catalog synchronization does not change list membership, checked state, plan state, session state, or purchase history.

### 5.12 Migration and startup repair

Current schema V3 adds nullable `Product.deletedAt`.

Migration behavior:

- V1/V2 Products migrate as active (`deletedAt == nil`).
- Existing IDs, Product history, list entries, and catalog links are preserved.
- Migration does not infer catalog identity.

Startup repair:

- ensures Weekly, Completed, and Recent list shells;
- repairs legacy Product/entry/item relationships;
- may create a Product from an active, unlinked legacy item;
- does not create an active Product from completed/recent-only history;
- does not resurrect a tombstoned Product;
- removes Weekly entries tied to a tombstoned Product;
- is designed and tested to be idempotent.

### 5.13 Persistence failure recovery

On persistent-store open failure, startup can:

1. quarantine the existing store components;
2. create a new empty persistent store; or
3. if persistent recovery fails, use an in-memory fallback.

These are application data-availability modes, not Product states. The in-memory fallback is ephemeral and currently has no Product-state UX explaining that changes may not survive relaunch.

### 5.14 Saved-location parallel lifecycle

`LocationDetailView` can directly:

- create a standalone `ShoppingItem`;
- toggle its global `isCompleted`;
- physically delete it.

These actions bypass `Product`, `ShoppingListEntry`, selected-list revision signaling, and plan invalidation. Saved-location items are therefore a separate Product-like lifecycle with the same checkmark but different ownership.

---

## 6. Complete Current Transition Matrix

| # | Trigger | Source | Before | After | Persistent effects | UX feedback/current issue |
|---:|---|---|---|---|---|---|
| 1 | Manual Add Product | Products | No Product | Active Product | Product insert | Saves to library only; plan is still marked stale |
| 2 | Catalog Add, new ID | Add Product | No linked Product | Active linked Product | Product + snapshots | Clear already-present handling |
| 3 | Catalog Add, active ID | Add Product | Active linked Product | No change | None | "Already present" notice |
| 4 | Catalog Add, removed ID | Add Product | Tombstone | Active same UUID | Clears `deletedAt`, refreshes snapshots | Implicit restore, not described as restore |
| 5 | Recognized new Product | Scanner | No match | Active Product | Product + learned knowledge | Scanner closes |
| 6 | Recognized active match | Scanner | Active Product | Active refreshed Product | Attributes/knowledge updated | May reorder library by `updatedAt` |
| 7 | Recognized removed barcode | Scanner | Tombstone | Active same UUID | Clears `deletedAt`, refreshes | Implicit restore |
| 8 | Add to list, absent | Products/chooser | No entry | Needed entry | Entry + compatibility item | Product remains in library |
| 9 | Add to list, checked | Products/chooser | Checked entry | Needed entry | Entry and legacy flag reset | "Add" doubles as reopen |
| 10 | Check list row | Shopping | Needed entry | Checked entry | Entry true; legacy true | Checkmark means resolved/checked, not purchased |
| 11 | Uncheck list row | Shopping | Checked entry | Needed entry | Entry false; legacy false | Can globally reopen item for other consumers |
| 12 | Change quantity | Shopping | Quantity N | Quantity N +/- | Entry quantity | Plan marked stale |
| 13 | Remove from Shopping | Products/Shopping | Entry present | Entry absent | Entry deleted; legacy true | Product retained; no undo |
| 14 | Start Fresh | Startup review | Weekly entries | No Weekly entries | Deletes entries; legacy true | Preserves library |
| 15 | Generate Plan | Shopping | idle/stale/failed | generating | None | Staged progress |
| 16 | Plan succeeds | Shopping | generating | ready | None | Runtime only |
| 17 | Plan fails | Shopping | generating | failed | None | Retry UX |
| 18 | Relevant list mutation | Multiple | ready | stale | None | Correct for list mutations; overly broad for library-only add |
| 19 | Select store | Shopping | Recommendation | Committed view choice | Runtime only until session | Selected visual state |
| 20 | Start Shopping | Shopping | No active session | Active session | Session insert | Captures list/store/items |
| 21 | Start while active | Shopping/Home | Active session | Same active session | None | New requested context can be ignored |
| 22 | Collect item | Shopping Mode | Remaining | Collected | Session ID set | Does not resolve list entry |
| 23 | Undo collection | Shopping Mode | Collected | Remaining | Session ID removed | Session-local only |
| 24 | Finish Shopping | Shopping Mode | Active session | Finished session | `isActive=false`, `finishedAt` | No outcome reconciliation |
| 25 | Delete library Product | Products swipe | Active Product | Tombstone | `deletedAt`; weekly entries deleted | No confirmation/undo/restore UI |
| 26 | App relaunch | App lifecycle | Tombstone | Tombstone | Repair only | Correctly not resurrected |
| 27 | Catalog update | App/catalog | Linked Product | Same Product | No automatic Product mutation | Snapshot-stable |
| 28 | Catalog becomes inactive | Catalog | Linked Product | Same active/removed library state | None | Inactive not offered for new search |
| 29 | Schema V1/V2 -> V3 | Migration | Product without deletion field | Active Product | `deletedAt=nil` | Data-preserving |
| 30 | Repair active unlinked legacy item | Startup | No Product | Active Product | Product insert/link repair | Compatibility recovery |
| 31 | Repair historical-only missing Product | Startup | Missing Product | Still missing Product | No insert | Avoids resurrecting history |
| 32 | Toggle saved-location item | Location Detail | Legacy incomplete/completed | Opposite global flag | ShoppingItem only | Parallel lifecycle, no plan revision |
| 33 | Delete saved-location item | Location Detail | Location item exists | Physically absent | ShoppingItem delete | Not Product Library deletion |
| 34 | Notification tap | Notification/Map | Any Product states | No Product mutation | Navigation context only | Can select list/map context |
| 35 | Store recovery | App lifecycle | Persistent graph unavailable | Empty persistent or memory graph | Store mode changes | No durable-state warning in Product UX |

---

## 7. Current User Actions by Surface

### 7.1 Products

| Action | Actual effect | Consistency assessment |
|---|---|---|
| Add Product | Creates active Product only | Correct permanent-library separation |
| Scan | Saves/restores Product only | Correct in principle; next destination is not offered |
| Search/filter | Filters active library Products | Does not search removed Products |
| Add to Shopping | Creates/reopens entry in selected list | Correct action, but selected list context is understated |
| Remove from Shopping | Deletes selected-list entry | Correct scope in service; legacy global side effect is incorrect |
| Change image | Mutates Product and compatibility snapshots | Product edit is limited to image only |
| Swipe delete | Tombstones Product and removes Weekly membership | Destructive semantics are under-explained |
| In Shopping / Library Only filter | Derived from selected list membership | "In Shopping" is not global but appears global |

### 7.2 Shopping

| Action | Actual effect | Consistency assessment |
|---|---|---|
| Switch list chip | Changes selected list | Completed/Recent semantics are not enforced |
| Choose Products | Adds pending selected Products | Existing entries cannot be removed in this chooser |
| Select All | Selects all Products not already in list | Clear All clears only pending selection |
| Check/needed toggle | Changes per-entry state and global legacy state | Split authority |
| Quantity +/- | Changes entry | Planner currently remains item-count, not quantity-weighted |
| Trash | Removes membership | Separate from checked state, which is good |
| Generate Plan | Builds plan from unchecked adaptable entries | Entries without compatibility items can disappear |
| Choose recommended store | Changes runtime selection | Not a Product state |
| View Map | Shares current plan | Correct when plan exists |
| Start Shopping | Creates/resumes session | Context conflict possible with existing session |
| Collect/uncollect | Changes session-local state | Not synchronized with list state by design or finish |
| Finish Shopping | Closes session | Lifecycle is incomplete |

### 7.3 Home

| Action | Actual effect | Consistency assessment |
|---|---|---|
| Primary CTA | Products when empty, Shopping when needed, resume when active | Reasonable routing |
| Tap a shopping-list card | Opens Products for every card | Does not select/open the tapped list; navigation friction |
| Recent Product plus | Opens Products | Icon implies direct add but action only navigates |
| Recommended store | Opens Shopping | Read-only plan projection |
| Nearby opportunity | Opens Map | No Product state mutation |

### 7.4 Map and saved locations

| Action | Actual effect | Consistency assessment |
|---|---|---|
| View plan stores/items | Uses shared plan when available | Correct plan projection |
| Default Map items | Uses all globally incomplete compatibility items | Not selected-list scoped |
| Tap notification store | Focuses store and item names | No mutation; item/list payload can disagree |
| Navigate | Opens Apple Maps | No Product state mutation |
| Open saved location items | Opens direct legacy item list | Bypasses Product/List architecture |
| Add/toggle/delete location item | Mutates legacy ShoppingItem directly | Conflicting lifecycle owner |

### 7.5 Notifications

Notifications:

- are generated from globally incomplete compatibility items;
- may carry the currently selected shopping list ID;
- carry ShoppingItem IDs and display names;
- open Map;
- have no complete/check/add/remove action.

The notification item set is not guaranteed to be the actual needed entries in the list named by the payload.

### 7.6 Scanner and future AI

Current scanner actions save to the Product Library. They do not add to Shopping.

Current AI recognition:

- proposes Product data;
- requires user confirmation;
- saves through Product acquisition;
- does not own shopping state.

Future fridge/pantry/wardrobe scanning is described in the roadmap. Any future AI action must be expressed as a proposed domain command such as "Add these Products to Weekly Shopping," not as direct mutation of a generic Product state.

---

## 8. Visual Indicator Audit

### 8.1 Indicator meanings today

| Surface | Visual | Actual meaning | Obvious? | Consistent? |
|---|---|---|---:|---:|
| Product card | `checkmark.circle.fill` | Product is a member of selected list | Partly, because text exists | No |
| Product card | empty circle | Product is not in selected list | No; resembles incomplete task | No |
| Product card | `cart.badge.checkmark` | In selected list | More specific | Duplicates the adjacent circle |
| Product chooser | checked square | Pending selection **or already in list** | No; two meanings | No |
| Shopping list row | filled check circle | Entry is checked/resolved | Partly | No |
| Shopping list row | empty circle | Entry is needed | Familiar but unlabeled visually | No |
| Shopping Mode | filled check circle | Item collected in this session | Partly | No |
| Saved-location row | checked square | Global legacy item completed | No scope shown | No |
| Add Product summary | check circle + "Selected" | Catalog/custom draft selected | Yes, because labeled | Acceptable locally |
| Camera | check seal/circle | Barcode confirmed or Product recognized | Contextual | Acceptable locally |
| Completion screens/buttons | check circle | Operation/session success | Contextual | Acceptable locally |

### 8.2 The checkmark problem

The checkmark is not one problem; it is one symptom of several unmodeled scopes:

- membership;
- chooser selection;
- list resolution;
- session collection;
- recognition success;
- general operation success.

The Products card is the most serious violation because the approved Product Specification explicitly says:

- never show shopping/completion checkmarks inside the Product Library;
- a Product Card never carries a completion checkbox;
- collection state belongs to the Shopping Mode item row.

The current Product card also shows both a membership label/cart icon and a circular checkmark, so the ambiguous symbol is redundant.

### 8.3 Color and accessibility

Some current controls provide good accessibility labels:

- Shopping row: "Mark X needed/checked."
- Session row: "Mark X remaining/collected."
- Product action: "Add/Remove X from Shopping."

However:

- hidden decorative Product-card checkmarks still shape sighted interpretation;
- "In Shopping" does not announce which list;
- chooser `accessibilityValue` says "Selected" even when the real state is "Already in Shopping";
- saved-location squares do not establish list/session scope;
- most user-facing state copy is hardcoded English and does not meet Hebrew parity.

### 8.4 Icon quality and input alignment

Catalog icons are semantic category/subcategory mappings with a generic fallback. They are not Product-state indicators.

Catalog icon-quality feedback therefore has a different primary root cause:

- taxonomy-to-icon specificity;
- fallback frequency;
- visual quality of the platform mapping;
- inconsistent presentation between catalog-backed and custom Products.

Input alignment primarily belongs to layout, RTL, Dynamic Type, and form-control implementation. It is not caused by Product lifecycle state. It becomes more visible when controls also carry ambiguous selection semantics.

The Product Search UX Contract already establishes the correct standard:

- semantic icon at visual leading edge;
- natural text alignment;
- proper RTL mirroring;
- icon decorative to assistive technology;
- selection communicated by summary and text, not icon/color alone.

---

## 9. Cross-Screen Consistency

### 9.1 Same question, different answer

| Question | Products | Shopping | Home | Map | Notifications |
|---|---|---|---|---|---|
| Is Product in the selected list? | Yes, derived from entry existence | Yes | Indirectly | Usually no | Payload implies a list but input is global |
| Is the entry still needed? | Not shown | `!entry.isChecked` | Entry and legacy flag must both be open | Global `!item.isCompleted` | Global `!item.isCompleted` |
| Was it collected this trip? | Not shown | Session-local | Session count only | Not shown | Not shown |
| Was it purchased? | Not available | Not available | Not available | Not available | Not available |
| Is Product removed from library? | Hidden by query | Hidden Product may still have historical entry | Hidden | Active Products queried; legacy copies may remain | Legacy copy may remain |
| Which list is the state about? | Selected list, weakly surfaced | Selected list | Selected list for counts | Often all compatibility items | Selected-list ID plus potentially global items |
| Is the plan current? | Membership actions stale it | Explicit idle/generating/ready/failed/stale | Shared state | Shared plan when applied | Not encoded |

### 9.2 Products versus Shopping

Products correctly owns Product acquisition and library management. Shopping correctly owns list entries and sessions. The inconsistency is that Products visually renders selected-list membership as a task checkbox, while Shopping uses the same visual for list resolution and collection.

The Product Library also uses the unqualified phrases:

- "In Shopping"
- "Already in Shopping"
- "Remove from Shopping"

These actions are actually relative to one selected list. If the Product is in another list but not the selected list, it is shown as Library Only.

### 9.3 Shopping versus Map

Shopping plans from selected-list, unchecked entries. Map without an applied shared plan uses all globally incomplete compatibility items. Therefore:

- Shopping can show Product A as needed while Map excludes it because its compatibility item was completed elsewhere.
- Map can show Product B even though it is not a member of the selected list.
- A ready shared plan improves consistency temporarily, but normal Map state remains legacy-global.

### 9.4 Shopping versus Notifications

The geofence refresh receives all `ShoppingItem` records and filters `!isCompleted`. It also receives the selected shopping list ID as payload context.

This can produce:

```text
Notification label/context: Weekly Shopping
Notification Product IDs: globally incomplete items from multiple/no lists
```

The notification deep link is read-only and does not corrupt state, but it can present the wrong shopping intent.

### 9.5 Shopping list versus Shopping Session

The list has needed/checked. The session has remaining/collected. There is no defined bridge at session finish.

This produces three user-visible truths:

1. A Product may look collected inside Shopping Mode.
2. The same entry may still look needed in the Shopping list.
3. The compatibility item may still be incomplete for Map/notifications.

### 9.6 Home versus list navigation

Home calculates list counts from entries, but tapping a specific list card opens Products and does not:

- select the tapped list;
- open Shopping;
- focus that list;
- explain whether the card is editable or historical.

Recent Product cards display a plus affordance that only navigates to Products. These are navigation-contract inconsistencies rather than data corruption, but they amplify workflow confusion.

### 9.7 Catalog and scanner consistency

Manual Add, catalog selection, barcode, and AI all converge on Product Library persistence. This is a strong foundation.

The inconsistency is in action language and continuation:

- "Save Product" and "Add Product" both mean library save.
- The scanner contains a method named as if it adds to Shopping but does not.
- After scan, no explicit "Add to Shopping" continuation is offered.
- Catalog selection has an explicit selected summary; the camera uses recognition checkmarks that are visually similar but represent acquisition confidence/success.

---

## 10. Beta Feedback Analysis

### 10.1 Evidence status

`BETA_BACKLOG.md` directly documents:

- WT-003B: unresolved shopping-list selector UX.
- WT-003C: Product row readability and control density.
- WT-005: remove circular indicators from the Shopping Product list.
- WT-010: first-time workflow guidance.
- WT-011A: Add Product input focus, disabled state, validation, and persistence reliability.

The Beta Feedback table itself is empty. The WT-030A request additionally names these known observations:

- meaning of the checkmark;
- removing Products from Shopping;
- Product workflow confusion;
- scan workflow;
- navigation friction;
- catalog icon quality;
- input alignment.

The following analysis does not invent tester quotes or attribution.

### 10.2 Meaning of the checkmark

**Observed behavior:** The same family of circle/square checkmarks means membership, pending selection, checked, collected, recognized, or success.

**Root cause:** Visual semantics were assigned at view level without a shared state vocabulary. Several underlying states are also duplicated or unsynchronized.

**Severity:** High UX risk; medium data-integrity signal.

**Decision:** A checkmark may be used only for an explicitly labeled local meaning. It is prohibited as a Product Library membership decoration.

### 10.3 Removing Products from Shopping

**Observed behavior:** Products and Shopping both provide removal. The operation keeps the Product in the library but also sets a global compatibility item completed.

**Root cause:** The user action is correctly scoped, but its compatibility side effect is not. The language also omits the selected list name.

**Severity:** Critical cross-list correctness risk.

**Decision:** Remove from Shopping must remove only one list membership. It must not change another list, a session outcome, Product Library membership, purchase history, Map state, or notifications except through the resulting selected-list projection.

### 10.4 Product workflow confusion

**Observed behavior:** The user moves among Products, chooser, Shopping list, planner, Map, and Shopping Mode with several similar controls but no stable state vocabulary.

**Root cause:** The permanent Product, temporary list need, derived plan, and session execution are visually and architecturally blurred by the compatibility model.

**Severity:** High.

**Decision:** Every action must state both destination and scope. Examples: "Add to Weekly Shopping," "Remove from Weekly Shopping," "Mark need resolved," and "Mark collected at this store."

### 10.5 Scan workflow

**Observed behavior:** Scan saves to the library and exits. The user must navigate and take a separate action to add the Product to Shopping. Method and button names do not consistently describe that destination.

**Root cause:** Product acquisition and shopping intent are correctly separate in data, but the UX does not provide an explicit continuation between them.

**Severity:** Medium to high depending on primary scan use case.

**Decision:** Acquisition must remain library-safe. The post-confirmation destination policy is an open Product decision; it must never be implicit or mislabeled.

### 10.6 Navigation friction

**Observed behavior:** Home list cards open Products, Recent plus opens Products rather than adding, scanner closes without a next action, and notification taps open Map even when the user's likely goal is the active list/session.

**Root cause:** Navigation actions are keyed to tabs rather than the domain object and intended task.

**Severity:** Medium.

**Decision:** Navigation must carry list/session context and land at the surface that owns the intended action.

### 10.7 Catalog icon quality

**Observed behavior:** Catalog-backed Products use semantic resolution, custom Products often use a generic shipping box, and specificity depends on taxonomy/subcategory mapping.

**Root cause:** Primarily catalog/presentation quality, not Product-state architecture. The absence of a consistent Product-card contract makes variation more noticeable.

**Severity:** Medium presentation risk; low state-integrity risk.

**Decision:** Keep icon semantics separate from state semantics. Never use a category icon to imply list membership or completion.

### 10.8 Input alignment

**Observed behavior:** Alignment concerns interact with icons, selection controls, keyboard behavior, Hebrew RTL, and Dynamic Type.

**Root cause:** Primarily form/layout implementation. It shares a secondary cause with checkmark confusion when extra state controls compete for row width.

**Severity:** Medium accessibility/localization risk.

**Decision:** Apply the Product Search UX Contract's natural leading alignment and RTL rules. Removing nonessential state decorations reduces alignment pressure.

### 10.9 Shared root-cause map

| Feedback | Shared state/ownership root | Shared visual-vocabulary root | Separate presentation/data root |
|---|---:|---:|---:|
| Checkmark meaning | Yes | Yes | No |
| Remove from Shopping | Yes | Partly | No |
| Workflow confusion | Yes | Yes | Partly |
| Scan workflow | Yes, destination boundary | Partly | Partly |
| Navigation friction | Yes, context ownership | Partly | Partly |
| Catalog icon quality | No | Partly | Yes |
| Input alignment | No | Partly | Yes |

Most Product workflow complaints are not isolated screen defects. They are different manifestations of missing state scope and ownership. Catalog icon quality and input alignment require separate quality work even after the state architecture is corrected.

---

## 11. Current Inconsistencies and Architectural Limitations

### 11.1 Risk register

| ID | Severity | Finding | Consequence |
|---|---|---|---|
| PS-01 | Critical | Per-list `isChecked` is mirrored to shared `ShoppingItem.isCompleted` | One list can alter another list's planner/Map/notification visibility |
| PS-02 | Critical | Finish Shopping has no outcome reconciliation | "Finished" trip can leave every list need open |
| PS-03 | Critical | Map/notifications use global legacy active items | Wrong Products can be associated with the selected list/store |
| PS-04 | High | Product Library checkmark represents list membership | Violates approved Product-card rule and resembles completion |
| PS-05 | High | No explicit restore UX for durable tombstones | Delete appears irreversible while re-add can silently restore |
| PS-06 | High | Completed and Recent are named historical lists without historical transitions | Users see categories that the lifecycle does not produce |
| PS-07 | High | Existing active session can ignore new list/store/item request | User intent and resumed context can diverge |
| PS-08 | High | Plan depends on compatibility items, not native entries | Valid entries can be omitted when adapter links are missing |
| PS-09 | High | Saved-location items bypass Product/list repositories | Parallel Product lifecycle and stale plans |
| PS-10 | Medium | Library-only mutation marks plan stale | False invalidation and unclear dependency model |
| PS-11 | Medium | "In Shopping" is selected-list scoped but sounds global | Cross-list misunderstanding |
| PS-12 | Medium | Chooser merges "selected now" and "already present" visuals | Clear All and checkbox meanings are surprising |
| PS-13 | Medium | No purchase event or outcome reason | History, AI learning, and Completed semantics cannot be trustworthy |
| PS-14 | Medium | Plan is transient and session snapshot is item-ID based | Recovery loses recommendation detail and product context can age |
| PS-15 | Medium | Degraded in-memory persistence is not surfaced | User may believe ephemeral Product actions are durable |
| PS-16 | Medium | State copy is largely hardcoded English | Hebrew parity and Android shared semantics are blocked |
| PS-17 | Low | Product card duplicates membership text, cart badge, and check circle | Visual noise and competing signals |

### 11.2 Multiple representations

The same real-world Product can appear as:

- a `Product`;
- one or more `ShoppingListEntry` rows;
- one shared compatibility `ShoppingItem`;
- a Product History key;
- a Product Knowledge record;
- a catalog ProductID;
- a transient ProductCandidate;
- a session item ID;
- a saved-location standalone ShoppingItem.

Stable identity work has improved catalog linking, but state ownership remains fragmented.

### 11.3 Missing repository/use-case boundary

Views and services directly query and mutate SwiftData in several places. There is no single Product Lifecycle repository coordinating:

- library removal/restoration;
- list membership and resolution;
- session outcomes;
- notification/Map projections;
- cross-screen revision events.

The existing service layer provides useful operations, but alternate direct writers remain.

### 11.4 Boolean compression

Two booleans currently compress several meanings:

- `ShoppingListEntry.isChecked`
- `ShoppingItem.isCompleted`

Neither records why a need is no longer open. Possible meanings include:

- purchased;
- already owned;
- intentionally skipped;
- unavailable;
- removed from the list;
- completed at a saved location;
- legacy migration cleanup.

These meanings drive different future recommendations and must not be learned as equivalent.

### 11.5 Historical ambiguity

`ProductHistory.lastCompletedDate` exists, but current session finish does not establish a trustworthy completed/purchased transition. Completed and Recent list shells are not projections of history. Future AI cannot safely infer replenishment intervals from a generic check or session closure.

### 11.6 Error and unknown-state handling

Unknown and missing data are mostly repaired or skipped:

- missing compatibility item can omit an entry from planning;
- missing Product relationship can leave a historical entry;
- invalid list kind falls back to Weekly;
- invalid catalog raw ID is treated as corrupt/unresolved;
- missing catalog record retains Product snapshots.

This is resilient, but invisible omission is not an acceptable normal Product state. Official projections need explicit diagnostics and user-safe unavailable presentation when repair cannot resolve an active need.

---

## 12. Complete Design Alternatives

### Alternative A - Preserve current model and standardize labels

#### Description

Keep:

- `Product.deletedAt`;
- `ShoppingListEntry.isChecked`;
- shared `ShoppingItem.isCompleted`;
- current session collected IDs;
- current Map/notification inputs.

Change only labels, icons, accessibility copy, and screen navigation.

#### Advantages

- Lowest schema and migration complexity.
- Fastest visual improvement.
- Minimal disruption to planner, Map, geofence, and session code.
- Existing tests remain mostly applicable.

#### Disadvantages

- Does not resolve cross-list corruption through the shared compatibility flag.
- Does not define Finish Shopping outcomes.
- Leaves Map and notifications on a different state source.
- Leaves saved-location items as a parallel lifecycle.
- Future Android and AI would inherit iOS compatibility debt.
- Visual clarity would be fragile because underlying contradictions remain.

#### Migration complexity

Low.

#### Future scalability

Poor. Multiple lists, shared lists, AI, purchase history, and Android parity magnify the split authority.

#### Decision

Rejected. This is a cosmetic mitigation, not an official Product State architecture.

---

### Alternative B - One flat `ProductState` enum

#### Description

Add one state to Product, for example:

```text
libraryOnly
inShopping
planned
purchased
archived
deleted
```

Every screen would read this state.

#### Advantages

- Appears simple to explain.
- Easy to show one badge/filter.
- A single field seems easy to synchronize.
- Straightforward for basic analytics.

#### Disadvantages

- States are not mutually exclusive.
- One Product can be in multiple lists with different entry states.
- Planned and recommended are derived for one list revision, not durable Product properties.
- Purchased is an event that can occur repeatedly.
- Collected is session-local and reversible during a trip.
- Catalog lifecycle is independent.
- Transitions would overwrite valid concurrent facts.
- Shared/family lists and Android sync would create last-write-wins data loss.

#### Migration complexity

High and destructive because existing combinations must be collapsed arbitrarily.

#### Future scalability

Very poor. The enum grows combinatorially or becomes inaccurate.

#### Decision

Rejected. It models the UI shorthand instead of the domain.

---

### Alternative C - Orthogonal Product Lifecycle

#### Description

Use separate authoritative aggregates:

1. Product identity and attributes.
2. User-library membership.
3. Per-list shopping entry.
4. List revision and plan projection.
5. Shopping Session and per-session line outcomes.
6. Purchase/usage history events.
7. Independent catalog lifecycle.

All screens consume scoped projections from these owners. Compatibility flags are not authoritative.

#### Advantages

- Correct for multiple lists and repeated purchases.
- Matches the approved permanent Product / temporary list / intelligent plan mental model.
- Makes Finish Shopping behavior definable and testable.
- Gives Map and notifications the same selected-list/session item set.
- Supports shared lists, sync, AI, analytics, and Android parity.
- Makes each checkmark/label correspond to one scope.
- Allows Product Library deletion/restoration without erasing knowledge or history.

#### Disadvantages

- Requires coordinated migration of all legacy consumers.
- Requires explicit Product decisions for entry resolution and session outcomes.
- More domain types and projections than a flat enum.
- Must prevent direct view writes and enforce repository/use-case boundaries.

#### Migration complexity

High but bounded. Existing Product IDs, catalog IDs, entry IDs, list IDs, session IDs, tombstones, and history can be preserved. Ambiguous legacy completion values require conservative mapping and an exception report.

#### Future scalability

Strong.

#### Decision

**Approved.**

---

### Alternative D - Full event sourcing

#### Description

Store all Product lifecycle changes as append-only events and derive library, list, plan, session, and history projections.

#### Advantages

- Complete audit history.
- Natural conflict resolution opportunities for sync/shared lists.
- Excellent explainability for AI and analytics.
- Projections can be rebuilt.

#### Disadvantages

- Substantial implementation, migration, storage, tooling, and debugging complexity.
- Requires event versioning and replay governance.
- Existing local-first SwiftData architecture is not organized around event streams.
- Product team has not defined retention/privacy rules for a permanent event ledger.
- Excessive operational complexity for current maturity.

#### Migration complexity

Very high.

#### Future scalability

Strong technically, but costly operationally.

#### Decision

Rejected as the current standard. The recommended architecture may use append-only outcome/history events without event-sourcing the entire application.

### 12.5 Comparison

| Criterion | A: Labels only | B: Flat enum | C: Orthogonal | D: Event sourced |
|---|---:|---:|---:|---:|
| Correct with multiple lists | No | No | Yes | Yes |
| Correct with repeated purchases | No | No | Yes | Yes |
| Resolves Map/notification drift | No | Only superficially | Yes | Yes |
| Preserves Product permanence | Partly | Risky | Yes | Yes |
| Migration risk | Low | High | High | Very high |
| UX clarity ceiling | Medium | Medium | High | High |
| Android parity | Weak | Weak | Strong | Strong |
| AI workflow fit | Weak | Weak | Strong | Strong |
| Current product fit | Poor | Poor | **Best** | Premature |

---

## 13. Recommended Official Architecture

### 13.1 Architectural rule

There is no single global Product State. The official Product State is a composite projection of independent, scoped lifecycles.

```text
Product identity
  + Library membership
  + List entry state (for a named list)
  + Plan inclusion (for a list revision)
  + Session outcome (for a named session)
  + Historical events
  + Catalog status
```

Every state-bearing value must answer:

- Who owns it?
- What is its scope?
- Is it authoritative or derived?
- Is it durable, transient, or historical?
- Which action may change it?

### 13.2 Aggregate 1 - Product Identity

**Purpose:** Stable identity and reusable attributes.

**Owns:**

- user Product UUID;
- optional canonical catalog ProductID;
- display snapshots and user overrides;
- barcode/provider observations through the appropriate knowledge boundary;
- semantic icon/category references;
- timestamps and provenance.

**Does not own:**

- in Shopping;
- checked;
- planned;
- recommended store;
- collected;
- purchased;
- list quantity;
- active session.

The current user Product UUID remains the relationship identity for user-owned state. Catalog ProductID remains a separate stable knowledge reference.

### 13.3 Aggregate 2 - User Library Membership

Official states:

```text
active
removed(removedAt)
```

Rules:

- Active appears in the Product Library.
- Removed is hidden from normal library/search selection but retained as a tombstone.
- Remove does not erase Product Knowledge, usage history, purchase events, or historical list/session references.
- Restore reactivates the same user Product identity.
- Startup repair and catalog synchronization never restore a Product implicitly.
- A user-initiated acquisition flow may restore only with explicit, visible confirmation.
- "Archived" is not part of the approved state set until its distinct user value and retention behavior are decided.
- Physical erasure is a privacy/data-management operation, not ordinary Product Library removal.

### 13.4 Aggregate 3 - Shopping List

The list owns:

- stable list ID;
- title and user-visible purpose;
- lifecycle such as active/closed if later approved;
- revision number or equivalent deterministic content revision;
- entry ordering.

List kind must not imply behavior that does not exist. Weekly, Completed, and Recent must become either:

- explicitly defined user lists; or
- system-managed projections with exclusive writers.

They cannot remain generic editable lists with historical names.

### 13.5 Aggregate 4 - Shopping List Entry

Identity:

```text
(listID, productID)
```

There must be at most one current membership per Product per list.

Official entry lifecycle:

```text
absent
needed
resolved(reason, resolvedAt)
```

Candidate resolution reasons that require Product approval include:

- purchased;
- alreadyHave;
- skipped;
- noLongerNeeded;
- other.

Until the reason taxonomy is approved, the architecture must preserve an explicit unresolved/needed state and must not translate a generic boolean into "purchased."

Entry owns:

- membership;
- quantity/unit;
- notes;
- sort order;
- needed/resolved state;
- resolution reason and time when approved.

Entry does not own Product Library membership or session collection.

Removing from Shopping transitions entry to absent for one list only. It does not mark another list or a Product globally completed.

### 13.6 Aggregate 5 - Shopping Plan

The plan is a rebuildable projection keyed by:

- list ID;
- list revision;
- included needed entry IDs;
- generation timestamp;
- ranking/catalog/store input revision as needed.

Official lifecycle:

```text
idle
generating(stage)
ready
failed
stale
```

Rules:

- A plan never changes Product Library or list-entry state.
- A plan becomes stale only when one of its declared inputs changes.
- A library-only Product addition is not a plan input and must not stale a plan.
- Recommended store is derived plan data.
- When a Shopping Session starts, the chosen plan/store/item snapshot needed for recovery becomes session context.
- A plan may be cached or persisted, but it is not the source of truth for list membership.

### 13.7 Aggregate 6 - Shopping Session

Official session lifecycle:

```text
active
finished
abandoned
```

`abandoned` requires UX/policy approval before use but must be distinguishable from a successful finish.

The session captures:

- source list ID and revision;
- chosen plan ID/revision when present;
- selected store/route snapshot;
- session lines keyed to Product and source entry;
- started/finished timestamps.

Official session-line lifecycle:

```text
remaining
collected
unavailable
skipped
carriedForward
```

The exact allowed outcomes and finish policy remain Product decisions, but `collected` cannot be the only recorded distinction if Finish is allowed with remaining items.

Rules:

- Collection is session-local while the session is active.
- Starting with an existing active session must explicitly resume it or ask the user to end/switch; it must not silently ignore a new context.
- Finish must reconcile every session line in one domain transaction.
- Collected must not automatically mean paid/purchased unless the Product decision explicitly defines that rule.
- Unavailable/remaining items must not disappear silently.

### 13.8 Aggregate 7 - Purchase and Usage History

Purchase is historical and repeatable.

The official architecture uses an event/outcome record, not `Product.state = purchased`.

Minimum conceptual fields:

- event ID;
- Product ID;
- source list-entry ID when present;
- session ID when present;
- store ID/snapshot when known;
- quantity/unit;
- outcome/reason;
- occurredAt;
- provenance (user/session/import/AI-confirmed).

Usage aggregates such as frequency and replenishment interval are derived from trustworthy events. A generic checked boolean or deleted compatibility item is not a purchase event.

### 13.9 Aggregate 8 - Catalog Lifecycle

Official catalog states:

```text
active
inactive
replaced(redirect)
missing/unavailable
```

Rules:

- Catalog status affects discovery and current metadata.
- It never deletes or removes a user's Product.
- Saved snapshots remain usable offline or after catalog deactivation.
- Redirect resolution preserves user Product UUID and history.
- Catalog icon/category changes are metadata changes, not Product-state transitions.

### 13.10 Projections for screens

Screens consume explicit projections:

| Projection | Required scope | Consumers |
|---|---|---|
| Product Library card | Product + library state | Products, Home recent |
| List membership action | Product + named list | Products action sheet, chooser |
| Shopping list row | Entry + Product display | Shopping |
| Plan item/store | List revision + plan | Shopping, Map |
| Active session line | Session + Product snapshot | Shopping Mode, Home resume |
| Notification opportunity | Named list/session + needed entry IDs | Notifications, Map deep link |
| Purchase/history row | Historical event + Product snapshot | Future history/AI |

No screen may infer a scoped projection from global `ShoppingItem.isCompleted`.

### 13.11 Command ownership

All state mutations go through named domain actions:

- Add Product to Library.
- Remove Product from Library.
- Restore Product to Library.
- Add Product to List.
- Remove Product from List.
- Resolve/Reopen List Entry.
- Generate/Invalidate Plan.
- Start/Resume/Abandon Session.
- Collect/Reopen/Mark Unavailable/Skip Session Line.
- Finish Session and reconcile outcomes.

Views, Map, notifications, scanner adapters, and AI adapters do not write state fields directly.

### 13.12 Required invariants

1. Product identity contains no global shopping or purchase state.
2. Library removal never erases reusable knowledge/history.
3. At most one current list entry exists per `(listID, productID)`.
4. A transition in list A cannot mutate list B.
5. Plan inputs are exactly the needed entries in its source list revision.
6. Map and notification Product sets are projections of the same list/session source.
7. Session collection does not silently alter list state before finish.
8. Finish reconciles every session line or refuses to finish.
9. No Product becomes globally purchased.
10. Catalog inactive/missing does not remove a user Product.
11. Startup repair never changes a user tombstone to active.
12. Restoration preserves the original user Product ID.
13. Compatibility records, while they exist, are derived outputs only.
14. Unknown/missing active references are diagnosed and never silently treated as purchased/completed.
15. State transitions are atomic from the user's perspective.

### 13.13 Why this becomes the product standard

This architecture:

- directly implements permanent Products, temporary lists, and intelligent plans;
- remains correct for multiple lists and repeated shopping trips;
- provides a coherent completion model without claiming purchase;
- removes the root cause of Map/notification/list disagreement;
- gives each visual indicator one scoped meaning;
- supports local-first persistence, future sync, shared lists, Android, and AI;
- preserves existing stable Product/catalog identities and durable tombstones;
- makes behavior testable as explicit transition contracts.

### 13.14 Why the competing alternatives were rejected

- Labels-only leaves correctness defects beneath clearer copy.
- A flat enum cannot represent valid concurrent states.
- Full event sourcing offers benefits beyond the current need at disproportionate cost.

---

## 14. Official UX Representation Standard

### 14.1 Product Library

The Product Library represents durable Products, not tasks.

Required:

- No empty/filled completion circle on Product cards.
- No unlabeled checkmark for list membership.
- Product icon/photo communicates identity/category only.
- Adding to a list is an explicit action with the list name.
- If membership context is shown, it is text/action context such as "In Weekly Shopping," not a completion glyph.
- Removing from a list is never presented as deleting the Product.
- Removing from the library uses explicit destructive language and explains the effect on active list memberships and retained history.

The approved v1 Product Card principle remains binding: collection state belongs to Shopping Mode, not the library card.

### 14.2 Product chooser

The chooser has two distinct concepts:

1. Already a member of the named list.
2. Selected in the current, unsaved chooser operation.

Required representation:

- Existing membership: text/badge such as "Already in Weekly Shopping"; row is not a pending selection.
- Pending selection: standard checkbox semantics with "Selected"/"Not selected."
- Clear All affects pending selections only and says so if ambiguity remains.
- Existing membership cannot be visually merged with pending selection.
- Removal of existing membership is either a separate explicit action or unavailable with clear explanation.

### 14.3 Shopping list

The Shopping list represents needs for one named list.

Required:

- List name and scope remain visible.
- Membership removal uses a trash/remove action and explicit label.
- Need resolution is separate from membership removal.
- If the resolution control remains, it uses text or a labeled state pair such as "Needed" and "Resolved."
- A standalone circular indicator without an adjacent state label is not sufficient.
- "Resolved" must not be labeled "Purchased" until the reason/outcome contract is approved.
- Quantity is entry state and remains visually attached to the entry.
- Completed/Recent surfaces must not be shown as system history until they are real projections.

### 14.4 Shopping Plan

The Plan represents recommendations, not Product status.

Required:

- Show source list and whether the plan is current/stale.
- Use "Likely here," "Other items," and confidence language already approved.
- Never show "available," "100% match," or equivalent certainty without verified inventory.
- Store selection is labeled selection, not Product completion.
- Missing/unadaptable entries are disclosed; they are not silently omitted.

### 14.5 Shopping Mode

Shopping Mode is the only surface where the collection checkmark has collection semantics.

Required:

- Collected and Remaining are explicit text/accessibility values.
- The current store/session is visible.
- Unavailable/Skipped/Carry Forward outcomes receive distinct controls and labels if approved.
- Finish presents or enforces reconciliation for all remaining lines.
- A session success checkmark is a transient success symbol, not persisted Product status.

### 14.6 Map

Map represents the active plan, active session, or explicitly selected list context.

Required:

- Context source is visible when Product markers/items are shown.
- Product identity icons do not imply state.
- "Likely here" remains a recommendation label.
- Map does not directly toggle Product/list/session state unless it invokes the same scoped domain action as the owner surface.
- Saved-location standalone Product-like items must not remain a parallel writable lifecycle in the official architecture.

### 14.7 Notifications

Required:

- Every shopping notification is tied to a concrete list revision or active session snapshot.
- Product IDs/names in the notification are exactly from that source.
- Notification wording never implies purchase or verified availability.
- Tapping lands in the owning list/session/plan context.
- Notification actions, if later added, invoke domain commands and expose scope.

### 14.8 Scanner and AI

Required:

- Acquisition success says "Saved to Product Library" when that is the effect.
- "Add to Shopping" is used only when a named list membership will be created.
- A post-save continuation must be explicit.
- AI may propose actions but cannot silently add, remove, resolve, collect, purchase, archive, or delete.
- Catalog selection/AI recognition checkmarks remain local review-state indicators and are paired with "Selected" or "Recognized."

### 14.9 State visual vocabulary

| Meaning | Approved visual rule |
|---|---|
| Product identity/category | Product photo or semantic catalog icon |
| Library active | Default Product card; no status glyph required |
| Library removed | Dedicated removed-products surface with text and restore action |
| In named list | Cart/list badge with explicit list text, when context is necessary |
| Pending chooser selection | Square checkbox plus selected semantics |
| List need open | "Needed" text/state control |
| List need resolved | "Resolved" text; check may accompany but never stand alone |
| Session remaining | "Remaining" |
| Session collected | Collection check plus "Collected" |
| Session unavailable/skipped | Distinct icon and label; never a success check |
| Plan current/stale | Plan status text/badge |
| Recommended store | Store/recommendation treatment, not a Product badge |
| Operation success | Transient checkmark/toast |
| Catalog inactive/missing | Metadata notice only where actionable |

### 14.10 Accessibility standard

Every state control must expose:

- object name;
- scope;
- current state;
- action result.

Examples:

```text
Milk. In Weekly Shopping. Remove from Weekly Shopping.
Milk. Weekly Shopping. Needed. Mark resolved.
Milk. Shopping at Market A. Remaining. Mark collected.
```

Requirements:

- State is never conveyed by color or icon alone.
- Decorative category icons are hidden from assistive technology.
- Dynamic Type can wrap state labels without hiding the differentiator.
- RTL mirrors layout while preserving logical reading order.
- Touch targets are at least 44 by 44 points.
- Selected, disabled, destructive, and restored states use native semantics.

---

## 15. Official Target Transition Contract

### 15.1 Library transitions

| Command | Allowed before | Required after | Forbidden side effects |
|---|---|---|---|
| Add manual Product | No resolved Product | Active Product | No automatic list/session/purchase state |
| Save catalog Product | No same linked Product | Active linked Product | No name-based merge |
| Save existing active catalog Product | Active same ID | Same Product/no duplicate | No snapshot overwrite without explicit refresh |
| Remove from Library | Active | Removed tombstone | No history/knowledge erasure |
| Restore to Library | Removed | Active same identity | No silent list-membership recreation |
| Catalog deactivates | Active or removed | Same library state | No user Product deletion |
| Physical privacy erasure | Policy-authorized | Data removed/anonymized per policy | Must not masquerade as ordinary Remove |

### 15.2 List-entry transitions

| Command | Allowed before | Required after | Forbidden side effects |
|---|---|---|---|
| Add to named list | Absent | Needed entry | No other-list mutation |
| Add existing needed | Needed | Idempotent needed | No duplicate entry |
| Reopen resolved | Resolved | Needed | Resolution history retained per policy |
| Resolve need | Needed | Resolved with reason/time | No implicit Product purchase without reason |
| Remove from named list | Needed/resolved | Absent | No library removal, no other-list completion |
| Change quantity | Present | Same lifecycle, new quantity | No Product identity mutation |
| Remove Product from Library | Active Product + active entries | Product removed; active-entry policy applied atomically | Historical references retained |

### 15.3 Plan transitions

| Trigger | Required result |
|---|---|
| Generate for list revision R | Plan enters generating with exact input entry IDs |
| Generation succeeds | Ready plan records R and included/unresolved entries |
| Generation fails | Failed plan keeps list unchanged |
| Any declared plan input changes | Plan becomes stale |
| Library-only Product changes | No staleness unless the plan explicitly depends on that Product |
| Open Map | Same plan identity/context is projected |
| Start Session | Selected plan/store snapshot is captured in session |

### 15.4 Session transitions

| Command | Required result |
|---|---|
| Start with no active session | New active session for the requested list/store/snapshot |
| Start with active same context | Explicit resume |
| Start with active different context | Explicit user decision; never silently reuse |
| Mark collected | One session line becomes collected |
| Undo collected | Same line becomes remaining |
| Mark unavailable/skip/carry | Explicit distinct line outcome |
| Finish | Every line reconciled; list/history effects committed atomically |
| Abandon | Distinct from successful finish; progress retention follows approved policy |
| Relaunch | Exact active session and line outcomes resume |

### 15.5 Cross-screen projection rule

For a given selected list revision:

```text
Shopping needed entry IDs
  == Planner input entry IDs plus explicitly reported unresolved exclusions
  == Map shopping-context entry IDs
  == Notification opportunity entry IDs
```

An active session uses its frozen session-line snapshot instead of a mutable global item set.

---

## 16. Impact Analysis

### 16.1 UX

Positive impact:

- Removes checkmark ambiguity.
- Makes Products, list needs, plan, and collection visibly distinct.
- Makes remove/delete/finish outcomes predictable.
- Reduces navigation friction by carrying list/session context.
- Enables an honest restore experience.

Cost:

- More explicit labels and finish outcomes require careful hierarchy to avoid visual density.
- Users may need a one-time explanation when legacy checked/completed behavior changes.

### 16.2 Architecture

Positive impact:

- One authority per lifecycle.
- Removes cross-screen direct-write behavior.
- Planner, Map, notifications, and session consume native projections.
- Compatibility adapter becomes derivation only and can be retired.

Cost:

- All current legacy consumers must move together to preserve invariants.
- Domain command and projection boundaries become mandatory.

### 16.3 Persistence

Required effects:

- Preserve Product UUIDs, catalog IDs/snapshots, `deletedAt`, list IDs, entry IDs, quantities, ordering, sessions, and history.
- Represent explicit entry resolution and session-line outcomes.
- Persist enough session context for exact recovery.
- Treat plan as rebuildable while preserving session snapshots.
- Maintain tombstones for restore/sync.

Risk:

- Legacy `isCompleted` cannot be trusted as a purchase reason.
- Ambiguous legacy values must map conservatively to "resolved/legacyUnknown" or remain needed according to an approved migration rule; they must never be guessed as purchased.

### 16.4 Catalog

The catalog remains independent:

- stable IDs and redirects resolve identity;
- active/inactive governs discovery;
- user snapshots preserve offline display;
- catalog metadata changes do not alter shopping/session state;
- semantic icons remain category presentation, not lifecycle state.

### 16.5 Notifications

Notifications must consume a list/session projection rather than global incomplete ShoppingItems.

Expected result:

- correct Product set;
- correct list ID;
- correct deep link;
- consistent stale-plan behavior;
- no notification for a Product resolved/removed in that source context.

### 16.6 Shopping

Shopping becomes the single owner of:

- list membership/resolution;
- plan;
- selected store;
- session and outcomes.

Finish Shopping becomes a real lifecycle boundary. Completed/Recent must be defined as projections or removed/renamed.

### 16.7 Map

Map becomes a consumer of:

- current plan;
- active session;
- explicit selected list.

It stops using all global compatibility items as the default shopping truth. Saved-location item management must use Product/list commands or become clearly separate non-Product notes.

### 16.8 Accessibility

Positive impact:

- scope and action are announced;
- icon-only ambiguity is removed;
- controls gain deterministic state/value pairs.

Required validation:

- VoiceOver in English and Hebrew;
- Dynamic Type through accessibility sizes;
- RTL/bidirectional strings;
- Reduce Motion;
- contrast and non-color state cues;
- Switch Control and hardware keyboard focus.

### 16.9 Localization

State names and actions become shared localization keys with parameterized list/store names.

Required:

- English and Hebrew parity;
- natural RTL ordering;
- no concatenation that produces incorrect grammar;
- no raw enum/raw-value display;
- consistent terminology for Library, Shopping, Needed, Resolved, Remaining, Collected, Removed, Restore, and Finish.

### 16.10 Performance

The target model improves query scope:

- membership by indexed `(listID, productID)`;
- needed entries by `(listID, resolutionState, sortOrder)`;
- active session by session state/time;
- notifications by precomputed scoped projection;
- no full-library compatibility scan for list state.

Costs include additional session-line/outcome rows and projection updates. These are bounded by list/session size and preferable to repeated global scans.

### 16.11 Testing

Testing must shift from individual booleans to transition and invariant tests:

- per-list independence;
- finish reconciliation;
- Map/notification/list parity;
- tombstone/restore/relaunch;
- catalog inactive/missing;
- session context conflict;
- migration of ambiguous legacy state;
- accessibility semantics;
- localization fixtures;
- Android shared contract fixtures.

### 16.12 Future Android parity

The recommended concepts are platform-neutral:

- opaque Product/list/session IDs;
- library membership state;
- entry lifecycle and outcome reasons;
- plan revision contract;
- session-line outcomes;
- catalog lifecycle;
- shared transition fixtures.

Android must not copy `ShoppingItem.isCompleted` or iOS view-driven writes. Native persistence may differ, but transition outcomes and user-facing terminology must match.

### 16.13 Future AI workflows

AI can safely:

- suggest Products;
- propose list additions/removals;
- propose quantities;
- propose alternative stores;
- recommend carry-forward/unavailable outcomes;
- estimate replenishment from confirmed events.

AI cannot:

- infer purchase from a checkmark;
- change library/list/session state without user-authorized command policy;
- treat catalog inactive as user removal;
- use globally completed compatibility items as ground truth.

Explicit outcome history improves AI quality by distinguishing purchased, unavailable, already owned, skipped, and removed.

### 16.14 Analytics and privacy

Although not a separate audit goal, the architecture changes the meaning of analytics:

- checked is not purchase;
- collected may not be paid;
- finished may include remaining/unavailable Products;
- removed is not physical erasure.

Analytics must use named outcomes. Privacy erasure and historical retention need an approved policy before purchase events or sync are expanded.

---

## 17. Migration and Compatibility Requirements

This section defines architectural constraints, not an implementation plan. WT-030A authorizes no code and proposes no partial implementation.

### 17.1 Cutover principle

The Product State standard is accepted only when every authoritative consumer agrees. A release must not leave:

- Shopping on entry state;
- Map/notifications on global legacy completion;
- session finish without reconciliation;
- saved locations as a direct writer;
- Product cards on old membership checkmarks.

Temporary internal migration machinery may be necessary, but no mixed-authority state is an acceptable Product outcome or partial feature.

### 17.2 Data that must be preserved

- Product UUID and active/removed state.
- Catalog ProductID and snapshots.
- User images, names, brand/category/details, notes, and source.
- Shopping list IDs, names, kinds, entries, quantities, order, and timestamps.
- Active session identity, selected store, item IDs, collected IDs, and timestamps.
- Product History and Product Knowledge.
- Completed/Recent historical references.
- Redirect and repair diagnostics.

### 17.3 Conservative legacy interpretation

Migration must not infer:

- purchased from `isCompleted`;
- collected from `isChecked`;
- library deletion from missing list membership;
- archive from `deletedAt`;
- current list membership from a compatibility item;
- catalog identity from name/category/barcode without approved stable resolution.

Ambiguous rows require a deterministic conservative rule and an audit count. No ambiguous state may be silently upgraded to a stronger claim.

### 17.4 Validation requirements

Before/after validation must prove:

- Product and list-entry counts reconcile.
- No active Product is unintentionally tombstoned.
- No tombstone is resurrected.
- Each entry resolves to a Product or an explicit exception.
- No duplicate current `(listID, productID)` membership exists.
- Per-list needed/resolved results are stable under relaunch.
- Active session recovery preserves every line outcome.
- Map/notification projections equal their source list/session.
- Re-running migration/repair causes no drift.
- Original persistent store remains recoverable on failure.

### 17.5 Compatibility retirement condition

`ShoppingItem.isCompleted` can remain only as a derived compatibility output during an approved migration mechanism. It must have:

- no user-facing direct writer;
- no role in Product/list/session truth;
- no role in Map or notification item selection;
- no power to restore/delete Products;
- an explicit retirement gate.

---

## 18. Measurable Acceptance Criteria

### Architecture and invariants

- **AC-01:** No Product identity/library record contains a global in-shopping, planned, recommended, collected, completed, or purchased state.
- **AC-02:** Automated constraints/tests prove at most one current entry for each `(listID, productID)`.
- **AC-03:** Changing or removing an entry in list A produces zero field changes and zero projection changes for the same Product in list B, except shared Product attribute edits.
- **AC-04:** Every state mutation is routed through a named domain command; production views contain no direct writes to lifecycle fields.
- **AC-05:** `ShoppingItem.isCompleted` is absent from all authoritative selection, planning, Map, notification, and session decisions.

### Product Library

- **AC-06:** Product cards display no completion-style empty/filled circle.
- **AC-07:** Product Library membership actions name or otherwise unambiguously identify the target list.
- **AC-08:** Removing a Product from a list leaves the Product active and visible in the library.
- **AC-09:** Removing a Product from the library creates a durable tombstone, survives relaunch, and never deletes Product Knowledge/history.
- **AC-10:** Restore is explicit, restores the same Product ID, and does not silently recreate prior active-list memberships.
- **AC-11:** Startup repair and catalog update test fixtures never reactivate a tombstone.

### Shopping lists

- **AC-12:** Add to list is idempotent and reopens a resolved entry only through the approved rule.
- **AC-13:** Remove from list affects exactly one named list.
- **AC-14:** Needed and resolved states are represented by text/accessibility semantics, not color/icon alone.
- **AC-15:** Completed and Recent are either verified system projections with exclusive transition rules or are not presented as such.
- **AC-16:** The Product chooser differentiates already-in-list from pending selection visually and semantically.
- **AC-17:** Clear All in the chooser has a tested, accurately labeled scope.

### Plan, Map, and notifications

- **AC-18:** Every ready plan stores or deterministically exposes its list ID, list revision, and exact included entry IDs.
- **AC-19:** A Product Library-only change leaves an unrelated ready plan current.
- **AC-20:** Any source-entry change makes the corresponding plan stale before Map/session use.
- **AC-21:** For each fixture, Shopping needed IDs, plan input IDs, Map context IDs, and notification IDs are identical except for explicitly surfaced planner exclusions.
- **AC-22:** Notification list ID and Product IDs always originate from the same list revision or session snapshot.
- **AC-23:** A notification tap restores the exact owning list/session context.

### Shopping Session

- **AC-24:** Starting a session with a conflicting active session requires an explicit resume/switch/end decision.
- **AC-25:** Collection changes only the session line while the session is active.
- **AC-26:** Finish cannot succeed while any session line lacks an approved outcome.
- **AC-27:** Finish commits the session, list-entry reconciliation, and history outcomes atomically.
- **AC-28:** Relaunch restores the same active session, store context, item set, and per-line outcomes.
- **AC-29:** A finished session cannot leave collected items as open needs unless that is an explicitly selected policy/outcome.
- **AC-30:** No finished/collected/check action creates a global Product purchased state.

### Catalog and acquisition

- **AC-31:** Catalog inactive/missing/replaced fixtures never change user-library or shopping state.
- **AC-32:** Catalog re-add and recognized-barcode restore flows are explicit to the user and preserve Product identity.
- **AC-33:** Scanner/AI action labels exactly match whether the result saves to Library, adds to a named list, or both.
- **AC-34:** AI-generated commands require the approved confirmation/authority policy and use the same domain transitions as manual actions.

### Accessibility and localization

- **AC-35:** VoiceOver announces object, scope, current state, and action result for every lifecycle control.
- **AC-36:** English and Hebrew state/action copy is complete; no production lifecycle UI displays a raw enum or unlocalized hardcoded fallback.
- **AC-37:** RTL and Dynamic Type tests show no overlap or loss of the only distinguishing state label.
- **AC-38:** Every lifecycle action has at least a 44 by 44 point target and state is not color-only.

### Persistence, recovery, and performance

- **AC-39:** File-backed V1/V2/V3 migration fixtures preserve all IDs, tombstones, entry counts, session data, catalog snapshots, and history.
- **AC-40:** Migration and startup repair are idempotent across at least two repeated launches with zero count/state drift.
- **AC-41:** Persistent-store failure never reports a state mutation as durable when the app is operating in an ephemeral store without a visible warning.
- **AC-42:** List membership and needed-entry queries use scoped indexed lookups; no Product-state screen requires an O(total compatibility items) scan.
- **AC-43:** On the oldest supported test device and production-scale fixture, p95 state-projection time does not regress more than 10% from the recorded pre-cutover baseline.

### Cross-platform and testing

- **AC-44:** Shared platform-neutral transition fixtures produce identical lifecycle outcomes on iOS and Android.
- **AC-45:** Automated tests cover every allowed and forbidden transition in Section 15.
- **AC-46:** Tests intentionally construct contradictory legacy states and prove deterministic conservative migration with an exception count.
- **AC-47:** No acceptance test uses "checked," "completed," and "purchased" as synonyms.

---

## 19. Open Questions

These questions are unresolved. This audit does not invent answers.

### Product policy

1. What user-visible meaning should resolving a list need have before a session: done, no longer needed, already owned, purchased, or a selectable reason?
2. Does "Collected" in Shopping Mode imply purchased, or only placed in the basket?
3. What outcomes are mandatory when finishing with remaining items: carry forward, unavailable, skip, keep needed, or another policy?
4. Is an abandoned session different from a finished session, and how is its progress retained?
5. Should Product Library removal automatically remove active list memberships, ask the user, or be blocked until memberships are handled?
6. Should removed Products be available in a Recently Removed surface, and what is the retention/undo period?
7. Is Archive a distinct user need? If yes, how does it differ from Removed in visibility, list eligibility, history, and sync?
8. What is the user-facing privacy-erasure policy for Products with purchase/history references?

### Lists and history

9. Are Completed and Recent real editable shopping lists, system-managed projections, or labels that should be removed?
10. Can multiple Weekly/active lists exist, and can more than one be active at a time?
11. Are checked/resolved entries retained in the active list, hidden, moved, or projected elsewhere?
12. Does reopening a resolved entry preserve its prior resolution event?
13. What list should receive a restored Product, if any? The recommendation is none, but final Product confirmation is required.

### Sessions and navigation

14. When a conflicting active session exists, which choices and progress warning must be shown?
15. Can the user edit the source list while a session is active, and if so, how are session lines reconciled?
16. Can a session cover multiple lists or multiple stores in the supported product scope?
17. What exact screen should a shopping notification open: list, plan, Map, or active session?
18. What exact screen should a Home shopping-list card open?

### Scanner, catalog, and AI

19. After a scan saves to the Product Library, should the default continuation be Done, Scan Another, Add to a named list, or a choice?
20. Should selecting a removed catalog Product be described as Restore, Add, or both?
21. Should barcode recognition ever restore automatically, or must it ask when a tombstone match is found?
22. What authority may future AI have for bulk list creation or session outcome suggestions?
23. Which Product outcomes are trustworthy enough to train replenishment recommendations?

### Visual and localization policy

24. Should list resolution retain a checkmark with a text label, or use a different control entirely in response to WT-005?
25. What approved Hebrew terms map to Needed, Resolved, Remaining, Collected, Removed, Restore, Unavailable, Skipped, and Carry Forward?
26. What minimum catalog icon-specificity/quality threshold is required before generic fallback is acceptable?

### Technical policy

27. Must plans persist across cold launch, or is deterministic regeneration sufficient before a session begins?
28. What is the maximum supported list/library/session size for formal performance acceptance?
29. How should the app communicate persistent-store recovery and in-memory fallback without alarming users or implying durability?
30. What support window is required before compatibility ShoppingItem state can be physically retired?

---

## 20. Terminal Decision

### Decision

**APPROVED:** Orthogonal Product Lifecycle is the official WayTask Product State architecture.

WayTask Product State is not one enum and not one checkbox. It is a scoped composition of:

- Product identity;
- active/removed library membership;
- per-list membership and need resolution;
- list-revision plan state;
- per-session execution outcomes;
- historical purchase/usage events;
- independent catalog lifecycle.

### Binding product rules

1. Products are reusable and do not become globally purchased, planned, or completed.
2. Shopping state belongs to a named list entry.
3. Collection state belongs to a named session line.
4. Recommended store belongs to a plan/session.
5. Purchase belongs to history.
6. Catalog status never controls user-library membership.
7. The Product Library does not display completion checkboxes.
8. Remove from Shopping affects one list only.
9. Finish Shopping must reconcile every session line.
10. Map and notifications use the same scoped source as Shopping.
11. Library removal is a durable tombstone with explicit restoration semantics.
12. Legacy `ShoppingItem.isCompleted` is not an authority in the official architecture.

### Implementation gate

WT-030A is an audit-only decision and authorizes no code changes.

Implementation must not begin as a partial visual patch or mixed-authority cutover. The unresolved Product questions in Section 19 that determine user-visible outcomes must be decided before an implementation specification is approved. Technical work must then satisfy the complete architecture, transition contract, and acceptance criteria in this document.

### Final recommendation

Adopt this document as the Product State specification for WayTask and supersede any prior implication that:

- Product Library membership is a completion check;
- `ShoppingItem.isCompleted` is global Product truth;
- finishing a session equals purchasing every Product;
- Completed/Recent list names constitute a working history model;
- recommended store is a Product state;
- catalog deactivation removes user data.

**WT-030A audit result: COMPLETE.**

---

## Appendix A - Current-to-Official Meaning Map

| Current field/behavior | Current meaning | Official destination |
|---|---|---|
| `Product.deletedAt == nil` | Active library Product | Library membership `active` |
| `Product.deletedAt != nil` | Removed tombstone | Library membership `removed` |
| `ShoppingListEntry` exists | In one list | List membership present |
| `ShoppingListEntry.isChecked == false` | Needed | Entry `needed` |
| `ShoppingListEntry.isChecked == true` | Checked, reason unknown | Entry `resolved(reason)` after policy decision |
| `ShoppingItem.isCompleted` | Global compatibility active/completed | Non-authoritative derived compatibility only |
| Plan state enum | Runtime generation state | Retain as scoped plan lifecycle with revision |
| Plan recommended store | Derived recommendation | Plan context |
| Session `isActive` | Active/finished | Session lifecycle |
| Session collected ID | Collected at session | Session-line `collected` |
| `ProductHistory` | Frequency/recency aggregate | Derive from trustworthy usage/outcome events |
| Completed list kind | Named list shell | Decide system projection vs user list |
| Recent list kind | Named list shell | Decide system projection vs user list |
| Catalog `isActive` | Catalog discovery state | Independent catalog lifecycle |
| Product-card check | Selected-list membership | Remove from Product card |
| Chooser checked square | Pending or existing | Split pending selection from existing membership |
| Saved-location item completion | Location-owned global flag | Route through scoped Product/list/session command or separate non-Product concept |

## Appendix B - Current State Combinations That Prove a Flat Enum Cannot Work

| Scenario | Library | List A | List B | Plan | Session | Catalog |
|---|---|---|---|---|---|---|
| Normal pre-trip | Active | Needed | Absent | Ready/included | None | Active |
| Two-list conflict today | Active | Needed | Checked | May exclude globally | None | Active |
| In-store collection | Active | Needed | Absent | Ready snapshot | Collected | Active |
| Catalog retired | Active | Needed | Absent | Ready | None | Inactive |
| Removed with history | Removed | Absent | Historical resolved | None | Finished reference | Active/missing |
| Repeated purchase | Active | Needed again | Absent | New plan | Prior finished + new active | Active |

No one value among `libraryOnly`, `inShopping`, `planned`, `purchased`, `archived`, or `deleted` can represent these combinations without losing valid information.

## Appendix C - Documentation Reconciliation

| Source | Relevant rule/claim | Audit reconciliation |
|---|---|---|
| v1.0 Product Specification | Products permanent; lists temporary; plans intelligent | Adopted as core boundary |
| v1.0 Product Specification | Never show shopping/completion state inside library | Current membership checkmark is noncompliant |
| v1.0 Product Specification | Product Card never carries completion checkbox | Adopted in official UX standard |
| v1.0 Product Specification | Shopping Mode reconciles uncollected items | Current finish does not; target session outcomes required |
| `docs/20_ARCHITECTURE.md` | Product -> list entry -> temporary ShoppingItem -> plan | Confirms compatibility debt |
| `docs/15_ENGINEERING_BLUEPRINT.md` | Retire ShoppingItem after migration | Consistent with recommendation |
| `docs/60_CHANGELOG.md` 1.15.1-1.15.5 | Product/Shopping split with temporary adapters | Current implementation baseline |
| WT-020 Product Audit | Multiple Product representations and weak lifecycle semantics | Still valid except deletion behavior was superseded |
| WT-029 commits/tests | Durable deletion, restoration, schema V3, startup resilience | Current removal/recovery authority |
| `BETA_BACKLOG.md` WT-005 | Circular indicators should be removed | Supports visual-vocabulary finding |
| Product Search UX Contract | Explicit selection, semantic icons, RTL/accessibility | Adopted for acquisition and alignment rules |
| Catalog-Aware Persistence Architecture | User Product identity and catalog status remain separate | Adopted |

Review Status: Approved

Reviewed by:
Product Architecture

Review Date:
2026-07-29

Approved for implementation planning only.

This audit authorizes no production code changes.
