# WT-022A — Product Knowledge Foundation

## Phase 1 Implementation Plan

**Status:** Planning complete<br>
**Date:** 2026-07-23<br>
**Blocker resolution:** WT-022A.1<br>
**Scope:** Isolated Product Knowledge domain, bundled-catalog loading, validation, and read-only repository foundation<br>
**Implementation authorization:** Approved; all approval gates in Section 15 are PASS

---

## 1. Purpose and Scope

WT-022A introduces the smallest code foundation that can represent and load approved Product Knowledge without changing any existing product-creation, Product Library, Shopping, camera, barcode, AI, or persistence behavior.

The implementation planned here is deliberately isolated:

```text
Versioned bundle resource
  -> decode
  -> catalog validation
  -> immutable in-memory snapshot
  -> read-only repository contract
```

No current feature consumes the repository in WT-022A. The new foundation is compiled and tested, but it is not created from `WayTaskApp`, injected into a view, registered in SwiftData, or called by a current service.

### In scope

- A minimal, platform-neutral `ProductEntity`.
- Authoritative localized product-name records.
- The approved Phase 1 taxonomy representation.
- A read-only Product Knowledge repository contract.
- A bundle loader for one versioned, local catalog snapshot.
- A structural catalog validator.
- Unit tests and current-behavior characterization tests.
- One approved, manually authored runtime JSON resource.

### Explicitly out of scope

- Search, suggestions, ranking, indexing, autocomplete, normalization projections, or fuzzy matching.
- UI or changes to current product creation.
- Gemini, camera, barcode, voice, provider, or network integration.
- Product Generator.
- The user-facing/draft **Product Validator** feature.
- `ProductDraft`, `ProductObservation`, product resolution, merge, or redirects.
- Writable Product Knowledge persistence.
- SwiftData schema changes.
- User library or Shopping integration.
- Migration, backfill, or modification of existing user data.
- Media, nutrition, store affinity, community, cloud sync, and generalized provenance.

The `ProductKnowledgeCatalogValidator` proposed below is only an infrastructure validator for a bundled catalog artifact. It is not the deferred Product Validator feature.

---

## 2. Source-of-Truth Interpretation

The implementation must apply the approved documents in this order when examples or recommendations differ:

1. `ProductTaxonomy.md` is authoritative for taxonomy version 1.0, including the exact 15 category IDs and semantic icon keys.
2. The Executive Architecture Review's required changes supersede the broader or duplicated fields in the original architecture and data-model proposals.
3. `PilotProductCatalog.md` is the approved human review record. WT-022A.1 authorizes exact manual promotion of its 15 Product Concepts to `product-knowledge-catalog-v1.json`.
4. Earlier illustrative identifiers such as `food.dairy` and `food.dairy.milk` are not valid Phase 1 taxonomy IDs. The implementation must use `dairy`, `bakery`, and the other IDs defined by `ProductTaxonomy.md`.
5. Taxonomy version 1.0 has no published subcategories. No local subcategory IDs may be invented.
6. Product names are authoritative `ProductName` records. Normalized names are future versioned projections and are not stored by this foundation.
7. A normal product icon is derived from its category. Catalog schema version 1 has no product icon override field.
8. The runtime JSON is authoritative for the app; Markdown remains authoritative for human-reviewed meaning and governance. A mismatch blocks shipping.

---

## 3. Current Source Audit

### 3.1 Project and target structure

- The repository has one Xcode project and one native application target, `WayTask`.
- There is no unit-test target and no test source tree.
- Most legacy Swift files are explicitly listed at the repository root in `project.pbxproj`.
- The `WayTask/` directory is a file-system-synchronized root group. New Swift and resource files under this directory can inherit app-target membership without listing every file manually.
- The app uses Swift 5 mode, Swift approachable concurrency, and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- SwiftData is the current local persistence technology.
- Sentry is the only Swift Package dependency recorded in the project.
- The Resources build phase explicitly contains `Secrets.plist`; the synchronized `WayTask/` group also contains the asset catalog.

Planning implication: keep all new production sources and bundled resources inside `WayTask/ProductKnowledge/` and `WayTask/Resources/ProductKnowledge/`. Modify the project only to add a real test target and shared test scheme.

### 3.2 Current persistence models

`WayTask/Models.swift` currently defines:

- `Product`, the persistent Product Library record.
- `ShoppingItem`, the legacy/compatibility shopping record with copied product fields.
- `ShoppingListEntry`, which stores a `Product.id` plus an optional relationship and legacy item ID.

`ProductKnowledge.swift` defines a separate SwiftData cache keyed by a derived barcode or lowercased-name key. It stores copied identity, category, provider, keyword, image, and usage fields.

`ProductHistory.swift` defines another name/barcode-keyed usage record.

`WayTask/WayTaskApp.swift` registers all of these models in the app-level SwiftData model container.

Planning implication: WT-022A must not add `ProductEntity` to the SwiftData model container and must not modify any current `@Model`. `ProductEntity` is a plain domain value in this phase.

### 3.3 Current manual product creation

`ProductListView.addItem()`:

1. Trims the entered product name.
2. Calls `ShoppingListService.addManualProduct`.
3. Creates a new SwiftData `Product`.
4. Preserves the existing success, diagnostics, and error behavior.

The current manual path does not query or write `ProductKnowledge`. Equivalent manual names can create separate `Product` records.

Planning implication: do not modify `ProductListView.swift`, `ShoppingListService.swift`, or their dependencies. Add characterization tests before introducing the isolated foundation so this behavior is recorded.

### 3.4 Current recognized-product and knowledge behavior

- `ProductCandidate` is the transient provider-neutral DTO.
- Camera and barcode flows call `ShoppingListService.upsertRecognizedProduct`.
- Recognized-product upsert writes the current `Product` and learns the legacy `ProductKnowledge`.
- `ProductKnowledgeService` performs exact barcode/key lookup and source-priority updates.
- The current `ProductKnowledge` count appears in Settings.

Planning implication: retain `ProductCandidate`, `ProductKnowledge`, and `ProductKnowledgeService` unchanged. The new repository must use distinct names and must not be substituted into camera or barcode flows.

### 3.5 Current startup and compatibility behavior

`ContentView` runs `ShoppingListBackfillService` on startup to maintain `Product`, `ShoppingItem`, `ShoppingList`, and `ShoppingListEntry` compatibility.

Planning implication: the new loader must not run at startup in WT-022A. This avoids launch I/O, failure coupling, dual writes, a new migration state, and changes to existing user data.

### 3.6 Current resource-loading convention

`SecretsManager` uses `Bundle.main.url(forResource:withExtension:)`. No general versioned JSON resource loader or catalog validator exists.

Planning implication: the new loader accepts an injected `Bundle` and resource descriptor. Production may pass `.main` later; unit tests use a fixture bundle or direct `Data`.

### 3.7 Worktree condition

At planning time, the worktree already contains unrelated modified Swift/project files and modified or untracked product documents. Those changes are user-owned and were not altered by WT-022A planning.

Before implementation, re-audit the effective baseline and apply project-file edits narrowly. Do not replace or regenerate the entire `.pbxproj`.

---

## 4. Proposed Files to Create

The implementation should create only files with an immediate responsibility.

### 4.1 Production domain and application files

| File | Responsibility |
|---|---|
| `WayTask/ProductKnowledge/Domain/ProductEntity.swift` | Strong ID values, `ProductEntityStatus`, and the Product Concept entity |
| `WayTask/ProductKnowledge/Domain/ProductName.swift` | Authoritative localized canonical/display/alias name records |
| `WayTask/ProductKnowledge/Domain/ProductCategory.swift` | Approved taxonomy category and localized category-name values |
| `WayTask/ProductKnowledge/Application/ProductKnowledgeRepository.swift` | Narrow read-only repository protocol and snapshot metadata |
| `WayTask/ProductKnowledge/Application/ProductKnowledgeError.swift` | Stable resource, version, decode, and validation error taxonomy |

### 4.2 Production data files

| File | Responsibility |
|---|---|
| `WayTask/ProductKnowledge/Data/ProductKnowledgeCatalog.swift` | Codable wire envelope, separate from domain types |
| `WayTask/ProductKnowledge/Data/ProductKnowledgeCatalogValidator.swift` | Pure structural and referential validation |
| `WayTask/ProductKnowledge/Data/BundledProductKnowledgeLoader.swift` | Bundle lookup, decoding, and validation orchestration |
| `WayTask/ProductKnowledge/Data/InMemoryProductKnowledgeRepository.swift` | Immutable ID-indexed snapshot implementing the read-only repository |

### 4.3 Production resource

WT-022A.1 approves this exact resource:

| File | Responsibility |
|---|---|
| `WayTask/Resources/ProductKnowledge/product-knowledge-catalog-v1.json` | The approved taxonomy, Product Entities, and Product Names |

The production catalog is manually authored from the approved pilot and taxonomy, reviewed, and validated. It must not be generated by scraping Markdown at runtime or during the app build.

### 4.4 Test files

| File | Responsibility |
|---|---|
| `WayTaskTests/ProductKnowledge/ProductEntityTests.swift` | Product Concept/default-name/category/status invariants and Codable behavior |
| `WayTaskTests/ProductKnowledge/ProductKnowledgeCatalogValidatorTests.swift` | Valid catalog plus one focused test for every validation rule |
| `WayTaskTests/ProductKnowledge/BundledProductKnowledgeLoaderTests.swift` | Missing, malformed, unsupported-version, invalid-content, and valid loading |
| `WayTaskTests/ProductKnowledge/InMemoryProductKnowledgeRepositoryTests.swift` | Exact ID reads, name/category lookup, locale fallback, and immutability |
| `WayTaskTests/ProductKnowledge/ProductKnowledgeResourceConformanceTests.swift` | Exact shipped-resource contract, counts, IDs, taxonomy, and aliases |
| `WayTaskTests/ProductKnowledge/LegacyProductCreationCharacterizationTests.swift` | In-memory SwiftData tests proving the current manual creation path is unchanged |
| `WayTaskTests/ProductKnowledge/Support/ProductKnowledgeFixtureFactory.swift` | Small valid fixture builder and controlled invalid mutations |

### 4.5 Test scheme

| File | Responsibility |
|---|---|
| `WayTask.xcodeproj/xcshareddata/xcschemes/WayTask.xcscheme` | Shared scheme that includes `WayTaskTests` in its Test action |

If Xcode can safely convert the existing autogenerated scheme to shared form, create the scheme through Xcode and review the resulting XML. Do not hand-invent project identifiers.

---

## 5. Proposed Files to Modify

### Required modification

| File | Change |
|---|---|
| `WayTask.xcodeproj/project.pbxproj` | Add the `WayTaskTests` unit-test target, synchronized test group, host-app dependency, product reference, build configurations, and test target membership |

### Explicitly not modified in WT-022A implementation

- `WayTask/WayTaskApp.swift`
- `WayTask/ContentView.swift`
- `WayTask/Models.swift`
- `ProductListView.swift`
- `ShoppingListService.swift`
- `ProductKnowledge.swift`
- `ProductKnowledgeService.swift`
- `ProductHistory.swift`
- `ShoppingMemoryService.swift`
- `ProductCandidate.swift`
- `CameraView.swift`
- `CameraViewModel.swift`
- `SettingsView.swift`
- Any asset catalog, plist, xcconfig, package dependency, or existing resource

This is the principal behavior-preservation mechanism. There is no runtime composition change and no SwiftData schema change.

---

## 6. ProductEntity Design

### 6.1 Domain boundary

`ProductEntity` is a framework-independent value type. It must:

- Import Foundation only.
- Conform to `Identifiable`, `Codable`, `Hashable`, and `Sendable`.
- Use opaque string-backed ID value types rather than a name-derived key.
- Represent a generic Product Concept only.
- Contain no SwiftData, SwiftUI, UIKit, provider, image, shopping, or user-library state.
- Contain no stored normalized name or resolved icon.
- Contain no entity-kind, variant, brand, barcode, size, price, or package field.

### 6.2 Minimal fields

| Field | Type | Rule |
|---|---|---|
| `id` | `ProductID` | Stable, unique, language-independent, never name-derived or reused |
| `defaultNameID` | `ProductNameID` | Must reference a name belonging to the same product |
| `primaryCategoryID` | `ProductCategoryID` | Exactly one approved Phase 1 category ID |
| `status` | `ProductEntityStatus` | `active` or `inactive`; initial 15 entities are active |

No timestamps, per-row schema version, origin, verification summary, variant relationship, product icon override, brand, barcode, media, keywords, nutrition, usage, redirects, or provider metadata are included.

### 6.3 Authoritative names

`ProductName` is the only source of product display text:

| Field | Rule |
|---|---|
| `id` | Stable row identity |
| `productID` | Parent Product Entity |
| `locale` | BCP-47 string; initial supported values are `en` and `he` |
| `kind` | `canonical`, `localizedDisplay`, or `alias` |
| `value` | Trimmed, non-empty valid Unicode |
| `isPreferred` | Exactly one preferred display-capable name per product/locale |

The entity does not duplicate a canonical name. The initial catalog stores each approved pilot alias as its own `ProductName` row.

For catalog v1, the preferred English name is the entity's `defaultNameID`; the preferred Hebrew name is a localized display name. Display-name resolution is deterministic:

1. Exact requested BCP-47 locale.
2. Requested language without region/script subtags.
3. Preferred English (`en`).
4. The entity's referenced default name.

The raw Product ID is never a user-visible name fallback.

### 6.4 Category representation

`ProductCategory` contains:

- Stable `ProductCategoryID`.
- Localized English and Hebrew category names.
- One semantic category icon key.
- Sort order.
- Active status.

For taxonomy version 1.0:

- Exactly the 15 authoritative top-level IDs must exist.
- There is no parent or subcategory field.
- `uncategorized` is available as a controlled fallback.
- The exact icon mappings come from `ProductTaxonomy.md`.

### 6.5 Icon resolution

The domain rule is:

```text
primary category icon
  -> product.generic
```

Catalog schema version 1 has no Product Concept override field. WT-022A stores category semantic keys only and does not add an iOS icon resolver or UI assets.

### 6.6 Resolved identity relationships

WT-022A.1 resolves the terms as follows:

| Term | Decision |
|---|---|
| Product Concept | The only catalog `ProductEntity`; a generic need such as Milk |
| Sellable Variant | Brand/package-specific retail SKU; outside WT-022A and not represented |
| Brand | Retail qualifier; outside catalog v1 and not an identity |
| Shopping item | User-owned list state; current `ShoppingListEntry` and legacy `ShoppingItem` remain unchanged |
| Custom User Product | Existing user-owned `Product` created manually; valid, mutable, and independent of the catalog |
| Alias | Alternate localized search metadata belonging to one Product Concept; never an independent identity |

The first 15 Product IDs remain `prd_pilot_0001` through `prd_pilot_0015` and become permanent when first shipped.

WT-022A adds no catalog reference or display-name snapshot field to existing persistence. Search and Autocomplete integration is deferred. When a later approved integration links user-owned state to a Product Concept, it must store both the stable catalog Product ID and a user-visible display-name snapshot so a catalog rename, deactivation, or missing resource cannot erase the user's visible text.

---

## 7. Repository Design

### 7.1 Contract

The initial `ProductKnowledgeRepository` is read-only and intentionally does not resemble the broad repository rejected by the Executive Architecture Review.

Conceptual operations:

```text
metadata() -> ProductKnowledgeSnapshotMetadata
entity(id) -> ProductEntity?
names(productID) -> [ProductName]
category(id) -> ProductCategory?
preferredName(productID, locale) -> ProductName?
resolvedIconKey(productID) -> String?
```

All reads are local and exact-ID based. There is no:

- `suggest`
- `search`
- `resolve`
- `save`
- `merge`
- `removeFromLibrary`
- `rebuildIndex`
- enumeration intended for UI

### 7.2 Adapter

`InMemoryProductKnowledgeRepository`:

- Is initialized from one already-validated immutable snapshot.
- Builds dictionaries keyed by Product, ProductName, and Category ID once.
- Returns domain values rather than wire DTOs.
- Is isolated as an actor, or otherwise explicitly made concurrency-safe after a compiler spike under the target's default MainActor isolation.
- Does not mutate or persist catalog data.
- Performs no file I/O after initialization.

This adapter is suitable only for the small first bundled catalog. It is not evidence that an in-memory repository meets the future 5,000/50,000-product requirement.

### 7.3 Future replacement boundary

A later persistence/search ADR may replace the in-memory adapter with SQLite or another indexed local store without changing the domain values. That later work must define authority, transaction boundaries, read-after-write behavior, index repair, and concurrency. None of those decisions are implied by WT-022A.

---

## 8. Loader Design

`BundledProductKnowledgeLoader` is dependency-injected with:

- A `Bundle`.
- The exact resource name `product-knowledge-catalog-v1`.
- Supported schema versions.
- A `ProductKnowledgeCatalogValidator`.

Loading sequence:

1. Locate and read `product-knowledge-catalog-v1.json`.
2. Decode the catalog envelope with a configured `JSONDecoder`.
3. Reject unsupported schema or taxonomy versions.
4. Run full structural, referential, and content validation.
5. Map validated DTOs to domain values.
6. Return one immutable snapshot.

The loader must:

- Fail atomically; never return a partial catalog.
- Perform no network access.
- Avoid `try!`, force unwraps, or silent empty-catalog fallback.
- Accept direct `Data` in a test seam so decoder and validator tests do not depend on `Bundle.main`.
- Avoid logging full catalog contents.

The loader is not invoked from application startup in WT-022A.

---

## 9. Validator Design

`ProductKnowledgeCatalogValidator` is pure and deterministic. It returns either success or a list of stable, structured violations. It does not repair input.

### 9.1 Envelope rules

- Exact `schemaVersion = 1`.
- Positive `catalogRevision`; the first runtime resource uses revision `1`.
- Exact `taxonomyVersion = 1.0`.
- Exact `expectedProductCount = 15` for catalog revision 1, matching the decoded product count.
- `supportedLocales` is exactly `["en", "he"]`.
- Required top-level collections are `categories`, `products`, and `names`.
- Unsupported fields for schema version 1 are rejected by validation/schema-conformance tests.
- The uncompressed catalog resource is no larger than 100 KiB for revision 1.

### 9.2 Category rules

- Exactly 15 unique category IDs.
- IDs match the documented ID pattern.
- The ID set exactly equals the authoritative taxonomy v1.0 set.
- No parent IDs or locally invented subcategories.
- Exactly one English and one Hebrew display name per category.
- Each semantic icon key exactly matches the authoritative category mapping.
- `uncategorized` maps to `product.generic`.
- Sort orders are unique and deterministic.

### 9.3 Product rules

- Product IDs are non-empty, unique, stable-looking opaque identifiers.
- No ID is derived automatically from a localized product name.
- The initial ID set is exactly `prd_pilot_0001` through `prd_pilot_0015`.
- Every entity references an existing category.
- Every entity is a Product Concept by schema definition; no entity-kind or variant field exists.
- Catalog revision 1 contains exactly 15 active concepts.
- Every `defaultNameID` resolves to a name owned by that product.
- No product contains a subcategory, icon override, brand, barcode, package, price, or provider field.

### 9.4 Name and alias rules

- Name IDs are unique.
- Every name references an existing product.
- Values are non-empty after trimming and contain no disallowed control characters.
- Locales are supported BCP-47 tags.
- Each initial product has English and Hebrew preferred names describing the same documented concept.
- At most one preferred display-capable name exists per product/locale.
- Canonical names are not repeated as aliases within the same locale.
- Exact duplicate `(productID, locale, kind, value)` rows are rejected.
- Aliases are separate rows; delimiter-encoded alias lists are rejected by schema shape.

Search normalization, typo acceptance, ranking weight, transliteration generation, and semantic alias inference are outside this validator.

### 9.5 Content conformance rules

The resource-conformance test must assert:

- Exactly 15 Product Concepts.
- Exact Product ID list `prd_pilot_0001` through `prd_pilot_0015`.
- Exact English/Hebrew names and approved aliases.
- Exact category assignments.
- 11 of 15 categories represented by products.
- No curated product assigned to `uncategorized`.
- No product-specific icon field or sellable-variant metadata.

Human review remains responsible for semantic equivalence and taxonomy-boundary judgments; structural validation cannot replace catalog governance.

---

## 10. Resource Loading Strategy

### 10.1 Artifact shape

Use one versioned runtime resource:

```text
product-knowledge-catalog-v1.json
```

Its exact top-level schema is:

```json
{
  "schemaVersion": 1,
  "catalogRevision": 1,
  "taxonomyVersion": "1.0",
  "expectedProductCount": 15,
  "supportedLocales": ["en", "he"],
  "categories": [],
  "products": [],
  "names": []
}
```

Flat collections keep references explicit and make uniqueness and cross-reference validation straightforward.

### 10.2 Bundle membership

Place resources under the file-system-synchronized `WayTask/Resources/ProductKnowledge/` tree. Verify target membership and the built app bundle in tests and QA; do not rely solely on Xcode UI appearance.

### 10.3 Catalog content

The approved initial content is:

- All 15 taxonomy v1.0 categories.
- English and Hebrew category names.
- The exact taxonomy semantic icon keys.
- The 15 pilot Product Concepts with permanent IDs `prd_pilot_0001` through `prd_pilot_0015`.
- The exact English/Hebrew names and approved aliases in `PilotProductCatalog.md`.

The pilot's coverage gaps remain visible: `meat_fish`, `snacks`, and `pharmacy` have no pilot product, and `uncategorized` has no curated product. WT-022A must not invent products to fill those gaps.

### 10.4 Source of truth and synchronization

- Runtime JSON is authoritative for the app.
- `PilotProductCatalog.md` is the human-readable review record for product identity, names, aliases, categories, and reasons.
- `ProductTaxonomy.md` is authoritative for category IDs, meaning, localized names, and icon keys.
- The app never parses Markdown.
- JSON, affected Markdown, and validation must be updated in the same review. A mismatch blocks shipping.
- Revision 1 is WayTask-authored content for common Israeli shopping behavior, supports `en` and `he`, and includes no third-party catalog data.

### 10.5 Catalog governance

- Any team member may propose a catalog change.
- The Product owner reviews concept identity, names, aliases, and category meaning.
- The implementing engineer reviews schema, stable IDs, and validation. One person may hold both roles on a small team if the checklist is recorded.
- Released Product IDs never change, get repurposed, or get reused.
- Category corrections require explicit Product review against `ProductTaxonomy.md`, an updated assignment reason, and a `catalogRevision` increment.
- Alias changes require Product review and must remain equivalent expressions, not brands, subtypes, or packages.
- Icon keys come only from the taxonomy; schema v1 has no product icon override.
- Released products are changed to `inactive`, never deleted. Their IDs remain reserved.
- `schemaVersion` changes only for incompatible JSON shape or field semantics. Content changes increment `catalogRevision`.
- Revision 1 must remain at or below 100 KiB uncompressed.
- No separate manifest, checksum, or detached signature is required for catalog v1. Automated validation checks the exact source and packaged file; the signed app bundle provides distribution authenticity.

### 10.6 Generator decision

**Generator deferred; validated manual pilot JSON is approved for WT-022A.**

The fixed 15-product pilot is small enough for direct transcription and row-by-row review. A generator would add a second transformation boundary and build tooling without solving a current scale problem. Automated structural and exact-content validation is required before shipping. Reconsider a generator only when catalog size or update frequency makes manual synchronization unsafe.

---

## 11. Error Handling Strategy

### 11.1 Typed errors

`ProductKnowledgeError` should distinguish:

- `catalogMissing`
- `catalogUnreadable`
- `unsupportedSchemaVersion`
- `unsupportedTaxonomyVersion`
- `decodingFailed`
- `validationFailed`
- `repositoryUnavailable`

Validation violations use stable codes plus safe record identifiers and JSON paths where possible.

### 11.2 Failure behavior

- Loading is all-or-nothing.
- No malformed, partially decoded, or partially valid catalog becomes visible.
- No network retry occurs.
- No user data is created, changed, or deleted.
- No app alert is introduced because no production feature consumes the repository in this phase.
- Tests fail the build for an invalid shipped resource.

### 11.3 Diagnostics

If later composition adds diagnostics, record only:

- Error code.
- Schema/catalog/taxonomy versions when available.
- Violation count and stable violation codes.

Do not send product names, aliases, barcodes, raw JSON, or user data to Sentry.

---

## 12. Unit Testing Strategy

### 12.1 Test-target prerequisite

Create a real `WayTaskTests` XCTest target before adding Product Knowledge production files. The test target must host against `WayTask`, use `@testable import WayTask`, and run from the shared `WayTask` scheme.

### 12.2 Legacy behavior characterization

With an in-memory SwiftData container, assert the current manual creation behavior:

- A non-empty trimmed name creates one `Product`.
- Optional image data is preserved.
- The product source remains manual.
- No `ShoppingListEntry` is created.
- No `ShoppingItem` is created by library-only manual save.
- No legacy `ProductKnowledge` record is created by the standard manual path.
- Repeating the same manual name still creates a second `Product`.
- Save failure behavior remains owned by the existing path.

These tests describe current behavior; they do not endorse it as the future Smart Product Creation behavior.

### 12.3 Domain tests

- Strong IDs encode/decode without locale dependence.
- Every Product Entity has the concept-only Phase 1 shape.
- Default name and category references.
- Entity equality/hash behavior.
- English and Hebrew Unicode round trips.
- No stored normalized name, variant, retail, or resolved category icon field.

### 12.4 Validator tests

Use one minimal valid fixture and mutate one condition per test:

- Duplicate/missing IDs.
- Invalid category set or icon mapping.
- Parent/subcategory in taxonomy v1.
- Missing English/Hebrew name.
- Invalid default-name ownership.
- Orphan product/name/category references.
- Duplicate preferred name.
- Repeated alias.
- Unsupported status, version, or locale.
- Unsupported variant, brand, barcode, package, subcategory, or product icon field.
- Count mismatch.

### 12.5 Loader tests

- Valid catalog load.
- Missing catalog.
- Invalid JSON.
- Unsupported versions.
- Validation failure propagation.
- No partial result after failure.
- Correct injected-bundle behavior.

### 12.6 Repository tests

- Exact entity lookup.
- Unknown ID returns `nil`.
- Names are scoped to the product.
- Preferred locale name, then English fallback.
- Category and icon fallback resolution.
- Snapshot data cannot be mutated through returned values.
- Concurrent read safety.

### 12.7 Shipped-resource conformance

Load the exact resource packaged for the app and assert every rule in Section 9.5. The test must fail whenever the runtime JSON diverges from the approved Product IDs, taxonomy, names, aliases, assignments, counts, or schema.

### 12.8 Build gates

The implementation is not complete until:

- Debug app build passes.
- Release app build passes with code signing disabled for CI/local verification.
- All unit tests pass.
- Test discovery shows `WayTaskTests` in the shared scheme.
- No new package dependency is present.

---

## 13. QA Plan

### 13.1 Automated QA

- Run all Product Knowledge unit tests.
- Run legacy product-creation characterization tests.
- Inspect the built app bundle for `product-knowledge-catalog-v1.json`.
- Validate the exact packaged JSON rather than only a source-tree copy.
- Verify the packaged resource does not exceed the 100 KiB revision-1 budget.
- Verify no Product Knowledge loader call is reachable from app startup.
- Compare the SwiftData model list before and after implementation; it must be identical.
- Compare Package.resolved before and after; it must be identical.

### 13.2 Manual regression QA

On a clean install and an install with existing user data:

1. Launch the app online and in Airplane Mode.
2. Open Products and add a name-only manual product.
3. Add a manual product with a photo.
4. Repeat an existing product name and confirm current duplicate behavior is unchanged.
5. Confirm the saved product appears in the Product Library.
6. Add that product to Shopping and remove it.
7. Exercise current Product Library filtering and search.
8. Open the scanner and verify the existing barcode/manual fallback flow still opens.
9. Confirm Settings' existing “Learned products” count has not been replaced by the new catalog count.
10. Relaunch and confirm startup/backfill behavior is unchanged.

Expected user-visible result: no new screen, row, category, icon, suggestion, loading state, error, or behavior.

### 13.3 Data-safety QA

- Snapshot the counts of existing SwiftData models before and after regression testing.
- Confirm no new SwiftData store/table/model is introduced.
- Confirm existing Product, ShoppingItem, ProductKnowledge, ProductHistory, and ShoppingListEntry rows are unchanged except for actions deliberately performed during QA.
- Confirm no migration ledger, feature flag, or UserDefaults key is added.

---

## 14. Rollback Plan

WT-022A is additive and non-integrated, so rollback does not require a user-data migration or database downgrade.

Rollback steps:

1. Remove the new `WayTask/ProductKnowledge/` production files.
2. Remove `product-knowledge-catalog-v1.json`.
3. Remove the `WayTaskTests` target/files only if the entire foundation is being abandoned; otherwise retain the characterization safety net.
4. Revert only the Product Knowledge/test-target hunks in `project.pbxproj` and the shared scheme.
5. Build and run the existing manual regression checklist.

Rollback guarantees:

- No Product Entity records require cleanup because none are persisted.
- No existing SwiftData schema was changed.
- No existing Product, ShoppingItem, ProductKnowledge, or ProductHistory row was migrated.
- Removing an unused bundled catalog does not affect current runtime behavior.
- An older app build can read the same user store because WT-022A adds no store schema.

Do not delete or rename the current `ProductKnowledge.swift` or its stored data as part of rollback.

---

## 15. Risks and Approval-Gate Review

### 15.1 Gate interpretation

These gates determine whether implementation may begin. They do not claim that implementation deliverables such as the test target or JSON resource already exist. Implementation completion remains governed by Sections 16 and 17.

### 15.2 WT-022A approval gates

| Gate | Previous status | Resolution | Evidence section | New status |
|---|---|---|---|---|
| B1 — Product Identity | OPEN | `ProductEntity` is a generic Product Concept only. Variants, brands, sizes, prices, and barcodes are excluded. Existing Product/Shopping persistence remains unchanged and unlinked; custom products remain valid; aliases are metadata only; later linking must retain a display-name snapshot. | `SmartProductKnowledge.md` §6.1; `ProductEntityDataModel.md` §2; this plan §6.6 | **PASS** |
| B2 — Pilot Catalog Production Governance | OPEN | Exact manual promotion of the 15 pilot concepts is approved. Runtime filename/schema/count, stable IDs, ownership, review, alias/category/icon rules, deactivation, versioning, validation, and Markdown synchronization are defined. | `PilotProductCatalog.md` §12; `ProductEntityDataModel.md` §19; this plan §§9–10 | **PASS** |
| B3 — Unit-test target prerequisite | OPEN as an implementation-state item | Reclassified from architecture blocker to the first enforceable implementation prerequisite. `WayTaskTests` must be created and a trivial test must run before any foundation production file or resource is added. | This plan §§4.4–4.5, 12.1, and 16 steps 2–3 | **PASS** |
| B4 — Effective worktree safety | OPEN as an execution-state item | The effective worktree and current code paths were re-audited; unrelated changes are explicitly preserved. Implementation begins with a scoped status/diff check and narrow project edits rather than requiring destructive cleanup. | This plan §§3.1–3.7, 5, and 16 step 1 | **PASS** |

All WT-022A approval gates are PASS. There are no remaining documentation or design blockers to starting implementation.

### 15.3 Implementation risks

| Risk | Impact | Control |
|---|---|---|
| New `ProductEntity` becomes a third active canonical model | Architecture drift | Plain read-only domain value; no SwiftData registration, writes, or consumers |
| New repository is confused with legacy `ProductKnowledgeService` | Wrong integration or duplicate ownership | Distinct type names and no modification to the legacy service |
| Promoted pilot IDs are accidentally changed | Broken stable references | Conformance-test exact `prd_pilot_0001`–`0015`; never rename or reuse after release |
| Older architecture examples leak invalid IDs/icons | Taxonomy divergence | Exact validator allowlist from `ProductTaxonomy.md` |
| Names become duplicated sources of truth | Rename/locale drift | `ProductName` rows authoritative; entity stores only `defaultNameID` |
| Category and icon conflict | Inconsistent semantics | Store one category ID; derive its icon from the taxonomy; no product override field |
| Invalid catalog ships | Repository unavailable later | Strict schema/semantic validation, exact-resource tests, fail build |
| Bundle resource is omitted from target | Runtime load failure | Built-bundle inspection and loader integration test |
| Full JSON/in-memory approach is reused at 50,000 products | Performance failure | Label adapter as small-catalog only; require later persistence/search ADR and benchmarks |
| MainActor default leaks into domain/repository API | Poor concurrency boundary | Explicit Sendable values, actor-isolated adapter, compiler tests |
| Test-target project edits overwrite current project work | Build/config loss | Narrow `.pbxproj` edit after clean baseline review; inspect diff |
| Catalog fixture expands into search/UI/Gemini work | Scope failure | Enforce non-goals and reject those dependencies in review |
| Manual JSON and Markdown diverge | Incorrect runtime content | Same-review updates, row-by-row Product review, exact-content tests; reconsider generator only if scale demands it |
| Hebrew text or aliases are damaged | Incorrect catalog content | UTF-8 JSON, Unicode round-trip tests, exact conformance fixtures |

### 15.4 Accepted residual limitations

- The first repository supports exact ID reads only.
- The first promoted catalog contains only 15 concepts and covers 11 categories.
- No catalog item uses a subcategory or product-specific icon.
- No current user benefits from suggestions until a separately approved integration phase.
- The in-memory adapter is intentionally temporary for a small seed and does not resolve the persistence/search ADR.

---

## 16. Ordered Implementation Sequence

1. **Rebaseline the repository.** Record the effective source state, current `.pbxproj` diff, target list, and relevant SwiftData behavior while preserving unrelated changes.
2. **Add `WayTaskTests`.** Create the unit-test target and shared scheme; verify a trivial test runs before adding foundation code or resources.
3. **Add legacy characterization tests.** Capture current manual Product Library creation behavior in an in-memory SwiftData container.
4. **Create minimal domain values.** Implement Product ID, Product Entity, Product Name, and Product Category without framework/persistence coupling.
5. **Create the wire catalog DTO.** Implement schema version 1 exactly as specified in `ProductEntityDataModel.md` §19.
6. **Implement the pure catalog validator.** Complete all invariant tests before adding bundle I/O.
7. **Implement the bundle loader.** Add resource lookup, version checks, decode, validation, and atomic failure.
8. **Implement the immutable repository.** Build exact-ID maps only from a validated snapshot.
9. **Create the governed resource manually.** Transcribe the approved taxonomy and 15 pilot concepts into `product-knowledge-catalog-v1.json`.
10. **Perform content review.** Compare all 15 IDs, names, aliases, categories, and icon derivations row by row with the approved Markdown.
11. **Add exact resource-conformance tests.** Pin category IDs, icon keys, Product IDs, names, aliases, assignments, schema, and counts.
12. **Verify isolation.** Confirm no modification to app composition, SwiftData models, views, services, providers, or existing resources.
13. **Run automated build/test gates.** Test Debug and Release and inspect the built resource bundle.
14. **Run manual regression and data-safety QA.** Validate current manual, Shopping, scanner, Settings, and startup behavior.
15. **Review the final diff against scope.** Reject search, UI, Product Validator, Product Generator, Gemini, camera, barcode, migration, and user-data changes.

No later step may be pulled forward past its gate.

---

## 17. Acceptance Criteria

WT-022A implementation is complete only when:

- Implementation follows the four PASS gate resolutions in Section 15.
- A real unit-test target runs in the shared scheme.
- The approved catalog loads fully offline through an injected bundle.
- Every structural, taxonomy, identity, locale, alias, icon, schema, count, and reference validation passes.
- The read-only repository returns correct entities, names, categories, and derived icon keys by exact ID.
- Invalid data produces a typed error and no partial snapshot.
- Current manual product creation behaves exactly as characterized.
- No SwiftData schema, existing Swift file, UI, provider, existing resource, or user data is modified; only the approved new bundle resource is added.
- No search, autocomplete, Product Validator, Product Generator, Gemini, camera, barcode, or migration implementation is present.
- The rollback requires only removing additive code/resources/project-target entries.

---

## 18. Planning Deliverable Summary

### Documentation updated by WT-022A.1

- `docs/Implementation/WT-022A_ProductKnowledgeFoundation_Plan.md`
- `docs/Product/SmartProductKnowledge.md`
- `docs/Product/PilotProductCatalog.md`
- `docs/Architecture/ProductKnowledgeArchitecture.md`
- `docs/Architecture/ProductEntityDataModel.md`
- `docs/Architecture/ProductKnowledgeMigrationStrategy.md`
- `docs/Specifications/SmartProductCreation.md`

### Existing files inspected

Approved Product Knowledge documentation:

- `docs/Product/SmartProductKnowledge.md`
- `docs/Product/ProductTaxonomy.md`
- `docs/Product/PilotProductCatalog.md`
- `docs/Architecture/ProductKnowledgeArchitecture.md`
- `docs/Architecture/ProductEntityDataModel.md`
- `docs/Specifications/SmartProductCreation.md`
- `docs/Audits/2026-07-23_WT-020B_ExecutiveArchitectureReview.md`
- `docs/Audits/2026-07-23_WT-020_ProductAudit.md`
- `docs/Implementation/SmartProductKnowledge_Implementation.md`
- `docs/Architecture/ProductKnowledgeMigrationStrategy.md`
- `docs/Audits/2026-07-23_WT-020_RiskAnalysis.md`

Current project/source evidence:

- `WayTask.xcodeproj/project.pbxproj`
- `WayTask/WayTaskApp.swift`
- `WayTask/ContentView.swift`
- `WayTask/Models.swift`
- `ProductListView.swift`
- `ShoppingListService.swift`
- `ProductKnowledge.swift`
- `ProductKnowledgeService.swift`
- `ProductHistory.swift`
- `ShoppingMemoryService.swift`
- `ProductCandidate.swift`
- `ProductDataProvider.swift`
- `CameraView.swift`
- `CameraViewModel.swift`
- `SettingsView.swift`
- `SecretsManager.swift`
- `TESTING.md`
- `README.md`

### Key architectural decisions

- Introduce plain domain values, not another active SwiftData model.
- Keep names authoritative in `ProductName`.
- Store one approved category ID and derive the normal semantic icon.
- Use a narrow, read-only exact-ID repository for the first small bundle.
- Validate and load one immutable snapshot atomically and offline.
- Do not compose the repository into the running app in WT-022A.
- Preserve every current product-creation and persistence path unchanged.
- Promote the exact 15 pilot concepts with permanent `prd_pilot_NNNN` IDs.
- Defer the Catalog Generator; approve manually authored, validated runtime JSON.

### Documentation-only confirmation

WT-022A.1 modified Markdown documentation only. It did not modify Swift files, tests, Xcode project configuration, resources, user data, commits, or remote branches.

APPROVED FOR IMPLEMENTATION
