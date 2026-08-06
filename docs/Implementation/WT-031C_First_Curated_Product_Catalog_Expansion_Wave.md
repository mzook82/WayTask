# WT-031C — First Curated Product Catalog Expansion Wave

Release target: WayTask 1.0.3  
Editorial release: `wt-031c-wave-1`  
Generation date: 2026-08-06

## Outcome

WT-031C advances the production catalog from schema 1/catalog 5 with 647 active
products to schema 1/catalog 6 with 700 active products. It adds 53 reviewed
product identities supported by existing repository material. No products were
generated, scraped, or added merely to approach the 300–500 target.

The repository did not contain an unused approved product source capable of
supporting another 300–500 identities. The release therefore stops at the 53
records that could be traced confidently. Twenty additional candidates remain in
the withheld-review report because a Hebrew canonical name, exact identity,
package/SKU evidence, or production editorial approval is missing.

## Editorial audit

The catalog 5 baseline contained:

- 647 active products, 780 aliases, and 1,750 keywords.
- 23 approved taxonomy categories and 22 subcategories; 22 categories and 21
  subcategories were used by products. `uncategorized` remained an unused defined
  fallback.
- Hebrew canonical-name coverage for all 647 products.
- 11 English localization records covering 6 products.
- 17 brand terms on 14 generic products; no structured brand fields, barcodes, or
  variant descriptors.
- A complete 647-product taxonomy review and no production-validator error or
  warning.

The only approved, not-yet-promoted product evidence in the repository was a
bounded set of materially distinct names embedded in existing aliases plus three
normative product examples. These represented the most credible coverage gaps in
bakery, produce, meat, pantry, drinks, cleaning, personal care, baby, pets,
pharmacy, household supplies, dairy, and snacks. Existing frozen coverage was
already comparatively broad, while repository material could not support safe new
electronics records.

## Release contents and identity decisions

The complete release is
`shared/catalog/releases/wt-031c-wave-1.json`. A guarded builder at
`tools/catalog/releases/build-wt031c-wave-1.js` records the source product and
asserts every transferred alias against the exact catalog 5/647 baseline. The
checked-in release JSON is the immutable import input; the builder intentionally
refuses to run against later catalog versions.

The release contains 99 operations:

- 53 `add` operations create materially distinct shopping identities.
- 46 `replace` operations retain their existing stable IDs while transferring
  names that now own a distinct identity or correcting three obvious editorial
  defects.
- 0 products are deactivated, redirected, removed, or replaced by another stable
  identity.

The three direct editorial corrections are:

- `baking_paper` gains the documented alias `נייר פרגמנט`.
- `strawberry_jam` drops the overbroad alias `ריבה`.
- `baby_snack_puffs` drops `חטיף תינוקות תפוח`, which incorrectly implied an
  unproven flavor.

Every new record has a stable ASCII ID, Hebrew canonical name, status, valid
taxonomy assignment, and repository provenance. Forty-seven additions carry a
variant descriptor because material, ingredient, form, species, or function
distinguishes them from the source generic concept. No brand, barcode, package
size, dosage, or unit was guessed. The single added brand term, `נוטלה`, is the
brand-led generic hazelnut-spread example already approved by the normative catalog
specification; it is not represented as an exact branded SKU.

English canonical displays were added only for `coffee` and `hazelnut_spread`,
using repository-approved bilingual/normative examples. All other new products
remain Hebrew-only rather than receiving invented translations.

## Coverage report

| Metric | Catalog 5 | Catalog 6 | Delta |
| --- | ---: | ---: | ---: |
| Active products | 647 | 700 | +53 |
| Hebrew canonical coverage | 647 (100%) | 700 (100%) | +53 |
| Products with verified English names | 6 | 8 | +2 |
| English localization records | 11 | 13 | +2 |
| Aliases | 780 | 731 | -49 |
| Keywords | 1,750 | 1,891 | +141 |
| Products with brand terms | 14 | 15 | +1 |
| Brand terms | 17 | 18 | +1 |
| Structured brand fields | 0 | 0 | 0 |
| Barcodes | 0 | 0 | 0 |
| Products with variant descriptors | 0 | 47 | +47 |
| Products with provenance | 0 | 99 | +99 |
| Validator errors / warnings | 0 / 0 | 0 / 0 | 0 / 0 |

The alias decrease is intentional: exact names that previously searched as aliases
of broader generic products were promoted to distinct product identities where the
shopping intent materially differed. Justified aliases were retained or added.
Search recall is preserved through the new canonical records and semantic family
metadata; quantity was not increased by duplicating the old aliases.

### Products added by category

| Category | Before | Added | After |
| --- | ---: | ---: | ---: |
| Baby | 36 | 1 | 37 |
| Bakery | 33 | 4 | 37 |
| Cleaning | 27 | 3 | 30 |
| Dairy | 38 | 1 | 39 |
| Drinks | 36 | 2 | 38 |
| Fruits & vegetables | 47 | 4 | 51 |
| Household | 40 | 6 | 46 |
| Meat & fish | 42 | 2 | 44 |
| Pantry | 108 | 16 | 124 |
| Personal care | 26 | 3 | 29 |
| Pets | 36 | 7 | 43 |
| Pharmacy | 26 | 1 | 27 |
| Snacks | 31 | 3 | 34 |

The other nine used categories are unchanged. Taxonomy schema/version and every
existing assignment remain compatible.

## Withheld review

`shared/catalog/releases/wt-031c-wave-1-withheld-review.json` records 20 excluded
candidates and the exact missing evidence. They include electronics whose repository
references provide only English intent, synthetic test-only names, future SKU
examples without brand/package/barcode proof, intentionally unmatched custom-product
fixtures, ambiguous generic identities, and brand-specific candidates without an
approved production record. None were silently imported.

## Import and validation evidence

The required production sequence completed in order:

1. `validate-release` accepted catalog 5 -> 6, product count 700, all 99 operations,
   with zero errors and zero warnings.
2. `import-release` dry run accepted the same proposal and left the catalog 5 files
   unchanged.
3. `import-release --write` committed the five-file bundle atomically and appended
   release audit version 3.
4. `validate-production` accepted the resulting 700-product bundle with zero errors
   and zero warnings.

The first 647 IDs retain the catalog 5 identity fingerprint
`31d11cc10d8aed1f7d27b210b8402f1883f87e1a334abe50ec2c2a3b8c0d53ff`.
The complete catalog 6 identity fingerprint is
`d953038e3b7416128ad7414c20341edf7c080eff331283f8200debcfc65dacd2`.
No prior ID was removed or renamed.

Automated validation completed:

- Node catalog-tool suite: 36 tests passed, 0 failed.
- Focused iOS catalog, search, autocomplete, identity, save/duplicate, migration,
  manifest, localization, icon, and compatibility suites: passed on an iPhone 17
  Pro simulator (`** TEST SUCCEEDED **`).
- The 5,000-record decode/index/search budget test passed in 0.963 seconds; its
  rapid consecutive-query/deduplication companion passed in 0.808 seconds.
- Generic unsigned iOS build: succeeded.
- `git diff --check`: succeeded.

The focused search coverage includes exact Hebrew, Hebrew prefix, verified English,
alias, category evidence, stable-ID deduplication, meaningful no-result custom
creation, one-character restrictions, and existing milk identity regression. It
also samples every category changed by this wave. No ranking or autocomplete
production code was changed.

Code inspection confirmed that the importer remains atomic, runtime metadata agrees
across catalog/localization/manifest resources, review coverage is 700/700, and the
catalog 6 resources are copied into the built app. Automated simulator tests were
run; no manual simulator walkthrough or physical-device validation is claimed.

## Search examples

- Exact Hebrew `קפה` resolves once to `coffee`; verified English `Coffee` resolves
  to the same ID.
- Hebrew prefix `אבקת כבי` resolves `laundry_powder` ahead of secondary evidence.
- Alias `קמח מכוסמת` resolves to canonical `קמח כוסמת` / `buckwheat_flour`.
- Category evidence `מכונת כביסה` can discover the applicable laundry products
  without changing identity.
- `שקיות כריכים` resolves once to `sandwich_bags`, despite multiple indexed terms.
- A meaningful unmatched term still exposes explicit custom-product creation.
- Short-query rules and existing `milk` identity behavior remain unchanged.

## Compatibility impact

There is no ProductState or persistence migration. Existing snapshots remain
readable and are not relocalized or converted. Stable-ID duplicate rules, aliases,
normalization, locale-aware ranking, short-query gating, custom-product confidence,
taxonomy/icon authority, Shopping, Map, Scanner, Camera, and destination behavior
are unchanged. The release changes production catalog data, localization data,
manifest metadata, review/audit evidence, and focused test expectations only.

## Device QA checklist

- Cold-launch twice and confirm the catalog 6 snapshot loads without fallback.
- Search representative new Hebrew exact names and prefixes in every changed
  category.
- Search `Coffee` and `Hazelnut Spread`; confirm English display and one stable ID.
- Search retained aliases such as `קמח מכוסמת` and `שקיות כריכים`.
- Verify category icons for new products and the generic unknown fallback.
- Add an existing and a new catalog product; verify exact/possible duplicate dialogs.
- Open previously saved products and lists, then relaunch to verify snapshot and
  quantity persistence.
- Create and cancel a custom product; verify query restoration and destination.
- Exercise scanned/imported products without converting them to catalog identities.
- Check Products- and Shopping-launched destinations plus Mission Map compatibility.
- Rapidly type one-, two-, and longer-character Hebrew/English queries and confirm
  responsiveness, stable ordering, and no stale-result flicker.

## Remaining risks and next editorial prerequisites

- Physical-device QA is still required.
- Structural validation cannot independently prove human editorial meaning; the 53
  identity splits should receive bilingual product-owner review on device.
- Catalog breadth, especially electronics and verified English coverage, is still
  constrained by source material rather than search-engine behavior.
- The next wave requires a human-reviewed source sheet containing Hebrew canonical
  names, identity rationale, taxonomy decisions, provenance, and optional verified
  English/brand/package/barcode fields. Candidate collisions must be reviewed before
  authoring, and the same validate -> dry run -> atomic import -> production
  validation gate must be used.
