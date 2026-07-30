# WT-031A Phase 1 Product State Baseline Evidence

## Record status

- Work item: WT-032B, Implementation Execution Step E-01 only.
- Evidence date: 2026-07-30 (Asia/Hebron).
- Scope: static Product State inventory plus the approved E-00 build/test baseline.
- Repository snapshot: `main` at `98da1a4c3a0d737ac0d53ad638a6ed21c28cbed4`.
- This record describes current and legacy behavior found in the repository. It does not redefine the approved architecture or approve any known defect.
- E-02 and all later execution steps are outside this record and were not executed.
- No fixture values or private user data were inspected or copied into this document. Property names are recorded where they are part of the source contract; no real barcode, note, store, coordinate, image, credential, or account value is present.

### Evidence labels

- **V-E00** — verified by the completed E-00 command and its result.
- **V-SRC** — verified directly in repository source at the recorded snapshot.
- **V-TEST** — verified in existing test source and/or the E-00 full test run.
- **INTERPRETATION** — a mapping or gap statement derived from verified facts; it is not a new requirement or an approval.

Line references are stable for the recorded commit. Paths and symbols remain the primary locator if later work moves a line.

## Approved E-00 baseline

### Repository

| Item | Approved value | Evidence |
|---|---|---|
| Branch | `main` | V-E00 |
| Upstream | `origin/main` | V-E00 |
| Ahead / behind | `+0 / -0` | V-E00 |
| Commit | `98da1a4c3a0d737ac0d53ad638a6ed21c28cbed4` | V-E00 |
| Initial repository status | Clean; no staged, modified, deleted, or untracked path | V-E00 |
| Pre-existing E-01 evidence file | Absent | V-E00 |

Reproduction commands:

```sh
git branch --show-current
git rev-parse HEAD
git rev-list --left-right --count origin/main...HEAD
git status --short --untracked-files=all
```

### Environment

| Component | Approved value | Evidence |
|---|---|---|
| Host | macOS 26.6, build 25G72 | V-E00 |
| Xcode | 26.6, build 17F113 | V-E00 |
| Swift | 6.3.3; `swiftlang-6.3.3.1.3 clang-2100.1.1.101` | V-E00 |
| Simulator | iPhone 17 Pro, iOS 26.5 (23F77), UDID `DE30E799-0496-4818-851D-FF613F62FCD3` | V-E00 |
| Swift package | Sentry 9.21.0, revision `53eb9bd5da18e208cfd80e86863d3f4c7ba21b1d` | V-E00 |

### Build result

The E-00 clean generic iOS Debug build passed with `** BUILD SUCCEEDED **`.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Debug \
  -destination generic/platform=iOS \
  -derivedDataPath /private/tmp/WayTask-WT032B-E00-Resume-Build-20260730-0948 \
  CODE_SIGNING_ALLOWED=NO build
```

Result: **PASS** (V-E00). The derived data was outside the repository and was removed during E-00 cleanup.

### Test result

The E-00 full `WayTaskTests` run passed with `** TEST SUCCEEDED **`.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=DE30E799-0496-4818-851D-FF613F62FCD3' \
  -derivedDataPath /private/tmp/WayTask-WT032B-E00-Resume-Tests-20260730-1002 \
  -resultBundlePath /private/tmp/WayTask-WT032B-E00-Resume-Tests-20260730-1002.xcresult \
  -only-testing:WayTaskTests
```

Result: **291 passed, 0 failed, 0 skipped** (V-E00). The result bundle and derived data were outside the repository and were removed during E-00 cleanup.

The first E-00 attempt encountered sandbox DNS restrictions and an `xcresulttool` permission restriction. Those were infrastructure conditions, not repository or product failures. The approved build and test results above came from the successful reruns.

### Protected hashes

Reproduction:

```sh
shasum -a 256 \
  docs/Audits/1.0.3/WT-030A_ProductStateUXAudit.md \
  docs/Audits/1.0.3/WT-030_ArchitectureSummary.md \
  docs/ImplementationPlans/1.0.3/WT-031A_ProductStateImplementationPlan.md \
  docs/ImplementationSpecifications/1.0.3/WT-032A_ProductState_Phase0DecisionSpecification.md \
  docs/ImplementationSpecifications/1.0.3/WT-032B_ProductState_Phase1ImplementationSpecification.md \
  design/v1.0/WayTask_Product_Specification_v1.0.pdf \
  WayTask.xcodeproj/project.pbxproj \
  WayTask/Persistence/WayTaskSchemaV1.swift \
  WayTask/Persistence/WayTaskSchema.swift \
  WayTask.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

git ls-files WayTaskTests | sort | xargs shasum -a 256 | shasum -a 256
```

| Protected artifact | SHA-256 |
|---|---|
| `docs/Audits/1.0.3/WT-030A_ProductStateUXAudit.md` | `752695899449581256e8826b1318b9aa63b7d361a8a4b1bc2de2af0afb8cf032` |
| `docs/Audits/1.0.3/WT-030_ArchitectureSummary.md` | `21aa18de727ad392dbd3f6b3845c283d45522df2c21022c554dd3a502979e586` |
| `docs/ImplementationPlans/1.0.3/WT-031A_ProductStateImplementationPlan.md` | `7321482546b6985ace7aee999c1a195ed1b295dda3af1bb57c6e670c5cc6d06a` |
| `docs/ImplementationSpecifications/1.0.3/WT-032A_ProductState_Phase0DecisionSpecification.md` | `c1d43c3037651f59cb3e8bd680ef3fe4e7e8f3306ed038abf2c710a8462d1abd` |
| `docs/ImplementationSpecifications/1.0.3/WT-032B_ProductState_Phase1ImplementationSpecification.md` | `25824516c1d0602281fe8000dd1a5c81cc12ddd9b3ba68b3da5d5b82097b1fb7` |
| `design/v1.0/WayTask_Product_Specification_v1.0.pdf` | `a8ef365c558730dd9aaf9b1544315f5da677e1bfc86cae6b7acd8dd726d4f61b` |
| `WayTask.xcodeproj/project.pbxproj` | `9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f` |
| `WayTask/Persistence/WayTaskSchemaV1.swift` | `a82370847be17b15d15bebfd7aae72c48b98141f1fd2f346bb6afa8b33ff7a56` |
| `WayTask/Persistence/WayTaskSchema.swift` | `bc9a5cf075275e5b40242b5109d9b2eddc50a49bbe44b3f8b01279db159fe27e` |
| `WayTask.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | `42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244` |
| Tracked `WayTaskTests` tree aggregate | `f2213e1f79bb0d4f3d5917eb5acbb3a0f75c6a6b913d11e1c5a3268835fbb08d` |

## Reproducible static inventory method

The following read-only commands were run from the repository root. Test sources were excluded from production-field counts and included separately in the test inventory.

```sh
for property in isCompleted isChecked legacyShoppingItemID deletedAt shoppingListRevision
do
  rg --glob '*.swift' --glob '!WayTaskTests/**' \
    -o "\b${property}\b" . | wc -l
  rg --glob '*.swift' --glob '!WayTaskTests/**' \
    -l "\b${property}\b" . | wc -l
done

rg --glob '*.swift' --glob '!WayTaskTests/**' \
  -l '\b(isCompleted|isChecked|legacyShoppingItemID|deletedAt|shoppingListRevision)\b' . \
  | sort -u

rg --glob '*.swift' --glob '!WayTaskTests/**' \
  -n '\bmodelContext\.(insert|delete|save)\s*\(|\bcontext\.save\s*\(|\$0\.save\s*\(' .

rg -n 'ModelConfiguration\(|isStoredInMemoryOnly|XCTAttachment|measure\s*\(' \
  WayTaskTests --glob '*.swift'

for file in $(git ls-files 'WayTaskTests/*.swift' 'WayTaskTests/**/*.swift')
do
  count=$(rg -c '^\s*func test' "$file" || true)
  printf '%s\t%s\n' "$count" "$file"
done

git ls-files WayTaskTests | wc -l
git ls-files WayTaskTests | rg -c '\.swift$'
git ls-files WayTaskTests | rg -c '\.json$'
```

### Key-field counts

These are lexical occurrences, followed by the number of production Swift files containing the property.

| Property | Occurrences | Files | Current role |
|---|---:|---:|---|
| `ShoppingItem.isCompleted` | 67 | 19 | Legacy compatibility completion/active filter used across product, plan, session, map, location, discovery, and UI paths |
| `ShoppingListEntry.isChecked` | 37 | 7 | Current entry-level checked state in services, Shopping/Home UI, diagnostics, models, and frozen schemas |
| `legacyShoppingItemID` | 80 | 9 | Product/entry bridge to compatibility `ShoppingItem`, including every schema generation |
| `Product.deletedAt` | 20 | 7 | Product Library tombstone and active-library filter |
| `AppStateManager.shoppingListRevision` | 4 | 2 | In-memory UI invalidation token; not a persisted list revision |

Twenty-four production Swift files reference at least one of these five fields.

### Reviewed writer counts

Mutation-shaped lexical results were manually reviewed to exclude initializer assignments, local bindings, comparisons, and presentation DTO initialization.

| State | Executable existing-object write statements | Exact writer locations |
|---|---:|---|
| `ShoppingItem.isCompleted` | 9 | `ShoppingListService.swift:161,204,334,341,449,725`; `WayTask/ContentView.swift:396`; `WayTask/LocationDetailView.swift:26`; `WayTask/ShoppingWorkspaceView.swift:1543` |
| `ShoppingListEntry.isChecked` | 2 | `ShoppingListService.swift:158`; `WayTask/ShoppingWorkspaceView.swift:1540` |
| `legacyShoppingItemID` | 8 | `ShoppingListService.swift:162,167,168,342,349,570,677`; `WayTask/Models.swift:402` |
| `Product.deletedAt` | 3 | `WayTask/Models.swift:477,486`; rollback restoration in `WayTask/Persistence/CatalogProductPersistenceService.swift:306` |
| `shoppingListRevision` | 1 | `WayTask/AppStateManager.swift:394`; 11 production call sites invoke `shoppingListDidChange` |

`Product.deletedAt` semantic callers are `ShoppingListService.swift:128,439` and `WayTask/Persistence/CatalogProductPersistenceService.swift:202`. The model methods contain the normal tombstone/restore assignments; the catalog snapshot assignment is rollback behavior.

### Direct `ModelContext` counts

| Operation | Production call sites | Files |
|---|---:|---|
| `modelContext.insert(...)` | 16 | `ProductListView.swift`, `DebugSeedStoreService.swift`, `ShoppingListService.swift`, `ShoppingSessionService.swift`, `ShoppingMemoryService.swift`, `WayTask/MainMapView.swift`, `SettingsView.swift`, `ProductKnowledgeService.swift`, `WayTask/Persistence/CatalogProductPersistenceService.swift` |
| `modelContext.delete(...)` | 8 | `ShoppingListService.swift`, `SettingsView.swift`, `WayTask/ContentView.swift`, `WayTask/LocationDetailView.swift`, `WayTask/MainMapView.swift`, `WayTask/Persistence/CatalogProductPersistenceService.swift` |
| `modelContext.save()`, `context.save()`, or injected default `$0.save()` | 26 | `ProductListView.swift`, `DebugSeedStoreService.swift`, `ShoppingListService.swift`, `ShoppingMemoryService.swift`, `WayTask/ContentView.swift`, `WayTask/MainMapView.swift`, `WayTask/ShoppingWorkspaceView.swift`, `ShoppingSessionService.swift`, `SettingsView.swift`, `ProductKnowledgeService.swift`, `WayTask/Persistence/CatalogProductPersistenceService.swift` |

There are 50 direct insert/delete/save call sites in total. This is a lexical count, not a transaction count: one behavior may use multiple calls, and SwiftData may also autosave mutations where no explicit save appears.

## Persistence and schema inventory

All rows are V-SRC.

| Lifecycle | Exact path and lines | Symbol / persisted properties | Category | Verified current fact |
|---|---|---|---|---|
| Map/location | `WayTask/Models.swift:4-17` | `GeoLocation`; identity, display/location metadata, `shoppingItems` cascade relationship | Persistence R/W | Saved locations own a relationship to compatibility `ShoppingItem` records. No values are reproduced here. |
| Compatibility ShoppingItem | `WayTask/Models.swift:70-90` | `ShoppingItem`; `id`, product metadata, `isCompleted`, added/source fields; catalog IDs are `@Transient` | Persistence R/W | `isCompleted` is durable; the three catalog identity fields on this compatibility model are transient. |
| Product / Product Library / Catalog | `WayTask/Models.swift:190-216` | `Product`; `id`, `legacyShoppingItemID`, metadata, `updatedAt`, `deletedAt`, seven catalog snapshot fields | Persistence R/W | Product Library deletion is represented by nullable `deletedAt`; the compatibility link is nullable. |
| Product | `WayTask/Models.swift:377-415,420-487` | `refresh(from:)`, `refresh(from:fallbackImageData:)`, `markDeletedFromLibrary`, `restoreToLibrary` | Writer | Refresh refuses catalog-linked or tombstoned products in the legacy-item path; the tombstone helpers mutate `deletedAt`. |
| Shopping List | `WayTask/Models.swift:553-590` | `ShoppingListKind`, `ShoppingList`; `id`, `title`, `kindRawValue`, timestamps, `isDefault` | Persistence R/W | Durable kinds are `weekly`, `completed`, and `recent`; no durable revision field exists. |
| ShoppingListEntry | `WayTask/Models.swift:593-626` | `ShoppingListEntry`; list/product/legacy IDs, quantity, `isChecked`, created/sort fields, nullable product relationship | Persistence R/W | Entry checked state and compatibility identity are durable; the relationship delete rule is nullify. |
| Product History | `ProductHistory.swift:4-43` | `ProductHistory`; `productKey`, product snapshot fields, add dates/count/source/interval, `lastCompletedDate` | Persistence R/W | History is keyed separately from Product UUID and may retain completion inference. |
| Shopping Session | `ShoppingSession.swift:4-74` | `ShoppingSession`; active/finish state, encoded item/collected IDs, optional list/store snapshots | Persistence R/W | Session membership and collected membership are encoded UUID lists; no entry snapshot collection is stored. |
| Migration/recovery | `WayTask/Persistence/WayTaskSchemaV1.swift:4-19,22-115` | `WayTaskSchemaV1` 1.0.0 | Frozen schema | V1 includes the eight-model graph. V1 Product and entry both contain `legacyShoppingItemID`; entry contains `isChecked`. |
| Migration/recovery | `WayTask/Persistence/WayTaskSchema.swift:6-142` | `WayTaskSchemaV2` 2.0.0 | Frozen schema | V2 is the frozen V1 graph with the seven nullable Product catalog snapshot properties; entry shape retains the compatibility ID and checked flag. |
| Migration/recovery | `WayTask/Persistence/WayTaskSchema.swift:144-161` | `WayTaskSchemaV3` 3.0.0 | Current schema | V3 uses runtime Product, including durable nullable `deletedAt`, and retains the same eight-model graph. |
| Migration/recovery | `WayTask/Persistence/WayTaskSchema.swift:163-214` | `WayTaskSchemaMigrationPlan`, `WayTaskModelContainer` | Migration / container | The registered stages are lightweight V1→V2 and V2→V3; the current container uses V3 and that plan. |

## Reader/writer path inventory

All behavior statements in this table are V-SRC. Trace mappings are observations against the existing CB/KD/D identifiers, not approvals.

| Lifecycle | Exact path and symbol/lines | Category | Verified current behavior | Trace |
|---|---|---|---|---|
| Product; compatibility ShoppingItem | `ShoppingListService.swift:68-109`, `addManualItem`, `addRecognizedProduct`, `addManualProduct` | Writer | Creates compatibility items and/or Products and saves them. | CB-01; D-02, D-33 |
| Product; Shopping List; ShoppingListEntry; compatibility ShoppingItem | `ShoppingListService.swift:112-191`, `upsertRecognizedProduct`, `addProductToShopping` | R/W | Barcode upsert can restore a tombstone. Add-to-list reuses or creates a compatibility item and entry; an existing entry is unchecked and its compatibility item reopened. | CB-01, CB-02, CB-07; KD-01, KD-08; D-01, D-02, D-09, D-17, D-22, D-33 |
| Shopping List; ShoppingListEntry; compatibility ShoppingItem | `ShoppingListService.swift:194-209`, `removeProductFromShopping` | R/W/delete | Removing an entry marks its linked compatibility item completed, deletes the entry, and saves. | CB-03; KD-01, KD-02; D-01, D-08, D-10 |
| Product; compatibility ShoppingItem | `ShoppingListService.swift:212-350`, candidate conversion and `openCompatibilityItem` helpers | R/W | Compatibility item resolution can reopen an existing matching item and refresh Product/entry compatibility IDs. | CB-01, CB-02; KD-01; D-02, D-17, D-33 |
| Product Library; Shopping List; ShoppingListEntry; compatibility ShoppingItem | `ShoppingListService.swift:410-455`, `ProductLibraryDeletionService.delete` | R/W/delete | Tombstones Product, completes the compatibility item, removes matching weekly-list entries, and saves. It does not query active sessions. | CB-05, CB-06; KD-07; D-15, D-16, D-18, D-32 |
| Migration/recovery; all list/product compatibility lifecycles | `ShoppingListService.swift:464-738`, `ShoppingListBackfillService.ensureDefaultListsAndBackfill` | Startup repair R/W | Ensures default list kinds, repairs legacy links, resolves Products by explicit identity paths, avoids active resurrection of tombstones, and removes tombstoned weekly entries. | CB-13, CB-14, CB-16; KD-02, KD-03; D-23-D-28, D-30, D-32, D-33 |
| Product Library; Shopping List; Catalog | `ProductListView.swift:1551-1809`, save/delete/list actions and compatibility resolution | UI reader/service writer | Saves through coordinator/services, invokes Product Library deletion and list add/remove, filters tombstones, and resolves entry/product compatibility links for presentation. | CB-01, CB-05; KD-01, KD-12; D-15, D-20, D-33 |
| Map/location | `ProductListView.swift:2123-2125` | Direct ModelContext writer | Inserts a saved location and explicitly saves. | D-23 |
| Shopping List; ShoppingListEntry; compatibility ShoppingItem | `WayTask/ShoppingWorkspaceView.swift:581-654,801,1105-1206,1535-1584` | UI R/W; direct mutation | Reads entry checked state and compatibility links. Toggle directly mutates `entry.isChecked`, mirrors `item.isCompleted`, optionally deletes through the service, and saves. | CB-02, CB-03; KD-01, KD-12; D-01-D-03, D-20, D-33 |
| Shopping List; ShoppingListEntry; compatibility ShoppingItem | `WayTask/ContentView.swift:391-435`, fresh-list/reset paths | UI R/W/delete; direct mutation | One reset path completes linked compatibility items, directly deletes entries, saves, and signals the in-memory revision. Other plan inputs filter legacy completion. | CB-03, CB-12; KD-01, KD-12; D-01, D-10, D-20, D-35 |
| Map/location; compatibility ShoppingItem | `WayTask/LocationDetailView.swift:22-50,83-115` | UI R/W/delete; direct mutation | Directly toggles legacy completion for a location item, appends new compatibility items to the relationship, and directly deletes items. | CB-12; KD-01, KD-12; D-20, D-23, D-35 |
| Product; Shopping List; ShoppingListEntry; compatibility ShoppingItem; Completed/Recent | `WayTask/HomeView.swift:400-523,734-739,796-797` | UI reader | Reads `isChecked` when entries exist, falls back to `isCompleted`, derives completed/recent counts, and resolves compatibility IDs. | CB-12; KD-01, KD-11, KD-12; D-19-D-21, D-30, D-33 |
| Product; Map/location; compatibility ShoppingItem | `WayTask/MainMapView.swift:1-16,370-427` | UI reader; direct ModelContext location R/W | Filters tombstoned products, includes completion in signatures, and inserts/deletes saved locations directly. | CB-12; KD-12; D-20, D-23, D-35 |
| Product; ShoppingListEntry; Shopping Plan; diagnostics | `WayTask/BetaDiagnosticsView.swift:58-105,470-483` | UI/diagnostic reader | Reads lists and entries, includes checked state in a live signature, and derives needed/checked counts. | KD-04, KD-12; D-11, D-20 |
| Shopping Plan; compatibility ShoppingItem | `DecisionEngine.swift:36-55`, `DecisionEngine.evaluate` | Reader | Decision output includes only active compatibility item IDs. | CB-12; KD-01, KD-12; D-01, D-20 |
| Product discovery; compatibility ShoppingItem | `DiscoverViewModel.swift:27-42,99-143` | Reader | Discovery lists filter legacy completion state. | CB-12; KD-01, KD-12; D-01, D-20 |
| Map/location; Shopping Plan; compatibility ShoppingItem | `MapViewModel.swift:247-261,398-450,836-846` | Reader | Map state, suggestions, plans, and saved-location product lists filter `isCompleted`. | CB-12; KD-01, KD-12; D-01, D-12, D-20, D-23 |
| Map/location; Catalog; compatibility ShoppingItem | `StoreSearchService.swift:67-98,177-195` | Reader | Search intents use active legacy items; saved-store mapping separately derives incomplete and completed names. | CB-12; KD-01, KD-12; D-01, D-19, D-20, D-23 |
| Shopping Plan; compatibility ShoppingItem | `ShoppingContext.swift:23-41,67-102` | Reader / snapshot DTO | Context snapshots carry `isCompleted`; active-list presence is derived from it. | CB-12; KD-01; D-01, D-12 |
| Catalog; Shopping Plan; compatibility ShoppingItem | `ShoppingIntentMatcher.swift:988-1138` | Reader | Grouping, relevance, eligibility, and unresolved-item paths filter `isCompleted`. | CB-12; KD-01, KD-12; D-01, D-20 |
| Shopping Plan; Shopping Session; compatibility ShoppingItem | `ShoppingTripService.swift:25-49` | Reader | Coverage starts from items filtered by `!isCompleted`. | CB-12; KD-01, KD-12; D-01, D-12, D-20 |
| Shopping Session; compatibility ShoppingItem | `ShoppingSessionService.swift:24-84`, `startShopping`, `activeSession` | R/W | Start filters completed compatibility items but returns any existing active session before validating requested list/store/items. | CB-09, CB-12; KD-06; D-12-D-14, D-28, D-29 |
| Shopping Session; compatibility ShoppingItem | `ShoppingSessionService.swift:100-139`, collect/remaining/finish | R/W | Collect/remaining mutate only encoded session membership. Finish only clears active state and stamps finish time. | CB-10, CB-11; KD-09; D-03-D-05, D-35, D-36 |
| Product History; compatibility ShoppingItem | `ShoppingMemoryService.swift:12-94` | R/W | Aggregates history by barcode when present, otherwise normalized name; last completion is inferred from legacy completion. | CB-08; KD-10, KD-11; D-06, D-07, D-19, D-31 |
| Shopping Plan; Shopping List; notifications | `WayTask/AppStateManager.swift:119-233`, `ShoppingPlan` | Reader / in-memory snapshot | Plan stores filtered compatibility items, stores/options/coverage/signatures, but no source entry-ID set or durable source-list revision. | CB-12; KD-04, KD-05; D-11, D-12 |
| Shopping List | `WayTask/AppStateManager.swift:337-397`, `shoppingListRevision`, `shoppingListDidChange` | In-memory writer | A UUID invalidation token changes in memory and is consumed by `ProductListView`; it is not persisted. | KD-04; D-11 |
| Shopping Plan; notifications | `WayTask/AppStateManager.swift:416-569,657-720` | R/W / route consumer | Manages plan cache/state; notification tap decodes list/item/store/location snapshots and routes to map context. | CB-15; KD-05, KD-12; D-12, D-20, D-21 |
| Map/location; notifications/geofencing; compatibility ShoppingItem | `WayTask/LocationManager.swift:54-195,357-482` | Reader / notification writer | Filters location/list items by legacy completion, creates geofence candidates, and schedules/reads snapshot payloads. | CB-12, CB-15; KD-01, KD-12; D-01, D-20, D-21, D-23 |
| Notifications/geofencing | `GeofenceNotificationService.swift:5-150,244-313` | Snapshot serializer / notification writer | Candidate/payload carry store/location, item-ID/name, list-ID, and coordinate fields into identifiers/user info and notification requests. This record contains field names only. | CB-15; KD-12; D-20, D-21 |
| Scanner/acquisition; Product | `CameraView.swift:904-941` | Acquisition writer via service | Barcode acquisition builds a candidate and calls `ShoppingListService.upsertRecognizedProduct`, then signals list change. | CB-07; KD-08; D-17, D-22 |
| Catalog; Product | `WayTask/Persistence/AddProductSaveCoordinator.swift:31-150`, `AddProductSaveCoordinator.save` | Writer coordinator | Catalog selections route only to catalog persistence; custom selections route to the manual Product writer. | CB-01, CB-07; KD-08; D-17, D-22 |
| Catalog; Product; compatibility ShoppingItem | `WayTask/ProductCatalog/ShoppingItemCatalogResolver.swift:13-17,57-115,168-220` | Reader / metadata writer | Resolves explicit catalog identities and hydrates compatibility metadata; its legacy compatibility crosswalk is ID-only, not name inference. | CB-13, CB-14, CB-16; D-22, D-24, D-33 |
| Catalog; Product Library | `WayTask/Persistence/CatalogProductPersistenceService.swift:91-218,274-319` | R/W/insert/delete/save | Exact catalog Product save restores a matching tombstone, inserts a new Product when absent, and rolls back insertion or restored snapshots on failure. | CB-07; KD-08; D-15, D-17, D-18, D-22, D-35 |
| Migration/recovery | `WayTask/Persistence/WayTaskStartupPersistence.swift:106-335`, `WayTaskStartupPersistenceBootstrap` | Container/repair/recovery | Opens the V3 container, runs list backfill, reports failures, quarantines/recreates on recoverable failure, and can fall back to in-memory persistence. | CB-13, CB-16; D-24, D-27, D-32, D-34 |
| Migration/recovery | `WayTask/Persistence/WayTaskStartupPersistence.swift:337-432`, `WayTaskStoreQuarantine` | Recovery writer | Moves the store and sidecars as a unit with rollback on quarantine failure. | D-34 |
| Map/location | `DebugSeedStoreService.swift:1-55` | Direct ModelContext insert/save | Debug seed path inserts a saved location and saves. | D-23 |
| Map/location | `SettingsView.swift:252-255,435-438` | Direct ModelContext delete/insert/save | Settings directly deletes and creates saved locations. | D-23, D-35 |
| Catalog | `ProductKnowledgeService.swift:91-117` | Direct ModelContext insert/save | Legacy ProductKnowledge service directly inserts catalog knowledge and saves. | CB-16; D-22, D-24 |

## Existing test inventory

E-00 verified 34 tracked files under `WayTaskTests`: 33 Swift files and one JSON test resource. The 33 Swift files contain 291 `func test...` methods. The Xcode project uses a file-system-synchronized test root (`PBXFileSystemSynchronizedRootGroup` at `WayTask.xcodeproj/project.pbxproj:168-170`), so no per-file project membership entries are expected.

| Test source | Methods | Product State relevance |
|---|---:|---|
| `WayTaskTests/FeatureTour/FeatureTourFoundationTests.swift` | 27 | UI foundation; no focused Product State persistence contract |
| `WayTaskTests/Map/MapBottomSheetProductLabelTests.swift` | 2 | Map product presentation |
| `WayTaskTests/Monitoring/SentryStabilityTests.swift` | 9 | Diagnostic stability and privacy controls |
| `WayTaskTests/Onboarding/OnboardingFoundationTests.swift` | 4 | UI foundation |
| `WayTaskTests/Persistence/AddProductSaveCoordinatorTests.swift` | 5 | Catalog/manual save routing |
| `WayTaskTests/Persistence/CatalogProductCompatibilityTests.swift` | 5 | Product/compatibility identity and backfill |
| `WayTaskTests/Persistence/CatalogProductPersistenceServiceTests.swift` | 9 | Catalog save, exact-match restore, rollback |
| `WayTaskTests/Persistence/ProductLibraryDeletionPersistenceTests.swift` | 3 | Tombstone persistence, history survival, non-recreation |
| `WayTaskTests/Persistence/StartupPersistenceResilienceTests.swift` | 4 | Quarantine, retry, in-memory fallback, diagnostics |
| `WayTaskTests/Persistence/StartupRepairIdempotencyTests.swift` | 6 | Interrupted/default-list repair, tombstone stability, idempotency |
| `WayTaskTests/Persistence/WayTaskSchemaMigrationTests.swift` | 5 | V1/V2/V3 graph and file-backed migration |
| `WayTaskTests/ProductCatalog/ProductCatalogAutocompleteTests.swift` | 9 | Catalog acquisition/search |
| `WayTaskTests/ProductCatalog/ProductCatalogCanonicalValidationTests.swift` | 14 | Catalog validation |
| `WayTaskTests/ProductCatalog/ProductCatalogCompatibilityLayerTests.swift` | 3 | Catalog compatibility |
| `WayTaskTests/ProductCatalog/ProductCatalogMigrationTests.swift` | 8 | Catalog artifact migration |
| `WayTaskTests/ProductCatalog/ProductCatalogPersonalizationTests.swift` | 8 | Catalog personalization |
| `WayTaskTests/ProductCatalog/ProductCatalogSearchTests.swift` | 20 | Catalog search |
| `WayTaskTests/ProductCatalog/ProductCatalogServiceTests.swift` | 12 | Catalog loading/service behavior |
| `WayTaskTests/ProductCatalog/SharedCatalogFixtureTests.swift` | 5 | Shared catalog fixture validity |
| `WayTaskTests/ProductKnowledge/BundledProductKnowledgeLoaderTests.swift` | 7 | Legacy knowledge loading |
| `WayTaskTests/ProductKnowledge/InMemoryProductKnowledgeRepositoryTests.swift` | 12 | Legacy knowledge repository |
| `WayTaskTests/ProductKnowledge/LegacyProductCreationCharacterizationTests.swift` | 5 | Existing Product shape, duplicate manual Products, current shopping flow |
| `WayTaskTests/ProductKnowledge/ProductAutocompleteViewModelTests.swift` | 27 | Acquisition UI/view-model behavior |
| `WayTaskTests/ProductKnowledge/ProductEntityTests.swift` | 4 | Product entity fields |
| `WayTaskTests/ProductKnowledge/ProductKnowledgeCatalogValidatorTests.swift` | 27 | Legacy catalog validation |
| `WayTaskTests/ProductKnowledge/ProductKnowledgeIconResolverTests.swift` | 5 | Catalog icon resolution |
| `WayTaskTests/ProductKnowledge/ProductKnowledgeResourceConformanceTests.swift` | 4 | Bundled resource contract |
| `WayTaskTests/ProductKnowledge/ProductKnowledgeSearchPerformanceTests.swift` | 6 | Contains two explicit XCTest `measure(...)` blocks |
| `WayTaskTests/ProductKnowledge/ProductKnowledgeSearchTests.swift` | 18 | Catalog/knowledge search |
| `WayTaskTests/ShoppingClassification/CanonicalCatalogSelectionFlowTests.swift` | 5 | Catalog selection/classification |
| `WayTaskTests/ShoppingClassification/OtherItemsClassificationTests.swift` | 7 | Compatibility classification |
| `WayTaskTests/ShoppingUX/ShoppingWorkspaceUXTests.swift` | 6 | Shopping presentation policy, not persistence semantics |
| `WayTaskTests/ProductKnowledge/Support/ProductKnowledgeFixtureFactory.swift` | 0 | Test support source |

Tracked test resource: `WayTaskTests/ProductCatalog/product_catalog_he_legacy_v2.json`. Its content is not reproduced here.

Static configuration inventory found seven file-backed `ModelConfiguration` sites: five in `WayTaskSchemaMigrationTests`, one in `StartupRepairIdempotencyTests`, and one in `ProductLibraryDeletionPersistenceTests`. Other listed configurations are in-memory. No `XCTAttachment` call was found. These facts do not substitute for the later WT-032B fixture and diagnostic requirements.

## Current-behavior traceability

| ID | Verified repository evidence | Evidence status |
|---|---|---|
| CB-01 | `ShoppingListService.addProductToShopping` creates/reuses compatibility state and an entry; coordinator/service tests cover adjacent save routing. | V-SRC; partial V-TEST |
| CB-02 | Existing entry is unchecked and linked compatibility item is reopened at `ShoppingListService.swift:158-168`. | V-SRC; source-only for focused semantic outcome |
| CB-03 | Removal completes linked compatibility item and deletes one entry at `ShoppingListService.swift:194-209`. | V-SRC; source-only for multi-list semantic outcome |
| CB-04 | Neither `ShoppingListEntry` schema nor migrations declare a uniqueness constraint; existing code uses first-match lookup. | V-SRC; source-only duplicate-entry characterization |
| CB-05 | `ProductLibraryDeletionService.delete` tombstones Product, removes weekly entries, and leaves history/other list kinds untouched; persistence tests cover survival. | V-SRC; V-TEST |
| CB-06 | Product Library deletion has no active-session query or guard. | V-SRC; source-only |
| CB-07 | Barcode upsert and exact catalog save can restore tombstones. | V-SRC; catalog restore V-TEST, barcode path source-only |
| CB-08 | `ShoppingMemoryService` keys history by barcode/name and infers last completion from `isCompleted`. | V-SRC; source-only |
| CB-09 | `ShoppingSessionService.startShopping` returns an existing active session before requested-context validation. | V-SRC; source-only |
| CB-10 | Collect/remaining mutate only `ShoppingSession.collectedItemIDs`. | V-SRC; source-only |
| CB-11 | Finish only mutates session header state and saves. | V-SRC; source-only |
| CB-12 | Decision, discovery, plan, trip, map, location, search, intent, and several UI paths filter `ShoppingItem.isCompleted`. | V-SRC; broad source-only characterization |
| CB-13 | Startup invokes idempotent default-list/backfill repair; existing repair tests cover interrupted and repeated runs. | V-SRC; V-TEST |
| CB-14 | Backfill Product resolution creates only for current-weekly or unlinked incomplete compatibility items, not indiscriminately for historical rows. | V-SRC; V-TEST |
| CB-15 | Geofence notification identifiers/user info carry list and item snapshots plus routing metadata. | V-SRC; source-only payload characterization |
| CB-16 | V1/V2/V3 schemas and lightweight stages are registered; existing file-backed migration tests pass in E-00. | V-SRC; V-TEST |

## Known-defect traceability

These rows locate known defects; they do not approve them.

| ID | Current evidence | Related decisions |
|---|---|---|
| KD-01 | `ShoppingItem.isCompleted` remains a shared compatibility flag with 67 production occurrences and nine reviewed executable writes. | D-01, D-02, D-33 |
| KD-02 | One compatibility item can be linked through nullable legacy IDs across entries/lists; removal mutates shared completion. | D-08, D-10 |
| KD-03 | No durable uniqueness constraint exists for `(shoppingListID, productID)`; migration/backfill can encounter first-match duplicates. | D-09, D-26, D-37 |
| KD-04 | `shoppingListRevision` is an in-memory UUID, not durable Product State. | D-11 |
| KD-05 | `ShoppingPlan` has no source list revision or source entry-ID snapshot. | D-12 |
| KD-06 | Any active session is reused without requested-context conflict evaluation. | D-14, D-29 |
| KD-07 | Product Library deletion does not inspect an active session. | D-16 |
| KD-08 | Scanner barcode upsert and catalog add can implicitly restore tombstones. | D-17, D-22 |
| KD-09 | Finish does not reconcile entry purchased/remaining state, history, Product State, or plan invalidation. | D-03, D-04, D-35, D-36 |
| KD-10 | Product history aggregates by barcode/name rather than immutable Product UUID ownership. | D-06, D-07, D-31 |
| KD-11 | Completed/Recent are durable list kinds and completion can be inferred from the compatibility flag. | D-19, D-30 |
| KD-12 | Consumers and UI mix entry checked state, compatibility completion, persisted Completed/Recent lists, and plan/session snapshots. | D-20, D-21 |

## WT-032A decision traceability

This is a static comparison of the current repository to each approved decision. “Gap” means the approved Phase 0 concept is not represented by current Product State; it is not implementation approval in E-01.

| Decision | Current repository evidence / gap |
|---|---|
| D-01 | Current global compatibility completion is still read/written across 19 files; no separated target-state field exists. |
| D-02 | Entry identity is partly represented by `ShoppingListEntry.productID`, but compatibility behavior still uses `ShoppingItem.isCompleted`. |
| D-03 | Session collect state is separate in encoded IDs; entry state remains a single `isChecked` boolean, so collected/purchased semantics are not represented. |
| D-04 | `finishShopping` changes only session header state; no outcome-specific reconciliation exists. |
| D-05 | No explicit abandon command or abandoned terminal session field is present. |
| D-06 | `ProductHistory` is a separate aggregate keyed by barcode/name, not immutable Product UUID ownership. |
| D-07 | No Product History retention/deletion policy is implemented in the inventoried paths. |
| D-08 | Multiple `ShoppingList` rows and list-scoped entries are possible; compatibility state remains shared. |
| D-09 | Service-level first-match behavior exists, but no schema uniqueness constraint exists. |
| D-10 | Current reopen behavior unchecks an existing entry and reopens compatibility completion. |
| D-11 | Revision is only the in-memory `AppStateManager.shoppingListRevision` UUID. |
| D-12 | Plan/session carry partial snapshots; neither stores an immutable source-entry snapshot plus durable revision. |
| D-13 | No active-session edit boundary is enforced by list mutation paths. |
| D-14 | Session start reuses any active session instead of exposing a conflict result. |
| D-15 | Library removal uses a durable `deletedAt` tombstone and removes matching weekly entries. |
| D-16 | No active-session block exists in Product Library deletion. |
| D-17 | Restore helpers exist, but scanner/catalog current paths can invoke them implicitly. |
| D-18 | Tombstones are durable and no expiry/purge policy was found. |
| D-19 | Home and store readers derive Completed/Recent semantics from persisted list kinds and compatibility completion. |
| D-20 | UI surfaces mix `isChecked` and `isCompleted`; legacy/current behavior is explicitly identified above. |
| D-21 | Notification taps route list/item/store snapshots into map context, while Home derives current list views independently. |
| D-22 | Catalog save and scanner barcode upsert are current implicit-restore acquisition paths. |
| D-23 | Saved `GeoLocation.shoppingItems` is a legacy evidence path; map/settings/location views mutate it directly. |
| D-24 | `WayTaskSchemaMigrationPlan` owns V1→V2→V3 migration; startup backfill owns row repair. |
| D-25 | Lightweight schema migration does not map legacy completion into new Product State because target state is not present; backfill still repairs compatibility links. |
| D-26 | No deterministic duplicate-entry migration is present beyond current first-match/backfill behavior. |
| D-27 | Backfill has explicit orphan/link resolution and controlled Product creation paths. |
| D-28 | No explicit legacy-session-to-new-session migration exists; current session shape is retained across all three schema graphs. |
| D-29 | Multiple active sessions are not reconciled; fetch-first reuse returns one active session. |
| D-30 | Completed/Recent remain persisted `ShoppingListKind` values; no new derived-state migration exists. |
| D-31 | Legacy Product History remains barcode/name-keyed; no UUID-first conversion exists. |
| D-32 | Tombstone repair completes compatibility items and removes active weekly entries. |
| D-33 | Compatibility fields/models remain live in current schema and consumers. |
| D-34 | Startup has quarantine/recreate/retry/in-memory fallback and diagnostics; it does not provide a new Product State migration rollback because that migration does not yet exist. |
| D-35 | Product/list behaviors use multiple direct mutation/save paths; no single target atomic command boundary exists. |
| D-36 | Finish is a session-header save only and is not atomic Product State reconciliation. |
| D-37 | No durable uniqueness or revision constraints exist in the current schemas. |

## Validation and source-only gaps

### E-01 validation

1. The approved E-00 branch, commit, clean status, environment, build, test, protected hashes, and test inventory are recorded.
2. Every minimum reader/writer path named by WT-032B Section 4.3 is represented:
   - `ShoppingItem.isCompleted` across Product, Home, Shopping, decision, discovery, map, location, store search, context, session, trip, and app-state paths.
   - `ShoppingListEntry.isChecked` across service, Shopping/Home UI, diagnostics, models, and frozen/current schemas.
   - `legacyShoppingItemID` across list service, Product/Shopping/Home UI, catalog resolution, model definitions, and V1/V2/V3.
   - `Product.deletedAt` across Product Library UI/service, catalog persistence, barcode upsert, startup repair, and persistence tests.
   - Direct `ModelContext` insert/delete/save calls, including the required `ShoppingListService`, `ShoppingWorkspaceView`, `ContentView`, and `LocationDetailView` mutation paths.
   - Required plan/session/discovery/map/location/notification/acquisition/recovery consumers.
3. Reproducible read-only commands, counts, paths, symbols, categories, and useful line references are recorded.
4. CB-01…CB-16, KD-01…KD-12, and D-01…D-37 are all traceable.
5. Legacy/current behavior is labeled. Verified facts are separated from interpretation.
6. No private value or fixture content is included.

### Problems and gaps found

- Focused runtime characterization is absent for CB-02, CB-03 multi-list behavior, CB-04, CB-06, CB-08 through CB-12, CB-15, and the scanner side of CB-07. Their E-01 evidence is source-only.
- The repository has no Phase 1 deterministic fixture manifest/digest, semantic digest, migration diagnostic capture, or Product State performance baseline. Those are later-step evidence and were not fabricated or executed in E-01.
- Existing test coverage is strong for schema migration, startup repair/recovery, catalog persistence, and Product Library tombstones, but it does not yet provide a focused Product State suite for list uniqueness, active-session conflicts, finish reconciliation, or history ownership.
- Existing explicit performance tests cover Product Knowledge search, not Phase 1 Product State command/query budgets.
- Existing notification/geofence source carries snapshot fields whose values can be sensitive. E-01 recorded field names only; it did not capture payloads, logs, screenshots, or runtime data.
- No `XCTAttachment` call exists in current tests. This is only a static fact; later diagnostic evidence requirements remain pending.

## E-01 boundary

At the point this record was created, E-01 performed static inspection only and did not build, test, migrate, seed, or mutate Product State. The only approved repository path for E-01 is this evidence record:

`docs/ImplementationEvidence/1.0.3/WT-031A_Phase1_ProductStateBaseline.md`

Final read-only validation produced:

| Check | Result |
|---|---|
| `git branch --show-current` | `main` |
| `git rev-parse HEAD` | `98da1a4c3a0d737ac0d53ad638a6ed21c28cbed4` |
| `git status --short --untracked-files=all` | Only `?? docs/ImplementationEvidence/1.0.3/WT-031A_Phase1_ProductStateBaseline.md` |
| `git diff --name-only` | Empty; no tracked working-tree file changed |
| `git diff --cached --name-only` | Empty; no staged file changed |
| Protected hashes | All ten individual hashes and the tracked-test-tree aggregate match E-00 |
| Trace IDs | CB-01…CB-16, KD-01…KD-12, and D-01…D-37 all present |
| Required source paths/lifecycles | All WT-032B Section 4.3 minimums present |

No production file, test, schema, project file, package file, localization, Catalog artifact, or previous WT document was created or modified. E-02 was not executed.
