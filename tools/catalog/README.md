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
| Locale overlay | `WayTask/Resources/ProductKnowledge/product-knowledge-localizations-v1.json` |
| Release manifest | `WayTask/Resources/ProductKnowledge/product-catalog-release-v1.json` |
| JSON Schema | `shared/catalog/product-catalog.schema.json` |
| Editorial release schema | `shared/catalog/product-editorial-release.schema.json` |
| Taxonomy | `shared/catalog/taxonomy.json` |
| Taxonomy review | `shared/catalog/product-taxonomy-review.json` |
| Write audit | `shared/catalog/catalog-authoring-audit.jsonl` |

The audit file is created only by the first committed authoring change. Dry runs and
read-only commands do not create it.

## WT-031B production boundary

Production expansion now enters through a versioned editorial release. Direct
`add`, `update`, `deactivate`, and `batch --write` calls against the default
production catalog are refused. Those commands remain available for historical
fixtures, diagnostics, and explicitly overridden development copies.

An editorial release contains one complete record for every added or replaced
product. The record owns:

- Stable `id` and locale-keyed `canonicalNames`; `he-IL` is required and `en` is
  optional.
- Locale-tagged `localizedDisplayNames`, `aliases`, `keywords`, `brandTerms`, and
  optional `legacyNames`.
- Optional `brand`, `semanticKey`, variant descriptors, package descriptor, unit,
  GTIN/barcodes, and provenance.
- Approved category/subcategory, popularity, and explicit active/inactive status.

Localized strings never replace the stable product ID. A secondary canonical name
is emitted as a preferred localized display record, so Hebrew and English resolve
to one Product Knowledge identity.

The release envelope owns `schemaVersion`, the next `catalogVersion`,
`taxonomyVersion`, an ISO `generationDate`, the proposed `productCount`, a stable
`releaseId`, supported locales, and operations. It must advance the catalog by
exactly one version.

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

### Validate the complete production bundle

```sh
node tools/catalog/catalog-tool.js validate-production
node tools/catalog/catalog-tool.js validate-production --json
```

This validates the canonical catalog, taxonomy review, locale overlay, and release
manifest as one bundle. Catalog version and product count must agree across all
resources. Localized name IDs, locale codes, preferred displays, cross-product
localized names, aliases, and product references are also checked.

### Validate an editorial release

```sh
node tools/catalog/catalog-tool.js validate-release \
  --input path/to/editorial-release.json
```

The validator applies the release to an in-memory copy of the current production
bundle and reports all errors before import. It rejects malformed records, existing
IDs submitted as adds, repeated operations, normalized alias collisions,
conflicting localized display names, missing Hebrew canonical names, invalid
keywords/locales, broken taxonomy, malformed or conflicting GTINs, invalid status,
and incorrect release metadata. It never merges records.

### Import an editorial release

```sh
# Full dry run; no files change
node tools/catalog/catalog-tool.js import-release \
  --input path/to/editorial-release.json

# Commit only after human review and validation
node tools/catalog/catalog-tool.js import-release \
  --input path/to/editorial-release.json \
  --write
```

The importer validates the current baseline, constructs the complete proposed
catalog in memory, validates the editorial and runtime representations, rejects a
stale filesystem snapshot, then transactionally replaces the canonical catalog,
locale overlay, release manifest, taxonomy review, and audit. Any validation or
write failure leaves the prior release intact.

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

### Commit a batch release

Use one batch when several reviewed mutations belong to one catalog release:

```sh
# Dry run the complete release
node tools/catalog/catalog-tool.js batch --input path/to/release.json

# Commit all mutations atomically as one catalog revision
node tools/catalog/catalog-tool.js batch \
  --input path/to/release.json \
  --write
```

The batch input is:

```json
{
  "releaseId": "wt-027b-wave-2",
  "operations": [
    {
      "operation": "add",
      "product": {
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
    },
    {
      "operation": "update",
      "id": "trash_bags",
      "patch": {
        "keywords": ["פח", "פסולת"]
      }
    },
    {
      "operation": "deactivate",
      "id": "obsolete_product"
    }
  ]
}
```

Supported batch operations are `add`, `update`, and `deactivate`. A stable product
ID may appear only once in a batch. `releaseId` is a stable lowercase ASCII release
identifier. The full batch is validated and written as one transaction; any invalid
operation prevents all catalog, review, and audit writes.

## Write safety

`add`, `update`, `deactivate`, and `batch` are dry runs unless `--write` is
explicitly present. A committed command is one release operation:

1. Validates the current catalog and refuses to mutate an invalid baseline.
2. Constructs the complete proposed catalog and review manifest in memory.
3. Increments `catalogVersion` exactly once for the release, regardless of the
   number of mutations in a batch.
4. Runs full validation before writing.
5. Rejects the operation if the catalog or review file changed since loading.
6. Transactionally replaces the catalog and review manifest and appends one audit
   JSON line per mutation.
7. Reloads and validates the committed files.

Each audit record contains the mutation, product ID, old/new release versions,
changed fields, timestamp, and catalog SHA-256 values. Batch records additionally
share the `releaseId`, release transition, before/after hashes, and contain
`batchIndex` and `batchSize`. Audit-entry count never determines `catalogVersion`.
Single-product write commands remain valid one-mutation releases and increment the
version once. Audit data contains no user shopping data, analytics, or credentials.

Always review the ordinary dry-run output or use `--json` before committing.
Commit the catalog, review manifest, audit entry, feedback update, and regression
tests together.

For WT-031B and later production releases, `import-release` is the only approved
write path. Its audit entry records the release ID, changed stable IDs, release
versions, generation date, product count, and checksums of every runtime artifact.

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

Tests execute the shared Hebrew normalization plus Wave 1 and Wave 2 search
fixtures, validate the 647-product release-5 production catalog, verify the
preserved release-4 ID fingerprint and immutable 331-entry audit prefix, and check
the 180-entry Wave 2 transaction. They also exercise every required validator
failure and perform single and transactional-batch dry runs and committed writes
only against temporary copies.

Before releasing catalog content, also run the complete iOS test suite, the unsigned
generic iOS build, and:

```sh
git diff --check
```

## Release workflow

Use `CATALOG_FEEDBACK.md` as the operational source for accepted work:

1. The editor records the request and evidence in `CATALOG_FEEDBACK.md`, searches
   existing names/aliases, confirms identity and taxonomy, and authors complete
   locale-aware records. Names, brands, aliases, and barcodes require a real
   editorial source; missing optional data stays absent.
2. Run `validate-release`. Resolve every error and review every warning; never
   auto-merge identities.
3. Run `import-release` without `--write` and review the proposed version, count,
   stable IDs, localized output, and taxonomy review.
4. Run `import-release --write` once. This is the Importer step and creates the
   accepted runtime resources.
5. Run `validate-production`; then run toolkit, Product Knowledge, search, and
   persistence compatibility tests plus the generic iOS build.
6. Review the generated audit entry and checksums, commit the editorial release,
   runtime resources, review, audit, feedback, and tests together.
7. Device-QA Hebrew/English search, display selection, aliases, duplicate handling,
   icons/categories, custom creation, scan/import readability, and cold startup.

The deployment flow is therefore:

`Editor -> Validator -> Importer -> ProductKnowledgeSnapshot -> Production App`.

Do not hand-edit the audit log. Do not use this toolkit to bypass canonical identity,
alias, brand, taxonomy, versioning, or feedback-review policy.
