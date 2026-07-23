# WT-020 Risk Analysis

**Version:** 1.0  
**Status:** Proposed controls  
**Scope:** Smart Product Knowledge architecture and future migration  

---

## 1. Rating Method

| Rating | Meaning |
|---|---|
| Likelihood: Low | Uncommon with normal controls |
| Likelihood: Medium | Credible during implementation or growth |
| Likelihood: High | Expected without explicit control |
| Impact: Low | Local inconvenience; easy recovery |
| Impact: Medium | User-visible failure or meaningful repair |
| Impact: High | Data loss, incorrect identity, broad regression, or architecture failure |

Risk priority is qualitative because implementation choices and production data volumes are not yet fixed.

---

## 2. Risk Register

| ID | Risk | Likelihood | Impact | Primary control | Verification |
|---|---|---|---|---|---|
| R1 | False merge combines two different products | Medium | High | Exact identifier/explicit link first; never auto-merge on name-only similarity; redirects and repair tooling | Resolver fixtures and conflict migration tests |
| R2 | Duplicate entities remain after migration | High | Medium | Idempotent mapping ledger, uniqueness constraints, conservative composite matching, later merge workflow | Count reconciliation and duplicate reports |
| R3 | Migration drops product, shopping, image, or history data | Medium | High | Preserve legacy rows, transactional checkpoints, backups, invariants, staged cutover | Interrupted/resumed migration and rollback tests |
| R4 | Legacy and target models drift during dual write | High | High | One centralized dual-write adapter, repair ledger, short compatibility window | Shadow comparison and injected-failure tests |
| R5 | 50,000-row catalog is implemented with in-memory filtering | Medium | High | Require indexed database-side search and bounded fetch contracts | 50,000-entity release-build performance gate |
| R6 | Search index becomes stale or corrupt | Medium | Medium | Treat index as projection; version, validate, and rebuild from authoritative rows | Delete/rebuild/integrity tests |
| R7 | Multilingual normalization hides or misranks Hebrew/Arabic products | Medium | High | Versioned Unicode normalization, native-script retention, locale fixtures, RTL QA | Multilingual ranking suite and accessibility tests |
| R8 | Partial matching consumes excessive disk/memory | Medium | Medium | Index only normalized names/aliases, minimum query length, bounded n-grams, measure tokenizer options | Index-size and cold/warm benchmarks |
| R9 | Free-text categories map incorrectly | High | Medium | Controlled taxonomy, explicit alias mapping, confidence threshold, Uncategorized fallback, preserve raw source text | Taxonomy fixture and fallback-rate review |
| R10 | Platform implementations diverge | Medium | High | Shared schemas, stable IDs, normalization/ranking fixtures, contract conformance tests | Run identical fixture corpus on iOS and Android |
| R11 | Semantic icon mapping is incomplete | Medium | Low | Category inheritance, generic fallback, platform icon-map validation | Missing-key build validation |
| R12 | Storing images in core rows causes database bloat | High | Medium | Media metadata plus managed asset store, lazy thumbnails, dedup hashes, size policy | Database-size and memory profiling |
| R13 | Image migration increases launch time or fails mid-copy | Medium | Medium | Lazy/batched copy, hash verification, legacy-byte retention during rollback | Large-library migration benchmark and resume test |
| R14 | User-confirmed data is overwritten by provider/AI data | Medium | High | Field-level provenance and authority policy; observations are proposals; review before promotion | Authority matrix unit tests |
| R15 | AI becomes a hidden dependency in a non-AI phase | Medium | High | Local search/save acceptance criteria; adapters optional; timeouts never gate manual flow | Offline UI tests with all providers unavailable |
| R16 | Seed updates overwrite local aliases or overrides | Medium | High | Stable seed IDs/revisions, separate user overrides/contributions, deterministic conflict policy | Multi-revision seed upgrade tests |
| R17 | External identifier uniqueness rejects legitimate variants or accepts invalid data | Medium | High | Scheme-aware normalization and issuer scope; conflict quarantine | GTIN/provider fixture tests |
| R18 | Product deletion erases shared knowledge or leaves broken references | Medium | High | Separate library removal from entity retirement; redirects/tombstones; repository-owned delete semantics | Reference-integrity tests |
| R19 | Current downstream features still depend on ShoppingItem copies | High | High | Consumer-by-consumer migration; compatibility adapter; do not remove legacy fields early | Dependency audit and cutover checklist |
| R20 | Search ranking favors catalog matches over user intent | Medium | Medium | Usage/locale/library boosts, transparent Create action, deterministic tunable weights | Product ranking review with representative tasks |
| R21 | One-character/rapid queries create UI lag or stale results | Medium | Medium | Cancellation, bounded queries, result generation IDs, no image fetch in search | Rapid-typing UI and performance tests |
| R22 | Database implementation choice is too coupled to SwiftData or Room | Medium | High | Domain repository/search protocols; native records isolated in Data layer | In-memory/fake repository tests and adapter review |
| R23 | Metadata JSON becomes an untyped dumping ground | Medium | Medium | Namespaces, schema versions, size limits, promotion policy for stable fields | Schema registry review and payload validation |
| R24 | Provider/community payload introduces unsafe or private data | Low/Medium | High | Data minimization, provenance, payload allowlists, local privacy policy, no raw user media by default | Privacy review and storage inspection |
| R25 | No automated tests make migration/ranking unsafe | High | High | Characterization tests before schema work; release gates prohibit untested cutover | CI test target and coverage of critical policies |
| R26 | Scope expands into Gemini, barcode, cloud, or ML implementation | High | Medium | Phase acceptance criteria and adapter-only boundaries; separate backlog items | Sprint review against explicit non-goals |
| R27 | Catalog licensing or attribution is incompatible with bundled use | Medium | High | Review data source license before seed inclusion; store attribution/source metadata | Legal/product sign-off on seed manifest |
| R28 | Local catalog consumes excessive app/download storage | Medium | Medium | Seed size budget, compressed/versioned artifact, lazy media, measure per release | App-size gate and seed manifest report |
| R29 | Search/category rules encode cultural or regional assumptions | Medium | Medium | Locale-aware taxonomy aliases, reviewable defaults, user override, diverse fixtures | Regional product review |
| R30 | Redirect chains or merge cycles corrupt resolution | Low | High | Database constraints where possible, cycle detection, path compression, merge transaction | Redirect graph property tests |

---

## 3. Highest-Priority Risks

### 3.1 Identity and false merges

This is the most consequential domain risk. A false merge can change shopping membership, barcodes, images, history, and future enrichment for two products at once.

Required controls:

- Product ID never derives from name.
- Exact external identifier is the strongest automatic signal.
- Composite matching includes locale/category/brand where available.
- Name-only similarity produces an ambiguity, not a merge.
- Merge creates a reversible/auditable redirect.
- Shopping and library references resolve through redirects.

### 3.2 Migration and dual-model drift

The current app deliberately maintains Product and ShoppingItem compatibility copies. Adding another model without a bounded transition would worsen the problem.

Required controls:

- Migration ledger.
- Centralized legacy adapter.
- Idempotent backfill.
- Explicit invariants.
- Target shadow reads.
- Time-bounded dual writes.
- Legacy retirement in a later release.

### 3.3 Search scalability

The current in-memory filtering pattern is unsuitable for the knowledge catalog. A UI prototype could appear correct at 500 items and fail later.

Required controls:

- Repository contract returns bounded matches.
- Database performs candidate generation.
- Images excluded from search rows.
- 50,000-row fixture is a release gate, not an optional benchmark.
- Index size and cold-start behavior are measured alongside latency.

### 3.4 Offline authority

Existing barcode and AI integrations could accidentally shape the new creation flow around connectivity.

Required controls:

- Seed catalog and taxonomy local.
- Manual Create always present.
- Save commits locally first.
- Provider enrichment is optional.
- Offline UI tests disable every network/provider adapter.

### 3.5 Multilingual behavior

WayTask operates in a context where English, Hebrew, Arabic, brands, and transliterations may coexist. Naive lowercase/diacritic rules can cause missing or incorrect matches.

Required controls:

- Unicode normalization specification.
- Original script preserved.
- Locale attached to names and aliases.
- Transliteration stored as an alias.
- Shared fixture corpus across platforms.
- RTL and accessibility review.

---

## 4. Product Risks

### 4.1 Too many weak suggestions

Partial matching can make the list feel noisy.

Mitigation:

- Rank exact and prefix matches above partial matches.
- Require a minimum length for substring/trigram search.
- Limit visible results.
- Always retain Create action.
- Tune against real add-product tasks.

### 4.2 Auto-category feels incorrect

Users may trust a category because WayTask filled it automatically.

Mitigation:

- Only auto-select above a deterministic confidence threshold.
- Use Uncategorized otherwise.
- Let users change taxonomy through a picker.
- Treat user confirmation as stronger provenance.

### 4.3 Product Entity versus variant is confusing

Users may see Milk, a brand of Milk, and a specific package next to one another.

Mitigation:

- Display variant qualifiers consistently.
- Favor generic products for generic text queries.
- Favor exact variant for barcode and usage history.
- Add brand/package details only when needed to distinguish rows.

### 4.4 Save versus immediate add

An additional Save tap reduces accidental additions but costs speed.

Mitigation:

- Phase 1 uses explicit Save.
- Measure abandonment and time-to-add later.
- Architecture supports changing the interaction without changing persistence.

---

## 5. Technical Decision Risks

### 5.1 SQLite/FTS feature availability

Tokenizer behavior can vary by OS/runtime, particularly for trigram support.

Mitigation:

- Hide syntax behind `ProductSearchIndex`.
- Prototype supported OS versions before committing.
- Provide normalized n-gram fallback.
- Run identical functional fixtures for both adapters.

### 5.2 Split persistence during transition

SwiftData may continue to own existing app state while a dedicated SQLite index/store is introduced.

Mitigation:

- Define one repository transaction boundary.
- Document which store is authoritative in each phase.
- Use a ledger/outbox for repair if atomic cross-store writes are impossible.
- Prefer one logical database when the selected technology can meet migration and search needs.

### 5.3 Seed import time

A large JSON seed could slow first launch.

Mitigation:

- Benchmark import before choosing format.
- Ship a prebuilt validated database if needed.
- Perform versioned/background preparation while preserving manual creation.
- Never parse large media with the core catalog.

### 5.4 Over-generalized entity model

Trying to model every possible grocery fact in Phase 1 could slow delivery and create unused abstractions.

Mitigation:

- Keep the typed core narrow.
- Add explicit extension tables only at the capability boundary.
- Use namespaced metadata for experimental provider data.
- Require a query/use case before promoting metadata into the core.

---

## 6. Security, Privacy, and Data Governance

Product Knowledge is mostly low sensitivity, but user-created names, photos, store associations, and usage history can reveal personal behavior.

Controls:

- Keep local data local by default.
- Do not include raw names, barcodes, images, or voice transcripts in diagnostics.
- Separate generic catalog knowledge from user usage/history.
- Define deletion semantics for user media and overrides.
- Validate remote image URLs and content before caching.
- Bound and validate provider metadata.
- Review seed licenses and attribution requirements.
- Require explicit future consent/design for community or cloud contribution.

---

## 7. Risk Gates Before Implementation

Implementation should not start until:

- Canonical identity and variant decisions are accepted.
- Taxonomy and Uncategorized behavior are accepted.
- Search technology spike confirms supported OS behavior.
- Normalization version 1 and multilingual fixtures exist.
- Migration fixtures characterize current models.
- Seed data source and license are approved.
- Performance budgets and supported devices are defined.

Cutover should not occur until:

- All migration invariants pass.
- Offline acceptance tests pass.
- 500/50,000 search gates pass.
- Provider-off tests pass.
- Shadow-read drift is understood.
- Rollback is exercised.

Legacy retirement should not occur until:

- Downstream ShoppingItem dependencies are removed.
- Compatibility metrics are zero for the agreed period.
- Recovery and upgrade-floor policy is approved.

---

## 8. Residual Risk

Even with the proposed controls:

- Some duplicates will remain because user-entered products can be ambiguous.
- Some category mappings will fall back to Uncategorized.
- Search ranking will require product tuning after real usage.
- Platform tokenization can produce small ordering differences unless fixtures and scoring are strictly specified.
- Future cloud/community merging will require additional identity and privacy design.

These residual risks are acceptable for an offline-first Phase 1 because the architecture favors recoverable duplicates and explicit user choice over destructive automatic merging.

