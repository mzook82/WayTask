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
- `wave-1-search-fixtures.json` — production Wave 1 Hebrew search expectations,
  reusable by Node, Swift, and future Kotlin tests.
- `product-taxonomy-review.json` — non-runtime maintenance evidence containing the
  completed taxonomy decision for every production product.
- `catalog-authoring-audit.jsonl` — append-only JSON Lines authoring history.

## Supported source formats

The iOS compatibility layer accepts:

1. Canonical `schemaVersion: 1`, decoded directly from the JSON Schema shape. The
   production Hebrew resource is catalog version 4 and taxonomy version 1.
2. The retired legacy v2 shape, identified by the absence of `schemaVersion`. Its
   `name` maps to `canonicalName`, `subcategoryId` maps to `null`, and `brandTerms`
   maps to an empty array. It remains supported and covered by an archived fixture.

Both formats produce the same Swift `CatalogProduct` model. Search, ranking,
personalization, UI, and persistence do not branch on source format.

WT-026B assigned approved taxonomy IDs to every one of the original 147 products.
All 48 products in the eight `product_review_required` legacy groups were reviewed
individually. `product-taxonomy-review.json` records those decisions and contains no
runtime dependency. Legacy mappings remain solely for compatibility decoding.

WT-027A added 320 individually reviewed canonical products, bringing production to
467 active records without changing any original ID. The same review manifest now
contains all 467 assignments. The 320 toolkit transactions are recorded in
`catalog-authoring-audit.jsonl`; ten semantic-review updates bring the audit to 330
historical mutation entries. WT-027A.1 preserves those entries, normalizes the Wave
1 release to catalog version 4, and appends one explicit policy-migration record.
`wave-1-search-fixtures.json` provides shared regressions for the expanded coverage.

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

1. Use `tools/catalog/catalog-tool.js` to inspect, validate, and dry-run catalog
   content changes; see `tools/catalog/README.md`.
2. Put all mutations for one release into one toolkit `batch`; dry-run it, then
   commit only with the explicit `--write` flag.
3. Increment the catalog revision once per committed release. Each mutation remains
   a separate audit entry. Increment schema or taxonomy versions only under their
   independent compatibility rules.
4. Validate all JSON and run shared fixtures and toolkit tests.
5. Run the full native test suites.
6. Tag the shared contract release and record its checksum in each platform
   repository.

WT-026B migrated but did not expand the original 147-product catalog. WT-027A is the
first controlled expansion. All future additions must use canonical schema version
1, an approved taxonomy assignment, a review-manifest entry, a catalog-version
increment, an audit record, and shared/native regression coverage.
