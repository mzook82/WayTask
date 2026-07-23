# WT-021C — Pilot Product Catalog

**Document:** `docs/Product/PilotProductCatalog.md`<br>
**Version:** 1.1<br>
**Status:** Pilot validated; approved for WT-022A runtime promotion; expansion requires review approval<br>
**Sprint:** WT-021C<br>
**Scope:** Taxonomy validation and governance record for the first runtime catalog<br>
**Last updated:** 2026-07-23

Related documentation:

- [Smart Product Knowledge Blueprint](SmartProductKnowledge.md)
- [Product Taxonomy](ProductTaxonomy.md)
- [Product Knowledge Architecture](../Architecture/ProductKnowledgeArchitecture.md)
- [Product Entity Data Model](../Architecture/ProductEntityDataModel.md)
- [Smart Product Creation UX Specification](../Specifications/SmartProductCreation.md)

---

## 1. Executive Summary

This document defines a 15-product pilot fixture for validating the approved WayTask Phase 1 Product Taxonomy. It remains a human-readable review and governance record rather than an application resource.

WT-022A.1 is the separate implementation decision required by version 1.0 of this document. It approves exact manual conversion of these 15 reviewed Product Concepts into `product-knowledge-catalog-v1.json`, subject to the validation and review rules in Section 12. The application reads the JSON resource, never this Markdown file.

The pilot prioritizes common Israeli supermarket and household purchases. It deliberately combines straightforward staples with boundary-sensitive products so the review tests:

- Stable, language-independent Product IDs.
- Exactly one canonical category per Product Concept.
- English and Hebrew localization.
- Hebrew and English aliases.
- Semantic category-icon inheritance.
- Search-ready names and aliases.
- Deterministic category boundary rules.

The 15 Product Concepts exercise 11 of the 15 canonical categories. The remaining categories are recorded as explicit coverage gaps for the proposed 30-product expansion.

---

## 2. Scope and Catalog Conventions

### 2.1 Pilot scope

Every row represents a generic `ProductEntity`, not a brand, package size, barcode, store listing, or sellable retail variant.

Examples:

| Included Product Concept | Excluded retail detail |
|---|---|
| Milk | Tnuva Milk 3% 1 L |
| Water | Neviot Water 1.5 L |
| Coffee | Elite Instant Coffee 200 g |
| Dog Food | A brand-specific dog-food bag and barcode |

All pilot products:

- Are generic Product Concepts and require no entity-kind discriminator in catalog schema version 1.
- Have `status = active`.
- Represent curated pilot content.
- Reference one top-level `primaryCategoryID`.
- Have no subcategory field because taxonomy version 1.0 publishes no canonical subcategories.
- Use the approved category icon as their resolved semantic icon.

### 2.2 Product ID convention

Pilot Product IDs use:

```text
prd_pilot_NNNN
```

This convention is:

- Stable within the pilot and the first runtime catalog.
- Unique.
- Language-independent.
- Unrelated to a mutable product name or category.
- Visibly identifies the promoted pilot cohort.

WT-022A.1 promotes `prd_pilot_0001` through `prd_pilot_0015` unchanged. Once any ID ships in a runtime catalog, it is permanent: it must never be renamed, repurposed, recycled, or assigned to another concept. New post-pilot concepts use a new governed ID and do not renumber this cohort.

### 2.3 Name and alias convention

- Hebrew and English display names are equivalent localized names for the same Product Concept.
- An alias is an alternate expression for the same concept, not a subtype or related product.
- Canonical names are not repeated as aliases.
- `—` means no additional alias is approved for that locale in this pilot.
- Aliases shown in one table cell represent separate conceptual `ProductName` records, not a delimiter-encoded production field.
- Misspellings are included only when they represent a common orthographic form, not an accidental typo.

---

## 3. Product Selection Strategy

The pilot favors products commonly purchased in Israel while maximizing useful validation within the 15-product limit.

Selection priorities:

1. Everyday food staples.
2. Common household and personal-care purchases.
3. Native Hebrew search behavior.
4. Products with useful English alternate names.
5. Taxonomy boundaries that could otherwise be assigned inconsistently.

The selected set intentionally tests:

- Eggs under `dairy`.
- Coffee under `drinks`.
- Frozen vegetables under `frozen` rather than `fruits_vegetables`.
- Baby wipes under `baby` rather than `personal_care` or `cleaning`.
- Dish soap under `cleaning` rather than `personal_care`.
- Paper towels under `household` rather than `cleaning`.
- Dog Food under `pets` through audience precedence.

---

## 4. Pilot Product Catalog

| Product ID | Hebrew display name (`he`) | English display name (`en`) | Category ID | Semantic icon key | Hebrew aliases | English aliases | Assignment reason |
|---|---|---|---|---|---|---|---|
| `prd_pilot_0001` | חלב | Milk | `dairy` | `product.dairy` | חלב פרה | Cow's Milk | General dairy staple; the canonical concept is dairy milk rather than a retail variant. |
| `prd_pilot_0002` | לחם | Bread | `bakery` | `product.bread` | כיכר לחם | Loaf of Bread | Prepared bread-led bakery product, not a baking ingredient. |
| `prd_pilot_0003` | ביצים | Eggs | `dairy` | `product.dairy` | ביצי תרנגולת | Chicken Eggs | The approved taxonomy explicitly assigns Eggs to `dairy` as a conventional dairy-led grocery staple. |
| `prd_pilot_0004` | אורז | Rice | `pantry` | `product.pantry` | — | — | Shelf-stable dry meal component and pantry staple. |
| `prd_pilot_0005` | תפוח | Apple | `fruits_vegetables` | `product.fruit` | תפוח עץ | — | Fresh fruit sold as produce. |
| `prd_pilot_0006` | עגבנייה | Tomato | `fruits_vegetables` | `product.fruit` | עגבניה | — | Fresh vegetable/produce concept; the Hebrew alias captures a common spelling variant. |
| `prd_pilot_0007` | מים | Water | `drinks` | `product.drink` | מי שתייה | Drinking Water | Ready-to-drink non-dairy beverage. |
| `prd_pilot_0008` | קפה | Coffee | `drinks` | `product.drink` | — | — | Product whose primary purpose is preparing or consuming a beverage. |
| `prd_pilot_0009` | שמפו | Shampoo | `personal_care` | `product.personalcare` | שמפו לשיער | Hair Shampoo | Routine general-human hair hygiene, not a therapeutic treatment. |
| `prd_pilot_0010` | משחת שיניים | Toothpaste | `personal_care` | `product.personalcare` | משחה לשיניים | Tooth Paste | Routine oral-care product, not medicine or medical support. |
| `prd_pilot_0011` | מזון לכלבים | Dog Food | `pets` | `product.pet` | אוכל לכלבים | Canine Food | Animal-specific purpose has precedence over the product's food form. |
| `prd_pilot_0012` | מגבונים לתינוקות | Baby Wipes | `baby` | `product.baby` | מגבונים לתינוק<br>מגבוני תינוקות | Infant Wipes | Baby-specific, non-therapeutic care has precedence over general personal-care and cleaning uses. |
| `prd_pilot_0013` | נוזל כלים | Dish Soap | `cleaning` | `product.cleaning` | סבון כלים<br>נוזל לשטיפת כלים | Dishwashing Liquid<br>Washing-Up Liquid | Primary purpose is dish cleaning, not hand or body hygiene. |
| `prd_pilot_0014` | מגבות נייר | Paper Towels | `household` | `product.household` | נייר סופג | Kitchen Paper | General household paper good rather than a dedicated cleaning chemical or tool. |
| `prd_pilot_0015` | ירקות קפואים | Frozen Vegetables | `frozen` | `product.frozen` | ירקות מוקפאים | Frozen Veg | Frozen state is fundamental at purchase and overrides the fresh-produce category. |

---

## 5. Taxonomy Coverage

### 5.1 Covered categories

| Category ID | Pilot products | Count | Validation value |
|---|---|---:|---|
| `dairy` | Milk, Eggs | 2 | Tests a standard staple and the explicit Eggs boundary. |
| `bakery` | Bread | 1 | Distinguishes prepared bakery goods from pantry ingredients. |
| `fruits_vegetables` | Apple, Tomato | 2 | Validates fresh produce and Hebrew spelling behavior. |
| `pantry` | Rice | 1 | Validates a shelf-stable dry staple. |
| `drinks` | Water, Coffee | 2 | Validates ready-to-drink and beverage-preparation concepts. |
| `frozen` | Frozen Vegetables | 1 | Validates frozen-state precedence over ingredient category. |
| `household` | Paper Towels | 1 | Tests the Household/Cleaning boundary. |
| `cleaning` | Dish Soap | 1 | Tests purpose-based separation from Personal Care. |
| `personal_care` | Shampoo, Toothpaste | 2 | Validates routine hygiene versus therapeutic intent. |
| `baby` | Baby Wipes | 1 | Validates baby-specific audience precedence. |
| `pets` | Dog Food | 1 | Validates animal-specific audience precedence. |
| **Total** | **15 Product Concepts** | **15** | **11 of 15 canonical categories covered.** |

### 5.2 Categories not covered

The pilot does not contain curated products from:

- `meat_fish`.
- `snacks`.
- `pharmacy`.
- `uncategorized`.

The first three are required targets for the proposed 30-product expansion. `uncategorized` should be tested as an unknown-product workflow fixture, not populated with a knowingly classifiable curated Product Concept.

---

## 6. Boundary Validation

| Boundary | Pilot evidence | Result |
|---|---|---|
| Dairy versus conventional grocery grouping | Eggs resolve to `dairy` under the explicit normative assignment. | Deterministic, with a UX-label watch item. |
| Fresh versus frozen food | Apple and Tomato resolve to `fruits_vegetables`; Frozen Vegetables resolve to `frozen`. | Clear under frozen-state precedence. |
| Beverage versus pantry | Coffee resolves to `drinks` because its primary purpose is beverage preparation. | Clear for the generic concept. |
| Personal Care versus Pharmacy | Shampoo and Toothpaste are routine hygiene products and remain `personal_care`. | Clear; a therapeutic product is still needed in expansion. |
| Baby versus Personal Care/Cleaning | Baby Wipes resolve to `baby`. | Clear under baby-specific precedence. |
| Cleaning versus Personal Care | Dish Soap resolves to `cleaning`, unlike hand or body soap. | Clear under primary-use rules. |
| Household versus Cleaning | Paper Towels resolve to `household` as a general paper good. | Clear under the approved normative assignment. |
| Pets versus food categories | Dog Food resolves to `pets`. | Clear under animal-specific precedence. |

No pilot product requires multiple primary categories. No product uses `uncategorized` to avoid a documented boundary decision.

---

## 7. Localization and Alias Validation

### 7.1 Localization

The pilot uses:

- `he` for Hebrew display names.
- `en` for English display names.
- Stable Product IDs and category IDs that do not change by locale.
- Hebrew names as first-class native-script content, not transliterations.

Hebrew and English names describe the same generic concept in every row. Brand, package size, preparation variant, and store-specific language are excluded.

### 7.2 Alias quality

The aliases validate several safe patterns:

| Alias pattern | Example |
|---|---|
| Common equivalent phrase | `נייר סופג` → Paper Towels |
| Alternate regional English term | `Washing-Up Liquid` → Dish Soap |
| Common Hebrew orthographic form | `עגבניה` → Tomato |
| Equivalent audience phrase | `אוכל לכלבים` → Dog Food |
| Spacing variant | `Tooth Paste` → Toothpaste |

The pilot intentionally does not use narrower subtypes as aliases. For example:

- White Rice is not an alias for Rice.
- Whole Wheat Bread is not an alias for Bread.
- Instant Coffee is not an alias for Coffee.
- Mixed Frozen Vegetables is not an alias for Frozen Vegetables.

Those terms may become separate Product Concepts or retail variants after the concept-granularity policy is reviewed.

---

## 8. Semantic Icon Validation

Every icon key is copied from the canonical mapping in `ProductTaxonomy.md`.

Resolution used by this pilot:

```text
No approved Product Concept override
  -> no canonical subcategory in taxonomy v1.0
  -> primary-category semantic icon
```

Results:

- All 15 products resolve to an icon offline.
- All icon keys are platform-independent.
- No emoji, SF Symbol name, Android resource name, or file path is stored.
- Products in the same category intentionally share the category icon.

This validates category-level fallback, not product-specific icon differentiation. The pilot does not invent Product Concept icon keys because no approved product-icon registry exists yet.

---

## 9. Search Readiness

The pilot supplies canonical names and aliases suitable for the local search projection. It does not define ranking weights or implement search.

Representative expected matches:

| Query | Expected Product ID | Match source |
|---|---|---|
| `mil` | `prd_pilot_0001` | English canonical-name prefix |
| `חלב` | `prd_pilot_0001` | Hebrew localized display name |
| `ביצי` | `prd_pilot_0003` | Hebrew alias prefix |
| `עגבניה` | `prd_pilot_0006` | Hebrew orthographic alias |
| `dishw` | `prd_pilot_0013` | English alias prefix |
| `נייר ס` | `prd_pilot_0014` | Hebrew alias prefix |
| `אוכל ל` | `prd_pilot_0011` | Hebrew alias prefix |
| `ירקות ק` | `prd_pilot_0015` | Hebrew display-name prefix |

Search integration must continue to:

- Apply the versioned normalization rules.
- Keep each alias as a separate localized name record.
- Rank canonical names above weaker metadata.
- Treat transliteration as an alias when later approved.
- Avoid adding a single user typo as a curated alias.

---

## 10. Validation Results

### 10.1 Product identity

- [x] Exactly 15 Product IDs exist.
- [x] Every Product ID is unique.
- [x] Every Product ID is stable and language-independent.
- [x] No Product ID is derived from a mutable product name.
- [x] Every row represents a generic Product Concept.

### 10.2 Taxonomy

- [x] Every product has exactly one primary category.
- [x] Every referenced category exists in the approved taxonomy.
- [x] No local category or subcategory was invented.
- [x] Every assignment follows the approved precedence and boundary rules.
- [x] Every assignment reason is documented.

### 10.3 Localization and aliases

- [x] Every product has Hebrew and English display names.
- [x] Hebrew and English names represent the same concept.
- [x] Every alias is localized by language.
- [x] Alias fields explicitly record when no additional alias is approved.
- [x] Subtypes and retail variants are not collapsed into aliases.

### 10.4 Icons

- [x] Every product has a valid taxonomy semantic icon key.
- [x] Icon keys are platform-independent.
- [x] The category-icon fallback resolves for every pilot product.
- [x] No platform asset name or emoji is stored as the icon key.

### 10.5 Documentation

- [x] Required fields are present for every product.
- [x] Markdown tables use consistent columns.
- [x] Local document references resolve.
- [x] No production artifact is defined by this document.

---

## 11. Taxonomy Ambiguities and Findings

### 11.1 Eggs under Dairy

The assignment is unambiguous because the taxonomy explicitly places Eggs in `dairy`. The user-facing label “Dairy & Alternatives,” however, does not naturally communicate Eggs in either English or Hebrew.

This is a discoverability and category-label risk, not an assignment failure. The 30-product review should test whether users understand Eggs under the current label before changing the category set.

### 11.2 Category icons are not product-specific

Milk and Eggs both resolve to `product.dairy`; Shampoo and Toothpaste both resolve to `product.personalcare`. This is consistent with the approved inheritance model but offers limited visual differentiation.

Before a production catalog promises distinct product icons, WayTask should approve a governed Product Concept icon-override registry. This pilot must not invent that registry or its keys.

### 11.3 Generic concept granularity

Bread, Coffee, Water, and Rice each have common forms that could become narrower Product Concepts or retail variants. The current pilot remains intentionally generic and does not resolve the complete concept-versus-variant policy.

Expansion should test:

- Generic versus preparation-specific concepts.
- Direct substitutes such as Oat Milk.
- Ready-to-consume versus ingredient forms.
- Fresh/chilled versus frozen forms.

### 11.4 Alias boundaries require curation

Aliases can improve search but can also collapse distinct concepts. The pilot demonstrates that equivalent phrases are safe while subtypes are not. Production curation will need an explicit alias review rule and multilingual fixtures.

None of these findings requires a taxonomy ID change for the pilot.

---

## 12. Runtime Promotion and Governance

### 12.1 Source-of-truth responsibilities

- `product-knowledge-catalog-v1.json` is the exact authoritative dataset read by the app.
- This document is the authoritative human-readable review record for the promoted pilot concepts, names, aliases, and assignment reasons.
- `ProductTaxonomy.md` remains authoritative for category meaning, IDs, localized category names, and category icon keys.
- A mismatch blocks shipping; runtime JSON must not silently override a conflicting reviewed document, and the app must never parse Markdown.
- The Product owner owns catalog content; iOS Engineering owns schema conformance and resource packaging.
- Revision 1 targets common Israeli shopping behavior and supports `en` and `he`.
- Revision 1 is WayTask-authored curated content from WT-021C; it imports no third-party catalog and therefore carries no external catalog license or attribution requirement.
- A future external data source requires explicit license/attribution review before any content is copied into the runtime catalog.

The exact JSON contract is defined once in `ProductEntityDataModel.md` and consumed by the WT-022A plan. This document does not define a second schema.

### 12.2 Initial conversion

An engineer may manually create the first runtime JSON by transcribing the 15 catalog rows and the 15 approved taxonomy categories. The conversion must:

1. Preserve every Product ID exactly.
2. Create separate `ProductName` rows for each English/Hebrew preferred name and each approved alias.
3. Preserve each `primaryCategoryID`.
4. Copy category icon keys only from `ProductTaxonomy.md`.
5. Set all 15 products to `active`.
6. Set `schemaVersion` to `1`, `catalogRevision` to `1`, and `expectedProductCount` to `15`.
7. Pass structural, referential, and exact-content validation before shipping.
8. Receive one explicit Product/Architecture review confirming the JSON matches this document.
9. Remain at or below 100 KiB uncompressed for runtime revision 1.

### 12.3 Small-team change process

Any team member may propose a catalog change in one review:

- The Product owner reviews concept identity, localized names, aliases, and category meaning.
- The implementing engineer reviews schema conformance, stable IDs, and automated validation.
- One person may hold both roles on a small team, but the review checklist and automated validation must still be recorded.
- A schema-shape change also requires an Engineering review and a schema-version decision.

No separate committee, release service, or Catalog Generator is required.

### 12.4 Content rules

- **Stable IDs:** A released Product ID never changes or gets reused. Renames, alias edits, and category corrections keep the same Product ID.
- **Category changes:** A category correction requires an explicit Product review against `ProductTaxonomy.md`, an updated assignment reason here, and a `catalogRevision` increment.
- **Alias changes:** An alias must be an equivalent expression, not a subtype, brand, package, or related product. The Product reviewer must approve additions/removals; automated validation must reject duplicates and canonical-name repetition.
- **Icon keys:** Catalog v1 has no product icon override. Each product derives its icon from `primaryCategoryID`; category icon changes must update `ProductTaxonomy.md` and runtime JSON together.
- **Deactivation:** A released product is changed to `inactive`, not deleted. Its ID and names remain reserved, and the ID is never reused.
- **Deletion:** Deletion is allowed only before the product appears in a shipped catalog. Released rows are retained as inactive.
- **Schema versions:** `schemaVersion` changes only when the JSON shape or field meaning becomes incompatible. Content additions/corrections increment `catalogRevision` without changing schema version.
- **Documentation sync:** Every content change updates runtime JSON and this document in the same review. A taxonomy change also updates `ProductTaxonomy.md`.
- **Resource integrity:** Catalog v1 uses one JSON resource with no separate manifest or detached signature. Automated validation checks the exact source and packaged resource; the signed iOS app bundle provides distribution authenticity.

### 12.5 Generator decision

**Generator deferred; validated manual pilot JSON is approved for WT-022A.**

The initial catalog has only 15 reviewed products and a fixed taxonomy. A generator would add build tooling and another transformation boundary without reducing current risk. Manual conversion plus exact-content tests, schema validation, and review is sufficient. Reconsider a generator only when catalog size or update frequency makes manual synchronization demonstrably error-prone.

---

## 13. Expansion Gate

This pilot must not be expanded automatically.

Expansion to approximately 30 Product Concepts requires Product and Architecture review of:

1. The 15 assignments in this document.
2. The Eggs category-label watch item.
3. Category-icon fallback versus Product Concept overrides.
4. Generic concept and retail-variant boundaries.
5. Alias equivalence rules.

If approved, the next 15 products should prioritize:

- `meat_fish`, `snacks`, and `pharmacy`.
- A direct milk or meat alternative.
- A therapeutic Personal Care/Pharmacy boundary.
- A Pantry/Snacks consumption-form boundary.
- Additional Hebrew spelling and English synonym cases.
- A separate unknown-product fixture that safely resolves to `uncategorized`.

Expansion remains documentation and data-design work until a separate implementation task authorizes a production catalog artifact.

---

## 14. Final Recommendation

**APPROVED FOR EXPANSION**

The pilot demonstrates that the approved taxonomy can classify 15 common Israeli shopping Product Concepts with stable identities, one primary category, bilingual names, safe aliases, and valid semantic icons.

The recorded ambiguities are non-blocking for the pilot. The exact 15 reviewed concepts are approved for WT-022A runtime promotion under Section 12. Expansion to 30 products should occur only after the review gate in Section 13 is accepted and should target the uncovered categories and boundary cases rather than catalog breadth.
