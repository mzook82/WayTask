# WT-031A — Smart Product Knowledge Foundation

Release target: WayTask 1.0.3  
Implementation date: 2026-08-06

## Outcome

WT-031A activates one Product Knowledge representation and an indexed search path
for the production catalog without changing persistence or filling production with
generated content. The release-5 catalog remains 647 curated, active records with
the same stable-ID fingerprint. A version-bound localization overlay adds eleven
English name/alias records for six existing identities. A deterministic test-only
fixture proves decode, indexing, ranking, deduplication, and rapid-query behavior
with 5,000 products and 20,000 searchable names.

## Audited production path before WT-031A

1. **Catalog source.** `WayTask/Resources/product_catalog_he.json` was and remains
   the production source. It is schema 1, catalog version 5, taxonomy version 1,
   locale `he-IL`, with 647 active products. `shared/catalog/taxonomy.json` owns
   23 stable categories and 22 stable subcategories.
2. **Loading and decoding.** `WayTaskProductionRuntimeView.init` synchronously
   called `ProductCatalogService.loadProductsOrEmpty()`. The service supported the
   canonical schema and a retired compatibility format, decoded to
   `CatalogProduct`, and validated the complete document. Taxonomy loaded through
   `ProductCatalogTaxonomyLoader`.
3. **Identity.** `CatalogProduct.id` was the stable catalog identity. A selected
   catalog product persisted that identity as `catalogProductIDRawValue`; custom
   products retained only their own product UUID. Catalog snapshots stored display,
   locale, category, and icon information separately.
4. **Canonical/display ownership.** `canonicalName` belonged to the catalog.
   Persisted products owned their current user-facing `name`; catalog selections
   also carried immutable display snapshots. Display strings were not the durable
   catalog key.
5. **Normalization.** Hebrew search, Product Knowledge search, duplicate policy,
   service matching, and barcode lookup had several similar but separate
   normalizers. This created drift risk around punctuation, final Hebrew letters,
   whitespace, and formatted barcodes.
6. **Search.** The active `ProductCatalogSearch` precomputed normalized records but
   scanned every product and all terms for every query. A newer 15-product
   `ProductKnowledgeSearch` pilot also scanned its complete record array. The
   autocomplete view model already canceled the prior task and used a request
   generation to reject stale results, but the search work itself was linear.
7. **Aliases.** Production aliases were arrays on `CatalogProduct`. The inactive
   Product Knowledge pilot represented aliases as separate `ProductName` records.
8. **Category and icon resolution.** Stable category/subcategory IDs lived in the
   shared taxonomy. App display/icon metadata was keyed by those IDs through
   `ProductCatalogCategoryMetadata`, and SF Symbols were resolved centrally by
   `ProductKnowledgeIconResolver`. Unknown meaning fell back to
   `uncategorized`/`product.generic`/`tag.fill`.
9. **Identity evidence fields.** The persisted product graph already retained
   optional brand, barcode, product type, flavor, package size, and package type.
   Catalog records held category, subcategory, aliases, keywords, brand terms,
   activity/replacement state, and stable ID, but had no general rich in-memory
   type for semantic key, variant descriptors, package descriptor, unit, GTIN, or
   provenance.
10. **Acquisition paths.** Catalog and autocomplete selection went through
    `AddProductSaveCoordinator`; manual, scan, camera/AI review, and import paths
    went through the Product State V4 acquisition authority. Exact requested UUID,
    catalog ID, or barcode could resolve an existing product. A scanned/imported or
    custom product was not silently promoted to catalog identity.
11. **Localization.** UI copy used normal app localization. The production catalog
    was Hebrew-first. A separate 15-product pilot demonstrated `ProductName`
    records in English and Hebrew, but it was not the active production catalog.
12. **Startup and memory.** Root-view initialization decoded the catalog each time
    a new root value was constructed. Search records were retained in memory, and
    every query allocated/ranked a full linear scan. No production index statistic
    or 5,000-record baseline existed.
13. **Duplicate/compatibility rules.** Same product UUID was exact. Same catalog ID,
    barcode, or normalized display name was duplicate evidence, with conflicting
    catalog ID, barcode, or brand preventing name-only merging. Persistence V1–V4
    migration and reopen tests protected existing products and shopping lists.

## Root causes and scalability risks

- Two search/model generations existed, but the scalable Product Knowledge path
  was not connected to production.
- Per-query full scans scale with products multiplied by aliases/keywords and can
  amplify rapid typing cost.
- Normalization drift can cause missed barcode/name matches or inconsistent
  duplicate/icon/category inference.
- Hebrew-first strings and aliases were attached directly to catalog records, so
  adding languages without a separate name authority would distort identity.
- Optional brand/variant/package/GTIN/provenance concepts had no common catalog
  knowledge representation.
- Ranking behavior differed between search generations and older personalization
  could affect tie ordering. The WT-031A contract requires textual match tier,
  canonical name, then stable ID, independent of acquisition/creation source.
- No automated 5,000-record decode/index/query evidence existed.

## Implemented Product Knowledge contract

`ProductEntity` is the stable identity record. It supports stable ID, default name
ID, category/subcategory IDs, semantic key, generic/branded identity kind, optional
brand, variant descriptors, package descriptor, unit, barcodes/GTINs, icon key,
catalog version, provenance, and active state. These fields are optional where a
generic type does not need them.

`ProductName` owns display and search text independently of `ProductEntity`. It
stores stable name ID, product ID, locale, kind (`canonical`, localized display,
alias, or keyword), original value, and display preference. Original text is never
replaced by its normalized key.

Identity rules are:

- A stable catalog ID is exact identity.
- A normalized GTIN/barcode is probable/strong identity evidence.
- An alias resolves to its owning catalog ID and never creates another result.
- Equal normalized display text alone is possible-duplicate evidence.
- Brand, semantic type, variant descriptors, package descriptor, and unit are part
  of exact catalog-knowledge identity validation.
- Persisted custom/scanned/imported records are never converted based only on a
  name or alias.

Generic type, branded product, variant, and package remain separate concepts. For
example `milk`, a manufacturer's milk, `lactose free`, and `1 L` do not collapse
into one display string identity.

## Normalization contract

`ProductKnowledgeNormalizer` is the authority used by both compatibility search
normalizers, Product Knowledge indexing, duplicate matching, custom matching,
barcode repository lookups, service matching, and icon inference.

Search normalization applies compatibility decomposition, locale-aware lowercase,
diacritic removal for the search key, Hebrew final-letter folding, whitespace
trimming/collapse, and conservative punctuation/hyphen/apostrophe separation or
removal. It does not stem, singularize, pluralize, translate, or fuzzily merge
terms. Barcode normalization trims and removes whitespace/hyphens from numeric
GTIN-like values. The original display value remains untouched.

## Alias and multilingual contract

Aliases are individual locale-tagged `ProductName` records. Exact and prefix alias
matches participate in ranking but return the owning product once, using the
preferred display record for the requested locale. An exact alias also suppresses
the contextual custom-product action because it is already an exact catalog match.

`product-knowledge-localizations-v1.json` is schema 1 and explicitly bound to
catalog version 5. It proves English plus Hebrew resolution for existing IDs:

| English query | Hebrew query | Stable product ID |
| --- | --- | --- |
| Bread | לחם | `bread_white` |
| Milk | חלב | `milk_3_percent` |
| Eggs | ביצים | `eggs` |
| Rice | אורז | `rice_white` |
| Water | מים | `mineral_water` |
| Apples | תפוחים | `apple` |

The overlay contains eleven English display/alias records and no new product.
Missing translations fall back by exact locale, primary language, English, then
the catalog default. A malformed or version-mismatched overlay is ignored safely;
the validated base catalog remains searchable. No online translation is used.

## Search index and ranking contract

`ProductKnowledgeSearch` owns an immutable, lazily cached in-memory index. It is
prewarmed once from a root-level shared service rather than decoded or normalized
from SwiftUI body evaluation. Its exact, full-prefix, token-prefix, category-prefix,
and trigram maps produce bounded candidate sets. Trigram fallback is evaluated only
when higher-quality indexes find no candidate. Results are deduplicated naturally
by product index/stable identity.

Ranking is deterministic:

1. Exact canonical/display name.
2. Exact alias.
3. Canonical/display full prefix.
4. Alias full prefix.
5. Contiguous token-prefix match.
6. Category relevance.
7. Conservative substring/keyword fallback.

Ties use normalized canonical display name, then stable product ID. Creation source
and usage source do not change this order. Each result retains tier, match type,
record authority, original matched value, normalized matched value, and locale for
future highlighting.

Autocomplete preserves the existing empty-query behavior (idle, no catalog result,
no custom action), keeps existing results visible while replacing them, cancels the
prior task, and uses a generation guard so stale completions cannot publish. A
meaningful unmatched query continues to expose contextual custom creation.

## Categories and icons

The shared taxonomy remains the category identity authority. The adapter creates
search categories from the same stable IDs used by catalog records. App-specific
display/icon metadata remains keyed only by those IDs, so search, persistence
snapshots, scanner/manual/import inference, and `ProductKnowledgeIconResolver`
agree on meaning without source-specific recategorization. Unknown products retain
the existing generic fallback. Persisted category snapshots are not rewritten.

## Catalog format, compatibility, and failure behavior

The production catalog was already a maintainable versioned bundled JSON document,
so it was not replaced or rewritten. `ProductCatalogKnowledgeAdapter` converts the
validated schema-1/catalog-5 document and optional schema-1 localization overlay to
one `ProductKnowledgeSnapshot`. Stable IDs are copied, never inferred from strings.

The existing Node authoring toolkit remains the transactional import path. It
validates schema, versions, stable IDs, normalized canonical/alias collisions,
taxonomy references, replacement loops, review coverage, and audit history. The
new Swift foundation validator adds deterministic error/warning reporting for
duplicate IDs, canonical-name absence, invalid/missing categories, duplicate
locale/name definitions, alias collisions, barcode conflicts, invalid locale and
normalized keys, unindexable entries, and indistinguishable exact identities. It
reports only; it never repairs or merges.

Unsafe base-catalog decode/validation fails closed to unavailable catalog search.
One malformed record cannot silently replace or partially shadow another. Optional
unknown rich fields decode to empty/nil compatibility values. No persistence schema
or destructive migration was added.

## Production content and validation results

- Before WT-031A: 647 active products, 780 aliases, 1,750 keywords, 17 brand terms.
- After WT-031A: 647 active products with the same IDs and content; eleven localized
  names/aliases reference six existing IDs.
- Stable-ID fingerprint before/after:
  `31d11cc10d8aed1f7d27b210b8402f1883f87e1a334abe50ec2c2a3b8c0d53ff`.
- Node catalog validator: 0 errors, 0 warnings.
- Swift production foundation validator: 0 errors. Warning count is captured by
  `WT031A_PRODUCTION_METRICS` in the focused XCTest result.
- No generated brands, barcodes, package data, scraped data, or filler product
  names were added.

## Performance fixture and budgets

The test-only fixture deterministically generates 5,000 product identities and
20,000 localized/search name records (one English canonical, one Hebrew display,
and two aliases per identity). It is compiled only into `WayTaskTests` and is not a
production resource.

Measured on an arm64 iPhone 17 Pro simulator running iOS 26.5:

| Measurement | Result | Broad regression budget |
| --- | ---: | ---: |
| Encoded fixture | 3,585,277 bytes | Diagnostic only |
| JSON decode + snapshot | 59.37 ms | < 3,000 ms |
| Index build | 746.41 ms | < 5,000 ms |
| 100 exact searches | 76.44 ms | < 3,000 ms |
| Maximum measured search | 1.33 ms | Diagnostic baseline |
| Indexed UTF-8 deterministic lower bound | 8,756,451 bytes | < 100 MiB |
| Full benchmark test | 1.00–1.14 s across final runs | Diagnostic baseline |
| 64 rapid concurrent queries | 0.84–1.90 s across full runs | Stable/deduplicated |

The memory value is a deterministic lower-bound estimate of indexed strings and
integer postings, not process RSS. Physical-device Instruments measurement remains
required before WT-031B content ships.

## Persistence and UX compatibility

- No SwiftData schema changed and no migration was introduced.
- Existing V1–V4 products and shopping lists continue through their existing
  compatibility/migration paths.
- Catalog identity and display/category/icon snapshots remain readable.
- Custom, scanned, camera-reviewed, AI-reviewed, and imported products remain custom
  unless they already carry exact catalog/barcode evidence through the existing
  authority.
- Same catalog ID is now explicitly exact shopping-list identity; barcode is
  probable evidence; equal name is possible evidence; conflicting variant evidence
  is not silently merged.
- Catalog add, custom creation, query preservation, shopping destination context,
  duplicate dialogs, quantity/progress, list management, Mission Map, camera,
  scanner, and the dark/orange presentation were not redesigned.

## Before versus after

| Concern | Before | After |
| --- | --- | --- |
| Production runtime search | Linear `ProductCatalogSearch` scan | Shared, prewarmed `ProductKnowledgeSearch` index |
| Normalization | Several local implementations | One central authority plus compatibility adapters |
| Aliases | Product arrays; active search-specific behavior | Locale-tagged name records resolving one identity |
| Languages | Hebrew production strings; inactive pilot | Versioned locale overlay on production identities |
| Ranking | Legacy scoring/popularity behavior | Explicit seven-tier deterministic contract |
| Rich product type | Split across catalog/persistence | Optional in-memory knowledge fields with stable identity |
| Validation | Base schema/Node/iOS validators | Base validators plus rich foundation error/warning report |
| Scalability evidence | No 5,000-record fixture | 5,000 products/20,000 names with measured budgets |
| Persistence | Existing Product State V4 | Unchanged |

## Automated and simulator validation

- Unsigned generic iOS production build: passed.
- Focused WT-031A XCTest result: 29/29 before the final production-metrics test was
  added; the final focused rerun records the authoritative current count.
- Catalog toolkit: 21/21 Node tests passed.
- Bounded simulator regression excluding only the unrelated long
  `ProductStatePerformanceBaselineTests`: 809/810 passed. The sole failure was the
  test harness reporting a temporary source-fixture mutation in
  `testStartupRepairDoesNotRecreateMissingProduct`; that exact test then passed in
  isolation (0.492 s) and had also passed in the earlier full run.
- The attempted all-tests run executed for 812.77 s and passed its catalog, search,
  scanner, migration, map, and completed performance cases, but Xcode stalled while
  finalizing a restarted simulator worker. It was explicitly interrupted; this is
  not reported as a complete pass.
- Code inspection confirmed release root, acquisition, persistence, duplicate,
  icon/category, and autocomplete paths.
- Simulator validation here is automated XCTest only; no exploratory simulator UI
  session is claimed.
- No physical-device validation was performed.

## Files changed

Runtime and compatibility:

- `WayTask/ProductionRuntimePresentation.swift`
- `WayTask/ProductCatalog/CatalogProduct.swift`
- `WayTask/ProductCatalog/ProductCatalogSearch.swift`
- `WayTask/ProductKnowledge/Application/ProductKnowledgeRepository.swift`
- `WayTask/ProductKnowledge/Application/ProductKnowledgeSearch.swift`
- `WayTask/ProductKnowledge/Data/InMemoryProductKnowledgeRepository.swift`
- `WayTask/ProductKnowledge/Data/ProductCatalogKnowledgeAdapter.swift`
- `WayTask/ProductKnowledge/Data/ProductKnowledgeFoundationValidator.swift`
- `WayTask/ProductKnowledge/Domain/ProductEntity.swift`
- `WayTask/ProductKnowledge/Domain/ProductKnowledgeNormalizer.swift`
- `WayTask/ProductKnowledge/Domain/ProductName.swift`
- `WayTask/ProductKnowledge/Domain/ProductSearchResult.swift`
- `WayTask/ProductKnowledge/Presentation/AddProductAutocompleteViewModel.swift`
- `WayTask/ProductKnowledge/Presentation/ProductKnowledgeIconResolver.swift`
- `WayTask/ProductState/Application/ShoppingListDuplicatePolicy.swift`
- `WayTask/ProductState/Persistence/ProductStateRepositories.swift`
- `WayTask/Persistence/AddProductSaveCoordinator.swift`
- `ProductKnowledgeService.swift`
- `ShoppingListService.swift`
- `WayTask/Resources/ProductKnowledge/product-knowledge-localizations-v1.json`

Tests and evidence:

- `WayTaskTests/ProductKnowledge/ProductAutocompleteViewModelTests.swift`
- `WayTaskTests/ProductKnowledge/ProductKnowledgeSearchTests.swift`
- `WayTaskTests/ProductKnowledge/ProductKnowledgeFiveThousandRecordTests.swift`
- `WayTaskTests/ProductKnowledge/SmartProductKnowledgeFoundationTests.swift`
- `WayTaskTests/ProductKnowledge/Support/ProductKnowledgeScalabilityFixture.swift`
- `WayTaskTests/ShoppingUX/ShoppingUXActionClarityTests.swift`
- `docs/Implementation/WT-031A_Smart_Product_Knowledge_Foundation.md`

## Physical-device QA checklist

1. Cold-launch on the lowest supported device; record launch and first-search signpost
   or Instruments time and peak/resident memory.
2. In Products, search one character, two characters, exact Hebrew canonical,
   English alias, Hebrew alias, prefix, multi-token prefix, and no-result terms.
3. Rapidly type, erase, and replace a query; verify no stale result flash, list
   flicker, keyboard loss, or delayed overwrite.
4. Verify the six bilingual pairs resolve the listed stable identities and preserve
   the requested-locale display name.
5. Verify an exact alias does not offer a duplicate custom product; verify a real
   unmatched term still offers contextual custom creation with exact query text.
6. Add a catalog product to Products and a selected shopping list; cancel/change
   selection and confirm query/destination state is preserved.
7. Exercise same-product, same-catalog-ID, barcode, equal-name, and different-brand
   duplicate dialogs; verify legitimate size/flavor/form variants remain separate.
8. Relaunch with an existing production store and verify products, lists, quantities,
   progress, catalog snapshots, removed products, and history remain intact.
9. Exercise barcode scan, camera review, AI review, and import/manual creation; verify
   custom records are not silently catalog-linked and icons/categories are consistent.
10. Exercise Mission Map, store selection, shopping session progress, list creation,
    rename/delete, and the current dark/orange visual state.
11. Test English and Hebrew app-language changes, right-to-left layout, VoiceOver
    labels, long names, and empty/unavailable catalog behavior.
12. Run Instruments Allocations and Time Profiler with a staged 5,000-record resource
    before approving WT-031B for production.

## WT-031B curated import plan and prerequisites

Prerequisites:

- Named editorial owner and review policy for every source row; documented license
  or first-party authorship; no scraped commercial dataset.
- A stable-ID allocation manifest. IDs are lowercase ASCII, never reused, and are
  chosen from product meaning rather than display spelling or locale.
- Each row declares generic/branded identity, semantic key, approved category and
  optional subcategory, canonical Hebrew name, reviewed aliases, and only factual
  optional brand/variant/package/GTIN data.
- Locale policy defines one preferred display record per available locale. Missing
  translations remain missing; they are not machine-filled.
- Human review of normalized-name, alias, semantic-duplicate, category, and barcode
  reports before a release is written.

Import sequence:

1. Normalize the curated source into the existing catalog batch format and a
   catalog-version-matched localization overlay. Generate only structure/IDs from
   reviewed source rows, never product-name filler.
2. Run `catalog-tool find` for canonical names and every alias, then
   `check-candidate` for representative rows.
3. Stage all additions/updates in a versioned release JSON. Run
   `node tools/catalog/catalog-tool.js batch --input <release>` without `--write`.
4. Run both validators and review every warning. Correct the source; do not auto-merge.
5. Commit through the same batch command with `--write`, which advances the catalog
   version once, updates the review manifest, and appends per-record audit entries.
6. Advance the localization overlay's `catalogVersion`, add deterministic stable
   name IDs, and rerun the Swift foundation validator to catch cross-locale aliases.
7. Add shared Hebrew/English query fixtures for representative categories, variants,
   collisions, and long-tail no-result cases. Preserve the release-5 ID fingerprint
   as an immutable prefix/identity set.
8. Run Node validation/tests, focused iOS contracts, the 5,000-record benchmark,
   full native regressions, and `git diff --check`.
9. Stage the actual curated candidate resource on simulator and physical low-end
   hardware. Record cold load/index, p50/p95 search latency, RSS/peak memory, rapid
   typing, bilingual behavior, and accessibility.
10. Ship only after editorial, engineering, privacy/legal, simulator, and physical
    device sign-off. Keep rejected or unreviewed rows outside production.

## Remaining risks

- Production coverage is still 647 products; the bilingual proof covers six
  identities and is not complete English or Hebrew coverage.
- The memory figure is a deterministic lower bound, not RSS; device Instruments
  evidence is required at real WT-031B size.
- The base authoring CLI validates the Hebrew-first document; cross-locale overlay
  validation currently runs in Swift tests. WT-031B should add a platform-neutral
  overlay/import validator before content editors work at full scale.
- The legacy `ProductCatalogSearch` remains for compatibility and regression tests,
  though release runtime now uses Product Knowledge. It should be removed only after
  device QA confirms no fallback consumer remains.
- App-specific icon metadata remains separate from the platform-neutral taxonomy by
  design; stable category IDs are the join and require parity tests for every new
  category.
- Semantic near-duplicates cannot be decided safely by normalization alone and will
  continue to require human review.
- The complete parallel Xcode suite exposed an existing simulator-worker/finalization
  instability. Bounded suites are reliable, but CI should isolate the long Product
  State performance baselines from ordinary regressions.
