# WayTask Hebrew Product Catalog Guide

The [Canonical Product Catalog Specification](docs/Specifications/CanonicalProductCatalogSpecification.md)
is the normative long-term identity, schema, taxonomy, resolution, parity, and
migration contract. This guide describes maintenance of the canonical Hebrew
resource shipped through WT-027B.

## Shared contract

Platform-neutral contract resources are stored in:

`shared/catalog/`

- `product-catalog.schema.json`: canonical JSON Schema, currently
  `schemaVersion: 1`.
- `taxonomy.json`: taxonomy version 1, 23 approved categories, subcategories,
  and the complete v2 compatibility map.
- `normalization-fixtures.json`: shared Hebrew normalization cases.
- `acceptance-fixtures.json`: shared canonical identity and resolution cases.
- `wave-1-search-fixtures.json`: representative Hebrew search regressions for
  the WT-027A production expansion.
- `wave-2-search-fixtures.json`: representative Hebrew search regressions for
  the WT-027B production expansion.
- `releases/wt-027b-wave-2.json`: the reviewed transactional source for release 5.
- `product-taxonomy-review.json`: non-runtime evidence of the completed
  product-by-product taxonomy review, including Wave 1 and Wave 2 additions.
- `catalog-authoring-audit.jsonl`: append-only authoring audit for toolkit
  mutations.
- `README.md`: release and future Android consumption workflow.

The files contain semantic IDs and text only. Platform icon mappings remain outside
the shared registry.

## Authoring toolkit

WT-026C provides a dependency-free Node.js toolkit at
[`tools/catalog/`](tools/catalog/README.md). Run it from the repository root before
editing or releasing catalog content:

```sh
node tools/catalog/catalog-tool.js validate
node tools/catalog/catalog-tool.js report
node tools/catalog/catalog-tool.js find --query "שקיות זבל"
node tools/catalog/catalog-tool.js inspect --id trash_bags
node tools/catalog/catalog-tool.js check-candidate --input product.json
```

`add`, `update`, `deactivate`, and `batch` are dry runs by default. `--write` is
required to commit. A committed single command or multi-mutation batch represents
one released catalog revision: it validates the complete proposal, increments
`catalogVersion` exactly once, synchronizes the taxonomy review manifest, and
appends one audit entry per mutation. The toolkit rejects stale concurrent writes.
See its README for batch shape, path overrides, audit fields, tests, and the release
workflow.

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
  "catalogVersion": 5,
  "taxonomyVersion": 1,
  "locale": "he-IL",
  "products": []
}
```

- `schemaVersion`: Version of the canonical document shape. The shipped format is 1.
- `catalogVersion`: Positive released revision of catalog content. The shipped
  Hebrew Wave 2 catalog is release 5.
- `taxonomyVersion`: Version of `shared/catalog/taxonomy.json`. The shipped value is 1.
- `locale`: Catalog language and regional terminology. Phase 1 requires `he-IL`.
- `products`: The complete list of catalog product records.

`catalogVersion` identifies a published content release, not the number of
authoring mutations. Use one transactional `batch --write` for all mutations in a
release; the version increments exactly once while each mutation receives its own
audit line. An isolated `add`, `update`, or `deactivate --write` is a valid
single-mutation release and also increments once. Commit the catalog, review
manifest, audit log, fixtures, and tests together. Never reuse or decrease a
released revision.

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

`shared/catalog/taxonomy.json` is the category source of truth. WT-026B reviewed the
original 147 products individually, WT-027A reviewed 320 additions, and WT-027B
reviewed another 180 additions through the authoring toolkit. All 647 products have
an approved `categoryId` and nullable `subcategoryId`. The review evidence is recorded in
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

1. Use `find` for the proposed name and every alias, then run `check-candidate`.
2. Choose a stable semantic ID such as `buckwheat_flour`; do not use a translated name,
   sequence number, package size, or current brand unless the product itself is
   brand-specific.
3. Add the complete record under `products`.
4. Choose an approved `categoryId` and matching `subcategoryId` from
   `shared/catalog/taxonomy.json`; use `null` only when no approved subcategory fits.
5. Add only aliases that people genuinely use for that same product.
6. Add a few meaningful use, aisle, or household terms as keywords.
7. Add `brandTerms` only for genuine brand-led searches.
8. Set popularity relative to comparable products in that category.
9. Review the candidate and include it in the intended release batch. For an
   isolated single-product release, `add --write` creates the review entry and
   increments `catalogVersion` once.
10. Review the generated audit entry.
11. Add or update a ranking test when the product fixes search feedback.
12. Run the toolkit, catalog, and search tests.

Example:

```json
{
  "id": "buckwheat_flour",
  "canonicalName": "קמח כוסמת",
  "categoryId": "pantry",
  "subcategoryId": "pantry.baking",
  "aliases": ["קמח מכוסמת"],
  "keywords": ["אפייה", "כוסמת"],
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

## WT-027A Wave 1 expansion record

WT-027A added 320 reviewed canonical concepts without changing or removing any of
the original 147 records. That Wave 1 release contained 467 active products at
schema version 1, catalog version 4, taxonomy version 1.

Every addition was processed through `check-candidate`, a dry-run `add`, and an
explicit `add --write`. Each committed transaction updated the taxonomy review
manifest, ran whole-catalog validation, and appended one entry to
`shared/catalog/catalog-authoring-audit.jsonl`. Ten follow-up toolkit updates moved
non-equivalent use phrases from aliases into keywords and brand-led expressions
into `brandTerms`, yielding 330 historical mutation entries in total.

WT-027A.1 established release-level versioning and normalized Wave 1 to released
revision 4. The 330 historical audit lines and their former per-mutation counter
fields remain byte-for-byte unchanged. One appended policy-migration record links
the former authoring counter 333 to release 4. Future transactional batches append
one audit record per mutation but increment the release revision only once.

The shared `wave-1-search-fixtures.json` file covers representative canonical-name,
alias, brand-term, and custom no-match behavior. Wave 1 does not change ranking,
personalization, UI, persistence, schema, or taxonomy.

## WT-027B Wave 2 expansion record

WT-027B added 180 reviewed canonical concepts in one toolkit batch, preserving all
467 release-4 records and advancing `catalogVersion` exactly once from 4 to 5.
Production now contains 647 active products at schema version 1 and taxonomy
version 1.

The batch source is `shared/catalog/releases/wt-027b-wave-2.json`. Its additions
are distributed across pharmacy (15), snacks (15), bakery (12), drinks (15), baby
(15), pet supplies (15), apparel (15), home and garden (15), office and school
(15), automotive (12), sports (12), toys (12), and books and media (12). Every
entry has a completed taxonomy review. The 180 audit entries share release ID
`wt-027b-wave-2`, versions 4 and 5, and one before/after catalog hash pair.

`shared/catalog/wave-2-search-fixtures.json` adds 42 Hebrew canonical-name, alias,
brand-term, and custom no-match cases consumed by both the Node and native iOS
suites. Wave 2 changes no ranking, personalization, UI, persistence, schema, or
taxonomy behavior.

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

Use `deactivate` in the intended batch release, or as an isolated one-product
release. Do not delete or rename the ID if it may already be referenced by a saved
shopping item. The loader validates inactive records but excludes them from search
results.

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

The authoritative local check is:

```sh
node tools/catalog/catalog-tool.js validate
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
Run the toolkit suite first:

```sh
node --test tools/catalog/test/*.test.js
```

## Next migration and expansion steps

**WT-027C — Catalog Coverage QA and Wave 3 planning:** collect real missing-query
evidence in `CATALOG_FEEDBACK.md`, review the remaining shallow categories
(especially electronics and the newer non-grocery categories), and improve shared
taxonomy subcategory coverage before authoring another transactional release. Wave
3 should remain feedback-led and must not add narrow SKU or brand variants merely
to raise counts.
