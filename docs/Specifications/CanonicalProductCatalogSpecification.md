# WayTask Canonical Product Catalog Specification

**Version:** 1.0  
**Status:** Approved architecture and product contract  
**Scope:** Long-term shared catalog contract for iOS and Android  
**Default locale:** `he-IL`  
**Last updated:** 2026-07-25

This specification defines WayTask's long-term canonical product catalog. It is
normative for catalog identity, content governance, resolution, persistence,
personalization, taxonomy, cross-platform parity, and migration.

The current implementation remains the baseline:

- `product_catalog_he.json` supplies the shipped Hebrew autocomplete catalog.
- `ProductCatalogService` validates and loads active catalog records.
- `ProductCatalogSearch` normalizes Hebrew text and applies deterministic relevance
  tiers with bounded local personalization.
- ProductKnowledge supplies platform-neutral product, name, category, repository,
  search, and validation concepts.
- SwiftData `Product` is the user-owned library record. A catalog-linked Product
  stores the stable catalog ID and selection-time display snapshots.
- `ShoppingListEntry` continues to reference the user-owned `Product.id`.
- Custom Products remain valid and have no catalog ID.

This document defines the contract to which those pieces will converge. It does not
authorize a catalog expansion, remote catalog, backend, or automatic migration.

Normative terms are used deliberately:

- **Must / must not:** required for conformance.
- **Should / should not:** expected unless an approved exception is recorded.
- **May:** optional behavior that does not change identity semantics.

## 1. Canonical product identity

### 1.1 Canonical entity

A canonical product is one stable catalog entity representing one reusable product
concept. Its identity is its `id`, not its Hebrew name, an alias, a barcode, a brand,
a category, a package, or the user's typed text.

Example:

```text
ID: trash_bags
Canonical name: שקיות אשפה
Aliases: שקיות זבל, שקי אשפה, שקי זבל
```

All accepted aliases resolve to `trash_bags`. Search and UI display the canonical
name `שקיות אשפה`; the alias never creates another catalog identity.

Released IDs:

- Must be unique across active and inactive records.
- Must use lowercase ASCII letters, digits, and underscores.
- Must match `^[a-z][a-z0-9_]*$`.
- Must be stable across renames, category changes, deactivation, and catalog
  replacement.
- Must never be reused for a different concept.
- Need not be renamed if their English wording later becomes imperfect.
- May retain an already released legacy ID even if it does not follow the preferred
  naming style.

### 1.2 Identity layers

| Layer | Identity | Meaning |
| --- | --- | --- |
| Canonical product concept | Stable catalog `id` | Generic, reusable shopping intent such as `trash_bags` or `milk_3_percent` |
| Exact retail SKU | Future stable SKU ID | Brand/package/barcode-specific sellable item linked to one canonical concept |
| User Product | Local UUID | User-owned library record that may reference one canonical ID |
| Shopping entry | Local entry UUID | List state that references the user Product UUID |
| Custom Product | Local UUID, no catalog ID | Exact user-owned text when no confident catalog concept is selected |

A meaningful non-brand variant may be its own canonical concept when the distinction
changes shopping intent. Therefore `milk_1_percent`, `milk_3_percent`, and
`lactose_free_milk` may remain separate concepts. A branded one-litre carton is an
exact SKU beneath one of those concepts, not another generic concept.

### 1.3 Query and identity

The raw query is input evidence only. It may be retained as optional resolution
metadata, but it must not replace the canonical ID or canonical name.

An exact normalized canonical-name match, an exact unique alias, or an exact barcode
mapping is a confident catalog resolution. Once the user explicitly selects any
catalog suggestion, that selection is also a confident resolution even if the
suggestion was discovered through a keyword or brand term.

When a query confidently resolves, the save flow must not create a second custom
Product with the query as its identity. When no confident resolution exists, the
exact trimmed custom text remains available.

## 2. Final product schema

### 2.1 Catalog document

The shared catalog is one versioned document. The target top-level shape is:

```json
{
  "schemaVersion": 1,
  "catalogVersion": 1,
  "taxonomyVersion": 1,
  "locale": "he-IL",
  "products": []
}
```

`schemaVersion` describes JSON structure and field semantics. `catalogVersion`
describes a reviewed content release. `taxonomyVersion` describes the category and
subcategory registry. These counters have separate meanings and must not be
collapsed into one value. `locale` is the locale of `canonicalName`, aliases,
keywords, and brand terms in this document. Taxonomy records live in the separately
versioned shared `taxonomy.json` registry.

### 2.2 Required product record

Every product record must contain exactly these required core fields:

```json
{
  "id": "trash_bags",
  "canonicalName": "שקיות אשפה",
  "categoryId": "household",
  "subcategoryId": "household.waste_bags",
  "aliases": [
    "שקיות זבל",
    "שקי אשפה",
    "שקי זבל"
  ],
  "keywords": [
    "פח",
    "ניקיון",
    "פסולת"
  ],
  "brandTerms": [],
  "popularityScore": 92,
  "isActive": true
}
```

| Field | Type | Required rule |
| --- | --- | --- |
| `id` | String | Stable ASCII identifier; unique forever |
| `canonicalName` | String | Nonempty preferred product name in the catalog `locale` |
| `categoryId` | String | Exactly one active top-level category ID |
| `subcategoryId` | String or `null` | Present on every record; valid child of `categoryId` when non-null |
| `aliases` | Array of strings | True alternate names for this same concept; may be empty |
| `keywords` | Array of strings | Related discovery terms; may be empty |
| `brandTerms` | Array of strings | Approved brand expressions used only for discovery; may be empty |
| `popularityScore` | Integer | Inclusive range `0...100`; global prior, not identity |
| `isActive` | Boolean | Controls discovery without deleting identity |

Array values must be nonempty after trimming, unique after search normalization, and
stored in a deterministic reviewed order.

### 2.3 Display-name decision

A separate required `displayName` field is not part of the model. In the catalog
locale, `canonicalName` is both the authoritative product name and the normal
catalog display name. A second identical field would create avoidable divergence.

Display resolution is:

1. Preferred canonical name for the requested locale, when present.
2. Language-only localization, when present.
3. `canonicalName` in the catalog `locale`.
4. A saved user-owned display-name snapshot when the live catalog is unavailable.

A future genuinely different UI label, such as a reviewed short accessibility or
compact label, must be explicitly named for that use case. It must not be introduced
as a redundant general `displayName`.

### 2.4 Optional future extensions

These extensions are reserved and are not required in the current implementation:

| Future field or record | Placement and meaning |
| --- | --- |
| `localizedNames` | Product-local map keyed by BCP-47 locale, containing canonical name and locale-specific aliases, keywords, and brand terms |
| `aiRecognitionLabels` | Reviewed machine-recognition labels and locale; never a user-visible canonical name by itself |
| `imageReferences` | Stable semantic or media references, not platform file paths |
| `unitMetadata` | Concept-level allowed/default quantity units such as item, kilogram, or litre |
| `packageMetadata` | Normally belongs to an exact SKU; package amount, unit, type, and count |
| `barcodeIdentifiers` | Normally belongs to an exact SKU; scheme, normalized value, market, and verification status |
| `replacementProductId` | Surviving canonical ID for a safe one-to-one retirement or merge |
| `deprecation` | Reason, first deprecated catalog version, review metadata, and optional replacement |
| `skuIds` | References to future exact branded/package SKU records |

The normal barcode model is:

```text
barcode -> exact SKU -> canonicalProductId
```

A barcode may be attached directly to a concept only when it genuinely identifies
the concept rather than one commercial package. Barcode strings, images, and AI
provider payloads must not be used as canonical product IDs.

Future exact SKU records must minimally own:

- Their stable SKU ID.
- `canonicalProductId`.
- Brand identity or reviewed brand label.
- Barcode identifiers.
- Package metadata.
- Optional localized sellable name and image references.
- Active/deprecation state.

## 3. Categories and subcategories

### 3.1 Roles

A top-level category is a durable, broad classification used for:

- Browse and filter experiences.
- Weak search context.
- Recommendation boundaries and substitute discovery.
- Semantic icon fallback.
- Analytics-free local grouping.
- Future mapping to store departments and aisle taxonomies.

A subcategory is a controlled second-level refinement used for:

- More precise search and recommendation context.
- Product-specific semantic icon selection.
- Store-aisle mapping.
- Distinguishing broad category content without multiplying top-level categories.

Categories and subcategories are taxonomy, not aliases. A category match is always a
weaker search signal than a product canonical-name or alias match.

### 3.2 Membership

Each canonical product must have exactly one `categoryId` and zero or one
`subcategoryId`. A product must not belong to multiple canonical categories.
Cross-category discovery belongs in keywords, relationships, recommendations, or
store mappings, not duplicate category membership.

Every subcategory has exactly one parent. A third taxonomy level is prohibited.

### 3.3 Identifiers

Top-level category IDs must match `^[a-z][a-z0-9_]*$`.

Subcategory IDs must be namespaced under their parent and match:

```text
^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$
```

Examples:

- `pantry.pasta_rice`
- `household.paper_products`
- `personal_care.oral_care`
- `electronics.mobile_accessories`

IDs are language-independent, immutable after release, and never reused.

### 3.4 Initial long-term target taxonomy

The long-term taxonomy keeps the approved broad grocery and household IDs and adds a
small number of retail domains. The target contains 23 top-level categories, not
hundreds of aisle-level categories:

| ID | Scope |
| --- | --- |
| `dairy` | Dairy, eggs, and direct dairy alternatives |
| `bakery` | Bread and prepared bakery products |
| `fruits_vegetables` | Fresh produce and herbs |
| `meat_fish` | Fresh/chilled meat, fish, and direct alternatives |
| `pantry` | Shelf-stable food, cooking, canned, breakfast, baking, pasta, rice, and spices |
| `drinks` | Non-dairy beverages and beverage preparation |
| `frozen` | Products whose frozen state is fundamental |
| `snacks` | Snacks, sweets, and confectionery |
| `household` | Paper, storage, disposables, and general household consumables |
| `cleaning` | Cleaning, dishwashing, laundry, and cleaning tools |
| `personal_care` | Hygiene, oral care, grooming, and routine body care |
| `pharmacy` | Medicines, supplements, first aid, and health support |
| `baby` | Non-therapeutic infant feeding, diapering, hygiene, and care |
| `pets` | Pet food, care, hygiene, and animal-specific consumables |
| `apparel` | Clothing, footwear, and wearable accessories |
| `electronics` | Consumer electronics, cables, batteries, and accessories |
| `home_garden` | Home improvement, kitchenware, furniture, garden, and tools |
| `office_school` | Office, stationery, art, and school supplies |
| `automotive` | Vehicle care, accessories, and consumables |
| `sports_outdoors` | Sports, fitness, travel, and outdoor products |
| `toys_games` | Toys, hobbies, puzzles, and games |
| `books_media` | Books and physical media |
| `uncategorized` | Review-only fallback, never a search synonym |

Existing released taxonomy IDs in this table retain their meaning. Current
autocomplete categories that are narrower than the target become subcategories in a
future migration. For example:

- `fruits` and `vegetables` map under `fruits_vegetables`.
- `meat` and `fish` map under `meat_fish`.
- `dairy_alternatives` maps under `dairy`.
- `pasta_rice`, `canned_food`, `breakfast`, `baking`, and `spices` map under
  `pantry`.
- `paper_products`, `disposable_products`, and `household_products` map under
  `household`.
- `pet_supplies` maps under `pets`.

That mapping is a future catalog migration, not a change authorized by this
specification task.

### 3.5 Taxonomy records and evolution

Category records own a stable ID, canonical name, localized names, optional
description, and subcategories. Subcategory records additionally own
`parentCategoryId`.

Platform visual assets, icon keys, and resource names remain outside the shared
taxonomy. iOS and Android map stable category IDs to their own visual assets.

New categories and subcategories require:

1. A taxonomy-version increment.
2. A stable new ID and documented boundary.
3. Localized names and any platform-specific icon mappings maintained by each app.
4. Mapping and acceptance fixtures for both platforms.
5. Validation that no old ID changed meaning.

Retired taxonomy IDs remain reserved. Products are migrated by content update; saved
user snapshots remain readable.

Store matching must use a separate mapping from canonical category/subcategory IDs to
store-specific departments or aisles. A retailer's taxonomy must not redefine the
WayTask canonical taxonomy.

## 4. Alias rules

An alias is a genuine alternate name for the same canonical product concept. Replacing
the canonical name with the alias in a shopper's request must preserve the intended
thing.

Approved examples:

- `שקיות זבל`, `שקי אשפה`, and `שקי זבל` are aliases of `שקיות אשפה`.
- `נייר שירותים` is an alias of `נייר טואלט`.
- `נס קפה` is a common Israeli alias of `קפה נמס`.
- `חלב שיבולת שועל` is an alias of `משקה שיבולת שועל`.

Alias rules:

- Synonyms are aliases when they are interchangeable in the catalog locale.
- Singular and plural forms may be aliases when number does not change identity.
- Common spelling and orthographic variants may be aliases.
- Common Israeli terminology and established slang may be aliases.
- Borrowed words and transliterations may be aliases when shoppers use them for the
  same concept.
- Punctuation, quotes, case, whitespace, and Hebrew final-letter differences handled
  entirely by normalization should not be duplicated as aliases.
- A broad family term must not alias a narrower product.
- A use, aisle, ingredient, or related object is a keyword, not an alias.
- A package size, flavour, dietary property, concentration, material, or functional
  variant is an alias only when it does not change shopper intent.
- An alias must resolve to exactly one active canonical product after normalization.

A brand is not normally an alias. A brand expression may become an alias only when
catalog governance has verified that, in the locale, it is an established generic
name for exactly one concept and no branded-SKU ambiguity remains. `נס קפה` is
accepted as a lexicalized Israeli term for instant coffee. `נוטלה` remains a brand
term or exact SKU, not an alias for every hazelnut spread.

## 5. Keyword rules

A keyword is a related discovery term, not another name for the product.

Example:

```text
Canonical product: נייר אפייה
Alias: נייר פרגמנט
Keywords: אפייה, תנור, תבנית
```

Keywords may describe:

- Primary use.
- Aisle or task context.
- A meaningful ingredient or compatible activity.
- A constrained household or retail context.

Keywords must not:

- Repeat canonical names or aliases.
- Be treated as proof of canonical identity.
- Be so broad that unrelated products appear for short queries.
- Include every category name on every product.
- Include speculative typo noise.
- Promote a related but different product as if it were equivalent.

Keyword matching is eligible only for a sufficiently specific query. The default
shared acceptance rule is at least four normalized non-space characters or a
meaningful multi-token query. Platforms may optimize their index differently, but
must satisfy the same acceptance fixtures.

Keyword and category matches must never outrank canonical-name prefix matches.
Returning fewer suggestions is preferable to filling the limit with weak keyword or
category matches.

## 6. Brand handling

### 6.1 Two-layer model

WayTask uses two distinct layers:

1. **Generic canonical product type:** the reusable need, such as `קפה נמס`,
   `משחת שיניים`, or `קולה`.
2. **Exact branded product/SKU:** a future sellable item, such as `נסקפה טייסטרס
   צ'ויס 200 גרם`, `קולגייט טוטאל 75 מ"ל`, or `קוקה קולה זירו 1.5 ליטר`.

The current catalog must not create every brand/package combination as a canonical
concept.

### 6.2 `brandTerms`

`brandTerms` contains reviewed brand expressions only when users genuinely search by
that expression and the generic suggestion remains useful. Brand terms:

- Are search metadata, not canonical identity.
- Rank below canonical names and aliases.
- Must not rename the product.
- Must not imply that every SKU from the brand is the same product.
- May be shared by multiple concepts, in which case the term is not a confident
  automatic resolution.
- Must yield to an exact SKU result when the SKU layer is available.

Examples:

| Query | Current generic behavior | Future SKU behavior |
| --- | --- | --- |
| `נסקפה` | May suggest canonical `קפה נמס` through `brandTerms`; explicit selection required | Prefer matching Nescafé SKU when exact evidence exists |
| `נוטלה` | May suggest `ממרח אגוזי לוז`, clearly labeled generically | Prefer exact Nutella SKU |
| `קוקה קולה זירו` | Must not redefine canonical `קולה` | Resolve exact branded zero-sugar SKU, then link to the appropriate canonical type |

### 6.3 Barcode resolution

A verified barcode resolves an exact SKU. The SKU then supplies
`canonicalProductId`. Saving still stores the canonical ID in user-owned product
state and may additionally retain the SKU ID and package snapshot in a future schema.

Unknown or conflicting barcode evidence creates a reviewable candidate; it must not
silently create or mutate canonical identity.

## 7. Duplicate prevention

Duplicate checks use the same versioned normalization contract as search: Unicode
compatibility normalization, locale-aware case folding, whitespace collapse,
punctuation/quote handling, diacritic removal where approved, and Hebrew final-letter
normalization.

| Condition | Validator decision | Required content action |
| --- | --- | --- |
| Duplicate `id` | Hard error | Keep one identity; never reuse an ID |
| Duplicate normalized active `canonicalName` in one locale | Hard error | Merge, or add a meaningful canonical qualifier if concepts truly differ |
| Alias equals its own canonical name | Hard error | Remove redundant alias |
| Alias equals another active product's canonical name | Hard error | Remove/reassign alias or merge the duplicate concepts |
| Same normalized alias on multiple active products | Hard error | Establish one owner, create a broader canonical concept, or remove the ambiguous alias |
| Singular/plural-only records | Normally merge | Keep one canonical record and move the other form to aliases |
| Spelling-only records | Merge | Keep one canonical spelling and use alias/normalization |
| Punctuation/case-only records | Merge | Let normalization handle the difference |
| Near-identical package/brand records in concept layer | Merge | Move retail detail to future SKU layer |
| Material shopper-intent variant | Keep separate | Use separate stable IDs and explicit canonical names |

`שקיות אשפה` and `שקיות זבל` normally merge. `חלב 1%`, `חלב 3%`, and `חלב ללא
לקטוז` may remain separate because fat percentage and lactose constraint materially
affect selection.

Two variants remain separate only when at least one of these is true:

- Shoppers routinely reject one as a substitute for the other.
- The distinction affects dietary, medical, audience, form, or functional intent.
- Separate favorites/history/recommendations are useful.
- The catalog names contain a stable, meaningful qualifier rather than brand/package
  noise.

If none applies, merge and represent wording differences as aliases.

## 8. Canonical resolution and saving

### 8.1 Resolution confidence

| Evidence | Confidence before user selection | Save rule |
| --- | --- | --- |
| Exact normalized canonical name | Confident when unique | Resolve canonical ID; suppress duplicate custom creation |
| Exact unique alias | Confident | Resolve canonical ID; suppress duplicate custom creation |
| Normalization-only variation | Same as underlying canonical/alias match | Resolve canonical ID |
| Verified barcode to one SKU | Confident | Resolve SKU and canonical ID |
| Canonical prefix/contains | Candidate | User must select result |
| Keyword or category | Candidate only | User must select result |
| Brand term | Candidate only unless exact SKU also resolves | User must select generic result or SKU |
| AI/camera label | Candidate unless resolver policy provides a uniquely reviewed ID | Require review/selection |

An explicit result selection is an identity decision. It converts a displayed
candidate into a confident resolution for that save.

### 8.2 Catalog save

When the user selects or confidently resolves a catalog product through canonical
name, alias, keyword, brand term, normalization, AI, or barcode:

1. Save the stable canonical catalog product ID.
2. Save/display the resolved canonical product name, not the raw alias or keyword.
3. Preserve the selection-time canonical name, locale, category, and icon as
   user-owned snapshots so the item works offline and survives catalog changes.
4. Optionally preserve `rawQuerySnapshot`, match source, SKU ID, or recognition
   provenance when useful and privacy-appropriate.
5. Deduplicate user-library catalog Products by exact canonical ID.
6. Do not create a duplicate custom Product.
7. Keep `ShoppingListEntry.productID` pointing to the user-owned Product UUID.

This matches the existing catalog persistence boundary: the catalog ID is a reference,
while the user Product UUID and snapshots remain durable user data.

### 8.3 Custom save

When no confident match exists:

1. Offer the exact trimmed user text as a custom Product.
2. Save it through the existing manual path.
3. Leave its catalog ID `nil`.
4. Do not invent a canonical ID, category, barcode, or AI confidence.
5. Preserve existing custom Product behavior and user data.

### 8.4 Legacy custom linking

Legacy or custom Products may later be linked safely, but never by an unattended
migration:

1. Produce a candidate using exact unique canonical/alias normalization or other
   reviewed evidence.
2. Show the canonical target and consequences.
3. Require explicit user confirmation unless a separately approved deterministic
   migration policy covers the exact case.
4. Attach the canonical ID to the existing user Product UUID and preserve its current
   name as a snapshot or user override.
5. If another user Product already owns that canonical ID, merge only through a
   transactional workflow that rewrites shopping references, combines history and
   favorite state, and preserves recovery information.
6. Record the migration version; never delete unresolved legacy data.

Name similarity, category similarity, or a shared brand alone is insufficient for
automatic linking.

## 9. Personalization interaction

Personalization aggregates by canonical ID first. Every canonical-name, alias,
keyword, brand-term, camera, or barcode selection that resolves to the same product
strengthens one history record.

For `trash_bags`, selecting any of these:

- `שקיות זבל`
- `שקי אשפה`
- `שקיות אשפה`

increments history for `trash_bags`.

The local personalization profile may include:

- Capped selection-frequency boost.
- Capped recency boost.
- Future favorite boost.
- Optional last-completed or purchase-interval features.

Rules:

- Textual relevance is always primary.
- Personalization may reorder only products in the same textual match tier.
- It must never introduce a product that does not independently match.
- It must never promote keywords, brand terms, or categories above a
  canonical-name prefix.
- An unrelated frequently selected product must not appear.
- Canonical ID history takes precedence over name-derived history.
- Normalized-name fallback is permitted only for legacy/custom records without a
  canonical ID.
- Once a legacy record is linked, its history should be migrated to the canonical ID
  and the name fallback retired.
- Data remains local unless a future separately approved sync feature is introduced.
- No analytics or tracking is implied by personalization.

The current capped frequency/recency implementation is a valid initial realization
of this policy.

## 10. iOS and Android parity

### 10.1 Shared contract

iOS and Android must consume the same:

- JSON schema and field meanings.
- Product, category, subcategory, redirect, and future SKU IDs.
- Catalog, schema, and taxonomy versions.
- Normalization specification.
- Canonical names, aliases, keywords, and brand terms.
- Duplicate and validation rules.
- Acceptance fixtures and expected resolution IDs.

Swift and Kotlin loaders, indexes, and UI presentation remain native. Platform UI
metadata may differ when appropriate:

- SF Symbols/custom iOS assets versus Android drawables.
- Native persistence and indexing implementation.
- Native accessibility and bidirectional-layout details.

Platform differences must not change canonical identity or the semantic meaning of a
field.

### 10.2 Ranking parity

Implementations need not use identical internal score values. They must satisfy the
same visible ordering contract:

1. Exact canonical name.
2. Canonical full-query prefix.
3. Canonical word prefix.
4. Canonical contains.
5. Alias prefix, then alias contains.
6. Brand-term prefix/contains.
7. Keyword prefix/contains.
8. Subcategory/category context.

Popularity and bounded personalization break ties only inside the textual tier.
Weak matches must not be added merely to reach a result limit.

### 10.3 Repository synchronization

While platform code remains in separate repositories, the source of truth must be a
small platform-neutral `waytask-catalog-contract` repository containing:

- Catalog JSON.
- Machine-readable JSON Schema.
- Taxonomy registries.
- Normalization and acceptance fixtures.
- Catalog changelog and release metadata.

Each catalog release receives an immutable Git tag and checksum. iOS and Android
vendor the exact released artifact and record its tag/checksum in their repository.
CI on each platform validates the artifact, runs native loader/search fixtures, and
rejects a version/checksum mismatch.

This strategy requires no backend. A future remote provider may deliver the same
versioned document, but local bundled loading remains a conforming provider.

## 11. Versioning and migration

### 11.1 Version meanings

- `schemaVersion` increments when a reader must understand an incompatible shape or
  changed field semantics.
- `catalogVersion` increments for every released product-content change, including a
  product, canonical name, alias, keyword, brand term, popularity, category
  assignment, active state, or redirect.
- `taxonomyVersion` increments when category/subcategory definitions, boundaries,
  display metadata, or icon semantics change.

Adding a backward-compatible optional field does not require a schema-version
increment until content depends on it. Adding or changing a required field does.

Readers must:

- Declare the schema-version range they support.
- Decode known compatible optional fields and ignore unknown optional extensions.
- Reject unsupported required semantics atomically.
- Keep the last valid bundled or installed catalog on update failure.
- Never expose a partially decoded catalog.

### 11.2 Stable IDs and names

Product IDs survive:

- Canonical-name changes.
- Alias and keyword changes.
- Category/subcategory changes.
- Product deactivation.
- Replacement by a surviving canonical product.

A renamed canonical product keeps its ID. Existing user Products retain their saved
display snapshot; new search results use the current canonical name. History and
favorites continue to aggregate under the stable ID.

### 11.3 Deactivation, merge, and replacement

An obsolete product is retained with `isActive: false`. It is excluded from ordinary
search but remains resolvable for saved data.

For a safe merge:

1. Keep the retired record inactive.
2. Set its `replacementProductId` or add one redirect to the survivor.
3. Ensure the survivor is active.
4. Reject redirect cycles and chains to missing IDs.
5. Resolve future reads to the survivor while retaining the original ID for audit and
   migration.
6. Migrate saved references transactionally and idempotently when that migration is
   implemented.

For a split from one concept to multiple concepts, no automatic single replacement is
allowed. Existing saved data remains on the retired ID until user or deterministic
domain evidence chooses a target.

### 11.4 Implementation migration

The convergence migration requirements were:

1. Preserve every released product ID.
2. Map `name` to `canonicalName`.
3. Add required `subcategoryId` as a reviewed ID or `null`.
4. Add `brandTerms: []` unless evidence approves terms.
5. Move semantic category records into the shared contract.
6. Preserve `catalogVersion` history and introduce independent `schemaVersion` and
   `taxonomyVersion`.
7. Provide compatibility decoding during at least one app release.
8. Leave every existing user Product, shopping entry, custom Product, snapshot, and
   history record intact.

No product expansion is required to perform this schema convergence.

### 11.5 Non-normative implementation status (WT-026B and WT-027A)

As of WT-026B, the bundled Hebrew catalog implements schema version 1, catalog
version 3, and taxonomy version 1. All 147 existing stable IDs were preserved and
every product received a reviewed canonical taxonomy assignment. The one deliberate
canonical-name migration (`cornflakes`: `קורנפלקס` to `דגני בוקר`) retains the
former term as both an alias and legacy name. The v2 decoder and archived fixture
remain for compatibility testing. This status note records implementation progress
and does not alter the normative model or its versioning rules.

WT-027A later applies the same model to 467 active Hebrew canonical products. The
resource remains schema version 1 and taxonomy version 1; the authoring toolkit's
one-increment-per-write policy produced catalog version 333 after 320 audited
additions and 10 audited semantic review updates. All original 147 IDs remain
unchanged.

## 12. Validation

Catalog publication must fail atomically when any required check fails.

Required validator checks:

### Document and schema

- Valid UTF-8 JSON and valid machine-readable JSON Schema.
- Supported `schemaVersion`.
- Positive, nondecreasing `catalogVersion` and `taxonomyVersion`.
- Required top-level fields and correct types.
- Declared locales use valid BCP-47 tags.
- Cross-platform fixture decoding in both Swift and Kotlin.

### Product records

- Unique stable product IDs across active and inactive records.
- No empty required fields.
- Required arrays are present.
- `popularityScore` is an integer in `0...100`.
- Exactly one valid category and zero or one valid subcategory.
- Non-null subcategory belongs to the product's category.
- No orphan category or subcategory IDs.
- Duplicate normalized canonical names are rejected.
- Canonical names, aliases, keywords, and brand terms contain no normalized duplicate
  inside a record.

### Alias and duplicate integrity

- Alias does not repeat its own canonical name after normalization.
- Alias does not equal another active canonical name.
- Normalized alias is not owned by multiple active products.
- Singular/plural, punctuation-only, spelling-only, and near-identical concept
  duplicates are flagged for review.
- Keywords and brand terms are not treated as aliases by the validator or resolver.
- Every normalization collision report identifies both product IDs and source fields.

### Status and redirects

- Active products do not redirect to another product.
- Inactive products with a replacement reference an existing active product.
- Redirect source and target differ.
- Redirect graph has no cycle.
- A retired ID remains present and is never reused.
- Deprecation metadata is internally consistent with catalog versions.

### Taxonomy and media contracts

- Category and subcategory IDs are unique, stable, and structurally valid.
- Each platform's separate category-ID-to-icon mapping resolves every active
  category or supplies a generic fallback.
- No subcategory has multiple parents.
- No third taxonomy level exists.
- Platform-specific asset names and file paths do not appear in the shared catalog.

### Release consistency

- Declared product count, when included in release metadata, equals actual count.
- Catalog changes have a changelog entry and required version increment.
- Shared acceptance examples produce the same canonical IDs on iOS and Android.
- Bundled artifact checksum matches the approved release.
- Inactive records are excluded from suggestions but remain resolvable by ID.

Warnings may identify broad keywords, suspicious brand terms, and near-duplicates for
human review. Identity collisions, broken references, and invalid required fields are
hard errors.

## 13. Catalog maintenance workflow

`CATALOG_FEEDBACK.md` is the operational log for catalog and resolution QA.

Supported feedback includes:

- Missing product.
- Missing alias.
- Missing keyword.
- Incorrect ranking.
- Weak match shown.
- Duplicate product.
- Incorrect canonical resolution.
- Brand-term issue.
- Incorrect category or subcategory.
- Typo/normalization support.
- Localization.
- Personalization.
- Other.

Workflow:

1. Record the exact query, expected canonical result, actual result, issue type, and
   status in `CATALOG_FEEDBACK.md`.
2. Reproduce against the current released catalog and native search implementation.
3. Classify the fix as content, taxonomy, schema, search, persistence, or UI copy.
4. Check duplicate and alias ownership before adding a product.
5. Make the smallest authoritative change.
6. Increment `catalogVersion` for released catalog content; increment
   `taxonomyVersion` or `schemaVersion` only under their rules.
7. Add a regression test named in the feedback row.
8. Run validators, shared acceptance fixtures, the full platform test suite, and the
   platform build.
9. Update the feedback row to Fixed/Implemented only after the regression passes.
10. Mark Verified after release or explicit QA confirmation.

Every accepted content fix must include:

- The catalog or taxonomy change.
- The required version increment.
- A regression test using the reported query.
- A feedback-log status update.

A ranking-code-only or localization-code-only fix does not increment the catalog
version unless catalog content also changes. Rejected feedback remains documented
with the identity or relevance rationale.

## 14. Acceptance examples

The following examples are normative shared fixtures. “Custom remains available”
means no confident identity exists until the user explicitly selects a candidate.

| # | Hebrew query or action | Expected canonical outcome | Contract covered |
| ---: | --- | --- | --- |
| 1 | `שקיות אשפה` | Exact `trash_bags`; display `שקיות אשפה` | Canonical exact name |
| 2 | `שקיות זבל` | Alias resolves once to `trash_bags` | Synonym alias |
| 3 | `שקי אשפה` | Alias resolves once to `trash_bags` | Plural/form alias |
| 4 | `שקי זבל` | Alias resolves once to `trash_bags` | Slang/form alias |
| 5 | `נייר טואלט` | Exact `toilet_paper` | Canonical exact name |
| 6 | `נייר שירותים` | Alias resolves to `toilet_paper`; display `נייר טואלט` | Israeli terminology |
| 7 | `קפה נמס` | Exact `instant_coffee` | Canonical exact name |
| 8 | `נס קפה` | Alias resolves to `instant_coffee`; display `קפה נמס` | Borrowed/common alias |
| 9 | `משקה שיבולת שועל` | Exact `oat_drink` | Canonical exact name |
| 10 | `חלב שיבולת שועל` | Alias resolves to `oat_drink`; display canonical name | Equivalent consumer term |
| 11 | `דגני בוקר` | Exact breakfast-cereal concept | Canonical exact name |
| 12 | `קורנפלקס` | Alias resolves to the same breakfast-cereal ID | Common borrowed word |
| 13 | `נייר אפייה` | Exact baking-paper concept | Canonical exact name |
| 14 | `נייר פרגמנט` | Alias resolves to baking-paper ID | Genuine alternate name |
| 15 | `תנור` | May discover `נייר אפייה` only as a weak keyword result | Keyword, not identity |
| 16 | `נסקפה` | May suggest generic `קפה נמס` through `brandTerms`; selection required | Brand discovery |
| 17 | `נוטלה` | May suggest generic `ממרח אגוזי לוז`; exact SKU wins when available | Brand versus concept |
| 18 | `חלב 1%` | Resolves to `milk_1_percent` | Separate meaningful variant |
| 19 | `חלב 3%` | Resolves to `milk_3_percent` | Separate meaningful variant |
| 20 | `חלב ללא לקטוז` | Resolves to `lactose_free_milk` | Dietary variant |
| 21 | `חלב` | Strong milk-name prefixes rank before keywords; personalization may reorder only tied prefix results | Relevance plus personalization |
| 22 | `שקית אשפה` | Singular alias resolves to `trash_bags`, not a new product | Singular/plural deduplication |
| 23 | `עגבניה` | Approved spelling alias resolves to canonical `עגבנייה` concept | Orthographic alias |
| 24 | `  נייר---שירותים  ` | Normalization resolves the alias to `toilet_paper` | Whitespace/punctuation |
| 25 | `פודינג חלבון וניל מהמאפייה` | No catalog ID; save exact trimmed custom text | Custom product |
| 26 | `תבנית` | Baking paper may appear only as weak context; custom remains available | Keyword confidence |
| 27 | Select `נייר אפייה` after query `תבנית` | Save baking-paper canonical ID and canonical name | Keyword-discovered save |
| 28 | Select result after query `נייר שירותים` | Save `toilet_paper`, display/snapshot `נייר טואלט`, optionally retain raw query | Alias saving |
| 29 | Exact unique query `שקיות זבל` | Custom duplicate action is suppressed or canonicalized on confirmation | Duplicate custom prevention |
| 30 | Select `שקיות זבל`, then `שקי אשפה`, then `שקיות אשפה` | One `trash_bags` history aggregate receives three selections | Canonical personalization |
| 31 | Frequent history for `לחם מלא`, query `שמ` | `לחם מלא` does not appear unless text independently matches | No unrelated boost |
| 32 | Frequent `חלב 3%`, query `ח` | It may lead other same-tier `ח` prefixes | Frequency boost |
| 33 | Recent `לחם מלא`, query `לח` | It may lead otherwise tied bread prefixes | Recency boost |
| 34 | Barcode for branded `חלב 3% 1 ליטר` | Resolve exact SKU, then `milk_3_percent`; retain SKU/package snapshot when supported | Barcode/SKU mapping |
| 35 | Camera label `גליל נייר לשירותים` | Suggest `toilet_paper`; require configured confidence or user selection | AI recognition |
| 36 | Add second active record named `שקיות זבל` | Validator rejects it; add alias to `trash_bags` instead | Duplicate normalized concept |
| 37 | Put alias `נייר טואלט` on another product | Validator rejects canonical-name/alias collision | Alias ownership |
| 38 | Query `קמח` with records `קמח` and `קמח לבן` | Generic exact result leads; subtype may remain separate when explicitly useful | Broad concept versus subtype |
| 39 | Query `קוקה קולה זירו` | Do not rename generic `קולה`; prefer exact branded SKU or custom/candidate flow | Brand and SKU boundary |
| 40 | iOS and Android query `נייר שירותים` on the same catalog version | Both resolve `toilet_paper` and save the same canonical ID | Cross-platform parity |
| 41 | Deactivate duplicate legacy product with replacement `trash_bags` | Existing ID remains resolvable; new searches use survivor | Redirect/migration |
| 42 | Link legacy custom `שקיות זבל` after user confirmation | Preserve local UUID/data, attach `trash_bags`, merge history safely | Legacy linking |

## 15. Approved Model

The final WayTask canonical catalog model is approved as follows:

1. **Canonical identity:** One stable ASCII product ID represents one reusable product
   concept. Names, aliases, queries, brands, barcodes, packages, categories, and
   provider data are evidence or metadata, never identity.
2. **Required product fields:** Every product has `id`, `canonicalName`,
   `categoryId`, present-but-nullable `subcategoryId`, `aliases`, `keywords`,
   `brandTerms`, `popularityScore`, and `isActive`.
3. **Display name:** No redundant required `displayName` exists. `canonicalName` is
   the default-locale display name; localized canonical names and saved snapshots
   provide fallback.
4. **Aliases and keywords:** Aliases are genuine alternate names for the same
   concept. Keywords are weaker related discovery terms and never identity proof.
5. **Brand strategy:** Generic canonical concepts remain separate from future exact
   branded/package SKUs. `brandTerms` aids discovery without changing canonical
   identity. Verified barcodes resolve SKU first, then canonical product.
6. **Taxonomy:** Every product has exactly one broad top-level category and at most
   one namespaced subcategory. The approved long-term target has 23 stable top-level
   retail categories and no third hierarchy level.
7. **Save behavior:** A confident or explicitly selected catalog result saves the
   canonical ID and canonical display snapshot and never creates a duplicate custom
   identity. An unresolved query saves exact custom text with no catalog ID.
8. **Personalization:** Frequency, recency, and future favorites aggregate by
   canonical ID and may reorder only within the same textual relevance tier.
9. **Shared contract:** iOS and Android consume one versioned JSON schema, stable IDs,
   normalization contract, validator rules, and acceptance fixtures through vendored
   immutable catalog-contract releases.
10. **Versioning and migration:** Schema, catalog content, and taxonomy have
    independent versions. Released IDs are never deleted or reused; deactivation and
    redirects preserve compatibility. Existing user data and snapshots migrate
    additively and are never inferred or rewritten from names without an approved,
    safe linking flow.

No backend is required for this model. A future remote source must implement the same
catalog contract and must not change UI, search, persistence, or identity semantics.
