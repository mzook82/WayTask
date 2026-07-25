# WT-020 Smart Product Knowledge Blueprint

**Version:** 1.0  
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

1. [Canonical Product Catalog Specification](../Specifications/CanonicalProductCatalogSpecification.md)
2. [Product Audit](../Audits/2026-07-23_WT-020_ProductAudit.md)
3. [UX Specification](../Specifications/SmartProductCreation.md)
4. [Architecture Proposal](../Architecture/ProductKnowledgeArchitecture.md)
5. [Product Entity Data Model](../Architecture/ProductEntityDataModel.md)
6. [Suggested Folder Structure](../Implementation/SmartProductKnowledge_Implementation.md)
7. [Migration Strategy](../Architecture/ProductKnowledgeMigrationStrategy.md)
8. [Risk Analysis](../Audits/2026-07-23_WT-020_RiskAnalysis.md)

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
  -> WayTask resolves Product ID, Dairy category, Milk subcategory, and milk icon
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

---

## 7. WT-026A Shared Contract and WT-026B Migration

The approved canonical model is now represented by platform-neutral resources in
`shared/catalog/`:

- JSON Schema version 1.
- Taxonomy version 1 with 23 top-level retail categories.
- Explicit compatibility mappings for all 24 production v2 category IDs.
- Hebrew normalization fixtures.
- Canonical resolution acceptance fixtures.

iOS supports the retired schema-less v2 resource and canonical schema version 1.
Both decode to one `CatalogProduct` model; the search, ranking, personalization, UI,
and catalog-aware persistence paths remain source-format independent. The bundled
production catalog now uses schema version 1, catalog version 3, and taxonomy version
1.

WT-026B reviewed all 147 products and assigned canonical category/subcategory IDs.
The 48 products belonging to the eight broad `product_review_required` legacy
groups were reviewed individually, and none remains unresolved. The non-runtime
audit is `shared/catalog/product-taxonomy-review.json`.

Every stable product ID, popularity score, and active state was preserved. Search
equivalence fixtures cover representative canonical-name, alias, brand-term, and
custom queries. Catalog-aware persistence and personalization continue to aggregate
by the same product IDs; the legacy decoder remains covered for backward
compatibility.

The future Android repository should vendor the same released `shared/catalog/`
artifact, validate its checksum, and execute the same normalization and acceptance
fixtures through native Kotlin loaders and search code.

## 8. WT-027A Controlled Coverage Expansion

WT-027A expands the canonical Hebrew resource from 147 to 467 active products while
preserving every original product object and stable ID. The resource remains schema
version 1 and taxonomy version 1; 320 individually committed toolkit additions and
10 follow-up alias/keyword/brand review updates move the catalog from version 3 to
333.

Every new product has an explicit category and nullable subcategory review entry.
The append-only `shared/catalog/catalog-authoring-audit.jsonl` contains 330
contiguous transactions: 320 adds and 10 semantic review updates.
`shared/catalog/wave-1-search-fixtures.json` adds shared
Hebrew acceptance coverage for canonical names, aliases, one genuine brand term,
and custom no-match behavior.

Search weights, suggestion limits, personalization, UI, persistence, and saved
identity behavior are unchanged. The original 147 IDs remain the compatibility
baseline and are verified as a subset of the 467 production IDs.

## 9. Exact Next Step

**WT-027B — Canonical Catalog Coverage Review and Wave 2:** measure real missing
queries through `CATALOG_FEEDBACK.md`, fill only evidenced gaps in low-coverage
categories, and extend the shared Swift/Node/Kotlin-ready fixtures. Add a
transactional toolkit batch mode before another large wave if release-level catalog
versioning is preferred over one version per committed product.
