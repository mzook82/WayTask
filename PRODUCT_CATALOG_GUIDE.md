# WayTask Hebrew Product Catalog Guide

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
  "catalogVersion": 2,
  "locale": "he-IL",
  "products": []
}
```

- `catalogVersion`: Positive integer revision of the catalog content and schema.
- `locale`: Catalog language and regional terminology. Phase 1 requires `he-IL`.
- `products`: The complete list of catalog product records.

Increase `catalogVersion` by one whenever a reviewed catalog update is released.
Commit the version change in the same change as the products and tests. Do not
reuse or decrease a released version number.

## Product fields

Every product contains all of these fields:

| Field | Meaning |
| --- | --- |
| `id` | Stable, portable identifier using lowercase ASCII letters, digits, and underscores. It must start with a letter and must never depend on the Hebrew display name. |
| `name` | Preferred Hebrew display name shown in suggestions. |
| `categoryId` | Stable category identifier used for grouping, category search, and icon selection. |
| `aliases` | Real alternative names that shoppers are likely to type. |
| `keywords` | Useful discovery terms that are not alternative product names. |
| `popularityScore` | Integer from 0 through 100 used only to break ties within the same match level. |
| `isActive` | `true` to expose the product; `false` to retain its stable identity while removing it from suggestions. |

Aliases and keywords may be empty arrays, but every string they contain must be
nonempty. Product IDs must be unique across active and inactive records.

## Add a product

1. Search the entire JSON file for the proposed ID and Hebrew name.
2. Choose a stable semantic ID such as `bread_rye`; do not use a translated name,
   sequence number, package size, or current brand unless the product itself is
   brand-specific.
3. Add the complete record under `products`.
4. Use the closest existing `categoryId`.
5. Add only aliases that people genuinely use for that same product.
6. Add a few meaningful use, aisle, or household terms as keywords.
7. Set popularity relative to comparable products in that category.
8. Increase `catalogVersion`.
9. Add or update a ranking test when the product fixes search feedback.
10. Run the catalog and search tests.

Example:

```json
{
  "id": "bread_rye",
  "name": "לחם שיפון",
  "categoryId": "bakery",
  "aliases": ["לחם מקמח שיפון"],
  "keywords": ["מאפייה", "כריך", "דגנים"],
  "popularityScore": 78,
  "isActive": true
}
```

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
- `ProductCatalogSearchTests`
- `ProductCatalogAutocompleteTests`

Also run the full `WayTask` scheme test action before releasing a catalog version.
