# WT-024A — Product Autocomplete UI Integration Plan

**Status:** Planning complete; UI implementation is defined, but production
catalog-selection saving remains gated by Smart Product Creation persistence  
**Scope:** Architecture and implementation plan only  
**Last updated:** 2026-07-24  
**Related search plan:** `WT-023A_ProductSearchFoundation_Plan.md`  
**Related UX contract:** `ProductSearchUXContract.md`

---

## 1. Executive Summary

WayTask can integrate the implemented `ProductKnowledgeSearch` actor into Add
Product without changing search ranking, the bundled catalog, or the reliable
custom-product save path.

The recommended UI architecture is:

- construct one `ProductKnowledgeSearch` for the app session at the app
  composition root;
- pass an explicit available/unavailable search dependency to Add Product;
- extract the current inline Add Product sheet into a focused view;
- give that view a `@MainActor` state model that owns query, search, selection,
  stale-result protection, and confirmation state;
- use the existing search normalizer to decide whether a query activates
  catalog search;
- call the existing `ShoppingListService.addManualProduct` only after the user
  explicitly selects the custom-product action;
- keep catalog selection transient until an approved catalog-aware persistence
  handler exists.

Two small presentation gaps must be closed before the UI can meet the approved
UX contract:

1. `ProductSearchResult` must include the localized category display name. It
   currently exposes only `categoryID`.
2. The iOS UI must add a complete semantic-icon-key-to-SF-Symbol resolver with
   a generic fallback. No such resolver exists today.

The current `Product` SwiftData model has no catalog Product ID field.
Consequently, a selected catalog result must **not** be sent through
`addManualProduct`. Doing so would discard catalog identity while presenting
the interaction as a catalog selection. The authoritative UX and data-model
documents explicitly prohibit that implication.

WT-024A UI work may be implemented and tested behind an integration gate, but
production autocomplete must remain disabled until the separately approved
Smart Product Creation persistence task provides a catalog-aware save
operation that retains:

- the stable catalog `ProductID`; and
- the user-visible display-name snapshot.

Until that gate is satisfied, WayTask must continue presenting the current
manual Add Product experience unchanged.

## 2. Scope

### 2.1 This plan defines

- Product Knowledge construction and dependency ownership;
- Add Product query and selection state;
- immediate asynchronous search behavior;
- suggestion, no-result, slow, and unavailable presentation;
- catalog and custom explicit-selection behavior;
- keyboard, focus, clear, and Change behavior;
- localized category and semantic icon presentation;
- preservation of photo and manual-save state;
- accessibility and RTL requirements;
- unit, integration, UI, and manual regression coverage;
- exact production and test files expected to change;
- the catalog-persistence shipping gate.

### 2.2 This plan does not authorize

- implementation during WT-024A planning;
- a SwiftData schema or migration change;
- adding a catalog ID to `Product`, `ShoppingListEntry`, or `ShoppingItem`;
- catalog-linked saving through the manual-product API;
- a known-product duplicate policy;
- changes to search normalization, matching, ranking, limits, or aliases;
- changes to the bundled Product Knowledge JSON;
- catalog expansion;
- recent/frequent suggestions;
- fuzzy, substring, transliteration, AI, barcode, or network search;
- search analytics or raw-query collection;
- product-specific icon content;
- changes to legacy `ProductKnowledge` or `ProductKnowledgeService`.

## 3. Authoritative Inputs Reviewed

The source audit reviewed:

- `docs/Implementation/WT-023A_ProductSearchFoundation_Plan.md`
- `docs/Specifications/ProductSearchUXContract.md`
- `docs/Product/SmartProductKnowledge.md`
- `docs/Product/ProductTaxonomy.md`
- `docs/Product/PilotProductCatalog.md`
- `docs/Architecture/ProductKnowledgeArchitecture.md`
- `docs/Architecture/ProductEntityDataModel.md`
- all production code under `WayTask/ProductKnowledge`
- all tests under `WayTaskTests/ProductKnowledge`
- the bundled revision-1 catalog
- `ProductListView.swift`
- `ShoppingListService.swift`
- `WayTask/Models.swift`
- `WayTask/WayTaskApp.swift`
- `WayTask/ContentView.swift`
- `WayTaskDesignSystem.swift`
- legacy `ProductKnowledge.swift`
- legacy `ProductKnowledgeService.swift`
- `TESTING.md`
- `WayTask.xcodeproj/project.pbxproj`
- the shared `WayTask` scheme.

`docs/Implementation/WT-011A_ManualProductCreationReliability_Plan.md` is not
present. The implemented flow and
`LegacyProductCreationCharacterizationTests.swift` provide the current
reliability contract instead.

## 4. Current Implementation Audit

### 4.1 Implemented search foundation

`ProductKnowledgeSearch` is a concrete actor with:

```swift
func suggestions(
    matching query: String,
    locale: String,
    limit: Int = 8
) async -> [ProductSearchResult]
```

The implementation:

- normalizes before loading the index;
- returns immediately for normalization-empty or nonpositive-limit queries;
- lazily obtains one immutable catalog snapshot;
- caches one immutable search index;
- indexes active products and all approved names and aliases;
- returns at most eight results by default and clamps callers at twenty;
- returns one result per `ProductID`;
- is deterministic across concurrent and reordered inputs;
- uses no network or SwiftData;
- does not throw once it has been constructed.

The search actor's synchronous scan is not cancellation-aware internally.
That is acceptable at the approved catalog sizes, but it means the UI must
logically invalidate stale results even after canceling its caller task.

### 4.2 Actual result model

The implemented result is a flattened UI-oriented value:

```swift
struct ProductSearchResult {
    let productID: ProductID
    let displayName: String
    let secondaryName: String?
    let categoryID: ProductCategoryID
    let iconKey: String
    let matchedRecordAuthority: ProductSearchRecordAuthority
    let matchType: ProductSearchMatchType
    let matchedLocale: String
}
```

This differs from the illustrative WT-023A result that contained full
`ProductEntity`, `ProductName`, and `ProductCategory` values. The production
type is the integration interface and should not be renamed or expanded back
to the earlier illustrative shape merely for UI work.

The flattened result already provides:

- app-locale product display text;
- a secondary matched-name cue only when it differs;
- stable product and category IDs;
- the resolved semantic icon key;
- test-observable match metadata.

It does not provide the localized category label required by the UX contract.

### 4.3 Catalog loading and availability

`BundledProductKnowledgeLoader.load()` is synchronous and throwing. It reads,
decodes, and validates the bundled catalog before repository construction.

`InMemoryProductKnowledgeRepository` and `ProductKnowledgeSearch` are
nonthrowing after successful construction. Therefore:

- catalog missing, unreadable, decode, version, and validation failures belong
  to app composition;
- the UI needs an available/unavailable dependency value;
- normal search completion is success with zero or more results;
- the UI must not invent per-query thrown failures that the current API cannot
  produce.

If the search API becomes throwing later, a current-query failure can map to
the same unavailable presentation without changing the state contract.

### 4.4 Bundled catalog

Runtime revision 1 contains:

- schema version 1;
- catalog revision 1;
- taxonomy version 1.0;
- 15 active Product Concepts;
- 15 categories;
- 57 English/Hebrew canonical, display, and alias name records;
- all 15 approved semantic category icon keys.

No runtime resource change is required for autocomplete.

### 4.5 Current Add Product view

`ProductListView` owns the complete Add Product sheet inline. It currently
holds:

- the typed name;
- selected photo item and loaded image data;
- presentation and save-error flags;
- name-field focus;
- the `ShoppingListService`.

Current behavior is:

1. open the sheet at medium or large detent;
2. focus the name field on appearance;
3. trim leading/trailing whitespace and newlines for validation and save;
4. allow Return with `.done` to call the same save path as the button;
5. call `ShoppingListService.addManualProduct`;
6. report a persistence failure and keep all state;
7. reset and dismiss only after a successful save.

The sheet is embedded in an outer `ScrollView`, already giving a suitable
scroll owner for future suggestion rows.

### 4.6 Current manual persistence

`ShoppingListService.addManualProduct` creates a new SwiftData `Product` with:

- a new UUID;
- caller-supplied name and optional image data;
- `source = .manual`;
- no brand, category, barcode, Product Knowledge ID, or shopping membership.

It inserts and saves synchronously. Duplicate names create independent
products.

The UI currently trims the name before calling the service even though the
service itself preserves caller-supplied whitespace. The UI-level trimming
behavior is the one autocomplete must preserve for custom creation.

After a successful manual save, `ProductListView` also:

- increments manual-product beta diagnostics;
- signals the shopping list changed;
- marks the current shopping plan stale;
- resets the form;
- dismisses the sheet.

Those side effects remain part of custom save success.

### 4.7 Persistence incompatibility

The current models contain no:

- `catalogProductID`;
- `productConceptID`;
- catalog display-name snapshot;
- catalog revision;
- catalog relationship.

`ShoppingListEntry.productID` points to the UUID of the existing user-owned
`Product`, not to Product Knowledge.

Saving a catalog result through `addManualProduct` would retain only a display
string and lose the selected `ProductID`. It is therefore not an acceptable
catalog save implementation.

### 4.8 App composition

`WayTaskApp` currently constructs:

- `AppStateManager`;
- `LocationManager`;
- the SwiftData model container through a scene modifier.

`ContentView` constructs `ProductListView()` with no Product Knowledge
dependency. No repository or search actor is currently owned by the app.

Constructing the search inside `ProductListView.body`, the sheet builder, or a
SwiftUI `onAppear` would allow view recreation to rebuild the repository and
discard the cached search index. Search must instead be constructed once at
the app root.

### 4.9 Localization and icons

The app currently has no explicit localized string catalog for Add Product and
the visible Add Product strings are English.

The Product Knowledge catalog contains bilingual category names, but the
search result exposes only `categoryID`.

No production type maps Product Knowledge semantic icon keys such as
`product.dairy` or `product.cleaning` to iOS visuals.

### 4.10 Test and Xcode structure

The repository has:

- one `WayTaskTests` unit-test target;
- no `WayTaskUITests` target or XCUITest source directory;
- Product Knowledge loader, validator, repository, domain, resource,
  characterization, correctness, concurrency, and performance tests;
- a shared scheme that runs `WayTaskTests`;
- no existing automated Add Product UI tests.

Both the `WayTask` directory and `WayTaskTests` directory use Xcode
file-system-synchronized groups. New production files placed under `WayTask`
and new unit tests placed under `WayTaskTests` should acquire target membership
without manual project-file entries. Root-level source files such as
`ProductListView.swift` remain explicit project entries.

Adding a new UI-test target would require an intentional project and shared
scheme change.

The audited source builds successfully for generic iOS Debug with code signing
disabled and derived data outside the repository.

## 5. Required Integration Decisions

### 5.1 One search actor per app session

Construct and retain one search actor at `WayTaskApp` initialization:

```text
BundledProductKnowledgeLoader
  -> validated ProductKnowledgeSnapshot
  -> InMemoryProductKnowledgeRepository
  -> ProductKnowledgeSearch
```

This preserves the actor's one-snapshot/one-index lifetime and makes initial
catalog failure explicit.

### 5.2 Explicit availability, not an optional error leak

Add a small value such as:

```swift
nonisolated enum ProductKnowledgeSearchAvailability: Sendable {
    case available(ProductKnowledgeSearch)
    case unavailable
}
```

The root catches and reports the technical loader error, then stores
`.unavailable`. The UI sees only availability and displays the approved
nontechnical copy.

Do not carry `Error`, resource paths, validation violations, or technical
descriptions into SwiftUI state.

### 5.3 Constructor injection

Pass availability explicitly:

```text
WayTaskApp
  -> ContentView
    -> ProductListView
      -> AddProductSheet
```

Do not use a global singleton, service locator, or SwiftUI environment object
for this one feature dependency.

### 5.4 Add Product owns UI state; search owns search behavior

The UI state model may use `ProductSearchNormalizer` to determine:

- whether search activates;
- whether two raw edits have the same normalized query;
- whether clearing should invalidate results.

It must not reproduce matching, ranking, alias, locale, deduplication, or limit
logic. All catalog suggestions come from `ProductKnowledgeSearch`.

### 5.5 No new search protocol is required

Production code has one search implementation. The state model should accept
`ProductKnowledgeSearch` directly.

For deterministic state-model tests, provide an internal initializer that
accepts an asynchronous suggestion closure. This creates a narrow test seam
for delayed and reordered completions without adding a public protocol to the
search foundation.

## 6. Target Architecture

```text
WayTaskApp
  |
  | load + validate once
  v
ProductKnowledgeSearchAvailability
  |
  v
ContentView -> ProductListView -> AddProductSheet
                                    |
                                    v
                       AddProductAutocompleteViewModel
                          |                     |
               async suggestions        explicit choice
                          |                     |
                          v                     v
              ProductKnowledgeSearch   AddProductCreationRequest
                                                |
                           +--------------------+--------------------+
                           |                                         |
                           v                                         v
                 custom-product handler                  catalog-product handler
                  existing reliable path                    future prerequisite
                           |                                         |
                           v                                         v
             ShoppingListService.addManualProduct     catalog-aware persistence
```

The view does not access the Product Knowledge repository or bundled resource.
The search actor does not access SwiftUI or SwiftData. The commit boundary does
not alter search state.

## 7. Search Result Presentation Extension

### 7.1 Required field

Extend the current flattened result with:

```swift
let categoryDisplayName: String
```

`ProductKnowledgeSearch` should resolve it while building each result using the
same requested application locale passed to `suggestions`.

For taxonomy version 1.0:

1. use Hebrew when the normalized requested primary language is `he`;
2. otherwise use English;
3. retain a UI-localized generic category fallback for defensive presentation
   if an invalid test snapshot lacks a category.

Production validated snapshots always contain the referenced category.

Keep `categoryID` as stable semantic metadata. Do not make the UI maintain a
second dictionary of taxonomy labels and do not add repository access to the
view.

### 7.2 Required parity tests

Pin category display for:

- `en`;
- `en_US`;
- `he`;
- `he-IL`;
- locale case variants;
- an unsupported locale, which uses English;
- every bundled category referenced by a result.

No ranking or identity field changes are required.

### 7.3 Match metadata visibility

`matchedRecordAuthority`, `matchType`, and `matchedLocale` remain available for
tests and future presentation decisions. The UI must not display or announce:

- match type;
- alias authority;
- score;
- locale code;
- Product ID;
- category ID.

The row uses `secondaryName` exactly as returned. It must not independently
decide whether an alias or cross-language name should be shown.

## 8. Semantic Icon Resolution

Add a pure iOS presentation resolver that maps all taxonomy keys and returns a
generic fallback for unknown input.

Recommended Phase 1 map:

| Semantic key | iOS system image |
|---|---|
| `product.dairy` | `drop.fill` |
| `product.bread` | `birthday.cake.fill` |
| `product.fruit` | `carrot.fill` |
| `product.meat` | `fork.knife` |
| `product.pantry` | `shippingbox.fill` |
| `product.drink` | `cup.and.saucer.fill` |
| `product.frozen` | `snowflake` |
| `product.snack` | `popcorn.fill` |
| `product.household` | `house.fill` |
| `product.cleaning` | `sparkles` |
| `product.personalcare` | `figure.stand` |
| `product.pharmacy` | `cross.case.fill` |
| `product.baby` | `figure.child` |
| `product.pet` | `pawprint.fill` |
| `product.generic` | `shippingbox.fill` |

The exact visual review may revise an SF Symbol without changing semantic keys
or search data. The resolver must:

- cover every key in the bundled taxonomy;
- return `shippingbox.fill` for unknown keys;
- contain no category labels;
- remain UI-only;
- be unit tested for completeness;
- render the icon as decorative beside text.

No asset-catalog or bundled-image change is needed.

## 9. Add Product State Model

### 9.1 State owner

Extract a `@MainActor` `ObservableObject` named
`AddProductAutocompleteViewModel`, following the project's existing
view-model style.

It owns:

- raw query;
- the last searched normalized query;
- current results;
- search availability;
- current search generation;
- current search task;
- 150 ms slow-status task;
- editing/selection mode;
- save-in-progress state if needed to prevent repeat activation;
- save-error presentation state.

`PhotosPickerItem` remains SwiftUI presentation state. Loaded `Data?` may
remain in the sheet because it is not search state.

### 9.2 Explicit selection type

Use an explicit selection enum:

```swift
enum AddProductSelection: Hashable, Sendable {
    case catalog(result: ProductSearchResult, preselectionQuery: String)
    case custom(name: String, preselectionQuery: String)
}
```

The preselection raw query is retained so Change can restore exactly what the
user typed, including internal whitespace and capitalization.

### 9.3 Search presentation type

Use semantic state rather than several contradictory booleans:

```swift
enum ProductSuggestionPhase: Equatable {
    case idle
    case searchingSlow
    case results
    case noMatch
    case unavailable
}
```

Results live in a separate immutable array or as associated state. Invariants:

- `idle` has no interactive catalog rows;
- `searchingSlow` has no stale rows;
- `results` has one or more current-query rows;
- `noMatch` has no catalog rows and is not an error;
- `unavailable` has no catalog rows and never blocks custom selection.

### 9.4 Derived values

The state model exposes:

- `trimmedCustomName`;
- `isManualNameValid`;
- `normalizedQuery`;
- `showsCustomAction`;
- `canConfirm`;
- `selectedCatalogResult`;
- `selectedCustomName`.

Manual validity remains:

```text
trim whitespace and newlines
  -> valid when the remaining string is nonempty
```

Search activation remains:

```text
normalize with ProductSearchNormalizer
  -> active when one or more normalized letters/digits remain
```

These are intentionally different. For example, `***` is a valid custom name
under the current manual contract but is empty for catalog search. It should
show the custom action without calling search.

## 10. State Transition Contract

| Event | Required state transition |
|---|---|
| Sheet opens | Editing, empty query, no rows, Add disabled, name field focused |
| Whitespace-only input | No search, no custom action, Add disabled |
| Valid punctuation-only input | No search, custom action visible, Add disabled until custom is selected |
| First normalized character | Clear old rows, start immediate search, keep custom action visible |
| Equivalent raw edit with same normalized query | Do not search again; update custom-action text from the current trimmed raw query |
| Different normalized query | Invalidate generation, cancel caller task, clear rows, start new search |
| Search returns current nonempty results | Show at most eight rows plus custom action |
| Search returns current empty results | Show No catalog match plus custom action |
| Search exceeds 150 ms | Show Searching products status plus custom action |
| Catalog unavailable | Show unavailable copy plus custom action |
| Old search finishes | Ignore it by generation and normalized-query checks |
| Clear button or deletion to empty | Cancel/invalidate, clear rows and selection, preserve photo, focus empty field |
| Catalog row tapped | Store catalog selection and raw preselection query; dismiss keyboard; show summary; enable Add |
| Custom row tapped | Store trimmed custom name and raw preselection query; dismiss keyboard; show custom confirmation; enable Add |
| Change tapped | Clear selection, restore raw preselection query, re-run only if needed, refocus field |
| Return in text field | Dismiss keyboard; do not select and do not save |
| Add tapped with no selection | No action |
| Custom save succeeds | Run existing success side effects, reset entire form, dismiss |
| Custom save fails | Preserve query, selection, photo, and sheet; show existing save alert |
| Sheet closes | Cancel tasks and discard the entire form |

## 11. Query Lifecycle

### 11.1 No debounce

The artificial debounce is exactly zero milliseconds.

On every raw query edit:

1. compute current manual validity;
2. normalize using `ProductSearchNormalizer`;
3. update custom-action copy from the trimmed raw value;
4. stop if the normalized query is unchanged;
5. invalidate the prior generation;
6. cancel prior search and slow-status tasks;
7. clear old result rows immediately;
8. if normalized empty, enter idle;
9. if search unavailable, enter unavailable;
10. otherwise call `suggestions` with the environment locale and limit 8.

### 11.2 Stale-result protection

Task cancellation alone is insufficient because the search actor's scan does
not check cancellation.

Each request captures:

- a monotonically increasing generation;
- the normalized query;
- the requested locale.

Before publishing completion, verify:

- the task is not canceled;
- generation is still current;
- normalized query is still current;
- locale is still current;
- the form is in editing mode.

Old rows are never retained while new work runs and are never interactive for
the new query.

### 11.3 Slow status

Start a separate 150 ms task at the same generation. If it wins while the
search is still current:

- enter `searchingSlow`;
- show no spinner or skeleton;
- keep the custom action available.

Cancel the slow task on result, failure, new query, selection, clear, or sheet
dismissal.

The sleep operation should be injectable in state-model tests so tests do not
depend on wall-clock races.

### 11.4 Locale changes

Use SwiftUI's `@Environment(\.locale)` identifier as the application locale,
not `Locale.current` read deep inside the model.

If the effective locale changes while editing:

- invalidate current work;
- re-run the current normalized query;
- refresh primary names, secondary cues, and categories.

If it changes while a catalog result is selected, return to editing and
re-search. This prevents confirming a stale app-language display snapshot.
A custom selection is language-independent and may remain selected.

## 12. Add Product UI Structure

### 12.1 Extraction

Extract the inline sheet into `AddProductSheet`. `ProductListView` should retain
only:

- the Boolean sheet presentation;
- the existing `ShoppingListService`;
- the custom save success side effects;
- the injected Product Knowledge availability;
- the future catalog commit handler.

Moving the form out of the 1,600-line `ProductListView` creates an isolated
state boundary and avoids adding asynchronous search state to unrelated list,
shopping, map, and recommendation logic.

### 12.2 Editing layout

Keep one outer `ScrollView`. Inside it:

1. name/photo form card;
2. current-query suggestion/status area;
3. catalog rows;
4. custom-product action;
5. Photo and Add Product controls.

Do not nest another vertical `ScrollView` or `List`. Use a `LazyVStack` or
ordinary `VStack` so medium detent, keyboard, and Dynamic Type all scroll as
one surface.

### 12.3 Name field

The active autocomplete field:

- receives focus after presentation;
- uses `.submitLabel(.search)`;
- dismisses focus on submit;
- never calls a save method from `onSubmit`;
- includes a clear action when nonempty;
- remains editable while search runs;
- uses word autocapitalization without altering the stored raw value.

### 12.4 Suggestion row

Each row contains:

- decorative semantic icon at visual leading;
- `displayName` as primary text;
- `categoryDisplayName` as secondary text;
- `secondaryName` before the category only when nonnil.

Examples:

```text
[icon] Paper Towels
       Household
```

```text
[icon] חלב
       Milk · מוצרי חלב ותחליפים
```

Requirements:

- minimum height 56 points before Dynamic Type growth;
- at least a 44-by-44-point activation target;
- whole-row button hit target;
- visible pressed and keyboard-focus feedback;
- wrapping when needed;
- no forced one-line truncation when text distinguishes products;
- stable search order unchanged by RTL.

### 12.5 Custom action

Show one custom action for every current manually valid name, regardless of:

- results;
- no results;
- slow search;
- unavailable search;
- normalization-empty punctuation input.

It follows catalog rows and is not counted in the eight-result cap.

Activation selects custom confirmation. It does not save.

### 12.6 No-result and unavailable states

No-result copy is secondary to the custom action and must not look like an
error.

Unavailable copy is inline and nonblocking. It must not:

- use the save-failure alert;
- clear query or photo;
- disable custom selection;
- expose a technical error;
- offer a blocking retry screen.

### 12.7 Selected summary

Catalog selection replaces editing results with a compact summary:

- selected photo if one exists, otherwise semantic icon;
- localized display name;
- localized category;
- Change action.

The product name is not editable while catalog-selected.

Custom selection uses the same confirmation pattern:

- selected photo or generic product icon;
- trimmed custom name;
- Change action.

This makes the required explicit custom choice visible and prevents later
edits from appearing to remain confirmed. Change restores the original query.

## 13. Persistence and Confirmation Boundary

### 13.1 UI commit request

The presentation layer should emit an explicit request:

```swift
enum AddProductCreationChoice: Hashable, Sendable {
    case catalog(ProductSearchResult)
    case custom(name: String)
}

struct AddProductCreationRequest: Hashable, Sendable {
    let choice: AddProductCreationChoice
    let imageData: Data?
}
```

The view must not convert `.catalog` into `.custom`.

### 13.2 Custom save

The custom handler maps exactly to:

```swift
shoppingListService.addManualProduct(
    name: trimmedName,
    imageData: imageData,
    in: modelContext
)
```

On success, preserve the existing diagnostics, app-state updates, form reset,
and dismissal.

On failure, preserve:

- the selected custom state;
- raw/preselection query;
- trimmed selected name;
- selected photo;
- the sheet;
- the current alert copy;
- retry ability.

`ShoppingListService.addManualProduct` requires no change for autocomplete
custom fallback.

### 13.3 Catalog save gate

A catalog handler is a prerequisite for production activation. It must be
provided by a separately approved Smart Product Creation task and must retain,
at minimum:

- `ProductSearchResult.productID`;
- `ProductSearchResult.displayName` as the user-visible snapshot;
- the selected user photo, if any.

That task must separately decide:

- which user-owned model stores the stable catalog reference;
- schema and migration behavior;
- duplicate catalog-selection behavior;
- how category/icon snapshots are represented, if persisted;
- transaction semantics;
- how existing Product Library and Shopping references remain valid.

WT-024A must not infer those decisions.

### 13.4 Production feature gate

The production behavior is binary:

- if both search availability handling and catalog-aware commit capability are
  integrated, present autocomplete;
- otherwise present the current reliable manual sheet unchanged.

Do not ship a partial mode where catalog rows can be selected but Add cannot
complete. Do not silently fall back to a manual save for catalog selection.

The UI component and state model may be implemented and tested before the
catalog handler, but root composition must not enable them for production.

## 14. Localization and Bidirectional Text

### 14.1 String catalog

Add a string catalog under the synchronized `WayTask` source tree for English
and Hebrew autocomplete copy.

At minimum include localized values for:

- Product name;
- Add Product;
- Close;
- Photo;
- Change;
- Clear search;
- Searching products…;
- No catalog match;
- Product suggestions are unavailable. You can still add this product
  manually.;
- Add “%@” as a custom product;
- Product wasn’t saved;
- Couldn’t save this product. Please try again.;
- accessibility labels and selected announcements.

Use the exact English and Hebrew wording in
`ProductSearchUXContract.md`. Do not construct Hebrew grammar by concatenating
localized fragments.

### 14.2 Category and product language

Pass `locale.identifier` to search. The result owns:

- primary product display language;
- secondary matched-name cue;
- localized category label.

The UI does not infer language from the query and does not translate or
title-case catalog values.

### 14.3 RTL layout

Use semantic leading/trailing alignment and the environment layout direction.

- icon is at visual leading;
- text aligns naturally;
- row order remains search order;
- dynamic user text is not manually reversed;
- matched name and category should be separate text runs so the separator does
  not reorder mixed Hebrew/English content;
- custom-name interpolation must use a localized format and bidirectional
  isolation where necessary.

## 15. Accessibility and Input

### 15.1 VoiceOver

Each suggestion is one Button accessibility element.

Without a secondary match:

```text
<display name>, <category>
```

With a secondary match:

```text
<display name>, <category>, matched as <secondary name>
```

The semantic icon is hidden from accessibility.

After selection, post the localized announcement:

```text
<product name> selected, <category>. Add Product to confirm.
```

The custom action announces its complete quoted name. Add Product exposes its
disabled state until explicit selection.

### 15.2 Dynamic Type

- allow rows and summaries to grow vertically;
- let distinguishing text wrap;
- keep the full surface scrollable;
- avoid fixed row heights;
- test accessibility sizes in medium and large sheet detents.

### 15.3 Hardware keyboard

Use standard Buttons so focused catalog rows, custom action, Change, and Add
activate with Return or Space.

Return in the text field only ends text submission and dismisses the software
keyboard. It does not select the top result, select custom, or save.

### 15.4 Stable automation identifiers

Add identifiers that contain no free-form user text:

- `addProduct.nameField`
- `addProduct.clearQuery`
- `addProduct.searchStatus`
- `addProduct.suggestion.<ProductID>`
- `addProduct.customAction`
- `addProduct.selectedSummary`
- `addProduct.change`
- `addProduct.confirm`
- `addProduct.close`

Stable catalog IDs are acceptable in identifiers. Raw queries and custom names
are not.

## 16. Files to Create During Implementation

### Production

- `WayTask/ProductKnowledge/Application/ProductKnowledgeSearchAvailability.swift`
  - available/unavailable dependency value.
- `WayTask/ProductKnowledge/Presentation/AddProductAutocompleteViewModel.swift`
  - query, generation, async work, phases, explicit selection, and derived
    validation state.
- `WayTask/ProductKnowledge/Presentation/AddProductSheet.swift`
  - sheet, focus, photo state, suggestion surface, confirmation, and save
    alert.
- `WayTask/ProductKnowledge/Presentation/ProductKnowledgeSuggestionRow.swift`
  - reusable accessible result row.
- `WayTask/ProductKnowledge/Presentation/ProductKnowledgeIconResolver.swift`
  - complete semantic icon map and fallback.
- `WayTask/Localizable.xcstrings`
  - English/Hebrew Add Product autocomplete strings.

### Unit tests

- `WayTaskTests/ProductKnowledge/ProductAutocompleteViewModelTests.swift`
  - query lifecycle, stale work, state transitions, explicit selection, and
    failure preservation.
- `WayTaskTests/ProductKnowledge/ProductKnowledgeIconResolverTests.swift`
  - all taxonomy keys and generic fallback.

### UI tests

- `WayTaskUITests/ProductAutocompleteUITests.swift`
  - focus, keyboard, suggestion, selection, custom fallback, unavailable
    behavior, and reset.

Creating `WayTaskUITests` requires a new Xcode UI-test target and shared-scheme
entry because no UI target exists today.

## 17. Files to Modify During Implementation

- `WayTask/ProductKnowledge/Domain/ProductSearchResult.swift`
  - add `categoryDisplayName`.
- `WayTask/ProductKnowledge/Application/ProductKnowledgeSearch.swift`
  - resolve category display text for the requested locale;
  - do not change normalization, matching, ranking, or limits.
- `WayTask/WayTaskApp.swift`
  - construct availability once;
  - report loader failure safely;
  - pass availability to `ContentView`.
- `WayTask/ContentView.swift`
  - accept and pass Product Knowledge availability.
- `ProductListView.swift`
  - accept availability;
  - present extracted `AddProductSheet`;
  - remove only the state and helpers moved into the sheet;
  - preserve existing custom save side effects.
- `WayTask/SentryReportingService.swift`
  - add one privacy-safe Product Knowledge unavailable diagnostic message if
    diagnostics are routed through Sentry.
- `WayTaskTests/ProductKnowledge/ProductKnowledgeSearchTests.swift`
  - assert localized category metadata and retain all existing search tests.
- `WayTaskTests/ProductKnowledge/LegacyProductCreationCharacterizationTests.swift`
  - retain existing manual shape and duplicate guarantees;
  - add coverage through the new custom creation request boundary if useful.
- `WayTask.xcodeproj/project.pbxproj`
  - only to add the new UI-test target and its dependency.
- `WayTask.xcodeproj/xcshareddata/xcschemes/WayTask.xcscheme`
  - include the UI-test target.
- `TESTING.md`
  - add the manual autocomplete regression matrix.

## 18. Files That Must Remain Unchanged

- `ShoppingListService.swift` for WT-024A custom behavior;
- `WayTask/Models.swift` until the separate persistence task;
- `ProductKnowledgeRepository.swift`;
- `InMemoryProductKnowledgeRepository.swift`;
- `BundledProductKnowledgeLoader.swift`;
- `ProductKnowledgeCatalogValidator.swift`;
- Product Entity, Product Name, and Product Category identity fields;
- `product-knowledge-catalog-v1.json`;
- legacy `ProductKnowledge.swift`;
- legacy `ProductKnowledgeService.swift`;
- search performance expectations and ranking contract.

The later Smart Product Creation task will necessarily revisit persistence,
but that is not authorized by this UI integration plan.

## 19. Ordered Implementation Sequence

1. Add category-display assertions to existing search tests.
2. Extend `ProductSearchResult` with localized category display text.
3. Resolve that text inside `ProductKnowledgeSearch` and run the complete
   Product Knowledge suite.
4. Add and test the semantic icon resolver.
5. Add the search availability value.
6. Construct loader, repository, and search once in `WayTaskApp`.
7. Add privacy-safe diagnostics for composition-time catalog failure.
8. Pass availability explicitly through `ContentView` and `ProductListView`.
9. Add the Add Product state model and pin its pure/derived state behavior.
10. Add immediate query execution, generation invalidation, and stale-result
    tests.
11. Add the injectable 150 ms slow-status clock and tests.
12. Add catalog/custom selection and Change transitions.
13. Add the extracted Add Product sheet using existing design-system surfaces.
14. Move photo handling and the existing save-failure alert into the sheet
    without changing their reliability semantics.
15. Connect only the explicit custom choice to the current manual save
    handler.
16. Add English/Hebrew strings and RTL presentation.
17. Add accessibility semantics and stable identifiers.
18. Add the UI-test target and deterministic launch controls.
19. Run unit, UI, localization, accessibility, and manual regression coverage.
20. Integrate the separately approved catalog-aware commit handler.
21. Enable autocomplete in production only after the catalog handler's
    persistence tests and migration gates pass.
22. Confirm no catalog, ranking, legacy Product Knowledge, or unrelated
    Product List diff exists.

Steps 1 through 19 may be developed without a persistence migration, provided
the feature is not production-enabled. Steps 20 and 21 are the shipping gate.

## 20. Automated Test Plan

### 20.1 Existing search regression

Keep all current tests green for:

- Unicode normalization;
- Hebrew and English matching;
- exact, full-prefix, and word-prefix matching;
- alias and cross-language secondary names;
- ranking;
- duplicate suppression;
- limits;
- inactive exclusion;
- empty-query no-load behavior;
- one-snapshot concurrency;
- stable source-order independence;
- no fuzzy/brand/subtype matching;
- 15/100/500-product performance measurements.

### 20.2 Category presentation tests

Verify:

- Milk returns Dairy & Alternatives in English;
- Milk returns מוצרי חלב ותחליפים in Hebrew;
- `he-IL` uses Hebrew;
- `en_US` uses English;
- an unsupported locale uses English;
- category ID remains stable across locale changes;
- category display does not affect ranking;
- every bundled result has a nonempty category display name.

### 20.3 View-model query tests

Verify:

- empty and whitespace-only input does not call search;
- normalization-empty punctuation does not call search but can offer custom;
- one Hebrew or English normalized character calls immediately;
- digits activate;
- same normalized query does not call again;
- a same-normalized raw change updates custom copy;
- result count uses requested limit 8;
- latest generation alone publishes;
- cancellation plus late completion cannot restore old rows;
- clearing invalidates and removes rows immediately;
- 150 ms status appears only while current work is pending;
- fast search never shows slow status;
- unavailable search never blocks custom;
- locale change reruns and updates localized metadata.

### 20.4 Selection tests

Verify:

- typing alone never enables Add;
- catalog tap selects exactly that `ProductID`;
- custom tap stores the trimmed visible name;
- both choices require a later Add activation;
- no top result is auto-selected;
- selection cancels/invalidates outstanding work;
- catalog Change restores the exact raw query;
- custom Change restores the exact raw query;
- query, photo, and selection survive save failure;
- clear preserves photo but clears query and selection;
- close and successful save reset all state.

### 20.5 Manual persistence regression

Keep and extend characterization proving:

- custom creation still creates one `Product`;
- name is the UI-trimmed custom name;
- photo bytes are preserved;
- source remains manual;
- category, barcode, brand, and legacy ID remain nil;
- no shopping entry is added automatically;
- duplicate custom names remain independent;
- custom products can still enter Shopping later;
- failed saves do not dismiss the form.

Add a negative boundary assertion: catalog choice must never dispatch
`addManualProduct`.

### 20.6 Composition tests

Using a test bundle or fixture:

- valid catalog produces `.available`;
- missing resource produces `.unavailable`;
- invalid catalog produces `.unavailable`;
- technical failure is reported once without raw query/user data;
- unavailable composition does not affect SwiftData startup;
- one app composition creates one search actor.

### 20.7 Icon resolver tests

Verify all 15 runtime taxonomy keys resolve to nonempty supported SF Symbols
and an unknown key resolves to the generic symbol.

### 20.8 XCUITest scenarios

Add deterministic UI launch controls for bundled-search and unavailable-search
states. Cover:

1. sheet opens with focused empty name field;
2. typing `mil` shows Milk and a custom action;
3. tapping Milk shows a selected summary and does not save;
4. Return in the field does not select or save;
5. typing `Protein Vanilla Pudding`, selecting custom, then Add uses the
   existing manual path;
6. search unavailable still permits explicit custom creation;
7. clear removes results and preserves selected photo;
8. Change restores query and keyboard focus;
9. closing and reopening starts empty;
10. rapid `m` -> `mi` -> `mil` never makes older rows interactive;
11. Hebrew launch shows Hebrew primary and category text;
12. English launch with `חלב` shows Milk plus Hebrew secondary cue;
13. accessibility Dynamic Type retains scrollability;
14. duplicate-looking name records still produce one row.

The full catalog-selection save test is added only when the catalog-aware
persistence handler exists.

## 21. Manual Acceptance Matrix

### Editing and search

- [ ] Add Product opens at medium detent and focuses the name field.
- [ ] Empty query shows no catalog rows, recent items, or custom action.
- [ ] One normalized character searches without visible debounce.
- [ ] No spinner appears for normal local search.
- [ ] Slow status appears only after 150 ms.
- [ ] At most eight catalog rows appear.
- [ ] Old-query rows disappear immediately and cannot be tapped.

### Selection

- [ ] No row is auto-selected.
- [ ] Return does not select or save.
- [ ] Catalog selection dismisses keyboard and shows summary.
- [ ] Custom selection dismisses keyboard and shows confirmation.
- [ ] Add remains disabled before an explicit choice.
- [ ] Change restores the preselection query and focus.

### Manual reliability

- [ ] Unknown product can always choose custom.
- [ ] Custom choice remains available with results, no results, slow search,
  and unavailable search.
- [ ] Photo survives search, selection, Change, and save failure.
- [ ] Save failure preserves the sheet and permits retry.
- [ ] Successful custom save dismisses and appears in Products.
- [ ] Duplicate custom names still work.

### Localization and accessibility

- [ ] Hebrew primary names/categories and RTL layout are correct.
- [ ] English primary names/categories and LTR layout are correct.
- [ ] Cross-language secondary name remains readable.
- [ ] Mixed-language punctuation does not reorder.
- [ ] Rows remain usable at accessibility text sizes.
- [ ] VoiceOver announces name, category, and matched name when present.
- [ ] Icons are not announced.
- [ ] Hardware keyboard focus and activation work.

## 22. Performance and Responsiveness

Search performance remains governed by WT-023A:

| Catalog size | Warm-query expectation |
|---:|---:|
| 15 | at most 2 ms p95 |
| 100 | at most 5 ms p95 |
| 500 | less than 20 ms p95 |

UI integration adds:

- zero artificial debounce;
- no work for normalized-empty input;
- no catalog reload per view render or sheet presentation;
- no image load per result;
- maximum eight rendered catalog rows;
- immediate invalidation of stale rows;
- no main-actor matching or ranking.

Measure typing responsiveness with the software keyboard open at medium detent.
The UI must not move the cursor, close the keyboard, or block custom selection
while waiting.

## 23. Diagnostics and Privacy

Catalog composition failure should produce one privacy-safe diagnostic:

- operation: diagnostics or integration;
- area: Products;
- safe message: Product suggestions unavailable;
- optional numeric catalog/schema metadata only when already validated and
  non-sensitive.

Never report:

- raw query;
- custom product name;
- matched alias;
- selected photo;
- catalog resource path;
- user-visible save input.

No search or selection analytics are authorized by this plan.

## 24. Risks and Mitigations

### Catalog choice loses identity

**Risk:** The UI sends catalog display text through the manual save API.

**Mitigation:** Typed creation-choice boundary, negative dispatch test, and a
hard production gate until catalog-aware persistence exists.

### Manual flow regresses during extraction

**Risk:** Moving the inline sheet changes trimming, photo retention, error
preservation, side effects, or dismissal timing.

**Mitigation:** Preserve the existing custom handler, retain characterization
tests, and add end-to-end custom UI coverage before enabling autocomplete.

### Stale results overwrite current input

**Risk:** Canceled actor work still returns.

**Mitigation:** Clear rows immediately and require task cancellation,
generation, normalized query, locale, and editing-mode checks before publish.

### Search actor is recreated

**Risk:** SwiftUI reconstruction loses the cached index and repeats catalog
loading.

**Mitigation:** Create once in `WayTaskApp` and use explicit constructor
injection.

### Category labels drift from the catalog

**Risk:** UI hardcodes a second taxonomy-name map.

**Mitigation:** Resolve category display in `ProductKnowledgeSearch` and carry
it in the result.

### Semantic icons are missing or blank

**Risk:** An unmapped key produces no visible symbol.

**Mitigation:** Complete resolver test against all bundled keys and a generic
fallback.

### Search failure blocks manual creation

**Risk:** Loader failure disables the form or presents a blocking retry.

**Mitigation:** Composition availability state, inline nontechnical copy, and
custom action independent of catalog availability.

### Return preserves old accidental-save behavior

**Risk:** The old `.done` submit handler remains connected to save.

**Mitigation:** Replace with `.search`, test Return with results and no
results, and require explicit selection before Add.

### Raw and normalized validity are conflated

**Risk:** A valid custom string such as punctuation is hidden because it does
not activate search.

**Mitigation:** Separate manual trimmed validity from catalog normalization in
state and tests.

### Hebrew/mixed text reorders

**Risk:** Alias/category separators and custom quotes render incorrectly.

**Mitigation:** Localized format strings, separate text runs, semantic
alignment, RTL device tests, and VoiceOver review.

### UI automation is absent

**Risk:** Focus, keyboard, detent, and accessibility regressions remain manual.

**Mitigation:** Add a dedicated UI-test target as an explicit project change
and supplement it with the manual matrix.

## 25. Rollout and Rollback

### 25.1 Rollout

1. Land category presentation and icon resolver with tests.
2. Land composition and state model with production activation off.
3. Land the extracted sheet and custom-path regression tests.
4. Land localization, accessibility, and UI tests.
5. Obtain separate Smart Product Creation persistence approval.
6. Land the catalog-aware commit handler and its migration/transaction tests.
7. Enable autocomplete.
8. Validate offline English/Hebrew behavior on a supported device.

### 25.2 Rollback

The UI integration is reversible before any catalog persistence migration:

- stop passing the autocomplete capability;
- present the legacy manual sheet;
- remove the extracted autocomplete presentation components if desired;
- retain the Product Knowledge search foundation and catalog unchanged.

Custom products created through the preserved manual path require no repair.

Once a later catalog-ID migration ships, its rollback must follow that task's
separate migration plan; WT-024A does not define a data downgrade.

## 26. Approval-Gate Matrix

| Gate | Required evidence | Current status |
|---|---|---|
| Search correctness | Existing actor correctness/concurrency/performance suite | Implemented |
| Result UI metadata | Localized category display name added and tested | Required |
| Icon presentation | All 15 semantic keys plus fallback mapped | Required |
| Composition lifetime | One app-session search actor | Required |
| Catalog failure | Nonblocking unavailable state and safe diagnostic | Required |
| Query lifecycle | Zero debounce, generation guard, 150 ms status | Defined |
| Explicit choice | Catalog/custom selection before Add | Defined |
| Manual reliability | Existing handler, state retention, regression suite | Defined |
| Keyboard | Return never selects or saves | Defined |
| Localization | English/Hebrew strings and environment locale | Required |
| Accessibility | VoiceOver, Dynamic Type, RTL, hardware focus | Required |
| UI automation | New UI-test target and scenarios | Required |
| Catalog persistence | Stable Product ID plus display snapshot | **Blocked on separate approval** |
| Production activation | Catalog-aware commit handler installed | **Blocked on separate approval** |
| Resource stability | No bundled catalog change | Satisfied |
| Legacy isolation | No legacy Product Knowledge integration | Satisfied |

## 27. Final Recommendation

Proceed with the autocomplete presentation architecture defined here, using
one app-owned `ProductKnowledgeSearch`, a focused Add Product state model,
localized category metadata, a semantic icon resolver, and explicit
catalog/custom selection.

Preserve the existing custom-product save path exactly.

Do not route a selected catalog result through
`ShoppingListService.addManualProduct`, and do not production-enable
autocomplete until the separately approved Smart Product Creation task stores
the stable catalog Product ID and display-name snapshot.

**IMPLEMENTATION PLAN COMPLETE**  
**PRODUCTION ACTIVATION GATED BY CATALOG-AWARE PERSISTENCE**
