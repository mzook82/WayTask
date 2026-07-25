# WayTask Hebrew Product Catalog Guide

The [Canonical Product Catalog Specification](docs/Specifications/CanonicalProductCatalogSpecification.md)
is the normative long-term identity, schema, taxonomy, resolution, parity, and
migration contract. This guide describes maintenance of the canonical Hebrew
resource shipped by WT-026B.

## Shared contract

Platform-neutral contract resources are stored in:

`shared/catalog/`

- `product-catalog.schema.json`: canonical JSON Schema, currently
  `schemaVersion: 1`.
- `taxonomy.json`: taxonomy version 1, 23 approved categories, subcategories,
  and the complete v2 compatibility map.
- `normalization-fixtures.json`: shared Hebrew normalization cases.
- `acceptance-fixtures.json`: shared canonical identity and resolution cases.
- `product-taxonomy-review.json`: non-runtime evidence of the completed
  product-by-product WT-026B taxonomy review.
- `README.md`: release and future Android consumption workflow.

The files contain semantic IDs and text only. Platform icon mappings remain outside
the shared registry.

## Catalog location

The Phase 1 catalog is stored at:

`WayTask/Resources/product_catalog_he.json`

It is bundled with the iOS application. Product data must be edited in that JSON
resource, not added as a Swift array in a view or ViewModel. The loader and search
engine are intentionally separate, so a future remote provider can conform to
`ProductCatalogProviding` without changing autocomplete UI or ranking logic.

## Catalog metadata

The file has this top-level structure:

```json
{
  "schemaVersion": 1,
  "catalogVersion": 3,
  "taxonomyVersion": 1,
  "locale": "he-IL",
  "products": []
}
```

- `schemaVersion`: Version of the canonical document shape. The shipped format is 1.
- `catalogVersion`: Positive integer revision of catalog content. The shipped
  Hebrew catalog is version 3.
- `taxonomyVersion`: Version of `shared/catalog/taxonomy.json`. The shipped value is 1.
- `locale`: Catalog language and regional terminology. Phase 1 requires `he-IL`.
- `products`: The complete list of catalog product records.

Increase `catalogVersion` by one whenever a reviewed catalog update is released.
Commit the version change in the same change as the products and tests. Do not
reuse or decrease a released version number.

## Supported source formats

The iOS compatibility decoder accepts:

1. Canonical `schemaVersion: 1` documents validated by the shared JSON Schema. This
   is the only format permitted for future production catalog releases.
2. The retired schema-less v2 shape, retained in the decoder and test fixture for
   backward compatibility.

Both produce the same in-memory `CatalogProduct`:

```text
id, canonicalName, categoryId, subcategoryId, aliases, keywords,
brandTerms, popularityScore, isActive, replacement metadata
```

Legacy compatibility mapping remains deterministic:

- `name` becomes `canonicalName`.
- `subcategoryId` becomes `nil`.
- `brandTerms` and `legacyNames` become empty arrays.
- Optional replacement and metadata values remain absent.
- Product IDs, legacy category IDs, aliases, keywords, popularity, and active state
  are unchanged.

Search, ranking, personalization, UI, and persistence receive this canonical model
and do not branch on the source schema.

## Product fields

Every product contains all of these fields:

| Field | Meaning |
| --- | --- |
| `id` | Stable, portable identifier using lowercase ASCII letters, digits, and underscores. It must start with a letter and must never depend on the Hebrew display name. |
| `canonicalName` | Stable natural Hebrew name for the product concept and the default suggestion display name. |
| `categoryId` | Stable approved top-level taxonomy ID. |
| `subcategoryId` | Present but nullable approved namespaced subcategory ID whose parent is `categoryId`. |
| `aliases` | Real alternative names that shoppers are likely to type. |
| `keywords` | Useful discovery terms that are not alternative product names. |
| `brandTerms` | Genuine brand expressions used to find this generic concept; they do not redefine identity. |
| `popularityScore` | Integer from 0 through 100 used only to break ties within the same match level. |
| `isActive` | `true` to expose the product; `false` to retain its stable identity while removing it from suggestions. |

Aliases, keywords, and brand terms may be empty arrays, but every string they
contain must be nonempty. Product IDs must be unique across active and inactive
records. Optional migration fields are defined by the shared schema.

## Taxonomy compatibility

`shared/catalog/taxonomy.json` is the category source of truth. WT-026B reviewed all
147 products individually and assigned an approved `categoryId` and nullable
`subcategoryId`. The audit is recorded in
`shared/catalog/product-taxonomy-review.json`; it is maintenance evidence and is
included only in the test bundle, not read at runtime.

The 48 products from the eight broad legacy mappings marked
`product_review_required` were classified individually. No unresolved assignment
remains. The explicit legacy compatibility mappings are retained for decoding v2
fixtures; they are not a shortcut for future product assignment.

## Validator

`ProductCatalogValidator` validates both formats after compatibility decoding. It
rejects unsupported metadata, invalid IDs, empty fields, popularity outside
`0...100`, duplicate canonical names, cross-product alias collisions, brand terms
that collide with canonical names or aliases, invalid category/subcategory
references, parent mismatches, invalid replacements, and replacement loops. It also
validates the taxonomy registry and its compatibility targets.

Structural rules remain in `product-catalog.schema.json`; comparisons across records
are application-level checks. Invalid catalogs fail atomically and the existing safe
empty fallback remains available.

## Add a product

1. Search the entire JSON file for the proposed ID and Hebrew name.
2. Choose a stable semantic ID such as `bread_rye`; do not use a translated name,
   sequence number, package size, or current brand unless the product itself is
   brand-specific.
3. Add the complete record under `products`.
4. Choose an approved `categoryId` and matching `subcategoryId` from
   `shared/catalog/taxonomy.json`; use `null` only when no approved subcategory fits.
5. Add only aliases that people genuinely use for that same product.
6. Add a few meaningful use, aisle, or household terms as keywords.
7. Add `brandTerms` only for genuine brand-led searches.
8. Set popularity relative to comparable products in that category.
9. Add a completed entry to the taxonomy review manifest.
10. Increase `catalogVersion`.
11. Add or update a ranking test when the product fixes search feedback.
12. Run the catalog and search tests.

Example:

```json
{
  "id": "bread_rye",
  "canonicalName": "לחם שיפון",
  "categoryId": "bakery",
  "subcategoryId": null,
  "aliases": ["לחם מקמח שיפון"],
  "keywords": ["מאפייה", "כריך", "דגנים"],
  "brandTerms": [],
  "popularityScore": 78,
  "isActive": true
}
```

## WT-026B migration record

WT-026B preserved all 147 IDs, aliases and keywords with semantic value,
popularity scores, and active states while moving the production resource from v2
to canonical schema 1/catalog 3/taxonomy 1.

- One canonical name changed: `cornflakes` from `קורנפלקס` to `דגני בוקר`.
  `קורנפלקס` remains an alias and the former name is also retained in `legacyNames`.
- True brand expressions moved from aliases to `brandTerms`: `קוקה קולה`
  (`cola`), `שמרית` (`dry_yeast`), `אקמול` (`paracetamol`), `אדוויל` and
  `נורופן` (`ibuprofen`), and `גרבר` (`baby_puree`).
- Alias normalization collisions within individual products were removed without
  removing distinct searchable meaning. `trash_bags` gained the accepted
  equivalents `שקי אשפה` and `שקי זבל`.
- No cross-product canonical-name, alias, or brand-term collision remains.

The exact collision cleanup was:

| Product ID | Resolution |
| --- | --- |
| `cottage_cheese` | Removed `קוטג'` and `קוטג`, which normalize to canonical `קוטג׳`. |
| `potato` | Removed `תפוא`, which normalizes to retained alias `תפו״א`. |
| `frozen_french_fries` | Removed `צ'יפס קפוא`, which normalizes to canonical `צ׳יפס קפוא`. |
| `potato_chips` | Removed `תפוצ'יפס`, which normalizes to canonical `תפוצ׳יפס`. |
| `laundry_detergent` | Removed `ג'ל כביסה`, which normalizes to canonical `ג׳ל כביסה`. |
| `body_wash` | Removed `ג'ל רחצה`, which normalizes to retained alias `ג׳ל רחצה`. |
| `hand_sanitizer` | Removed `ג'ל לחיטוי ידיים`, which normalizes to retained alias `ג׳ל לחיטוי ידיים`. |
| `infant_formula` | Removed `תמל`, which normalizes to retained alias `תמ״ל`. |
| `food_storage_bags` | Removed `שקיות סנדוויץ'`, which normalizes to retained alias `שקיות סנדוויץ׳`. |

## Add an alias

Add the alternative name to the product's `aliases` array. An alias should denote
the same product, for example `"נייר שירותים"` for `"נייר טואלט"`. Do not use
aliases to force an unrelated product into results. Add a test using the reported
query when the alias comes from feedback.

## Add keywords

Add terms to `keywords` only when they help a shopper discover the product by
aisle, use, or common context. Keywords are intentionally ranked below every
product-name and alias match. Avoid repeating the product name, adding every
category name to every record, or adding speculative spelling noise.

## Deactivate an obsolete product

Change `isActive` to `false` and increase `catalogVersion`. Do not delete or rename
the ID if it may already be referenced by a saved shopping item. The loader
validates inactive records but excludes them from search results.

## Avoid duplicate IDs

- Search for the full quoted ID before adding a record.
- Reuse an existing product and add an alias when the identity is the same.
- Do not create separate IDs for spelling or punctuation variations.
- Run the tests: duplicate IDs cause catalog loading to fail atomically.

Quick JSON checks:

```sh
jq -e '.' WayTask/Resources/product_catalog_he.json
jq -r '.products[].id' WayTask/Resources/product_catalog_he.json | sort | uniq -d
```

## Run catalog and search tests

From the repository root, choose an installed iOS Simulator destination and run:

```sh
xcodebuild test \
  -project WayTask.xcodeproj \
  -scheme WayTask \
  -destination 'platform=iOS Simulator,name=<installed simulator>' \
  -derivedDataPath /private/tmp/WayTaskCatalogTests
```

The focused suites are:

- `ProductCatalogServiceTests`
- `ProductCatalogCanonicalValidationTests`
- `ProductCatalogCompatibilityLayerTests`
- `ProductCatalogMigrationTests`
- `SharedCatalogFixtureTests`
- `ProductCatalogSearchTests`
- `ProductCatalogAutocompleteTests`

Also run the full `WayTask` scheme test action before releasing a catalog version.

## Next migration and expansion steps

**WT-027A — Controlled Canonical Catalog Coverage Expansion:** admit only reviewed
gaps from `CATALOG_FEEDBACK.md`, author every addition in canonical schema 1, assign
taxonomy product by product, increment `catalogVersion`, and add shared acceptance
plus native regression coverage. The released `shared/catalog/` contract and
fixtures should be vendored into Android as an entry criterion for cross-platform
parity; no backend is required.
