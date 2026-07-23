# WT-020 Product Knowledge Architecture Proposal

**Version:** 1.1<br>
**Status:** Proposed  
**Decision scope:** Phase 1 architecture; no production implementation  
**Related documents:**

- `docs/Audits/2026-07-23_WT-020_ProductAudit.md`
- `docs/Specifications/SmartProductCreation.md`
- `docs/Architecture/ProductEntityDataModel.md`
- `docs/Architecture/ProductKnowledgeMigrationStrategy.md`

---

## WT-022A Applicability

WT-022A implements only a read-only bundle-backed catalog of generic Product Concepts. It does not implement the broader persistence, search, resolution, acquisition, migration, or integration architecture in this proposal.

For WT-022A:

- `ProductEntity` means Product Concept only.
- Sellable variants, brands, sizes, prices, and barcodes are deferred.
- Existing `Product`, `ShoppingListEntry`, legacy `ShoppingItem`, `ProductKnowledge`, and `ProductHistory` persistence remain unchanged and unlinked.
- Catalog integration with product creation is deferred to Search and Autocomplete work.
- Existing custom/manual products remain valid without a catalog entity.

The broader architecture below remains future direction and must not be read as WT-022A implementation authorization where it conflicts with this narrower profile or `ProductEntityDataModel.md` version 1.1.

---

## 1. Decision Summary

WayTask should establish one canonical local `ProductEntity` and make every product-producing feature resolve to it.

The Product Entity owns reusable product knowledge. User-specific library state, shopping-list state, usage history, media files, and provider observations are stored separately and reference the Product Entity by stable ID.

The Product Knowledge Layer is accessed only through domain repositories and use cases. UI, camera, barcode, voice, and AI code do not query persistence models directly.

The primary store is a local indexed database. A versioned seed catalog is packaged with the app and imported or attached locally. Optional remote providers can propose observations, but local persistence remains authoritative and all core creation/search/save flows work offline.

---

## 2. Architecture Drivers

The design must:

- Make product creation search-first.
- Return local suggestions quickly.
- Support prefix, partial-token, and alias matches.
- Provide controlled category/subcategory values.
- Resolve meaningful cross-platform icons.
- Keep the Product Library separate from Shopping.
- Scale from hundreds to tens of thousands of knowledge entities.
- Preserve existing user data.
- Allow camera, barcode, AI, community, learning, and voice features without parallel product models.
- Avoid an AI or network dependency.
- Remain independently testable.

---

## 3. Core Domain Boundaries

### 3.1 Product Knowledge

Owns reusable facts:

- Canonical identity.
- Display and normalized names.
- Localized aliases.
- Category and subcategory.
- Search keywords.
- Semantic icon.
- External identifiers.
- Brand/variant relationships.
- Media references.
- Nutrition and provider metadata extensions.
- Provenance and verification state.
- Entity merge redirects and tombstones.

### 3.2 User Product Library

Owns user-specific state:

- Whether an entity is in the user’s permanent library.
- User-preferred display override.
- User-selected image.
- Favorite/pinned state when introduced.
- Added/updated dates.
- Local/private provenance and deletion state.

It does not duplicate canonical category, barcode, aliases, or search metadata.

### 3.3 Shopping

Owns list-specific state:

- Product Entity reference.
- Quantity and unit.
- Checked state.
- Sort order.
- Notes and list membership.

It does not own the product name/category snapshot except for an optional immutable event snapshot needed by analytics/audit.

### 3.4 Product Acquisition

Owns transient input:

- Typed text.
- Barcode observation.
- Camera recognition.
- Photo-library recognition.
- Voice transcript.
- AI/provider suggestion.

Every acquisition adapter emits a `ProductObservation` or `ProductDraft`. A resolver maps that input to zero, one, or several Product Entities before save.

---

## 4. Logical Architecture

```text
SwiftUI / future Android UI
          |
          v
Product Creation State + Use Cases
          |
          +---------------------+
          |                     |
          v                     v
ProductSuggestionService   ProductResolver
          |                     |
          +----------+----------+
                     |
                     v
          ProductKnowledgeRepository
                     |
          +----------+-----------+
          |                      |
          v                      v
 Local relational store    Local search index
 entities, aliases,        FTS/token/trigram
 taxonomy, identifiers

Camera / Barcode / Voice / AI / Import
          |
          v
 ProductObservation adapters
          |
          v
 ProductResolver -> ProductDraft -> user review -> local commit
```

Optional providers sit outside the critical path:

```text
Local miss
  -> core flow remains usable
  -> optional provider returns observation
  -> observation stored with provenance
  -> user accepts/rejects
  -> accepted resolution committed locally
```

---

## 5. Canonical Product Identity

### 5.1 Stable ID

`ProductEntity.id` is the only canonical internal product identifier.

Requirements:

- Opaque and never derived from a mutable name.
- Stable across renames, category changes, and new aliases.
- Platform-neutral string representation.
- Assigned by the seed catalog for curated entities.

WT-022A catalog IDs are assigned only by catalog governance. User-created/custom products remain in the existing user-owned model and do not receive a catalog Product ID in this phase.

### 5.2 Generic products and sellable variants

WT-022A models generic Product Concepts only, such as Milk, Oat Milk, and Bread. A sellable branded/package item such as Tnuva Milk 3% 1 L is not a Product Entity in this phase.

No `entityKind`, `variantOfProductID`, Brand, package-size, price, or barcode field is included in catalog schema version 1. A later retail-variant design may extend or separate the model, but that decision is not required to load the pilot catalog and is not made by WT-022A.

### 5.3 Merge and redirect

False duplicates are inevitable. Entity merge must:

- Select a surviving Product ID.
- Store a redirect from retired ID to survivor.
- Repoint or resolve all future references.
- Retain former names as aliases when safe.
- Never reuse a retired ID for another product.

Deleting a product from the user’s library is different from deleting Product Knowledge. Library removal must not erase a useful catalog entity.

---

## 6. Product Draft and Observation Pipeline

### 6.1 `ProductObservation`

An observation is a provider-scoped claim, not authoritative product truth. It includes:

- Source and source record ID.
- Observed names, barcode, brand, category text, image, and metadata.
- Locale.
- Confidence when applicable.
- Timestamp.
- Raw payload reference where policy allows.

Sources include manual, seed, barcode provider, camera, AI, community, and voice.

### 6.2 `ProductDraft`

A draft is the normalized, reviewable creation state:

- Optional resolved Product ID.
- Proposed display name.
- Proposed taxonomy IDs.
- Proposed semantic icon.
- Proposed external identifiers.
- User image reference.
- Source observations.
- Resolution confidence and alternatives.

Drafts are transient unless explicit crash recovery is later required.

### 6.3 Resolver outcomes

The resolver returns:

- `resolved(ProductID)` for a unique strong match.
- `ambiguous([ProductMatch])` when the user must choose.
- `new(ProductDraft)` when no safe match exists.

Resolution order:

1. Exact normalized external identifier.
2. Explicit selected Product ID.
3. Exact canonical/alias name plus compatible brand/category/locale.
4. High-confidence composite match.
5. Otherwise ambiguous or new.

The resolver must not auto-merge on name-only similarity.

---

## 7. Local Persistence Strategy

### 7.1 One logical local source of truth

Product Knowledge is one logical local database even if implementation uses:

- A packaged read-only seed database plus writable overlay; or
- A versioned seed import into the writable app database.

Repository behavior hides this choice from features.

Recommended Phase 1 approach:

1. Package a versioned, platform-neutral seed artifact.
2. Import/upsert it into the local product database by stable Product ID.
3. Keep user-created entities and user overrides in the same logical repository.
4. Record seed revision and migration state.
5. Rebuild the search index from authoritative relational rows.

### 7.2 Relational core

Use normalized tables for:

- Products.
- Localized names and aliases.
- Categories/subcategories.
- Search keywords.
- External identifiers.
- Product relationships.
- User library references.
- Shopping references.
- Provenance/observations.
- Media metadata.
- Redirects/tombstones.

Arrays serialized into newline strings are not suitable as the long-term search schema.

### 7.3 Images and large payloads

Do not load or duplicate image bytes with every Product Entity.

- Store image/media metadata in the database.
- Store local binary assets in a managed file/blob cache.
- Reference them using local asset IDs.
- Load thumbnails lazily.
- Apply size, eviction, and privacy policies independently of entity queries.

### 7.4 Transaction boundary

A save of a new product should atomically:

1. Resolve or create the Product Entity.
2. Write names/aliases/taxonomy/identifiers.
3. Create or restore the user-library reference.
4. Add Shopping membership if requested.
5. Write provenance.
6. Update or enqueue a deterministic search-index rebuild for that entity.

The UI receives success only after the authoritative rows are committed. Search-index repair can be retried from a migration/index ledger if the selected database cannot update the index in the same transaction.

---

## 8. Suggestion Engine

### 8.1 Search normalization

A shared specification, implemented natively on each platform, should:

- Apply Unicode NFKC normalization.
- Case-fold using locale-safe behavior.
- Trim and collapse whitespace.
- Normalize punctuation separators.
- Optionally fold diacritics for an additional search form.
- Preserve original and native-script names.
- Treat transliteration as an alias, not a replacement.
- Version the normalization algorithm.

Stored normalized values must be regenerated when the algorithm version changes.

### 8.2 Candidate generation

The engine searches:

1. Canonical/display name.
2. Aliases.
3. Token prefixes within multi-word names.
4. Search keywords.
5. Brand and category terms at lower weight.
6. Partial/trigram terms when the query is long enough.

The database returns a bounded candidate set. Ranking never loads the full catalog.

### 8.3 Index implementation

Use an abstract `ProductSearchIndex` interface.

Recommended adapters:

- iOS: SQLite FTS/token index behind the repository; a compatible SQLite layer may be used even if user/library state remains in SwiftData during migration.
- Android: Room/SQLite FTS or equivalent local indexed adapter.

If the runtime supports a reliable trigram tokenizer, use it for partial matching. Otherwise maintain a compact normalized n-gram table for searchable names/aliases only. The feature layer must not depend on tokenizer-specific syntax.

### 8.4 Ranking

Ranking is deterministic and testable. A starting score model:

| Signal | Relative priority |
|---|---|
| Exact canonical name | Highest |
| Exact alias | Very high |
| Canonical-name prefix | High |
| Alias prefix | High |
| Token prefix | Medium-high |
| Keyword prefix | Medium |
| Partial/trigram match | Lower |
| Category/brand text only | Lowest candidate signal |

Tie-break boosts:

- Already in the user’s Product Library.
- Recent use.
- Frequency.
- Locale match.
- Curated/confirmed verification.

Penalties:

- Deprecated/redirected entities.
- Weak provider-only observations.
- Variant mismatch.

Ranking must use stable Product ID as a final deterministic tie-breaker.

### 8.5 Query lifecycle

- Search locally after each normalized query change.
- Cancel stale work.
- Return at most 20 candidates from storage.
- Present at most eight primary results.
- Cache small recent query/result sets, not the entire catalog.
- Never fetch images during candidate search.

---

## 9. Taxonomy and Icons

### 9.1 Category model

Taxonomy version 1.0 categories have stable IDs, localized names, and semantic icon keys. It publishes no subcategories or parent relationships.

Product Entity stores:

- One required `primaryCategoryID`, with `uncategorized` as a valid fallback.

Provider category strings are observations that pass through a mapping table. They do not directly become category IDs.

### 9.2 Semantic icon model

Store `iconKey`, for example:

- `product.dairy`
- `product.fruit`
- `product.cleaning`

Each platform owns an `IconResolver`:

| Semantic key | iOS example | Android example | Text fallback |
|---|---|---|---|
| `product.dairy` | SF Symbol or bundled asset | Vector/Material/bundled asset | Dairy & Alternatives |

This prevents platform-specific asset names from entering Product Knowledge.

---

## 10. Integration Contracts

### 10.1 Product Knowledge repository

Conceptual operations:

```text
get(ProductID) -> ProductEntity?
getByExternalIdentifier(type, value) -> ProductEntity?
suggest(ProductQuery, limit) -> [ProductMatch]
resolve(ProductObservation) -> ResolutionOutcome
save(ProductDraft, destination) -> ProductSaveResult
merge(survivorID, duplicateID) -> ProductEntity
removeFromUserLibrary(ProductID) -> Void
rebuildSearchIndex(scope) -> IndexReport
```

### 10.2 Adapters

| Feature | Adapter output | Core dependency |
|---|---|---|
| Manual text | Query/Draft | Suggestion service and resolver |
| Barcode | Identifier observation | Resolver |
| Camera | Visual observation | Resolver |
| Gemini/other AI | Provider observation | Resolver |
| Voice | Text query plus locale | Suggestion service |
| Community | Signed/provider observation | Resolver/provenance |
| Learning cache | Usage/alias proposal | Repository |

No adapter creates feature-specific persistent product rows.

### 10.3 Existing `ProductCandidate`

During migration, `ProductCandidate` can remain an adapter DTO. It should not become the canonical persisted domain type. A mapper converts it to `ProductObservation`/`ProductDraft`.

---

## 11. Offline-First Rules

1. Product suggestions read only from the local database.
2. Product save commits locally before any optional remote work.
3. A network failure cannot remove manual creation.
4. Barcode checks local identifiers before provider lookup.
5. AI/provider results are optional observations.
6. Seed catalog and taxonomy ship with the app.
7. Index rebuild and migration require no network.
8. UI never displays an indefinite online-loading state before showing local results.

The local database remains the primary source of resolved product truth even when future sync is introduced.

---

## 12. Extensibility

New capabilities use extension tables and observations rather than expanding one giant row:

| Capability | Extension |
|---|---|
| Brands and variants | Brand entity plus variant relationship |
| Multiple barcodes | Product external identifiers |
| Images | Product media metadata plus asset store |
| Nutrition | Versioned nutrition profile |
| Common stores | Product-store affinity |
| AI metadata | Namespaced metadata/observation envelope |
| Community data | Provenanced contribution |
| Learning | Usage events and accepted alias/category proposals |

Frequently queried, stable fields should be promoted into typed tables/columns. Provider-specific and experimental payloads may remain namespaced JSON with schema version and provenance; they must not replace the typed core.

---

## 13. Maintainability and Testing

### 13.1 Pure components

The following should be framework-independent and unit tested:

- Query normalizer.
- Taxonomy mapper.
- Icon fallback resolver contract.
- Product resolver.
- Duplicate/merge policy.
- Ranking/scoring.
- Draft validation.
- Seed conflict policy.

### 13.2 Repository tests

Use fixture databases to test:

- Exact and alias lookup.
- Multilingual normalization.
- Prefix/partial behavior.
- Uniqueness and redirects.
- Transaction rollback.
- Seed upgrade.
- Search-index rebuild.
- 500- and 50,000-entity performance.

### 13.3 UI tests

Cover:

- Focus on open.
- Known selection and save.
- Existing-library result.
- Unknown creation.
- Ambiguous duplicate.
- Save failure preservation.
- Right-to-left layout and VoiceOver labels.

---

## 14. Scalability Review

### 14.1 500 products

Yes. The indexed architecture is intentionally more capable than required at this size and remains simple at the feature boundary. Search can complete in a few milliseconds without loading full records or images.

### 14.2 50,000 products

Yes, with the specified indexed relational implementation, bounded result sets, lazy media loading, and database-side candidate generation. It will **not** scale if implemented as the current `@Query` plus in-memory filtering or full-array upsert.

Expected safeguards:

- Indexed normalized identifiers.
- FTS/token or n-gram index.
- Pagination/bounded fetches.
- No image blobs in search rows.
- Measured release-build performance.
- Incremental or rebuildable index.

### 14.3 Beyond 50,000

The same contracts remain valid. Storage/index implementation can change without changing UI, resolver, or provider adapters.

---

## 15. Architecture Review Checklist

| Question | Answer |
|---|---|
| Will this work with 500 products? | Yes; local indexed queries are comfortably within target. |
| Will this work with 50,000 products? | Yes, contingent on database-side indexed search and bounded/lazy reads. |
| Can iOS and Android use the same conceptual model? | Yes; IDs, entities, taxonomy, observations, and repository contracts are platform neutral. |
| Can Barcode, Images, AI Metadata, and future fields be added without redesign? | Yes; external identifiers, media, typed extension tables, and namespaced observations are first-class extension points. |
| Does every future feature use the same Product Entity? | Yes; every adapter resolves to `ProductEntity.id`. |
| Does the solution remain Offline First? | Yes; local search and save are authoritative; providers are optional. |
| Is the architecture modular and testable? | Yes; normalizer, ranker, resolver, repositories, adapters, and icon mapping have explicit boundaries. |

---

## 16. Decisions and Non-Decisions

### Approved by this proposal

- One canonical Product Entity.
- Separate product knowledge from user/shopping state.
- Stable controlled taxonomy.
- Semantic cross-platform icon keys.
- Local indexed search.
- Provider observation/draft boundary.
- Offline-first authority.
- Extension tables rather than parallel product models.

### Deferred to implementation design

- Exact SQLite wrapper/library on iOS.
- Whether seed data is imported or attached as a read-only database.
- FTS trigram versus explicit n-gram fallback after device compatibility testing.
- Concrete schema migration API.
- Final ranking weights.
- Final seed catalog size/content and category taxonomy.

These choices can vary without changing the approved domain architecture.
