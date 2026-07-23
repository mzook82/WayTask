# WT-020 Product Entity Data Model

**Version:** 1.1<br>
**Status:** WT-022A Phase 1 foundation profile approved; later extensions proposed<br>
**Scope:** Platform-neutral Product Concept and runtime-catalog contract<br>
**Implementation:** WT-022A foundation only; integration and persistence changes deferred

---

## 1. Model Goals

The WT-022A data model provides:

- One stable Product ID per generic catalog Product Concept.
- Authoritative localized names and aliases.
- Exactly one approved Phase 1 category per concept.
- Category-derived semantic icons.
- One versioned, validated, read-only runtime catalog.
- A platform-neutral contract that can later support Search and Autocomplete.

WT-022A intentionally excludes sellable variants, brands, sizes, prices, barcodes, search projections, writable persistence, user-library links, Shopping links, migration, provider observations, media, nutrition, and synchronization.

The Phase 1 domain values and serialized catalog contract are shared conceptually across platforms. They must not depend on SwiftData, SwiftUI, UIKit, Android resources, or provider payloads.

---

## 2. Phase 1 Product Identity

### 2.1 Normative decision

In WT-022A, `ProductEntity` represents only a generic **Product Concept**.

Examples:

- Milk is a Product Concept and may be a `ProductEntity`.
- Tnuva Milk 3% 1 L is a Sellable Variant and is outside WT-022A.
- Protein Vanilla Pudding may remain a Custom User Product created by the current manual flow if no catalog concept exists.

There is no `entityKind`, `variantOfProductID`, brand, barcode, package, price, or provider field in the WT-022A Product Entity.

### 2.2 Object meanings and relationships

| Object | Owner | WT-022A relationship |
|---|---|---|
| `ProductEntity` | Read-only runtime catalog | Generic Product Concept only |
| Sellable Variant | Deferred retail model | Not represented or loaded |
| Brand | Deferred retail qualifier | Not a Product Entity and not stored in catalog v1 |
| Current `Product` | Existing user Product Library | Unchanged; no catalog ID is added |
| Current `ShoppingListEntry` | Existing user shopping-list membership | Unchanged; continues to reference current `Product.id` |
| Legacy `ShoppingItem` | Existing compatibility shopping data | Unchanged; no catalog ID is added |
| Custom User Product | Existing user-owned `Product` created manually | Remains valid, mutable, and independent of the read-only catalog |
| `ProductName` alias | Catalog metadata | Belongs to one Product Entity and never creates another identity |

The conceptual term “shopping item” means user-owned list state. In the current iOS codebase that state is implemented through `ShoppingListEntry` and a legacy compatibility `ShoppingItem`. WT-022A does not change either representation.

### 2.3 Deferred integration contract

WT-022A only loads the catalog. Search, Autocomplete, selection, saving, and catalog references are deferred.

When a later approved feature links user-owned state to a catalog concept, it must preserve:

- The stable catalog Product ID.
- A user-visible display-name snapshot in user-owned persistence.

The snapshot prevents data loss and preserves the user's visible item when a catalog resource is absent, renamed, deactivated, or upgraded. WT-022A does not add that field or perform any link, migration, backfill, or dual write.

---

## 3. Phase 1 Aggregate Overview

```text
ProductEntity
  |-- ProductName (canonical, localized, alias)
  |
  +-- ProductCategory (one approved top-level category)

Existing user-owned models (not linked in WT-022A)
  |-- Product
  |-- ShoppingListEntry
  +-- legacy ShoppingItem
```

The domain layer exposes:

```text
ProductEntity
  id: ProductID
  defaultNameID: ProductNameID
  primaryCategoryID: ProductCategoryID
  status: active | inactive
```

Names and categories are separate catalog records. `ProductEntity` does not duplicate display names, localized names, aliases, or category icon keys.

---

## 4. Product Entity

| Field | Type | Required | Rules |
|---|---|---:|---|
| `id` | Opaque string ID | Yes | Stable, unique, never name-derived or reused |
| `defaultNameID` | Opaque Product Name ID | Yes | References the preferred English name belonging to this product |
| `primaryCategoryID` | Approved Category ID | Yes | Exactly one ID from taxonomy version 1.0 |
| `status` | Enum | Yes | `active` or `inactive` |

Constraints:

- `id` is the primary key.
- Released Product IDs never change, get reused, or get reassigned.
- Every `defaultNameID` resolves to a name owned by the same Product Entity.
- `primaryCategoryID` resolves to one of the 15 approved taxonomy IDs.
- A released entity may be changed to `inactive` but must not be deleted.
- All 15 initial pilot products are `active`.
- No concept/variant discriminator is stored because every catalog entity is a Product Concept.

---

## 5. Names and Aliases

### 5.1 `ProductName`

| Field | Type | Required | Notes |
|---|---|---:|---|
| `id` | Opaque ID | Yes | Row identity |
| `productID` | Product ID | Yes | Parent |
| `value` | String | Yes | User-visible name/alias |
| `locale` | BCP-47 tag | Yes | Language/script context |
| `kind` | Enum | Yes | `canonical`, `localizedDisplay`, or `alias` |
| `isPreferred` | Boolean | Yes | At most one preferred display name per product/locale |

Required uniqueness:

- `(productID, value, locale, kind)`.
- One preferred canonical/localized display name per `(productID, locale)`.

Alias rules:

- An alias is an alternate expression for the same Product Concept.
- An alias is search metadata only and is never a separate Product Entity.
- A brand, subtype, package size, or related product is not an alias.
- A single unconfirmed typo is not an approved alias.
- Catalog v1 uses only the aliases reviewed in `PilotProductCatalog.md`.
- Normalized search values are future versioned projections and are not stored by WT-022A.

Display fallback is exact requested locale, then language-only locale, then preferred English (`en`), then `defaultNameID`. The raw Product ID is not a normal user-visible fallback.

---

## 6. Taxonomy

### 6.1 `Category`

| Field | Type | Required | Notes |
|---|---|---:|---|
| `id` | Stable category ID | Yes | Example: `dairy` |
| `names` | Localized map | Yes | Exactly `en` and `he` in taxonomy v1.0 |
| `iconKey` | Semantic icon key | Yes | Cross-platform |
| `sortOrder` | Integer | Yes | Curated display order |
| `status` | Enum | Yes | `active` for all taxonomy v1.0 categories |

### 6.2 Taxonomy rules

- The catalog contains exactly the 15 IDs in `ProductTaxonomy.md`.
- Taxonomy version 1.0 contains no parent or subcategory field.
- Applications must not invent local categories or subcategories.
- Every Product Entity stores exactly one `primaryCategoryID`.
- Category icon keys exactly match `ProductTaxonomy.md`.
- `uncategorized` remains available, but no reviewed pilot product uses it.

---

## 7. Icon Model

WT-022A stores semantic icon keys on Product Categories only. A Product Entity resolves its icon from `primaryCategoryID`; `product.generic` is the fallback for an unknown category key.

Catalog schema version 1 has no product-specific icon override. Adding an override registry requires a later schema and governance decision. Platform visual mappings remain outside the catalog.

---

## 8. Deferred Data Model Extensions

Sections 8 through 18 describe possible later architecture only. They are not part of the WT-022A Product Entity, runtime JSON, repository, SwiftData schema, or implementation approval. In particular, WT-022A does not implement identifiers/barcodes, sellable variants, brands, relationships, media, nutrition, store affinity, provider metadata, provenance, library links, Shopping links, usage, redirects, or search projections.

### 8.1 `ProductIdentifier`

| Field | Type | Required | Notes |
|---|---|---:|---|
| `id` | Opaque ID | Yes | Row identity |
| `productID` | Product ID | Yes | Resolved entity |
| `scheme` | Enum/string | Yes | `gtin8`, `gtin12`, `gtin13`, `gtin14`, `upce`, `provider`, etc. |
| `value` | String | Yes | Original value |
| `normalizedValue` | String | Yes | Scheme-specific normalized value |
| `issuer` | String | No | Provider namespace for non-global IDs |
| `isPrimary` | Boolean | Yes | Display/preference only |
| `verificationState` | Enum | Yes | Confirmed/provider/unverified |
| `sourceContributionID` | Contribution ID | No | Provenance |

Recommended uniqueness:

- Global schemes: `(scheme, normalizedValue)`.
- Provider-scoped schemes: `(scheme, issuer, normalizedValue)`.

One Product Entity can have multiple identifiers to support package-size changes, regional barcodes, and provider IDs.

Barcode normalization must be scheme-aware. It must not be implemented as lowercasing an arbitrary string.

---

## 9. Brands and Relationships

### 9.1 `Brand`

| Field | Type | Required |
|---|---|---:|
| `id` | Brand ID | Yes |
| `displayName` | String | Yes |
| `normalizedName` | String | Yes |
| `status` | Enum | Yes |

### 9.2 `ProductBrandLink`

Supports one or more brand roles:

- Manufacturer.
- Consumer brand.
- Private label.

### 9.3 `ProductRelationship`

| Field | Type | Required | Examples |
|---|---|---:|---|
| `sourceProductID` | Product ID | Yes | Oat Milk SKU |
| `targetProductID` | Product ID | Yes | Oat Milk generic |
| `kind` | Enum | Yes | `variantOf`, `replacementFor`, `relatedTo`, `bundleContains` |
| `sourceContributionID` | Contribution ID | No | Provenance |

`variantOfProductID` may be materialized on Product Entity for the common query while the relationship table remains extensible.

---

## 10. Media

### 10.1 `ProductMedia`

| Field | Type | Required | Notes |
|---|---|---:|---|
| `id` | Media ID | Yes | Stable metadata identity |
| `productID` | Product ID | Yes | Parent |
| `kind` | Enum | Yes | `icon`, `thumbnail`, `frontPackage`, `gallery`, `nutritionLabel` |
| `localAssetID` | Asset ID | No | Managed local file/blob |
| `remoteURL` | URL string | No | Optional source |
| `mimeType` | String | No | Validate before display |
| `width` / `height` | Integer | No | Pixels |
| `contentHash` | String | No | Dedup/integrity |
| `isPreferred` | Boolean | Yes | One preferred item per kind |
| `sourceContributionID` | Contribution ID | No | Provenance |
| `createdAt` | Instant | Yes | UTC |

Raw image bytes are not part of the core Product Entity row.

---

## 11. Nutrition

### 11.1 `ProductNutritionProfile`

Nutrition is an optional extension associated mainly with a sellable variant:

- Product ID.
- Serving quantity/unit.
- Measurement basis, such as per 100 g or per serving.
- Typed nutrient values and units.
- Locale/market.
- Effective date.
- Source contribution.
- Schema version.

Nutrition must be versioned and provenance-aware because label values can change.

---

## 12. Common Stores

### 12.1 `ProductStoreAffinity`

| Field | Type | Required | Notes |
|---|---|---:|---|
| `productID` | Product ID | Yes | Product |
| `storeID` or `storeTypeID` | Opaque ID | Yes | Specific store or category |
| `score` | Bounded decimal | Yes | Estimated affinity |
| `evidenceCount` | Integer | Yes | Aggregate only |
| `lastObservedAt` | Instant | No | UTC |
| `sourceContributionID` | Contribution ID | No | Local/provider/community |

This extension does not put user location history into Product Entity.

---

## 13. AI and Provider Metadata

### 13.1 `ProductMetadataEnvelope`

Experimental/provider-specific data uses a namespaced envelope:

| Field | Type | Required |
|---|---|---:|
| `id` | Metadata ID | Yes |
| `productID` | Product ID | Yes |
| `namespace` | String | Yes |
| `schemaVersion` | Integer | Yes |
| `payload` | JSON/blob | Yes |
| `sourceContributionID` | Contribution ID | Yes |
| `createdAt` | Instant | Yes |
| `expiresAt` | Instant | No |

Examples:

- `ai.gemini.recognition`
- `provider.openfoodfacts.raw`
- `community.aggregate.v1`

Rules:

- Metadata is not automatically authoritative.
- Stable, frequently queried facts graduate into typed tables.
- Provider payload size is bounded.
- Sensitive or unnecessary raw payload is not persisted.

---

## 14. Provenance and Contributions

### 14.1 `KnowledgeContribution`

| Field | Type | Required | Notes |
|---|---|---:|---|
| `id` | Contribution ID | Yes | Claim group |
| `sourceType` | Enum | Yes | Seed/user/barcode/camera/AI/community/import |
| `sourceName` | String | No | Provider/adapter |
| `sourceRecordID` | String | No | Provider reference |
| `confidence` | Decimal | No | Bounded 0...1 |
| `verificationState` | Enum | Yes | Suggested/confirmed/rejected/curated |
| `observedAt` | Instant | Yes | UTC |
| `acceptedAt` | Instant | No | UTC |
| `schemaVersion` | Integer | Yes | Payload interpretation |

The resolved Product Entity is local truth. Contributions explain where its facts came from and allow future conflict resolution without trusting the newest provider blindly.

Recommended default authority:

1. Explicit user override/confirmation.
2. Curated seed.
3. Verified barcode provider.
4. Accepted AI/camera result.
5. Unconfirmed provider/community observation.

Individual fields may have different policies; authority is not only one entity-wide source value.

---

## 15. User Library State

### 15.1 `UserProduct`

| Field | Type | Required | Notes |
|---|---|---:|---|
| `id` | User-product ID | Yes | Local row identity |
| `productID` | Product ID | Yes | Canonical reference |
| `preferredNameOverride` | String | No | User-only display preference |
| `preferredMediaID` | Media ID | No | User-selected image |
| `isFavorite` | Boolean | Yes | Future-compatible default false |
| `addedAt` | Instant | Yes | UTC |
| `updatedAt` | Instant | Yes | UTC |
| `removedAt` | Instant | No | Tombstone/restore behavior |

For a single-profile Phase 1 app, `productID` should be unique among active UserProduct rows. A future `profileID` can extend the uniqueness boundary without altering Product Entity.

Removing a UserProduct does not delete Product Entity.

---

## 16. Shopping and Usage References

### 16.1 Shopping

`ShoppingListEntry` references `productID`. It owns:

- List ID.
- Quantity/unit.
- Check state.
- Sort order.
- Notes.
- Created/updated timestamps.

### 16.2 Usage

`ProductUsage` replaces name-derived history identity:

| Field | Type | Required |
|---|---|---:|
| `productID` | Product ID | Yes |
| `addCount` | Integer | Yes |
| `firstAddedAt` | Instant | Yes |
| `lastAddedAt` | Instant | Yes |
| `lastCompletedAt` | Instant | No |
| `averageInterval` | Duration | No |

Future event-level learning may use append-only `ProductUsageEvent` rows and derive the aggregate.

---

## 17. Merge, Redirect, and Tombstone

### 17.1 `ProductRedirect`

| Field | Type | Required |
|---|---|---:|
| `retiredProductID` | Product ID | Yes |
| `survivingProductID` | Product ID | Yes |
| `reason` | Enum/string | Yes |
| `createdAt` | Instant | Yes |

Repository reads follow redirect chains with cycle detection and path compression/repair.

### 17.2 Deletion semantics

- **Remove from library:** tombstone/disable UserProduct only.
- **Retire catalog entity:** set Product Entity status and redirect or hide it.
- **Erase user-created knowledge:** only when policy and references permit; retain a tombstone if future sync/merge needs it.
- **Delete shopping entry:** does not delete Product Entity or UserProduct.

---

## 18. Search Projection

The search index is a rebuildable projection, not source of truth.

Each indexed document includes:

- Product ID.
- Normalized canonical/localized names.
- Normalized aliases.
- Tokenized keywords.
- Brand/category text at lower weights.
- Locale.
- Entity/verification status.

Usage recency/frequency may be joined or supplied as bounded ranking features. Image data and raw provider payloads are excluded.

---

## 19. Runtime Catalog Contract

### 19.1 Authoritative resource

The exact runtime filename is:

```text
product-knowledge-catalog-v1.json
```

The app reads this JSON resource only. `PilotProductCatalog.md` remains the human review record, and `ProductTaxonomy.md` remains authoritative for taxonomy meaning. The app does not parse either Markdown file.

### 19.2 Exact top-level shape

Catalog schema version 1 has exactly these top-level members:

```json
{
  "schemaVersion": 1,
  "catalogRevision": 1,
  "taxonomyVersion": "1.0",
  "expectedProductCount": 15,
  "supportedLocales": ["en", "he"],
  "categories": [],
  "products": [],
  "names": []
}
```

Required record shapes:

```json
{
  "categories": [
    {
      "id": "dairy",
      "names": {
        "en": "Dairy & Alternatives",
        "he": "מוצרי חלב ותחליפים"
      },
      "iconKey": "product.dairy",
      "sortOrder": 0,
      "status": "active"
    }
  ],
  "products": [
    {
      "id": "prd_pilot_0001",
      "defaultNameID": "name_prd_pilot_0001_en",
      "primaryCategoryID": "dairy",
      "status": "active"
    }
  ],
  "names": [
    {
      "id": "name_prd_pilot_0001_en",
      "productID": "prd_pilot_0001",
      "locale": "en",
      "kind": "canonical",
      "value": "Milk",
      "isPreferred": true
    },
    {
      "id": "name_prd_pilot_0001_he",
      "productID": "prd_pilot_0001",
      "locale": "he",
      "kind": "localizedDisplay",
      "value": "חלב",
      "isPreferred": true
    }
  ]
}
```

Aliases use the same name shape with `kind = alias` and `isPreferred = false`.

The schema contains:

- Exactly 15 categories.
- Exactly 15 products for catalog revision 1.
- The permanent Product IDs `prd_pilot_0001` through `prd_pilot_0015`.
- Separate name rows for all approved English/Hebrew names and aliases.
- No entity-kind, variant, subcategory, product icon, brand, barcode, package, price, keyword, normalized-value, provider, timestamp, or user-state field.

### 19.3 Version rules

- `schemaVersion` is `1` for the contract above.
- `schemaVersion` changes only for an incompatible shape or field-semantics change.
- `catalogRevision` increments for any product, name, alias, category assignment, status, or category-content change.
- `taxonomyVersion` changes only with an approved taxonomy revision.
- `expectedProductCount` must equal the number of product records.
- Adding content without changing the JSON shape does not change `schemaVersion`.
- Runtime revision 1 must remain at or below 100 KiB uncompressed.
- Catalog v1 uses no separate manifest, checksum, or detached signature; automated validation checks the exact packaged JSON, and the signed app bundle provides distribution authenticity.

### 19.4 Validation

Before shipping, validation must reject:

- Unknown or missing top-level members required by schema version 1.
- Unsupported schema or taxonomy versions.
- Any product count other than 15 in catalog revision 1.
- Duplicate or missing Product, Product Name, or Category IDs.
- Any Product ID outside the exact approved initial list.
- Broken default-name, product-name, or category references.
- Missing English/Hebrew preferred names.
- Duplicate/canonical-repeating aliases.
- Any category ID/name/icon mismatch with `ProductTaxonomy.md`.
- Subcategory, product icon override, variant, brand, barcode, package, price, or other unsupported fields.
- Deletion or reuse of a released Product ID.

The first JSON may be authored manually. A Catalog Generator is not required for WT-022A.

---

## 20. Relationship to Current Models

| Current field/model | WT-022A decision |
|---|---|
| `Product` | Unchanged user Product Library record; no catalog reference added |
| `Product.name` | Continues to be the current user-visible snapshot |
| `Product.brand`, barcode, image, package fields | Unchanged legacy/user data; not imported into catalog |
| `ShoppingListEntry.productID` | Continues to reference current `Product.id` |
| `ShoppingItem` | Unchanged compatibility record |
| `ProductKnowledge` | Unchanged recognition/learning cache |
| `ProductHistory` | Unchanged usage record |
| `ProductCandidate` | Unchanged transient recognition DTO |

WT-022A performs no mapping, migration, link, backfill, dual write, or persistence-schema change. The future mapping described by `ProductKnowledgeMigrationStrategy.md` is not approved or activated by this foundation.

---

## 21. Required WT-022A Invariants

- Every runtime `ProductEntity` is a generic Product Concept.
- Exactly 15 active Product Entities ship in catalog revision 1.
- Every Product ID is unique, stable, opaque, and never name-derived.
- Every Product Entity has one valid default English name and one approved primary category.
- Every initial entity has one preferred English and one preferred Hebrew name.
- Every alias belongs to one Product Entity and is never an independent identity.
- Every category and semantic icon key matches taxonomy version 1.0.
- No Product Entity contains retail-variant or user-owned state.
- The runtime catalog is read-only.
- Existing Product Library and Shopping models have no catalog reference in WT-022A.
- Existing custom products remain usable without a catalog match.
- No existing user record is read, written, migrated, linked, or deleted by catalog loading.
- Incompatible or invalid catalog data fails atomically and never produces a partial repository snapshot.
