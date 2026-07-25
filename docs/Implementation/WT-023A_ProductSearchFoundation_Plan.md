# WT-023A — Product Search and Suggestion Foundation

## 1. Executive Summary

WT-023A should add a small, deterministic, read-only search layer over the
validated Product Knowledge snapshot introduced by WT-022A. The search layer
will support Hebrew and English product-name queries, exact and prefix-based
matching, aliases, stable ranking, duplicate suppression, and bounded results.
It will remain independent of SwiftUI and of shopping-item persistence.

The current `ProductKnowledgeRepository` supports exact identifier lookups and
locale-aware name resolution, but it does not support catalog enumeration.
Search cannot be implemented correctly or efficiently by probing that API one
identifier at a time. The only required repository extension is therefore a
read-only `catalogSnapshot()` operation returning the existing immutable
`ProductKnowledgeSnapshot` value.

The proposed implementation consists of:

- one concrete `ProductKnowledgeSearch` actor;
- one search-result value model;
- internal normalization and index types owned by the search implementation;
- one repository snapshot method;
- focused correctness, determinism, concurrency, and performance tests.

No protocol is proposed for the search component. No database, SwiftData model,
network dependency, resource change, persistence migration, or UI change is
required. `ProductEntity` and existing shopping-item persistence remain
unchanged.

## 2. Current Source Audit

### 2.1 Product Knowledge domain

The current Product Knowledge domain is a Foundation-only, value-semantic
model:

- `ProductID`, `ProductNameID`, and `ProductCategoryID` are string-backed,
  `Sendable` identifiers.
- `ProductEntity` contains only `id`, `defaultNameID`, `primaryCategoryID`, and
  `status`.
- `ProductName` contains `id`, `productID`, `locale`, `kind`, `value`, and
  `isPreferred`.
- `ProductName.Kind` distinguishes canonical, localized display, and alias
  records.
- `ProductCategory` contains localized English and Hebrew names, an icon key,
  sort order, and status.

No normalized name, search token, ranking score, mutable usage signal, or
shopping-item relationship exists in `ProductEntity`. None is required for
WT-023A.

### 2.2 Repository API and enumeration

`ProductKnowledgeRepository` is currently a `Sendable`, nonisolated protocol
with asynchronous operations for:

- snapshot metadata;
- entity lookup by `ProductID`;
- names for a known product;
- category lookup by `ProductCategoryID`;
- preferred-name resolution for a product and locale;
- resolved icon lookup for a product.

It does not enumerate products, names, or categories. Although
`InMemoryProductKnowledgeRepository` is initialized from a complete
`ProductKnowledgeSnapshot`, it currently indexes that snapshot into private
dictionaries and does not expose the immutable catalog.

A new read-only catalog snapshot API is required. It should return the existing
`ProductKnowledgeSnapshot`; a second catalog DTO or a search-specific
repository protocol would duplicate the WT-022A model without adding useful
separation.

### 2.3 Snapshot and loader behavior

`BundledProductKnowledgeLoader` decodes and validates the bundled catalog, then
creates `ProductKnowledgeSnapshot`. The snapshot contains metadata, categories,
products, and names. The catalog validator establishes the referential
integrity needed by search:

- product and name identifiers are unique;
- every name references a product;
- every product has a valid default name and category;
- supported locale, preferred-name, and alias invariants hold;
- active catalog data is internally consistent.

Search should consume only a repository backed by a validated snapshot. It
should not decode JSON, repeat catalog validation, or read the bundle itself.

### 2.4 Locale fallback

The current repository resolves a display name in this order:

1. case-insensitive exact BCP-47 locale after replacing `_` with `-`;
2. requested primary language;
3. English;
4. the product's `defaultNameID`.

WT-023A search results must use the same display-name fallback order. Search
matching is broader than display-name resolution: every active canonical,
localized-display, and alias name may contribute a match.

### 2.5 Name and alias representation

Localized names and aliases are already first-class `ProductName` records.
Aliases do not create a second product identity. The bundled pilot catalog
contains 15 active products and 57 name records across English and Hebrew,
including deliberate prefix-oriented aliases such as `mil`, `dishw`, `נייר ס`,
and `אוכל ל`.

The pilot catalog therefore already contains enough representative data to
exercise exact, full-prefix, word-prefix, locale, alias, and duplicate
suppression behavior. WT-023A must not expand or rewrite the catalog.

### 2.6 Existing normalization behavior

`ProductKnowledgeCatalogValidator` currently uses trimmed, canonically
equivalent, lowercased comparisons for catalog integrity checks such as alias
collision detection. That comparison is a validation rule, not a search
contract.

WT-023A needs a stronger, explicitly versioned search normalization projection.
It must remain private to search and must not change validator behavior or
persist normalized values. A catalog can contain multiple name records that
normalize to the same search string; the search layer will collapse those
records to one result per `ProductID`.

### 2.7 Actor isolation and thread safety

The project enables Swift's default `MainActor` isolation. Product Knowledge
domain values and repository declarations explicitly use nonisolated,
`Sendable` contracts where needed, and
`InMemoryProductKnowledgeRepository` is an actor.

Search should be another actor, not a `@MainActor` object. It should lazily read
one immutable repository snapshot, build one immutable index, and serialize
access to that cached index. Search calls may originate from the main actor,
tests, or future background tasks without exposing mutable shared state.

### 2.8 Current test infrastructure

The `WayTaskTests` XCTest target is present in the shared `WayTask` scheme.
Current Product Knowledge coverage includes:

- bundled loader success and failure behavior;
- catalog validation rules;
- repository exact lookup and locale fallback behavior;
- concurrent repository reads and value-copy behavior;
- exact bundled-resource conformance;
- plain-domain value semantics;
- legacy manual-product creation characterization.

`ProductKnowledgeFixtureFactory` can construct valid synthetic snapshots.
Search tests can add local fixture builders for deliberate ranking collisions
and 15/100/500-product performance data without changing production resources.

### 2.9 Current Add Product flow

`ProductListView` currently owns Add Product presentation state. Its sheet:

- focuses and validates the manual product-name field;
- sends keyboard submission through the same save path as the Add button;
- calls `ShoppingListService.addManualProduct`;
- dismisses only after a successful save;
- preserves input and presents an error after failure.

`ShoppingListService.addManualProduct` creates the existing SwiftData `Product`
model. The manual flow does not load Product Knowledge, query
`ProductKnowledgeRepository`, or create/reference `ProductEntity` records.
Duplicate manual product names remain supported.

There is no Product Knowledge composition at the app root and no Product
Knowledge dependency in `ProductListView`. WT-023A must preserve that boundary:
it prepares an API for a later UI task but does not inject, instantiate, or call
search from the current Add Product flow.

### 2.10 Legacy Product Knowledge

The root-level `ProductKnowledge.swift` SwiftData model and
`ProductKnowledgeService.swift` support an older barcode/name cache used by
recognized-product behavior. They are distinct from the WT-022A catalog and are
not a search source for WT-023A. They require no modification.

### 2.11 Sources inspected

The audit used the following source-of-truth files:

- `docs/Product/SmartProductKnowledge.md`
- `docs/Product/ProductTaxonomy.md`
- `docs/Product/PilotProductCatalog.md`
- `docs/Specifications/SmartProductCreation.md`
- `docs/Implementation/WT-022A_ProductKnowledgeFoundation_Plan.md`
- `WayTask/ProductKnowledge/Application/ProductKnowledgeError.swift`
- `WayTask/ProductKnowledge/Application/ProductKnowledgeRepository.swift`
- `WayTask/ProductKnowledge/Data/BundledProductKnowledgeLoader.swift`
- `WayTask/ProductKnowledge/Data/InMemoryProductKnowledgeRepository.swift`
- `WayTask/ProductKnowledge/Data/ProductKnowledgeCatalog.swift`
- `WayTask/ProductKnowledge/Data/ProductKnowledgeCatalogValidator.swift`
- `WayTask/ProductKnowledge/Domain/ProductCategory.swift`
- `WayTask/ProductKnowledge/Domain/ProductEntity.swift`
- `WayTask/ProductKnowledge/Domain/ProductName.swift`
- `WayTask/Resources/ProductKnowledge/product-knowledge-catalog-v1.json`
- `ProductKnowledge.swift`
- `ProductKnowledgeService.swift`
- `ProductListView.swift`
- `ShoppingListService.swift`
- `WayTask/ContentView.swift`
- `WayTask/WayTaskApp.swift`
- `WayTaskTests/ProductKnowledge/BundledProductKnowledgeLoaderTests.swift`
- `WayTaskTests/ProductKnowledge/InMemoryProductKnowledgeRepositoryTests.swift`
- `WayTaskTests/ProductKnowledge/LegacyProductCreationCharacterizationTests.swift`
- `WayTaskTests/ProductKnowledge/ProductEntityTests.swift`
- `WayTaskTests/ProductKnowledge/ProductKnowledgeCatalogValidatorTests.swift`
- `WayTaskTests/ProductKnowledge/ProductKnowledgeResourceConformanceTests.swift`
- `WayTaskTests/ProductKnowledge/Support/ProductKnowledgeFixtureFactory.swift`
- `WayTask.xcodeproj/project.pbxproj`
- `WayTask.xcodeproj/xcshareddata/xcschemes/WayTask.xcscheme`
- `TESTING.md`

## 3. Search Contract

### 3.1 Supported inputs

Phase 1 accepts:

- a user query as `String`;
- a requested display locale as a BCP-47-like `String`;
- a requested result limit as `Int`.

The same operation supports Hebrew, English, and mixed-script input. It does
not infer a language and does not transliterate between scripts.

### 3.2 Searchable records

Search indexes all name records belonging to active products:

- canonical names;
- localized display names;
- aliases.

Inactive products are excluded. Category names, identifiers, icon keys,
barcodes, shopping history, and legacy Product Knowledge records are not
searchable in this phase.

### 3.3 Output and result limits

The default result count is 8, matching the future primary suggestion surface.
The hard maximum is 20, matching the repository-level cap described by the
product specification.

- `limit <= 0` returns an empty array.
- `1...20` returns at most the requested count.
- values above 20 are clamped to 20.

No caller can request an unbounded result set through the search API.

### 3.4 Empty-query behavior

If normalization produces no tokens, search returns an empty array and does not
build or fetch the catalog index.

This includes:

- the empty string;
- spaces, line breaks, and tabs only;
- punctuation or symbols only;
- combining marks only.

Recent and frequent products are intentionally not returned for an empty query.
Those require usage data and belong to a later suggestion-ranking task.

### 3.5 Determinism

For a fixed snapshot revision, query, locale, and limit, the result array must
be byte-for-byte equivalent at the value-model level across repeated and
concurrent calls.

Results must not depend on:

- JSON record order;
- array insertion order;
- dictionary iteration order;
- the user's current system locale;
- wall-clock time;
- shopping history;
- network state.

## 4. Normalization Contract

Search normalization version 1 applies the following ordered algorithm to both
the query and every candidate name:

1. Apply Unicode compatibility decomposition (NFKD).
2. Lowercase with the fixed `en_US_POSIX` locale. This is locale-independent
   case handling; it must not use the device's current locale.
3. Remove every scalar whose Unicode general category is nonspacing mark,
   spacing-combining mark, or enclosing mark.
4. Retain Unicode letter and decimal-number scalars.
5. Replace every maximal run of all other scalars with one ASCII space
   (`U+0020`).
6. Collapse repeated ASCII spaces and remove leading/trailing space.
7. Split tokens only on the resulting ASCII space.

The implementation should expose an internal pure normalizer so tests can pin
this contract without adding it to the public API.

### 4.1 English behavior

- Matching is case-insensitive.
- Composed and decomposed diacritics are equivalent.
- Latin accents are ignored: for example, `café` normalizes to `cafe`.
- Compatibility-width variants normalize consistently.
- Punctuation separates words rather than concatenating them.

No stemming, plural reduction, phonetic comparison, or typo correction is
performed.

### 4.2 Hebrew behavior

- Hebrew has no case conversion; letters remain unchanged.
- Niqqud, cantillation, and other combining marks are removed.
- Punctuation such as maqaf and geresh becomes a word separator.
- Final and non-final letter forms remain distinct.
- No transliteration, root extraction, spelling correction, or grammatical
  normalization is performed.

An English transliteration can match a Hebrew product only when that
transliteration exists as an approved alias record in the catalog.

### 4.3 Normalization examples

| Input | Normalized value |
|---|---|
| `  Paper   Towels  ` | `paper towels` |
| `DISHWASHING-LIQUID` | `dishwashing liquid` |
| `Café` | `cafe` |
| `חָלָב` | `חלב` |
| `נייר־סופג` | `נייר סופג` |
| `***` | empty |

Normalized values are derived in memory and are never written to the bundled
catalog, `ProductEntity`, SwiftData, or shopping-item persistence.

## 5. Matching Rules

Each normalized candidate name is evaluated against the normalized query in
the following quality classes.

### 5.1 Exact match

The candidate and query normalized strings are equal.

Examples:

- `milk` matches `Milk`;
- `חָלָב` matches `חלב`;
- a query exactly matching an alias is an exact alias match.

### 5.2 Full-name prefix

The candidate normalized string begins with the complete normalized query, and
the strings are not equal.

Examples:

- `pap` matches `paper towels`;
- `paper t` matches `paper towels`;
- `נייר ס` matches `נייר סופג`.

The query may end partway through its final token.

### 5.3 Word-prefix match

Let query tokens be `Q` and candidate tokens be `C`. A word-prefix match exists
when there is a start index `i` in `C` such that:

- enough candidate tokens remain for every query token; and
- for every query token `Q[j]`, `C[i + j]` starts with `Q[j]`.

The smallest matching `i` is the match's word-start index.

Examples:

- `towe` matches `paper towels` at word index 1;
- `soap` matches `dish soap` at word index 1;
- `wash up l` matches `washing up liquid` at word index 0.

The rule does not support:

- a substring beginning inside a candidate token;
- token reordering;
- skipped candidate tokens between query tokens;
- edit distance or fuzzy similarity.

For example, `ilk` does not match `milk`, and `towels paper` does not match
`paper towels`.

### 5.4 Alias behavior

Alias records use exactly the same normalization and three quality classes as
canonical and localized-display names. An alias does not receive a standalone
result and never changes product identity.

An exact alias may rank above a prefix match on another product because match
quality is the first ranking dimension. Within the same match-quality class,
display-capable names rank above aliases.

## 6. Ranking Rules

Ranking is a stable ascending lexicographic tuple. No opaque or learned score is
used.

### 6.1 Best matching name per product

For every active product, select one best matching `ProductName` using:

1. match quality:
   - exact;
   - full-name prefix;
   - word prefix;
2. name authority:
   - the record selected as the result's localized display name;
   - another preferred canonical or localized-display record;
   - another canonical or localized-display record;
   - alias;
3. locale affinity:
   - exact requested normalized BCP-47 locale;
   - same requested primary language;
   - English;
   - any other locale;
4. word-start index, with exact and full-name-prefix matches using zero;
5. normalized matched-name Unicode-scalar count, shorter first;
6. normalized matched-name Unicode-scalar lexicographic order;
7. `ProductNameID.rawValue` Unicode-scalar lexicographic order.

The final identifier comparison makes selection total even when duplicate name
records have otherwise identical search projections.

### 6.2 Ordering product results

After one match has been selected per product, order products using:

1. selected match quality;
2. selected name authority;
3. selected locale affinity;
4. selected word-start index;
5. selected normalized matched-name scalar count;
6. selected normalized matched-name scalar lexicographic order;
7. normalized localized display-name scalar lexicographic order;
8. `ProductID.rawValue` Unicode-scalar lexicographic order.

Comparisons must use Unicode scalar order, not `localizedCompare`, current
locale collation, hash values, or source-array order. The tuple is the complete
ranking contract.

### 6.3 Display-name selection

Before ranking, each product's result display name is resolved using the
repository's existing fallback contract:

1. exact requested locale;
2. primary language;
3. English;
4. `defaultNameID`.

Tests must verify parity between search display names and
`ProductKnowledgeRepository.preferredName(productID:locale:)` for exact,
regional, unsupported, and underscore-form locales.

## 7. Result Model

Create a Foundation-only, immutable, `Sendable`, `Equatable`, and `Identifiable`
value:

```swift
nonisolated enum ProductSearchMatchQuality: Int, Sendable {
    case exact
    case fullNamePrefix
    case wordPrefix
}

nonisolated struct ProductSearchResult: Identifiable, Equatable, Sendable {
    let product: ProductEntity
    let displayName: ProductName
    let category: ProductCategory
    let iconKey: String
    let matchedName: ProductName
    let matchQuality: ProductSearchMatchQuality

    var id: ProductID { product.id }
}
```

The exact access level should follow the current Product Knowledge module
conventions. The model deliberately exposes semantic match quality rather than
an integer score. Callers must not be able to couple UI behavior to internal
ranking weights.

`matchedName` makes alias and localized-name matches observable for tests and
future presentation decisions. It does not imply that alias text must be shown
by the future UI.

The category is nonoptional because validated catalog snapshots guarantee the
product-category reference. `iconKey` is resolved while building the index and
follows the current repository's category-icon behavior.

## 8. Proposed API

### 8.1 Repository addition

Add one operation to the existing repository:

```swift
nonisolated protocol ProductKnowledgeRepository: Sendable {
    // Existing operations remain unchanged.
    func catalogSnapshot() async -> ProductKnowledgeSnapshot
}
```

`InMemoryProductKnowledgeRepository` should retain the immutable constructor
snapshot in addition to its lookup indexes and return that value from
`catalogSnapshot()`. Swift value semantics ensure callers cannot mutate
repository state.

The method is intentionally read-only and nonthrowing. Loader and validator
errors occur before repository construction under the existing WT-022A flow.

### 8.2 Search component

Add one concrete actor:

```swift
actor ProductKnowledgeSearch {
    static nonisolated let defaultResultLimit = 8
    static nonisolated let maximumResultLimit = 20

    init(repository: any ProductKnowledgeRepository)

    func suggestions(
        matching query: String,
        locale: String,
        limit: Int = 8
    ) async -> [ProductSearchResult]
}
```

The actor should:

- normalize the query first;
- return immediately for an empty normalized query or nonpositive limit;
- load `catalogSnapshot()` once, on the first nonempty search;
- build and cache an immutable in-memory search index;
- search only that cached index on later calls;
- deduplicate and sort before applying the clamped limit.

No new search protocol, dependency container, publisher, callback API, or
SwiftUI environment key is proposed. A protocol can be introduced later only
if a second production implementation or a real substitution boundary appears.

### 8.3 Snapshot lifetime

A `ProductKnowledgeSearch` instance represents one immutable repository
revision. It does not poll for catalog changes. A future catalog replacement
should construct a new repository and search actor, making revision changes
explicit and avoiding hidden cache invalidation.

## 9. Files to Create

### Production

- `WayTask/ProductKnowledge/Domain/ProductSearchResult.swift`
  - `ProductSearchMatchQuality`
  - `ProductSearchResult`
- `WayTask/ProductKnowledge/Application/ProductKnowledgeSearch.swift`
  - concrete search actor;
  - internal normalization contract;
  - internal indexed-name and rank-key values;
  - locale display-name resolution;
  - matching, deduplication, stable sorting, and limit enforcement.

### Tests

- `WayTaskTests/ProductKnowledge/ProductKnowledgeSearchTests.swift`
  - normalization, matching, locale, ranking, deduplication, limits,
    determinism, and concurrency.
- `WayTaskTests/ProductKnowledge/ProductKnowledgeSearchPerformanceTests.swift`
  - synthetic 15, 100, and 500-product cold-index and warm-query measurements.

The Xcode project currently uses synchronized source groups. The implementer
must verify target membership after adding the files, but no
`project.pbxproj` edit is expected or authorized by this plan.

## 10. Files to Modify

- `WayTask/ProductKnowledge/Application/ProductKnowledgeRepository.swift`
  - add the read-only `catalogSnapshot()` requirement.
- `WayTask/ProductKnowledge/Data/InMemoryProductKnowledgeRepository.swift`
  - retain and return its immutable source snapshot.
- `WayTaskTests/ProductKnowledge/InMemoryProductKnowledgeRepositoryTests.swift`
  - prove the returned snapshot matches constructor data and remains
    value-isolated under concurrent reads.

No change is planned for:

- `ProductEntity.swift`, `ProductName.swift`, or `ProductCategory.swift`;
- the bundled JSON catalog or catalog validator;
- `ProductListView.swift` or `ShoppingListService.swift`;
- legacy Product Knowledge files;
- SwiftData models, schemas, or migrations;
- project configuration or resources.

## 11. Ordered Implementation Sequence

1. Add a repository test that describes immutable full-snapshot enumeration.
2. Add `catalogSnapshot()` to `ProductKnowledgeRepository`.
3. Retain the constructor snapshot in
   `InMemoryProductKnowledgeRepository` and implement the new operation.
4. Run all existing Product Knowledge tests to confirm exact lookup, fallback,
   concurrency, and resource behavior are unchanged.
5. Add `ProductSearchMatchQuality` and `ProductSearchResult`.
6. Add the internal normalization implementation and pin every normalization
   rule with tests.
7. Add lazy immutable-index construction over active products and all their
   name records.
8. Add display-name resolution with parity tests against the repository.
9. Add exact, full-name-prefix, and word-prefix matching.
10. Add best-name selection, one-result-per-product suppression, and the
    complete stable rank tuple.
11. Add result-limit and empty-query behavior.
12. Add randomized source-order and concurrent-call determinism tests.
13. Add pilot-catalog integration tests using the real bundled snapshot.
14. Add 15/100/500-product performance measurements.
15. Run the complete unit-test suite and a clean app build.
16. Confirm `ProductListView`, resources, persistence, and project settings
    have no diff before requesting implementation approval.

## 12. Automated Test Plan

### 12.1 Normalization matrix

| Case | Required assertion |
|---|---|
| empty input | normalizes empty and returns no results |
| spaces/tabs/newlines | collapses and trims to empty |
| repeated internal whitespace | becomes one ASCII space |
| English case | upper/lower variants are equivalent |
| composed/decomposed Latin accent | both match the same candidate |
| Hebrew niqqud/cantillation | pointed and unpointed forms are equivalent |
| compatibility-width input | normalizes to the same candidate |
| hyphen/maqaf/apostrophe/punctuation | acts as a token separator |
| punctuation only | returns no results |
| digits | remain searchable |
| Hebrew final letters | remain distinct |
| mixed Hebrew/English | preserves both scripts and token order |

### 12.2 Matching matrix

Test English and Hebrew examples for:

- exact canonical name;
- exact localized-display name;
- exact alias;
- one-token full-name prefix;
- multi-token full-name prefix;
- second-word prefix;
- multiword word-prefix alignment;
- no token-internal substring match;
- no reordered-token match;
- no skipped-token match;
- no fuzzy or typo match;
- inactive product exclusion.

Pilot-resource integration cases should include representative aliases such as
`mil`, `dishw`, `נייר ס`, and `אוכל ל` without changing the resource.

### 12.3 Ranking matrix

Construct collision fixtures that independently prove:

1. exact precedes full-name prefix;
2. full-name prefix precedes word prefix;
3. resolved display name precedes other preferred display-capable names;
4. display-capable names precede aliases at equal match quality;
5. exact requested locale precedes primary-language affinity;
6. primary-language affinity precedes English fallback;
7. English fallback precedes other locales;
8. lower word-start index wins;
9. shorter normalized matched name wins;
10. normalized matched-name scalar order breaks the next tie;
11. normalized display-name scalar order breaks the next product tie;
12. `ProductID.rawValue` is the final product tie-breaker;
13. `ProductNameID.rawValue` makes same-product match selection total.

Repeat the ranking suite after reversing and deterministically shuffling
products, names, and categories. Expected result identifiers must remain
identical.

### 12.4 Duplicate suppression and limits

Verify:

- canonical, localized, and alias matches for one product yield one result;
- two records on one product with the same normalized string yield one result;
- identical display text on distinct product IDs remains two results;
- default limit returns at most 8;
- limits from 1 through 20 are honored;
- values above 20 are clamped;
- zero and negative limits return no results;
- limiting occurs after full deduplication and sorting.

### 12.5 Locale fallback

For representative English and Hebrew products, compare the search result's
`displayName.id` with the repository preferred-name result for:

- `en`;
- `he`;
- a regional locale such as `he-IL`;
- underscore input such as `en_US`;
- case variants;
- an unsupported locale;
- a fixture requiring default-name fallback.

### 12.6 Repository and thread-safety tests

Verify:

- `catalogSnapshot()` returns all constructor metadata, categories, products,
  and names;
- mutating a caller-owned array copy cannot change later repository results;
- concurrent snapshot calls return equivalent values;
- concurrent first searches do not build divergent indexes;
- at least 64 concurrent identical searches return the same ordered IDs;
- searches with different queries and locales remain isolated.

### 12.7 Regression suite

The complete existing unit-test suite must remain green, including:

- loader and validator tests;
- bundled resource conformance;
- existing repository behavior;
- legacy manual-product characterization;
- current shopping and product-list regression tests.

No test should require network access, current time, random unseeded ordering,
or a simulator UI.

## 13. Performance Plan

### 13.1 Complexity

For `P` products and `N` name records:

- one-time index construction: `O(P + N)`;
- each query: `O(N × T)` where `T` is the small token-prefix comparison cost;
- deduplication: `O(N)` using a product-ID keyed best-match map;
- sorting: `O(M log M)` where `M <= P`;
- retained memory: `O(P + N)`.

At the Phase 1 scale, a linear in-memory scan is simpler and sufficiently fast.
A trie, persisted index, database query layer, or n-gram index is not justified.

### 13.2 Acceptance expectations

Measure with optimized code on a currently supported iPhone-class device or
equivalent Release simulator, using deterministic synthetic catalogs with an
average of four names per product:

| Products | Cold first nonempty search, including index build | Warm-query p95 |
|---:|---:|---:|
| 15 | at most 10 ms | at most 2 ms |
| 100 | at most 20 ms | at most 5 ms |
| 500 | at most 50 ms | less than 20 ms |

Each warm measurement should include at least 100 searches drawn from exact,
prefix, word-prefix, Hebrew, English, hit-heavy, and no-result queries. Report
median and p95. Exclude bundle loading and JSON validation because repository
construction precedes search; include normalization, matching, deduplication,
sorting, model creation, and result limiting.

XCTest performance tests should track regressions, but noisy Debug/CI timings
should not use hard wall-clock assertions. The Release-device numbers above are
the approval gate. If 500-product warm p95 misses the gate, profile before
adding an index structure; do not preemptively expand the architecture.

## 14. UI Integration Boundary

WT-023A stops at the asynchronous, Foundation-only search API. It does not:

- instantiate the loader, repository, or search actor at app startup;
- inject search into `ProductListView`;
- change Add Product state, focus, validation, save, alert, or dismissal;
- display a suggestion list;
- turn a result into a SwiftData `Product`;
- create or link a `ProductEntity`;
- alter duplicate manual-product behavior.

A future UI task may own one `ProductKnowledgeSearch` instance in an
appropriate composition root and call:

```swift
let results = await search.suggestions(
    matching: query,
    locale: localeIdentifier,
    limit: 8
)
```

That UI must treat results as read-only suggestions. Selection-to-persistence
semantics require a separate approved contract because the current manual
shopping `Product` model has no Product Knowledge identity field.

## 15. Risks and Mitigations

### Stronger normalization than catalog validation

Different source names may collapse to the same search projection even though
the current validator accepts them.

Mitigation: retain every record in the index, choose the best match
deterministically, and deduplicate by `ProductID`. Keep validator changes out of
WT-023A.

### Locale-resolution drift

Search could accidentally display a different localized name than repository
lookups.

Mitigation: document the same fallback order and add direct parity tests across
exact, regional, underscore, English-fallback, and default-fallback locales.

### Ranking coupled to source order

Dictionary or JSON ordering could make suggestions unstable.

Mitigation: use complete lexicographic rank keys and test reversed and shuffled
snapshots.

### Alias dominance

An alias could outrank an intended display name unexpectedly.

Mitigation: match quality is primary, but name authority is the next dimension.
This permits a deliberate exact alias to beat a weak prefix while ensuring
display-capable names win equal-quality ties.

### Main-actor work

Future UI calls could perform catalog scanning on the main actor.

Mitigation: implement search as its own actor with immutable cached state.
Measure end-to-end search time and keep SwiftUI outside the implementation.

### Hidden catalog refresh expectations

A mutable future repository could make a cached index stale.

Mitigation: define one search instance as one repository revision. Replace the
instance explicitly when catalog revision changes.

### Scope expansion

Future-product documentation includes recents, fuzzy search, AI, barcode,
creation, and richer ranking signals.

Mitigation: enforce negative tests for unsupported substring/fuzzy behavior and
keep usage, network, persistence, and UI dependencies out of the proposed
files.

## 16. Rollback Plan

WT-023A is additive and has no migration.

To roll it back in a dedicated Git change:

1. remove `ProductSearchResult.swift`;
2. remove `ProductKnowledgeSearch.swift`;
3. remove the two search test files;
4. remove `catalogSnapshot()` from `ProductKnowledgeRepository`;
5. remove retained-snapshot storage and the method implementation from
   `InMemoryProductKnowledgeRepository`;
6. remove only the new snapshot tests from
   `InMemoryProductKnowledgeRepositoryTests`.

After rollback, run the existing suite and build. The WT-022A Product Knowledge
foundation, bundled catalog, legacy Product Knowledge, manual Add Product flow,
SwiftData stores, and shopping items remain intact. There is no data downgrade,
resource rollback, cache cleanup, or user-data repair.

## 17. Approval-Gate Matrix

| Gate | Required evidence | Status before implementation |
|---|---|---|
| Scope | No fuzzy, AI, cloud, barcode, inventory, UI, migration, or catalog-expansion work | Defined |
| Domain stability | No change to `ProductEntity` or shopping persistence | Defined |
| Enumeration | Existing snapshot returned through one read-only repository method | Defined |
| Normalization | Version 1 ordered Unicode contract and Hebrew/English cases pinned by tests | Defined |
| Matching | Exact, full-name prefix, and contiguous word-prefix only | Defined |
| Ranking | Complete semantic tuple with scalar/ID tie-breakers | Defined |
| Duplicates and limits | One result per ProductID; default 8; hard cap 20; empty query returns none | Defined |
| Thread safety | Search actor, immutable snapshot/index, concurrent determinism tests | Defined |
| Repository regression | Existing lookup, locale, loader, validator, and resource tests remain green | Implementation gate |
| Search correctness | Full normalization, matching, ranking, limit, and pilot-catalog matrix passes | Implementation gate |
| Performance | Release measurements meet 15/100/500 expectations | Implementation gate |
| Build | Clean app build and complete unit-test suite pass | Implementation gate |
| UI isolation | `ProductListView` and current Add Product behavior have no diff | Implementation gate |
| Persistence and resources | No SwiftData, project, resource, or catalog diff | Implementation gate |

No design blocker remains. Implementation approval should be revoked if the
existing snapshot cannot be returned with value semantics, if locale parity
cannot be maintained, or if meeting the 500-product target requires a
persistence or UI change. None of those conditions is present in the audited
source.

## 18. Final Recommendation

Implement WT-023A as the concrete read-only actor and immutable result API
defined above. Add only the repository snapshot operation needed for
enumeration, preserve all existing domain and persistence models, and use the
test and performance gates before any later UI integration begins.

APPROVED FOR IMPLEMENTATION
