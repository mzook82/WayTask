# WayTask Canonical Catalog Authoring Toolkit

This directory contains the platform-neutral, developer-facing toolkit for the
WayTask canonical product catalog. It is not linked into the iOS application and
does not provide an authoring UI.

The toolkit uses only Node.js built-in modules. There is no package installation,
lockfile, backend, or network dependency. Run commands from the repository root
with Node.js 20 or newer.

## Contract and default files

The CLI reads these repository sources by default:

| Purpose | Path |
| --- | --- |
| Production catalog | `WayTask/Resources/product_catalog_he.json` |
| JSON Schema | `shared/catalog/product-catalog.schema.json` |
| Taxonomy | `shared/catalog/taxonomy.json` |
| Taxonomy review | `shared/catalog/product-taxonomy-review.json` |
| Write audit | `shared/catalog/catalog-authoring-audit.jsonl` |

The audit file is created only by the first committed authoring change. Dry runs and
read-only commands do not create it.

## Commands

### Validate

```sh
node tools/catalog/catalog-tool.js validate
node tools/catalog/catalog-tool.js validate --json
```

Validation is atomic and covers the shared structural contract plus cross-record
rules:

- Required metadata and product fields.
- Supported schema, catalog, taxonomy, and locale values.
- Stable IDs and unique product IDs.
- Duplicate normalized canonical names.
- Empty and duplicate normalized text values.
- Aliases matching canonical names or aliases owned by another active product.
- Brand terms colliding with active canonical names or aliases.
- Valid categories, subcategories, and parent relationships.
- Integer popularity scores in `0...100`.
- Active/deprecation consistency, replacement targets, and replacement loops.
- Review-manifest metadata, count, product coverage, status, and taxonomy parity.

Errors include stable codes and affected product IDs. Exit status is nonzero when
validation fails.

### Report

```sh
node tools/catalog/catalog-tool.js report
node tools/catalog/catalog-tool.js report --json
```

The report includes versions, active/inactive totals, taxonomy coverage, alias,
keyword, and brand-term totals, category assignment counts, review statuses, the
sorted product-ID fingerprint, and validation status.

### Find

```sh
node tools/catalog/catalog-tool.js find --query "שקיות זבל"
node tools/catalog/catalog-tool.js find --query "שקיות זבל" --limit 5 --json
```

`find` is an authoring diagnostic. It shows the matching canonical name, alias,
brand term, keyword, or legacy name and excludes inactive products by default.
Use `--include-inactive` when reviewing deprecations.

Its deterministic tiers help identify collisions and existing concepts. It does not
replace or modify the iOS search engine, ranking weights, personalization, or UI.

### Inspect

```sh
node tools/catalog/catalog-tool.js inspect --id trash_bags
```

Inspection joins the full product record with its category, subcategory, and
taxonomy-review entry.

### Check a candidate

```sh
node tools/catalog/catalog-tool.js check-candidate \
  --input path/to/product.json
```

The input must be one complete canonical product object. The toolkit simulates
adding it, including review-manifest coverage, then validates the whole proposed
catalog. It never writes.

Run `find` for the proposed name and aliases before accepting a candidate; exact
normalization collisions are hard errors, while human semantic review remains
required for near-duplicates.

### Add a product

```sh
# Dry run
node tools/catalog/catalog-tool.js add --input path/to/product.json

# Commit after reviewing the dry run
node tools/catalog/catalog-tool.js add \
  --input path/to/product.json \
  --write
```

The product input uses the canonical shared-schema shape:

```json
{
  "id": "stable_ascii_id",
  "canonicalName": "שם עברי",
  "categoryId": "approved_category",
  "subcategoryId": null,
  "aliases": [],
  "keywords": [],
  "brandTerms": [],
  "popularityScore": 50,
  "isActive": true
}
```

A committed add also creates a `confirmed` review entry with
`previousLegacyCategoryId: null`.

### Update a product

```sh
# Arrays replace the complete existing array.
node tools/catalog/catalog-tool.js update \
  --id trash_bags \
  --input path/to/update.json

node tools/catalog/catalog-tool.js update \
  --id trash_bags \
  --input path/to/update.json \
  --write
```

The input is a partial product object containing fields to replace. The stable
product ID cannot change. A taxonomy, canonical-name, alias, or brand-term update
also synchronizes the review entry with the appropriate approved review status.

### Deactivate a product

```sh
node tools/catalog/catalog-tool.js deactivate --id product_id
node tools/catalog/catalog-tool.js deactivate --id product_id --write
```

Deactivation retains the product and stable ID, sets `isActive: false`, and records
the new catalog version in `deprecatedSinceCatalogVersion`. Redirects are added
separately with `update` and must point to an existing active product.

## Write safety

`add`, `update`, and `deactivate` are dry runs unless `--write` is explicitly
present. A committed operation:

1. Validates the current catalog and refuses to mutate an invalid baseline.
2. Constructs the complete proposed catalog and review manifest in memory.
3. Increments `catalogVersion` exactly once.
4. Runs full validation before writing.
5. Rejects the operation if the catalog or review file changed since loading.
6. Transactionally replaces the catalog and review manifest and appends one audit
   JSON line.
7. Reloads and validates the committed files.

The audit record contains the operation, product ID, old/new catalog versions,
changed fields, timestamp, and catalog SHA-256 values. It does not contain user
shopping data, analytics, or credentials.

Always review the ordinary dry-run output or use `--json` before committing.
Commit the catalog, review manifest, audit entry, feedback update, and regression
tests together.

## Path overrides

All contract and output paths can be overridden, which is useful for release
staging and tests:

```sh
node tools/catalog/catalog-tool.js validate \
  --catalog /tmp/catalog.json \
  --schema shared/catalog/product-catalog.schema.json \
  --taxonomy shared/catalog/taxonomy.json \
  --review /tmp/review.json \
  --audit /tmp/audit.jsonl
```

Relative overrides are resolved from the current working directory.

## Automated tests

Run:

```sh
node --test tools/catalog/test/*.test.js
```

Tests execute the shared Hebrew normalization and Wave 1 search fixtures, validate
the 467-product production catalog and its 330-entry audit chain, exercise every
required validator failure, and perform add/update/deactivate dry runs and
committed writes only against temporary copies.

Before releasing catalog content, also run the complete iOS test suite, the unsigned
generic iOS build, and:

```sh
git diff --check
```

## Release workflow

Use `CATALOG_FEEDBACK.md` as the operational source for accepted work:

1. Record and reproduce the missing product or content defect.
2. Run `find`, `inspect`, and `check-candidate`.
3. Review the dry-run mutation.
4. Commit with `--write`.
5. Add the shared/native regression named in the feedback row.
6. Run toolkit validation, toolkit tests, iOS tests, and the build.
7. Review and commit the generated audit entry and incremented catalog version.

Do not hand-edit the audit log. Do not use this toolkit to bypass canonical identity,
alias, brand, taxonomy, versioning, or feedback-review policy.
