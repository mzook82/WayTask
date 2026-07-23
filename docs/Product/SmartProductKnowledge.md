# WT-020 Smart Product Knowledge Blueprint

**Version:** 1.1<br>
**Status:** Planning complete  
**Sprint:** WT-020  
**Theme:** Smart Product Creation  
**Last updated:** 2026-07-23

---

## 1. Outcome

WT-020 defines a search-first, offline-first Product Knowledge architecture without implementing production code.

The recommended foundation is:

- One canonical Product Entity used by manual entry, Product Library, Shopping, barcode, camera, voice, AI, and future community features.
- Separate user-library and shopping state referencing the Product Entity.
- A controlled category/subcategory taxonomy.
- Semantic cross-platform icons.
- A local indexed suggestion engine.
- Provider observations and user-reviewed drafts rather than provider-specific product records.
- A staged, reversible migration from the current Product/ShoppingItem/ProductKnowledge models.

---

## 2. Deliverables

1. [Product Audit](../Audits/2026-07-23_WT-020_ProductAudit.md)
2. [UX Specification](../Specifications/SmartProductCreation.md)
3. [Architecture Proposal](../Architecture/ProductKnowledgeArchitecture.md)
4. [Product Entity Data Model](../Architecture/ProductEntityDataModel.md)
5. [Suggested Folder Structure](../Implementation/SmartProductKnowledge_Implementation.md)
6. [Migration Strategy](../Architecture/ProductKnowledgeMigrationStrategy.md)
7. [Risk Analysis](../Audits/2026-07-23_WT-020_RiskAnalysis.md)

---

## 3. Key Audit Finding

WayTask already has useful product foundations:

- Persistent Product Library.
- Shopping-list entries referencing products.
- Local Product Knowledge cache.
- Product usage history.
- Provider-neutral recognition candidates.
- Local barcode cache before network lookup.

The gap is not the complete absence of product entities. The gap is that no single canonical identity is shared across Product, ShoppingItem, ProductKnowledge, ProductHistory, and ProductCandidate, and the knowledge cache is not an indexed autocomplete catalog.

---

## 4. Product Vision

```text
User types “Mil”
  -> local suggestions appear
  -> user selects “Milk”
  -> WayTask resolves Product ID, Dairy category, and semantic category icon
  -> user saves
  -> Product Library references the canonical entity
```

Unknown products:

```text
No suitable match
  -> Create “<query>”
  -> deterministic local classification when safe
  -> user review
  -> local Product Entity + library reference + search index update
```

No network or AI provider is required.

---

## 5. Architecture Checklist

| Question | Decision |
|---|---|
| 500 products? | Yes. |
| 50,000 products? | Yes, with indexed database-side search, bounded results, and lazy media. |
| iOS and Android conceptual parity? | Yes; shared IDs, schemas, taxonomy, normalization, and fixtures with native adapters. |
| Barcode, images, nutrition, stores, AI metadata later? | Yes; identifier, media, typed extension, and metadata/contribution tables. |
| Same Product Entity for every feature? | Yes; every adapter resolves to `ProductEntity.id`. |
| Offline first? | Yes; catalog, taxonomy, search, resolution, and save are local. |
| Modular and testable? | Yes; repository, search index, normalizer, ranker, resolver, and adapters are separate. |

---

## 6. Phase 1 Boundaries

WT-020 Phase 1 does not include:

- Gemini implementation or improvement.
- Barcode scanning changes.
- Camera recognition improvements.
- Cloud synchronization.
- Community data.
- Machine learning.
- Production schema/UI implementation.

Existing integrations are documented only so the architecture can accept them through stable adapters.

### 6.1 WT-022A Product Identity Decision

For the WT-022A Product Knowledge Foundation, `ProductEntity` represents one generic **Product Concept** only.

The Phase 1 meanings are:

| Term | Phase 1 meaning |
|---|---|
| Product Concept | A reusable generic shopping need such as Milk, Bread, or Shampoo. This is the only thing represented by catalog `ProductEntity`. |
| Sellable Variant | A brand/package-specific retail item such as Tnuva Milk 3% 1 L. Variants, sizes, prices, and barcodes are not modeled in WT-022A. |
| Brand | A retail qualifier, not a product identity. Brand modeling is deferred. Existing free-text brand values remain untouched. |
| Custom User Product | A user-owned product created by the existing manual flow when no catalog concept is used, such as Protein Vanilla Pudding. It remains valid and is not converted into catalog data. |
| Shopping item | User-owned shopping state. The current app uses `ShoppingListEntry` plus a legacy compatibility `ShoppingItem`; both remain unchanged in WT-022A. |
| Alias | An alternate localized search expression for one Product Concept. It is metadata attached to that concept, never a separate Product Entity. |

WT-022A therefore:

- Loads a read-only catalog of Product Concepts.
- Does not add concept/variant discriminator fields.
- Does not model sellable variants, brands, package sizes, prices, or barcodes.
- Does not add a catalog reference to `Product`, `ShoppingListEntry`, or `ShoppingItem`.
- Does not migrate, backfill, link, or dual-write any existing user data.
- Does not connect the catalog to product creation; that integration is deferred to Search and Autocomplete work.
- Leaves current custom/manual product creation fully usable and unchanged.

When a later integration allows selection of a Product Concept, user-owned state must keep both the stable catalog Product ID and a display-name snapshot. The snapshot preserves what the user saw if the catalog is unavailable, renamed, or deactivated. No snapshot field or catalog link is added in WT-022A.

---

## 7. Official Phase 1 Product Taxonomy

The [Product Taxonomy](ProductTaxonomy.md) is the authoritative Phase 1 classification contract for Smart Product Knowledge. It defines 15 stable top-level category identifiers, one primary category per Product Concept, Hebrew and English display names, semantic category icons, deterministic boundary rules, and the assignment workflow.

Phase 1 classifies Product Concepts rather than retail variants. No canonical subcategories are published in taxonomy version 1.0; the optional subcategory level remains reserved for evidence-based future expansion.

---

## 8. Pilot Product Catalog

The [Pilot Product Catalog](PilotProductCatalog.md) validates the approved taxonomy with 15 generic Product Concepts selected for common Israeli shopping behavior and meaningful boundary coverage. The pilot spans 11 canonical categories and validates stable Product IDs, Hebrew and English names, localized aliases, deterministic category assignments, category-level semantic icon fallback, and search-ready name data.

`PilotProductCatalog.md` remains the human-readable review record; the application never parses it. WT-022A.1 approves manual promotion of its exact 15 reviewed Product Concepts into the runtime resource `product-knowledge-catalog-v1.json`.

The runtime JSON is authoritative for the app. The Markdown catalog and taxonomy remain authoritative for human review and meaning. A change is not shippable unless the JSON, the affected Markdown, and automated validation agree.

The first runtime revision:

- Uses schema version `1`.
- Contains exactly 15 products.
- Promotes `prd_pilot_0001` through `prd_pilot_0015` unchanged; these IDs become permanent when first shipped.
- Contains all 15 taxonomy categories, while products cover the documented 11 categories.
- Contains only category semantic icon keys; no product-specific override exists.
- Is manually authored and reviewed because 15 products do not justify a Catalog Generator.

The Catalog Generator is deferred. A manually created, validated pilot JSON resource is approved for WT-022A implementation.

---

## 9. Resolved Foundation Decisions

WT-022A.1 resolves the implementation blockers as follows:

1. `ProductEntity` is a read-only catalog Product Concept in WT-022A.
2. Sellable variants and brands are deferred.
3. Existing Product Library and Shopping persistence remain authoritative and unchanged.
4. Runtime catalog promotion uses one manually authored, validated JSON file.
5. Stable pilot IDs are retained and become immutable after release.
6. Search, normalization, indexed persistence, catalog integration, and migration remain separate future approval gates.
