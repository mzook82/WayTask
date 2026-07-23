# WT-020B Executive Architecture Review

**Version:** 1.0  
**Review date:** 2026-07-23  
**Reviewer posture:** Senior Staff Software Architect approval gate  
**Decision:** **APPROVED WITH CHANGES**  
**Implementation readiness:** **Not ready for full implementation**

---

## Review Basis

This review challenges the following WT-020 documents as one proposed system:

1. Product Audit.
2. Smart Product Creation UX Specification.
3. Product Knowledge Architecture Proposal.
4. Product Entity Data Model.
5. Suggested Folder Structure / Implementation Strategy.
6. Product Knowledge Migration Strategy.
7. Risk Analysis.

The review evaluates the proposal as if implementation approval were the next action. Statements that depend on an unresolved persistence choice, search experiment, product-identity rule, or migration mechanism are treated as unproven.

---

## 1. Executive Summary

WT-020 has the right strategic direction:

- Reusable product knowledge should be separate from Shopping state.
- Every acquisition channel should converge through common product resolution.
- Search and save must work offline.
- Product identity must not be derived from mutable names.
- Search must be indexed at catalog scale.
- Provider and AI output must not silently become authoritative truth.
- Product icons should be semantic rather than platform-specific resource names.

The proposal is nevertheless not implementation-ready.

Four issues are architectural blockers:

1. **Product identity semantics are not finished.** `ProductEntity` is expected to represent Milk, Oat Milk, and a barcode-level branded package, but the proposal does not define which level the Product Library and Shopping list reference. This ambiguity will leak into search, duplicate resolution, usage history, barcode behavior, store matching, and future nutrition.
2. **The proposed data model contains multiple sources of truth.** Canonical names, normalized names, category hierarchy, icons, variant relationships, origin, and verification are stored in more than one place without a complete consistency contract.
3. **Persistence and search correctness are deferred.** “One logical database” can physically mean one SQLite transaction, SwiftData plus an FTS sidecar, or seed database plus writable overlay. Those options have materially different atomicity, migration, rollback, and read-after-write behavior. A repository cannot hide those guarantees.
4. **Migration depends on dual writes without an atomic boundary.** The strategy recognizes drift but does not define which store is authoritative after each phase or what the user observes when one side succeeds and the other fails.

The architecture is also broader than Phase 1 needs. It defines nutrition, store affinity, metadata envelopes, contribution graphs, media stores, redirects, multiple provider adapters, and a large folder hierarchy before the core identity/search path has been proven.

The decision is **APPROVED WITH CHANGES**, not REJECTED, because the required corrections fit within the proposed direction. Full feature implementation should not start until the blocking changes in Section 8 are resolved. Focused architecture spikes, test fixtures, and proposal revisions are appropriate next work.

### Executive scorecard

| Attribute | Assessment | Executive finding |
|---|---|---|
| Simplicity | Needs material improvement | The domain boundary is simple; the proposed Phase 1 schema and folder plan are not |
| Scalability | Plausible, not demonstrated | 50,000 products are routine for SQLite, but alias/trigram size, import, multilingual tokenization, and ranking joins are unmeasured |
| Maintainability | Conditional | Strong interfaces are offset by duplicated truth and a long dual-model period |
| Extensibility | Strong but overextended | Adapter and extension ideas are good; several future tables should remain design notes, not Phase 1 schema |
| Offline first | Strong | Core behavior is correctly local, subject to seed/index recovery being finalized |
| Cross-platform | Conceptually strong, operationally incomplete | Shared concepts exist, but normalization, ID encoding, ranking, and FTS behavior are not yet deterministic across platforms |

---

## 2. Strengths

### 2.1 Accurate correction of the original problem statement

The Product Audit correctly identifies that the current app is not merely storing product strings. It already has Product, ShoppingListEntry, ShoppingItem, ProductKnowledge, ProductHistory, and ProductCandidate concepts. This prevents an unnecessary rewrite based on an obsolete premise.

### 2.2 Correct separation of reusable knowledge from user state

Separating canonical knowledge from:

- Product Library membership.
- Shopping-list membership.
- Usage history.
- Provider observations.
- Images and other large assets.

is the correct long-term boundary.

### 2.3 Strong offline-first posture

The proposal consistently requires:

- Local suggestions.
- Local save before optional enrichment.
- Local taxonomy.
- Local seed data.
- Manual creation when every provider is unavailable.
- Local barcode resolution before network lookup.

This is one of the strongest parts of the design.

### 2.4 Provider-neutral acquisition boundary

Mapping manual text, camera, barcode, Gemini, future voice, and community input into observations/drafts is a sound abstraction. It prevents persistent `AIProduct`, `BarcodeProduct`, and `ManualProduct` silos.

### 2.5 Stable identifiers and conservative merge policy

The proposal correctly rejects name-derived primary keys and prefers false duplicates over false merges. Redirects and conflict quarantine are appropriate concepts where merges cannot be avoided.

### 2.6 Semantic icon strategy

A cross-platform semantic key with platform-owned rendering is substantially better than storing SF Symbol or Android resource names in product data.

### 2.7 Search index as a rebuildable projection

Treating the search index as derived state is correct. It permits repair, normalization upgrades, and persistence replacement without losing product knowledge.

### 2.8 Migration safety mindset

The migration proposal includes:

- Idempotency.
- Checkpoints.
- Count reconciliation.
- Conflict reporting.
- Legacy retention.
- Release gates.
- Privacy-safe diagnostics.

These are good instincts even though the operational sequence needs simplification.

### 2.9 Broad risk recognition

The Risk Analysis identifies most major categories, including false merges, model drift, multilingual behavior, index corruption, image size, provider authority, platform divergence, licensing, and scope expansion.

---

## 3. Weaknesses

### 3.1 Document-by-document findings

| Document | Strongest contribution | Principal weakness |
|---|---|---|
| Product Audit | Useful static trace of the effective implementation | Not reproducible enough for migration approval: no commit hash, schema/store inspection, representative database counts, runtime verification, or measured UX/performance baseline |
| UX Specification | Good states, offline fallback, accessibility, and failure preservation | Claims “few characters and one selection” but requires selection plus a separate Save; generic-versus-variant and already-in-library behavior remain ambiguous |
| Architecture Proposal | Correct boundaries and adapter direction | Defers physical persistence/search decisions that determine transaction and consistency guarantees |
| Product Entity Data Model | Covers identity, aliases, identifiers, localization, and extension points | Over-models Phase 1 and stores several facts redundantly |
| Suggested Folder Structure | Good dependency direction | It is a folder taxonomy, not a complete implementation strategy; it is prematurely fragmented and omits concurrency/module/deployment decisions |
| Migration Strategy | Thoughtful phases, invariants, and conflict policy | Nine phases plus dual writes create a long period with more representations than today; rollback is behavioral but depends on legacy mirror completeness |
| Risk Analysis | Wide and honest risk coverage | No owners, due gates, residual ratings, or explicit risk acceptance; several high/high mitigations depend on unresolved design choices |

### 3.2 Product Entity conflates distinct semantics

The proposed entity family includes:

- Generic product intent: Milk.
- Product subtype: Oat Milk.
- Branded sellable variant.
- Barcode-level package.

`entityKind` and `variantOfProductID` can represent a graph, but the documents do not define:

- Whether Oat Milk is a concept or variant.
- Whether a ShoppingListEntry means “any milk” or a specific package.
- Whether usage of a barcode variant increases ranking for its generic parent.
- Whether images and nutrition belong only to variants.
- Whether a user can keep both a generic concept and preferred variant in the library.
- How store matching should treat concept versus variant.
- What “duplicate” means across those levels.

This is the largest domain gap.

### 3.3 “One logical database” is not a sufficient architecture decision

The proposal allows:

- Imported writable seed data.
- An attached read-only seed plus writable overlay.
- SwiftData for current state.
- SQLite/FTS for search.

These options cannot be treated as interchangeable behind a repository because they differ in:

- Atomic transactions.
- Foreign-key enforcement.
- Backup and migration.
- App downgrade behavior.
- Search-index consistency.
- Seed update conflict resolution.
- Read-your-writes guarantees.
- Failure recovery.

An abstraction can hide APIs, but it cannot erase consistency semantics.

### 3.4 Phase 1 is over-modeled

The aggregate includes or anticipates:

- Product Entity.
- Product names and aliases.
- Search keywords.
- Category and category aliases.
- Icon values.
- External identifiers.
- Brands and brand links.
- General product relationships.
- Media.
- Nutrition.
- Store affinity.
- Metadata envelopes.
- Knowledge contributions.
- UserProduct.
- Usage.
- Redirects.

The architecture says extension tables are future capability points, but the migration and folder documents frequently treat them as target Phase 1 objects. This increases schema, migration, testing, and policy surface before autocomplete has been validated.

### 3.5 Repository boundaries are too broad

The conceptual repository includes get, external lookup, suggestions, resolution, save, merge, library removal, and index rebuild. This risks becoming the same global ProductManager anti-pattern under an interface.

Query, command, search, and maintenance responsibilities should have smaller contracts even if one adapter implements several of them.

### 3.6 Folder structure is prematurely granular

The proposed tree creates many directories and single-purpose types before module boundaries are known. Physical organization should follow dependency and build boundaries, not predict every future file.

Missing from the “implementation strategy” are:

- Concrete module/package boundaries.
- Dependency injection composition.
- Concurrency and isolation model.
- Database queue/actor ownership.
- Background import/index scheduling.
- Error taxonomy and retry policy.
- Observability.
- Feature-flag ownership.
- Release sequence.

### 3.7 Future compatibility is overstated

Gemini, camera, barcode, and voice fit the draft/observation boundary without structural redesign.

Community intelligence does not. It adds:

- Cross-installation/global identity.
- Trust and moderation.
- Contribution signing/authentication.
- Conflict resolution across revisions.
- Data distribution and incremental sync.
- Abuse handling.
- Privacy and deletion propagation.

The proposed local entity/provenance model is a useful prerequisite, but community intelligence will still require a synchronization architecture. The proposal should say “compatible foundation,” not “no redesign.”

---

## 4. Missing Considerations

### 4.1 Catalog ownership and authoring

The architecture assumes a curated seed but does not assign:

- Product/catalog owner.
- Taxonomy owner.
- Supported markets and languages.
- Data source and license.
- Authoring/validation workflow.
- Release/update cadence.
- Stable ID allocation authority.
- Removal/deprecation process.
- Catalog quality metrics.

A seed catalog is a product operation, not only a file format.

### 4.2 Exact consistency contract

The proposal needs explicit answers:

- Is a saved product immediately searchable?
- What happens if entity save succeeds and index update fails?
- What happens if library save succeeds and Shopping linkage fails?
- Which operation can be retried safely?
- Can the user see a partially committed product?
- Which database/store is authoritative in each release phase?

### 4.3 Concurrency and cancellation model

Search cancellation is mentioned, but there is no architecture for:

- Serializing database writes.
- Coordinating seed import with user search.
- Preventing migration and save races.
- Updating the index while reads continue.
- Handling app background/termination.
- Isolating media writes.

### 4.4 Locale display fallback

Names carry BCP-47 locales, but there is no deterministic display algorithm for:

- Exact locale.
- Language-only fallback.
- App locale versus device locale.
- Native-script versus transliteration.
- Default catalog name.
- Mixed-language brand names.

### 4.5 Structured variant attributes

The current app already receives package size, package type, flavor, and product type. The target model does not define which of these are:

- Identity-bearing.
- Searchable.
- Display-only.
- Variant-only.
- Typed versus free text.

Barcode and nutrition features will force this decision.

### 4.6 Taxonomy multiplicity

One top-level category plus one subcategory may be too restrictive. A product can have:

- One primary merchandising category.
- Multiple dietary or functional tags.
- Different provider classifications.

The proposal should keep one primary leaf category for Phase 1 and explicitly separate tags/observed provider categories.

### 4.7 Data integrity and update authenticity

The seed/update design lacks:

- Manifest checksum.
- Signature/authenticity policy.
- Corruption recovery.
- Disk-space failure behavior.
- Atomic catalog revision activation.
- Compatibility between app schema and catalog revision.

### 4.8 Success measures

The UX has latency targets but no product outcome targets such as:

- Median characters typed.
- Median time from Add to completion.
- Known-product selection rate.
- Unknown creation rate.
- Duplicate creation rate.
- Category correction rate.
- Search abandonment.

Without these, ranking and flow complexity cannot be evaluated.

### 4.9 Representative data volumes

The proposal tests 500 and 50,000 entities but omits the operationally important middle case of 5,000. It also does not define:

- Average aliases per product.
- Language distribution.
- Keyword count.
- Variant-to-concept ratio.
- Identifier count.
- Index size budget.
- Seed import/update budget.

Row count alone is not a useful performance corpus.

### 4.10 App downgrade and restore

“Rollback” is described as switching adapters. It does not address:

- Installing an older app over a new schema.
- Restoring an older backup.
- Target-to-legacy data loss after new-only writes.
- Whether schema changes are additive and forward-only.

Behavioral rollback and binary/database downgrade are different promises.

---

## 5. Technical Risks

### 5.1 Duplicate sources of truth in the data model

| Fact | Duplicate representations | Risk |
|---|---|---|
| Product name | `ProductEntity.canonicalName`, aggregate `displayName`, and canonical/preferred `ProductName` rows | Rename and locale drift |
| Normalized name | Product Entity, ProductName, and search projection | Normalizer-version drift |
| Category | `categoryID` plus `subcategoryID` in a hierarchical Category table | Invalid ancestry and unnecessary updates |
| Icon | Required Product `iconKey`, ProductIcon value, and taxonomy inheritance | Conflicting icon source |
| Variant relationship | `variantOfProductID` plus general `ProductRelationship.variantOf` | Relationship drift |
| Origin | Entity `origin` plus KnowledgeContribution source | Mixed-source entity cannot be summarized unambiguously |
| Verification | Entity `verificationState` plus contribution verification | Field-level authority conflicts with entity-level status |
| Schema version | Store/seed versions plus per-entity `schemaVersion` | Unclear upgrade meaning |

Recommended correction:

- Keep localized ProductName rows authoritative and store a `defaultNameID` or derive a display projection.
- Store one primary leaf category ID and derive ancestors.
- Make product icon override optional and otherwise derive it.
- Choose one canonical variant relation.
- Treat origin and verification as contribution/resolution summaries, not competing truth.
- Keep schema version at store, seed, and metadata-envelope boundaries.
- Treat all normalized values as versioned projections.

### 5.2 Search design review

#### Matching

The proposal correctly includes exact, prefix, token-prefix, alias, keyword, and partial matching. It does not define:

- Whether “partial” means substring anywhere, token substring, or trigram similarity.
- Script-specific minimum query length.
- Hyphen/apostrophe behavior.
- Numeric/package queries.
- Plural/morphological behavior.
- Whether typo tolerance is out of scope.
- Which fields participate in each matching tier.

“Two or three characters according to script and index configuration” is not a cross-platform contract.

#### Ranking

“Highest,” “high,” and “medium” are not an implementable ranking specification. Additive boosts can also create incorrect inversions—for example, a frequently used partial match outranking an exact canonical match.

Use tiered ranking:

1. Match class: exact, canonical prefix, alias prefix, token prefix, partial.
2. Within the class: locale, library membership, recency/frequency, verification.
3. Stable Product ID tie-break.

Usage boosts should normally reorder within a textual match class, not defeat a stronger class.

#### Performance assessment

| Catalog | Assessment | Conditions |
|---:|---|---|
| 500 products | Will perform well with almost any sane local implementation | The proposed schema/index is more machinery than necessary at this size |
| 5,000 products | Should perform well with SQLite FTS or a compact token index | Must add this dataset to tests; in-memory scans may appear acceptable and hide the wrong implementation |
| 50,000 products | Plausible but not yet approved as proven | Requires measured alias/trigram expansion, index size, seed import, cold/warm query, updates, and multilingual behavior |

Fifty thousand small rows are not inherently difficult for SQLite. The risk comes from:

- Multiple names/aliases per entity.
- Trigram or n-gram multiplication.
- Runtime tokenizer differences.
- Ranking joins against usage/library state.
- Catalog import and index rebuild.
- Images accidentally joining search fetches.

Required benchmark matrix:

- 500, 5,000, and 50,000 entities.
- At least three alias densities.
- English, Hebrew, Arabic, mixed-script, and numeric/package fixtures.
- Cold first query and warm queries.
- Prefix, alias, token-prefix, and partial cases.
- Index size, peak memory, import time, rebuild time, single-entity update, and p50/p95/p99 latency.
- Oldest supported and representative current devices in release builds.

### 5.3 Cross-platform determinism

The conceptual model is portable. The current matching implementation plan is not yet deterministic because native Unicode libraries and SQLite tokenizers can differ.

Require:

- One written normalization algorithm.
- Golden input/output fixtures.
- One ranking fixture corpus with expected ordering.
- Canonical identifier serialization.
- Canonical timestamp/duration encoding.
- Catalog-build normalization version.
- Platform conformance in CI.

### 5.4 External identifier conflict

The data model recommends unique barcode constraints while the migration strategy allows conflicting barcodes to be quarantined. Both are reasonable, but the storage distinction is missing.

Resolved/verified identifiers may be unique. Conflicting observed identifiers must remain in an observation/conflict table until resolved; otherwise the database cannot preserve the evidence the migration promises to report.

### 5.5 Index consistency

“Update or enqueue” is too weak for the UX promise that a newly created product immediately appears in suggestions.

Choose one:

- Entity and FTS projection update in one database transaction; or
- Entity commit plus durable index outbox, with a direct exact lookup/read-through path until projection catches up.

The user-visible read-after-write rule must be explicit.

### 5.6 Provenance complexity

Field-level provenance is valuable for AI/community intelligence, but linking most rows to contributions can materially increase write and resolution complexity.

Phase 1 can use:

- Resolved Product Entity.
- Minimal source/verification on accepted names and identifiers.
- Append-only observation envelope for provider evidence.

Do not implement a generalized claim graph until a concrete conflict-resolution use case requires it.

### 5.7 Media migration

Moving image bytes out of SwiftData is rational, but it expands WT-020 into an asset-migration project. Semantic icons solve the immediate visual requirement without moving all existing photos.

Defer bulk media extraction unless profiling shows a current database problem. New media can use the asset abstraction first, with legacy bytes read through a compatibility adapter.

### 5.8 Community and synchronization

Stable local IDs alone are not enough for community intelligence. User-created local IDs need namespace and reconciliation rules before they can become shared.

The current model can accept future community observations, but community distribution/sync remains a new subsystem. This should be acknowledged explicitly.

### 5.9 Data model component verdict

| Component | Verdict | Required change |
|---|---|---|
| Product Entity | Directionally correct | Define concept/variant semantics and remove duplicated resolved fields |
| Category | Stable hierarchy is correct | Store one primary leaf category; derive ancestors; keep optional tags separate |
| Alias | Locale and alias kinds are appropriate | Make ProductName the authoritative name source; define user/curated alias acceptance and typo policy |
| Icon | Semantic cross-platform key is correct | Store only an optional product override; inherit normal icons from the primary leaf category |
| Search metadata | Names and aliases are appropriate indexed inputs | Treat normalized values/index documents as projections; constrain provider keywords and weights |
| Future extensibility | Extension-table direction is sound | Add extensions when their feature ships instead of creating the full future schema in Phase 1 |

The alias model is one of the more useful proposed additions, but it needs governance. Automatically retaining every user query as an alias can turn typos into permanent search metadata. The system should retain a query as a private user alias only after the user selects or confirms the entity, and curated/global aliases should require a separate acceptance path.

### 5.10 Future feature compatibility

| Future feature | Can use the architecture without changing the core identity model? | Finding |
|---|---|---|
| Gemini | Yes, conditionally | Fits ProductObservation/ProductDraft; acceptance and field authority must be defined |
| Camera recognition | Yes | Visual results can use the same observation/resolver path |
| Barcode scanning | Yes, after identity ADR | Multiple identifiers fit, but barcode variant versus shopping concept must be explicit |
| Community intelligence | Partially | Can submit observations, but global identity, trust, moderation, and sync require a new subsystem |
| Voice search | Yes | Transcript plus locale can enter the same query contract |
| Multiple languages | Conditionally | Name/alias locale model is suitable; deterministic normalization, display fallback, and ranking fixtures are still required |

The correct executive claim is that WT-020 creates a compatible core for these features. It does not eliminate all future architectural work, especially for community intelligence and synchronization.

### 5.11 Migration, rollback, and backward-compatibility verdict

**Migration risk: High.** The current app already synchronizes Product and ShoppingItem compatibility data. Introducing Product Entity, UserProduct, contributions, media metadata, and a search index before retiring either current representation temporarily increases the number of states that can disagree.

**Rollback quality: Incomplete.** The proposal provides a reasonable behavioral rollback—switching reads to legacy adapters—but not a database or binary downgrade. If new-only writes occur, an older app or legacy reader can lose visibility unless a complete compatibility projection exists.

**Backward compatibility: Achievable with constraints.**

- Keep schema changes additive during the rollback window.
- Declare one canonical writer after backfill.
- Generate legacy compatibility data in one direction only.
- Retain legacy IDs and records until every downstream consumer has switched.
- Test interrupted migration, low disk, corrupted index, and app termination.
- Treat old-binary downgrade as unsupported unless separately engineered and tested.
- Distinguish “feature flag rollback” from “restore an old store/app” in release communication.

The migration should not be approved until the authoritative store for every phase and the partial-failure behavior for every cross-store command are documented.

---

## 6. UX Risks

### 6.1 The known-product flow does not meet its own interaction goal

The specification says “a few characters and one selection,” but the flow is:

1. Open Add.
2. Type.
3. Tap suggestion.
4. Review replacement screen.
5. Tap Save.

For a high-confidence known local product, the review screen adds effort without changing data.

Recommended behavior:

- Tapping a known suggestion completes the unambiguous destination action.
- Show a confirmation with Undo.
- Keep explicit review/save for unknown, ambiguous, barcode/AI-enriched, or edited drafts.

If Product chooses explicit Save for safety, it should be an evidence-based decision and the product goal should stop claiming one-selection completion.

### 6.2 Generic products and variants will confuse result rows

Milk, Oat Milk, a brand, and a package variant can all appear with similar icons and categories. Without an explicit product-level rule, users may create duplicates or choose specificity they did not intend.

Search should:

- Prefer concepts for generic text.
- Prefer exact variants for barcode and sufficiently specific brand/package queries.
- Group or indent variants when multiple variants compete.
- Clearly label variant qualifiers.

### 6.3 Already-in-library is a dead-end in library-only flow

The specification shows “Already in Products” but does not define the primary action. The user may have opened Add because they could not find the product.

Options:

- Open the existing product.
- Close and reveal/highlight it in the library.
- Offer Add to Shopping when appropriate.

Do not leave the user on a non-actionable selected state.

### 6.4 Local classifier may add more complexity than value

Rule-based category confidence, category picker, subcategory picker, and icon resolution can turn unknown creation into a larger form.

For Phase 1:

- Product name is the only blocking field.
- Use a best-effort category silently when strong.
- Use Uncategorized otherwise.
- Keep correction optional and compact.

The objective is product capture, not taxonomy completion.

### 6.5 Suggestion overload

Eight suggestions plus Create, brand details, category, subcategory, and Recent/Frequent markers may be visually dense on a phone.

Start with five primary results and measure. Show only the detail necessary to disambiguate.

### 6.6 Missing UX outcome metrics

Approve measurable targets before implementation:

- Median time-to-add for known products.
- Median characters typed.
- Percentage completed with one suggestion tap.
- Duplicate rate.
- Search abandonment.
- Unknown classification correction rate.
- Accessibility completion rate for core flows.

---

## 7. Alternative Designs

### Alternative A — Minimal relational Product Knowledge core

**Recommended**

Implement only the minimum authoritative core:

```text
ProductEntity
  id
  kind: concept | variant
  conceptID (required for variant)
  defaultNameID
  primaryLeafCategoryID
  iconOverrideKey?
  status

ProductName
  productID
  locale
  kind
  value

ProductIdentifier
  productID
  scheme
  issuer?
  value
  verification

LibraryMembership
  productID
  preferredNameOverride?
  preferredMediaReference?
  addedAt

ProductUsage
  productID
  lastUsedAt
  useCount

Category
  id
  parentID?
  localized names
  iconKey

ProductObservation
  source
  payload/version
  accepted resolution?

ProductRedirect
  retiredID
  survivingID

SearchProjection
  rebuildable FTS/token data
```

Rules:

- A concept is the normal shopping intent.
- A variant always points to a concept.
- Shopping stores required concept ID and optional preferred variant ID.
- Product names are authoritative in ProductName.
- Product Entity stores only the default-name reference.
- One leaf category is stored; ancestors and icon are derived.
- Nutrition, store affinity, generalized relationships, brand entities, and generalized metadata tables are added only with their features.

Benefits:

- Preserves the approved direction.
- Removes duplicated truth.
- Clarifies Shopping semantics.
- Keeps barcode variants possible.
- Reduces Phase 1 schema and migration surface.

Tradeoff:

- Later features add extension tables, which is normal schema evolution rather than a structural redesign.

### Alternative B — Separate ProductConcept and ProductVariant tables

Use one table for generic shopping concepts and another for sellable variants.

Benefits:

- Strong relational constraints.
- Clear ownership of barcode, package, image, and nutrition.
- Easier concept-first search.

Costs:

- Two ID types and more repository methods.
- Library/search results need a union or common reference.
- More migration decisions.

Choose this if branded/barcode/nutrition variants are a near-term product priority. Otherwise Alternative A is simpler.

### Alternative C — Incrementally evolve the current Product model

Keep current `Product` as the only user-library entity, add normalized names, controlled category/icon fields, alias records, and a search projection. Defer the separate catalog/library-membership model.

Benefits:

- Lowest migration risk.
- Fastest path to autocomplete.
- Reuses current Product and ShoppingListEntry IDs.

Costs:

- Catalog products not in the library remain awkward.
- Product Knowledge and Product remain partially separate.
- A later library/catalog split is likely.

This is a viable delivery tactic if WT-020 must ship quickly, but it does not fully achieve the proposed reusable knowledge layer.

### Alternative D — Bundled JSON plus in-memory prefix index

Load a small seed catalog and build a memory index.

Benefits:

- Very simple at 500 products.
- Easy cross-platform seed sharing.

Costs:

- Poor partial matching and update behavior.
- Memory and startup scale with catalog size.
- User-created updates and 50,000-product goals force replacement.

Reject if 50,000 products is a real requirement. Accept only if Product explicitly reduces the ceiling and treats the index as disposable.

### Alternative E — Full claim/provenance graph

Persist every provider/user claim separately and resolve canonical values dynamically or through materialized projections.

Benefits:

- Strong future community and AI conflict handling.
- Complete provenance.

Costs:

- Highest implementation and test complexity.
- Harder queries and debugging.
- Not justified for Phase 1.

Do not adopt this now. The current proposal should avoid drifting halfway into it.

### Alternative comparison

| Design | Simplicity | 50k search | Barcode variants | Community foundation | Migration risk |
|---|---|---|---|---|---|
| A. Minimal relational core | High | Strong with FTS | Strong | Good prerequisite | Medium |
| B. Separate concept/variant | Medium | Strong | Strongest | Good prerequisite | Medium-high |
| C. Evolve current Product | Highest initially | Adequate with sidecar index | Existing behavior | Weak-medium | Lowest |
| D. JSON/in-memory | High only at small size | Weak | Limited | Weak | Low initially |
| E. Full claim graph | Low | Strong if projected | Strong | Strongest | Highest |

---

## 8. Recommended Improvements

### P0 — Required before full implementation

#### 1. Publish a Product Identity ADR

Define:

- Concept versus variant.
- Required relationship and invariants.
- Which ID Product Library membership references.
- Which ID Shopping references.
- Barcode resolution result.
- Usage roll-up.
- Duplicate and merge behavior across levels.
- Search presentation rules.

Recommended decision: Alternative A’s one Product ID family with strict `concept`/`variant` kinds; Shopping references concept plus optional preferred variant.

#### 2. Reduce and normalize the Phase 1 data model

Amend the data model to:

- Remove canonical-name duplication.
- Store only the primary leaf category.
- Make icon override optional and derive the normal icon.
- Select one variant relationship representation.
- Remove per-row schema version unless a concrete row payload needs it.
- Define origin/verification as resolved summaries derived from accepted observations.
- Treat normalized text as a versioned projection.
- Keep only the tables required for creation, identifiers, library membership, usage, taxonomy, observations, redirects, and search.

#### 3. Resolve the persistence/search ADR with a measured spike

Compare at least:

- SwiftData authoritative records plus a durable SQLite search projection.
- Dedicated SQLite Product Knowledge store plus explicit cross-store Shopping command handling.

The ADR must state:

- Authoritative store.
- Transaction boundaries.
- Read-after-write behavior.
- Index repair.
- Concurrency isolation.
- Seed activation.
- Backup and behavioral rollback.
- Dependency/library choice.

Do not approve “SQLite/FTS or n-gram” as the implementation decision.

#### 4. Publish an exact Search Contract

Specify:

- Normalization inputs/outputs.
- Match classes.
- Minimum query length per class/script.
- Alias and keyword behavior.
- Whether typo/fuzzy matching is explicitly out of scope.
- Tiered ranking and tie-break rules.
- Result limits.
- Locale fallback.
- Read-after-create behavior.

Add golden fixtures shared by iOS and future Android.

#### 5. Benchmark 500, 5,000, and 50,000 realistic entities

The benchmark must include alias density, languages, variants, index disk size, import/rebuild time, and cold/warm latency. The existing 20/50 ms targets must identify devices, OS versions, and measurement boundaries.

#### 6. Rewrite migration around one authority per phase

Reduce the sequence to:

1. Characterize and add target schema.
2. Backfill and reconcile.
3. Make target the canonical writer.
4. Generate a one-way legacy compatibility projection where required.
5. Switch Product Creation/Library reads.
6. Migrate downstream consumers.
7. Retire compatibility later.

Avoid bidirectional dual writes. Define behavioral rollback separately from schema/app downgrade. Keep changes additive during the rollback window.

#### 7. Define seed catalog governance

Approve:

- Data owner.
- License.
- Markets/languages.
- ID namespace.
- Taxonomy owner.
- Build/validation pipeline.
- Manifest hash/signature.
- Revision activation/rollback.
- App-size and import budgets.

#### 8. Resolve the known-product tap behavior

Recommended:

- One tap on a confident local known product completes the destination action and provides Undo.
- Unknown, ambiguous, edited, barcode-provider, and AI-derived drafts keep explicit review/save.

If explicit Save remains universal, update the objective and measure the additional step.

#### 9. Establish characterization and conformance tests first

No migration or search implementation should precede:

- A real test target.
- Current-model migration fixtures.
- Unicode normalization fixtures.
- Search ranking fixtures.
- Conflict/redirect fixtures.
- Offline/provider-disabled UI tests.

### P1 — Required before production cutover

- Define database actor/queue and background-task behavior.
- Define catalog/index corruption recovery.
- Define provider observation retention and privacy.
- Define external-identifier conflict storage.
- Define user override behavior for name, category, and media.
- Define exact locale display fallback.
- Add migration telemetry owners and thresholds.
- Add risk owners, due gates, and residual acceptance.
- Re-baseline the Product Audit against a clean commit and representative local stores before implementation.

### P2 — Defer until demanded

- Nutrition schema.
- Product-store affinity.
- Generalized product relationship kinds beyond `variantOf`.
- Full field-level claim graph.
- Community sync/distribution.
- Bulk extraction of all legacy image blobs.
- Comprehensive folder reorganization.

---

## 9. Final Decision

# APPROVED WITH CHANGES

The strategic architecture is approved:

- Canonical product identity.
- Separate knowledge, library, and Shopping state.
- Local indexed search.
- Controlled taxonomy.
- Semantic icons.
- Provider-neutral observation/draft boundary.
- Offline-first authority.

The current documents are **not approved as an implementation-ready specification**.

Full implementation should begin only after all P0 items are resolved and reviewed. Until then, approved work is limited to:

- Product identity ADR.
- Data-model simplification.
- Persistence/search spike.
- Search and normalization fixtures.
- Migration characterization tests.
- Seed governance decisions.
- UX prototype/validation for the known-product action.

This decision is not REJECTED because the recommended corrections do not require abandoning the core direction. They remove ambiguity and excess scope so the implementation can be smaller, safer, and measurable.
