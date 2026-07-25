# WT-025A — Catalog-Aware Persistence Architecture

## 1. Executive Summary

WayTask should make its existing SwiftData `Product` model catalog-aware rather than
creating a second persisted catalog-product model.

The persisted `Product` remains a user-owned library record. Its existing UUID remains
the identity used by `ShoppingListEntry`, and its existing `name`, `category`,
`imageData`, and other fields remain the values consumed by current UI and
compatibility paths. A catalog-originated product adds one optional reference to the
Product Knowledge identity plus enough snapshots to remain useful if the catalog later
changes or is unavailable.

The minimum durable addition is:

- an optional Product Knowledge `ProductID`;
- the localized display name, category, and semantic icon key shown when the user
  selected the result;
- the locale of the displayed text;
- the time at which the catalog snapshot was captured;
- optional user notes.

All existing products migrate with those catalog fields set to `nil`. They remain
manual or recognition-originated products exactly as they are today. Migration must
not guess catalog matches from names, barcodes, brands, categories, or images.

Catalog selection and manual creation need separate persistence entry points:

- manual confirmation continues to call the existing, characterized
  `ShoppingListService.addManualProduct` flow;
- catalog confirmation calls a new, narrowly scoped catalog save use case that
  persists the selected `ProductID` and snapshots and deduplicates only by that stable
  `ProductID`.

Both paths converge on the same persisted `Product`, so current shopping-list,
photo-sync, history, and compatibility behavior can remain in place. The read-only
`ProductKnowledgeRepository` does not become a user-data repository, and
`ProductEntity` is not copied into SwiftData.

The architecture is intentionally snapshot-stable. Catalog updates do not silently
rename, recategorize, remove, or visually change products already saved by a user.
Current catalog facts may be compared with saved snapshots, but applying an update is
a separate, explicit future operation.

### Required invariants

1. `Product.id` remains the user-library UUID.
2. `ShoppingListEntry.productID` continues to refer to `Product.id`, not a Product
   Knowledge `ProductID`.
3. `catalogProductIDRawValue == nil` means the product is not linked to the catalog.
4. A catalog link is created only from an explicit catalog selection or a future
   resolver that returns an explicit stable `ProductID`.
5. Names, aliases, barcodes, brands, and categories never create a catalog link by
   inference during migration.
6. At most one user-library `Product` may be linked to a given catalog `ProductID`.
7. Saved catalog snapshots remain sufficient to display and use the product without a
   current catalog record.
8. The current manual-product save path and its failure behavior remain unchanged.
9. Catalog save success is reported only after the SwiftData save succeeds.
10. A catalog-aware schema must never require deletion or recreation of an existing
    user store.

## 2. Current Persistence Audit

### 2.1 Files inspected

The production source was treated as authoritative. The audit covered:

#### Persistence models and composition

- `WayTask/Models.swift`
- `ProductKnowledge.swift`
- `ProductHistory.swift`
- `ShoppingSession.swift`
- `WayTask/WayTaskApp.swift`
- `WayTask/ContentView.swift`

#### Save and compatibility paths

- `ShoppingListService.swift`
- `ProductListView.swift`
- `CameraView.swift`
- `CameraViewModel.swift`
- `ShoppingMemoryService.swift`
- `ProductKnowledgeService.swift`
- `ProductCandidate.swift`
- `ProductSource.swift`
- `RecognitionResult.swift`

#### Product Knowledge production code

- `WayTask/ProductKnowledge/Domain/ProductEntity.swift`
- `WayTask/ProductKnowledge/Domain/ProductName.swift`
- `WayTask/ProductKnowledge/Domain/ProductCategory.swift`
- `WayTask/ProductKnowledge/Domain/ProductSearchResult.swift`
- `WayTask/ProductKnowledge/Application/ProductKnowledgeRepository.swift`
- `WayTask/ProductKnowledge/Application/ProductKnowledgeSearch.swift`
- `WayTask/ProductKnowledge/Application/ProductKnowledgeError.swift`
- `WayTask/ProductKnowledge/Data/InMemoryProductKnowledgeRepository.swift`
- `WayTask/ProductKnowledge/Data/BundledProductKnowledgeLoader.swift`
- `WayTask/ProductKnowledge/Data/ProductKnowledgeCatalog.swift`
- `WayTask/ProductKnowledge/Data/ProductKnowledgeCatalogValidator.swift`

#### Current tests

- `WayTaskTests/ProductKnowledge/LegacyProductCreationCharacterizationTests.swift`
- `WayTaskTests/ProductKnowledge/ProductEntityTests.swift`
- `WayTaskTests/ProductKnowledge/InMemoryProductKnowledgeRepositoryTests.swift`
- `WayTaskTests/ProductKnowledge/ProductKnowledgeSearchTests.swift`
- `WayTaskTests/ProductKnowledge/ProductKnowledgeSearchPerformanceTests.swift`
- `WayTaskTests/ProductKnowledge/BundledProductKnowledgeLoaderTests.swift`
- `WayTaskTests/ProductKnowledge/ProductKnowledgeCatalogValidatorTests.swift`
- `WayTaskTests/ProductKnowledge/ProductKnowledgeResourceConformanceTests.swift`

#### Architecture, product, specification, and implementation inputs

- `docs/Architecture/ProductKnowledgeArchitecture.md`
- `docs/Architecture/ProductEntityDataModel.md`
- `docs/Architecture/ProductKnowledgeMigrationStrategy.md`
- `docs/Specifications/ProductSearchUXContract.md`
- `docs/Specifications/SmartProductCreation.md`
- `docs/Product/SmartProductKnowledge.md`
- `docs/Product/ProductTaxonomy.md`
- `docs/Product/PilotProductCatalog.md`
- `docs/Implementation/WT-023A_ProductSearchFoundation_Plan.md`
- `docs/Implementation/WT-024A_ProductAutocompleteUIIntegration_Plan.md`

`docs/Specifications/ProductSearchUXContract.md` is the WT-023B UX contract used by
this audit. No separate WT-023B implementation-plan file was present.
`docs/Implementation/WT-011A_ManualProductCreationReliability_Plan.md` was also not
present, so current production behavior and the manual-creation characterization tests
were used for that reliability baseline.

### 2.2 Current user-product model

`Product` is the current canonical user-library model. It stores:

- `id: UUID`;
- `legacyShoppingItemID: UUID?`;
- `name`;
- `imageData`;
- optional `brand`, `category`, `barcode`, and remote image URL;
- `dateAdded` and `updatedAt`;
- `sourceRawValue`;
- optional product type, flavor, package size, package type, visible text, and search
  keywords.

`Product` currently has no Product Knowledge `ProductID`, no catalog display snapshot,
and no catalog-specific provenance. The current tests explicitly characterize that
absence.

`ShoppingListEntry.productID` stores the UUID of a user-library `Product`. Its
relationship to `Product` is the durable route from a list entry to product details.
This field must not be repurposed for a Product Knowledge string identifier.

`ShoppingItem` remains a legacy, denormalized compatibility record. It can be created
from a `Product` and refreshed from current product values, but it has no catalog
identity. It should stay a compatibility snapshot, not become another catalog link.

### 2.3 Current Product Knowledge persistence

There are two distinct concepts that must not be merged:

1. The new Product Knowledge catalog is exposed as immutable domain entities through
   `ProductKnowledgeRepository` and searched by `ProductKnowledgeSearch`.
   `ProductEntity.id` is the stable, opaque `ProductID`.
2. The older SwiftData `ProductKnowledge` model is a learned recognition cache keyed
   primarily by barcode or normalized name. `ProductKnowledgeService` updates it after
   recognition and shopping activity.

The legacy `ProductKnowledge` SwiftData model is not a safe place to store the catalog
link:

- its key is not the Product Knowledge `ProductID`;
- its lifecycle and confidence semantics belong to recognition learning;
- it is mutable user/device memory;
- catalog entities are read-only reference data.

The names are similar, but their ownership and identity contracts are different.

### 2.4 Current manual save flow

The Add Product UI trims the entered name, calls
`ShoppingListService.addManualProduct`, and dismisses only after the service succeeds.
The service:

1. creates one `Product`;
2. sets its source to manual;
3. inserts it into the model context;
4. calls `save()` once.

It does not create a `ShoppingItem`, `ShoppingListEntry`, or legacy
`ProductKnowledge` row. Duplicate manual names intentionally create independent
products. On save failure, the UI reports the failure and preserves the form.

This is the reliability baseline. Catalog persistence must be additive and must not
insert catalog branching into this method.

### 2.5 Current recognized-product save flow

Camera and recognition paths build a `ProductCandidate` and call
`ShoppingListService.upsertRecognizedProduct`.

The current upsert searches user products by:

1. exact normalized barcode;
2. exact normalized name plus matching brand or category.

It refreshes a match or inserts a new `Product`, then updates the legacy learned
`ProductKnowledge` cache.

Once catalog-linked products exist, this heuristic must not be allowed to mutate one
unless recognition has explicitly resolved the candidate to that same catalog
`ProductID`. Name or barcode similarity alone is not a catalog-identity proof.

### 2.6 Current shopping persistence

Adding a library product to shopping uses the user `Product.id` to create or reuse a
`ShoppingListEntry`. The flow also creates or reopens a legacy `ShoppingItem` for
compatibility and records shopping memory.

Catalog awareness does not require a catalog ID on `ShoppingListEntry`. The entry
already reaches catalog identity through its related `Product`.

For compatibility, a catalog-linked `Product` may continue to create a legacy
`ShoppingItem` snapshot. The catalog product must not also be learned into the legacy
`ProductKnowledge` cache merely because it entered a shopping list; that would create
a second, name/barcode-based identity for a known catalog entity.

### 2.7 Current migration behavior

The app constructs a SwiftData container from its model types directly. The inspected
source has no explicit `VersionedSchema` or `SchemaMigrationPlan`.

`ShoppingListBackfillService` is an idempotent runtime compatibility backfill, not a
schema migration. It:

- creates default shopping lists;
- converts legacy `ShoppingItem` rows into `Product` rows where needed;
- repairs `ShoppingListEntry` links;
- refreshes compatibility values;
- saves the reconciled graph.

That backfill is important and must remain supported, but it cannot be the only
migration mechanism once new persistent fields are introduced.

### 2.8 Current gaps

The current store cannot distinguish:

- a manual product named “Milk”;
- a product recognized as “Milk”;
- an explicitly selected catalog product whose current display name is “Milk.”

It also cannot preserve the stable catalog identity through a rename, distinguish two
catalog entities with the same localized name, or detect a previously saved catalog
product without name matching.

`ProductSearchResult` already carries `productID`, `displayName`, `categoryID`, and
`iconKey`, but it does not carry localized category display text or the locale of the
chosen `displayName` record. Its current `matchedLocale` describes the name or alias
that matched the query. That can differ from the locale of `displayName`, so
`matchedLocale` must not be persisted as the display-snapshot locale.

The missing boundary is not a second catalog database. It is a small amount of
catalog-link metadata on the existing user-owned `Product`.

## 3. Proposed Data Model

### 3.1 Identity model

Two identities must remain explicit:

| Identity | Type | Owner | Purpose |
| --- | --- | --- | --- |
| User product ID | Existing `Product.id: UUID` | User library | Relationships, shopping entries, edits, photos, and local lifecycle |
| Catalog product ID | New optional Product Knowledge `ProductID` raw value | Product Knowledge catalog | Stable reference to a catalog concept across labels and catalog revisions |

The Product Knowledge ID is an opaque identifier. It must not be generated from a
display name, barcode, category, brand, or localized text.

### 3.2 Recommended additive fields on `Product`

| Field | Required for | Ownership | Meaning |
| --- | --- | --- | --- |
| `catalogProductIDRawValue: String?` | Catalog products | Reference | Stable Product Knowledge `ProductID`; the only live catalog reference |
| `catalogDisplayNameSnapshot: String?` | Catalog products | Snapshot | Localized name explicitly shown at selection time |
| `catalogDisplayLocaleSnapshot: String?` | Catalog products | Snapshot | BCP-47-compatible locale identifier used for the displayed snapshot |
| `catalogCategoryIDSnapshotRawValue: String?` | Catalog products | Snapshot | Category ID associated with the selected result |
| `catalogCategoryDisplayNameSnapshot: String?` | Catalog products | Snapshot | Localized category text shown or resolved at selection time |
| `catalogIconKeySnapshot: String?` | Catalog products | Snapshot | Semantic Product Knowledge icon key selected at save time |
| `catalogSnapshotUpdatedAt: Date?` | Catalog products | Snapshot metadata | Time the catalog snapshot was first captured or explicitly refreshed |
| `notes: String?` | All products | User data | Optional user-authored notes; initially `nil` for migrated records |

All fields are optional at the schema level so the migration is additive and existing
records remain valid.

The implementation may expose a computed typed `catalogProductID: ProductID?`, but
SwiftData persists the raw string. Invalid or empty raw values are treated as corrupt
links, not as names to be rematched.

### 3.3 Existing-field semantics

The current fields retain their storage role:

| Existing field | Recommended semantics |
| --- | --- |
| `id` | Permanent user-library UUID |
| `name` | Effective display name used by current UI and compatibility models |
| `category` | Effective category display value used by current UI |
| `imageData` | User-owned local photo; never refreshed from catalog metadata automatically |
| `brand` | User- or provider-supplied value; not a copied list of catalog aliases |
| `barcode` | User- or provider-supplied identifier; not the catalog identity |
| product detail fields | User- or recognition-provider snapshots |
| `dateAdded` | Original creation time of the user-library record |
| `updatedAt` | Last durable user-product mutation |
| `sourceRawValue` | Acquisition channel, not identity |

For a new catalog product, `name` and `category` are initialized from their catalog
snapshots. They remain the effective, backward-compatible values that all existing
screens already read.

The effective value also represents a future user override:

- `name == catalogDisplayNameSnapshot` means no divergent name override is visible;
- `name != catalogDisplayNameSnapshot` means the effective user value must be
  preserved during any explicit catalog refresh;
- the same rule applies to `category` and
  `catalogCategoryDisplayNameSnapshot`.

This avoids adding parallel override fields and avoids rewriting existing consumers.
The comparison for refresh protection uses the exact stored old snapshot, not
normalized search text.

### 3.4 Reference versus snapshot

Only `catalogProductIDRawValue` is a live reference.

These values are snapshots:

- catalog display name;
- display locale;
- category ID;
- category display name;
- semantic icon key;
- snapshot timestamp.

Snapshots are written from the explicitly selected search result. They are not
automatically changed when the bundled or remotely delivered catalog changes.

The category ID is deliberately a snapshot rather than a second live relationship.
Current category information can be obtained through the catalog product reference
when Product Knowledge is available, while the saved category remains renderable when
it is not.

### 3.5 Icon storage and resolution

The persisted icon value is a Product Knowledge semantic icon key. It is not:

- an SF Symbol name;
- an asset-catalog resource name;
- a rendered image;
- a platform-specific fallback.

Display precedence is:

1. user photo in `imageData`;
2. future explicit user icon override, if that feature is separately approved;
3. `catalogIconKeySnapshot` resolved by the app's semantic icon resolver;
4. the current generic product fallback.

WT-025B does not need a user-icon override field because there is no current user
workflow that creates one.

### 3.6 Source semantics

Add a `catalog` acquisition case to `ProductSource` for products created from an
autocomplete selection.

`source` must not determine whether a product is catalog-linked.
`catalogProductIDRawValue != nil` is the identity rule.

This distinction permits future flows such as:

- a catalog-resolved camera result with source `camera`;
- a catalog-resolved AI result with source `ai`;
- a barcode-resolved catalog result with source `barcode`;
- an autocomplete catalog result with source `catalog`.

All may carry the same stable catalog identity while preserving how the user obtained
the result.

The new raw value is additive; existing source values do not migrate. WT-025B must
audit every exhaustive `ProductSource` switch. Legacy recognition bridges may map
`catalog` to an unknown candidate source, but catalog-linked products should normally
bypass those learned-knowledge bridges entirely.

### 3.7 Brand aliases and community metadata

Brand aliases are Product Knowledge search and resolution metadata. They should not be
copied into every saved `Product`.

`Product.brand` remains the effective user/provider brand snapshot. A future accepted
community catalog contribution should receive a stable Product Knowledge `ProductID`
and use the same persistence contract. Submission provenance, moderation state, and
alias lists remain in Product Knowledge, not in the user-product table.

### 3.8 Model rules

For a catalog-linked product:

- `catalogProductIDRawValue` is non-empty and parseable as `ProductID`;
- display-name snapshot is non-empty;
- display locale is non-empty;
- category ID, category display name, and icon key are captured when available from
  the approved search-result contract;
- `name` is non-empty;
- `dateAdded`, `updatedAt`, and `catalogSnapshotUpdatedAt` are set.

For an unlinked product:

- all catalog identity and snapshot fields are `nil`;
- its existing fields retain their current meaning;
- it is never treated as catalog-linked because its name resembles a catalog entry.

Partially populated catalog metadata is tolerated when reading so a corrupt or
interrupted historical record remains accessible. The product falls back through its
effective fields and generic icon. New writes, however, must satisfy the complete
catalog-save contract.

### 3.9 Initializer and refresh ownership

Every `Product` creation path must make its catalog-field ownership explicit:

| Path | Catalog-field behavior |
| --- | --- |
| Existing manual initializer | Defaults every catalog field to `nil` |
| Legacy `ShoppingItem` initializer | Defaults every catalog field to `nil` |
| Unresolved `ProductCandidate` initializer | Defaults every catalog field to `nil` |
| Catalog save use case | Supplies ProductID and the complete approved snapshot |
| Refresh from legacy `ShoppingItem` | Preserves catalog fields without reading or clearing them |
| Refresh from unresolved `ProductCandidate` | Must never target a linked Product; also preserves catalog fields defensively |
| Photo update | Changes `imageData` and `updatedAt` only |
| Legacy `makeShoppingItem` conversion | Copies effective compatibility values; does not create a second catalog identity |

New optional initializer parameters should default to `nil` so current manual and
legacy call sites keep their characterized behavior. Only the catalog save use case is
authorized to pass a non-`nil` catalog ProductID during WT-025B.

## 4. Catalog Product Persistence

### 4.1 Save input

Introduce an immutable application-layer `CatalogProductSaveRequest` (the exact type
name may follow project conventions) containing:

- typed Product Knowledge `ProductID`;
- display-name snapshot;
- display locale;
- category-ID snapshot;
- category-display-name snapshot;
- semantic icon-key snapshot;
- optional user-selected photo data;
- acquisition source.

The autocomplete adapter builds this request directly from the explicitly selected
`ProductSearchResult` and its resolved localized category label. It must not rebuild a
catalog request from whatever text remains in the name field.

The request is a trusted selection snapshot. The catalog persistence service does not
need to copy or persist a `ProductEntity`, and it does not require network availability
at confirmation time.

### 4.2 Catalog save use case

Add a small main-actor catalog persistence service or use case beside
`ShoppingListService`. Its responsibility is limited to converting an explicit catalog
selection into a durable user `Product`.

The operation is:

1. Validate that the request has a non-empty typed ProductID, non-empty display name,
   and valid snapshot values.
2. Fetch `Product` records whose `catalogProductIDRawValue` equals the selected ID.
3. If more than one record exists, return an invariant error and emit diagnostics. Do
   not silently choose or merge a record.
4. If exactly one record exists, return an `alreadyInLibrary(existingProduct)` outcome
   without changing its name, category, snapshots, photo, notes, or timestamps.
5. If no record exists, create one new `Product`:
   - generate its normal user UUID;
   - initialize `name` from the display-name snapshot;
   - initialize `category` from the category-display snapshot;
   - store the ProductID and all catalog snapshots;
   - store the explicitly selected photo, if any;
   - set the acquisition source;
   - set `dateAdded`, `updatedAt`, and `catalogSnapshotUpdatedAt` to the operation time.
6. Insert the product and call `modelContext.save()` once.
7. Return success only after the save succeeds.

An existing same-ID product is not modified during Add Product. In particular, a
newly chosen draft photo does not silently replace that product's current photo.
Editing an existing product is a different user intent and should use an explicit edit
flow.

### 4.3 Save failure contract

On a catalog save failure:

- the Add Product UI keeps the selected result and user photo;
- the UI does not dismiss;
- the UI presents a retryable error;
- no success diagnostic is emitted;
- no legacy learned-knowledge write is attempted;
- the use case removes any new uncommitted object it inserted, without rolling back
  unrelated context changes.

The use case should enter with no unrelated unsaved work and should own the single save
boundary for its new product.

### 4.4 Product Knowledge repository interaction

`ProductKnowledgeRepository` remains read-only. It continues to provide:

- catalog entities and localized names;
- category resolution;
- icon-key resolution;
- current active/inactive state;
- search input for `ProductKnowledgeSearch`;
- future comparison of current facts with saved snapshots.

Catalog persistence consumes the explicit search selection; it does not write to the
repository.

An optional current-record validation may be performed before mutation when the
repository snapshot is available. That validation must not replace the user-visible
selection snapshots with newer text during the save, and temporary absence of a
record must not turn the selection into a manual product. If policy rejects a stale
selection, the UI remains in selection state and asks the user to choose again.

### 4.5 Legacy learned Product Knowledge

Do not call `ProductKnowledgeService.learn` for an explicitly catalog-linked save.

The catalog already owns the canonical reference data. Learning a second
name/barcode-keyed record would create divergent identities and make later duplicate
handling ambiguous.

## 5. Manual Product Persistence

### 5.1 Existing manual contract

The production manual path remains:

1. user enters a name and optionally selects a photo;
2. UI trims and validates the name;
3. UI calls `ShoppingListService.addManualProduct`;
4. the service inserts one manual `Product`;
5. the service saves once;
6. the UI resets and dismisses only on success.

WT-025B should not route manual creation through Product Knowledge search, catalog
deduplication, or the catalog save use case.

### 5.2 Manual record fields

For a manual product:

| Value | Stored behavior |
| --- | --- |
| User product ID | New UUID |
| Catalog ProductID | `nil` |
| Display name | Existing `name` |
| Catalog display snapshot | `nil` |
| Category | Existing optional effective `category` |
| Catalog category snapshots | `nil` |
| Catalog icon snapshot | `nil` |
| Photo | Existing user-owned `imageData` |
| Notes | Optional user-owned `notes`; initially `nil` unless a future UI supplies it |
| Timestamps | Existing `dateAdded` and `updatedAt` behavior |
| Source | `manual` |

All catalog fields remain `nil`, including when the manual name exactly matches a
catalog display name.

### 5.3 Recognized but unresolved products

A recognition result without an explicit catalog ProductID remains an unlinked product
and follows the current recognized-product path.

Before catalog-linked records ship, the heuristic recognized upsert must be constrained
to unlinked products. It must not refresh a catalog-linked product based solely on:

- matching barcode;
- matching normalized name;
- matching brand;
- matching category.

A future Product Knowledge resolver creates a typed catalog save request only after it
has resolved a stable ProductID. Resolved recognition then uses the catalog save use
case while retaining its acquisition source. Unresolved recognition continues to use
the current legacy upsert.

## 6. Migration Strategy

### 6.1 Migration objective

The migration is a schema evolution, not a catalog-matching project.

Every existing user record must keep:

- its UUID;
- name and image;
- brand, category, barcode, and details;
- source;
- timestamps;
- relationships;
- shopping completion and quantity state;
- legacy compatibility links.

### 6.2 Introduce explicit schema versioning

WT-025B should introduce a SwiftData `VersionedSchema` and
`SchemaMigrationPlan`:

- **V1** reproduces the exact currently shipped model graph.
- **V2** adds the optional catalog-link, snapshot, and notes fields to `Product`.
- **V1 → V2** uses a lightweight additive migration.

The container continues to include all current models. No existing model or attribute
is deleted, renamed, or repurposed in this migration.

Before implementation is accepted, a V1 fixture generated with the current production
schema must successfully open under V2. Defining V1 approximately is insufficient;
its model checksum and relationships must represent the shipped store.

### 6.3 Existing-row behavior

For every existing `Product`, the migration sets by absence/default:

- `catalogProductIDRawValue = nil`;
- all catalog snapshots to `nil`;
- `catalogSnapshotUpdatedAt = nil`;
- `notes = nil`.

No existing field is rewritten. There is no normalization pass and no timestamp
change.

This means an existing product called “Milk” remains the same unlinked user product,
even if the Product Knowledge catalog contains a “Milk” entry.

### 6.4 No forced catalog matching

Migration must not link by:

- normalized display name;
- localized name;
- alias;
- barcode;
- brand;
- category;
- icon;
- photo;
- legacy ProductKnowledge key;
- recognition confidence.

False merges are more damaging than temporary duplicate-looking products. A future
explicit “Link to catalog” workflow may offer user-governed linking, but it is not part
of automatic migration.

### 6.5 Runtime compatibility backfill

Keep `ShoppingListBackfillService` because it still reconciles legacy
`ShoppingItem`, `Product`, and `ShoppingListEntry` records.

Update its contract and tests so that:

- refreshing a product from a legacy `ShoppingItem` never clears catalog ID or
  snapshots;
- rerunning backfill remains idempotent;
- a catalog-linked Product keeps its user UUID and catalog identity;
- a legacy item cannot cause name-based catalog linkage;
- entry repair continues to use `Product.id`.

New catalog fields are outside the ownership of the legacy backfill.

### 6.6 Failure and rollback policy

If store migration fails:

- do not delete or recreate the store;
- do not fall back to an empty store;
- report a diagnostic that includes the schema transition;
- keep the original store intact for retry or support recovery.

The additive fields make a forward, feature-disabled rollback possible: a
V2-compatible build can ignore catalog fields and continue to display existing
effective `Product` values.

An older V1 application binary must not be assumed to open a store after V2 has written
it. Release rollback therefore means shipping a V2-schema-compatible build with the
catalog feature disabled, not reinstalling the old schema.

### 6.7 Rollout

Recommended rollout order:

1. add and test explicit V1/V2 schema handling;
2. ship or validate the additive fields with all catalog writes disabled;
3. validate migration telemetry and compatibility backfill;
4. enable the catalog save use case behind the same feature gate as autocomplete;
5. enable the autocomplete UI only when both selection and catalog persistence are
   present.

The application must not expose a selectable catalog result if confirmation would
still call the manual save method.

## 7. Save Flow Diagrams

### 7.1 Add Product decision and persistence

```text
Open Add Product
        |
        v
User enters name / sees local Product Knowledge suggestions
        |
        +---------------- explicit catalog selection ----------------+
        |                                                            |
        |                                                            v
        |                                           Catalog selection snapshot
        |                                           - ProductID
        |                                           - localized display name
        |                                           - locale
        |                                           - category snapshots
        |                                           - semantic icon key
        |                                           - optional user photo
        |                                                            |
        |                                                            v
        |                                            User confirms Add Product
        |                                                            |
        |                                                            v
        |                                      Catalog product save use case
        |                                      - dedupe by ProductID only
        |                                      - insert Product if absent
        |                                      - one SwiftData save
        |                                                            |
        |                         +------------------+----------------+
        |                         |                                   |
        |                    save succeeds                        save fails
        |                         |                                   |
        |                         v                                   v
        |                created / already present          retain draft + error
        |                         |
        |                         v
        |                 dismiss/reset on success
        |
        +---------------- explicit custom choice --------------------+
                                                                     |
                                                                     v
                                                         Manual draft
                                                         - typed name
                                                         - optional photo
                                                                     |
                                                                     v
                                                     User confirms Add Product
                                                                     |
                                                                     v
                                                Existing addManualProduct
                                                - create independent Product
                                                - catalog fields nil
                                                - one SwiftData save
                                                                     |
                                            +------------------------+---------+
                                            |                                  |
                                       save succeeds                       save fails
                                            |                                  |
                                            v                                  v
                                   dismiss/reset on success           retain draft + error
```

The flows diverge before persistence request construction. They do not diverge inside
the existing manual save method.

### 7.2 Persisted graph after a catalog save

```text
Product Knowledge catalog (read-only)
ProductEntity.id: ProductID
             |
             | stable reference + selected snapshots
             v
User library Product (SwiftData)
- id: UUID
- catalogProductIDRawValue: ProductID.rawValue
- effective user fields
- catalog snapshots
             |
             | existing Product relationship / UUID
             v
ShoppingListEntry
- productID: Product.id
- product: Product
             |
             | current compatibility behavior when added to shopping
             v
Legacy ShoppingItem snapshot
```

No SwiftData relationship points directly to `ProductEntity`, and no catalog entity is
inserted into the user store.

### 7.3 Future recognition flow

```text
Recognition provider result
          |
          v
Product Knowledge resolver
          |
          +---------------- stable ProductID resolved ----------------+
          |                                                            |
          |                                                            v
          |                                         Catalog save request
          |                                         source = camera / ai / barcode
          |                                                            |
          |                                                            v
          |                                         Catalog save use case
          |
          +---------------- unresolved candidate ---------------------+
                                                                       |
                                                                       v
                                                Existing recognized upsert
                                                restricted to unlinked Products
```

### 7.4 Later shopping-list insertion

Both catalog and manual products converge here:

```text
Persisted Product.id
        |
        v
ShoppingListService.addProductToShopping
        |
        +--> create/reuse ShoppingListEntry by Product.id
        |
        +--> maintain legacy ShoppingItem compatibility snapshot
        |
        +--> record current ShoppingMemory behavior
```

Catalog identity does not change this entry relationship.

## 8. Repository Responsibilities

### 8.1 ProductKnowledgeRepository

Keep the existing repository read-only. It owns current catalog facts:

- ProductEntity lookup;
- localized names and aliases;
- categories;
- semantic icon keys;
- active/inactive status;
- immutable snapshots consumed by search.

It does not:

- save user products;
- store photos or notes;
- mutate SwiftData;
- decide whether two user products should merge;
- overwrite saved catalog snapshots.

### 8.2 ProductKnowledgeSearch

Search continues to return stable `ProductID` values with localized display metadata.
To satisfy the WT-024A and WT-025B boundary cleanly, the selected result must provide
or be adapted with:

- localized category display text in addition to category ID;
- the actual locale of the `displayName` record;
- the semantic icon key.

The existing `matchedLocale` remains search-match provenance and cannot substitute for
the display locale. Either `ProductSearchResult` gains an explicit `displayLocale`, or
the autocomplete adapter resolves the selected preferred `ProductName` and carries its
locale into `CatalogProductSaveRequest`.

Ranking metadata is transient and is not persisted.

### 8.3 Catalog product save use case

The new use case owns:

- validating a catalog save request;
- querying user Products by catalog ProductID;
- enforcing the one-user-product-per-catalog-ID invariant;
- initializing effective values and snapshots;
- a single durable save;
- typed outcomes for created, already present, and failed.

It does not own search, catalog loading, suggestion state, manual creation, product
editing, or shopping-list insertion.

### 8.4 ShoppingListService

Keep the current manual entry point stable.

Changes in WT-025B should be limited to:

- adding the catalog save collaborator only if project composition places product
  persistence in this service;
- protecting catalog-linked products from unresolved recognition heuristics;
- avoiding legacy learned-knowledge writes for known catalog products;
- preserving catalog fields during legacy refresh and photo synchronization.

A separate `CatalogProductPersistenceService` is preferred because it prevents the
characterized manual method from accumulating search and deduplication branches.

### 8.5 User-product repository abstraction

Do not introduce a general `ProductRepository` protocol solely for WT-025B. The app
currently persists user products through SwiftData `ModelContext`, and a new abstraction
would broaden the migration without adding a second backend.

The catalog save use case can be tested against an in-memory SwiftData container.
Introduce a user-product repository later only if cloud sync, multiple stores, or a
separate persistence backend creates a real boundary.

### 8.6 Composition

App composition should construct:

- the existing read-only Product Knowledge repository;
- `ProductKnowledgeSearch`;
- the catalog save use case with the main user-data model context;
- the Add Product view model or adapter that owns transient selection state.

The UI receives dependencies; it must not construct a repository or model container.

### 8.7 Query and uniqueness

WT-025B should enforce uniqueness in the serialized application write path:

- catalog saves run on the main actor/model context;
- the UI disables repeated confirmation while a save is in flight;
- every save queries exact raw ProductID before insertion;
- multiple matches are an error.

Do not add a uniqueness constraint to the optional catalog ID until its behavior with
multiple `nil` values, migration, and the app's deployment targets has been proven.
The user library is small enough that an exact predicate query is adequate initially.
An index can be added later based on measured need and supported SwiftData APIs.

## 9. Future Catalog Updates

### 9.1 Default policy: saved appearance is stable

Opening the app, loading a new bundled catalog, or refreshing community data does not
rewrite saved products.

The user continues to see the effective values stored on `Product`, with saved
snapshots and photo fallbacks. This protects user expectations, offline operation, and
compatibility with existing views.

### 9.2 Renamed catalog entry

If a catalog entry is renamed:

- previously saved products keep their current `name`;
- their display-name snapshot remains the label captured at selection;
- search returns the new current name with the same ProductID;
- selecting the renamed result finds the existing Product by ProductID;
- no duplicate is created;
- the existing Product is not silently renamed.

### 9.3 Changed category

If the catalog category changes:

- the saved effective `category` remains unchanged;
- the category ID and display-name snapshots remain unchanged;
- current catalog category may be shown as informational metadata in a future review
  UI;
- shopping behavior continues from the saved Product.

### 9.4 Changed icon

If a catalog icon changes:

- a saved user photo continues to win;
- the saved semantic icon snapshot continues to resolve;
- no platform resource name is migrated;
- a future explicit refresh may replace the semantic snapshot.

### 9.5 Inactive, deleted, or missing catalog entry

Product Knowledge should normally deactivate entries rather than delete them, and IDs
must never be reused.

If a referenced entry becomes inactive or cannot be found:

- the user `Product` is not deleted or unlinked;
- its ProductID remains stored;
- its name, category, icon snapshot, photo, and notes remain available;
- it can still be added to shopping;
- search should not offer an inactive item as a new result;
- duplicate detection still uses the saved ProductID if a result or redirect resolves
  to it.

Absence is catalog status, not user-data corruption.

### 9.6 Derived update status

A future reconciliation reader may compare the saved snapshot with current Product
Knowledge and derive, without persisting on every launch:

- unchanged;
- catalog metadata changed;
- inactive;
- missing.

Do not store these as authoritative booleans because they become stale as soon as the
catalog revision changes.

### 9.7 Explicit future refresh

If a future UI allows the user to apply catalog updates, update atomically:

1. capture the old snapshots;
2. fetch the current record for the same ProductID;
3. replace the catalog snapshots;
4. replace effective `name` only if it still exactly equals the old name snapshot;
5. replace effective `category` only if it still exactly equals the old category
   display snapshot;
6. preserve any divergent user values, photo, notes, UUID, relationships, and
   `dateAdded`;
7. update `catalogSnapshotUpdatedAt` and `updatedAt`;
8. save once.

This “update only when still equal to the prior baseline” rule prevents catalog
refresh from erasing user overrides.

### 9.8 Aliases, community entries, and redirects

New aliases affect discovery, not saved rows. A renamed brand alias does not rewrite
`Product.brand`.

Community catalog entries use the same ProductID contract after acceptance.

If Product Knowledge later supports entity redirects or merges, the repository must
canonicalize a selected/resolved ProductID before duplicate lookup. A redirect may
update the stored catalog ProductID through an explicit migration while preserving the
user Product UUID and all snapshots. IDs must never be guessed or reused.

## 10. Duplicate Strategy

### 10.1 Duplicate definition

For catalog-aware persistence, a catalog duplicate means two user `Product` records
linked to the same canonical Product Knowledge `ProductID`.

Display-name equality is not catalog equality.

### 10.2 Required cases

| Situation | Required behavior |
| --- | --- |
| Same ProductID selected twice | Return the existing Product; create no duplicate and change no existing fields |
| Manual product has the same display name | Keep it unlinked; a selected catalog product may exist beside it |
| Two manual products have the same name | Preserve current behavior; both may exist |
| Catalog product is renamed | Same ProductID resolves to the existing Product despite different display text |
| Two catalog IDs share the same display name | Persist as distinct user Products |
| Barcode matches a catalog-linked Product but no ProductID was resolved | Do not treat the barcode as proof of catalog identity |
| Multiple stored Products already have one ProductID | Fail with an invariant error and diagnostics; do not silently merge |
| Catalog entry is inactive or missing | Keep the saved Product and its identity; do not recreate it as manual |

### 10.3 Manual-to-catalog linking

Do not automatically convert a manual Product when the user later selects a catalog
result with the same name.

A future explicit linking workflow may populate catalog fields on the existing UUID,
but it must:

- show the proposed match to the user;
- preserve effective user values and photos;
- detect whether another Product already owns the target ProductID;
- require a separate, user-governed merge choice if both exist;
- be independently tested and approved.

WT-025B should prefer a visible pair of similar products over an irreversible false
merge.

### 10.4 Recognition duplicates

The recognition pipeline must distinguish:

- explicit ProductID resolution, which uses catalog deduplication;
- unresolved heuristic matching, which may inspect only unlinked Products.

This prevents an AI or camera label change from overwriting a stable catalog-linked
record.

## 11. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| V1 schema does not exactly represent the shipped store | Existing stores may fail to open | Build a production-schema V1 fixture and run migration tests before enabling writes |
| Optional-field migration is assumed rather than tested | Launch failure or empty-looking data | Use explicit versioning, lightweight migration tests, and never recreate the store on failure |
| Catalog match inferred from an existing name | False merges and lost user distinctions | Migrate all existing rows as unlinked; require explicit ProductID |
| `ShoppingListEntry.productID` is repurposed | Broken relationships and shopping data | Keep it as the user `Product.id` UUID |
| Legacy `ProductKnowledge` is mistaken for catalog storage | Divergent identities and update conflicts | Keep the learned cache separate and skip learning known catalog products |
| Catalog update overwrites user edits | Visible data loss and loss of trust | Snapshot-stable default; explicit refresh protects values that differ from old snapshots |
| Same ProductID is inserted twice | Ambiguous user identity | Main-actor save, exact preflight query, in-flight UI guard, invariant diagnostics |
| Optional unique constraint rejects multiple `nil` values or complicates migration | Migration or insertion failures | Enforce in service first; add a database constraint only after platform validation |
| Recognition heuristics mutate a catalog record | Catalog identity is attached to unrelated provider data | Exclude linked Products from unresolved upsert; resolved path must carry ProductID |
| Save error leaves UI looking successful | Reliability regression | One durable save, typed failure, keep draft, dismiss only after success |
| Failed save leaves a pending inserted object | A retry may create confusing context state | Remove the use case's uncommitted insertion and test retry behavior |
| Catalog name/category/icon disappears | Saved product becomes blank or generic | Store localized snapshots and semantic icon key |
| Platform icon identifier is persisted | Cross-platform coupling and broken assets | Persist semantic Product Knowledge icon key only |
| Automatic catalog refresh changes a user's library | Unexpected UX and hard-to-reverse changes | No automatic mutation on launch or catalog update |
| Old binary is used as rollback after V2 writes | Store compatibility failure | Roll back with a V2-compatible feature-disabled build |
| Manual duplicates are accidentally blocked | Breaks characterized current behavior | Catalog dedupe applies only when ProductID is present |
| Existing compatibility backfill clears new fields | Catalog link loss | Define field ownership and add idempotent backfill preservation tests |
| Catalog and manual save branches drift in failure UX | Inconsistent Add Product reliability | Share UI save-state/error handling while keeping persistence methods separate |
| Snapshot locale is omitted | Ambiguous text after locale changes | Persist the locale identifier alongside localized snapshots |
| Notes are treated as catalog data | User-authored data could be overwritten | Make notes user-owned and exclude them from catalog refresh |

## 12. Testing Strategy

### 12.1 Migration tests

Create store-level migration fixtures, not only freshly created in-memory V2 stores.

Required cases:

1. Open a V1 store containing manual, recognized, legacy-backed, photographed, and
   shopping-linked products under V2.
2. Assert every existing UUID, relationship, field, image byte sequence, source, and
   timestamp is unchanged.
3. Assert all new catalog fields and notes are `nil`.
4. Assert no catalog matching occurs for names and barcodes that happen to exist in the
   pilot catalog.
5. Rerun app startup and compatibility backfill and verify idempotence.
6. Verify a migration failure leaves the original store intact and does not open an
   empty replacement.
7. Verify a V2-compatible, autocomplete-disabled configuration can read catalog-linked
   products through existing effective fields.

### 12.2 Catalog persistence tests

Required cases:

- explicit selection inserts one `Product` with a new user UUID and exact ProductID;
- all localized snapshots, locale, semantic icon key, timestamps, source, and optional
  photo are stored;
- effective name and category initialize from snapshots;
- no `ShoppingItem`, `ShoppingListEntry`, or legacy learned `ProductKnowledge` is
  created by library save alone;
- a save failure returns failure, leaves no committed product, and permits a clean
  retry;
- success is emitted only after `ModelContext.save`;
- a reload from a new model context returns the same identity and snapshots.

### 12.3 Duplicate tests

Required cases:

- selecting the same ProductID twice returns the same user Product;
- the second selection does not overwrite name, category, photo, notes, or timestamps;
- the same name with different ProductIDs creates distinct products;
- a manual product with the same name does not prevent catalog insertion;
- renamed search result with the same ProductID returns the existing product;
- multiple preexisting rows with the same ProductID return an invariant failure;
- inactive or currently missing catalog data does not destroy the saved product.

### 12.4 Manual backward-compatibility tests

Keep all current manual-product characterization tests.

Add assertions that:

- manual creation leaves every catalog field `nil`;
- duplicate manual names are still allowed;
- name trimming remains the UI responsibility currently characterized;
- photo save and failure recovery remain unchanged;
- no catalog repository or search call is required for manual confirmation;
- manual products can still be added to shopping exactly as before.

### 12.5 Shopping and compatibility tests

Required cases:

- a catalog Product can be added to shopping using its user UUID;
- `ShoppingListEntry.productID` equals `Product.id`;
- the legacy `ShoppingItem` mirror contains effective display values but does not
  become catalog identity;
- photo synchronization preserves catalog ID and snapshots;
- deleting shopping entries does not mutate catalog snapshots;
- runtime backfill does not clear catalog fields;
- catalog-linked shopping activity does not create a legacy learned
  `ProductKnowledge` record.

### 12.6 Recognition tests

Required cases:

- unresolved recognized candidates do not match catalog-linked Products by name,
  category, brand, or barcode;
- unresolved recognition retains current matching behavior among unlinked products;
- explicitly resolved ProductID uses the catalog save path;
- acquisition source remains camera, AI, or barcode as applicable;
- a resolved duplicate returns the existing catalog-linked Product;
- a recognition save failure does not partially learn into the legacy cache.

### 12.7 Catalog update tests

Use repository fixtures representing two catalog revisions:

- rename with stable ProductID;
- category change with stable ProductID;
- icon-key change;
- inactive entity;
- missing entity;
- new alias for an existing entity.

Assert that opening or searching the new revision does not mutate saved Products.
Assert that deduplication still works by ProductID. If explicit refresh is implemented
later, separately verify preservation of effective values that differ from their old
snapshots.

### 12.8 UI integration tests

WT-024B UI tests should cover the persistence boundary:

- catalog selection remains transient until Add Product is confirmed;
- editing text after a selection clears or changes selection according to the UX
  contract and cannot save a stale ID under new text;
- explicit custom choice calls only the manual method;
- explicit catalog choice calls only the catalog method;
- repeated taps while saving do not create two records;
- save failure keeps the draft and selection;
- existing same-ID outcome does not create or overwrite a product;
- successful save dismisses only after persistence succeeds.

### 12.9 Test infrastructure

Use:

- an in-memory SwiftData container for save-use-case unit tests;
- file-backed temporary stores for migration and relaunch tests;
- deterministic Product Knowledge repository fixtures;
- injected time for exact timestamp assertions;
- injected save failures for reliability tests;
- diagnostics assertions for duplicate-invariant failures.

The production schema test must include every model registered by app composition, not
an isolated `Product` schema.

## 13. Recommendation

Proceed with a minimal additive WT-025B implementation built around these decisions:

1. Introduce explicit SwiftData V1/V2 schema versioning before writing catalog data.
2. Add an optional Product Knowledge ProductID and localized selection snapshots to
   the existing user-owned `Product`.
3. Keep `Product.id` and `ShoppingListEntry.productID` unchanged.
4. Migrate every existing record as unlinked with zero matching or rewriting.
5. Preserve `name`, `category`, photo, notes, and timestamps as user-owned/effective
   data.
6. Add a separate catalog save use case that deduplicates only by ProductID and saves
   once.
7. Leave `addManualProduct` and duplicate-manual-name behavior unchanged.
8. Keep `ProductKnowledgeRepository` read-only and keep the legacy learned
   `ProductKnowledge` model separate.
9. Make saved snapshots stable across catalog changes; defer mutation to an explicit
   future refresh workflow.
10. Protect catalog-linked products from unresolved recognition heuristics and legacy
    backfill writes.
11. Gate autocomplete selection until catalog persistence and its migration tests are
    complete.

This architecture preserves current user data and manual save reliability while
providing a stable identity boundary for autocomplete, AI recognition, community
catalog entries, aliases, and future Product Knowledge revisions.

APPROVED FOR WT-025B IMPLEMENTATION

## 14. WT-026A Canonical Catalog Compatibility Layer

WT-026A adds a source-format boundary ahead of search and persistence:

```text
legacy v2 JSON ───────┐
                     ├─> ProductCatalogCompatibilityDecoder
canonical schema v1 ─┘          |
                                 v
                         CatalogProduct
                                 |
                      search / personalization
                                 |
                     existing catalog save path
```

`CatalogProduct` is the only production product-concept record used by the Hebrew
catalog path. Its canonical fields are `id`, `canonicalName`, `categoryId`,
nullable `subcategoryId`, `aliases`, `keywords`, `brandTerms`, popularity, active
state, and optional replacement metadata.

The decoder maps legacy `name` to `canonicalName` and supplies safe defaults for
fields absent from v2. It does not alter product IDs, category IDs, aliases,
popularity, or active state. Canonical schema version 1 decodes directly to the same
model. Search and persistence never branch on source format.

The shared taxonomy in `shared/catalog/taxonomy.json` validates canonical assignments
and every legacy category through an explicit compatibility map. It does not rewrite
legacy category IDs during WT-026A, because doing so would change current display
labels, semantic icons, and selection snapshots. Product-by-product category
migration is deferred to WT-026B.

The validator fails atomically for unsupported schema/taxonomy metadata, invalid
stable IDs, duplicate normalized canonical names, alias ownership collisions,
orphan/mismatched taxonomy references, invalid popularity, inconsistent inactive
replacements, missing targets, and replacement loops.

Catalog-aware persistence remains unchanged:

- `Product.id` is still the user-library UUID.
- `ShoppingListEntry.productID` still references that UUID.
- `catalogProductIDRawValue` still stores the stable canonical ID.
- Same-ID saves deduplicate regardless of whether the result originated in v2 or
  canonical JSON.
- Custom Products remain unlinked.
- Saved snapshots and personalization history are not migrated.

Future Android code should consume the same JSON Schema, taxonomy, normalization
fixtures, and acceptance fixtures with native Kotlin implementations. No backend or
remote delivery is introduced by WT-026A.

The exact next persistence-safe migration is **WT-026B — Canonical Taxonomy
Assignment and Bundled-Resource Migration**: review all 147 category assignments,
resolve every compatibility mapping marked `product_review_required`, migrate the
bundled resource to canonical schema version 1, and verify byte-independent semantic
equivalence without changing any product ID or user record.

## 15. WT-026B Canonical Bundled-Resource Migration

WT-026B completes that migration. The production resource is canonical schema
version 1, catalog version 3, and taxonomy version 1. All 147 products have an
explicit reviewed canonical category and nullable subcategory; the maintenance-only
review manifest is `shared/catalog/product-taxonomy-review.json`.

The legacy decoder remains at the source boundary for backward compatibility, but
the shipped resource now follows the canonical path directly:

```text
canonical catalog v3 ─> compatibility decoder ─> CatalogProduct
                                               ├─> unchanged search/ranking
                                               ├─> unchanged personalization scores
                                               └─> unchanged catalog-aware save path
```

The migration preserves persistence identity:

- All 147 `CatalogProduct.id` values are unchanged as a set.
- Existing `catalogProductIDRawValue` links continue to resolve.
- User-library UUIDs and shopping-entry relationships are not rewritten.
- Canonical-name, alias, brand-term, and legacy-name searches return the same stable
  catalog ID.
- Legacy normalized-name history can recognize retained aliases/legacy names, while
  exact catalog-ID history remains authoritative.
- Custom products remain unlinked and keep their existing identity.

Canonical taxonomy can differ from the former aisle category without changing saved
identity. The iOS presentation adapter maps approved subcategories to established
labels and icon metadata where needed; platform metadata is not stored in the shared
registry. Search match tiers, ranking weights, suggestion limits, personalization
scoring, and custom-save behavior are unchanged.

The archived v2 fixture and representative before/after queries prove semantic
equivalence. The validator and review-manifest tests reject unresolved taxonomy
work, invalid parent relationships, identity/name/alias/brand collisions, and broken
replacement metadata.

## 16. WT-027A Controlled Catalog Expansion

WT-027A adds 320 reviewed catalog concepts and brings the bundled Hebrew catalog to
467 active products. It does not change the persistence boundary: existing
`catalogProductIDRawValue` values still resolve through the same original stable
IDs, new products use new stable IDs, and custom products remain unlinked.

All additions use canonical schema version 1 and taxonomy version 1. Each was
candidate-checked, dry-run, and committed by the authoring toolkit. The resulting
catalog version is 333, the review manifest contains 467 assignments, and the
append-only audit contains 320 contiguous add transactions followed by 10 semantic
alias/keyword/brand review updates. Shared Wave 1 search fixtures are executed in
Node and Swift without adding schema-version branches to search, personalization,
UI, or persistence.
