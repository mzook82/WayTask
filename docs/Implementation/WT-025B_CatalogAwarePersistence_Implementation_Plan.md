# WT-025B — Catalog-Aware Persistence Implementation Plan

## 1. Executive Summary

WT-025C should implement catalog-aware persistence as a small additive evolution of
the existing user-owned `Product` model.

The implementation will:

- freeze the exact shipped SwiftData graph as schema V1;
- define schema V2 as the same eight-model graph with seven nullable catalog fields on
  `Product`;
- migrate V1 to V2 with one lightweight migration stage;
- construct the app's `ModelContainer` explicitly with the V2 schema and migration
  plan while retaining the default production store configuration;
- add `.catalog` to `ProductSource`;
- add an explicit catalog-save request, outcome, typed error set, and main-actor
  persistence service;
- deduplicate catalog saves only by exact Product Knowledge `ProductID`;
- protect linked products from unresolved recognition and legacy backfill refreshes;
- prevent known catalog products from being copied into the legacy learned
  `ProductKnowledge` store;
- keep `ShoppingListService.addManualProduct` unchanged;
- leave autocomplete and every catalog write entry point disconnected from production
  UI until all persistence gates pass.

`notes` is deferred. It is user-owned data but is not required to preserve a catalog
identity or its display snapshot, and there is no current notes workflow for Product.
Deferring it keeps V2 limited to catalog support and avoids an unrelated persistence
change.

The source audit found no material conflict with
`CatalogAwarePersistenceArchitecture.md`. It found three implementation facts that
the implementation must address explicitly:

1. the current store has no `VersionedSchema` or `SchemaMigrationPlan`;
2. the current test helper is in-memory only and therefore does not exercise store
   migration;
3. `ProductSearchResult.matchedLocale` is match provenance, not necessarily the locale
   of `displayName`, and the result currently has no localized category display text.

These are implementation gaps, not architecture blockers.

### Scope boundary

WT-025C may add persistence infrastructure and tests, but it must not:

- activate autocomplete;
- route the current Add Product button to catalog persistence;
- change manual creation semantics;
- infer catalog links for existing products;
- persist `ProductEntity`;
- add a catalog ID to `ShoppingItem` or `ShoppingListEntry`;
- add a uniqueness constraint or index;
- implement catalog refresh, manual-to-catalog linking, redirects, or merges;
- modify Product Knowledge resources;
- create an XCUITest target;
- add `notes`.

## 2. Source Audit

### 2.1 Files inspected

#### Approved architecture and UX inputs

- `docs/Architecture/CatalogAwarePersistenceArchitecture.md`
- `docs/Implementation/WT-024A_ProductAutocompleteUIIntegration_Plan.md`
- `docs/Specifications/ProductSearchUXContract.md`
- `docs/Architecture/ProductKnowledgeArchitecture.md`
- `docs/Architecture/ProductEntityDataModel.md`

#### SwiftData models and app composition

- `WayTask/Models.swift`
- `ProductKnowledge.swift`
- `ProductHistory.swift`
- `ShoppingSession.swift`
- `WayTask/WayTaskApp.swift`
- `WayTask/ContentView.swift`

#### Product creation, recognition, compatibility, and learning

- `ShoppingListService.swift`
- `ProductListView.swift`
- `CameraView.swift`
- `CameraViewModel.swift`
- `ProductKnowledgeService.swift`
- `ShoppingMemoryService.swift`
- `ProductCandidate.swift`
- `ProductSource.swift`
- `RecognitionResult.swift`

#### Product Knowledge search boundary

- `WayTask/ProductKnowledge/Domain/ProductEntity.swift`
- `WayTask/ProductKnowledge/Domain/ProductName.swift`
- `WayTask/ProductKnowledge/Domain/ProductCategory.swift`
- `WayTask/ProductKnowledge/Domain/ProductSearchResult.swift`
- `WayTask/ProductKnowledge/Application/ProductKnowledgeRepository.swift`
- `WayTask/ProductKnowledge/Application/ProductKnowledgeSearch.swift`
- `WayTask/ProductKnowledge/Data/InMemoryProductKnowledgeRepository.swift`

#### Tests and Xcode configuration

- `WayTaskTests/ProductKnowledge/LegacyProductCreationCharacterizationTests.swift`
- `WayTaskTests/ProductKnowledge/ProductKnowledgeSearchTests.swift`
- `WayTaskTests/ProductKnowledge/ProductKnowledgeSearchPerformanceTests.swift`
- `WayTaskTests/ProductKnowledge/InMemoryProductKnowledgeRepositoryTests.swift`
- `WayTaskTests/ProductKnowledge/ProductEntityTests.swift`
- `WayTaskTests/ProductKnowledge/BundledProductKnowledgeLoaderTests.swift`
- `WayTaskTests/ProductKnowledge/ProductKnowledgeCatalogValidatorTests.swift`
- `WayTaskTests/ProductKnowledge/ProductKnowledgeResourceConformanceTests.swift`
- `WayTask.xcodeproj/project.pbxproj`
- `WayTask.xcodeproj/xcshareddata/xcschemes/WayTask.xcscheme`

### 2.2 Exact shipped SwiftData graph

The production app currently passes these model types, in this order, to the SwiftUI
`.modelContainer(for:)` modifier:

```text
1. GeoLocation
2. ShoppingItem
3. Product
4. ShoppingList
5. ShoppingListEntry
6. ProductHistory
7. ProductKnowledge
8. ShoppingSession
```

There are no other production `@Model` types.

#### GeoLocation

Persisted attributes:

```text
id: UUID
title: String
latitude: Double
longitude: Double
radius: Double
storeCategoryRawValue: String?
addressText: String?
notes: String?
sourceTypeRawValue: String?
```

Relationship:

```text
shoppingItems: [ShoppingItem]
delete rule: cascade
```

#### ShoppingItem

Persisted attributes:

```text
id: UUID
name: String
isCompleted: Bool
imageData: Data?
brand: String?
category: String?
barcode: String?
imageURLString: String?
dateAdded: Date
sourceRawValue: String
productType: String?
flavor: String?
packageSize: String?
packageType: String?
visibleText: String?
searchKeywordsRawValue: String?
```

There is no catalog identity and no Product relationship.

#### Product

Persisted attributes:

```text
id: UUID
legacyShoppingItemID: UUID?
name: String
imageData: Data?
brand: String?
category: String?
barcode: String?
imageURLString: String?
dateAdded: Date
updatedAt: Date
sourceRawValue: String
productType: String?
flavor: String?
packageSize: String?
packageType: String?
visibleText: String?
searchKeywordsRawValue: String?
```

There are no declared relationships on `Product`.

#### ShoppingList

Persisted attributes:

```text
id: UUID
title: String
kindRawValue: String
createdAt: Date
updatedAt: Date
isDefault: Bool
```

#### ShoppingListEntry

Persisted attributes:

```text
id: UUID
shoppingListID: UUID
productID: UUID
legacyShoppingItemID: UUID?
quantity: Double
isChecked: Bool
createdAt: Date
sortOrder: Double
```

Relationship:

```text
product: Product?
delete rule: nullify
```

`productID` is the UUID of the user-library `Product`. It is not a Product Knowledge
identifier.

#### ProductHistory

Persisted attributes:

```text
id: UUID
productKey: String
productName: String
barcode: String?
firstAddedDate: Date
lastAddedDate: Date
addCount: Int
lastSourceRawValue: String
averageInterval: TimeInterval?
lastCompletedDate: Date?
```

#### ProductKnowledge

This is the legacy learned recognition model, not the read-only Product Knowledge
catalog.

Persisted attributes:

```text
id: UUID
knowledgeKey: String
barcode: String?
productName: String
preferredDisplayName: String?
brand: String?
category: String?
productType: String?
flavor: String?
packageSize: String?
thumbnailData: Data?
imageURLString: String?
searchKeywordsRawValue: String?
aiConfidence: Double?
recognitionSourceRawValue: String?
dateLearned: Date
lastUsed: Date?
timesUsed: Int
updatedAt: Date
```

#### ShoppingSession

Persisted attributes:

```text
id: UUID
startedAt: Date
finishedAt: Date?
isActive: Bool
itemIDListRawValue: String
collectedItemIDListRawValue: String
shoppingListID: UUID?
selectedStoreID: UUID?
selectedStoreName: String?
selectedStoreLatitude: Double?
selectedStoreLongitude: Double?
```

### 2.3 Current container construction

`WayTaskApp.body` currently uses:

```text
.modelContainer(for: [the eight model types])
```

Consequences:

- SwiftUI creates the `ModelContainer`;
- the store uses SwiftData's default configuration and URL;
- no migration plan is supplied;
- no container-construction error can be handled by app code;
- the implicit schema version is `1.0.0`;
- the main context is supplied through the environment.

WT-025C must preserve the default configuration rather than inventing a named store,
group container, CloudKit mode, or new URL. The explicit container initializer should
therefore receive the V2 schema and migration plan with no custom production
configuration. SwiftData will create its normal default configuration just as it does
today.

### 2.4 Every current Product initializer

| Initializer or creation site | Current caller | Current purpose |
| --- | --- | --- |
| `Product.init(...)` | `ShoppingListService.addManualProduct` | Manual library product |
| `Product.init(legacyItem:)` | `ShoppingListBackfillService.product(for:)` | Convert legacy ShoppingItem |
| `Product.init(candidate:fallbackImageData:)` | `ShoppingListService.upsertRecognizedProduct` | Insert unresolved recognized product |

There are no other production `Product(...)` construction sites.

The main initializer must gain catalog parameters with `nil` defaults so all three
existing paths remain source-compatible and create unlinked products unless the new
catalog service explicitly supplies catalog values.

### 2.5 Every Product mutation and deletion path

| File and method | Product fields affected | Required WT-025C behavior |
| --- | --- | --- |
| `Product.refresh(from: ShoppingItem)` | legacy ID, effective name/photo/details/source, `updatedAt` | Return without mutation for any nonnil catalog reference |
| `Product.refresh(from: ProductCandidate, fallbackImageData:)` | effective name/photo/details/source, `updatedAt` | Return without mutation for any nonnil catalog reference |
| `ShoppingListService.upsertRecognizedProduct` | invokes candidate refresh or inserts Product | Match only products whose catalog raw ID is `nil` |
| `ShoppingListService.addProductToShopping` | sets `legacyShoppingItemID` | Preserve every catalog field |
| `ShoppingListService.openCompatibilityItem` | may set `legacyShoppingItemID` | Preserve every catalog field |
| `ShoppingListBackfillService.ensureDefaultListsAndBackfill` | invokes legacy refresh and repairs entry relationships | Skip legacy refresh for linked Product; still repair relationships |
| `ProductListView.replaceImage` | `imageData`, `updatedAt` | No catalog-field assignment; behavior remains safe |
| `ProductListView.cacheRemoteImage` | `imageData`, `updatedAt` | No catalog-field assignment; behavior remains safe |
| `ProductListView.deleteFilteredProducts` | deletes Product after removing shopping membership | No new catalog-specific cascade or catalog deletion |

The following methods write compatibility `ShoppingItem` fields from a `Product` but
do not overwrite the Product:

- `ShoppingListService.refresh(_:from:)`;
- `ProductListView.syncCompatibilityItems(from:)`;
- `Product.makeShoppingItem()`.

They should continue copying effective fields. They must not gain a catalog reference
because `ShoppingItem` remains a compatibility snapshot.

### 2.6 Backfill triggers

`ContentView` invokes `ShoppingListBackfillService.ensureDefaultListsAndBackfill`:

- on initial appearance;
- when the legacy ShoppingItem signature changes;
- when the scene becomes active.

This is not a one-time migration. It is a recurring writer. Protection must therefore
exist in production code, not only in migration tests.

### 2.7 Recognition and legacy learning

`ShoppingListService.upsertRecognizedProduct` currently:

1. fetches all Products;
2. matches first by normalized barcode;
3. otherwise matches by normalized name plus brand or category;
4. refreshes the match or inserts a Product;
5. calls `ProductKnowledgeService.learn`;
6. saves.

Without a linked-product filter, a later camera or barcode result could overwrite a
catalog Product's effective values.

`ShoppingListService.addProductToShopping` currently writes a compatibility
`ShoppingItem`, then records `ProductHistory` and legacy learned `ProductKnowledge`.
The ProductHistory behavior may remain name/barcode based for compatibility. The
legacy `ProductKnowledge` write must be skipped when the source Product has a catalog
reference.

### 2.8 Exhaustive ProductSource switches

Only two production switches are exhaustive over `ProductSource`:

1. `ProductSource.displayName` in `ProductSource.swift`;
2. `ProductKnowledgeService.candidateSource(for:)`.

The switches in `Product.init(candidate:)`,
`Product.source(for:)`, and `ShoppingListService.source(for:)` are over
`ProductCandidateSource`, not `ProductSource`; adding `.catalog` does not make them
non-exhaustive.

Raw decoding in these types requires no switch change:

- `Product.source`;
- `ShoppingItem.source`;
- `ProductHistory.lastSource`.

They already use `ProductSource(rawValue:)`, so a new raw value is recognized by the
updated binary and unknown historical values continue to fall back to `.manual`.

### 2.9 ProductSearchResult conflict check

The current result contains:

```text
productID
displayName
secondaryName
categoryID
iconKey
matchedRecordAuthority
matchType
matchedLocale
```

It lacks:

- `categoryDisplayName`;
- `displayLocale`.

`matchedLocale` belongs to the name or alias that matched the query. Search may choose
a different preferred `ProductName` as `displayName`; therefore persisting
`matchedLocale` as the display snapshot's locale would be incorrect.

WT-025C should add both missing fields while preserving ranking and match metadata.
This is consistent with WT-024A and WT-025A and is not a material architecture
conflict.

### 2.10 Current test infrastructure

The repository has:

- one hosted `WayTaskTests` unit-test target;
- a shared `WayTask` scheme that runs it;
- filesystem-synchronized `WayTask` and `WayTaskTests` groups;
- SwiftData available through `@testable import WayTask`;
- default MainActor isolation for the target.

New Swift files inside those synchronized folders do not require manual project-file
membership changes.

The only current persistence helper creates:

```text
ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
```

Therefore the current tests cannot demonstrate a store migration. The target can,
however, create a true file-backed V1 fixture at runtime by:

1. allocating a unique temporary directory and explicit store URL;
2. creating a container with the frozen V1 schema and no migration plan;
3. inserting the full eight-model fixture and saving it;
4. releasing every V1 context and model;
5. opening the same URL with the V2 schema and migration plan;
6. fetching V2 model types and asserting preservation.

No checked-in SQLite resource and no Xcode configuration change are needed.

### 2.11 Architecture conflict decision

No material conflict requires stopping WT-025B.

The only scope refinement is `notes`: WT-025A identified it as a recommended
user-owned field, while this task explicitly asks whether it belongs in the smallest
catalog migration. It is deferred because none of the catalog identity, snapshot,
deduplication, update-survival, recognition, or compatibility contracts depend on it.

### 2.12 SwiftData API basis

Apple's SwiftData guidance requires each previously released shape to be captured as a
`VersionedSchema`, orders those schemas through `SchemaMigrationPlan`, and supports a
lightweight stage for compatible changes. The default unversioned
`Schema([modelTypes])` version is `1.0.0`.

Relevant primary references:

- [VersionedSchema](https://developer.apple.com/documentation/swiftdata/versionedschema)
- [SchemaMigrationPlan](https://developer.apple.com/documentation/swiftdata/schemamigrationplan)
- [MigrationStage](https://developer.apple.com/documentation/swiftdata/migrationstage)
- [Model your schema with SwiftData](https://developer.apple.com/videos/play/wwdc2023/10195/)
- [ModelContainer configuration defaults](https://developer.apple.com/documentation/swiftdata/modelcontainer/configurations)

## 3. Schema Versioning Plan

### 3.1 Schema organization

Create:

```text
WayTask/Persistence/WayTaskSchemaV1.swift
WayTask/Persistence/WayTaskSchema.swift
```

`WayTaskSchemaV1.swift` freezes only the two model types that cannot be shared across
versions:

- V1 `Product`, because V2 adds fields;
- V1 `ShoppingListEntry`, because its relationship must target the V1 Product type.

All other model types are structurally unchanged and can be shared by V1 and V2. This
is the pattern supported by versioned schemas: unchanged model classes may appear in
multiple versions, while changed classes receive version-specific definitions.

### 3.2 Exact V1 schema

Define:

```text
enum WayTaskSchemaV1: VersionedSchema
versionIdentifier = Schema.Version(1, 0, 0)
```

Its model list must be exactly:

```text
GeoLocation.self
ShoppingItem.self
WayTaskSchemaV1.Product.self
ShoppingList.self
WayTaskSchemaV1.ShoppingListEntry.self
ProductHistory.self
ProductKnowledge.self
ShoppingSession.self
```

The order mirrors the shipped container declaration.

#### Frozen V1 Product

Define a nested V1 `@Model final class Product` with exactly the 17 persisted
properties listed in Section 2.2:

```text
id
legacyShoppingItemID
name
imageData
brand
category
barcode
imageURLString
dateAdded
updatedAt
sourceRawValue
productType
flavor
packageSize
packageType
visibleText
searchKeywordsRawValue
```

It must not contain:

- catalog fields;
- notes;
- uniqueness constraints;
- indexes;
- relationships;
- renamed attributes;
- new default values that alter the schema.

It needs only fixture-construction initialization. Production behavior methods do not
belong on the frozen type.

#### Frozen V1 ShoppingListEntry

Define a nested V1 `@Model final class ShoppingListEntry` with exactly:

```text
id: UUID
shoppingListID: UUID
productID: UUID
legacyShoppingItemID: UUID?
quantity: Double
isChecked: Bool
createdAt: Date
sortOrder: Double
product: WayTaskSchemaV1.Product?
```

The relationship uses delete rule `.nullify`.

No other model is copied. Sharing the other six current model classes prevents a
hand-maintained duplicate from drifting unnecessarily.

### 3.3 V1 parity gate

Before adding any V2 Product field:

1. construct the currently shipped unversioned schema from the existing eight global
   model types;
2. construct `Schema(versionedSchema: WayTaskSchemaV1.self)`;
3. compare:
   - version `1.0.0`;
   - entity-name set;
   - property-name set per entity;
   - attribute optionality and value types;
   - relationship destination entity;
   - relationship delete rules;
4. assert `Schema.entityName` for the nested V1 Product and Entry matches the shipped
   entity names;
5. create and reopen a V1-only file-backed fixture with no migration plan.

The implementation must not proceed to Product field additions if this parity check
fails. A nested type that generates a different entity identity is not an acceptable
approximation.

### 3.4 Exact V2 schema

Define:

```text
enum WayTaskSchemaV2: VersionedSchema
versionIdentifier = Schema.Version(2, 0, 0)
```

Its model list is the exact current production types, in the same order:

```text
GeoLocation.self
ShoppingItem.self
Product.self
ShoppingList.self
ShoppingListEntry.self
ProductHistory.self
ProductKnowledge.self
ShoppingSession.self
```

The only persisted schema difference from V1 is seven nullable attributes added to
`Product`.

### 3.5 Migration plan

Define:

```text
enum WayTaskSchemaMigrationPlan: SchemaMigrationPlan
schemas = [WayTaskSchemaV1.self, WayTaskSchemaV2.self]
stages = [migrateV1toV2]
```

`migrateV1toV2` is:

```text
MigrationStage.lightweight(
    fromVersion: WayTaskSchemaV1.self,
    toVersion: WayTaskSchemaV2.self
)
```

There is no custom `willMigrate` or `didMigrate` closure because:

- every new field is nullable;
- existing rows naturally receive `nil`;
- no current attribute is renamed or deleted;
- no relationship changes;
- no matching, normalization, or backfill is allowed;
- no data-dependent transformation is needed.

If SwiftData rejects the transition as non-lightweight, that is a FAIL gate. Do not
replace it with a destructive store recreation or an unreviewed custom migration.

### 3.6 Model-container factory

`WayTaskSchema.swift` should expose one container factory with:

- `currentSchema = Schema(versionedSchema: WayTaskSchemaV2.self)`;
- `migrationPlan = WayTaskSchemaMigrationPlan.self`;
- a production constructor with no explicit configurations;
- an internal constructor that accepts `[ModelConfiguration]` for tests.

Production behavior:

```text
ModelContainer(
    for: currentSchema,
    migrationPlan: WayTaskSchemaMigrationPlan.self,
    configurations: []
)
```

An empty configuration array asks SwiftData to create its default configuration. This
avoids changing the current store URL, configuration name, app-group selection, or
CloudKit inference.

Test behavior supplies a `ModelConfiguration` with:

- the V1 or V2 schema;
- a unique temporary file URL;
- CloudKit disabled;
- saving enabled.

### 3.7 App composition

Change `WayTaskApp` from the type-list modifier to an explicitly constructed
`ModelContainer`:

```text
WayTaskModelContainer.makeDefault()
↓
WindowGroup
↓
.modelContainer(container)
```

Container creation happens once.

On failure:

- start/call existing diagnostics where safely available;
- report the container-construction failure;
- stop before showing an empty user-data experience;
- do not delete, rename, move, or recreate the store;
- do not fall back to an in-memory container.

The implementation may fail fast because no migration-error UI is approved in this
task. Preserving the store is more important than launching with apparently lost data.

## 4. Product Model Change Plan

### 4.1 Exact persisted fields

Add exactly these seven stored properties to the current `Product`:

| Field | Swift type | Optional | Declaration/init default | Persisted representation |
| --- | --- | ---: | --- | --- |
| `catalogProductIDRawValue` | `String?` | Yes | `nil` | Nullable string |
| `catalogDisplayNameSnapshot` | `String?` | Yes | `nil` | Nullable string |
| `catalogDisplayLocaleSnapshot` | `String?` | Yes | `nil` | Nullable locale string |
| `catalogCategoryIDSnapshotRawValue` | `String?` | Yes | `nil` | Nullable string |
| `catalogCategoryDisplayNameSnapshot` | `String?` | Yes | `nil` | Nullable string |
| `catalogIconKeySnapshot` | `String?` | Yes | `nil` | Nullable semantic key |
| `catalogSnapshotUpdatedAt` | `Date?` | Yes | `nil` | Nullable date |

Do not add:

- `notes`;
- catalog revision;
- catalog status;
- aliases;
- a ProductEntity relationship;
- an icon asset/SF Symbol name;
- a uniqueness constraint;
- an index.

### 4.2 Field behavior

#### catalogProductIDRawValue

- Ownership: Product Knowledge identity reference.
- New catalog initializer: exact `ProductID.rawValue`.
- Manual/legacy/unresolved recognition initializer: `nil`.
- Read fallback: any nonnil value protects the Product as catalog-linked; a malformed
  value is diagnosed but is not treated as permission for heuristic overwrite.
- New-write validation:
  - nonempty;
  - no leading/trailing whitespace;
  - stored exactly, without lowercasing or normalization;
  - supplied by `ProductSearchResult` or a future approved typed resolver.

Add a read-only computed `catalogProductID: ProductID?` only when the raw value passes
the nonempty/no-surrounding-whitespace check.

Add:

```text
isCatalogLinked = catalogProductIDRawValue != nil
```

The raw nonnil check is intentionally fail-safe for corrupted partial records.

#### catalogDisplayNameSnapshot

- Ownership: catalog snapshot.
- New catalog initializer: exact localized `ProductSearchResult.displayName`.
- Existing effective `name`: initialized to the same value.
- Read fallback: current screens continue reading `Product.name`; future snapshot
  readers fall back to `name` if this snapshot is absent.
- Validation: nonempty after trimming, but persist the original approved value.

#### catalogDisplayLocaleSnapshot

- Ownership: catalog snapshot metadata.
- New catalog initializer: actual locale of the `ProductName` used for
  `displayName`, not `matchedLocale`.
- Read fallback: `nil` means locale is unknown; do not infer it from current device
  locale.
- Validation: nonempty, no surrounding whitespace.

#### catalogCategoryIDSnapshotRawValue

- Ownership: catalog snapshot, not a live SwiftData relationship.
- New catalog initializer: exact `ProductCategoryID.rawValue`.
- Read fallback: `nil`; current UI may continue using `Product.category`.
- Validation: nonempty, no surrounding whitespace, no normalization.

#### catalogCategoryDisplayNameSnapshot

- Ownership: localized catalog snapshot.
- New catalog initializer: the category label resolved for the requested app locale.
- Existing effective `category`: initialized to the same value.
- Read fallback: `Product.category`.
- Validation: nonempty after trimming, while persisting the approved display text
  exactly.

#### catalogIconKeySnapshot

- Ownership: catalog snapshot.
- New catalog initializer: `ProductSearchResult.iconKey`.
- Read fallback: the semantic generic product key at presentation time; do not write
  the fallback into migrated rows.
- Validation: nonempty, no surrounding whitespace.
- Never contains an SF Symbol or asset name.

#### catalogSnapshotUpdatedAt

- Ownership: catalog snapshot metadata.
- New catalog initializer: the same injected operation time used for `dateAdded` and
  `updatedAt`.
- Read fallback: `nil` means no trustworthy capture time.
- Validation: required for a new linked record.

### 4.3 Initializer changes

Append the seven optional parameters to the main `Product.init`, all defaulting to
`nil`. Assign them directly.

Existing call-site behavior:

| Path | Result |
| --- | --- |
| `addManualProduct` | all seven fields `nil` |
| `Product(legacyItem:)` | all seven fields `nil` |
| `Product(candidate:)` | all seven fields `nil` |
| catalog persistence service | all seven fields nonnil |

Do not add catalog parameters to the legacy or candidate convenience initializers.
Their omission is an explicit identity boundary.

### 4.4 Defensive refresh behavior

At the beginning of both:

```text
Product.refresh(from: ShoppingItem)
Product.refresh(from: ProductCandidate, fallbackImageData:)
```

return without mutation when `catalogProductIDRawValue != nil`.

Caller filtering remains required. The model guard is defense in depth for future call
sites.

### 4.5 Effective values and snapshots

For a new catalog Product:

```text
name = catalogDisplayNameSnapshot
category = catalogCategoryDisplayNameSnapshot
imageData = request.imageData
brand/barcode/detail fields = nil
```

Current UI remains snapshot-stable because it already reads `name`, `category`, and
`imageData`.

WT-025C does not implement catalog refresh or user edits to name/category. A later
refresh can compare the effective value to the old snapshot before applying new
catalog text.

### 4.6 Notes decision

`notes` is deferred.

Reasons:

- no current Product notes field or UI exists;
- it is not needed for ProductID, display, category, icon, photo, timestamps, or
  duplicate handling;
- adding it would expand migration and acceptance scope without enabling catalog
  persistence;
- it can be added later as another nullable, user-owned field.

GeoLocation's existing `notes` property is unrelated and unchanged.

## 5. ProductSource Plan

### 5.1 Add catalog acquisition source

Add:

```text
case catalog
```

with raw value `"catalog"` and display name `"Catalog"`.

Do not reuse `.discover`. `discover` is an existing acquisition label and must remain
backward compatible; Product Knowledge catalog selection should have an unambiguous
source.

### 5.2 Exact switch updates

#### ProductSource.swift

Update `displayName`:

```text
case .catalog:
    return "Catalog"
```

#### ProductKnowledgeService.swift

Update `candidateSource(for:)`:

```text
case .catalog:
    return .unknown
```

This is a defensive compatibility mapping only. A linked catalog Product must
normally be prevented from entering `ProductKnowledgeService.learn(from:
ShoppingItem)`.

### 5.3 No-change mappings

The exhaustive switches over `ProductCandidateSource` do not change:

- `Product.init(candidate:)`;
- `Product.source(for:)`;
- `ShoppingListService.source(for:)`;
- `ProductKnowledgeService.sourcePriority`.

Catalog-resolved recognition does not invent a `ProductCandidateSource.catalog`.
Instead, the catalog save request carries the stable ProductID and an acquisition
`ProductSource` of `.camera`, `.ai`, or `.barcode`.

### 5.4 Backward compatibility

- Existing raw source strings remain unchanged.
- Existing binaries do not need data migration for the enum because SwiftData stores
  a string.
- The V2 binary recognizes `"catalog"`.
- Unknown source strings continue to fall back to `.manual` in existing getters.
- A rollback build must include the `.catalog` enum case even when autocomplete is
  disabled, so it is V2-compatible.

## 6. Catalog Save Types

Create all catalog save types in:

```text
WayTask/Persistence/CatalogProductPersistenceService.swift
```

### 6.1 CatalogProductSaveRequest

Define an immutable, `Sendable` value:

```text
CatalogProductSaveRequest
  productID: ProductID
  displayNameSnapshot: String
  displayLocaleSnapshot: String
  categoryIDSnapshot: ProductCategoryID
  categoryDisplayNameSnapshot: String
  iconKeySnapshot: String
  imageData: Data?
  source: ProductSource
```

Initializers:

1. an internal complete initializer for tests and future approved resolvers;
2. a convenience initializer from `ProductSearchResult`, optional image data, and
   source defaulting to `.catalog`.

The `ProductSearchResult` initializer uses:

```text
productID
displayName
displayLocale
categoryID
categoryDisplayName
iconKey
```

It must not use:

- raw name-field text;
- `secondaryName`;
- `matchedLocale`;
- match type or authority;
- a fresh repository lookup that changes the selected display text.

Responsibilities:

- carry one explicit selection snapshot across the UI/persistence boundary;
- preserve typed catalog IDs;
- carry user photo bytes.

Non-responsibilities:

- search;
- ranking;
- manual-name validation;
- repository mutation;
- duplicate resolution;
- SwiftData access;
- catalog refresh.

### 6.2 ProductSearchResult additions

Add:

```text
categoryDisplayName: String
displayLocale: String
```

`ProductKnowledgeSearch` populates:

- `displayLocale` from the actual chosen preferred display `ProductName.locale`;
- `categoryDisplayName` from the indexed category:
  - Hebrew when requested primary language is `he`;
  - English otherwise;
  - a stable generic category fallback only if the category is absent.

Do not change normalization, candidate matching, ranking, deduplication, limits,
`matchedLocale`, or identity.

### 6.3 Save outcome

Define:

```text
enum CatalogProductSaveOutcome {
    case inserted(Product)
    case alreadyPresent(Product)
}
```

The outcome is main-actor scoped because it carries a SwiftData model.

`alreadyPresent` means:

- exact same raw ProductID;
- no save performed;
- no existing fields changed;
- no photo replacement;
- no timestamp update.

### 6.4 Typed validation field

Define:

```text
enum CatalogProductSaveField {
    case productID
    case displayName
    case displayLocale
    case categoryID
    case categoryDisplayName
    case iconKey
}
```

### 6.5 Typed errors

Define `CatalogProductPersistenceError: LocalizedError` with:

```text
case invalidField(CatalogProductSaveField)
case unsupportedSource(ProductSource)
case lookupFailed(productID: String, underlying: Error)
case duplicateCatalogIdentity(
    productID: String,
    userProductIDs: [UUID]
)
case saveFailed(productID: String, underlying: Error)
```

Rules:

- validation errors occur before any fetch or mutation;
- lookup failure occurs before insertion;
- duplicate identity includes deterministically sorted user UUIDs;
- save failure preserves the underlying error for diagnostics;
- errors never include photo bytes or user notes.

### 6.6 CatalogProductPersistenceService

Define:

```text
@MainActor
struct CatalogProductPersistenceService
```

Dependencies:

```text
clock: () -> Date
saveContext: (ModelContext) throws -> Void
```

Production defaults:

```text
clock = Date.init
saveContext = { try $0.save() }
```

The save closure is the narrow injection seam for deterministic failure tests. It is
not a general repository abstraction.

Responsibilities:

- validate the request;
- fetch exact catalog-ID matches;
- enforce the one-record invariant;
- insert a new Product when absent;
- call one save;
- clean up an unsaved insertion after failure;
- return typed outcomes/errors.

Non-responsibilities:

- manual Product creation;
- Product Knowledge lookup or mutation;
- search validation;
- shopping-list insertion;
- legacy learned Product Knowledge;
- ProductHistory;
- editing an existing Product;
- catalog refresh;
- UI state or dismissal.

## 7. Save Algorithm

### 7.1 Validation

Validation preserves opaque IDs and localized display text:

```text
validate(request):
    require productID.rawValue is not empty
    require productID.rawValue == productID.rawValue.trimmed

    require displayNameSnapshot.trimmed is not empty

    require displayLocaleSnapshot is not empty
    require displayLocaleSnapshot == displayLocaleSnapshot.trimmed

    require categoryIDSnapshot.rawValue is not empty
    require categoryIDSnapshot.rawValue == categoryIDSnapshot.rawValue.trimmed

    require categoryDisplayNameSnapshot.trimmed is not empty

    require iconKeySnapshot is not empty
    require iconKeySnapshot == iconKeySnapshot.trimmed

    require source is one of:
        catalog
        barcode
        camera
        ai
```

Validation must not:

- lowercase or rewrite IDs;
- trim and persist a different display string;
- restrict ProductID to the 15 pilot IDs;
- require the current catalog repository to be available;
- accept `.manual` or `.discover`.

The request is trusted because it is created from a search result or future approved
typed resolver. Repository availability at confirmation time is not a durability
dependency.

### 7.2 Exact lookup

Use a SwiftData predicate:

```text
Product.catalogProductIDRawValue == request.productID.rawValue
```

Do not fetch by:

- `Product.id`;
- name;
- category;
- barcode;
- brand;
- source;
- snapshot text.

Fetch all exact matches because the service must distinguish one from multiple.

### 7.3 Full pseudocode

```text
save(request, modelContext):
    try validate(request)

    rawID = request.productID.rawValue

    do:
        matches = try fetch Products where catalogProductIDRawValue == rawID
    catch error:
        throw lookupFailed(productID: rawID, underlying: error)

    sort matches by Product.id.uuidString for deterministic diagnostics

    if matches.count > 1:
        throw duplicateCatalogIdentity(
            productID: rawID,
            userProductIDs: matches.map(id)
        )

    if matches.count == 1:
        return alreadyPresent(matches[0])

    now = clock()

    product = Product(
        name: request.displayNameSnapshot,
        imageData: request.imageData,
        category: request.categoryDisplayNameSnapshot,
        dateAdded: now,
        updatedAt: now,
        source: request.source,
        catalogProductIDRawValue: rawID,
        catalogDisplayNameSnapshot: request.displayNameSnapshot,
        catalogDisplayLocaleSnapshot: request.displayLocaleSnapshot,
        catalogCategoryIDSnapshotRawValue:
            request.categoryIDSnapshot.rawValue,
        catalogCategoryDisplayNameSnapshot:
            request.categoryDisplayNameSnapshot,
        catalogIconKeySnapshot: request.iconKeySnapshot,
        catalogSnapshotUpdatedAt: now
    )

    modelContext.insert(product)

    do:
        try saveContext(modelContext)
    catch error:
        modelContext.delete(product)
        throw saveFailed(productID: rawID, underlying: error)

    return inserted(product)
```

### 7.4 One-save boundary

For a zero-match insertion:

- there is exactly one call to the injected save function;
- the Product, its photo, effective values, catalog identity, snapshots, and
  timestamps commit together;
- no `ShoppingItem`, `ShoppingListEntry`, ProductHistory, or legacy
  `ProductKnowledge` write occurs.

For an existing exact match:

- there is no mutation;
- there is no save.

For validation, lookup, or multiple-match failure:

- there is no insertion;
- there is no save.

### 7.5 Failure cleanup

On save failure, call `modelContext.delete(product)` on the newly inserted unsaved
object. SwiftData discards a new unsaved model when it is deleted. Do not call
`modelContext.rollback()` because rollback would also discard unrelated pending
changes in the caller's context.

The service must not:

- retry automatically;
- create a manual fallback;
- learn legacy Product Knowledge;
- report success;
- leave the failed Product in `insertedModelsArray`.

Primary reference:
[ModelContext.delete](https://developer.apple.com/documentation/swiftdata/modelcontext/delete(_:)).

### 7.6 Retry behavior

The caller retains the request and explicitly retries.

A retry:

1. validates again;
2. performs a fresh exact lookup;
3. inserts only if still absent;
4. obtains a fresh injected time;
5. calls save once.

If another successful write appeared between attempts, retry returns
`alreadyPresent` without overwriting it.

### 7.7 Manual creation

`ShoppingListService.addManualProduct` is not changed and is not called by the catalog
service.

Its existing behavior remains:

```text
create Product with source manual and catalog defaults nil
insert
save once
return Product
```

Duplicate manual names remain allowed.

## 8. Recognition and Backfill Protection

### 8.1 Unresolved recognition filter

Modify `ShoppingListService.upsertRecognizedProduct`.

After fetching Products, derive:

```text
unlinkedProducts =
    products.filter { $0.catalogProductIDRawValue == nil }
```

Use `unlinkedProducts` for both:

- normalized barcode matching;
- `productMatches(_:candidate:)`.

If no unlinked match exists, create a new unlinked Product exactly as today.

This prevents unresolved recognition from refreshing any Product that has a nonnil
catalog reference, including a malformed partial link.

### 8.2 Defensive Product refresh

Both Product refresh methods return immediately for a nonnil catalog raw ID.

This is required even after caller filtering because:

- future callers may invoke the model method directly;
- `ShoppingListBackfillService` currently invokes legacy refresh;
- defense must survive later service refactoring.

### 8.3 Backfill protection

Modify `ShoppingListBackfillService.ensureDefaultListsAndBackfill`.

Current:

```text
product = product(for: item)
product.refresh(from: item)
repair entry
```

Required:

```text
product = product(for: item)
if product.catalogProductIDRawValue == nil:
    product.refresh(from: item)
repair entry regardless
```

The linked Product remains the source of truth. Backfill may still:

- associate its legacy ShoppingItem ID;
- repair `ShoppingListEntry.productID`;
- repair `ShoppingListEntry.product`;
- repair `legacyShoppingItemID`.

It may not replace linked Product effective fields or snapshots from a legacy
ShoppingItem.

`product(for:products:in:)` remains unchanged:

- exact `legacyShoppingItemID` match reuses a Product;
- otherwise a new unlinked Product is created from the legacy item;
- there is no name/barcode/catalog match.

### 8.4 Photo synchronization

No production logic change is required in:

- `ProductListView.replaceImage`;
- `ProductListView.cacheRemoteImage`;
- `ProductListView.syncCompatibilityItems`.

The first two assign only `imageData` and `updatedAt`; the third writes only
compatibility `ShoppingItem` fields. The new catalog fields are separate and therefore
remain unchanged.

Add regression tests that save a linked Product, mutate its photo and `updatedAt`,
save/reload it, and assert every catalog field is identical.

Do not refactor private ProductListView helpers merely to expose them to tests.

### 8.5 Shopping compatibility and legacy learning

In the new-entry branch of `ShoppingListService.addProductToShopping`, retain:

- compatibility ShoppingItem creation/reuse;
- `ShoppingListEntry.productID = Product.id`;
- Product relationship;
- ProductHistory recording.

Guard the legacy learned-knowledge call:

```text
if product.catalogProductIDRawValue == nil:
    recordProductKnowledgeIfPossible(...)
```

The already-existing-entry branch currently does not call legacy learning and needs no
new branch.

Do not add catalog parameters to `ProductKnowledgeService.learn`.

### 8.6 Resolved recognition boundary

WT-025C does not activate a Product Knowledge recognition resolver.

The future rule is:

```text
recognized candidate + explicit ProductID
    -> CatalogProductSaveRequest
    -> CatalogProductPersistenceService

recognized candidate without ProductID
    -> existing upsertRecognizedProduct
    -> unlinked Products only
```

The resolved request uses source `.camera`, `.ai`, or `.barcode`. It does not call the
legacy learned Product Knowledge service.

## 9. File-by-File Changes

### 9.1 New production files

#### `WayTask/Persistence/WayTaskSchemaV1.swift`

Change:

- define `WayTaskSchemaV1`;
- freeze exact V1 Product and ShoppingListEntry models;
- reuse the six unchanged model types;
- use version `1.0.0`.

Reason:

- reproduce the shipped store graph exactly;
- make a real V1 file-backed fixture possible.

Dependencies:

- current SwiftData models;
- SwiftData.

Tests:

- V1 schema parity;
- V1 file creation/reopen;
- V1→V2 migration.

#### `WayTask/Persistence/WayTaskSchema.swift`

Change:

- define `WayTaskSchemaV2`;
- define `WayTaskSchemaMigrationPlan`;
- define the lightweight V1→V2 stage;
- define the default/testable model-container factory.

Reason:

- centralize the exact schema and container contract;
- eliminate duplicated model lists.

Dependencies:

- `WayTaskSchemaV1`;
- current eight model types.

Tests:

- schema versions and model lists;
- migration plan presence;
- default and explicit-URL container construction.

#### `WayTask/Persistence/CatalogProductPersistenceService.swift`

Change:

- define request;
- define validation field;
- define outcome;
- define typed errors;
- define main-actor service;
- inject clock and save function;
- implement exact-ID save algorithm.

Reason:

- bridge Product Knowledge selection to user persistence without changing manual save.

Dependencies:

- `Product`;
- `ProductID`;
- `ProductCategoryID`;
- `ProductSearchResult`;
- `ProductSource`;
- SwiftData.

Tests:

- all catalog save, duplicate, failure, retry, and validation cases.

### 9.2 Modified production files

#### `WayTask/Models.swift`

Exact changes:

- add seven nullable Product fields;
- append seven nil-defaulted initializer parameters;
- assign those parameters;
- add typed catalog-ID and linked-state read helpers;
- add linked-product guards to both refresh methods.

Reason:

- persist catalog identity and display snapshots;
- protect catalog-linked Product from legacy writers.

Dependencies:

- `ProductID`.

Tests:

- field defaults;
- initializer behavior;
- refresh isolation;
- migration preservation.

#### `ProductSource.swift`

Exact changes:

- add `.catalog`;
- add `"Catalog"` display mapping.

Reason:

- distinguish autocomplete catalog acquisition from manual and Discover.

Dependencies:

- none.

Tests:

- raw-value round trip;
- display name;
- existing source round trips.

#### `ProductKnowledgeService.swift`

Exact change:

- map `.catalog` to `.unknown` in `candidateSource(for:)`.

Reason:

- keep the exhaustive switch compiling;
- define defensive legacy bridge behavior.

Dependencies:

- new ProductSource case.

Tests:

- catalog shopping path proves the legacy service is not invoked;
- source round-trip/bridge characterization.

#### `ShoppingListService.swift`

Exact changes:

- filter catalog-linked Products out of both recognition match passes;
- skip legacy ProductKnowledge learning for a linked Product added to shopping;
- skip legacy Product refresh in recurring backfill;
- retain relationship repair and compatibility ShoppingItem behavior.

Reason:

- prevent catalog overwrite and duplicate learned identity.

Dependencies:

- Product linked-state helper.

Tests:

- recognition isolation;
- backfill preservation;
- shopping compatibility;
- no learned ProductKnowledge for catalog products;
- existing manual/recognized behavior.

#### `WayTask/ProductKnowledge/Domain/ProductSearchResult.swift`

Exact changes:

- add `categoryDisplayName`;
- add `displayLocale`.

Reason:

- make the selected snapshot complete and prevent misuse of `matchedLocale`.

Dependencies:

- none beyond current domain values.

Tests:

- result metadata assertions across locale and alias cases.

#### `WayTask/ProductKnowledge/Application/ProductKnowledgeSearch.swift`

Exact changes:

- capture the chosen display ProductName locale;
- resolve localized category display text;
- pass both values into ProductSearchResult;
- leave ranking and matching unchanged.

Reason:

- supply trustworthy persistence snapshots and WT-024A presentation metadata.

Dependencies:

- ProductSearchResult additions;
- indexed ProductCategory names.

Tests:

- English/Hebrew/fallback category display;
- display locale differs correctly from matched alias locale;
- complete existing ranking suite remains unchanged.

#### `WayTask/WayTaskApp.swift`

Exact changes:

- construct the container once through the new factory;
- inject it with `.modelContainer(container)`;
- report/fail closed on construction failure;
- remove the inline eight-type model list.

Reason:

- activate the schema migration plan without changing the store configuration.

Dependencies:

- `WayTaskSchemaV2`;
- migration plan;
- container factory.

Tests:

- container factory tests;
- build and launch smoke validation.

### 9.3 Modified test files

#### `WayTaskTests/ProductKnowledge/LegacyProductCreationCharacterizationTests.swift`

Exact changes:

- assert all seven catalog fields are nil for manual creation;
- retain duplicate manual-name, whitespace, and shopping-flow assertions;
- replace the obsolete “no Product catalog field” assertion with:
  - Product contains the exact seven catalog properties;
  - ShoppingItem and ShoppingListEntry still contain no catalog reference;
  - ShoppingListEntry.productID remains UUID-based.

Reason:

- preserve the manual baseline while acknowledging approved V2 fields.

#### `WayTaskTests/ProductKnowledge/ProductKnowledgeSearchTests.swift`

Exact changes:

- assert `categoryDisplayName`;
- assert `displayLocale`;
- prove `displayLocale` is not derived from `matchedLocale`;
- retain all ranking/order assertions.

Reason:

- close the request-construction metadata gap.

### 9.4 New test files

#### `WayTaskTests/Persistence/WayTaskSchemaMigrationTests.swift`

Coverage:

- V1 structural manifest;
- entity-name parity;
- true file-backed V1 creation;
- V1→V2 migration;
- full graph/data preservation;
- new-field nil defaults;
- no inferred matching;
- V2 reopen.

#### `WayTaskTests/Persistence/CatalogProductPersistenceServiceTests.swift`

Coverage:

- validation;
- insertion;
- exact snapshot values;
- injected clock;
- exact-ID deduplication;
- same-name/different-ID behavior;
- manual same-name coexistence;
- multiple-record invariant;
- injected save failure and retry;
- no related legacy rows.

#### `WayTaskTests/Persistence/CatalogProductCompatibilityTests.swift`

Coverage:

- recognition excludes linked Product;
- recognition still matches unlinked Product;
- both Product refresh guards;
- backfill preserves linked Product;
- backfill remains idempotent;
- shopping entry uses user UUID;
- compatibility ShoppingItem creation;
- no legacy learned ProductKnowledge for linked Product;
- photo changes preserve catalog metadata;
- new catalog snapshots remain unchanged when repository fixtures change.

### 9.5 Files explicitly unchanged

- `ProductListView.swift`
- `CameraView.swift`
- `CameraViewModel.swift`
- `ProductKnowledge.swift`
- `ProductHistory.swift`
- `ShoppingMemoryService.swift`
- Product Knowledge JSON resources
- asset and string catalogs
- `WayTask.xcodeproj/project.pbxproj`
- shared scheme

No UI calls the new catalog save service in WT-025C.

## 10. Testing Matrix

| Area | Required case | Store | Special dependency | Expected result |
| --- | --- | --- | --- | --- |
| Product defaults | Main initializer omits catalog args | In-memory | None | Seven fields nil |
| Manual compatibility | `addManualProduct` | In-memory | Existing service | Shape and behavior unchanged |
| Manual duplicates | Same name twice | In-memory | Existing service | Two UUIDs, both unlinked |
| V1 parity | Frozen V1 graph/property manifest | In-memory schema inspection | Deterministic expected manifest | Exact shipped graph |
| V1 fixture | Create/save/reopen V1 | File-backed | Unique temp URL | All eight entities readable |
| V1→V2 | Open V1 URL with V2 plan | File-backed | Frozen clock/data fixture | Migration succeeds |
| Data preservation | UUIDs, relationships, photos, timestamps, raw sources | File-backed | Fixed bytes/dates/UUIDs | Exact equality |
| No inferred matching | Existing “Milk” and catalog-like strings | File-backed | Deterministic names/barcodes | Catalog fields remain nil |
| Catalog insert | Valid request, zero matches | In-memory | Injected clock | One complete Product |
| Save boundary | Successful insert | In-memory | Save spy closure | Exactly one save call |
| Same ProductID | Save request twice | In-memory | Same fixture | Second returns existing, zero save |
| Same name, different IDs | Two requests | In-memory | Deterministic fixtures | Two Products |
| Manual same name | Manual then catalog request | In-memory | Existing service | Both remain separate |
| Multiple-match invariant | Preinsert two linked rows | In-memory | Deterministic UUIDs | Typed invariant error, no save |
| Validation | Empty/surrounded fields and bad source | In-memory | Table-driven fixtures | Typed field/source errors |
| Save failure | Saver throws before commit | In-memory | Injected failure | Insert discarded, typed error |
| Retry | Failure then successful saver | In-memory | Stateful save closure | One committed Product |
| Backfill | Linked Product plus stale legacy item | In-memory | Fixed fields | Product unchanged; links repaired |
| Backfill idempotence | Run twice | In-memory | Same fixture | Counts and catalog data stable |
| Recognition isolation | Candidate matches linked barcode/name | In-memory | Deterministic candidate | Linked Product unchanged |
| Recognition legacy | Candidate matches unlinked product | In-memory | Deterministic candidate | Current behavior retained |
| Shopping compatibility | Add linked Product to list | In-memory | Existing service | Entry points to Product UUID |
| Legacy learning isolation | Add linked Product to shopping | In-memory | Existing service | No legacy ProductKnowledge row |
| ProductHistory | Add linked Product to shopping | In-memory | Existing service | Existing memory behavior retained |
| Photo preservation | Replace/cache photo and reload | In-memory | Fixed catalog fixture | Catalog fields unchanged |
| Catalog revision stability | Repository A then B | In-memory | Two deterministic repository fixtures | Saved Product not mutated |
| Search category locale | en/he/unsupported locale | No SwiftData | Search fixture | Approved localized label |
| Search display locale | Alias match differs from display locale | No SwiftData | Search fixture | Both locales remain distinct |
| Feature disabled | Construct V2 app container without UI save calls | File-backed/smoke | No autocomplete injection | Existing flows work |

### 10.1 In-memory tests

Use in-memory stores for:

- field defaults;
- catalog service behavior;
- validation;
- duplicate cases;
- recognition;
- backfill;
- shopping compatibility;
- legacy learned-knowledge isolation;
- photo preservation.

Each schema helper uses the production V2 schema, not a Product-only schema.

### 10.2 File-backed tests

Use explicit temporary URLs for:

- V1 store creation;
- V1 container release;
- V2 migration;
- V2 reopen after migration;
- preservation across container lifetimes.

The test must not keep V1 model instances or context references alive when opening V2.
Clean the uniquely scoped temporary directory in teardown.

### 10.3 Injected clock

The catalog service receives a fixed `Date` and tests assert:

```text
dateAdded == fixedDate
updatedAt == fixedDate
catalogSnapshotUpdatedAt == fixedDate
```

Existing manual/recognition code continues using `Date()` and does not need a clock
refactor.

### 10.4 Injected save failure

Inject a save closure that:

- counts calls;
- throws a deterministic sentinel error before calling `ModelContext.save`.

After failure assert:

- typed `.saveFailed`;
- zero fetched catalog Products;
- no pending inserted Product;
- request can be retried in the same context.

Then switch the closure to a real save and assert exactly one Product commits.

### 10.5 Deterministic fixtures

Use fixed:

- user UUIDs;
- ProductIDs;
- ProductCategoryIDs;
- English and Hebrew display values;
- icon keys;
- image bytes;
- dates;
- source raw values;
- shopping-list and legacy-item IDs.

The migration fixture must include at least:

- GeoLocation with a related ShoppingItem;
- manual Product with photo;
- AI- or barcode-source Product;
- ShoppingList;
- ShoppingListEntry related to Product;
- ProductHistory;
- legacy ProductKnowledge;
- active ShoppingSession;
- catalog-looking names and IDs that must remain unlinked.

### 10.6 Migration assertions

After V2 opens the V1 fixture, assert:

- entity counts unchanged except no automatically created rows;
- every fixed UUID unchanged;
- `ShoppingListEntry.productID` unchanged;
- Entry relationship resolves to the same user Product UUID;
- GeoLocation relationship resolves to the same ShoppingItem;
- every image byte sequence unchanged;
- names, brands, categories, barcodes, URLs, details, keywords unchanged;
- `dateAdded`, `updatedAt`, list dates, history dates, and session dates unchanged;
- all source raw values unchanged;
- all seven new Product fields nil;
- no Product is catalog-linked;
- reopening the same V2 store succeeds without another data change.

## 11. Validation Sequence

The implementation must execute in this order.

### 1. Baseline status audit

- Record the current worktree state with read-only status/diff inspection.
- Record unrelated modified and untracked paths.
- Do not stage, restore, delete, or rewrite unrelated changes.
- Run the current focused Product Knowledge/manual tests.
- Run the current full unit suite.
- Run the current Debug build.

Stop if the baseline does not build/test for a reason relevant to WT-025C.

### 2. Add schema versioning

- Add the frozen V1 schema definitions first.
- Add a V1 schema-manifest/parity test while Product still has its shipped shape.
- Verify entity names, properties, relationships, delete rules, and version.
- Do not define an identical V2 stage yet; duplicate schema checksums are not a valid
  migration chain.

### 3. Validate migration fixture

- Create the runtime-generated V1 file-backed store.
- Save and reopen it using V1 with no migration plan.
- Verify the complete fixture.
- Confirm the temporary explicit URL is used.
- Confirm no in-memory configuration is used.

This step validates the V1 fixture and frozen schema. The actual V1→V2 transition is
executed immediately after V2 exists in Step 4.

### 4. Add Product fields

- Add exactly seven nullable fields.
- Keep notes deferred.
- Define V2 and the lightweight migration stage.
- Open the Step 3 V1 fixture with V2 and run every migration assertion.
- Change app container construction only after the migration test passes.

Stop on any checksum, entity-name, relationship, or preservation mismatch.

### 5. Add catalog save service

- Add ProductSearchResult snapshot metadata.
- Add request, outcome, errors, service, injected clock, and save seam.
- Implement validation and exact-ID algorithm.
- Add focused service tests before any UI caller exists.

### 6. Harden recognition/backfill paths

- Filter linked Products from unresolved recognition.
- Add defensive refresh guards.
- Skip linked Product refresh during backfill.
- Skip legacy learned ProductKnowledge on linked shopping insertion.
- Add compatibility tests.

### 7. Run focused tests

Run:

- schema parity/migration tests;
- Product field/default tests;
- catalog save tests;
- manual characterization tests;
- recognition/backfill/shopping compatibility tests;
- Product Knowledge search tests.

### 8. Run full suite

Run the complete shared-scheme unit-test suite with no skipped persistence tests.

### 9. Run build

Run a clean Debug build for a generic iOS destination with code signing disabled, then
the project's normal supported simulator/device build as available.

### 10. Review diff

Verify:

- only listed production/test files changed;
- no resources changed;
- no project/scheme configuration changed;
- no unrelated formatting or cleanup;
- no generated stores or temporary files entered the workspace.

### 11. Confirm no UI activation

Search production call sites and confirm:

- `CatalogProductPersistenceService.save` has no UI caller;
- `ProductListView.addItem` still calls only `addManualProduct`;
- no catalog selection is enabled;
- no feature flag enables autocomplete.

### 12. Confirm no unrelated worktree changes

Compare final read-only status/diff output with the baseline record. Preserve all
preexisting user changes and fail review if WT-025C touched a path outside the approved
file list.

## 12. Rollout and Rollback Gates

### 12.1 Migration safety

PASS when:

- frozen V1 matches the shipped graph;
- a true V1 file-backed store opens under V2;
- migration uses the explicit plan and lightweight stage;
- V2 reopens successfully.

FAIL when:

- V1 is approximate;
- only an in-memory V2 store was tested;
- migration needs store deletion/recreation;
- a checksum/entity mismatch is ignored.

### 12.2 No data loss

PASS when all V1 values, UUIDs, relationships, photos, timestamps, and raw sources
survive exactly and all new fields are nil.

FAIL on any rewritten, missing, duplicated, or relinked user record.

### 12.3 Manual-flow compatibility

PASS when:

- existing manual tests remain green;
- duplicate manual names remain allowed;
- all catalog fields default nil;
- `addManualProduct` implementation is unchanged.

FAIL if manual creation invokes catalog search, catalog deduplication, or the catalog
save service.

### 12.4 Catalog-write correctness

PASS when:

- zero match inserts one complete Product with one save;
- one match returns existing without mutation/save;
- multiple matches fail deterministically;
- failure cleanup and retry pass;
- no legacy rows are created by library save.

FAIL if any catalog selection loses ProductID or saves as manual.

### 12.5 Recognition isolation

PASS when unresolved recognition cannot refresh linked Products and retains current
behavior for unlinked Products.

FAIL if barcode/name/brand/category similarity can mutate a linked Product.

### 12.6 Backfill and compatibility

PASS when:

- linked Products remain unchanged across repeated backfill;
- relationships are still repaired;
- shopping entries still use user Product UUIDs;
- compatibility ShoppingItems still work;
- linked shopping activity does not create legacy ProductKnowledge.

FAIL if catalog fields/effective values are cleared or legacy learned identity is
created.

### 12.7 Feature-disabled V2 compatibility

PASS when:

- app launches on V2 with autocomplete disconnected;
- existing Products and shopping data render through current fields;
- manual and recognition flows still work;
- no production caller writes catalog data.

FAIL if schema deployment implicitly activates autocomplete or changes visible product
behavior.

### 12.8 Old-binary rollback prohibition

PASS when release and rollback documentation explicitly states:

- do not install an old V1-schema binary over a store written by V2;
- rollback uses a V2-schema-compatible build;
- that build may disable autocomplete/catalog writes but must retain all V2 fields and
  `.catalog` decoding.

FAIL if the rollout depends on an old binary opening the V2 store.

### 12.9 Autocomplete gate

Autocomplete remains disabled until every gate in Sections 12.1–12.8 passes.

Failure of any persistence gate blocks autocomplete activation.

## 13. Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Frozen V1 nested type produces a different entity identity | Shipped stores cannot migrate | Entity-name/parity gate before V2; true file-backed migration test |
| V1 omits an unchanged model/property/relationship | Checksum mismatch or data loss | Exact eight-model manifest and shared unchanged types |
| Default production store URL changes | App appears to lose all data | Use empty configuration list/default configuration; no named/new URL |
| V1 and V2 are temporarily identical | Duplicate checksum migration failure | Freeze/test V1 first; define V2 only with field addition |
| Optional additions are assumed lightweight without proof | Runtime migration failure | File-backed V1→V2 test is a hard gate |
| Notes expands migration scope | Unrelated behavior and test burden | Defer notes |
| `matchedLocale` is persisted as display locale | Incorrect snapshot provenance | Add explicit `displayLocale` from chosen ProductName |
| Category label unavailable at save | Incomplete snapshot | Add localized `categoryDisplayName` to search result |
| ID validation normalizes opaque IDs | Identity corruption | Validate shape without rewriting |
| Same ProductID inserts twice | Ambiguous catalog ownership | Main-actor service and exact preflight query |
| Multiple corrupt matches are silently resolved | Hidden data loss | Typed invariant failure with sorted UUIDs |
| Save failure leaves pending Product | Retry duplicates or phantom UI state | Delete unsaved insertion; injected failure/retry test |
| `rollback()` discards unrelated changes | User-data loss | Never call context-wide rollback in service |
| Main context autosave races explicit save | More than one boundary | Keep operation synchronous on MainActor and call one explicit save |
| Legacy backfill overwrites linked effective values | Catalog/user snapshot drift | Caller guard plus defensive Product refresh guard |
| Recognition matches linked barcode/name | Catalog Product mutation | Filter both match passes to raw-ID-nil Products |
| Shopping activity learns catalog product by name | Parallel identity | Skip legacy ProductKnowledge write for linked Product |
| `.catalog` omitted from a switch | Compile failure or wrong bridge | Exact two-switch audit and source tests |
| `.catalog` is treated as identity | AI/barcode-linked products misclassified | Catalog raw ID remains sole identity test |
| Photo update clears snapshots | Metadata loss | Separate fields and reload regression test |
| Old binary is used for rollback | Store open failure | V2-compatible feature-disabled rollback only |
| Migration failure falls back to empty/in-memory store | Apparent total data loss | Fail closed and preserve original store |
| Test fixture remains in workspace | Repository pollution | Unique temp directory and teardown cleanup |
| Broad persistence repository refactor | Scope/risk expansion | Inject only clock and save closure |

## 14. Acceptance Checklist

### Schema

- [ ] V1 version is exactly `1.0.0`.
- [ ] V1 model graph contains the exact eight shipped entities.
- [ ] Frozen V1 Product contains exactly the shipped properties.
- [ ] Frozen V1 ShoppingListEntry preserves the Product relationship and nullify rule.
- [ ] V1 entity names match the shipped schema.
- [ ] V2 version is exactly `2.0.0`.
- [ ] V2 differs only by seven nullable Product attributes.
- [ ] V1→V2 uses one lightweight stage.
- [ ] Production uses the default store configuration.
- [ ] Migration failure never deletes or replaces the store.

### Product

- [ ] Seven catalog fields exist with `nil` defaults.
- [ ] Notes is absent.
- [ ] Manual, legacy, and unresolved candidate initializers remain unlinked.
- [ ] Catalog service supplies the complete linked snapshot.
- [ ] Nonnil raw catalog identity protects Product from refresh.
- [ ] Existing UUID and ShoppingListEntry ID semantics are unchanged.

### Source

- [ ] `.catalog` raw value and display name exist.
- [ ] Both exhaustive ProductSource switches are updated.
- [ ] Legacy bridge maps catalog to unknown defensively.
- [ ] Existing source raw values round-trip unchanged.

### Save service

- [ ] Request is built from explicit search result metadata.
- [ ] `matchedLocale` is never used as display locale.
- [ ] Validation performs no ID normalization.
- [ ] Exact ProductID lookup is the only catalog duplicate test.
- [ ] Zero match inserts and saves once.
- [ ] One match returns without mutation/save.
- [ ] Multiple matches return typed invariant error.
- [ ] Save failure discards the unsaved Product.
- [ ] Retry succeeds cleanly.
- [ ] Manual creation is unchanged.

### Protection

- [ ] Recognition considers only unlinked Products.
- [ ] Both Product refresh methods guard linked records.
- [ ] Backfill skips linked Product refresh and still repairs relationships.
- [ ] Photo updates preserve all catalog fields.
- [ ] Catalog shopping uses Product UUID.
- [ ] Catalog shopping does not learn legacy ProductKnowledge.

### Tests and validation

- [ ] V1 fixture is file-backed.
- [ ] V1 context is released before V2 opens the URL.
- [ ] Full graph and every required data class are represented.
- [ ] UUIDs, relationships, photos, timestamps, and sources are exact after migration.
- [ ] No inferred matching occurs.
- [ ] All focused tests pass.
- [ ] Full suite passes.
- [ ] Debug build passes.
- [ ] Diff contains only approved files.
- [ ] Xcode project and scheme are unchanged.
- [ ] Resources are unchanged.
- [ ] No UI calls the catalog service.
- [ ] Autocomplete remains disabled.
- [ ] Rollback documentation prohibits old V1 binary use.

## 15. Final Decision

The implementation is ready to proceed as WT-025C with no open architecture blocker.

The hard implementation gate is the file-backed V1 parity and migration test. If the
frozen V1 entity identity, lightweight stage, or preservation assertions fail, work
must stop without altering, deleting, or recreating the store. That gate validates the
approved architecture; it is not permission to substitute a broader migration.

WT-025C should implement only the exact schema, fields, save service, guards, and tests
listed here. Notes, UI activation, catalog refresh, explicit linking, redirects,
merges, and broader repository refactors remain deferred.

APPROVED FOR WT-025C IMPLEMENTATION
