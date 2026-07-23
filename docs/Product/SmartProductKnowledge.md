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

## 7. Recommended Next Decision

Before implementation planning, Product and Engineering should approve:

1. Canonical Product Entity versus user/shopping state separation.
2. Generic-product and sellable-variant behavior.
3. Taxonomy revision 1 and semantic icon contract.
4. Search normalization and supported-language fixtures.
5. iOS local search persistence spike.
6. Migration release gates and rollback window.
