# WT-031B — Curated Product Catalog Editorial Pipeline

Release target: WayTask 1.0.3

## Outcome

WT-031B adds a production editorial gate without adding or generating products.
The shipped catalog remains version 5 with 647 active curated identities. The new
pipeline validates a complete proposed release before atomically emitting runtime
resources and does not change `ProductState` persistence.

## Architecture audit

The active app path is:

1. `ProductCatalogService` decodes the bundled Hebrew canonical catalog through the
   legacy/canonical compatibility decoder and validates IDs, taxonomy, aliases,
   status, and replacement rules.
2. `BundledProductKnowledgeLocalizationLoader` decodes the catalog-version-matched
   locale overlay.
3. `ProductCatalogKnowledgeAdapter` joins stable products, localized names, taxonomy,
   icons, variants, package data, barcodes, status, and provenance into one
   `ProductKnowledgeSnapshot`.
4. `ProductKnowledgeFoundationValidator` validates the joined snapshot before the
   indexed `ProductKnowledgeSearch` becomes available.
5. `ProductState` stores compatible product snapshots and stable catalog references;
   it does not decode the editorial format.

The prior authoring CLI already validated the Hebrew runtime catalog and taxonomy,
but it did not own localized product records or one release manifest. Its direct
write operations could advance the canonical catalog without advancing the locale
overlay. WT-031B closes that release-level consistency gap.

## Editorial product model

`product-editorial-release.schema.json` defines complete added/replaced records:

- Stable product ID.
- Locale-keyed canonical names; `he-IL` is required and English is optional.
- Locale-tagged display names, aliases, keywords, brand terms, and legacy names.
- Optional brand, semantic key, variant descriptors, package descriptor, unit,
  provenance, and metadata.
- Approved category and optional controlled subcategory.
- Validated GTIN/barcode list.
- Popularity and explicit active/inactive status with compatible replacement and
  deprecation metadata.

The stable ID remains the identity. Localized strings, aliases, brand, variant, and
package information are evidence or descriptors and never rename the identity.

## Versioning and import transaction

Every editorial release declares editorial schema version, exactly-next catalog
version, taxonomy version, real ISO generation date, proposed product count, stable
release ID, supported locales, and operations.

The importer:

1. Validates the current production catalog, review, localization overlay, and
   release manifest.
2. Validates all editorial fields and applies operations only to an in-memory copy.
3. Validates the resulting complete editorial identity/name/barcode graph.
4. Emits the compatible canonical catalog and localization overlay in memory.
5. Validates the complete emitted runtime bundle.
6. Rejects stale source hashes.
7. Atomically replaces catalog, localization, manifest, taxonomy review, and audit.
8. Reloads and validates the committed bundle.

No partial catalog is visible if any record or artifact fails.

## Validation contract

Hard errors include malformed/duplicate stable IDs, missing Hebrew canonical names,
invalid or conflicting localized names, duplicate aliases, invalid keywords/locales,
invalid categories, orphan or mis-parented subcategories, malformed or conflicting
GTINs, invalid variants/status/replacements, count/version mismatches, and records
that cannot be normalized or indexed. The validator reports stable codes and never
merges records. Warnings remain non-blocking human-review observations from the
canonical validator, such as an active product assigned to the defined unknown
fallback.

## Production workflow

`Editor -> Validator -> Importer -> ProductKnowledgeSnapshot -> Production App`

The editor must have real evidence for every name, alias, brand, and barcode. Run
`find`/`inspect`, author a versioned release, run `validate-release`, dry-run
`import-release`, review the generated representations, commit once with
`import-release --write`, run `validate-production`, then run native validation and
device QA. Production direct writes through the older batch/per-product commands are
blocked.

## Compatibility

- No `ProductState` or persistence schema changes.
- Existing catalog version-5 IDs and product order are unchanged.
- Existing Hebrew/English aliases and WT-031A/A.1/A.2 ranking behavior are unchanged.
- No Shopping, Map, Scanner, Camera, icon, category, or duplicate-policy changes.
- The release manifest is a startup consistency gate and adds an optional generation
  date to in-memory Product Knowledge metadata only.

## Catalog expansion prerequisites

For each future curated wave:

1. Close feedback/evidence and taxonomy decisions before authoring.
2. Prefer modest reviewable batches; do not set a numeric quota.
3. Use deterministic stable IDs and complete Hebrew names; add English only when
   editorially verified.
4. Add only evidence-backed aliases/keywords, real brands, and check-digit-valid
   barcodes.
5. Add search fixtures for representative canonical, alias, localized, short-query,
   no-result, and duplicate cases.
6. Require zero importer and production-bundle errors, review warnings, run WT-031
   suites and the generic build, then complete physical-device QA before release.

## Remaining risks

- Editorial correctness still requires human review; structural validation cannot
  prove that a name, alias, brand, barcode, or taxonomy decision is factually right.
- Most of the current 647 products do not yet have English display coverage; absence
  is supported and is not fabricated by the importer.
- Large future waves can reveal semantic near-duplicates that intentionally remain
  warnings/manual decisions rather than automatic merges.
- Physical-device validation is still required for the bundled startup gate and for
  Hebrew/English search behavior after each imported wave.
