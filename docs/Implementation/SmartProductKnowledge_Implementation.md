# WT-020 Suggested Folder Structure

**Version:** 1.0  
**Status:** Proposed  
**Document type:** Architecture organization only  
**Important:** This is not an implementation plan or authorization to move production files.

---

## 1. Purpose

The current project keeps many Swift files at the repository root and combines product UI, shopping behavior, store discovery, camera state, and persistence coordination in large files.

WT-020 should introduce clear ownership boundaries without requiring a big-bang repository reorganization. The structure below supports:

- Product Knowledge as a reusable feature module.
- Framework-independent domain logic.
- Replaceable local database/search adapters.
- One acquisition boundary for manual, barcode, camera, AI, and voice.
- Focused unit and integration tests.
- Platform-neutral contracts and seed assets.

---

## 2. Proposed iOS Structure

```text
WayTask/
├── App/
│   ├── WayTaskApp.swift
│   ├── AppEnvironment.swift
│   └── Navigation/
│
├── Core/
│   ├── DesignSystem/
│   ├── Diagnostics/
│   ├── Persistence/
│   ├── Localization/
│   └── Utilities/
│
├── Features/
│   ├── ProductCreation/
│   │   ├── Presentation/
│   │   │   ├── ProductCreationView.swift
│   │   │   ├── ProductCreationViewModel.swift
│   │   │   ├── ProductSuggestionRow.swift
│   │   │   └── ProductDraftEditor.swift
│   │   ├── Application/
│   │   │   ├── SearchProductsUseCase.swift
│   │   │   ├── ResolveProductUseCase.swift
│   │   │   └── SaveProductUseCase.swift
│   │   └── Tests/
│   │
│   ├── ProductLibrary/
│   │   ├── Presentation/
│   │   ├── Application/
│   │   └── Tests/
│   │
│   ├── Shopping/
│   ├── Camera/
│   ├── Map/
│   └── Settings/
│
├── ProductKnowledge/
│   ├── Domain/
│   │   ├── Entities/
│   │   │   ├── ProductEntity.swift
│   │   │   ├── ProductName.swift
│   │   │   ├── ProductIdentifier.swift
│   │   │   ├── ProductCategory.swift
│   │   │   ├── ProductIcon.swift
│   │   │   └── ProductUsage.swift
│   │   ├── Drafts/
│   │   │   ├── ProductDraft.swift
│   │   │   ├── ProductObservation.swift
│   │   │   └── ProductResolution.swift
│   │   ├── Search/
│   │   │   ├── ProductQuery.swift
│   │   │   └── ProductMatch.swift
│   │   └── Policies/
│   │       ├── ProductNormalizer.swift
│   │       ├── ProductRanker.swift
│   │       ├── ProductResolver.swift
│   │       ├── ProductMergePolicy.swift
│   │       └── TaxonomyMappingPolicy.swift
│   │
│   ├── Application/
│   │   ├── ProductKnowledgeRepository.swift
│   │   ├── ProductSearchIndex.swift
│   │   ├── ProductAssetStore.swift
│   │   ├── ProductKnowledgeService.swift
│   │   └── ProductKnowledgeError.swift
│   │
│   ├── Data/
│   │   ├── Local/
│   │   │   ├── ProductDatabase.swift
│   │   │   ├── ProductKnowledgeRepositoryAdapter.swift
│   │   │   ├── ProductSearchIndexAdapter.swift
│   │   │   ├── ProductAssetStoreAdapter.swift
│   │   │   └── Records/
│   │   ├── Seed/
│   │   │   ├── ProductSeedImporter.swift
│   │   │   ├── ProductSeedValidator.swift
│   │   │   └── ProductSeedManifest.swift
│   │   └── Migration/
│   │       ├── ProductMigrationCoordinator.swift
│   │       ├── ProductMigrationLedger.swift
│   │       └── LegacyProductMapper.swift
│   │
│   ├── Acquisition/
│   │   ├── ManualProductAdapter.swift
│   │   ├── BarcodeProductAdapter.swift
│   │   ├── CameraProductAdapter.swift
│   │   ├── AIProductAdapter.swift
│   │   └── VoiceProductAdapter.swift
│   │
│   ├── Platform/
│   │   └── ProductIconResolver.swift
│   │
│   └── Tests/
│       ├── Domain/
│       ├── Search/
│       ├── Persistence/
│       ├── Migration/
│       ├── Performance/
│       └── Fixtures/
│
└── Resources/
    └── ProductKnowledge/
        ├── catalog-manifest.json
        ├── product-catalog.json
        ├── taxonomy.json
        ├── category-aliases.json
        └── icon-map-ios.json

Contracts/
└── ProductKnowledge/
    ├── product-catalog.schema.json
    ├── taxonomy.schema.json
    ├── normalization-spec.md
    ├── ranking-fixtures.json
    └── migration-fixtures.json
```

Names are illustrative. The important decision is the dependency direction and ownership, not the exact count of files.

---

## 3. Dependency Direction

```text
Presentation
    |
    v
Application use cases
    |
    v
ProductKnowledge Domain + repository protocols
    ^
    |
Data / platform / provider adapters
```

Rules:

- Domain imports Foundation-level primitives only where necessary.
- Domain does not import SwiftUI, SwiftData, UIKit, AVFoundation, MapKit, or provider SDKs.
- Presentation does not query database records directly.
- Data adapters implement domain/application protocols.
- Camera and provider code create observations; they do not create persistent product records.
- Shopping references Product IDs; it does not own product attributes.
- Search indexes are projections and cannot be the only copy of knowledge.

---

## 4. Folder Responsibilities

### `Features/ProductCreation`

Owns:

- Search-first UI state.
- Selection and unknown-product transitions.
- Validation presentation.
- Caller destination, such as library-only or library-and-shopping.
- Save success/failure presentation.

Does not own:

- Normalization.
- Ranking.
- Duplicate resolution.
- Persistence records.
- Provider clients.

### `Features/ProductLibrary`

Owns:

- Product Library screen.
- Product editing/removal presentation.
- Library filters/sorts.
- Add/remove Shopping actions through application use cases.

### `ProductKnowledge/Domain`

Owns:

- Platform-neutral models.
- Value validation.
- Normalization and ranking specifications.
- Merge and resolver policy.
- Taxonomy rules.

### `ProductKnowledge/Application`

Owns:

- Repository/search/asset protocols.
- Product Knowledge orchestration.
- Transaction-level use-case contracts.
- Domain-facing errors.

### `ProductKnowledge/Data`

Owns:

- SQLite/SwiftData/native record mappings.
- Index statements and query implementation.
- Seed import and validation.
- Migration checkpoints.
- Asset cache adapter.

Data records are not passed directly to UI.

### `ProductKnowledge/Acquisition`

Owns translation from:

- Manual entry.
- Current `ProductCandidate`.
- Barcode provider results.
- Camera results.
- Gemini/other AI results.
- Future voice/community inputs.

Every adapter ends at `ProductObservation` or `ProductDraft`.

### `Contracts/ProductKnowledge`

Owns assets shared conceptually across platforms:

- JSON schemas.
- Field semantics.
- Normalization test fixtures.
- Ranking fixtures.
- Taxonomy IDs.
- Seed validation rules.

This folder enables iOS and Android to implement the same model without requiring a shared runtime language.

---

## 5. Protocol Placement

Place protocols with the consumer that owns the abstraction:

| Protocol | Owner |
|---|---|
| `ProductKnowledgeRepository` | ProductKnowledge/Application |
| `ProductSearchIndex` | ProductKnowledge/Application |
| `ProductAssetStore` | ProductKnowledge/Application |
| Recognition provider protocol | Acquisition/application feature that consumes it |
| Database implementation | ProductKnowledge/Data/Local |
| Icon resolver implementation | ProductKnowledge/Platform |

This keeps a provider or persistence framework from defining the domain.

---

## 6. Existing File Transition Map

This table is a future extraction guide, not a request to move files during WT-020:

| Current file/symbol | Eventual ownership |
|---|---|
| `ProductListView.swift` manual sheet | Features/ProductCreation/Presentation |
| `ProductListView.swift` library cards/filtering | Features/ProductLibrary/Presentation |
| `WayTask/Models.swift` `Product` | ProductKnowledge legacy data mapping, then Product Entity records |
| `WayTask/Models.swift` `ShoppingListEntry` | Features/Shopping/Data |
| `ShoppingListService.swift` product upsert | Product Knowledge save/resolver use case |
| `ShoppingListService.swift` list membership | Features/Shopping/Application |
| `ProductKnowledge.swift` | Legacy Product Knowledge record mapping |
| `ProductKnowledgeService.swift` | Split among resolver, repository adapter, and contribution policy |
| `ProductCandidate.swift` | Acquisition adapter DTO |
| `CameraView.swift` manual fallback | Reuse Product Creation presentation/state |
| `CameraViewModel.swift` provider coordination | Features/Camera plus Acquisition adapters |
| `OpenFoodFactsProvider.swift` | ProductKnowledge/Acquisition/Providers |
| `GeminiProductRecognitionService.swift` | ProductKnowledge/Acquisition/Providers |
| `ProductHistory.swift` | Product usage data adapter |
| `ShoppingMemoryService.swift` | Product usage application service |

---

## 7. Test Structure

### Domain tests

- Unicode normalization.
- Alias and keyword validation.
- Taxonomy ancestry.
- Icon inheritance.
- Duplicate resolver.
- Merge redirect policy.
- Provenance authority.

### Search tests

- Exact/prefix/token/alias/partial matching.
- Multilingual and right-to-left fixtures.
- Stable ranking.
- Stale-query cancellation behavior at the use-case level.

### Persistence tests

- Constraints and transaction rollback.
- External identifier uniqueness.
- Search-index rebuild.
- Asset metadata integrity.
- Seed revision updates.

### Migration tests

- Empty install.
- Current manual-only product.
- Recognized product with knowledge.
- Duplicate barcode.
- Ambiguous same-name products.
- Legacy ShoppingItem linkage.
- Interrupted/resumed migration.
- Rollback and legacy-read fallback.

### Performance tests

- 500 entities.
- 50,000 entities.
- Alias-heavy multilingual catalog.
- Cold and warm index.
- Search without image loading.

---

## 8. Android Conceptual Mapping

The same folders can map to Android packages:

```text
productknowledge.domain
productknowledge.application
productknowledge.data.local
productknowledge.data.seed
productknowledge.migration
productknowledge.acquisition
features.productcreation
features.productlibrary
```

Likely platform adapters:

| Concern | iOS | Android |
|---|---|---|
| UI | SwiftUI | Compose |
| Local records | SQLite/SwiftData adapter | Room/SQLite adapter |
| Search | SQLite FTS/n-gram adapter | Room FTS/SQLite adapter |
| Assets | File/cache adapter | File/cache adapter |
| Icons | SF Symbol/bundled map | Vector/Material/bundled map |

Domain semantics, Product IDs, taxonomy IDs, seed JSON, normalization fixtures, and ranking fixtures remain aligned.

---

## 9. Incremental Adoption Rules

1. Create new directories only when the first real type is introduced.
2. Do not move unrelated features as part of Product Knowledge.
3. Add repository/use-case seams before changing persistence ownership.
4. Keep legacy adapters clearly named and time-bounded.
5. Avoid a second “temporary” canonical product model.
6. Require tests before switching a consumer from legacy reads.
7. Remove compatibility code only after migration telemetry and invariants pass.

---

## 10. Anti-Patterns to Avoid

- A global `ProductManager` that owns search, persistence, camera, shopping, and UI state.
- SwiftData `@Model` objects used as domain types in every layer.
- Provider JSON shapes persisted as canonical Product Entity.
- Apple SF Symbol names stored in shared product data.
- Category or aliases encoded as delimiter-separated strings.
- An in-memory array search over a 50,000-row catalog.
- Separate persistent AIProduct, BarcodeProduct, and ManualProduct types.
- Images embedded in every search/list fetch.
- Folder moves that mix WT-020 with unrelated cleanup.
