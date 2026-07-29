# WT-030C - Community Feedback System Audit

**Product:** WayTask iOS  
**Audit type:** Product, Architecture, Trust, Privacy, and UX  
**Date:** 2026-07-29  
**Status:** Complete  
**Implementation authorized:** No  
**Official decision:** Moderated Evidence-to-Truth Pipeline

---

## 1. Executive Decision

WayTask does not currently have a Community Feedback System.

The current application has:

- a versioned, bundled canonical Product Catalog;
- local catalog search and local personalization;
- manual creation when a Product is not found;
- local barcode and recognition memory;
- an internal maintainer catalog-feedback log;
- a validated maintainer authoring and release toolchain;
- estimated store recommendations;
- a dormant `StoreRealityFeedback` value and zero-weight future community
  ranking signals;
- internal beta diagnostics and privacy-filtered crash diagnostics.

It does not have:

- a consumer report action;
- a report submission path;
- durable report or moderation state;
- a community evidence repository;
- reporter identity, reputation, or trust evaluation;
- report duplicate clustering;
- moderation queues, decisions, appeals, or publication linkage;
- community-driven catalog, search, or store updates;
- a cloud community service;
- a reliable cross-platform Store identity suitable for community claims.

The official architecture is a **Moderated Evidence-to-Truth Pipeline**:

```text
User Opinion
  -> received report
  -> normalized Community Evidence
  -> duplicate/conflict cluster
  -> trust-based review priority
  -> human moderation
  -> approved domain change proposal
  -> domain validation and publication
  -> versioned Catalog/Search/Store projection
```

The pipeline has a hard authority boundary:

- a report is a claim;
- a cluster is evidence;
- a trust score is prioritization;
- verification is a moderation decision;
- publication is a separate domain-governance decision;
- only a validated, published domain revision becomes Catalog Truth, Search
  Truth, or Store Truth.

No single user report becomes authoritative automatically. Repetition by one
reporter is not independent confirmation. Reputation, majority count, AI
classification, or report volume may prioritize review, but may not publish a
catalog concept, alias, barcode, taxonomy change, store closure, store metadata
change, or inventory assertion without an explicitly approved publication
policy. The default policy is human review.

The current catalog authoring, validation, versioning, regression, and stable-ID
rules are sound and should be retained. They do not need replacement for
architectural purity. Community Feedback must feed reviewed proposals into that
governance boundary; it must not bypass it.

---

## 2. Scope, Method, and Evidence

### 2.1 Scope

This audit establishes the official Community Feedback architecture for:

- missing Product and catalog-growth reports;
- search-quality reports;
- Store identity, metadata, closure, and Product-availability reports;
- evidence, duplicate, trust, moderation, privacy, and anti-abuse policy;
- catalog, search, Shopping, Store recommendation, notification, AI, offline,
  Cloud, iOS, and Android authority boundaries.

This is an architecture specification, not an implementation specification. It
does not define database tables, service endpoints, infrastructure vendors,
deployment regions, moderation tooling, or patches.

### 2.2 Sources reviewed

The audit reviewed the available Product specification and the documentation and
implementation paths that participate in Product Catalog, Search, Product
Knowledge, Product persistence, Shopping, Store discovery/ranking, Map,
notifications, diagnostics, roadmap, beta feedback, and catalog maintenance.

Primary binding sources included:

- `design/v1.0/WayTask_Product_Specification_v1.0.pdf`;
- `WT-030A_ProductStateUXAudit.md`;
- `WT-030B_ShoppingSessionBackgroundAudit.md`;
- `docs/Specifications/CanonicalProductCatalogSpecification.md`;
- `docs/Specifications/ProductSearchUXContract.md`;
- `docs/Specifications/SmartProductCreation.md`;
- `docs/Architecture/ProductKnowledgeArchitecture.md`;
- `docs/Architecture/ProductEntityDataModel.md`;
- `docs/Architecture/CatalogAwarePersistenceArchitecture.md`;
- `docs/Architecture/ProductTaxonomy.md`;
- `PRODUCT_CATALOG_GUIDE.md`;
- `shared/catalog/README.md`;
- `tools/catalog/README.md`;
- `CATALOG_FEEDBACK.md`;
- `BETA_BACKLOG.md`;
- `ROADMAP.md`;
- `CHANGELOG.md`;
- `docs/60_CHANGELOG.md`;
- `DECISIONS.md`;
- `docs/75_STORE_RANKING.md`;
- `docs/100_SHOPPING_TRIPS.md`;
- `docs/140_STORE_RESOLUTION_ENGINE.md`;
- `docs/170_BETA_DIAGNOSTICS.md`.

Relevant production and test code was traced through:

- `WayTask/ProductCatalog`;
- `WayTask/ProductKnowledge`;
- Product creation and persistence services;
- the SwiftData schema and recovery code;
- scanner, barcode, Open Food Facts, Gemini, and manual Product flows;
- Store resolution and Store ranking;
- Map and Store bottom-sheet actions;
- Shopping Plan and Shopping Session consumers;
- geofence notifications and notification navigation;
- beta diagnostics and Sentry filtering;
- catalog/search/persistence test suites;
- shared catalog fixtures, validator, authoring, and audit tooling.

The shared catalog was validated read-only with the repository tool. At audit
time it was valid at:

- schema version 1;
- catalog version 5;
- taxonomy version 1;
- 647 total and active Product concepts;
- 23 categories and 22 subcategories;
- zero inactive Products;
- zero validation errors or warnings.

### 2.3 Evidence limitations

- The requested `Version_1.0.3_ProductSpec.md` is not present. The available
  formal Product specification is
  `design/v1.0/WayTask_Product_Specification_v1.0.pdf`; `ROADMAP.md` separately
  defines Beta 1.0.3 as the planned Community Intelligence release.
- No pre-existing `WT-030C_CommunityFeedbackAudit.md` template was present.
- Several roadmap/beta documents in the repository are empty placeholders and
  provide no behavioral evidence.
- No Community Feedback backend contract or deployed service configuration is
  present. This audit does not infer one.
- Documentation that describes future Product Knowledge contributions is
  architectural intent, not proof of a current implementation.

### 2.4 Evidence rule

Current behavior in this audit means behavior verified in the current code or
current released artifacts. A roadmap item, placeholder type, future signal, or
architecture blueprint is identified as future scaffolding, not implemented
behavior.

---

## 3. Official Truth and Authority Vocabulary

Community Feedback cannot be safe until the word "truth" is scoped. The following
definitions are binding.

### 3.1 User Opinion

A **User Opinion** is one user's submitted claim, correction, rating, free-text
explanation, or observation.

Examples:

- "This result is irrelevant."
- "I did not find this Product here today."
- "This Store appears closed."
- "This should be an alias."

A User Opinion:

- may be accurate, mistaken, stale, malicious, or subjective;
- may contain useful evidence;
- is never authoritative by itself;
- does not mutate any user, catalog, search, Store, plan, or session state.

### 3.2 Community Evidence

**Community Evidence** is one or more normalized, provenance-preserving claims
about the same resolvable target and issue. It includes corroborating and
conflicting claims, freshness, independence, evidence quality, and moderation
history.

Community Evidence:

- is not a vote total;
- is not Product Truth, Catalog Truth, or Store Truth;
- does not hide disagreement;
- is time-bounded where the observed fact is volatile;
- may prioritize or inform human review;
- may influence a future reviewed projection only under an approved policy.

### 3.3 Product Truth

**Product Truth** is the user-owned Product identity and state defined by WT-030A:

- the user's stable Product UUID;
- optional canonical Product reference;
- saved display snapshots and explicit user overrides;
- library membership;
- separate list, plan, session, and historical lifecycles.

Product Truth is private and user-scoped. Community reports, catalog releases,
Store reports, AI output, and search changes do not silently rewrite it.

### 3.4 Catalog Truth

**Catalog Truth** is the currently published, versioned, validated set of Global
Product Concepts and taxonomy:

- stable Product IDs;
- canonical and localized names;
- approved aliases, keywords, and brand terms;
- category and subcategory references;
- active/inactive/replacement lifecycle;
- future reviewed SKU/barcode relationships.

Catalog Truth is not retail inventory and is not a user's Product Library. A
community candidate becomes Catalog Truth only after identity review, domain
approval, validation, regression coverage, and publication in a catalog release.

### 3.5 Search Truth

**Search Truth** is the rebuildable projection of:

- published Catalog Truth;
- approved locale and normalization rules;
- approved ranking behavior;
- bounded user-local personalization.

Search Truth is not raw query feedback. A reported synonym, misspelling, ranking
problem, or duplicate is evidence until reviewed and published through the
correct content, localization, taxonomy, or search-rule path.

### 3.6 Store Truth

**Store Truth** has two different scopes:

1. **Store identity/profile truth:** a durable Store identity and reviewed,
   source-attributed facts such as name, location, category, operating status,
   hours, and website.
2. **Store/Product observation:** a time- and market-scoped claim that a Store
   did or did not appear to offer a Product or variant.

Product availability is normally an observation or confidence estimate, not
permanent Store Truth. "Not found today" does not mean "never sold here."
Provider inventory, merchant confirmation, and reviewed community evidence retain
their distinct provenance and freshness.

### 3.7 Moderator Decision

A **Moderator Decision** establishes that evidence was reviewed under policy. It
does not itself mutate Catalog Truth, Search Truth, or Store Truth.

### 3.8 Published Domain Decision

A **Published Domain Decision** is the separately validated result of an approved
change:

- a catalog/taxonomy release;
- an approved search or localization revision;
- a reviewed Store profile revision;
- an expiring Store/Product evidence projection.

Publication is the only community-originated path into a domain truth projection.

---

## 4. Binding Authority Rules

1. No single user report may automatically become authoritative.
2. More reports do not automatically equal truth.
3. Repeated reports from one actor are not independent confirmations.
4. Trust score controls review priority, not publication authority.
5. AI may classify, summarize, cluster, or flag reports; it may not approve or
   publish domain truth under the default policy.
6. Human review is required for identity, merge, split, alias, barcode, taxonomy,
   Store closure, and Store profile publication unless a future documented
   approval policy explicitly narrows an exception.
7. The current default has no automatic truth-changing exception.
8. Community Evidence may never rewrite Product Truth.
9. Community Evidence may never mutate an active Shopping Session snapshot or
   line outcome.
10. Community Evidence may never assert collection, purchase, or Shopping-list
    resolution.
11. A catalog deactivation or redirect never deletes a user's Product.
12. A Store report never becomes a categorical inventory guarantee.
13. Conflicting evidence remains visible to moderators and confidence evaluation.
14. Raw reports, evidence clusters, moderation decisions, and published revisions
    retain separate provenance.
15. Domain validators remain the publication gate even after moderator approval.
16. The reporter's public identity is unnecessary and must not be exposed.
17. Privacy, safety, and anti-abuse restrictions apply equally to high-reputation
    reporters and moderators.

---

## 5. Current Architecture

### 5.1 Current component map

```text
Bundled shared catalog JSON
  -> ProductCatalogService
  -> ProductCatalogValidator
  -> ProductCatalogSearch
  -> Add Product autocomplete
  -> selected catalog Product or local custom Product
  -> user Product persistence

Scanner
  -> local ProductKnowledge cache
  -> Open Food Facts / Gemini / manual review
  -> local user Product + optional local recognition memory

Shopping Product intent
  -> StoreResolutionEngine
  -> saved Store + MapKit transient results
  -> StoreRealityScore
  -> estimated recommendations
  -> Map / Shopping / geofence notifications

Maintainer QA finding
  -> CATALOG_FEEDBACK.md
  -> manual investigation
  -> catalog tool / code or copy correction
  -> validation + regression tests
  -> catalog/app release
```

No consumer feedback or moderation component connects these paths.

### 5.2 Canonical Product Catalog

The current catalog is:

- packaged with the app;
- read-only at runtime;
- platform-neutral at its shared source;
- versioned and validated atomically;
- based on stable semantic Product IDs;
- concept-oriented rather than SKU/inventory-oriented;
- filtered to active Products for search;
- stored as catalog identity plus display snapshots when selected into a user's
  Product Library.

The current catalog contract correctly prevents:

- duplicate Product IDs;
- normalized canonical-name collisions;
- alias ownership collisions;
- brand-term collisions with canonical names and aliases;
- invalid category references;
- missing replacement targets;
- replacement loops.

Semantic near-duplicates still require human identity review. That is correct:
normalization cannot determine whether two Products are genuinely the same
concept.

### 5.3 Catalog update workflow

Today new Products and search terms enter through a maintainer workflow:

1. A maintainer records or receives a specific QA issue.
2. The current release is reproduced locally.
3. The candidate is checked for identity, alias ownership, category, and
   duplication.
4. A dry-run authoring command is reviewed.
5. An explicit write changes the shared catalog source.
6. Full-catalog validation runs atomically.
7. The release revision and authoring audit are updated.
8. Shared/native fixtures and regression tests verify the reported query.
9. A catalog/app release publishes the change.
10. QA marks the issue verified.

This workflow is careful, reviewable, and compatible with future community
intake. No replacement is recommended. Its limitation is intake and operational
scale: it is a developer-maintained file workflow, not a user-facing evidence or
moderation system.

### 5.4 Current Product search

Production Add Product search uses the 647-concept `ProductCatalogSearch` when the
bundle loads. The older 15-record Product Knowledge repository still exists but
is not the production autocomplete source in `WayTaskApp`.

Current search:

- is local and offline;
- normalizes Hebrew final letters, punctuation, whitespace, and niqqud;
- ranks exact name, prefix, word-prefix, contains, alias, keyword, and category
  relevance in bounded tiers;
- deduplicates results by Product ID and normalized canonical name;
- applies local frequency/recency only within the textual relevance boundary;
- caps results;
- excludes inactive Products;
- always preserves explicit user selection and manual custom creation.

Current inconsistencies relevant to this audit:

- `ProductCatalogSearch` indexes `brandTerms` and `legacyNames` together with
  aliases, although the canonical specification and authoring toolkit distinguish
  brand discovery from alias identity.
- custom creation is suppressed for an exact primary display-name match, but an
  exact unique alias may still leave a duplicate custom action visible.
- the no-match and custom-action copy contains hard-coded Hebrew behavior rather
  than complete locale parity.
- there is no consumer action to report a wrong result, missing synonym,
  misspelling, duplicate, or irrelevant result.

The first three are current search/UX inconsistencies. They are documented here
because future feedback must classify the affected authority correctly. WT-030C
does not authorize their implementation.

### 5.5 Current missing-Product behavior

When no catalog result is suitable, the user can create a custom Product locally.
That is a valid user outcome and must remain available.

A custom Product:

- becomes Product Truth for that user;
- has no automatic canonical catalog identity;
- is not transmitted as a community candidate;
- does not grow the shared catalog;
- may remain separate from an equivalent future catalog concept until an explicit
  resolution/migration policy is approved.

Therefore "user successfully added a Product" and "catalog learned a Product" are
currently separate outcomes.

### 5.6 Current scanner and Product Knowledge behavior

The scanner checks local recognition memory and may use Open Food Facts, Gemini,
or manual confirmation. Confirmed results can improve the device-local
`ProductKnowledge` recognition cache.

This local learning:

- is private device knowledge;
- is not the canonical Product Catalog;
- is not Community Evidence;
- is not synchronized to other users;
- does not create or merge Global Product Concepts;
- does not report unknown barcodes to WayTask.

Open Food Facts is used as a lookup provider. The current application does not
submit WayTask community corrections to it.

The current scanner path can save a recognized/manual user Product without a
canonical catalog ID. That preserves user control but means scan recognition and
canonical Catalog Truth remain only partially integrated.

### 5.7 Current Store and recommendation architecture

Store recommendations combine:

- user-saved `GeoLocation` records;
- transient MapKit search results;
- Product/store-type intent;
- distance;
- known Store category;
- estimated Shopping-list coverage;
- saved-Store context.

They do not use verified retailer inventory.

Current Store limitations:

- a MapKit Store is transient and runtime-only;
- runtime Store identity is derived from source, title, and coordinate;
- there is no durable cross-platform WayTask Store registry;
- saved Stores are user-local locations, not globally curated Store records;
- opening hours are not represented as authoritative persisted Store profile data;
- website data is passed through from MapKit when present;
- Product availability is estimated from categories and intent, not observed
  stock;
- transient Store and Shopping Plan context does not survive as global community
  knowledge.

The current Map Store sheet offers Navigate, Open Items for saved locations, and
Website. It offers no report action.

The UI already says "Likely here" and "Availability is estimated." That wording
correctly avoids inventory certainty and should remain the baseline. No change is
recommended to this honesty rule.

### 5.8 Current community Store scaffolding

`StoreRankingService.swift` defines:

- `StoreRealityFeedback`;
- a user-feedback signal kind;
- a community-knowledge signal kind;
- an inventory-provider signal kind.

The three future signals always return zero. `StoreRealityFeedback` has no
consumer, persistence, submission, moderation, or ranking integration. The Store
ranking documentation explicitly states that no feedback UI or Cloud Sync exists.

These declarations are extension points, not a Community Feedback System. Their
current fields are insufficient to establish reporter independence, Product
identity, Store identity, market, temporal scope, conflict, moderation, or
publication authority.

### 5.9 Current notifications

Geofence notifications carry Store, coordinate, matched Product/list context, and
navigation metadata. A tap routes to Map context.

Notifications:

- are generated from estimated runtime Shopping/Store context;
- do not contain a feedback/report action;
- do not create community evidence;
- do not verify whether a Product was found;
- do not treat Store recommendation text as inventory truth.

### 5.10 Current diagnostics

Beta Diagnostics is a developer-mode troubleshooting surface. Exports can include
diagnostic Product names and a current decision coordinate, and intentionally
exclude credentials, email, Product photos, screenshots, and route history.

Sentry receives allowlisted operational diagnostic categories after privacy
filtering.

Neither system is community intake:

- diagnostics explain technical decisions;
- Sentry reports operational failure;
- neither creates a Product/Search/Store claim;
- neither provides community consent, status, moderation, or truth governance.

They must not be repurposed silently as Community Feedback.

### 5.11 Current persistence and Cloud

SwiftData schema version 3 persists:

- `GeoLocation`;
- `ShoppingItem`;
- `Product`;
- `ShoppingList`;
- `ShoppingListEntry`;
- `ProductHistory`;
- local `ProductKnowledge`;
- `ShoppingSession`.

There is no persisted Community Report, evidence cluster, moderation decision,
outbox, account, or publication-link model. No current Community Feedback Cloud
service is present.

This audit does not prescribe a new schema or backend.

---

## 6. Current Feedback Capability Matrix

| Surface or workflow | Current user capability | Community effect | Current limitation |
|---|---|---|---|
| Add Product search | Select catalog result or add custom Product | None | Cannot report missing/wrong/duplicate result |
| Product Library | Add, scan, remove, add to Shopping | None | No report or correction action |
| Scanner/barcode | Confirm provider/AI/manual result | Device-local learning only | Unknown/wrong barcode is not community evidence |
| Shopping | Manage Products, plan, and session | None | Cannot report Store/Product availability with session context |
| Map Store sheet | Navigate, open saved items, open website | None | Cannot report closure, relocation, metadata, or availability |
| Notification | Open Map context | None | Cannot confirm found/not found; context may be transient |
| Catalog QA | Maintainer edits `CATALOG_FEEDBACK.md` | Can lead to reviewed release | Internal/manual; no community provenance or scale |
| Catalog authoring tool | Validates and publishes maintainer changes | Changes Catalog Truth after release | Not a report/moderation service |
| Store ranking | Zero-weight future signal placeholders | None | No evidence, trust, freshness, or authority |
| Beta Diagnostics | User/internal export of technical state | None | Not designed or consented as community intake |
| Sentry | Sanitized operational diagnostics | None | Not a Product/Store feedback channel |

### 6.1 Current capability conclusion

Current consumer Community Feedback capability is **none**.

The current architecture is correct in these areas and needs no change solely for
purity:

- local-first catalog search;
- explicit selection;
- manual custom Product fallback;
- stable catalog IDs;
- snapshot-preserving user Product persistence;
- human semantic identity review;
- full-catalog validation;
- versioned release and regression requirements;
- honest estimated Store wording;
- zero influence from unimplemented future community signals;
- separation of technical diagnostics from Product truth.

---

## 7. Beta, Catalog, and Roadmap Findings

### 7.1 Catalog feedback

`CATALOG_FEEDBACK.md` is an internal QA log, not a community system. It records
exact query, expected result, actual result, issue type, required fix, regression
test, and status.

The recorded issues show multiple data-quality classes:

- missing generic concepts (`CAT-001` through `CAT-003`);
- weak or incorrect ranking (`CAT-002` through `CAT-006`);
- localization inconsistency (`CAT-007`, `CAT-008`);
- missing bounded personalization (`CAT-009`).

The fixes demonstrate a good governance pattern: reproduce, classify, make the
smallest authoritative change, add a regression, release, then verify.

The log does not record:

- reporter identity or account-free receipt;
- consent or privacy notice;
- raw evidence retention;
- equivalent/duplicate reports;
- conflicting reports;
- trust or independence;
- moderator and publication decisions as separate steps;
- status visible to a reporting user;
- Store or barcode/SKU reports.

### 7.2 Beta backlog

The backlog contains:

- WT-006 Store Reporting: report closed, relocated, or inactive Stores;
- WT-007 Product Reporting: report unavailable or incorrectly listed Products.

Both are planned and have only surface-level acceptance language such as
"submitted successfully." That is insufficient to establish:

- what is being asserted;
- which stable target is affected;
- whether "unavailable" means catalog absence, Store assortment, or temporary
  stock;
- who reviews it;
- how duplicates/conflicts are handled;
- what becomes authoritative;
- what data is collected and retained.

### 7.3 Roadmap

Beta 1.0.3 is described as Community Intelligence:

- Closed Store Reporting;
- Product Reporting;
- Community Confidence;
- Store Quality Learning.

The longer-term roadmap also calls for found/not-found confirmation and improved
recommendations. These are directionally compatible with this audit, but the
roadmap does not define authority, privacy, or moderation.

### 7.4 Shared root cause

The missing Product, wrong search result, unavailable-at-Store, closed Store, and
Store metadata requests appear superficially similar because they all use the
word "report." They are different domain claims:

| Observation | Correct domain |
|---|---|
| No suitable Product concept exists | Catalog candidate |
| Brand/variant/package/barcode is missing | Brand or future SKU candidate |
| Query maps poorly to existing concept | Search/localization proposal |
| Two concepts may be the same | Catalog identity review |
| Store likely does not carry Product | Time-bounded Store/Product evidence |
| Product temporarily absent today | Short-lived availability evidence |
| Store permanently stopped carrying Product | Longer-lived assortment evidence requiring review |
| Store is closed or relocated | Store identity/profile review |
| Hours or website is wrong | Store profile/provider correction |

The common root problem is not a missing button. It is the absence of an
evidence-to-authority boundary and a report taxonomy. A single generic "Report
Product" flow would conflate Global Product Concepts, sellable variants, search
relevance, Store assortment, inventory, and user Product state.

---

## 8. Product and System Problems to Solve

### 8.1 Product problems

- Users can recover locally from a missing Product, but cannot improve the shared
  catalog.
- Users cannot explain why a search result is wrong.
- Users cannot distinguish temporary stock absence from permanent Store
  assortment.
- Users cannot report Store closure, relocation, hours, category, or website.
- Reporters cannot receive a durable receipt or resolution status.
- The app cannot explain how community information influenced a recommendation.

### 8.2 Quality and trust problems

- There is no way to establish independent corroboration.
- There is no conflict-preserving evidence model.
- There is no moderator policy.
- There is no distinction between verified evidence and published truth.
- There is no protection from spam, brigading, reputation manipulation, or bot
  submission.
- There is no freshness policy for volatile claims.

### 8.3 Architectural problems

- Current runtime Store identity is unsuitable as a durable community target.
- Current canonical catalog is concept-level; package, variant, and barcode
  reports need a future SKU/identifier layer.
- Current community ranking scaffolding lacks provenance and authority.
- Current bundled release path is safe but cannot itself provide timely
  community status or Store-evidence updates.
- No report state survives offline retry, process death, or multi-device use.
- No publication record links a reviewed report to the exact domain revision it
  influenced.

### 8.4 Privacy problems

- No data-minimization contract exists for future reports.
- "Anonymous" has not been defined.
- No policy exists for current location, raw queries, free text, photos, EXIF,
  device identifiers, IP/security logs, or account linkage.
- No retention schedule, lawful basis, controller/processor allocation, data
  subject request process, or cross-border policy has been approved.

### 8.5 Scalability problems

- A Markdown queue cannot support large community volume.
- Manual one-report-at-a-time review does not exploit duplicate clusters.
- Unstable Store targets cause fragmented evidence.
- A flat reputation number cannot represent claim volatility or independence.
- Direct app-release coupling is too slow for short-lived Store observations.

---

## 9. Official Architecture Drivers

The official architecture must:

1. preserve Community Evidence separately from every domain truth;
2. accept useful reports without requiring broad personal data;
3. work with no account while honestly describing pseudonymity;
4. preserve offline core Shopping and Product behavior;
5. give every accepted upload an idempotent receipt and understandable status;
6. cluster equivalent claims without losing provenance;
7. preserve contradictory evidence;
8. prioritize review without allowing reputation to publish;
9. require reviewed, validated domain publication;
10. keep Global Product Concept IDs stable;
11. represent SKU/barcode candidates without corrupting concept identity;
12. represent Store availability as fresh, scoped evidence;
13. prevent community changes from rewriting Product Truth or active sessions;
14. support English, Hebrew, RTL, VoiceOver, and Dynamic Type;
15. use platform-neutral report types and lifecycle semantics;
16. permit future Cloud synchronization without making Cloud a requirement for
    core offline use;
17. permit future AI assistance without delegating final authority to AI;
18. scale review through automation of safe administrative work: validation,
    idempotency, exact duplicate detection, clustering, prioritization, and
    expiration.

---

## 10. Recommended System Boundaries

### 10.1 Boundary A - Report Intake

Owns:

- user review and submission of one claim;
- minimum context needed to resolve the target;
- optional evidence;
- idempotent submission receipt;
- local pending/sent/failed status.

Does not own:

- domain truth;
- trust verdict;
- moderator approval;
- catalog or Store mutation.

### 10.2 Boundary B - Community Evidence

Owns:

- normalization;
- exact retry detection;
- equivalent-report clustering;
- provenance;
- corroboration and contradiction;
- freshness and expiry;
- evidence-quality and abuse signals.

Does not own:

- Product Truth;
- Catalog Truth;
- Store Truth;
- publication.

### 10.3 Boundary C - Trust and Triage

Owns:

- review-priority evaluation;
- independent-confirmation discounting;
- conflict and staleness flags;
- abuse-risk routing;
- human-readable reasons for priority.

Does not own:

- automatic verification;
- automatic catalog or Store change;
- public reputation ranking.

### 10.4 Boundary D - Moderation

Owns:

- policy-based review;
- evidence requests;
- duplicate confirmation where semantic judgment is needed;
- verified/rejected/expired decisions;
- reasons, reviewer accountability, and appeal/reopen behavior.

Does not own:

- bypassing catalog/search/Store domain validation.

### 10.5 Boundary E - Domain Governance and Publication

Owns:

- identity and taxonomy review;
- alias/localization review;
- search-rule and regression review;
- Store profile/source review;
- approved time-bounded Store evidence projections;
- exact version/revision publication;
- rollback/supersession.

This boundary reuses the current catalog validator and release discipline where
applicable.

### 10.6 Boundary F - Runtime Consumption

Owns:

- loading only published or explicitly approved projections;
- source/freshness/confidence presentation;
- respecting offline cache and expiry;
- applying evidence only to future eligible recommendations;
- never changing user or active-session truth implicitly.

---

## 11. Report Taxonomy and Required Context

The following requirements describe information semantics, not a database schema
or API payload.

Every report must identify:

- one report type;
- one resolvable target or an explicit "target not found" state;
- the reporter's selected claim;
- observation time when the claim is temporal;
- locale and market where relevance depends on language or geography;
- the catalog/app revision needed to reproduce the issue;
- optional explanatory evidence;
- an idempotent client receipt for safe retry.

Free text is optional and secondary to structured choices. Structured input
reduces ambiguity, improves accessibility/localization, limits personal-data
collection, and makes duplicate detection safer.

### 11.1 Missing Product reports

#### Product not found

Meaning:

- the user searched for a concept and found no suitable Global Product Concept.

Minimum context:

- exact reviewed query;
- locale/market;
- the user's chosen distinction: generic concept, brand, variant, package, or
  unknown;
- optional category suggestion;
- optional barcode or photo with separate notice.

Authority outcome:

- catalog candidate only;
- the user's local custom Product remains independent Product Truth;
- no automatic concept creation or automatic link to the local Product.

#### Brand not found

Meaning:

- the user expects brand discovery or a brand-specific sellable item.

Rules:

- a brand name is not automatically an alias for a generic concept;
- brand discovery and Product identity remain distinct;
- a moderator determines whether the claim belongs to brand discovery, a future
  Brand entity, an SKU/variant, or no catalog change.

#### Variant not found

Meaning:

- the generic concept exists, but a materially distinct flavor, formulation,
  model, or sellable variant is missing.

Rules:

- do not create a second Global Product Concept solely to absorb a retail SKU;
- do not attach the variant as an alias if it changes shopping intent;
- route to the future SKU/variant authority when available;
- until that layer exists, retain it as unresolved evidence without corrupting
  concept identity.

#### Package size not found

Meaning:

- the user needs a specific sellable package or quantity.

Rules:

- package size is not a Global Product Concept alias;
- it belongs to future SKU/package evidence;
- exact quantities and units require normalization and regional review;
- current concept search may still let the user save a local Product snapshot.

#### Category missing

Meaning:

- the controlled taxonomy lacks the needed semantic category.

Rules:

- users may propose a label and rationale;
- user text never becomes a category ID;
- taxonomy owners review cross-platform stability, hierarchy, icon semantics,
  localization, and migration impact before publication.

#### Barcode missing

Meaning:

- a barcode is not recognized or not linked to the expected sellable item.

Rules:

- barcode evidence routes to an exact identifier/SKU review;
- the barcode is never silently attached to a generic concept;
- conflicts are preserved and escalated;
- check-digit validity can reject malformed input administratively, but valid
  syntax is not proof of identity;
- one scan does not establish the barcode relationship.

### 11.2 Search-quality reports

#### Wrong search result

Capture:

- reviewed query;
- displayed result's stable Product ID;
- result position where reproducible;
- locale, catalog version, and search revision;
- structured reason: wrong identity, too broad, too weak, wrong language,
  duplicate, or other.

The report proposes investigation; it does not down-rank the result globally.

#### Missing synonym

Rules:

- the proposed expression must denote the same Product concept;
- region and language must be explicit;
- use/context phrases belong to keywords rather than aliases;
- brand-led phrases belong to brand discovery, not alias identity;
- accepted changes require collision validation and a query regression.

#### Wrong synonym

Rules:

- removal can reduce discoverability and therefore requires reproduction and
  locale review;
- conflicting regional meanings must remain explicit;
- the latest report never deletes an alias automatically.

#### Wrong language

Rules:

- distinguish wrong result language from untranslated UI copy;
- route catalog display-name issues, search matching, and UI localization to
  their separate owners;
- do not mix locale corrections into canonical identity.

#### Misspelling

Rules:

- distinguish common accepted spelling variants from one user's typo;
- normalization/fuzzy rules must not be expanded from one observation;
- if approved, add a bounded rule or reviewed discoverability term with negative
  and collision fixtures.

#### Duplicate concepts

Rules:

- require stable IDs for both candidates;
- do not merge on normalized name alone;
- compare semantic intent, variants, material attributes, history, and saved
  references;
- an approved merge uses a redirect/tombstone policy and never reuses an ID;
- a split never assigns existing user references to a new target by guess.

#### Irrelevant result

Rules:

- capture why it is irrelevant and the matching authority that exposed it;
- distinguish a bad keyword, brand-term tier, alias collision, category match, and
  personalization tie-break;
- accepted fixes preserve stronger textual relevance and include regression
  queries.

### 11.3 Store-quality reports

Store reports require a durable Store target. A transient runtime UUID derived
from title and coordinate is insufficient as the sole community identity.

Until WayTask establishes a stable Store identity contract, a report must retain
enough source attribution to be reviewed without pretending the runtime Store ID
is permanent. The exact Store registry and provider contract remain open.

#### Recommended Store does not sell Product

Meaning:

- the recommendation model predicted likely fit, but the user has contrary
  Store/Product evidence.

Context:

- Store target and source;
- canonical Product ID when available;
- future SKU/variant when material;
- observation time;
- "not found" versus staff-confirmed "not carried";
- whether the user searched/asked, when voluntarily supplied.

The report affects future confidence only after policy review. It never changes
the current Shopping line to unavailable.

#### Store permanently removed Product

Meaning:

- the reporter has evidence of a longer-lived assortment change.

Rules:

- require stronger freshness and independent evidence than a temporary absence;
- preserve the Store, Product/variant, market, and source scope;
- expire or re-review the conclusion because assortments can return;
- never present it as permanent inventory truth solely from community volume.

#### Store temporarily unavailable

Meaning:

- the Product was not available at an observed time.

Rules:

- this is short-lived evidence;
- it decays and expires quickly under a policy still to be approved;
- old reports must not continue suppressing a Store;
- it cannot trigger a delayed notification after its context expires.

#### Wrong Store category

Rules:

- distinguish MapKit/provider category, WayTask derived intent category, and
  user-saved category;
- route provider corrections to the provider where appropriate;
- a community report cannot overwrite another user's private saved Store.

#### Wrong opening hours

Rules:

- identify the displayed source and observation time;
- use authoritative provider or verified Store information where available;
- community evidence may flag the profile for review;
- holiday/special hours and ordinary hours must not be conflated.

#### Wrong website

Rules:

- capture the displayed URL and selected Store target;
- do not ask users to visit an unsafe URL as proof;
- validate candidate destinations and source ownership before publication;
- route provider-owned metadata corrections appropriately.

#### Closed, relocated, or duplicate Store

Although not listed in the minimum prompt taxonomy, these are existing roadmap
requirements and use the same Store profile authority:

- temporary closure differs from permanent closure;
- relocation should link the old and new identities rather than merely moving a
  pin;
- duplicate Store results require provider/source reconciliation;
- no one report may remove a Store from discovery automatically.

### 11.4 Evidence attachments

Photos, receipts, shelf labels, barcodes, and links are optional evidence, not
mandatory proof.

Policy requirements:

- explain the purpose before collection;
- let the user review and remove the attachment;
- strip unnecessary EXIF and current-location metadata;
- reject secrets, faces, payment details, and unrelated personal information
  where reasonably detectable;
- bound type and size;
- scan uploads for unsafe content;
- use a shorter retention policy than the moderation decision where possible;
- never use the attachment for AI training under the report-submission purpose
  without a separate, explicit policy and legal basis.

---

## 12. Official Report Lifecycle

### 12.1 Approved states

```text
Received
Under Review
Needs More Evidence
Verified
Implemented
Rejected
Duplicate
Expired
```

These states describe the report/moderation lifecycle. They do not replace
Catalog, Search, Store, Product, Shopping, or Session states.

### 12.2 State definitions

| State | Meaning | Domain-truth effect |
|---|---|---|
| Received | Intake accepted and receipt assigned | None |
| Under Review | Report/cluster is being triaged or investigated | None |
| Needs More Evidence | Current evidence cannot support a decision | None |
| Verified | Moderator accepted the claim as supported evidence | None by itself |
| Implemented | An approved domain revision was published or an approved expiring evidence projection was activated | Only the linked published revision |
| Rejected | Claim did not satisfy policy, was out of scope, or was contradicted | None |
| Duplicate | Report is linked to the canonical report/evidence cluster | None from duplicate count alone |
| Expired | Time-sensitive evidence is no longer actionable/current | None |

### 12.3 Important distinction: Verified versus Implemented

`Verified` means evidence review is complete. It does not mean the catalog or Store
has changed.

`Implemented` requires:

- an approved domain proposal;
- the correct domain validator/review;
- an exact published revision or expiring projection;
- a traceable link from the report/cluster to that publication.

A report cannot be marked Implemented merely because code was written, a moderator
agreed, or an issue was added to a backlog.

### 12.4 Allowed transitions

```text
Received -> Under Review
Received -> Duplicate
Received -> Expired

Under Review -> Needs More Evidence
Under Review -> Verified
Under Review -> Rejected
Under Review -> Duplicate
Under Review -> Expired

Needs More Evidence -> Under Review
Needs More Evidence -> Rejected
Needs More Evidence -> Expired

Verified -> Implemented
Verified -> Under Review       (audited reopen after material contrary evidence)
Verified -> Expired            (time-bounded fact expires before publication)

Rejected -> Under Review       (approved appeal/reopen)
Duplicate -> Under Review      (cluster link shown to be wrong)
Expired -> Under Review        (approved review with fresh evidence)
```

`Implemented` is terminal for that report's publication outcome. The published
domain fact may later be superseded by a new revision; the old report history is
not rewritten.

### 12.5 Automatic and human transitions

Safe administrative automation may:

- accept a well-formed report as Received;
- identify an exact retry as Duplicate;
- suggest an equivalent cluster;
- prioritize a queue;
- expire time-bounded evidence under an approved policy;
- reject structurally invalid or unsafe payloads before acceptance with a clear
  client error.

Human moderation is required by default to:

- confirm semantic duplicates;
- move evidence to Verified;
- move a verified report into a domain publication path;
- reject a substantive claim;
- reopen an appealed or materially conflicted decision.

No automatic transition may publish domain truth.

### 12.6 Reporter-facing status

Reporter status must:

- use plain, non-legalistic language;
- distinguish received, reviewing, needs information, verified, applied,
  rejected, duplicate, and expired;
- explain that "received" is not confirmation;
- avoid revealing other reporters;
- give a reason category for rejection or expiry;
- identify the canonical report outcome when safe;
- provide an accessible appeal/correction path where policy allows.

Moderation notes, abuse signals, other users' content, and sensitive reviewer
information are not automatically reporter-visible.

### 12.7 Withdrawal and privacy requests

Withdrawal is an administrative request, not a truth status:

- a locally queued report can be cancelled before upload;
- after receipt, a user can request withdrawal/deletion of personal data;
- independently verified facts or published catalog revisions are evaluated
  separately from the reporter's personal data;
- retained audit or legal records require an approved lawful basis and
  minimization policy;
- a privacy request must not be misrepresented as "Rejected."

### 12.8 Lifecycle alternatives considered

#### Binary Open / Closed

Rejected because it cannot distinguish receipt, evidence request, verification,
publication, rejection, duplication, or expiry. It would make "closed" ambiguous
to reporters and operators.

#### Shared report and domain-change state

Rejected because a Verified report is not necessarily a published catalog/search/
Store revision. Combining those lifecycles would let moderation appear to mutate
truth and would make rollback/status misleading.

#### Public voting state

Rejected because vote count describes participation, not evidence quality,
independence, freshness, or domain publication.

#### Approved lifecycle plus separate delivery and domain states

Approved:

- local delivery owns Draft/Pending/Sent/Failed/Cancelled;
- report moderation owns the eight states in Section 12.1;
- evidence clusters own corroboration/conflict/freshness;
- Catalog/Search/Store domains own their revision and publication lifecycle.

`Withdrawn` is not added as a substantive truth outcome because withdrawal and
personal-data deletion have different consequences for raw evidence, independent
verification, and an already published revision. They remain explicit
administrative/privacy actions under Section 12.7.

---

## 13. Duplicate and Conflict Architecture

### 13.1 Duplicate classes

#### Transport duplicate

The same client submission is retried because connectivity or acknowledgement was
uncertain.

Decision:

- detect through an idempotent client receipt;
- return the original report identity/status;
- never increase corroboration or reputation.

#### Same-actor repeat

The same reporter repeats the same claim about the same target and time scope.

Decision:

- link to the existing report/cluster;
- update last-observed context only under an approved rule;
- do not count as independent confirmation;
- avoid penalizing an honest retry.

#### Equivalent independent report

Different reporters make materially equivalent claims about the same stable
target, market, and relevant time window.

Decision:

- cluster while preserving each report's provenance;
- count independence after correlation checks;
- retain distinct evidence and timestamps.

#### Semantic near-duplicate

Reports appear related but may refer to different concepts, variants, Stores,
markets, or time windows.

Decision:

- suggest a cluster;
- require human semantic review before treating as equivalent.

#### Duplicate domain candidate

The proposed Product, Store, alias, or metadata change already exists or is
already under review.

Decision:

- link to the canonical candidate;
- do not create a second truth identity;
- preserve the report as supporting or conflicting evidence.

### 13.2 Duplicate key dimensions

Equivalence evaluation considers:

- report type;
- stable target identity;
- Product concept versus SKU/variant;
- Store identity and provider/source;
- language/locale;
- market/region;
- observation time and claim volatility;
- normalized structured claim;
- reporter independence;
- catalog/search revision where reproducibility matters.

Free-text similarity alone is insufficient.

### 13.3 Merge requirements

When reports or clusters are merged:

- every original report remains traceable;
- reporter receipts continue to resolve;
- the merge is reversible;
- moderation decisions identify the canonical cluster;
- no evidence, contradiction, timestamp, or attachment disposition is lost;
- report counts are not presented as a simple truth score.

### 13.4 Conflict requirements

Conflicting reports are not duplicates.

Examples:

- "found today" versus "not found today";
- "Store permanently closed" versus recent verified operation;
- proposed alias has different meaning in another locale;
- barcode points to two materially different SKUs.

Conflict handling:

- retain both sides;
- evaluate source, time, market, and independence;
- lower confidence or escalate review;
- avoid last-write-wins;
- never hide inconvenient evidence to produce a clean score.

### 13.5 Resolution strategy

The canonical resolution path is:

```text
exact retry detection
  -> structured normalization
  -> target resolution
  -> candidate cluster match
  -> independence/correlation evaluation
  -> human confirmation for semantic ambiguity
  -> preserved merge link or preserved conflict
```

---

## 14. Trust Model

### 14.1 Purpose

Trust exists to answer:

> Which evidence should be reviewed first, and how cautiously should it be
> interpreted?

It does not answer:

> What is true?

### 14.2 Trust is contextual

There is no single global "trusted user" value that grants authority.

Trust evaluation belongs to:

- a report;
- an evidence cluster;
- a claim type;
- a target/market/time context.

A reporter may have a strong history for Store hours and no history for Hebrew
catalog identity. Stable Product identity and temporary shelf availability also
need different freshness policies.

### 14.3 Evaluation dimensions

#### Target specificity

- Is the Product, SKU, Store, locale, and market resolvable?
- Is the report about the displayed result or a vague category?

#### Evidence completeness

- Does structured context support reproduction?
- Is the optional evidence relevant and internally consistent?

#### Historical accuracy

- Were prior claims later verified, contradicted, rejected, or withdrawn?
- Was the reporter consistently precise about claim type?

Historical accuracy is bounded input, not authority.

#### Freshness

- How quickly can this fact change?
- Is the observation still within its policy window?

Temporary availability decays rapidly. Product concept identity is more stable,
but a report still requires review.

#### Independent confirmations

- Are confirmations from genuinely distinct reporters/sources?
- Are timing, network, device, account, and content patterns correlated?
- Are multiple reports merely one copied campaign?

Independent confirmation receives diminishing returns. One actor cannot manufacture
independence by resubmission.

#### Conflicting evidence

- Is there recent contrary evidence?
- Is the conflict explained by market, Store branch, SKU, time, or locale?

Conflict lowers confidence or escalates review; it is never deleted to improve a
score.

#### Source strength

Source types remain distinct:

- user observation;
- merchant/Store confirmation;
- catalog curator;
- verified provider;
- public authoritative registry where applicable;
- AI inference.

A provider's authority applies only to the facts and scope it is competent to
assert. A merchant cannot define Global Product Concept taxonomy merely because it
defines its own SKU.

#### Abuse risk

- velocity and volume anomalies;
- repeated identical content;
- coordinated targeting;
- reputation farming;
- conflicting device/account/network patterns;
- unsafe attachment behavior.

Abuse risk affects routing and review, not the substantive truth by itself.

### 14.4 Trust outputs

The official model uses internal review bands rather than a public percentage:

| Band | Meaning | Allowed effect |
|---|---|---|
| Uncorroborated | One unresolved claim or weak context | Retain; normal review |
| Corroborated | Independent, materially consistent evidence exists | Higher review priority |
| High Review Priority | Strong evidence/freshness/impact warrants prompt review | Queue escalation only |
| Moderator Verified | Human review accepted evidence under policy | Eligible for domain proposal |
| Conflicted | Material recent disagreement exists | Require resolution; no silent publication |
| Expired | Evidence is outside its useful time window | No current recommendation influence |

These labels do not appear as public claims about a person's trustworthiness.

### 14.5 One-report policy

One report may:

- be received;
- trigger urgent safety or quality review;
- identify a defect that a moderator independently reproduces;
- become verified after independent authoritative evidence is obtained.

One report may not:

- automatically create or merge a Product concept;
- assign a barcode;
- add/remove an alias;
- change taxonomy;
- close or relocate a Store;
- mark a Product permanently unavailable;
- change Shopping or notification context;
- publish any truth solely because the reporter has high reputation.

The decisive evidence in a one-report case is the moderator's independent
verification or separate authoritative source, not the report alone.

### 14.6 Reputation safeguards

- Reputation cannot be bought, transferred, or publicly traded.
- Repeated low-risk reports cannot grant unilateral authority over high-impact
  changes.
- Weight is capped.
- Old history decays where relevance changes.
- Rejected reports are not automatically abuse.
- Appeals and moderator reversals repair history.
- Reporters cannot see detailed anti-abuse thresholds.
- Coordinated groups do not receive linear influence from account count.
- Moderator actions are separately audited.

### 14.7 Unresolved scoring details

This audit intentionally does not invent:

- numeric weights;
- confirmation thresholds;
- decay durations;
- reputation windows;
- exact trust bands shown to moderators;
- which provider classes qualify as authoritative for each field.

These require operational data, legal review, moderation capacity, and launch
market decisions.

---

## 15. Moderation Architecture

### 15.1 Moderation objective

Moderation protects:

- Product and Store identity;
- search quality;
- users and businesses affected by reports;
- reporter privacy;
- the integrity of community evidence;
- the release and rollback trail.

Moderation is not merely content removal. It is evidence evaluation followed by
correct domain routing.

### 15.2 Triage responsibilities

Triage determines:

- whether the target resolves;
- whether the report type is correct;
- whether it is an exact or semantic duplicate;
- whether evidence is time-sensitive;
- whether contradictory evidence exists;
- whether the report is unsafe, abusive, or out of scope;
- which domain owner must review it;
- whether more evidence is needed.

Triage may correct classification without changing the reporter's original claim.

### 15.3 Domain review responsibilities

#### Catalog identity reviewer

Reviews:

- missing concepts;
- duplicate concepts;
- merge/split/redirect;
- variant versus concept;
- barcode/SKU relationship;
- active/inactive/replacement.

#### Search and localization reviewer

Reviews:

- aliases and keywords;
- spelling and normalization;
- language/locale;
- relevance and ranking;
- weak results;
- UI copy routing.

#### Taxonomy reviewer

Reviews:

- new category/subcategory;
- category moves;
- cross-platform semantic icon;
- localization and migration impact.

#### Store reviewer

Reviews:

- Store identity and duplication;
- closure/relocation;
- category, hours, and website;
- provider routing;
- time-bounded Product/Store evidence.

#### Privacy and abuse reviewer

Reviews:

- unsafe attachments;
- personal information;
- malicious or coordinated submissions;
- deletion/restriction requests;
- access controls and retention exceptions.

One moderator may hold multiple roles operationally, but the decision must record
which policy and authority were used.

### 15.4 Evidence standards by impact

| Change class | Default evidence standard |
|---|---|
| Exact transport duplicate | Deterministic administrative check |
| Obvious malformed barcode/check digit | Deterministic administrative rejection |
| Reproducible search ranking/copy defect | Moderator reproduction against named revision |
| Missing alias/keyword | Locale and semantic review plus collision/regression validation |
| New Global Product Concept | Human identity and taxonomy review |
| Concept merge/split/redirect | Enhanced identity review and migration impact |
| Barcode/SKU link | Independent identifier verification and conflict check |
| Store website/hours | Source verification plus Store identity review |
| Temporary availability | Fresh scoped corroboration under expiring policy |
| Permanent assortment or Store closure | Stronger independent/current evidence and human review |

### 15.5 Reviewer safeguards

- Least-privilege access by role.
- No moderator reviews a conflict in which they have a material interest.
- Every substantive transition records reason and policy revision.
- High-impact decisions support second review when the future policy requires it.
- Merge, split, closure, and barcode conflict decisions are reversible or
  supersedable.
- Moderator identities are protected from public exposure but auditable
  internally.
- Queue pressure does not lower evidence standards silently.
- Reviewer performance is measured for consistency and reversals, not only speed.

### 15.6 Appeals and correction

An appeal can:

- identify target-resolution error;
- provide new evidence;
- challenge duplicate classification;
- challenge rejection or Store-impacting publication;
- request privacy correction.

Appeal behavior:

- reopens the existing history rather than erasing it;
- routes to a different reviewer for high-impact disputes where practicable;
- does not expose other reporters;
- can supersede a publication through a new reviewed domain revision;
- does not retroactively make the original report authoritative.

### 15.7 Moderation scalability

Scale comes from:

- structured report types;
- target resolution;
- idempotency;
- duplicate clustering;
- safe administrative validation;
- trust-based queue prioritization;
- expiry of volatile evidence;
- batch review of equivalent low-impact proposals;
- domain-specific reviewer queues;
- reusable policy and regression fixtures.

Scale must not come from:

- automatic truth by majority;
- hidden AI approval;
- unbounded public voting;
- high-reputation unilateral edits;
- discarding conflict;
- lowering identity standards.

---

## 16. Catalog Growth and Global Product Concept Stability

### 16.1 Official growth workflow

```text
Community report
  -> report receipt
  -> target/locale/market normalization
  -> duplicate and existing-candidate search
  -> evidence cluster
  -> moderator identity classification
  -> Catalog/Search/Taxonomy proposal
  -> current catalog authoring checks
  -> full validator + shared/native regression fixtures
  -> reviewed versioned release
  -> publication link and reporter status
```

This extends the current workflow at the intake and evidence boundaries. It does
not weaken the current publication gate.

### 16.2 How new Products enter

A new Global Product Concept enters only when:

- no existing concept or valid alias represents the same shopping intent;
- the candidate is a concept rather than merely a brand, SKU, package, or Store
  assortment;
- canonical naming is approved;
- category/subcategory and semantic icon are reviewed;
- stable ID is allocated under the catalog contract;
- collision and replacement validation passes;
- shared/native search fixtures are added;
- the versioned release is published.

Community submission count is not an allocation rule.

### 16.3 How aliases enter

An alias enters only when:

- it denotes the same concept;
- locale/market meaning is known;
- it does not collide with another canonical name or owned alias;
- it is not merely a use phrase, speculative typo, brand, variant, or package;
- search behavior is verified with positive and negative fixtures;
- the catalog revision is published.

Keywords and brand terms remain weaker discoverability signals.

### 16.4 Duplicate prevention

Duplicate prevention combines:

- exact stable-ID checks;
- normalized canonical and alias collision checks;
- existing candidate/cluster lookup;
- semantic identity review;
- concept-versus-SKU classification;
- catalog history and redirect review;
- regression search against neighboring concepts.

Automatic normalization catches structural collisions. Human review decides
semantic equivalence.

### 16.5 Merge, split, and deactivation

- IDs are never reused.
- A merge preserves an inactive/redirect history.
- A deactivated concept remains resolvable for saved user snapshots.
- A split creates new concepts but does not guess which new concept owns an
  existing user reference.
- Product Truth and history retain the user Product UUID.
- Catalog changes affect discovery/current metadata, not user library membership
  or Shopping outcomes.

### 16.6 Catalog quality feedback loop

Quality improves through:

- evidence clusters rather than isolated anecdotes;
- exact reproduction of queries and revisions;
- domain classification;
- approved minimal changes;
- regression fixtures;
- release versioning;
- post-release verification;
- reversal/supersession tracking;
- monitoring of reopened/conflicting issues without collecting raw queries by
  default as analytics.

### 16.7 Existing catalog toolchain decision

**Retain without architectural replacement:**

- platform-neutral catalog artifact;
- stable IDs;
- dry-run authoring;
- atomic validation;
- authoring audit;
- release-level versioning;
- human near-duplicate review;
- regression fixtures;
- explicit deactivation and replacement.

Future Community Feedback may create reviewed work for this toolchain. It may not
write the catalog artifact directly.

---

## 17. Privacy and Data Protection

### 17.1 Privacy decision

WayTask should support **account-free pseudonymous reporting**, with optional
future account linkage for cross-device status, appeal, and bounded reputation.

It must not promise anonymous reporting unless WayTask has actually removed the
ability to identify or link the reporter by means reasonably likely to be used.
The European Data Protection Board states that pseudonymised data that can be
linked back to an individual remains personal data
([EDPB pseudonymisation guidance](https://www.edpb.europa.eu/news/edpb-adopts-pseudonymisation-guidelines-and-paves-the-way-to-improve-cooperation-with_en)).

Account-free reports:

- reduce friction;
- preserve core access for users without Cloud accounts;
- can use lower submission limits and lower historical weight;
- may still need a pseudonymous receipt for status, retry, and abuse prevention;
- are not automatically anonymous.

An optional account:

- may link report receipts with explicit notice;
- enables cross-device status and appeal;
- may support bounded historical accuracy;
- does not grant more truth authority;
- must not become mandatory merely to report a catalog defect unless abuse or
  legal policy proves it necessary.

### 17.2 Data-minimization principles

The GDPR requires personal data to be adequate, relevant, and limited to what is
necessary, and retained in identifiable form no longer than necessary
([GDPR Article 5](https://eur-lex.europa.eu/eli/reg/2016/679/oj/eng)).
Article 25 requires data protection by design/default and limits the amount,
extent, storage period, and accessibility of personal data by default
([GDPR Article 25](https://eur-lex.europa.eu/eli/reg/2016/679/oj/eng)).

The Community Feedback default therefore is:

- structured claim before free text;
- stable domain target before current location;
- selected Store identity before device coordinates;
- locale/market before precise location;
- optional evidence before mandatory media;
- pseudonymous receipt before real name/email;
- shortest justified retention by data class;
- least-privilege moderator access;
- no public reporter profile.

The EDPB's data-protection-by-design guidance calls for privacy safeguards from
system design onward
([EDPB Guidelines 4/2019](https://www.edpb.europa.eu/documents/guideline/guidelines-42019-on-article-25-data-protection-by-design-and-by-default_en)).

### 17.3 Required and optional information

#### Required by report purpose

- report type;
- resolvable Product/Search/Store target or explicit missing target;
- structured claim;
- relevant observation time;
- locale/market when necessary;
- catalog/search/app revision needed for reproduction;
- idempotent receipt;
- minimal pseudonymous/abuse-control context where approved.

#### Optional

- free text;
- photo;
- barcode image/value when not already the target;
- coarse location/market confirmation;
- follow-up contact through account linkage;
- diagnostic attachment.

#### Not required by default

- real name;
- email;
- address;
- contacts;
- exact current GPS;
- route or Shopping-trip history;
- entire Shopping List;
- Product Library;
- purchase history;
- advertising identifier;
- unrelated device diagnostics;
- account creation.

### 17.4 Location policy

- A selected Store's public location is Store context, not proof of the
  reporter's location.
- Current device location is not required to report that Store.
- Exact reporter location and route history must not be uploaded by default.
- If presence evidence is later proposed, it requires separate necessity,
  proportionality, permission, spoofing, retention, and legal review.
- Location permission denial must not block a manually selected Store report.
- Location-derived market should be coarse where sufficient.

### 17.5 Search-query and free-text policy

Queries and free text may contain names, addresses, health implications,
religious/cultural preferences, or other personal data.

Rules:

- show the exact text that will be submitted;
- allow editing before upload;
- collect only the query needed to reproduce the selected report;
- do not convert all no-result searches into hidden telemetry;
- do not use raw report text for unrelated personalization, advertising, or AI
  training;
- redact or restrict accidental personal information where possible;
- define a separate retention period from the published catalog change.

### 17.6 Media policy

- Attachments are optional.
- The user reviews what will be uploaded.
- Strip unnecessary metadata, including EXIF location.
- Warn against faces, receipts with payment details, prescriptions, and private
  documents.
- Limit moderator access.
- Delete or de-identify media as soon as its purpose ends under the approved
  schedule.
- Derived catalog facts retain provenance without retaining unnecessary raw media
  indefinitely.

### 17.7 Transparency and user rights

The GDPR requires privacy information to be concise, transparent, intelligible,
accessible, and in clear language, and requires disclosure of purpose, legal
basis, recipients, retention criteria, rights, and relevant automated
decision-making
([GDPR Articles 12-13](https://eur-lex.europa.eu/eli/reg/2016/679/oj/eng)).

Before Community Feedback launches, WayTask must provide:

- just-in-time report privacy notice;
- controller and contact information;
- purpose and lawful basis by processing activity;
- required versus optional data;
- retention period or criteria;
- processor/recipient and transfer information;
- access, correction, deletion, restriction, portability, and objection paths as
  applicable;
- explanation of trust/anti-abuse automation and human review;
- explanation that published domain facts may remain after personal data is
  removed when lawfully justified and de-linked.

The GDPR recognizes access, rectification, erasure, restriction, portability, and
objection rights subject to their legal conditions
([GDPR Articles 15-21](https://eur-lex.europa.eu/eli/reg/2016/679/oj/eng)).

### 17.8 Retention classes

Exact durations are unresolved and must not be invented. The official policy must
separately justify:

| Data class | Retention principle |
|---|---|
| Local unsent draft/outbox | Until sent, cancelled, or locally expired |
| Raw report text | Shortest period needed for review/appeal |
| Optional media | Shorter than report history where possible |
| Pseudonymous reporter link | Only while needed for status, appeal, trust, or abuse policy |
| Volatile Store evidence | Expires according to claim volatility |
| Moderation decision | Retained for accountability under approved schedule |
| Published catalog/search/Store revision | Versioned domain history; de-link unnecessary personal data |
| Security/abuse logs | Separate purpose, access, and schedule |
| Aggregated quality metrics | Anonymise where feasible and validate that re-identification is not reasonably likely |

### 17.9 Cloud and account synchronization

- Report receipts/status may sync to an account only after explicit linkage.
- Account linking must not merge reporters silently in a way that exposes prior
  account-free activity.
- Raw Shopping lists, Product Libraries, location history, and sessions are not
  required for Community Feedback sync.
- A report can be deleted/de-linked without deleting a published catalog concept
  that was independently validated.
- Multi-device retry must preserve idempotency and avoid double corroboration.
- Cloud outage must not block local Product, Search, Shopping, or Session use.

### 17.10 Legal decisions still required

This audit is not legal advice. Before launch, qualified review must decide:

- controller/joint-controller roles;
- processor contracts;
- lawful basis for intake, status, reputation, anti-abuse, and moderation;
- consent needs for optional media or future AI reuse;
- international transfers and data residency;
- children's access/age policy;
- retention durations;
- data subject request identity verification;
- whether a Data Protection Impact Assessment is required;
- merchant/business rights and local defamation/content law;
- launch-country requirements beyond GDPR.

---

## 18. Anti-Abuse Architecture

### 18.1 Threats

The system must address:

- accidental duplicate submissions;
- spam;
- automated bots;
- fabricated Product or Store reports;
- mass reporting;
- targeted Store/brand harm;
- coordinated manipulation;
- reputation farming;
- account/device cycling;
- malicious links and attachments;
- moderator compromise or inconsistency;
- AI-generated plausible but false evidence.

### 18.2 Controls

#### Intake controls

- bounded structured inputs;
- payload size/type limits;
- idempotency;
- schema/version validation at the boundary;
- safe URL/media handling;
- progressive rate limits;
- account-free and account-specific quotas;
- accessible human verification only when risk justifies it.

#### Correlation controls

- detect repeated target/type/time patterns;
- discount correlated accounts/devices/networks/content;
- recognize copied campaigns;
- apply diminishing returns to confirmations;
- do not reveal exact detection thresholds.

#### Reputation controls

- cap influence;
- require cross-time accuracy;
- separate claim domains;
- correct reputation after appeals/reversals;
- never grant publication power;
- prevent self-confirmation through linked identities.

#### Moderation controls

- prioritized abuse queue;
- dual review for high-impact decisions where policy requires;
- conflict-of-interest rules;
- moderator action audit;
- reversible publication;
- Store/merchant appeal route;
- periodic consistency review.

#### Privacy controls

- abuse prevention must still satisfy purpose limitation and minimization;
- security identifiers remain restricted and separate from content review where
  practicable;
- do not expose device/network fingerprints to moderators without need;
- do not retain anti-abuse data indefinitely;
- rejected honest mistakes are not treated as abuse by default.

### 18.3 Rate-limit principles

Exact limits are operational open questions. The policy must:

- limit bursts and sustained volume;
- use stricter limits for high-impact Store closure/identity claims;
- avoid blocking a user who retries after uncertain connectivity;
- return clear recoverable status;
- provide an accessible alternative to visual CAPTCHA;
- avoid public disclosure of thresholds that makes evasion trivial;
- allow moderators to investigate coordinated campaigns without accepting them as
  independent evidence.

### 18.4 Coordinated manipulation

Large volume from apparently independent users can still be one campaign.

Required response:

- preserve reports;
- group correlated evidence;
- freeze automatic recommendation influence;
- escalate human review;
- seek separate provider/merchant/field verification;
- avoid retaliatory public disclosure;
- reverse any affected projection through an audited revision.

### 18.5 Emergency claims

Community Feedback is not an emergency service. Reports alleging immediate danger,
illegal activity, or personal safety issues require a separate product/legal
policy. The default Community Feedback workflow must not imply emergency response.

---

## 19. Community Influence Policy

### 19.1 Influence levels

| Level | Meaning | Examples |
|---|---|---|
| Observe | Retain as User Opinion | One missing-Product or Store report |
| Prioritize | Adjust review queue | Corroborated/recent/high-impact cluster |
| Verify | Human accepts evidence | Reproduced search issue |
| Propose | Create domain-governed candidate | Alias, concept, Store profile correction |
| Publish | Validated revision becomes runtime input | Catalog release or expiring Store-evidence projection |
| Supersede | Later reviewed revision replaces earlier projection | Store reopens, alias corrected |

Reports never jump directly from Observe to Publish.

### 19.2 Catalog influence

Community Evidence may:

- propose a concept, alias, keyword, brand term, category review, SKU, or barcode;
- reveal duplicate concepts;
- prioritize catalog coverage work;
- supply reviewed query regressions.

It may never automatically:

- allocate or merge stable Product IDs;
- convert a brand/package into a concept;
- assign a barcode;
- create a category;
- deactivate a concept;
- rewrite a user's Product snapshot.

### 19.3 Search influence

Community Evidence may:

- identify wrong or weak matches;
- propose locale-specific synonyms;
- identify missing language/spelling support;
- produce reviewed evaluation fixtures;
- inform bounded ranking research.

It may never automatically:

- add or delete aliases;
- down-rank a Product from raw complaint count;
- collect every query as hidden analytics;
- let personalization override stronger textual relevance;
- publish AI-generated synonym lists without review.

### 19.4 Store recommendation influence

Reviewed, fresh Community Evidence may:

- explain lower or higher confidence;
- inform future Store/Product likelihood;
- surface "recent reports are mixed" honestly;
- trigger a future plan refresh when the user requests/accepts it;
- expire when stale.

It may never:

- claim verified stock without a competent source;
- mark a Store permanently unsuitable from one report;
- remove a Store automatically because of report volume;
- overwrite provider profile data without reviewed routing;
- mutate the active session snapshot;
- hide alternative Stores solely because evidence is old.

### 19.5 Shopping Plan influence

Under WT-030A and WT-030B:

- a plan is a projection for a named list revision;
- an active session owns a frozen execution snapshot;
- community data can improve future plan inputs;
- a changed community projection can make a cached plan eligible for explicit
  refresh under future revision rules;
- it does not silently rewrite an active plan/session;
- offline execution does not depend on current community connectivity.

### 19.6 Notification influence

Community Evidence may eventually:

- contribute to an approved, fresh Store-confidence projection used before a
  reminder is generated;
- explain why a reminder is estimated;
- suppress an opportunity only under an approved current projection.

It may never:

- schedule a notification directly from a raw report;
- notify "in stock" based on community count;
- deliver a deferred temporary-availability message after the evidence expires;
- include another reporter's identity or location;
- use a report as proof the current user is near a Store.

### 19.7 AI influence

AI may:

- classify report type;
- extract structured candidates for user/moderator review;
- suggest duplicate clusters;
- summarize corroborating and conflicting evidence;
- flag unsafe or abusive content;
- propose catalog/search/store changes;
- generate evaluation candidates from approved, de-identified aggregates.

AI may not:

- mark a report Verified or Implemented under the default policy;
- allocate/merge Product IDs;
- publish aliases, barcodes, taxonomy, or Store closure;
- turn a confidence score into inventory truth;
- train on raw queries, free text, photos, or location under the submission
  purpose without separate approval;
- change Product, Shopping, or Session state without the user-authorized command
  policy defined by the relevant domain.
  
### 19.8 Community Transparency

Whenever Community Evidence contributes to a user-visible decision,
WayTask should be capable of explaining the primary source of that decision.

Community-influenced experiences should clearly distinguish whether the information is based on:

- Official Catalog Truth
- Official Store or Provider data
- Reviewed Community Evidence
- A combination of approved sources

The explanation should use simple, user-friendly language rather than internal architectural terminology.

Transparency improves user trust, helps users understand recommendation quality,
and prevents Community Evidence from being perceived as undisclosed or authoritative truth.

This section defines an architectural capability only.
It does not require a specific UI implementation in this release.

### 19.9 Areas that may never change automatically under this standard

- Product Truth;
- library membership;
- Shopping-list membership/resolution;
- session-line outcomes;
- purchase history;
- Global Product Concept merge/split/ID;
- barcode identity;
- taxonomy identity;
- Store permanent closure/relocation;
- raw provider metadata;
- public reporter identity;
- AI training consent.

Any future exception requires a new documented approval policy and audit. It is
not implied by this architecture.

---

## 20. Offline, Recovery, and Synchronization

### 20.1 Offline core behavior

Community availability is optional enhancement data.

Without internet:

- bundled/cached catalog search remains usable;
- custom Product creation remains usable;
- Product Library and Shopping remain usable;
- active Shopping Session remains usable;
- cached Store recommendations retain their existing honest limitations;
- failure to submit feedback does not change Product or Shopping state.

### 20.2 Offline report behavior

The official UX contract for future intake is:

```text
Draft -> Pending Upload -> Sent
                    \-> Failed / Retry
Draft or Pending Upload -> Cancelled locally
```

These are local delivery states, not moderation states.

Requirements:

- the user can review a queued report;
- retry is idempotent;
- process death/relaunch does not duplicate a successfully acknowledged report;
- failed upload shows recoverable status;
- queued time-sensitive Store evidence visibly ages and may expire before upload;
- stale evidence is not silently submitted as current;
- attachments are not retained indefinitely because connectivity is absent;
- cancellation before upload removes the queued submission under local retention
  policy.

### 20.3 Recovered connectivity

On connectivity recovery:

- retry only pending user-authorized reports;
- preserve the original observation time;
- do not rewrite the time as upload time;
- revalidate target/revision compatibility;
- warn or expire claims that are no longer useful;
- return the canonical receipt if the service already accepted the report;
- do not regenerate a report from current app state.

### 20.4 Cached community projections

Published community-derived projections must include enough revision and freshness
context to:

- load offline;
- identify stale/expired data;
- avoid treating old availability evidence as current;
- roll back or supersede safely;
- produce the same platform-neutral interpretation on iOS and Android.

The cache is a projection, not evidence authority.

### 20.5 Cloud Sync

Future Cloud Sync must distinguish:

- personal report receipt/status;
- report content/evidence;
- community aggregate/projection;
- Product Catalog release;
- Store profile release;
- active Shopping Session state.

They have different owners, retention, and conflict rules.

Cloud Sync:

- must not duplicate one report across devices;
- must not count the same linked user/device confirmation twice;
- must not make a report dependent on syncing the Product Library;
- must not merge community evidence with user Product state;
- must preserve tombstones/supersession;
- must choose one notification authority separately under WT-030B.

### 20.6 Failure and recovery

| Failure | Required behavior |
|---|---|
| Catalog unavailable | Allow local custom Product; feedback draft may retain unresolved target |
| Store target disappears from MapKit | Preserve source snapshot for review; do not invent a stable identity |
| Upload timeout | Keep Pending/Failed; safe idempotent retry |
| Duplicate acknowledgement lost | Retry returns original receipt |
| Attachment upload fails | Do not submit misleading partial proof without user-visible state |
| Evidence service unavailable | Core app continues; report remains queued or fails clearly |
| Moderator service unavailable | Received status persists; no truth mutation |
| Publication validation fails | Report remains Verified/under domain review; never mark Implemented |
| Catalog release rollback | Publication link shows superseded/rolled back domain revision |
| Account linked later | Merge receipts only under explicit policy; never inflate independence |
| Local persistent-store recovery | Community outbox recovery must not reconstruct claims from Product/Shopping data |

---

## 21. Cross-Surface UX Contract

### 21.1 Current consistency

Products, Shopping, Map, and notifications are currently consistent in one narrow
respect: none presents a Community Feedback action and none writes community
state.

They are inconsistent in the context they could supply:

- Products/Search knows the query and catalog result identity.
- Scanner knows barcode/provider/AI candidate context.
- Shopping knows the named list, plan, selected Store, Product, and active session.
- Map knows the runtime Store/source and estimated Product set.
- Notification knows a serialized Store/list/Product snapshot and can become
  stale.

A generic global report form would lose those distinctions.

### 21.2 Official entry-point responsibilities

This section defines the complete UX responsibility, not a partial implementation
sequence.

#### Products and Add Product

May originate:

- Product not found;
- brand/variant/package/category/barcode missing;
- wrong search result;
- missing/wrong synonym;
- wrong language/misspelling;
- duplicate/irrelevant result.

Must:

- preserve the reviewed query/result context;
- keep custom Product creation independent;
- explain that reporting does not add the Product immediately to the catalog;
- never submit every no-result query automatically.

#### Scanner

May originate:

- barcode missing;
- barcode mapped to the wrong item;
- brand/variant/package mismatch.

Must:

- let the user correct their local Product immediately;
- distinguish local correction from community submission;
- not upload a photo/barcode observation without user review.

#### Shopping

May originate:

- recommended Store did not appear to sell Product;
- temporary unavailability;
- longer-lived assortment claim;
- Store information problem.

Must:

- keep "Mark unavailable/skip/collect" as a session command, not a report;
- let the user finish Shopping without submitting;
- preserve Product/Store/observation-time context;
- avoid changing the active session when the report is sent.

#### Map

May originate:

- closed/relocated/duplicate Store;
- wrong category/hours/website;
- Product found/not found at Store.

Must:

- show the Store source;
- use the selected Store rather than current GPS as context;
- distinguish saved private locations from global Store targets;
- not imply that a transient MapKit result is a permanent WayTask Store ID.

#### Notifications

A notification must not directly submit or pre-confirm evidence.

It may:

- deep-link to the exact Map/Shopping context;
- allow the user to choose a report action after reviewing current context.

It must:

- show when context is stale;
- never treat notification delivery/tap as Store presence or Product
  confirmation;
- never submit another user's community content.

#### Future AI workflow

AI may offer:

- "It sounds like this was temporarily unavailable. Review a report?"
- structured prefill based on the user's explicit statement.

It must:

- show the proposed claim and target before submission;
- avoid inventing evidence;
- keep report submission separate from Shopping/session commands;
- disclose that AI prepared the draft;
- require the user's affirmative action.

### 21.3 UX terminology

Use:

- Report an issue;
- Product not in catalog;
- Search result issue;
- Store information issue;
- Found here / Not found today;
- Report received;
- Under review;
- Applied in catalog version/revision, where understandable;
- Availability is estimated.

Avoid:

- Vote to remove;
- Community verified, unless the exact moderation state is explained;
- Guaranteed unavailable;
- Trusted user says;
- Report accepted, when only received;
- Fixed, when no published revision exists;
- Anonymous, when only pseudonymous/account-free.

### 21.4 Submission confirmation

Before upload, the user must be able to verify:

- what they are reporting;
- which Product/Search result/Store is targeted;
- when and where the observation applies;
- what optional text/media will be sent;
- whether the report is pending offline;
- that it will not immediately change the catalog or current Shopping state;
- how to see/cancel status where available.

---

## 22. Design Alternatives

### 22.1 Alternative A - Local Corrections Only

**Description**

Users can create/customize Products and correct local recognition, but WayTask
collects no community reports.

**Advantages**

- strongest default privacy;
- no moderation or abuse service;
- fully offline;
- lowest operational and legal complexity;
- current architecture already supports much of this behavior.

**Disadvantages**

- shared catalog and Store quality do not benefit from users;
- repeated defects are rediscovered independently;
- no Store reality learning;
- roadmap Community Intelligence goals are not met;
- users receive no resolution/status.

**Moderation complexity:** None.  
**Scalability:** Runtime scales, but knowledge growth remains maintainer-limited.  
**Privacy:** Best of the alternatives.  
**Trustworthiness:** High for private user state; no shared evidence.  
**Maintenance cost:** Low product cost; continuing manual catalog research cost.  
**Future compatibility:** Offline and Android compatible, but weak for Cloud,
Community, and AI knowledge.

**Decision:** Rejected as the official Community architecture because it does not
solve the documented catalog, search, or Store-quality problems. Retain its
local-first fallback behavior inside the recommended architecture.

### 22.2 Alternative B - Open Community Wiki / Direct Edits

**Description**

Users directly add or edit catalog and Store records; changes become live
immediately or with minimal rollback.

**Advantages**

- fast visible contribution;
- low central review latency;
- high participation and apparent catalog-growth speed;
- transparent edit history can support community collaboration.

**Disadvantages**

- stable Product and Store identity are easy to corrupt;
- variants, brands, aliases, inventory, and concepts will be conflated;
- malicious or coordinated edits can affect recommendations immediately;
- legal and business disputes become public edit wars;
- user Product/snapshot migration risk increases;
- Store claims become categorical without evidence review.

**Moderation complexity:** Reactive and very high at scale.  
**Scalability:** High write volume, poor quality scalability.  
**Privacy:** Public contribution history increases linkage and exposure risk.  
**Trustworthiness:** Low without mature governance; volatile.  
**Maintenance cost:** High rollback, dispute, identity repair, and abuse cost.  
**Future compatibility:** Cross-platform technically possible but unsafe for
Global Product Concepts, Store recommendations, and AI.

**Decision:** Rejected. Direct edits violate the evidence/truth boundary and the
stable-ID catalog contract.

### 22.3 Alternative C - Reputation or Majority Auto-Publish

**Description**

Reports accumulate votes/confirmations. A threshold or high-reputation reporter
automatically changes catalog/search/Store data.

**Advantages**

- lower human review volume;
- quick response to popular issues;
- community reputation can reward accurate contributors;
- seemingly measurable decision rules.

**Disadvantages**

- correlated accounts are mistaken for independence;
- majority count cannot resolve concept/SKU, locale, Store branch, or time scope;
- reputation farming creates concentrated authority;
- temporary availability can permanently bias recommendations;
- rare/localized Products are disadvantaged;
- coordinated attacks can close Stores or remove terms;
- numeric thresholds create false certainty.

**Moderation complexity:** Medium before incidents; very high during reversals and
appeals.  
**Scalability:** High throughput but unsafe truth scalability.  
**Privacy:** Requires durable behavioral profiles and correlation signals.  
**Trustworthiness:** Superficially quantified, structurally vulnerable.  
**Maintenance cost:** High anti-abuse, tuning, dispute, and rollback cost.  
**Future compatibility:** Easy to share across platforms, but contaminates Cloud
and AI with unreviewed truth.

**Decision:** Rejected. Trust is prioritization, not publication authority.

### 22.4 Alternative D - Central Manual Review of Every Report

**Description**

Every report is reviewed individually by a human before any further processing.
Little or no automated validation, clustering, prioritization, or expiry occurs.

**Advantages**

- strong human control;
- simple authority explanation;
- careful treatment of edge cases;
- no automatic truth changes.

**Disadvantages**

- exact retries and duplicates waste reviewer time;
- queues grow linearly with report volume;
- time-sensitive Store evidence expires before review;
- inconsistent routing across Product/Search/Store domains;
- poor reporter response time;
- high operational cost.

**Moderation complexity:** Simple conceptually, operationally high.  
**Scalability:** Low.  
**Privacy:** Moderate; reviewers see more raw data than necessary.  
**Trustworthiness:** Potentially high, limited by fatigue and inconsistency.  
**Maintenance cost:** High recurring staffing cost.  
**Future compatibility:** Correct authority model but inadequate for Community,
Cloud, Android scale, or AI-assisted triage.

**Decision:** Rejected as the complete architecture. Human approval remains, while
safe administrative automation is adopted.

### 22.5 Alternative E - Provider/Merchant-Only Corrections

**Description**

WayTask accepts catalog or Store changes only from selected providers, retailers,
or verified merchants.

**Advantages**

- stronger provenance for provider-owned metadata;
- lower public spam volume;
- merchant hours/website/inventory can be operationally current;
- simpler contributor support.

**Disadvantages**

- providers can be stale, incomplete, biased, or unavailable by market;
- merchants define their assortment/SKUs, not WayTask Global Product Concepts;
- no route for ordinary users to report observed defects;
- vendor lock-in and licensing constraints;
- smaller/local Stores and Products remain underrepresented;
- provider conflicts still require governance.

**Moderation complexity:** Lower intake volume, high source-contract and conflict
complexity.  
**Scalability:** Depends on coverage and integrations.  
**Privacy:** Lower community-personal-data collection.  
**Trustworthiness:** Strong within provider scope, not universal.  
**Maintenance cost:** High integration, licensing, and reconciliation cost.  
**Future compatibility:** Useful as one evidence source, insufficient as the
Community architecture.

**Decision:** Rejected as the sole architecture. Provider/merchant claims remain
distinct sources inside the recommended model.

### 22.6 Alternative F - Moderated Evidence-to-Truth Pipeline

**Description**

Account-free or account-linked reports become provenance-preserving Community
Evidence. Safe automation handles idempotency, validation, candidate clustering,
priority, and expiry. Humans verify substantive claims and approve domain
proposals. Existing domain validators and versioned publication remain the truth
gate.

**Advantages**

- explicit separation of opinion, evidence, moderation, and truth;
- no single-report authority;
- scalable duplicate and queue handling;
- stable catalog and Store identity protection;
- supports volatile availability without claiming inventory;
- preserves privacy-minimized account-free access;
- integrates provider, merchant, user, and AI assistance without conflating
  authority;
- compatible with existing catalog governance;
- explainable reporter status and rollback.

**Disadvantages**

- requires moderation operations and policy ownership;
- stable Store identity remains a prerequisite;
- trust/freshness policies need real operational calibration;
- privacy, retention, and abuse systems add complexity;
- publication latency is slower than direct edits;
- Store availability remains probabilistic.

**Moderation complexity:** Medium to high, but bounded by automation and domain
queues.  
**Scalability:** High if clustering, expiry, and prioritization are effective.  
**Privacy:** Good when minimization and pseudonymity rules are enforced; not
zero-data.  
**Trustworthiness:** Highest balanced option because authority remains reviewed
and versioned.  
**Maintenance cost:** Moderate/high ongoing, justified by product-quality and
trust goals.  
**Future compatibility:** Strong for Global Product Concepts, Offline Shopping,
Cloud, Android, providers, and AI.

**Decision:** Approved.

### 22.7 Comparative decision matrix

| Alternative | Quality | Scale | Privacy | Abuse resistance | Truth integrity | Roadmap fit |
|---|---:|---:|---:|---:|---:|---:|
| A Local only | Medium local / Low shared | Medium | High | High | High local | Low |
| B Open direct edits | Low/volatile | High volume | Low | Low | Low | Medium |
| C Reputation auto-publish | Medium/volatile | High | Low-Medium | Low-Medium | Low | Medium |
| D Manual every report | High at low volume | Low | Medium | Medium-High | High | Medium |
| E Provider only | Medium by coverage | Medium | High | High | Medium-High by scope | Medium |
| F Moderated pipeline | High | High | Medium-High | High | High | High |

---

## 23. Recommended Official Architecture

### 23.1 Decision

Adopt the **Moderated Evidence-to-Truth Pipeline** as the official WayTask
Community Feedback architecture.

### 23.2 Logical architecture

```text
Contextual report entry
  -> user-reviewed structured claim
  -> local delivery/outbox state
  -> idempotent intake receipt
  -> target resolution and safety validation
  -> evidence record with provenance
  -> duplicate/conflict cluster
  -> contextual trust and freshness evaluation
  -> domain moderation queue
  -> Verified / Rejected / Duplicate / Expired
  -> approved domain proposal
  -> catalog/search/store validation
  -> versioned publication
  -> runtime projection with provenance/freshness
  -> reporter-visible outcome
```

This is a logical capability model. It does not select database technology,
backend vendor, API shape, or deployment topology.

### 23.3 Sources are peers, not interchangeable authorities

The evidence boundary can receive:

- account-free user observation;
- account-linked user observation;
- moderator reproduction;
- merchant confirmation;
- catalog curator input;
- provider metadata;
- barcode/identifier provider observation;
- AI classification/inference.

Each retains source type, scope, time, and confidence. None is converted into a
generic "community says" value that loses provenance.

### 23.4 Domain projections

#### Catalog projection

- versioned Global Product Concepts;
- stable IDs and redirects;
- approved names/aliases/keywords/brand terms;
- controlled taxonomy;
- future reviewed SKU/barcode relationships.

#### Search projection

- rebuildable index and ranking/localization revision;
- approved catalog data;
- bounded local personalization;
- no raw report text.

#### Store profile projection

- durable Store identity;
- source-attributed reviewed name/location/category/hours/website/status;
- provider/merchant/community provenance;
- revision/supersession.

#### Store/Product evidence projection

- scoped Product concept or SKU;
- scoped Store/market;
- evidence direction;
- confidence band;
- observed/freshness/expiry context;
- no categorical inventory guarantee.

Exact persisted representations are deferred.

### 23.5 Why this becomes the product standard

It directly solves documented problems:

- missing catalog/search reporting;
- Store closure and availability reporting;
- no current moderation/trust path;
- unstable and volatile Store evidence;
- privacy risk from queries/location/media;
- scaling beyond a Markdown maintainer log;
- safe future influence on recommendations and AI.

It preserves what already works:

- local Product fallback;
- current stable catalog contract;
- current validator and release discipline;
- user Product snapshots;
- offline Shopping;
- honest Store-estimate language;
- WT-030A state ownership;
- WT-030B session snapshot and notification authority.

### 23.6 Why alternatives were rejected

- Local-only corrections cannot create community value.
- Direct edits sacrifice identity and trust.
- reputation/majority publication confuses count with independence and truth.
- pure manual review cannot scale safely.
- provider-only input lacks coverage and cannot represent user observations.

The recommended model uses the useful part of each alternative without adopting
its failure mode:

- local-first fallback from Alternative A;
- visible contribution history without direct writes from B;
- reputation for prioritization only from C;
- human truth approval from D;
- scoped provider authority from E.

### 23.7 Implementation boundary

This audit authorizes no code, schema, backend, tooling, entitlement, analytics,
or app behavior change.

Implementation must not begin as a standalone "Report" button with nowhere
authoritative to send the claim. A later approved implementation specification
must cover intake, delivery, receipt, lifecycle, moderation, privacy, abuse,
publication, rollback, and cross-domain authority as one coherent capability.

---

## 24. Future Compatibility

### 24.1 WT-030A Product State

The architecture preserves the Orthogonal Product Lifecycle:

- community reports are not Product state;
- a catalog candidate does not add a Product to a user's Library;
- catalog publication does not resolve a Shopping-list entry;
- found/not-found evidence does not collect a session line;
- catalog inactive/replacement does not delete Product Truth;
- saved user Product snapshots remain stable.

### 24.2 WT-030B Shopping Session

The architecture preserves the Session-Scoped Persistent Hybrid:

- active session lines and Store snapshots are process-independent truth;
- community evidence can improve future planning confidence;
- it cannot mutate an active snapshot;
- offline session execution does not require community connectivity;
- notification authority remains session/revision scoped;
- found/not-found reporting remains separate from collect/skip/unavailable
  session commands.

### 24.3 Global Product Concepts

- stable opaque IDs remain cross-platform;
- concepts stay distinct from brands, variants, packages, barcodes, user Products,
  and Store inventory;
- accepted community catalog entries follow the same ID/release contract;
- merges use redirects and splits avoid guessing;
- locale-specific discoverability does not redefine identity.

### 24.4 Offline Shopping

- community services are never on the critical path for Product save, search,
  list execution, or session finish;
- last approved catalog/projection can be cached;
- stale Store evidence is labeled/expired;
- queued reports are optional and cancellable.

### 24.5 Multi-device and Cloud Sync

- idempotent receipts prevent duplicate reports;
- reporter linkage remains separate from Product/Shopping sync;
- independent-confirmation logic understands linked devices/accounts;
- report status can sync without syncing raw Product/Shopping/location data;
- published projections use revision/supersession rather than last-write-wins.

### 24.6 Android

iOS and Android share:

- report-type identifiers;
- target identity semantics;
- moderation states and allowed transitions;
- trust and independence rules;
- expiry semantics;
- Catalog/Search/Store publication contracts;
- privacy terminology;
- shared acceptance fixtures.

Native UI, persistence, background transfer, and accessibility APIs may differ.
Android must not copy an iOS runtime UUID as a global Store identity or interpret
local iOS Product state as community truth.

### 24.7 AI

Future AI can use the same provenanced observation boundary, explain confidence,
and propose reviewed work. It cannot become a hidden writer. Published curated
projections are safer AI context than raw community content, but AI use, model
training, retention, and consent remain separately governed.

---

## 25. Impact Analysis

### 25.1 UX

Positive impact:

- users can distinguish local recovery from shared improvement;
- reports begin from relevant Product/Search/Store context;
- status explains that receipt, verification, and publication differ;
- found/not-found reports become precise and time-scoped;
- reporter effort is reduced through structured choices;
- honest Store uncertainty remains visible.

Costs and risks:

- additional actions can clutter high-frequency Product and Shopping surfaces;
- terminology such as concept, variant, and temporary availability must be
  translated into plain language;
- long moderation latency can feel unresponsive;
- evidence requests can burden users;
- status must not promise a fix.

Product requirement:

- reporting is optional and never blocks the primary Shopping task.

### 25.2 Catalog

Positive impact:

- broader evidence for missing concepts and discoverability;
- duplicate candidates detected before publication;
- accepted contributions enter the existing validated release path;
- version/reporter outcome becomes traceable.

Costs and risks:

- identity-review workload grows;
- community pressure can favor popular Products over important minority/local
  Products;
- concept/SKU mistakes can pollute stable IDs;
- bundled-only distribution limits update speed.

No change recommended:

- retain stable IDs, human semantic review, validator, versioning, redirects,
  audit, and regression fixtures.

### 25.3 Search

Positive impact:

- exact wrong-result and synonym evidence;
- locale-specific quality improvements;
- repeatable regression cases;
- better distinction between alias, keyword, brand term, typo, and UI copy.

Costs and risks:

- raw queries can contain personal data;
- crowd-proposed synonyms can create collisions or cultural bias;
- popularity can pressure ranking away from textual relevance;
- implementation/spec mismatches need their own correction path.

No change recommended:

- retain explicit selection, local search, custom fallback, bounded result list,
  and personalization subordinate to textual relevance.

### 25.4 Shopping

Positive impact:

- Store recommendations can learn from reviewed reality evidence;
- users can report an issue in context;
- temporary and permanent availability are distinguished.

Costs and risks:

- users may confuse "not found today" with the session "unavailable" outcome;
- submission can interrupt in-Store flow;
- Store evidence can become stale before the next plan.

Required boundary:

- session commands complete the user's Shopping task; report submission is
  optional and separate.

### 25.5 Store recommendations

Positive impact:

- confidence can incorporate reviewed, fresh Store/Product evidence;
- closure, relocation, hours, website, and category issues gain a route;
- explanation can reflect mixed or stale evidence honestly.

Costs and risks:

- a durable Store identity is required;
- reports can unfairly harm a Store;
- assortment and inventory volatility make "truth" short-lived;
- provider/community/merchant conflicts require review;
- false precision could undermine existing trustworthy wording.

Required boundary:

- current `StoreRealityFeedback` and zero-weight signal placeholders are not
  sufficient and must not be activated without the full evidence policy.

### 25.6 Notifications

Positive impact:

- future reminders can consume a more realistic approved projection;
- a notification can deep-link to precise report context.

Costs and risks:

- stale evidence can produce incorrect reminders;
- direct notification actions can submit accidentally;
- a notification may imply presence/location;
- community-derived copy can expose another user's claim.

Required boundary:

- notifications consume published scoped projections only and never raw reports.

### 25.7 Architecture

Positive impact:

- one clear path from claim to published truth;
- source provenance survives;
- trust, moderation, and domain validation have distinct owners;
- Product, Store, Search, Shopping, and AI no longer compete for authority;
- safe provider/merchant additions become possible.

Costs and risks:

- more explicit boundaries and lifecycle coordination;
- operational policy becomes part of system correctness;
- Store identity and SKU/identifier gaps must be addressed before those report
  types can publish;
- distributed revisions require robust supersession.

### 25.8 Persistence

Future persistence must support, conceptually:

- local report delivery state and receipt;
- durable provenance and status;
- evidence/duplicate/conflict linkage;
- moderation and publication linkage;
- expiry and deletion/de-linking;
- Cloud conflict/idempotency.

This audit defines no table, field layout, storage engine, or migration.

Risks:

- storing reports inside current user Product rows would conflate authority;
- storing community Store claims against runtime UUIDs would orphan evidence;
- copying report text into catalog artifacts would violate minimization and
  release separation;
- persistent recovery must not infer or recreate reports from Shopping data.

### 25.9 Cloud

Positive impact:

- shared evidence and cross-device status become possible;
- publication can be decoupled from raw user state;
- iOS/Android can consume one domain contract.

Costs and risks:

- availability, security, abuse, residency, backup, deletion, and operator access
  become production obligations;
- multi-device submissions can inflate evidence;
- offline retry requires idempotency;
- eventual consistency cannot become last-write-wins truth.

No backend design is selected by this audit.

### 25.10 Privacy

Positive impact:

- account-free participation;
- no exact GPS requirement;
- raw evidence separated from published facts;
- retention can follow claim volatility and purpose;
- reporter identity remains private.

Costs and risks:

- pseudonymous history, raw queries, attachments, and abuse signals remain
  personal data where linkable;
- Store reports may reveal habits or location indirectly;
- reputation is behavioral profiling;
- moderation staff access increases exposure;
- account linking and AI reuse create purpose-expansion risk.

Launch requires approved privacy/legal decisions in Section 28.

### 25.11 Localization

Requirements:

- report types and reason codes use stable localized identifiers;
- English and Hebrew receive semantic parity;
- no raw enum/value is displayed;
- bidirectional Product/brand/barcode/URL strings render safely;
- locale and market are separate;
- aliases and misspellings are reviewed within language context;
- reporter free text preserves original script and direction;
- status and rejection reasons are grammatically natural, not concatenated.

### 25.12 Accessibility

Requirements:

- every report action has a clear text/VoiceOver label;
- structured choices expose role, value, selection, and error;
- status never relies on color alone;
- attachments have accessible remove/review controls;
- Dynamic Type supports accessibility sizes without hiding submission context;
- Hebrew RTL navigation/order is verified;
- VoiceOver reads target, claim, evidence, privacy notice, and upload state in a
  logical order;
- Switch Control and hardware keyboard focus are deterministic;
- anti-bot controls have nonvisual alternatives;
- moderation and appeal do not exclude users who cannot provide a photo.

### 25.13 Performance

Positive impact:

- structured claims and stable IDs permit efficient clustering;
- published projections keep runtime reads separate from raw evidence;
- expiry bounds volatile data.

Costs and risks:

- media and large report bursts;
- duplicate/independence analysis;
- Store evidence refresh;
- cross-device status;
- moderation queries.

Performance rules:

- no network request for every search keystroke;
- no community lookup may block local catalog suggestions;
- no report upload may block session persistence/finish;
- bounded projections are loaded for the current Product/Store/market context;
- raw reports are not scanned on-device to rank every Store;
- media upload is explicit and recoverable;
- disabled/unavailable Community Feedback has negligible runtime work.

### 25.14 Testing

Testing expands to:

- authority and lifecycle transition fixtures;
- idempotency and duplicate clusters;
- conflicting evidence;
- trust/reputation caps;
- expiry;
- moderator and domain publication separation;
- catalog stable-ID/collision/regression rules;
- Store identity/source changes;
- offline queue and recovered connectivity;
- privacy deletion/de-linking;
- abuse/correlation scenarios;
- accessibility and localization;
- iOS/Android shared fixtures;
- AI proposal-without-authority;
- WT-030A Product-state and WT-030B active-session non-mutation.

### 25.15 Future Android parity

Positive impact:

- platform-neutral semantics prevent divergent truth;
- shared catalog and moderation fixtures;
- consistent user status and report taxonomy.

Risks:

- platform-specific Store provider IDs may differ;
- local account-free receipts need compatible merge rules;
- translation and accessibility must be verified independently;
- background upload policies differ.

### 25.16 Future AI workflows

Positive impact:

- curated evidence produces higher-quality evaluation and explanation;
- provenance supports uncertainty;
- duplicate/conflict clusters give AI structured context;
- accepted catalog/search changes improve recognition.

Risks:

- AI can amplify community bias or abuse;
- summaries can omit conflict;
- inferred reputation can become opaque profiling;
- raw media/text reuse can violate purpose;
- hallucinated candidates can overwhelm moderation.

Required boundary:

- AI remains assistant and proposer, never the default truth approver.

### 25.17 Maintenance and operations

The system creates ongoing responsibilities:

- moderation staffing and training;
- policy versioning;
- queue and appeal ownership;
- abuse response;
- privacy requests and retention jobs;
- provider/merchant coordination;
- catalog and Store release rollback;
- quality and fairness review;
- incident response.

These are product operating costs, not optional backend details. Launch scope must
match actual moderation capacity.

---

## 26. Risks and Mitigations

| Risk | Consequence | Required mitigation |
|---|---|---|
| Generic report taxonomy | Concept/SKU/Search/Store confusion | Structured domain-specific types |
| One report treated as truth | False catalog or Store change | Hard moderation/publication boundary |
| Majority/reputation authority | Brigading and reputation capture | Independence discount, caps, human approval |
| Runtime Store ID used globally | Orphaned/misapplied evidence | Durable Store identity/source contract |
| Variant forced into concept | Global Product Concept corruption | Future SKU/identifier review lane |
| Old availability retained | Bad recommendations | Claim-specific expiry |
| Raw query collection | Privacy and purpose creep | Explicit report-only collection/minimization |
| Exact GPS required | Privacy exclusion | Selected Store/public location, no GPS default |
| Public contributor profiles | Harassment/linkability | Private pseudonymous identity |
| AI auto-moderation | Opaque false truth | AI triage only; human verified/publication gate |
| Direct catalog write | Invalid release/collision | Existing validators and versioned publication |
| Report mutates session | Lost/incorrect Shopping state | WT-030A/B non-mutation invariant |
| Offline retry duplicates | Inflated evidence | Idempotent receipt |
| Conflicts collapsed | False confidence | Preserve contradiction and scope |
| Markdown queue at scale | Review backlog/data leakage | Moderation capability boundary; no raw repo intake |
| Merchant-targeted abuse | Business harm | High-impact review, correlation, appeal, rollback |
| Over-retention | Privacy/legal risk | Data-class schedule and expiry |
| Under-retention | No accountability/appeal | Approved purpose-based decision history |
| Cross-platform divergence | Different truth per device | Shared identifiers, states, fixtures |

---

## 27. Measurable Acceptance Criteria

These criteria define the complete architecture outcome. They do not authorize
implementation.

### 27.1 Authority and truth

- **AC-001:** In automated authority tests, 100% of newly received user reports
  produce zero direct writes to Product, Shopping, Session, Catalog, Search, or
  Store Truth.
- **AC-002:** No report reaches Verified without a recorded human moderation
  decision under the default policy.
- **AC-003:** No report reaches Implemented without a linked, successfully
  published domain revision or approved expiring Store-evidence projection.
- **AC-004:** A moderator's Verified decision alone produces zero runtime
  Catalog/Search/Store change.
- **AC-005:** One report from any reporter/reputation level produces zero automatic
  domain publication.
- **AC-006:** One hundred repeated reports from the same linked actor do not count
  as more than one independent source.
- **AC-007:** Product Truth, list entries, active plan/session snapshots, session
  outcomes, and purchase history are byte-for-byte/semantically unchanged by
  report submission, moderation, and catalog publication fixtures except where a
  separate explicit domain command is invoked.
- **AC-008:** Catalog deactivation/replacement fixtures preserve the user Product
  UUID and display snapshots.

### 27.2 Report taxonomy and context

- **AC-009:** Every accepted report has exactly one documented report type.
- **AC-010:** Product-not-found, brand, variant, package, category, and barcode
  reports remain distinct in round-trip fixtures.
- **AC-011:** Wrong result, missing synonym, wrong synonym, wrong language,
  misspelling, duplicate, and irrelevant result remain distinct.
- **AC-012:** Recommended-Store mismatch, permanent assortment, temporary
  unavailability, wrong category, wrong hours, wrong website, closure, and
  relocation remain distinct.
- **AC-013:** Every search-quality report identifies the relevant query, locale,
  displayed Product ID where present, and catalog/search revision.
- **AC-014:** Every temporal Store report preserves observation time separately
  from upload time.
- **AC-015:** Every Store/Product report identifies concept versus SKU/variant
  scope or records that the distinction is unresolved.
- **AC-016:** A transient Map runtime UUID is never the sole target key of a
  published community Store projection.
- **AC-017:** Every submission confirmation displays the target, structured claim,
  optional content, and delivery state before upload.

### 27.3 Lifecycle

- **AC-018:** The only official moderation states are Received, Under Review,
  Needs More Evidence, Verified, Implemented, Rejected, Duplicate, and Expired.
- **AC-019:** Every allowed transition in Section 12 has a positive transition
  test.
- **AC-020:** Every transition not listed in Section 12 is rejected and leaves the
  prior state unchanged.
- **AC-021:** Every substantive transition records reason, time, and applicable
  policy revision.
- **AC-022:** Reporter-facing status never labels Received as verified, accepted
  truth, fixed, or implemented.
- **AC-023:** Implemented status resolves to the exact domain revision/projection
  that applied the change.
- **AC-024:** A superseded or rolled-back domain revision does not erase the
  original report/moderation history.

### 27.4 Duplicate and conflict handling

- **AC-025:** One hundred retries with the same idempotent receipt yield exactly
  one accepted report identity and one corroboration contribution.
- **AC-026:** A retry after lost acknowledgement returns the original receipt and
  status.
- **AC-027:** Same-actor repeats do not increase independent-confirmation count.
- **AC-028:** Semantic near-duplicates are not merged automatically when Product,
  variant, Store, locale, market, or time scope differs.
- **AC-029:** A report-cluster merge preserves every original receipt, source,
  timestamp, and evidence disposition.
- **AC-030:** A merged cluster can be split without losing original provenance.
- **AC-031:** Materially contradictory reports remain represented as conflict and
  are not counted as corroboration.
- **AC-032:** Conflicted evidence cannot automatically publish or increase a
  categorical availability claim.

### 27.5 Trust and anti-abuse

- **AC-033:** Trust output exposes review-priority reasons and never a direct
  catalog/store mutation command.
- **AC-034:** Historical accuracy, freshness, independence, conflict, evidence
  completeness, target specificity, source strength, and abuse risk are each
  represented in trust-policy fixtures.
- **AC-035:** Trust influence is bounded; a maximum-reputation fixture still
  requires human verification and domain publication.
- **AC-036:** Linked devices/accounts cannot self-corroborate in shared fixtures.
- **AC-037:** Correlated campaign fixtures receive less independence than the same
  number of genuinely independent reports.
- **AC-038:** Reversal/appeal fixtures correct historical-accuracy inputs without
  deleting the moderation audit.
- **AC-039:** Rate-limited retries return a clear recoverable result and do not
  create duplicate reports.
- **AC-040:** Visual CAPTCHA, if ever used, has an equivalent accessible
  alternative.
- **AC-041:** Moderator actions are auditable separately from reporter reputation.

### 27.6 Catalog and search publication

- **AC-042:** Every community-originated catalog publication passes the same
  whole-catalog validator as maintainer-originated changes with zero errors.
- **AC-043:** Every accepted missing Product/alias/keyword/search issue has at
  least one regression fixture using the reported query or an approved
  privacy-safe equivalent.
- **AC-044:** New Product concepts receive new stable IDs; no existing stable ID
  is reused.
- **AC-045:** Alias publication passes canonical-name, alias-ownership, and
  brand-term collision validation.
- **AC-046:** Concept merge preserves redirect/inactive history; concept split
  never guesses existing user-reference reassignment.
- **AC-047:** Barcode candidates cannot publish directly to a generic concept
  without approved SKU/identifier verification.
- **AC-048:** A raw report, attachment, reporter identifier, IP/security signal,
  or moderation note never appears in the runtime catalog artifact.
- **AC-049:** Search report submission is triggered only by explicit user action;
  zero requests are sent merely because the user typed or received no result.
- **AC-050:** Local personalization remains below stronger textual relevance in
  shared regression fixtures after community-originated search changes.

### 27.7 Store and recommendation behavior

- **AC-051:** Every published Store profile correction resolves to one durable
  Store identity and records source/revision.
- **AC-052:** Temporary-unavailability evidence has an approved expiry and has
  zero recommendation influence after expiry.
- **AC-053:** Upload delay does not replace original observation time with receipt
  time.
- **AC-054:** One not-found report never produces "does not sell" or "out of
  stock" categorical UI.
- **AC-055:** Found and not-found evidence for the same scope produces a conflicted
  or mixed result rather than last-write-wins.
- **AC-056:** Provider, merchant, community, and WayTask-derived evidence remain
  separately attributable.
- **AC-057:** Current/future Store recommendation UI continues to disclose
  estimation unless inventory is verified by a competent approved source.
- **AC-058:** Report submission does not mark a Shopping Session line unavailable,
  skipped, collected, or purchased.
- **AC-059:** A community projection update cannot silently rewrite an active
  Shopping Plan/Session snapshot.
- **AC-060:** No raw report directly schedules a notification.

### 27.8 Offline, recovery, and Cloud

- **AC-061:** Product search, custom Product creation, Shopping, and active Session
  execution remain successful with Community Feedback unavailable.
- **AC-062:** Pending report delivery survives 100 cold-launch cycles without
  duplication or target/observation-time mutation.
- **AC-063:** A user can cancel an unsent report and subsequent reconnect produces
  zero upload attempts for it.
- **AC-064:** A report that expires while pending is not silently submitted as a
  current observation.
- **AC-065:** Account-free and multi-device retry fixtures preserve one canonical
  receipt when policy says they are the same submission.
- **AC-066:** Cloud synchronization of report status requires no upload of the
  Product Library, Shopping List, active Session, or route history.
- **AC-067:** Cache loss affects availability of community projections, not
  Product/Shopping truth.
- **AC-068:** Store/catalog projection rollback restores the prior approved
  revision without rewriting raw report history.

### 27.9 Privacy and security

- **AC-069:** Account-free submission is possible under the approved launch
  policy.
- **AC-070:** Real name, email, contacts, advertising ID, exact current GPS, route
  history, entire Shopping List, Product Library, and purchase history are not
  mandatory report inputs.
- **AC-071:** Store reporting succeeds when location permission is denied if the
  user can select the Store.
- **AC-072:** The pre-submit review shows all user-authored text and attachments
  that will be uploaded.
- **AC-073:** Image fixtures with EXIF location emerge from the approved upload
  boundary without that unnecessary location metadata.
- **AC-074:** Optional media can be removed before submission without losing the
  structured report.
- **AC-075:** Every personal-data class has an approved purpose, lawful basis,
  access role, retention/expiry rule, and deletion/de-linking behavior before
  launch.
- **AC-076:** Reporter identity and abuse/security signals are not exposed in
  public community or Store UI.
- **AC-077:** Access, correction, deletion/restriction, portability, and objection
  workflows are documented and tested where legally applicable.
- **AC-078:** Privacy deletion/de-linking does not falsely delete independently
  validated Catalog Truth, while unnecessary personal linkage is removed.
- **AC-079:** Raw report text, queries, media, or location are not used for AI
  training without a separately approved purpose, lawful basis/consent where
  required, and user notice.
- **AC-080:** Least-privilege tests prevent catalog reviewers from accessing
  unrelated abuse/network identifiers and prevent general moderators from
  accessing unnecessary account data.

### 27.10 Localization and accessibility

- **AC-081:** Every report type, reason, status, validation error, privacy notice,
  and appeal action has English and Hebrew localization coverage.
- **AC-082:** No raw enum, provider code, or untranslated moderation state appears
  in consumer UI.
- **AC-083:** Hebrew RTL fixtures render mixed-script Product names, barcodes,
  URLs, and Store names without changing semantic order.
- **AC-084:** VoiceOver announces target, claim, selection state, optional
  evidence, privacy consequence, upload state, and outcome in logical order.
- **AC-085:** All report flows remain operable at accessibility Dynamic Type sizes,
  with Switch Control, and by hardware keyboard.
- **AC-086:** Status and trust/freshness communication never relies on color or
  icon alone.
- **AC-087:** A user who cannot provide a photo has an equivalent report path.

### 27.11 Performance and platform parity

- **AC-088:** Community Feedback causes zero network request per search keystroke
  and zero network dependency in local suggestion latency.
- **AC-089:** Report upload never blocks the successful persistence of a Product,
  list mutation, session outcome, Finish, or Abandon command.
- **AC-090:** Runtime Store ranking consumes only the approved bounded projection
  for relevant context, not the raw report corpus.
- **AC-091:** Disabling/unavailability of Community Feedback results in no report
  polling or media work during ordinary Product/Shopping use.
- **AC-092:** iOS and Android pass shared fixtures for report types, lifecycle,
  duplicate handling, trust caps, expiry, and publication authority.
- **AC-093:** The same catalog release and stable Product IDs produce equivalent
  Catalog/Search truth semantics on iOS and Android.
- **AC-094:** AI-generated report drafts require explicit user review/submission;
  AI-generated moderation proposals cannot transition to Verified/Implemented.

### 27.12 Operational launch gates

- **AC-095:** A named owner exists for every moderation/domain queue.
- **AC-096:** Moderation, appeal, incident, rollback, privacy-request, and abuse
  response policies are approved and tested before launch.
- **AC-097:** Launch report volume is bounded to demonstrated moderation capacity;
  there is no unowned queue.
- **AC-098:** Durable Store identity and provider/source routing are approved
  before Store reports can reach Implemented.
- **AC-099:** SKU/barcode authority is approved before variant/package/barcode
  reports can reach Implemented.
- **AC-100:** Legal/privacy review approves controller, lawful bases, notices,
  retention, processors/transfers, and age policy before external collection.

---

## 28. Open Questions

These questions are unresolved. This audit does not invent answers.

### 28.1 Launch product scope

1. Which report types are included in the first Community Feedback release?
2. Are Product/Search reports launched before Store reports because stable Store
   identity is unresolved?
3. Is "Found here" included initially, or only negative quality reports?
4. Can users report outside an active Shopping context?
5. Should the reporter see only personal status or also privacy-safe aggregate
   community context?
6. What response-time expectation is communicated without promising an SLA that
   operations cannot meet?
7. Which rejection/expiry reasons are consumer-visible?
8. Is an appeal available for every report type or only substantive/high-impact
   decisions?
9. Should reporters be notified of status changes, and through in-app status,
   local notification, email, or account activity?
10. How are contributions acknowledged without creating competitive reputation
    pressure?

### 28.2 Product, SKU, barcode, and catalog

11. When will the future SKU/variant/package/identifier authority be approved?
12. Which barcode sources qualify as independently verified in each launch
    market?
13. How should an accepted custom user Product be offered a future canonical link
    without silently rewriting Product Truth?
14. Who owns Global Product Concept identity, merge, split, and redirect review?
15. Who owns taxonomy approval and cross-platform icon/localization review?
16. Can accepted community catalog releases be distributed independently of an
    app binary, and if so through what approved release/signing/rollback contract?
17. How does the existing `CATALOG_FEEDBACK.md` maintainer log reference future
    community cluster/publication identities without storing personal data?
18. What evidence is sufficient for a new generic concept versus an uncommon
    regional synonym?
19. How will catalog coverage avoid popularity bias against minority languages,
    local Products, accessibility needs, or small markets?

### 28.3 Search and localization

20. Who adjudicates regional synonym conflicts?
21. What misspelling frequency/evidence justifies a normalization rule rather than
    a keyword?
22. Which search revision identifier is exposed to users versus retained only for
    reproduction?
23. How are wrong-language catalog content and wrong UI localization routed?
24. May privacy-safe aggregate no-result metrics be collected separately, under
    what notice/lawful basis, or will all search evidence remain explicit reports?
25. How are ranking fairness and bias reviewed across English, Hebrew, and future
    languages?

### 28.4 Store identity and evidence

26. What is the durable cross-platform Store identity contract?
27. Which MapKit/provider identifiers may be stored and redistributed under their
    terms?
28. How are provider Store merges, branch moves, franchises, kiosks, and duplicate
    listings represented?
29. Who can verify a merchant, and what facts may a verified merchant assert?
30. What appeal path is offered to Stores/merchants affected by community
    evidence?
31. What evidence distinguishes temporary closure from permanent closure?
32. What evidence distinguishes temporary stock absence from an assortment
    change?
33. What expiry/decay windows apply by claim type, Product type, and market?
34. Can old evidence be used historically for model evaluation after it loses
    runtime recommendation influence?
35. Which source wins when provider, merchant, and fresh community evidence
    conflict, or must the UI represent uncertainty?
36. How are opening-hour exceptions, holidays, and seasonal Stores handled?
37. Who owns correction routing back to MapKit or other providers?

### 28.5 Trust, moderation, and anti-abuse

38. What are the trust dimensions' numeric weights, caps, and decay rules?
39. What qualifies as an independent reporter/source?
40. What signals may be used to correlate devices/accounts/networks, and under
    what privacy/legal basis?
41. What confirmation policy applies to each impact class?
42. Which decisions require two reviewers?
43. Who staffs each domain queue, in which languages and markets?
44. What review and appeal service levels can be sustained?
45. How are moderator consistency, reversal rate, and conflicts of interest
    audited?
46. What rate limits apply to account-free, account-linked, merchant, and provider
    submissions?
47. Which anti-bot method is both accessible and privacy proportionate?
48. When does suspicious activity justify temporary suppression versus rejection?
49. How are coordinated manipulation and merchant-targeting incidents escalated?
50. Is there a safe channel for urgent/high-impact Store corrections without
    bypassing review?

### 28.6 Privacy, legal, and retention

51. Who is the controller and which parties are processors or joint controllers?
52. What lawful basis applies separately to intake, status, moderation,
    reputation, anti-abuse, media, and aggregate quality measurement?
53. What launch countries and age groups are supported?
54. Is account-free reporting pseudonymous or can any mode genuinely satisfy the
    anonymity claim?
55. What pseudonymous receipt/identifier is necessary and how is it rotated or
    linked?
56. What are the exact retention periods for each data class in Section 17.8?
57. What media types are accepted, and what content/safety screening is lawful and
    proportionate?
58. Is a Data Protection Impact Assessment required?
59. What data residency and international-transfer safeguards apply?
60. How are access/deletion requests verified for account-free reporters without
    collecting unnecessary identity?
61. When may moderation/audit history remain after erasure, and how is reporter
    linkage removed?
62. What Store/business, defamation, consumer-protection, and intermediary-content
    rules apply by launch market?
63. May approved de-identified evidence be retained for quality research, and how
    is effective anonymisation demonstrated?

### 28.7 Cloud and multi-device

64. Is an account optional permanently or only during an initial phase?
65. How are account-free receipts linked to a later account with explicit user
    intent?
66. How are one person's multiple devices discounted from independence?
67. Which report content/status syncs, and which remains local?
68. What happens when a user deletes an account while reports are Under Review or
    already Implemented?
69. What publication distribution, signing, cache, expiry, and rollback mechanism
    is approved?
70. What is the Cloud conflict policy for status, attachments, withdrawal, and
    appeals?
71. Which device or service is authoritative for any notification about report
    status?

### 28.8 AI

72. Which AI triage/summarization tasks are allowed at launch?
73. How are AI confidence and reasons presented to moderators?
74. How is omitted/conflicting evidence detected in AI summaries?
75. Are raw reports or attachments ever used for model training/evaluation, under
    what separate purpose and user choice?
76. What quality threshold and human sampling validate AI duplicate suggestions?
77. How are AI-generated spam and synthetic evidence detected?
78. Who is accountable when AI misroutes a report or proposes a harmful change?

### 28.9 Operations and measurement

79. Which system/tool owns moderation operations? This audit does not select one.
80. What launch volume can the actual team review?
81. What backlog age triggers pausing intake or narrowing report types?
82. Which metrics measure quality without rewarding raw report volume?
83. How are false-positive publication, reversal, appeal, expiry, and time-to-review
    measured?
84. How are privacy incidents, moderator misuse, and Store-targeting incidents
    detected and handled?
85. Which aggregate metrics can be public without enabling contributor or Store
    harassment?

### 28.10 Blocking decisions

The following are blockers before any external Community Feedback launch:

- initial report-type scope;
- moderation owner and capacity;
- lifecycle/reason/appeal policy;
- durable Store identity for Store publication;
- SKU/barcode authority for those publication types;
- trust/independence/expiry policy;
- rate-limit and abuse policy;
- controller/lawful-basis/privacy notice;
- retention and data-subject-rights policy;
- processor/transfer/security review;
- launch language/market coverage;
- domain publication, revision, and rollback ownership.

---

## 29. Terminal Decision

### 29.1 Decision

**APPROVED:** The Moderated Evidence-to-Truth Pipeline is the official WayTask
Community Feedback architecture.

### 29.2 Binding product standard

1. User Opinion is a claim, not truth.
2. Community Evidence preserves provenance, freshness, independence, and
   conflict; it is not truth.
3. Product Truth is user-owned and never silently changed by community input.
4. Catalog Truth is a versioned, validated Global Product Concept release.
5. Store profile truth and Store/Product availability evidence remain distinct.
6. Search is a rebuildable projection of approved catalog/localization/ranking
   rules plus bounded local personalization.
7. No single report becomes authoritative automatically.
8. Reputation and volume prioritize review only.
9. AI assists intake/triage/proposals only under the default policy.
10. Human moderation verifies substantive evidence.
11. Domain governance and validation publish truth separately from moderation.
12. Current stable-ID catalog authoring, validation, versioning, redirect, audit,
    and regression rules remain the publication standard.
13. Brand, variant, package, barcode, concept, search, Store profile, assortment,
    and temporary availability reports are not conflated.
14. Volatile Store evidence expires.
15. A durable Store identity is required before community Store publication.
16. SKU/barcode authority is required before those reports can be Implemented.
17. Reporting is optional and never blocks core Product, Shopping, or Session
    workflows.
18. Active plans/sessions are not rewritten by community updates.
19. Notifications never consume raw reports.
20. Offline Product/Shopping/Session behavior remains first-class.
21. Account-free participation is pseudonymous unless true anonymity is
    demonstrated.
22. Exact current location, route history, Product Library, Shopping List, and
    purchase history are not required by default.
23. Raw reports, optional media, moderation history, and published domain facts
    have separate retention/purpose rules.
24. iOS and Android share identifiers, report semantics, lifecycle, trust caps,
    expiry, and publication fixtures.
25. No Community Feedback implementation launches without moderation, privacy,
    anti-abuse, publication, rollback, and operational ownership.

### 29.3 Explicitly rejected standards

The following must not become WayTask's Community Feedback architecture:

- one generic report type;
- direct user edits to catalog or Store truth;
- majority-vote publication;
- high-reputation unilateral publication;
- last-write-wins evidence;
- automatic merge by normalized Product name;
- barcode-to-concept assignment from one scan;
- permanent Store conclusions from temporary absence;
- raw community reports in Store ranking;
- public reporter identity or leaderboard authority;
- hidden no-result query collection as feedback;
- exact-location requirement for Store reporting;
- community reports stored as Product or Shopping state;
- notification tap treated as found/not-found evidence;
- AI as default moderator/publisher;
- a report button without receipt, lifecycle, moderation, and publication
  ownership.

### 29.4 Current architecture conclusion

The current application correctly makes no community-originated truth changes
because it has no implemented Community Feedback pipeline. The stable catalog
governance and honest Store-estimation language are sound foundations and should
not be changed merely for purity.

The current `StoreRealityFeedback`, future zero-weight signals, roadmap entries,
and internal `CATALOG_FEEDBACK.md` are not sufficient to claim implementation.
They should be treated as scaffolding and operational evidence only.

### 29.5 Implementation gate

WT-030C is audit-only and authorizes no implementation.

No source code, database schema, backend contract, catalog artifact, entitlement,
analytics, test, app behavior, or release is changed by this decision.

Implementation requires a later complete specification that resolves the blocking
questions in Section 28 and satisfies all acceptance criteria as one coherent
system. Partial report-button, direct-ranking, direct-catalog, or unmoderated
submission work is not authorized.

### 29.6 Final recommendation

Adopt this document as the official Community Feedback specification for WayTask.
Use it to govern future Product/Search/Store report design, moderation operations,
privacy review, Cloud contracts, Android parity, and AI workflows.

**WT-030C audit result: COMPLETE.**

---

## Appendix A - Current-to-Official Capability Map

| Current element | Current meaning | Official future relationship |
|---|---|---|
| Custom Product | Private Product Truth | May coexist with a separate catalog candidate |
| Local `ProductKnowledge` learning | Device recognition memory | Never Community Evidence unless user explicitly submits a separate report |
| `CATALOG_FEEDBACK.md` | Maintainer QA/work log | May reference reviewed community work without storing personal data |
| Catalog authoring tool | Maintainer validation/publication mechanism | Remains Catalog Truth gate |
| Shared catalog authoring audit | Catalog mutation history | Not reporter/evidence history |
| `StoreRealityFeedback` | Unused value scaffold | Does not define official evidence/trust policy |
| Future user/community ranking signals | Zero runtime influence | Future consumers of approved projections only |
| MapKit result | Transient provider Store snapshot | Evidence target input; not sole durable Store identity |
| Saved `GeoLocation` | User-local Store/location | Private user state; not global Store Truth |
| Estimated Store coverage | Heuristic recommendation | May later consume approved fresh projection |
| Beta Diagnostics | Technical troubleshooting export | Never silent community intake |
| Sentry diagnostics | Sanitized operational telemetry | Never Product/Search/Store truth input |
| Roadmap WT-006/WT-007 | Planned surface capability | Must conform to the complete pipeline |

---

## Appendix B - Truth Mutation Matrix

| Input | Product Truth | Catalog Truth | Search Truth | Store profile truth | Store/Product evidence | Active session |
|---|---:|---:|---:|---:|---:|---:|
| Raw user report | Never | Never | Never | Never | Never directly | Never |
| Evidence cluster | Never | Never | Never | Never | Not until approved projection | Never |
| Trust score | Never | Never | Never | Never | Priority only | Never |
| Moderator Verified | Never | Not by itself | Not by itself | Not by itself | Eligible for proposal | Never |
| Published catalog release | Never rewrites user snapshot | Yes | Rebuild input | No | No | Never silently |
| Published search revision | No | No | Yes | No | No | No |
| Published Store profile revision | No | No | No | Yes | Context only | Never silently |
| Approved expiring Store evidence projection | No | No | No | No | Yes | Never silently |
| Explicit user Product/Shopping/Session command | Yes, within command scope | No | No | No | No | Yes, within command scope |

---

## Appendix C - Report Routing Summary

| Report | Evidence target | Domain owner | Publication form |
|---|---|---|---|
| Product not found | Query + missing concept candidate | Catalog identity | Versioned catalog concept |
| Brand not found | Brand/discovery or SKU candidate | Catalog/Brand/Search | Approved brand discovery or future Brand/SKU projection |
| Variant/package missing | Future SKU candidate | SKU/identifier | Future reviewed SKU/package relationship |
| Category missing | Taxonomy proposal | Taxonomy | Versioned taxonomy |
| Barcode missing/wrong | Barcode + SKU candidate/conflict | Identifier/SKU | Reviewed identifier relationship |
| Wrong result/irrelevant | Query + result ID + revision | Search | Search/content revision |
| Missing/wrong synonym | Locale expression + Product ID | Search/Catalog | Approved alias/keyword/catalog release |
| Wrong language/misspelling | Locale/query/revision | Localization/Search | Localized content or search-rule revision |
| Duplicate Product | Two stable IDs/candidates | Catalog identity | Reject candidate or merge/redirect release |
| Store does not sell Product | Store + Product/SKU + time | Store evidence | Expiring confidence projection |
| Temporary unavailable | Store + Product/SKU + time | Store evidence | Short-lived expiring projection |
| Permanent assortment claim | Store + Product/SKU + corroboration | Store evidence | Reviewed, still expiring/renewable projection |
| Wrong category/hours/website | Durable Store + displayed source | Store profile/provider | Reviewed Store/provider revision |
| Closed/relocated/duplicate Store | Durable Store identity candidates | Store identity | Reviewed profile status/link revision |

---

## Appendix D - Current Evidence Traceability

| Evidence | Verified finding |
|---|---|
| `WayTask/WayTaskApp.swift` | Production autocomplete loads `ProductCatalogSearch` from bundled catalog |
| `WayTask/ProductCatalog` | Read-only model, loader, validator, normalizer, search, personalization |
| `WayTask/Persistence/WayTaskSchema.swift` | No Community Report/evidence/moderation/outbox model in schema v3 |
| Product save/persistence tests | Catalog ID and display snapshots persist; existing Product identity is preserved |
| `WayTask/ProductKnowledge` and scanner code | Recognition learning is local; provider/AI/manual results do not become community reports |
| `StoreRankingService.swift` | Feedback value exists; future user/community/provider signals score zero |
| `docs/75_STORE_RANKING.md` | Explicitly states no feedback UI or Cloud Sync |
| `MapBottomSheet.swift` | Navigate/Open Items/Website only; estimated availability wording |
| `WayTask/MainMapView.swift` | Map Store actions contain no report submission |
| Store resolution docs/code | MapKit Stores and Shopping Plans are runtime/transient; no global Store database |
| Notification code/docs | Store/list/Product context deep-links to Map; no report action or community authority |
| `CATALOG_FEEDBACK.md` | Internal catalog/search QA log, CAT-001 through CAT-009 |
| `PRODUCT_CATALOG_GUIDE.md` | Maintainer workflow requires collision checks, validators, release revision, regression, verification |
| `tools/catalog` and shared catalog | Developer authoring/validation only; 647 valid active concepts at audit time |
| `BETA_BACKLOG.md` | WT-006 and WT-007 planned, not implemented |
| `ROADMAP.md` | Beta 1.0.3 Community Intelligence is future scope |
| WT-030A | Product, list, plan, session, history, and catalog lifecycles are orthogonal |
| WT-030B | Community evidence may improve future confidence but cannot mutate active sessions or be required offline |
| EU/EDPB primary sources | Minimization, storage limitation, transparency, rights, privacy by design/default, and pseudonymised-data constraints |
