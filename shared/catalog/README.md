# WayTask Shared Catalog Contract

This directory is the platform-neutral source for the WayTask canonical catalog
contract. It contains no Swift, Kotlin, SF Symbol, Android resource, or UI-specific
metadata.

## Files

- `product-catalog.schema.json` — JSON Schema Draft 2020-12 contract for canonical
  catalog documents (`schemaVersion` 1).
- `taxonomy.json` — taxonomy version 1 with 23 approved top-level categories,
  controlled subcategories, and explicit mappings from every production v2 category.
- `normalization-fixtures.json` — Hebrew normalization inputs and expected outputs.
- `acceptance-fixtures.json` — a small canonical fixture catalog plus shared
  resolution expectations.
- `product-taxonomy-review.json` — non-runtime maintenance evidence containing the
  completed taxonomy decision for every production product.

## Supported source formats

The iOS compatibility layer accepts:

1. Canonical `schemaVersion: 1`, decoded directly from the JSON Schema shape. The
   production Hebrew resource is catalog version 3 and taxonomy version 1.
2. The retired legacy v2 shape, identified by the absence of `schemaVersion`. Its
   `name` maps to `canonicalName`, `subcategoryId` maps to `null`, and `brandTerms`
   maps to an empty array. It remains supported and covered by an archived fixture.

Both formats produce the same Swift `CatalogProduct` model. Search, ranking,
personalization, UI, and persistence do not branch on source format.

WT-026B assigned approved taxonomy IDs to every one of the 147 production products.
All 48 products in the eight `product_review_required` legacy groups were reviewed
individually. `product-taxonomy-review.json` records those decisions and contains no
runtime dependency. Legacy mappings remain solely for compatibility decoding.

## Validation and fixtures

The iOS validator checks document metadata, taxonomy references, stable IDs,
normalized canonical-name and alias collisions, brand terms that collide with a
canonical name or alias, popularity, inactive replacements, and replacement cycles.
JSON Schema handles structural validation; rules requiring comparisons across
records remain application-level checks.

iOS tests load the normalization and acceptance files as resources. A future Android
repository should vendor the same released directory and run the fixtures through its
Kotlin decoder, normalizer, validator, and search implementation.

## Release workflow

1. Update contract resources in one reviewed change.
2. Increment the relevant schema, catalog, or taxonomy version.
3. Validate all JSON and run shared fixtures.
4. Run the full native test suites.
5. Tag the shared contract release and record its checksum in each platform
   repository.

WT-026B migrated but did not expand the 147-product catalog. All future additions
must use canonical schema version 1, an approved taxonomy assignment, a review
manifest entry, a catalog-version increment, and shared/native regression coverage.
