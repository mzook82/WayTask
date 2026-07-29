# WT-031C — Community Feedback Implementation Plan

**Product:** WayTask iOS
**Release context:** Version 1.0.3
**Document type:** Implementation planning only
**Controlling architecture:** WT-030C Moderated Evidence-to-Truth Pipeline
**Repository baseline inspected:** `35a0775`
**Plan date:** 2026-07-29
**Production implementation authorized:** No

This document translates the approved WT-030C architecture into a dependency-aware
implementation plan. It creates no production model, database schema, API,
backend assumption, catalog mutation, test, entitlement, project change, or
application behavior.

Normative labels used throughout:

- **Current — verified:** observed in the repository at the baseline above.
- **Approved:** binding behavior from WT-030C and
  `WT-030_ArchitectureSummary.md`.
- **Planned:** work for a later, separately approved implementation
  specification.
- **Unresolved:** a decision that the plan does not invent.
- **Deferred:** intentionally outside the first authorized implementation scope.

---

## 1. Executive Summary

### 1.1 Current implementation problem

WayTask currently has no Community Feedback system. There is no consumer report
model, evidence repository, offline outbox, submission API, acknowledgement
receipt, moderation state client, trust service, abuse-control boundary, durable
Store identity, Community projection, or Community-to-domain publication
adapter. No current user action silently becomes Community Evidence, and no
Community input changes Product, Catalog, Search, Store, Shopping, or Session
truth. That absence of unauthorized writers is correct and must be retained.

The repository does contain adjacent foundations:

- a validated, bundled, read-only Global Product Concept catalog;
- local catalog search and bounded personalization;
- a maintainer-only catalog authoring, validation, audit, and release workflow;
- private custom Products and device-local Product Knowledge;
- transient MapKit Store snapshots and private saved `GeoLocation` records;
- honest estimated-availability wording;
- an unused `StoreRealityFeedback` value type and three zero-scoring future Store
  signal placeholders;
- privacy-bounded Beta Diagnostics and Sentry operational diagnostics.

Those foundations do not constitute feedback intake, evidence, moderation, or
truth publication.

### 1.2 Approved target

WT-030C approved one pipeline:

```text
User Opinion
  -> user-reviewed submission
  -> durable local delivery/outbox
  -> idempotent server receipt
  -> normalized Community Evidence
  -> duplicate/conflict cluster
  -> trust-based review priority
  -> human moderation
  -> approved domain proposal
  -> domain validation and publication
  -> versioned Catalog, Search, Store profile, or Store evidence projection
```

Community Evidence is never Product Truth, Catalog Truth, Search Truth, or Store
Truth. A report, report count, trust score, AI output, client calculation, or
moderator verification cannot publish truth. `Implemented` requires a linked,
successfully published domain revision or approved expiring Store-evidence
projection.

### 1.3 Planned implementation approach

The plan introduces four deliberately separate implementation planes:

1. **iOS intake and delivery:** contextual draft, review, local persistence,
   idempotent outbox, acknowledgement, safe status cache, withdrawal request, and
   privacy-bounded diagnostics.
2. **Community service boundary:** intake validation, canonical receipt,
   evidence normalization, duplicate/conflict grouping, moderation state,
   retention, and abuse controls. No such service exists in the current
   repository; its contract and operational ownership are prerequisites.
3. **Moderation and governance:** safe administrative automation plus accountable
   human decisions, appeal/reopen, reviewer access control, and audit history.
4. **Domain publication:** separate Catalog, Search, Store profile, and expiring
   Store-evidence validators and publishers. The existing catalog validator and
   release workflow remain authoritative.

The local outbox is a delivery mechanism only. Runtime clients consume only
approved, revisioned projections; they never query raw reports for search,
planning, ranking, notification, or Shopping decisions.

### 1.4 Expected phases

The implementation program is planned as:

1. decision and specification gate;
2. characterization and privacy baseline;
3. evidence identity and local persistence;
4. submission commands and offline outbox;
5. synchronization and server acknowledgement;
6. moderation and publication integration boundaries;
7. UI, transparency, accessibility, and localization;
8. reliability, abuse, privacy, and release qualification;
9. one authority cutover and compatibility retirement.

These are engineering phases, not independently releasable authority variants.
No public report entry point may launch before the whole applicable path,
including moderation, publication, privacy, abuse, operations, rollback, and
safe disablement, has passed its gates.

---

## 2. Scope

### 2.1 In scope

WT-031C plans:

- the separation of User Opinion, Community Evidence, Product Truth, Catalog
  Truth, Search Truth, Store profile truth, and Store/Product evidence;
- contextual Product, Search, scanner, Shopping, Map, and notification entry
  points;
- structured report taxonomy and target snapshots;
- draft, queue, retry, acknowledgement, status, cancellation, withdrawal, and
  deletion behavior;
- a privacy-safe local outbox with stable submission identity and idempotency;
- synchronization boundaries without assuming a particular backend vendor,
  database, deployment topology, or account provider;
- the eight approved moderation states and their transition contract;
- duplicate, conflict, freshness, trust-priority, and anti-abuse boundaries;
- human moderation, escalation, appeal/reopen, audit, and operations gates;
- separate Catalog, Search, Store profile, and Store-evidence publication
  boundaries;
- provenance metadata and user-facing explainability;
- local persistence, migration, recovery, rollback, diagnostics, performance,
  accessibility, English/Hebrew localization, RTL, and platform-neutral
  fixtures;
- feature flags and emergency disablement that stop intake without damaging core
  Product or Shopping behavior;
- file-level production and test work for a later approved specification.

### 2.2 Explicitly out of scope

This plan does not:

- implement code, tests, schemas, backend services, Cloud, entitlements, catalog
  changes, localization resources, or UI;
- choose a backend vendor, database engine, hosting provider, moderation product,
  authentication provider, or deployment topology;
- authorize analytics, passive query collection, behavioral inference, or
  conversion of existing user data into reports;
- define Product State or Shopping Session implementation already owned by
  WT-031A and WT-031B;
- define a new Global Product Concept, SKU, barcode, Store identity, or retail
  inventory architecture;
- permit raw Community Evidence in search ranking, Store ranking, plans,
  sessions, notifications, or AI training;
- create public contributor profiles, leaderboards, vote counts, or a public
  trust score;
- guarantee Store inventory or availability;
- authorize moderator or publication actions from the consumer iOS app.

### 2.3 WT-031A and WT-031B boundaries

- WT-031A owns Product identity, library lifecycle, named-list entries, plan
  projections, session-line isolation, Product History, and catalog snapshots.
  Community intake may copy stable references and display snapshots into a
  report context, but it may not write or reinterpret any of those lifecycles.
- WT-031B owns persisted Shopping Session lifecycle, frozen execution snapshots,
  recovery, geofence eligibility, and notification validation. A report may
  originate from Shopping context, but it may not alter a session line, session
  revision, plan snapshot, Finish, Abandon, Expire, or reminder state.
- Product State and Session authority cutovers must be stable before Community
  integration relies on their final commands and snapshot contracts.

### 2.4 Candidate launch scope versus architectural coverage

The architecture covers the complete report taxonomy. Version 1.0.3 launch scope
is unresolved and must be selected at Phase 0:

| Report family | Planning classification | Binding constraint |
|---|---|---|
| Product not found; catalog name/category problem | Candidate for an initial Product/Catalog lane | Requires catalog identity/taxonomy owner, moderation capacity, and current catalog publication gate |
| Wrong/irrelevant result; missing/wrong synonym; misspelling; wrong language; duplicate concept | Candidate for an initial Search/Catalog lane | Requires query/revision capture, locale review, regressions, and separate Search/Catalog publication |
| Brand not found | Unresolved launch scope | Must not make a brand an alias or concept automatically |
| Variant, package size, barcode missing/wrong | Publication-blocked and therefore deferred unless a Phase 0 evidence-only policy is explicitly approved | Cannot reach `Implemented` before SKU/identifier authority exists |
| Missing Store; category/hours/website; closure/relocation/duplicate | Publication-blocked | Cannot reach `Implemented` before durable Store identity and provider-routing policy exist |
| Found here, not found today, temporary unavailability, assortment claim | Publication-blocked | Requires durable Store identity, Product/SKU scope, observation-time policy, expiry, conflict, and Store-evidence publisher |
| Attachments | Deferred by default from first collection scope | Requires media safety, EXIF removal, storage, retention, legal, and moderator-access approval |
| AI-prepared draft | Deferred | AI may prepare only a user-reviewed draft and may never submit or moderate |
| Passive behavior, search telemetry, Store visits, notification taps, Product edits, Shopping outcomes | Prohibited as Community intake | Only an explicit user-reviewed submission is evidence |

An evidence-only lane for a publication-blocked report type may not be launched
merely to accumulate an unowned backlog. It requires an approved user promise,
retention rule, moderation owner, disposition path, and volume limit.

### 2.5 Release boundary

The first external release must have one Community authority chain:

```text
one iOS submission command
  -> one idempotent intake authority
  -> one evidence/moderation authority
  -> one appropriate domain proposal path
  -> one domain publication authority
```

Feature flags may hide or disable the capability, but they may not select a
direct-to-truth path, a client-only report path presented as submitted, or two
simultaneous evidence authorities.

---

## 3. Current Implementation Inventory

### 3.1 Repository and specification baseline

**Current — verified:**

- The available Product Specification is
  `design/v1.0/WayTask_Product_Specification_v1.0.pdf`. There is no repository
  file named `Version_1.0.3_ProductSpec.md`.
- Controlling documents are:
  - `docs/Audits/1.0.3/WT-030C_CommunityFeedbackAudit.md`;
  - `docs/Audits/1.0.3/WT-030_ArchitectureSummary.md`;
  - `docs/ImplementationPlans/1.0.3/WT-031A_ProductStateImplementationPlan.md`;
  - `docs/ImplementationPlans/1.0.3/WT-031B_ShoppingSessionImplementationPlan.md`.
- Relevant current specifications and guides include:
  - `docs/Specifications/CanonicalProductCatalogSpecification.md`;
  - `docs/Specifications/ProductSearchUXContract.md`;
  - `docs/Specifications/SmartProductCreation.md`;
  - `docs/Specifications/ShoppingFlow_v1.md`;
  - `docs/Architecture/CatalogAwarePersistenceArchitecture.md`;
  - `docs/Architecture/ProductKnowledgeArchitecture.md`;
  - `docs/75_STORE_RANKING.md`;
  - `docs/170_BETA_DIAGNOSTICS.md`;
  - `docs/180_SENTRY_INTEGRATION.md`;
  - `PRODUCT_CATALOG_GUIDE.md`;
  - `ROADMAP.md`;
  - `BETA_BACKLOG.md`;
  - `CATALOG_FEEDBACK.md`;
  - `docs/60_CHANGELOG.md`.

### 3.2 Current component inventory

| Area | Verified files/types | Current responsibility | Community capability today |
|---|---|---|---|
| App composition | `WayTask/WayTaskApp.swift`; `WayTask/AppStateManager.swift`; `WayTask/ContentView.swift` | Opens the SwiftData container, loads bundled catalog, constructs local search, owns navigation state | No Community dependency, startup recovery, status refresh, or feature policy |
| Main persistence | `WayTask/Persistence/WayTaskSchema.swift`; `WayTask/Persistence/WayTaskSchemaV1.swift`; `WayTask/Persistence/WayTaskStartupPersistence.swift` | Schema V3 and migrations; startup repair; quarantine/recreate/in-memory fallback | V3 contains only `GeoLocation`, `ShoppingItem`, `Product`, `ShoppingList`, `ShoppingListEntry`, `ProductHistory`, `ProductKnowledge`, and `ShoppingSession`; no report, draft, outbox, receipt, evidence, moderation, account, or projection model |
| User Product | `WayTask/Models.swift` `Product`; `ProductListView.swift`; `WayTask/Persistence/AddProductSaveCoordinator.swift`; `CatalogProductPersistenceService.swift` | Stable user Product, library lifecycle/snapshots, local custom/catalog Product creation | Product creation/edit is private Product Truth, not a report |
| Catalog model/load/validation | `WayTask/ProductCatalog/CatalogProduct.swift`; `ProductCatalogService.swift`; `ProductCatalogValidator.swift`; `ProductCatalogCompatibilityDecoder.swift`; `ProductCatalogTaxonomy.swift`; `ProductCatalogCategory.swift` | Decode and validate bundled catalog and taxonomy; return active concepts | Read-only runtime; no Community intake or publication |
| Catalog artifact | `WayTask/Resources/product_catalog_he.json`; `shared/catalog/*`; `shared/catalog/product-catalog-review.json`; `shared/catalog/product-catalog-audit.jsonl` | Versioned catalog/taxonomy/review/audit artifacts | Current report output is valid: schema 1, catalog 5, taxonomy 1, locale `he-IL`, 647 active/0 inactive concepts, 23 categories, 22 subcategories, zero validation errors/warnings |
| Catalog authoring | `tools/catalog/catalog-tool.js`; `tools/catalog/lib/*`; `tools/catalog/test/*`; `tools/catalog/README.md` | Dry-run-first, atomic catalog mutation; stable IDs; whole-catalog validation; version increment; review/audit/regression workflow | Correct Catalog Truth gate; maintainer-operated, not a Community backend |
| Maintainer issue log | `CATALOG_FEEDBACK.md` | QA work log CAT-001 through CAT-009 | Not a report database, receipt, moderation queue, privacy store, or user-facing status |
| Catalog search | `WayTask/ProductCatalog/ProductCatalogSearch.swift`; `ProductCatalogPersonalization.swift`; `ShoppingItemCatalogResolver.swift` | Local normalized search and bounded personalization | No network-per-keystroke; no reporting; `brandTerms` and `legacyNames` are currently folded into indexed alias values and remain a Search-contract concern, not Community authority |
| Search presentation | `WayTask/ProductKnowledge/Presentation/AddProductAutocompleteViewModel.swift`; `ProductListView.swift` | Catalog suggestions, explicit catalog/custom selection, localized copy helpers | No report action; no stored reviewed query/search revision/report context |
| Legacy Product Knowledge | `WayTask/ProductKnowledge/*`; `ProductKnowledge.swift`; `ProductKnowledgeService.swift` | Bundled legacy knowledge search plus private device recognition memory | Local learned data is not Community Evidence and has no submission path |
| Scanner | `CameraView.swift`; `CameraViewModel.swift`; `OpenFoodFactsProvider.swift`; `GeminiProductRecognitionService.swift`; `ProductCandidate.swift` | Barcode/provider lookup, AI recognition, manual fallback, user review, local Product creation/learning | OpenFoodFacts GET and Gemini POST exist, but neither is a Community submission service; scan/photo/barcode data is not reported |
| Store discovery | `StoreSearchService.swift`; `MapViewModel.swift`; `WayTask/MainMapView.swift`; `MapBottomSheet.swift`; `BuyingOptionsService.swift`; `BuyingOptionsSheet.swift` | Saved and MapKit Store discovery, transient runtime Store materialization, estimated Product coverage, navigation | No report action or durable global Store identity |
| Store identity | `MapViewModel.swift` `RuntimeStore`, `StoreRuntimeIdentity`; `WayTask/Models.swift` `GeoLocation`; `DataSourceType.swift` | Saved Stores use local UUID; transient results derive UUID from source/title/coordinate buckets | Runtime UUID is reproducible for a snapshot but not an approved durable cross-platform Store ID |
| Store ranking | `StoreRankingService.swift`; `docs/75_STORE_RANKING.md` | Local signal-based likelihood and explanation | `StoreRealityFeedback` is unused; `userFeedback`, `communityKnowledge`, and `inventoryProvider` signal implementations always score zero |
| Store UI wording | `MapBottomSheet.swift`; `WayTask/MainMapView.swift` | “Likely here” and “Availability is estimated” disclosure | Correct uncertainty baseline; no feedback/status/provenance UI |
| Shopping | `WayTask/ShoppingWorkspaceView.swift`; `ShoppingListService.swift`; `ShoppingTripService.swift`; `ShoppingSessionService.swift`; `ShoppingSession.swift` | List, plan, trip, session execution and history paths | No Community writer; Shopping context could originate a future draft only |
| Notifications | `GeofenceNotificationService.swift`; `WayTask/AppStateManager.swift`; `WayTask/ContentView.swift` | Encodes Store/list/item/coordinate snapshots, schedules estimated nearby reminders, deep-links to Map | No report action; payload is not durable Store or Community authority |
| Diagnostics | `WayTask/BetaDiagnostics.swift`; `WayTask/BetaDiagnosticsView.swift`; `WayTask/SentryReportingService.swift` | Explicit local beta report export; allowlisted operational crash/nonfatal diagnostics | Neither is Community intake. No product analytics. Sentry excludes content, exact location, request bodies, identity, tokens, screenshots, and replay by policy |
| Settings | `SettingsView.swift` | Custom Stores, notification permission, product-knowledge summary, developer diagnostics | No account, privacy request, reports/status, consent, or Community controls |
| Localization | Swift source copy helpers and hard-coded SwiftUI strings; catalog locale metadata | Current Hebrew catalog and some locale-aware copy | No `.xcstrings` or `.strings` resource is present; no Community terminology |
| Networking | `OpenFoodFactsProvider.swift`; `GeminiProductRecognitionService.swift`; image loading in `WayTaskDesignSystem.swift`; Sentry SDK boundary | Provider/AI/image/diagnostic traffic | No general API client, auth, CloudKit, Community sync, network monitor, or background transfer contract |
| Project/platform | `WayTask.xcodeproj/project.pbxproj` | iOS target, tests, location descriptions, Sentry package | No Community entitlement, background task identifier, account capability, or localization catalog |

### 3.3 Current tests and fixtures

**Current — verified:**

- Catalog tests cover service loading, canonical validation, compatibility,
  migration, search, autocomplete, personalization, and shared fixtures under
  `WayTaskTests/ProductCatalog/`.
- Product Knowledge tests cover local repository/search/resource and legacy
  creation under `WayTaskTests/ProductKnowledge/`.
- Persistence tests cover Product/catalog compatibility, schema migration,
  startup recovery, repair idempotency, and Product library deletion under
  `WayTaskTests/Persistence/`.
- Current integration/UX-adjacent tests include:
  - `WayTaskTests/Map/MapBottomSheetProductLabelTests.swift`;
  - `WayTaskTests/ShoppingClassification/*`;
  - `WayTaskTests/ShoppingUX/ShoppingWorkspaceUXTests.swift`;
  - `WayTaskTests/Monitoring/SentryStabilityTests.swift`.
- Catalog CLI tests exist in `tools/catalog/test/catalog-tool.test.js`.
- No Community Feedback, evidence state, outbox, submission, moderation,
  trust/abuse, privacy, attachment, projection, or publication-authorization test
  exists.
- No Community fake/demo report state or fixture was found.

### 3.4 Current data classification and migration inventory

| Existing data/artifact | Classification | Planned treatment | Reason |
|---|---|---|---|
| `Product`, custom Product edits, catalog snapshots | Retained; unrelated | Never migrate or reinterpret as evidence | User Product Truth |
| `ShoppingItem`, list entries, plans, sessions, outcomes, `ProductHistory` | Retained; unrelated | Never migrate or infer a report | Shopping/Session/History authority |
| `ProductKnowledge` learned records | Retained; unrelated/private | Never upload or convert; only explicit new report may copy user-reviewed context | Recognition memory is not an opinion submission |
| Search text, suggestion display, selection, no-result behavior | No Community record exists | Do not reconstruct; only explicit future reviewed report captures the chosen query | Behavioral telemetry is not evidence |
| `GeoLocation` saved Stores | Retained; unrelated/private | May be displayed as private context; never publish as Store Truth or upload without explicit review | User-local Store data |
| MapKit/runtime `RuntimeStore` | Ephemeral source snapshot | Future report may snapshot allowed provider/source fields; never use runtime UUID as sole publication key | No durable Store registry |
| `StoreRealityFeedback` | Deprecated scaffold; no persisted instances | Do not migrate. Replace or remove only at final compatibility retirement after approved projection consumer exists | Inadequate identity, lifecycle, trust, privacy, and authority |
| Future zero-weight Store signals | Inactive compatibility scaffold | Keep zero until final cutover; later accept only approved published projection, never raw reports | Current zero influence is safe |
| `CATALOG_FEEDBACK.md` | Historical/operational maintainer log | Retain; may reference privacy-safe Community cluster/publication IDs later, never raw user content or PII | Existing catalog governance |
| Catalog review/audit artifacts | Retained publication history | Never import as user reports; link future community-originated releases by opaque proposal/publication ID | Catalog Truth audit is not evidence history |
| Beta Diagnostics events/exports | Unrelated local diagnostics | Never migrate or submit as Community Evidence | Technical troubleshooting only |
| Sentry events | Unrelated operational diagnostics | Never reinterpret as reports/trust; extend only with allowlisted aggregate delivery reason codes | No product analytics or content |
| `BETA_BACKLOG.md`, `ROADMAP.md`, changelog | Historical documentation | Retain as roadmap/history | Not evidence records |
| Product photos, scans, barcodes, provider/AI results | Private user inputs | Never backfill to Community. Future attachment/context requires explicit review and consent | Purpose limitation |

Because no Community records exist, there is no legacy Community-data migration.
The later implementation requires a fresh, versioned local Community store and
must not synthesize evidence from existing data.

---

## 4. Current Authority Problems

### 4.1 Correct current ownership to retain

The following are not problems and should not change for architectural purity:

- no user report currently writes any truth domain;
- catalog runtime is read-only and only exposes validated active concepts;
- catalog publication remains dry-run-first, stable-ID, whole-document validated,
  versioned, audited, and regression-tested;
- custom Product creation and scanner corrections remain private user Product
  behavior;
- local Product Knowledge remains device-local;
- Map and notification wording states that availability is estimated;
- future Community Store signals contribute exactly zero;
- core Product, Shopping, and Session behavior is offline-capable;
- Beta Diagnostics and Sentry do not act as product analytics or evidence intake.

### 4.2 Missing authority boundaries

| Verified gap | Authority problem | Product/reliability consequence | Planned resolution |
|---|---|---|---|
| No Community domain | There is no owner for claims, receipts, evidence, moderation, or status | A report button would have nowhere authoritative to send a claim | Introduce explicit intake, evidence, moderation, and publication contracts before UI exposure |
| No durable Store identity | `RuntimeStore.id` may derive from provider/title/coordinate; saved IDs are private/local | Store evidence can be orphaned or applied to the wrong branch/source | Block Store publication until cross-platform Store identity/provider routing is approved |
| No SKU/identifier authority | Current catalog represents Global Product Concepts; scanner/provider fields are local | Variant/package/barcode evidence could corrupt concept identity | Preserve distinct report types and block publication until SKU authority exists |
| No local outbox | There is no durable user-authorized delivery record | Offline retry could duplicate, lose, or mutate a claim | Add a separate delivery repository with stable submission ID and idempotency |
| No server receipt/status | Local “sent” could not prove acceptance | Users could be told a report was submitted when it was not | Treat only canonical server acknowledgement as `Received` |
| No moderation owner/tool/policy | No human decision or appeal path exists | Evidence could be ignored, auto-published, or retained indefinitely | Make operations ownership a pre-collection gate |
| No publication adapters | Moderator agreement has no controlled truth path | `Verified` could be mistaken for runtime truth | Require domain proposal, validation, exact revision link, then `Implemented` |
| No projection provenance | Runtime recommendations know heuristic signals but not an approved source/revision/freshness contract | Community influence would be opaque or stale | Add bounded published projection and presentation metadata |
| No report-specific privacy store | Existing Product/Shopping store and diagnostics have different purposes/retention | Mixed retention and accidental recovery/upload risk | Use a logically and physically separate Community local store and attachment area |
| No account/pseudonymous receipt policy | There is no contributor identity or rights channel | Cannot claim anonymous, deduplicate actors, withdraw, or satisfy rights | Phase 0 privacy/account-free receipt contract |
| No feature/kill policy | A broken or attacked intake path cannot be disabled independently | Abuse or service outage could affect UX | Server/client capability flag that fails closed for intake and leaves core app untouched |

### 4.3 Inadequate scaffolding that must not become authority

`StoreRealityFeedback` has `storeID`, free-text `storeName`/`itemName`, two
independent Booleans (`foundHere` and `notFoundHere`), a timestamp, and a
client-provided confidence. It has no Product concept/SKU scope, provider
identity, market, locale, observation/upload distinction, provenance,
idempotency, conflict, trust, moderation, retention, or publication linkage. It
is not persisted or consumed. Promoting it would create a client-authored truth
signal and is rejected.

Likewise, `StoreRealitySignalKind.userFeedback` and `.communityKnowledge` are
safe only because their implementations score zero. The final system may feed
Store ranking only an approved, bounded, unexpired Store-evidence projection.
The raw report, client trust value, count, or moderation record must never fill
those signals.

### 4.4 Context and UX defects

- Product/Search can reproduce a query and stable catalog result, but no report
  context snapshot exists.
- The scanner can identify barcode/provider/AI candidates, but local correction
  and community submission are not distinguished because submission does not
  exist.
- Shopping knows Product, list, plan, Store, and session context, but a generic
  report could accidentally copy private list/session content.
- Map shows source-derived Store context but offers only Navigate, Open Items, and
  Website actions.
- Notifications carry a serialized Store/list/item snapshot that may be stale;
  they cannot establish user presence, Store truth, or evidence.
- Settings has no report status, privacy disclosure, deletion/withdrawal, or
  Community availability surface.
- Consumer copy is largely hard-coded and has no complete English/Hebrew
  Community status vocabulary.

These are implementation gaps, not permission to add an isolated report button.

---

## 5. Target Community Feedback Domain Model

The following are conceptual types and ownership contracts, not production
schemas. Exact Swift names and persisted fields require the later implementation
specification. The eight moderation state names are already binding; local
delivery enum names remain an implementation naming decision.

### 5.1 Authority model

| Domain | Authoritative owner | What it owns | Community permission |
|---|---|---|---|
| User Opinion | User-reviewed local draft/submission | Original structured assertion and optional authored evidence | May be submitted explicitly; never truth |
| Community Evidence | Evidence service | Normalized claim, provenance, source/time/scope, cluster membership, conflict, freshness | May inform review priority and proposals only |
| Product Truth | User Product/list/session/history commands | User Product UUID/snapshots/library, list state, session state, history | No Community publication service exists; zero writes |
| Catalog Truth | Catalog governance and publication pipeline | Global Product Concepts, taxonomy, names, aliases, keywords, brand discovery, lifecycle/redirects | Receives approved proposals; retains validators and release authority |
| Search Truth | Search governance/release owner | Published searchable content, localization, ranking/normalization rules, revision | Receives approved proposals/regressions; raw queries/reports never become runtime input |
| Store profile truth | Durable Store identity/profile authority | Stable Store identity, source links, reviewed profile revisions | Receives approved Store proposals only after identity/provider contract |
| Store/Product evidence | Store evidence publication authority | Expiring, scoped, source-attributed availability/assortment projection | Receives verified clusters; never claims guaranteed stock from Community volume |
| Moderation | Human moderation service | Report disposition, reasons, evidence requests, duplicate confirmation, appeal/reopen | Cannot write any truth domain |
| Trust/abuse | Triage/security service | Review priority, independence discount, abuse risk, rate limiting | Cannot verify, reject substantively, or publish automatically |
| AI | Assistive adapter | Classification, clustering suggestion, summary, candidate proposal | Cannot submit for user, transition to `Verified`/`Implemented`, or publish |

### 5.2 Planned conceptual records

| Concept | Owner | Required semantics |
|---|---|---|
| `FeedbackDraft` | iOS user/draft repository | Mutable, local, user-visible; one report type; target snapshot; claim; optional note/media; consent disclosure; never evidence before queue/submit |
| `SubmissionEnvelope` | iOS outbox | Immutable after queue; stable random submission ID/idempotency key; payload/schema version; target snapshot; original observation time; locale/market/revisions; policy/consent version |
| `AttachmentArtifact` | iOS attachment store until upload; service after acceptance | Sanitized derivative, MIME/size/hash, upload state; no EXIF; separately removable/retained |
| `DeliveryRecord` | iOS outbox | Draft/pending/attempt/failed/cancelled/acknowledged delivery facts, retry count, next eligible attempt, safe error code, canonical receipt link |
| `SubmissionReceipt` | Intake service; cached on iOS | Canonical report ID, opaque status/withdrawal credential as approved, accepted timestamp, moderation state/revision, status capability |
| `EvidenceTarget` | Evidence service | Resolvable target or explicit unresolved target; stable Catalog Product ID, Search result/revision, durable Store ID when available, provider/source snapshot, concept-versus-SKU scope |
| `CommunityEvidenceRecord` | Evidence service | Normalized claim plus immutable original submission provenance, observation/upload times, market/locale, evidence type, freshness/expiry, contributor linkage under privacy policy |
| `EvidenceCluster` | Evidence service | Reversible membership; equivalence dimensions; independent corroboration; contradiction; no lossy merge and no simple vote |
| `TrustAssessment` | Trust/triage service | Contextual priority reasons, independence/correlation, freshness, completeness, conflict, source strength, abuse risk; bounded and auditable |
| `ModerationDecision` | Moderation service | One of eight official states plus reason, actor/role, time, policy revision, audit/reopen/appeal linkage |
| `DomainProposal` | Responsible domain governance | Typed candidate change with evidence/decision links; not runtime truth |
| `PublicationLink` | Domain publisher and Community status service | Exact domain, proposal, revision/projection ID, validation result, effective/expiry/supersession/rollback status |
| `PublishedProvenance` | Domain runtime projection | Source class, domain revision, freshness/expiry, conflict/confidence band, user-facing reason code; no reporter PII or raw report |

### 5.3 Submission identity and target invariants

- Generate a cryptographically random stable `clientSubmissionID` before the
  first queue operation. Use the same ID and idempotency key for every retry of
  the exact immutable envelope.
- Any edit that changes the payload after queueing must cancel/retire the old
  unsent envelope and create a new submission identity. A sent/acknowledged
  submission is never mutated in place.
- The envelope preserves target snapshots even if the live Product, catalog
  concept, Store, or provider result later changes.
- A Product-targeted report may include the stable catalog concept ID and a
  display snapshot. A user Product UUID is private context and is omitted unless
  a narrowly approved purpose requires it; it never becomes a global Product ID.
- A Store-targeted report requires provider/source attribution and a selected
  public Store snapshot. A runtime UUID is never the sole server/publication key.
- Temporal evidence stores `observedAt` separately from `createdAt`,
  `queuedAt`, `receivedAt`, moderator time, and publication time.
- Locale and market are separate fields.
- Submission/payload, moderation, and domain publication each have independent
  revisions.

### 5.4 Truth non-interference invariants

No Community component or submission may directly:

- rename, merge, split, restore, remove, or create a user Product;
- add/remove/resolve a Shopping-list entry;
- change a plan or active Shopping Session snapshot;
- set session-line collected/skipped/unavailable/purchased outcome;
- create purchase or Product History truth;
- allocate, merge, replace, deactivate, or rename a Global Product Concept;
- publish an alias, keyword, barcode, taxonomy, Search rule, Store profile, Store
  availability, or notification;
- change current Store ranking from raw evidence;
- treat a custom Product, Product edit, search selection, Store visit,
  notification tap, or Shopping result as an implicit report.

These boundaries require negative tests at every adapter.

---

## 6. Evidence Lifecycle

### 6.1 Three independent lifecycles

The system has three related but non-interchangeable lifecycles:

```text
Local delivery:
Draft -> Pending Upload -> submission attempt -> Sent/Acknowledged
                    \-> Failed -> Pending Upload
Draft/Pending Upload -> Cancelled

Moderation:
Received -> Under Review -> ... -> Verified/Rejected/Duplicate/Expired
Verified -> Implemented only after linked publication

Domain truth:
Proposal -> domain validation/review -> published revision/projection
          -> superseded/rolled back/expired under that domain
```

Local delivery answers “did this device safely deliver the user-authorized
payload?” Moderation answers “what is the evidence disposition?” Domain
publication answers “what approved truth revision is active?” A single status
field must not represent all three.

### 6.2 Conceptual-name reconciliation

| Requested concept | Planned interpretation |
|---|---|
| `draft` | Local mutable `FeedbackDraft`; not uploaded and not evidence |
| `queued` | Local `Pending Upload`; immutable authorized envelope |
| `submitted` | A transport event/attempt, not durable truth or moderation state |
| `acknowledged` | Canonical receipt returned; server moderation state is `Received`; local delivery becomes sent/acknowledged |
| `under review` | Official `Under Review` |
| `accepted as evidence` | Official `Verified`; still zero truth effect |
| `rejected` | Official `Rejected` |
| `withdrawn` | Administrative cancellation/privacy request, not an official moderation state |
| `expired` | Official `Expired` or local stale-before-upload disposition, recorded in the applicable layer |
| `published into an approved truth domain` | Official `Implemented` linked to a separate published revision/projection |

This mapping avoids inventing additional moderation states where WT-030C fixed
the state vocabulary.

### 6.3 End-to-end lifecycle

1. A contextual surface constructs a draft from allowlisted visible context.
2. The user selects exactly one structured report type and claim.
3. The user reviews the target, observation scope, optional content, disclosure,
   and delivery behavior.
4. Queueing freezes an immutable envelope and persists it before any upload.
5. The outbox attempts delivery with the same idempotency key until canonical
   acknowledgement or a terminal local action.
6. Intake validates structure, policy/version, payload bounds, consent,
   idempotency, and safe attachment manifest.
7. Successful intake creates or returns one canonical report identity in
   `Received`; an acknowledgement lost in transit is recovered by retry.
8. Evidence normalization preserves the original claim and provenance, then may
   add typed normalized fields.
9. Exact retries are the same report. Equivalent or conflicting reports are
   clustered without erasing individual receipts or evidence.
10. Trust and abuse services produce review priority and routing only.
11. Human moderation performs substantive state transitions and records reasons,
    policy revision, and accountable actor.
12. `Verified` evidence may create a typed proposal for the responsible domain.
13. The domain validates and publishes or rejects the proposal independently.
14. Only successful publication yields `Implemented` with an exact link.
15. Later supersession, rollback, or expiry changes the publication link/runtime
    projection, not the historical report/moderation record.

### 6.4 Withdrawal, deletion, and appeal

- A local Draft or unsent Pending Upload may be cancelled. Cancellation prevents
  all future attempts and applies the approved local deletion policy.
- Once intake has acknowledged a report, the user sends an authenticated or
  receipt-authorized withdrawal/privacy request; the client does not rewrite the
  moderation state.
- Withdrawal may de-link/delete contributor data as policy permits. It does not
  falsely erase independently corroborated evidence or a separately validated
  domain revision.
- An appeal/reopen is a moderated transition with policy, reason, and audit. It
  is not a resubmission storm and does not create independent corroboration.
- Account deletion, local receipt deletion, evidence deletion, moderator audit
  retention, and domain truth rollback remain distinct operations.

### 6.5 Lifecycle invariants

- `Received` never means verified, accepted truth, fixed, or implemented.
- `Verified` has zero runtime truth effect by itself.
- `Implemented` is impossible without a successful linked publication.
- Exact transport retry returns the original receipt; it does not create a
  second report or corroboration.
- Every rejected transition is atomic and preserves the prior state.
- Every substantive transition records reason, time, actor/automation class, and
  policy revision.
- Report state moves forward only under the official transition graph, except
  audited reopen transitions.
- Expired or stale temporal evidence cannot be silently relabeled current.

---

## 7. Evidence State Matrix

This is one logical state reference presented in three tables for readability.
Table A covers local delivery, Table B covers the official moderation states, and
Table C proves that publication has a separate lifecycle. Every row states all
required behaviors.

### 7.1 Table A — local delivery states and events

Exact persisted Swift case names are **Unresolved**. The semantics below are
binding. “Submission attempt” is intentionally an operation marker, not an
official moderation state.

| State/event | Allowed transitions | Authority owner | Client behavior | Server behavior | Moderation behavior | Publication behavior | Retry behavior | Offline behavior | Deletion/retention | Terminal? |
|---|---|---|---|---|---|---|---|---|---|---|
| Draft | Pending Upload; Cancelled | User through draft repository | Mutable; preview all authored content/attachments; validate locally; no success claim | None | None | None | None | Fully editable offline | User may delete immediately; draft TTL/storage limit required | No |
| Pending Upload / queued | Submission attempt; Failed; Cancelled; local stale-before-send disposition | Outbox repository under explicit user authorization | Immutable envelope; visible queue/age; core app remains usable | None until attempt | None | None | Same stable ID/key on every attempt | Persists across relaunch/termination; no silent mutation from current app state | Cancel removes queued payload/attachments per policy; pending TTL applies | No |
| Submission attempt / in flight | Sent/Acknowledged; Failed; Pending Upload after interruption | Outbox delivery worker | Shows sending without claiming receipt; serializes one envelope; never blocks Product/Shopping | Idempotently accepts/returns existing receipt or a typed error | No state until intake accepts | None | Lost response retries same key; one active attempt per envelope | Process/network loss returns durable record to retryable state | No cleanup until acknowledgement/error is durably recorded | No; ephemeral |
| Failed | Pending Upload; Cancelled; permanent local disposition after user-visible reason | Outbox repository | Shows privacy-safe recoverable/permanent reason and explicit retry where appropriate | May expose retryable, rate-limited, invalid, revoked-scope, or permanent rejection response | Structurally invalid payload rejected before `Received` is not a substantive moderation rejection | None | Capped exponential backoff with jitter and `Retry-After`; limits fixed by policy | Remains durable; no busy loop | Retain only within failure/attachment TTL; user can delete | No unless policy declares unrecoverable and user dismisses/deletes |
| Sent/Acknowledged local receipt | Status refresh; withdrawal request; local receipt deletion | Intake service is authoritative; client caches | Displays receipt and server state/revision; stops upload; never edits original envelope | Returns canonical report ID and `Received` or newer state | Official state machine begins at `Received` | None until later linked publication | Any replay returns same receipt; never adds evidence | Receipt/status cache usable offline and labeled last updated | Payload cleanup separates from receipt retention; keep minimal status token as approved | Yes for delivery, not moderation |
| Cancelled local | None for that envelope; a new draft creates a new ID | User/outbox | Never uploads; clearly local; may start a separate new draft | Must receive zero future requests for unsent cancellation | None | None | Disabled permanently for that ID | Durable tombstone long enough to suppress scheduled attempts, then privacy-safe cleanup | Delete content/attachments; bounded tombstone may retain ID/hash only | Yes for that envelope |
| Local stale-before-send disposition | New user-reviewed draft only | Outbox policy plus user | Explains that a time-sensitive observation is too old; does not send as current | None | None | None | No automatic retry; never rewrite observation time | Works offline | Delete/retain under stale-draft policy | Yes for that envelope |

### 7.2 Table B — official moderation states

| Official state | Allowed transitions | Authority owner | Client behavior | Server behavior | Moderation behavior | Publication behavior | Retry behavior | Offline behavior | Deletion/retention | Terminal? |
|---|---|---|---|---|---|---|---|---|---|---|
| Received | Under Review; Duplicate; Expired | Intake/evidence service | Show “Report received,” never “accepted/fixed”; cache revision | Persist canonical receipt/evidence; enqueue safely | Human or approved administrative triage begins | None | Submission retry returns same record | Show cached state with last-updated label | Raw/personal data follows approved retention; rights requests allowed | No |
| Under Review | Needs More Evidence; Verified; Rejected; Duplicate; Expired | Human moderation service | Show reviewing; no promised outcome/SLA; allow approved status refresh | Enforce transition and revision atomically | Review claim, source, conflicts, scope, policy; record reason/audit | None | Status refresh is read/idempotent; no resubmit | Cached status only | Retain evidence/audit by class and policy | No |
| Needs More Evidence | Under Review; Rejected; Expired | Human moderation service | Explain requested evidence without exposing others; optional accessible response only if policy supports it | Accept supplemental evidence as linked evidence, not payload mutation | Decide sufficiency; preserve original record | None | Supplemental upload has its own idempotency identity | User may prepare response offline; no false delivery | Extra media/text has separate retention and deletion | No |
| Verified | Implemented; Under Review (audited reopen); Expired | Human moderation service owns verification; domain owns proposal/publication | Say evidence was verified, not that truth changed; show domain review pending | Persist decision and create/route typed proposal only through authorized adapter | Human decision required by default; contrary evidence may reopen | Eligible only; zero runtime change until domain validates/publishes | Status reads only; proposal commands idempotent separately | Cached status; core app unchanged | Preserve decision/audit; personal linkage minimized under rights policy | No |
| Implemented | No report-state transition | Community status service records link; responsible domain owns active revision | Resolve to exact applied revision/projection and current superseded/rolled-back/expired publication status | Validate that link refers to successful publication before transition | Cannot set directly without publication proof | Linked domain revision/projection is the only truth effect | Reads are revisioned/idempotent | Cached outcome may be shown; runtime truth uses domain cache, not report cache | Report history remains; domain revision has separate retention/supersession | Yes for report outcome |
| Rejected | Under Review through approved appeal/reopen | Human moderation service | Show user-safe reason and appeal/correction path where approved; do not expose abuse detail | Preserve decision and revision; never publish | Substantive rejection requires human by default | None | Appeal command idempotent; resubmission not independent by default | Cached status | Retention/de-linking follows purpose and legal policy | No because audited reopen is allowed |
| Duplicate | Under Review when canonical link is shown wrong | Human moderation for semantic duplicate; intake for exact transport identity | Show canonical outcome when privacy-safe; never display other reporter content | Preserve original receipt and reversible cluster link | Confirm semantic equivalence; exact retry normally returns original identity instead of creating a row | None from duplicate count | Retry returns canonical receipt; zero corroboration inflation | Cached link/outcome | Preserve provenance while minimizing duplicate raw content | No because bad link may reopen |
| Expired | Under Review only with approved fresh evidence/reopen | Approved expiry policy plus moderation oversight | Explain evidence is no longer current; never imply falsehood | Apply claim-specific expiry with audit and revision | Review fresh evidence as linked evidence or approved reopen | None; an already published projection expires in its separate domain lifecycle | Old submission is not retried/re-dated | Cached expired state | Delete/minimize volatile raw data under retention schedule; preserve necessary decision audit | No because approved reopen exists |

### 7.3 Table C — separate domain publication lifecycle

These are conceptual domain events, not new Community moderation states; exact
names remain domain-specific.

| Domain publication stage | Owner | Allowed movement | Community/report effect | Runtime effect | Rollback/supersession |
|---|---|---|---|---|---|
| Approved proposal | Catalog/Search/Store governance | Validate; reject; request clarification | Report remains `Verified` | None | Proposal can be closed without truth mutation |
| Domain validation/review | Domain validator/reviewer | Publish; fail; return to proposal | `Verified`; never `Implemented` on failure | None | Failed validation retains evidence and diagnostics |
| Published revision/projection | Domain publisher | Activate; supersede; roll back; expire where temporal | Community service may atomically link then mark `Implemented` | Only this approved revision/projection | Previous approved revision restored or newer one activated |
| Superseded/rolled back/expired publication | Domain publisher | Domain-specific new revision/review | Original report history remains `Implemented` with publication link status | Old effect ends; no raw report fallback | Audit identifies active replacement/prior revision |

### 7.4 Matrix enforcement

- The client validates only presentation and command preconditions. The service
  independently validates every transition.
- Moderation and publication transition commands use optimistic revision checks
  and idempotency.
- Client caches accept only monotonically newer service state revisions; an
  out-of-order response cannot regress or invent a state.
- Unknown future states are displayed as a localized safe “Status unavailable;
  refresh later,” retained as opaque data, and never mapped to truth.
- A feature flag may stop new drafts/uploads or hide projection use, but it cannot
  rewrite moderation history.

---

## 8. Submission Strategy

### 8.1 Entry points and command ownership

| Surface | Planned report context | Allowed command | Explicit non-authority |
|---|---|---|---|
| Products / Add Product | Reviewed query, selected/no target, stable catalog ID/display snapshot, locale, catalog/search revision | `createDraft(context:)`; user selects Product/Catalog/Search type | Custom Product save remains separate; no automatic no-result report |
| Search result row | Query, result Product ID, position, match context/revision | Create Search-quality draft | Does not down-rank or change alias |
| Scanner | User-reviewed barcode/provider/AI candidate, optional local Product snapshot | Create barcode/variant draft if launch policy supports it | Scan, provider result, AI result, photo, or local correction is not uploaded automatically |
| Shopping | Selected Product concept/snapshot, selected Store/source, observation time; never entire list/session | Create Store/Product evidence draft | Session outcome and report are separate commands; Finish never waits |
| Map | Selected public Store/source snapshot, displayed category/hours/website, optional Product concept | Create Store issue draft | Saved private Store is not global Store Truth; current GPS not required |
| Notification | Deep-link to current Map/Shopping context only | User may choose report after current-context review | Delivery/tap is not presence, evidence, or pre-confirmation |
| Settings / report status | Existing receipts/statuses, privacy controls, feature availability | Retry, cancel unsent, request withdrawal, delete local copy | No moderator or truth mutation command |
| Future AI | Explicit proposed draft labeled AI-prepared | User edits/reviews and queues | AI cannot submit, fabricate evidence, or choose a moderation outcome |

### 8.2 Report taxonomy coverage

The labels below are semantic planning categories, not final wire-enum names.
Phase 0 must assign stable platform-neutral codes without merging distinct
claims.

| Target domain | Distinct report concepts that the contract must represent |
|---|---|
| Product/Catalog | Product not found; incorrect Product name; incorrect Product category; brand not found; variant not found; package size not found; barcode missing; barcode mapped to the wrong item; duplicate Product concepts |
| Search | Wrong search result; irrelevant result; missing synonym; wrong synonym; wrong language; misspelling/normalization problem; duplicate concepts exposed in results |
| Store identity/profile | Missing Store; wrong Store category; wrong opening hours; wrong website; temporarily closed; permanently closed; relocated; duplicate Store |
| Store/Product evidence | Recommended Store does not sell the Product; found here; not found today; temporarily unavailable; longer-lived/permanent assortment claim |

Incorrect Product name/category reports route to Catalog governance; incorrect
Store category routes to Store profile/provider governance; wrong-language UI
copy routes to localization rather than catalog identity. “Duplicate report” is a
lifecycle/cluster disposition, while “duplicate Product/Store” is a domain
identity claim. The implementation must not use one generic duplicate type for
both meanings.

### 8.3 Structured report contract

Every queued envelope includes, when applicable:

- exactly one stable report-type code and payload schema version;
- `clientSubmissionID` and idempotency key;
- target kind and target resolution state;
- approved stable Product/Store/source identifiers plus immutable display
  snapshots needed for review;
- structured claim and scope (`concept`, `brand`, `variant`, `package`, `SKU`,
  `unknown`);
- original observation time for temporal claims;
- locale and market;
- app version and relevant catalog/search/provider revision;
- user-reviewed query only for an explicit Search report;
- draft/created/queued timestamps;
- consent/notice/policy version;
- optional note and attachment manifest only when the report type and approved
  policy allow them.

The client never includes an entire Product Library, Shopping List, active
Session, route history, contacts, advertising identifier, authentication token,
ordinary diagnostics, or unrelated recent behavior.

### 8.4 Optional and required fields

| Field | Default |
|---|---|
| Structured report type, target/resolution, claim | Required |
| Observation time | Required for Store/availability/temporal claims |
| Locale; market when regional | Required where relevance depends on them |
| Catalog/search revision and displayed result ID | Required for reproducible Search reports when available |
| Source/provider snapshot | Required for Store/profile reports |
| Concept-versus-SKU scope | Required or explicitly `unresolved` |
| Free-text note | Optional, bounded, user-reviewed, PII warning |
| Category suggestion | Optional structured value |
| Barcode | Optional only in approved identifier lane; validated syntax is not truth |
| Selected public Store location | Minimum provider/public context; precise current location not required |
| Current GPS | Prohibited by default; requires separate explicit approved purpose |
| Photo/receipt/shelf label/link | Optional only after media gate; never mandatory |
| User identity | Account-free pseudonymous receipt by approved policy; real name/email not required |
| Device metadata | Not evidence by default; only minimal compatibility/security data under approved purpose |

### 8.5 Review, edit, cancel, and acknowledgement

- The pre-submit screen displays target, claim, time/market, optional note/media,
  privacy disclosure, and whether delivery will queue offline.
- The user can edit or cancel while the record is Draft.
- Queue freezes the envelope. Before the first attempt, returning to edit cancels
  the queued envelope and creates a new identity; after attempt/acknowledgement,
  corrections use a linked correction/withdrawal path.
- Double taps and navigation re-entry call the same idempotent queue command and
  cannot create two envelopes.
- Submission success is shown only after the canonical service receipt is durably
  saved. “Queued” and “Sending” are never called “received.”
- Permanent validation rejection shows a localized actionable reason and leaves
  core user actions complete.

### 8.6 Duplicate submission behavior

- Exact retry: same immutable envelope and key; service returns the original
  receipt and state.
- Same actor/same claim: service links under approved policy and does not increase
  independence.
- Independent equivalent evidence: separate report receipt, reversible cluster.
- Near duplicate: suggestion only until semantic human review.
- Editing the claim, target, scope, observation time, or attachment manifest
  produces a new submission identity and optional correction link.

### 8.7 Attachment handling

If attachments enter an approved scope:

1. Import into a protected temporary area; do not upload the original asset
   directly.
2. Decode and re-encode an allowed derivative, remove EXIF/location/hidden
   metadata, bound dimensions/bytes/type, and compute an integrity hash.
3. Show the exact derivative and note to the user before queueing.
4. Persist a stable local attachment ID and manifest separate from report text.
5. Upload idempotently and record per-part state.
6. Intake creates the report only when the approved manifest is complete, or
   explicitly accepts a report without the failed optional attachment after user
   confirmation. It never implies partial media was reviewed.
7. Scan server-side for safety/privacy under approved policy.
8. Delete local derivatives after acknowledgement/retention threshold unless the
   user needs them for a retry.

Attachments remain deferred until every step, storage budget, moderator role,
legal purpose, and retention period is approved.

---

## 9. Offline Outbox Strategy

### 9.1 Persistence ownership

**Planned:** use a dedicated Community Feedback local repository and physical
store, separate from `WayTaskSchemaV3` and the Product/Shopping model container.
This is justified by different authority, retention, optional service
availability, attachment lifecycle, account-free receipt secrets, feature
rollback, and the need to avoid Product-store recovery inventing or silently
deleting claims.

The later specification must choose the concrete Apple persistence technology
and versioned model. A separate SwiftData container is the default candidate
because the app already has tested SwiftData migration/recovery patterns; that
choice is not a schema authorization. Attachments belong in a protected,
repository-owned Application Support directory, not as large Product-store
blobs. Opaque bearer/withdrawal credentials belong in Keychain, not diagnostics
or ordinary persisted envelopes.

### 9.2 Outbox records

The repository owns:

- mutable local drafts;
- immutable queued envelopes;
- delivery state and attempt lease;
- stable submission ID/idempotency key;
- attempt count, last attempt time, next eligible retry time, and safe error code;
- attachment manifest and local sanitized file references;
- canonical server receipt/status token after acknowledgement;
- bounded cancelled/tombstone identity needed to suppress stale scheduled work.

It does not own Community Evidence, moderation truth, trust, or publication.

### 9.3 Outbox commands

| Command | Preconditions | Atomic result | Failure behavior |
|---|---|---|---|
| Create/update draft | Feature available for drafting; valid local target context | Draft persisted with revision | Preserve previous draft; no upload |
| Add/remove attachment | Media scope approved; draft mutable | Sanitized artifact plus manifest revision | Delete partial derivative; draft remains |
| Queue/freeze | User reviewed current draft; required fields/notice valid | Immutable envelope + stable ID/key + Pending state | No network attempt unless durable write succeeds |
| Claim attempt lease | Pending/eligible Failed; no live lease; feature permits upload | One bounded lease/attempt marker | Process death lease expires safely |
| Record acknowledgement | Response matches ID/key and passes validation | Receipt saved, delivery terminal, retry stopped | If local save fails, retry same key later |
| Record retryable failure | Valid attempt lease | Failure code/backoff persisted | No spin; user sees safe status |
| Record permanent failure | Typed server/client policy error | Failure/disposition persisted | No automatic retry; allow correction/new draft |
| Cancel unsent | No canonical acknowledgement | Cancel tombstone, pending work invalidated, content cleanup | Any racing worker rechecks state before send |
| Request withdrawal | Canonical receipt and valid authority token | Separate idempotent request queued | Does not rewrite moderation state locally |
| Delete local copy | Policy allows and pending safety resolved | Draft/receipt/local media removed or de-linked | Does not instruct domain truth deletion |

### 9.4 Retry and backoff

- Correctness does not depend on background execution or a live process.
- Retry triggers are app launch, foreground activation, explicit user retry, and
  an approved discretionary transfer callback. A network-path observer may hint,
  but never declares delivery.
- Use server `Retry-After` where present; otherwise capped exponential backoff
  with jitter.
- Exact attempt count, maximum elapsed queue age, media TTL, and retry cap are
  Phase 0 policy decisions by report type.
- `4xx` validation/policy errors are not blindly retried. Authentication/receipt
  renewal, rate limit, server unavailable, timeout, and transport errors have
  distinct safe handling.
- One durable lease prevents concurrent foreground/background workers sending the
  same envelope. Server idempotency remains mandatory even with local exclusion.
- No retry may recompute the target, query, observation time, or payload from
  live Product/Shopping/Map state.

### 9.5 Process death, relaunch, and degraded storage

- On launch, expire abandoned attempt leases, verify envelope/attachment
  integrity, and recover eligible work without changing content.
- One hundred cold-launch cycles must preserve pending identity, target, and
  observation time with no duplicate.
- If the Community store cannot open, do not block the main Product/Shopping
  store. Disable queue/upload, show a bounded recoverable Community error, and
  never label an in-memory draft as durably queued.
- Community-store corruption follows its own quarantine/recovery policy. It must
  not reconstruct claims from Product, Shopping, diagnostics, or current Map
  state.
- A quarantined Community store is retained under an approved privacy-safe
  recovery window, with count/reason diagnostics only. User-authored content is
  not put in logs.
- Main-store in-memory fallback does not grant permission to upload Product or
  Shopping data. Community intake remains independently gated.

### 9.6 Partial upload and attachment recovery

- Attachment parts use stable part IDs and content hashes.
- A retry queries or safely repeats idempotent part upload; it never duplicates
  the report.
- The final intake commit references the complete approved manifest.
- If a part is rejected for privacy/safety/size, the client shows which optional
  evidence was excluded and requires user confirmation before sending a
  structure-only report.
- Orphan server parts and local files have bounded cleanup jobs.
- Cancellation invalidates future commit, requests server cleanup where
  supported, and removes local files under policy.

### 9.7 Storage and battery limits

- Draft count, queued count, per-file bytes, total attachment bytes, and age
  limits require measured Phase 0 values; unbounded storage is prohibited.
- Disabled Community Feedback performs no polling, media processing, or retry
  work during ordinary Product/Shopping use.
- Submission work is utility/background priority, never blocks Product save,
  list mutation, session outcome, Finish, or Abandon.
- A background `URLSession` may be used for approved media delivery, but no
  `BGTaskScheduler`, continuous network monitor, or background mode is required
  for correctness. Any later capability needs a separate project/privacy/battery
  review.

### 9.8 Outbox is never truth

An outbox row, `Sent` flag, retry count, attachment hash, or cached moderation
state can never:

- create evidence without canonical intake;
- increment trust or corroboration;
- update catalog/search/store data;
- score a Store;
- change a Product, list, plan, session, history, Map, or notification;
- serve as a local publication fallback while the service is unavailable.

---

## 10. Synchronization Strategy

### 10.1 Required service contract

No Community backend is present. Before production implementation, an approved
contract must provide:

- versioned intake endpoint with idempotency-key semantics;
- stable canonical report ID and acknowledgement;
- typed structural/policy/rate-limit/safety errors;
- moderation status with monotonically increasing state revision;
- receipt-authorized account-free status and withdrawal, or an approved account
  alternative;
- attachment manifest/part protocol if media is in scope;
- privacy deletion/de-linking and export routes as applicable;
- service capability/kill state;
- projection distribution/version/expiry/rollback contracts;
- auditability and operational ownership.

The plan does not select REST, GraphQL, database, queue, Cloud provider, or
deployment topology.

### 10.2 Client synchronization boundaries

| Local/service object | Authoritative side | Client synchronization rule |
|---|---|---|
| Draft | Current device/user | Does not sync in initial account-free scope unless future explicit multi-device policy |
| Queued envelope | Current device until acknowledgement | Upload exact immutable payload; no server merge with Product/Shopping |
| Receipt | Intake service | Cache opaque ID/token and last-known service revision |
| Moderation state | Moderation service | Read-only client projection; accept only valid newer revision |
| Publication link | Responsible domain plus Community status service | Read-only; resolves exact domain revision and active/superseded/expired status |
| Catalog/Search/Store projection | Responsible domain distribution | Separate download/cache path; never reconstructed from receipt or raw evidence |
| Withdrawal/deletion request | Privacy/intake service | Idempotent command with its own status; does not locally fabricate completion |

### 10.3 Retry and delayed acknowledgement

- Reuse the exact submission ID/key.
- If the first request committed but its response was lost, the retry returns the
  original receipt and current state.
- The service must reject reuse of a key with a different payload hash.
- A local acknowledgement is complete only after receipt persistence succeeds.
- An unknown server outcome remains Pending/Failed, not Received.
- Rate-limited retry returns a recoverable next time and creates no new report.

### 10.4 Target changes

| Change after draft/submission | Required behavior |
|---|---|
| User edits a Draft | Update local draft revision; no server effect |
| User attempts to edit queued payload | Cancel old unsent envelope and create a new ID; acknowledged report uses correction/withdrawal |
| Catalog Product replaced/deactivated | Preserve submitted ID/snapshot/revision; service may link replacement under catalog governance; never rewrite user Product UUID/snapshot |
| Catalog Product missing locally after update | Show submitted snapshot/status; do not guess a new target |
| Search rules/catalog revision changed | Preserve reproduction revision; a newer result does not invalidate original evidence |
| Runtime Store disappears | Preserve source snapshot; mark target unresolved for review; no fabricated durable ID |
| Durable Store merged/moved later | Store identity authority links revisions; report provenance retains original source |
| Store no longer exists | Moderation/publication decides closure/profile outcome; client does not delete truth |
| Payload rejected | Show typed reason; allow a corrected new draft; do not reuse key for changed payload |
| Server returns newer moderation state | Apply monotonic revision after transition validation; preserve local delivery history |
| User withdraws | Queue/request withdrawal; status follows server; do not recast as Rejected |

### 10.5 Status refresh

- Refresh on explicit status view, foreground with a bounded stale interval, and
  service-driven notification only if a later notification authority is
  approved.
- No per-keystroke, continuous, or ordinary Product/Shopping polling.
- Batch status refresh by opaque receipt IDs where privacy and service contracts
  allow it.
- Offline UI shows last updated time and does not present stale status as live.
- Unknown status/reason codes are retained, safely localized as unavailable, and
  never interpreted as publication.

### 10.6 Account-free, accounts, and devices

- Initial participation is account-free and pseudonymous unless policy proves
  true anonymity; the UI must not claim anonymity.
- A random submission/receipt identity is not a public profile and must not use
  advertising ID, contacts, full device fingerprint, or ordinary Product data.
- Future account linking requires explicit user intent and a server merge policy.
  It cannot inflate independence or upload unrelated local records.
- Multi-device deduplication and independence discounting are server policy.
- Account deletion while a report is under review or implemented follows the
  approved de-linking/audit/domain-truth separation; the client cannot decide it.
- Future Cloud Sync transports receipt/status separately from Product Library,
  lists, sessions, route history, and domain projections.

### 10.7 Offline and recovered connectivity

- Local catalog search, custom Product creation, Shopping, and active Session
  execution continue when Community services are absent.
- Reconnect retries only durable user-authorized envelopes.
- Time-sensitive queued evidence is revalidated for age and target compatibility;
  it is never silently re-dated.
- Projection cache loss reduces Community enhancement availability only. It
  cannot delete user data or active session context.
- Deferred notifications about temporary evidence are suppressed after evidence
  expiry.

### 10.8 Synchronization migration and compatibility

- API/payload/state/reason/projection formats are independently versioned.
- Server minimum-supported versions disable intake with a user-safe update
  message; they do not accept lossy payloads.
- Client decoders tolerate additive fields and unknown states without granting
  authority.
- Local-store migrations preserve stable submission IDs, payload hashes,
  observation times, attachment manifests, acknowledgement, and cancellation.
- Rollback to an older app must not resend an acknowledged envelope or treat an
  unknown newer status as Draft.
- Compatibility readers have a removal phase and are never alternate writers.

---

## 11. Moderation Strategy

### 11.1 Boundary

Moderation is a service and operations capability, not a consumer-iOS truth
writer. The iOS app may submit evidence, display a privacy-safe state/reason, add
approved supplemental evidence, request withdrawal, or start an approved appeal.
It must not expose reviewer controls, internal notes, abuse signals, contributor
identity, or a direct domain mutation command.

No moderation backend or tool exists in the current repository. Backend/service
and operations specifications are prerequisites; this iOS plan defines the
contract they must satisfy without inventing their topology.

### 11.2 Safe automation versus human authority

| Capability | Automation permitted | Human/accountable decision required |
|---|---:|---:|
| Payload/schema/size validation | Yes | Policy defines limits |
| Idempotent exact retry | Yes | No |
| Check-digit/syntax rejection | Yes, as structure only | Identity remains human/domain reviewed |
| Exact binary duplicate detection | Yes | No truth effect |
| Semantic cluster suggestion | Yes | Human confirms material equivalence |
| Conflict/staleness flag | Yes | Human evaluates consequence |
| Queue priority/trust reasons | Yes | Human substantive decision |
| Known unsafe-media quarantine | Yes under approved safety policy | Human escalation as policy requires |
| Administrative expiry | Yes only under approved claim-specific rule/audit | Human can review/reopen |
| `Verified` | No | Yes by default |
| Substantive `Rejected` | No | Yes by default |
| `Implemented` | No | Requires domain publication proof, not moderator discretion |
| Domain truth publication | No Community automation | Responsible domain validation and authorized publication |

AI may classify, summarize, cluster, translate for review, or propose a candidate.
AI output is labeled, reasons/confidence are available to reviewers, conflicting
source material remains accessible, and no AI command can produce `Verified`,
`Implemented`, a stable identity change, or a domain release.

### 11.3 Moderation queues and routing

Each accepted type routes to a named domain queue:

- Global Product Concept identity/catalog content;
- taxonomy/localization;
- Search relevance/normalization;
- SKU/variant/package/barcode, only after that authority exists;
- Store identity/profile/provider routing, only after durable identity exists;
- Store/Product temporal evidence;
- privacy/safety;
- abuse/security;
- appeal/reopen.

Every queue requires an owner, supported language/market, maximum launch volume,
backlog-age threshold, escalation route, and pause-intake behavior. An unowned or
over-capacity queue is a release blocker, not a reason to leave reports in
`Received` indefinitely.

### 11.4 Reviewer decisions and audit

Every substantive decision records:

- report and canonical cluster IDs;
- prior/new state and state revision;
- reason code plus protected internal rationale;
- applicable policy revision and evidence standard;
- reviewer/service actor and role;
- decision time;
- evidence/proposal/publication links;
- conflict, escalation, appeal, and reopen linkage;
- access and modification audit.

The public/client reason is a separately localized safe code. Internal notes are
never client telemetry. Reviewer access uses least privilege:

- catalog reviewers do not receive network/abuse identifiers;
- general moderators do not receive unnecessary account data;
- abuse investigators receive only approved security fields;
- attachment access is explicit, logged, and purpose-bound;
- publication permission is separate from evidence verification.

### 11.5 Needs More Evidence and supplemental material

- The request identifies the missing evidence category without disclosing other
  reporters or coercing optional sensitive data.
- A user who cannot provide a photo must have an equivalent structured path.
- Supplemental text/media has its own immutable identity, consent, idempotency,
  retention, safety checks, and provenance.
- It does not mutate the original submission, reset observation time, or count as
  a new independent reporter.
- Failure to respond follows an approved expiry/rejection policy and accessible
  explanation; the client does not invent a deadline.

### 11.6 Duplicate, conflict, and grouping review

- Exact retries resolve to one canonical report.
- Equivalent independent reports remain individually traceable.
- Same-actor repeats do not raise independence.
- Cluster merge is reversible and retains every receipt, timestamp, attachment
  disposition, source, and contradiction.
- Product/variant, Store/source, market, locale, or time differences block
  automatic semantic merge.
- Conflicting evidence remains visible to reviewers and reduces certainty; it is
  never collapsed by last-write-wins or omitted from an AI summary.

### 11.7 Escalation, appeal, and correction

- High-impact identity, closure, relocation, barcode, merchant, safety, or abuse
  claims route through documented escalation and, where policy requires, a
  second reviewer.
- Appeal availability and user-visible reasons are Phase 0 policy decisions.
- An appeal is idempotent, auditable, and transitions only through the approved
  reopen edges.
- Reversal corrects trust-history inputs without deleting the original
  moderation audit.
- Merchant/provider correction paths must not bypass evidence review or domain
  validation.
- Urgent claims may receive queue priority; urgency never grants publication
  authority.

### 11.8 Publication authorization and rollback

Moderation can produce a typed, approved proposal. It cannot:

- directly edit `product_catalog_he.json`;
- update `ProductCatalogSearch`;
- allocate or merge Product IDs;
- change Store ranking weights;
- write a Store profile or availability record;
- schedule a notification;
- mutate Product/Shopping/Session state.

The responsible domain returns a signed/authorized publication result with exact
revision and validation evidence. Publication failure leaves the report
`Verified` or under domain review and never marks it `Implemented`. Rollback or
supersession updates the publication link while preserving the report and
moderation audit.

### 11.9 Retention and operational safety

- Raw evidence, attachments, contributor linkage, security signals, moderator
  notes, decisions, proposals, and published facts have separate retention
  classes.
- Queue exports and support tools must not become ad hoc Markdown/email stores of
  personal reports.
- Staff training, conflict-of-interest policy, access review, incident response,
  privacy requests, and abuse investigations are launch requirements.
- Intake pauses safely when moderator capacity, privacy controls, publication,
  or incident response is unavailable.

---

## 12. Trust and Abuse-Prevention Strategy

### 12.1 Trust purpose and output

Trust answers “what should reviewers examine first, and why?” It never answers
“what becomes truth?” Trust is contextual by report type, target, market, time,
and source. It must expose bounded reason codes rather than one public or
unreviewable global score.

Planned evaluation dimensions from WT-030C:

- historical accuracy, corrected for reversals/appeals;
- freshness and claim volatility;
- genuinely independent confirmations;
- conflict/contradiction;
- evidence completeness;
- target specificity and resolvability;
- source strength;
- abuse/correlation risk.

Planned internal outputs are priority band, priority reasons, conflict/staleness
flags, and suggested queue. Exact bands, weights, caps, decay, and public
visibility are **Unresolved**. A maximum-trust result still requires human
verification and domain publication.

### 12.2 Non-authority contract

Trust, reputation, volume, votes, device/account history, provider confidence,
and AI confidence may not:

- automatically move a report to `Verified`, `Rejected`, or `Implemented`;
- allocate/merge/deactivate a Product or Store identity;
- publish Catalog/Search/Store data;
- directly change Store scoring, plans, sessions, or notifications;
- make same-actor or linked-device repeats independent;
- turn absence reports into a categorical “does not sell” statement.

Interface-level type separation and negative authorization tests must make these
commands unavailable to the trust service, not merely discouraged by comments.

### 12.3 Abuse threats

The implementation threat model must cover:

- accidental double submission and retry storms;
- spam, bots, automated media/text, and denial of moderation capacity;
- malicious Product, barcode, taxonomy, Store, hours, website, closure, and
  relocation claims;
- false availability/assortment claims;
- mass Store edits and merchant-targeted harassment;
- brigading and coordinated manipulation;
- sockpuppets, linked devices/accounts, and reputation laundering;
- prompt-injection or synthetic content in AI-assisted moderation;
- unsafe links/media, faces, payment information, secrets, and personal data;
- reviewer misuse, collusion, compromised credentials, and audit tampering;
- enumeration of reporters, receipts, Stores, or moderation cases;
- withdrawal/deletion and attachment-cleanup abuse;
- feature-flag/configuration bypass.

### 12.4 Controls

| Layer | Planned controls |
|---|---|
| Client | Explicit review; type/size bounds; idempotency; no hidden submission; local attempt lease; privacy warning; feature flag; no client trust/publication command |
| Edge/intake | Authenticated or receipt-bound account-free channel; schema/payload validation; rate limits; replay protection; request/body limits; idempotency hash; safe error |
| Evidence | Same-actor/link correlation under approved privacy basis; reversible clustering; conflict preservation; expiry; provenance |
| Trust/triage | Bounded priority; independence discount; campaign/correlation risk; human-readable reasons |
| Moderation | Human substantive review; language/market routing; escalation; second review by impact; appeal/reopen |
| Publication | Separate permissions; validator; revision; audit; staged activation; rollback |
| Operations | Queue/capacity alarms; anomaly detection; access review; incident playbook; intake pause; report-type/market disable |

### 12.5 Rate limits and duplicate safety

- Server rate limits are authoritative and differ by account-free/account-linked,
  attachment, report type, target, and impact only under an approved policy.
- Client throttling improves UX but is not abuse security.
- Rate-limited responses are recoverable, localized, carry safe retry timing, and
  create no new report.
- Idempotent exact retry is not penalized as spam and never adds corroboration.
- Repeated distinct submissions from the same linked actor may be grouped or
  throttled without silently treating them as independent.
- Exact numeric thresholds, device/network signals, and retention are
  privacy/legal and operations decisions.

### 12.6 Privacy-preserving abuse signals

- Do not use advertising identifiers, contacts, Product Library, Shopping
  history, precise location, or general behavioral analytics for reputation.
- Pseudonymous contributor/security identifiers are purpose-limited, access
  controlled, rotated/retained under policy, and not exposed to normal
  moderators or public UI.
- IP/network and device signals, if approved, stay in an abuse-security plane,
  not the evidence record/runtime projection.
- Linked devices/accounts cannot self-corroborate.
- Privacy deletion may de-link personal identifiers while retaining the minimum
  lawful moderation/publication audit; the decision must be documented.

### 12.7 Emergency disablement and safe degradation

The capability policy supports:

- global intake off;
- report-family/market/media off;
- upload paused while drafts remain local;
- status read-only;
- projection influence off/rollback;
- moderator queue paused;
- publication lane off.

Flags fail closed and are authorized/configured outside client-editable user
defaults. Disabling Community Feedback causes no Product, Search-local,
Shopping, Session, Map baseline, or notification failure and performs no
ordinary polling/media work.

### 12.8 AI boundary

AI may assist only when:

- the exact approved task and input data classes are documented;
- user/moderator sees AI-prepared output and original/conflicting context;
- confidence/reasons are review aids;
- no raw content is reused for training/evaluation without separate purpose,
  lawful basis/consent where required, and notice;
- deterministic authorization rejects any AI-originated verification/publication
  command;
- quality, bias, omission, injection, and synthetic-evidence tests pass.

No AI Community work is included in the initial iOS implementation unless a
later approved specification explicitly scopes it.

---

## 13. Publication and Truth-Update Strategy

### 13.1 Required separation

```text
Community service: report -> evidence -> moderation -> approved proposal
                                            |
                                            v
Domain service: proposal -> domain validation -> publication -> runtime projection
```

The boundary is enforced through separate identities, permissions, command
interfaces, audit trails, and deployment/release owners. A moderator role cannot
call a raw truth writer. The consumer app has no publication credential or
endpoint.

### 13.2 Domain ownership

| Truth domain | Publication owner/service | Current verified foundation | Planned Community integration | Prohibited shortcut |
|---|---|---|---|---|
| Product Truth | No Community publication service. Only explicit user Product/list/session/history commands | `Product`, list/session services, WT-031A/B | None; a report may retain an allowed display snapshot only | Community linking/renaming/removal/restoration or purchase inference |
| Catalog Truth | Catalog governance/release owner using current catalog toolchain and validators | `tools/catalog`, `ProductCatalogValidator`, shared catalog/review/audit, catalog tests | Reviewed proposal package references evidence cluster; curator performs current validation/version/release; publication returns exact catalog revision | Direct report-to-JSON write, client edit, ID allocation/merge by vote/AI |
| Search Truth | Search governance/release owner; current app rebuilds local search from published catalog/code/rules | `ProductCatalogSearch`, normalization, personalization, search fixtures | Approved content/rule proposal plus privacy-safe regression query; versioned Search/catalog release | Raw query collection, complaint-count down-rank, alias auto-add |
| Store profile truth | Future durable Store identity/profile publication authority | MapKit/source snapshots and private `GeoLocation`; no registry | Only after identity/provider contract; reviewed name/location/category/hours/website/status proposal and revision | Runtime UUID or private saved Store as global ID; one-report closure |
| Store/Product evidence | Future expiring Store-evidence publication authority | Honest local heuristic ranking; zero future signals | Publish bounded target/market/Product/scope/direction/confidence/freshness/expiry projection | Raw reports/count/client confidence directly in `StoreRankingService` |

### 13.3 Catalog publication plan

Retain without weakening:

- stable lowercase concept IDs and no ID reuse;
- active/inactive/replacement lifecycle and redirect validation;
- canonical/alias/brand-term collision validation;
- taxonomy ownership and locale checks;
- whole-catalog validation before writes;
- dry-run review;
- one catalog-version increment per release;
- stale-write rejection, atomic file/review/audit update, reload/validation;
- regression fixture from the reported or approved privacy-safe query;
- shared iOS/Android semantics.

The Community system creates a proposal, never a catalog mutation. A future
privacy-safe bridge may put opaque cluster/proposal/publication IDs in the
maintainer workflow. It must not place reporter identity, raw note/query,
attachment, security signal, or moderation note in runtime catalog/review/audit
artifacts.

New concepts receive new stable IDs. Merges preserve inactive/redirect history.
Splits never guess reassignment of user references. Barcode candidates cannot
attach to a generic concept without SKU/identifier verification.

### 13.4 Search publication plan

- Capture an explicit, user-reviewed query only for the submitted report.
- Reproduce against the submitted catalog/search revision.
- Classify the defect as catalog content, alias/keyword/brand discovery,
  localization, normalization/ranking code, personalization, or UI copy.
- Domain owners approve the smallest authoritative change.
- Add positive and negative/collision regression fixtures.
- Preserve the rule that bounded personalization cannot override stronger
  textual relevance.
- Build runtime Search from published inputs. Raw reports and moderation state
  are absent from the index.
- Search revision identification and independent release distribution are
  **Unresolved**.

### 13.5 Store publication plan

Store publication remains blocked until:

- a durable cross-platform Store identity and provider/source-link contract;
- branch/merge/move/duplicate semantics;
- provider terms and correction routing;
- market and Store/Product/SKU scoping;
- claim-specific freshness, expiry, conflict, and evidence standards;
- profile versus availability separation;
- Store/merchant appeal and rollback;
- bounded projection distribution.

Store profile corrections and Store/Product evidence use different publishers.
Temporary evidence always expires. Found/not-found conflict is represented as
mixed/conflicted, not last-write-wins. One not-found report cannot produce “does
not sell,” “out of stock,” removal, or notification suppression.

### 13.6 Publication validation and minimum evidence

- “No single report” is a hard authorization rule, not necessarily a universal
  numeric threshold. Official-provider evidence and low-impact reproducible
  Search defects still follow their documented source/verification policy.
- Confirmation standards vary by impact; exact independent-evidence minima,
  reviewer count, source precedence, and expiry remain Phase 0/domain policy.
- Conflicting, stale, superseded, duplicate, or correlated evidence cannot be
  hidden to meet a threshold.
- Provider/merchant/community/WayTask-derived inputs remain separately
  attributable.
- Official-provider conflict routes to review; the latest or highest-volume
  source does not automatically win.

### 13.7 Publication transaction

1. Domain adapter accepts only an approved proposal and evidence/moderation
   references.
2. Domain service validates authorization, current base revision, stable target,
   evidence policy, conflicts, and domain-specific invariants.
3. Domain validator builds and validates the complete candidate revision.
4. Authorized publisher commits one versioned revision/projection and audit.
5. Distribution makes the revision available with integrity, freshness, and
   rollback metadata.
6. Community status service validates the publication proof and links it.
7. Only then may the report move from `Verified` to `Implemented`.

Every step is idempotent. Partial failure cannot publish truth without audit or
mark a report implemented without truth.

### 13.8 Runtime consumption

- `ProductCatalogService` continues to load a validated published catalog.
- `ProductCatalogSearch` continues to use published catalog/rules and local
  personalization, not Community records.
- A future Store projection repository exposes only bounded approved records for
  the relevant Store/Product/market context.
- `StoreRankingService` may consume that projection through an explicit source
  adapter after final cutover; raw reports, report counts, contributor identity,
  and client trust are unavailable to it.
- Active Shopping plans/sessions remain frozen. A newer projection may inform a
  future plan or explicit refresh command only under WT-031A/B.
- Notifications validate their own authoritative session/Store projection and
  never consume raw reports.

### 13.9 Reversible publication

- Catalog/Search/Store releases identify base and new revision, audit, and
  rollback target.
- Rollback restores the prior approved projection; it never deletes raw evidence
  or rewrites the original report/moderation decision.
- Client projection caches reject invalid/incomplete revisions, retain the last
  valid approved revision where policy permits, and respect expiry.
- A killed Community feature can disable use of a Community-derived Store
  projection independently of Product/Shopping.
- Publication signing/integrity and dynamic distribution mechanisms are
  **Unresolved**; bundled catalog behavior remains current until separately
  approved.

---

## 14. Community Transparency and Explainability

### 14.1 Architectural capability

Presentation layers must be able to explain whether a user-visible decision is
based on:

- official WayTask catalog information;
- official Store/provider information;
- reviewed recent community information;
- a combination of approved sources;
- WayTask's estimated recommendation logic.

The consumer text must use those plain concepts rather than “evidence cluster,”
“trust score,” or “publication projection.”

### 14.2 Provenance metadata

Published runtime projections need:

- domain and stable target/revision;
- source-class set: official catalog, provider, merchant if approved, reviewed
  community, WayTask-derived estimate;
- effective and last-reviewed/observed time where relevant;
- freshness/expiry and stale state;
- confidence/freshness band and reason code, not a raw opaque score;
- conflict/disputed/mixed indicator;
- superseded/rollback link;
- localization key and accessibility summary;
- attribution-suppression/privacy classification.

No runtime provenance contains reporter name, public contributor ID, raw note,
precise contributor location, receipt ID, moderation note, abuse signal, or a
count that could expose or harass contributors.

### 14.3 Presentation rules

| Situation | Planned user-facing behavior |
|---|---|
| Bundled/published catalog name/category | Present as WayTask catalog information; do not permanently label a canonical concept by individual contributors |
| Provider Store hours/website | Identify provider/official source where useful and permitted |
| Reviewed Community input materially affects current Store confidence | Say “Recent reviewed reports suggest…” or localized approved equivalent; include freshness/estimated limitation |
| Provider plus reviewed Community evidence | Say that the estimate combines Store information and reviewed recent reports |
| Evidence conflicted/disputed | Use “Recent reports are mixed” or approved equivalent; no categorical claim |
| Projection stale/expired | Remove influence; show unavailable/stale context only when useful, never current certainty |
| No approved Community influence | Show no Community attribution |
| Moderation status | Explain received/reviewing/needs info/verified/applied/rejected/duplicate/expired without internal codes |

Source labels, confidence wording, freshness granularity, and exact English/Hebrew
copy require user research, localization review, and legal/privacy approval.

### 14.4 Explainability boundaries

- Transparency explains approved sources; it does not expose private
  contributors or moderation internals.
- `Received` never displays “community verified.”
- `Verified` may say the report was reviewed/verified but still awaiting an
  applied change.
- `Implemented` links to understandable domain/version context when useful.
- Store availability remains estimated unless a competent approved inventory
  source provides a stronger claim.
- A report count is not confidence and is not required in consumer UI.
- Trust/reputation is not public.
- AI-generated wording must be derived from published provenance and cannot
  invent certainty or omit conflict.

### 14.5 Accessibility and localization

Every source/freshness/conflict state has:

- text in addition to color/icon;
- a concise VoiceOver label and longer hint where needed;
- English and Hebrew semantic parity;
- RTL-safe mixed Product/brand/URL presentation;
- Dynamic Type layout without hiding the uncertainty statement.

---

## 15. Privacy and Data-Minimization Strategy

### 15.1 Privacy posture

Participation is optional and account-free under the approved baseline.
Account-free means pseudonymous unless true anonymity is demonstrated. The
system collects only data necessary for intake, status, moderation, publication,
security, and legal obligations under separately approved purposes. Core Product
and Shopping use cannot be conditioned on reporting consent.

Privacy and legal approval is a pre-collection gate, not a post-launch notice
task.

### 15.2 Data classes

| Data class | Default collection | Purpose/owner | Client handling | Retention/deletion gate |
|---|---|---|---|---|
| Structured report type/claim | Required | Evidence/moderation | Encrypted-by-platform protected store; upload only after review | Claim-specific schedule |
| Target ID/source/display snapshot | Minimum necessary | Reproduction/routing | Include stable public ID or unresolved/source snapshot | Retain with evidence as required |
| Reviewed Search query | Only explicit Search report | Reproduce defect | Show before submission; never collect on typing/no-result alone | Shortest useful evidence/audit schedule |
| Observation time | Temporal reports | Freshness/conflict | Preserve separately from upload time | Claim-specific expiry |
| Locale/market | When relevant | Language/regional review | Separate fields; no inferred precise route | Policy schedule |
| Selected Store public location/source | Store reports only | Resolve branch/source | Selected Store, not current GPS by default | Store-evidence schedule |
| Precise current location/route | Not required; prohibited by default | None in baseline | Do not collect/upload/log | Any exception requires separate approval/consent |
| User note | Optional/bounded | Explanation | PII warning, preview, moderation access control | Raw-text schedule and rights handling |
| Attachment | Deferred/optional | Evidence | Sanitized derivative; separate protected storage | Short media schedule; delete independent of decision |
| Contributor identity | Minimum pseudonymous receipt/security linkage | Status, independence, abuse, rights | Opaque token; no public profile | Rotation/de-linking/account-delete policy |
| App/catalog/search schema revisions | Required when reproducible | Compatibility/reproduction | Safe structured values | Evidence schedule |
| Device metadata | Not evidence by default | Compatibility/security only if approved | Avoid exact device/fingerprint; segregate security signals | Purpose/legal/security schedule |
| IP/network/abuse signals | Service-side only if approved | Abuse/security | Never normal client/moderator/public field | Restricted retention/access |
| Moderation notes | Not client data | Review/audit | Never client telemetry/status payload | Moderator/audit schedule |
| Publication link | Required for `Implemented` | Explainability/audit | Read-only public-safe metadata | Domain revision retention |

### 15.3 Identity and account policy

- Real name, email, contacts, advertising ID, and public profile are not
  required.
- Generate no device fingerprint in the client. Use random scoped identifiers
  and server-issued opaque receipt/status credentials.
- Store bearer/withdrawal/status secrets in Keychain. Do not embed them in report
  bodies, UserDefaults, logs, URLs, or notification payloads.
- Contributor linkage needed for same-actor/abuse analysis is service-side,
  pseudonymous, purpose-limited, and inaccessible to public UI.
- Future authentication and account linking require explicit consent, account
  deletion behavior, multi-device conflict rules, and no reputation inflation.
- The policy must define how an account-free user proves access/deletion rights
  without collecting unnecessary identity.

### 15.4 Location

- A user selects the public Store target; location permission may be denied.
- Store/provider/source identity and a public branch coordinate may be necessary
  target data. Current user GPS and route history are not.
- Market/coarse region is preferred over precise location where only regional
  relevance is needed.
- Never infer a visit from Map display, geofence entry, notification, session, or
  current location and turn it into a report.
- Exact location requires a separately approved report type, explicit purpose,
  disclosure/consent, retention, access, and test; none is approved here.

### 15.5 Free text and attachments

- Structured choices are primary; notes are optional and length bounded.
- Warn users not to include names, contact details, payment data, secrets, or
  unrelated people.
- Apply privacy/safety screening without silently changing the user's claim.
- Show the complete authored note and exact sanitized attachment before upload.
- Re-encode images to strip EXIF/location metadata; do not trust metadata-field
  deletion alone.
- Do not log image content, hashes usable for cross-purpose tracking, OCR, full
  report body, or notes.
- Moderator media access is least-privilege and audited.
- Raw text/media is not AI training/evaluation data under the submission purpose.

### 15.6 Disclosure and consent

Pre-submit disclosure covers:

- what claim/target/context is sent;
- whether the report is queued offline;
- optional text/media;
- account-free pseudonymous status;
- moderation and possible domain publication;
- that reporting does not immediately change the catalog/current Shopping;
- withdrawal/deletion/status route;
- applicable notice/policy version.

Consent must be granular where media, precise location, account linking, or a
separate AI use requires it. Refusal leaves the structured report or core app
usable where possible.

### 15.7 Retention and deletion

Before collection, every class needs an approved purpose, lawful basis where
applicable, controller/processor/access roles, retention/expiry, deletion or
de-linking, backup behavior, and incident handling. At minimum, separate:

- unsubmitted drafts;
- pending/failed/cancelled envelopes;
- attachment derivatives and orphan parts;
- raw accepted reports;
- contributor linkage;
- abuse/security signals;
- evidence clusters;
- moderator decisions/audit;
- rejected/expired evidence;
- publication proposals;
- published domain truth and revision audit;
- local receipt/status cache.

Deleting a local receipt does not promise server deletion. Privacy deletion may
remove/de-link personal evidence while an independently validated Catalog Truth
revision remains. The UI must state the distinction honestly.

### 15.8 Rights and future account/Cloud behavior

The service and client plan for access, correction, deletion/restriction,
portability/export, objection, withdrawal, and account deletion where applicable.
Exact legal applicability, verification, and UI scope are unresolved and require
legal/privacy review.

Future Cloud synchronization:

- syncs report receipt/status only under explicit account policy;
- does not require Product Library, list, session, route, or purchase uploads;
- preserves one canonical submission and independence discount;
- uses separate retention/conflict rules for drafts, evidence, moderation, and
  projections.

### 15.9 Diagnostics and logging prohibitions

Ordinary client diagnostics must not contain:

- raw Product notes or user-authored report notes;
- full report body or reviewed Search query;
- precise location, route, or selected branch coordinate;
- image/media content, OCR, EXIF, or attachment URL;
- personal contact details or contributor identity;
- authentication, receipt bearer, withdrawal, or idempotency tokens;
- moderation notes or abuse/security details;
- Product Library, Shopping List, Session lines, or purchase history.

Allowed client diagnostics are enum-backed event/error type, app/schema version,
delivery-state category, retry-count bucket, latency/size bucket, attachment
present Boolean, service capability state, and aggregate success/failure counts.
Sentry's existing allowlist must be extended deliberately; raw `Error` text,
URL/request/response bodies, breadcrumbs, screenshots, and network capture remain
forbidden.

### 15.10 Privacy launch gates

External collection is blocked until approval of:

- controller/processors/transfers/residency and launch countries/ages;
- lawful basis/purpose per data class;
- account-free pseudonymous receipt and rights verification;
- notices/consent;
- precise/coarse location policy;
- free-text/media safety and EXIF handling;
- retention/deletion/de-linking/backups;
- moderator/abuse access control;
- security threat model and incident response;
- AI-use prohibition or separately approved choice;
- App Store/privacy manifest and platform disclosure review;
- DPIA or equivalent assessment decision where applicable.

---

## 16. File-by-File Change Plan

All filenames under “Proposed” are planning labels, not created files. The later
implementation specification may consolidate them, but may not collapse the
authority boundaries. Existing files marked “retain” require no Community change
unless the applicable launch scope needs an entry point or published projection.

### 16.1 Planned component contracts

The following matrix supplies the required contract for every planned component.
“CF” means the proposed `WayTask/CommunityFeedback/` module; “service” means a
future external capability not present in this iOS repository.

| Planned component | Current verified responsibility | Target responsibility / authority owner | Inputs -> outputs | Persistence / offline | Sync / failure | Privacy / diagnostics | Tests | Phase / dependencies |
|---|---|---|---|---|---|---|---|---|
| CF domain types | Absent | Platform-neutral report/target/delivery/receipt/provenance value contracts; owns no truth | User-reviewed primitives -> typed immutable values | Codable/versioned; no I/O | Unknown values fail safe | No PII in descriptions/logging | Type round trips; taxonomy distinctness; authority compile tests | 2; WT-030C taxonomy/policy |
| Draft repository | Absent | User-owned mutable draft lifecycle | Context + edits -> revisioned draft | Dedicated protected Community store; fully offline | No server; storage failure visible | Authored data never logged | CRUD, relaunch, cancel, corruption, limits | 2; persistence decision/privacy |
| Context factory | Surfaces each hold raw local context | Allowlists minimal snapshot without gaining surface authority | Product/Search/Scanner/Shopping/Map context -> draft seed | No independent persistence | No network; unresolved target retained | Excludes list/session/library/GPS by default | Per-surface allowlist/noninterference | 2/6; WT-031A/B final contracts |
| Attachment processor/store | Scanner/photo paths exist for Product recognition; no report media | User-reviewed sanitized derivative and lifecycle | Imported asset -> bounded EXIF-free artifact/manifest | Protected files separate from store; offline preview | Idempotent parts; partial failure explicit | No image/log/OCR; audited removal | EXIF, type/size, corruption, cancel, VoiceOver | 3+ only if media approved |
| Outbox repository | Absent | Durable delivery state, stable ID/key, lease, backoff; no evidence/truth | Frozen envelope + delivery events -> durable state | Dedicated store; survives process death | Exact retry; concurrency lease; typed failure | Safe codes/buckets only | 100-relaunch, idempotency, backoff, race, storage | 3; service contract |
| Submission client | Existing `URLSession` clients are provider-specific | One versioned intake adapter; intake service authoritative after ack | Envelope/parts -> canonical receipt/error | No authority cache beyond repository | TLS/auth/idempotency; unknown result retry | No bodies/URLs/tokens in logs | Mock transport, lost ack, rate limit, cancellation | 4; approved backend/security |
| Outbox worker | Absent | Opportunistic delivery orchestration | Eligible records + capability -> attempts | Correct without background; restart safe | Launch/foreground/manual/discretionary callback; no spin | Aggregate attempt telemetry | scheduling, lease expiry, disabled mode, battery | 3/4; repository/client |
| Receipt/status repository | Absent | Cache service-owned moderation/publication status | Receipt + monotonic updates -> user status | Minimal offline cache; separate credentials | Bounded refresh; unknown/newer state safe | No reviewer/other reporter data | revision/order/unknown/deletion/offline | 4; status API |
| Withdrawal/privacy command client | Absent | User-authorized administrative requests; service authoritative | Receipt credential + command -> request status | Durable command if offline policy allows | Idempotent; no local fake completion | Token in Keychain; safe status only | retry, account deletion, de-link, failure | 4/7; privacy API/policy |
| Feature capability policy | Only unrelated developer flags | Fail-closed intake/media/report-family/market/status/projection capability | Signed/approved config + local app compatibility -> capabilities | Last valid bounded config; safe default off | Service outage keeps core app; kill switch | No user segmentation based on private behavior | config validation, emergency disable, rollback | 1/4/7; ops/security |
| Composer view model | Autocomplete/scanner/map VMs own their workflows | Draft/review/queue commands only; Community repository owner | Draft seed + user edits -> queue result | Draft offline; no truth writes | Shows queued/sent/failed distinctly | Exposes disclosure; no hidden context | validation, double tap, stale target, cancellation | 6; domain/repositories/localization |
| Composer/status UI | No report UI | Explicit review, status, retry/cancel/withdrawal, explainability | View state -> named commands | Offline/degraded states | Never promises receipt/publication | English/Hebrew/RTL/a11y; no PII attribution | snapshot/manual/a11y/VoiceOver/Dynamic Type | 6; copy/privacy/policy |
| Community diagnostics | Beta/Sentry diagnostics exist with strict allowlists | Enum-backed delivery health only | Safe events -> local/Sentry aggregates | No raw report persistence | Diagnostics failure no effect | Redaction by construction | allowlist, log scan, raw-error rejection | 1/7; Sentry privacy policy |
| Evidence/intake service | Absent outside repo | Canonical report/evidence/provenance/idempotency authority | Submission -> receipt/evidence | Service durability/backup/retention spec | Exactly-once identity; fail safely | Segregated personal/security data | Contract, load, replay, retention, security | 4; backend/privacy/ops |
| Trust/abuse service | Absent | Priority/correlation/abuse routing only | Evidence/cluster/security signals -> bounded reasons | Server-side, separately restricted | Cannot emit truth command | Privacy-purpose/access limits | trust-priority-only, correlation, rate, abuse | 5/7; policy/ops/legal |
| Moderation service/tool | Absent | Eight-state human decision authority | Evidence/cluster -> decision/proposal | Server audit; role-based | Outage preserves `Received`; no truth | Least privilege; protected notes | state, audit, access, appeal, capacity drills | 5; owner/staff/policy |
| Domain proposal adapters | Current catalog tool is maintainer-local; no Community adapters | Typed one-way proposal to responsible domain | Verified decision -> candidate proposal | Domain-owned audit | Validation failure leaves `Verified` | No raw PII in artifacts | authorization/noninterference/validator | 5; domain owners |
| Catalog publisher | Existing tool/validator/release is correct | Retain Catalog Truth authority; return publication proof | Approved proposal -> validated release | Existing artifacts/audit | Atomic/reversible current workflow | No report/PII in runtime artifact | existing + community-origin proposal tests | 5; catalog owner |
| Search publisher | Current Search is local catalog/code projection; no separate service/revision | Versioned approved content/rule and regression publication | Proposal -> Search/catalog revision | Domain release artifacts | Failure has no runtime change | Privacy-safe regression query | search relevance/collision/parity | 5; Search revision decision |
| Store profile publisher | Absent | Future durable Store profile authority | Approved profile proposal -> versioned profile | Service/domain store | No ID, no publication | Source terms/privacy | identity/merge/move/rollback | Deferred until Store identity |
| Store-evidence publisher | Absent | Future expiring projection authority | Verified cluster -> bounded projection | Versioned cache/distribution | Conflict/expiry/rollback | No reporter/notes/security data | freshness/conflict/no-single-report | Deferred until Store identity/policy |
| Projection repository | No Community projection | Read-only approved Store/provenance cache | Signed/versioned projection -> relevant records | Offline bounded cache; not evidence | Reject invalid/expired; last valid/none | Public-safe metadata only | integrity, expiry, rollback, disabled | 5/7; publisher/distribution |
| Runtime projection adapter | Store future signals score zero | Feed only approved bounded projection to eligible future recommendations | Relevant projection -> typed ranking signal | No raw reports; current heuristic remains | Missing cache = zero Community influence | Explainable reason/source | raw-evidence exclusion, active-session isolation | 8; Store publisher + WT-031B |

### 16.2 Migration and cutover strategy

#### Fresh-data migration

There are no current Community records to transform. The implementation adds an
empty, versioned Community store. It must not scan or convert Product, list,
session, history, `ProductKnowledge`, search behavior, `GeoLocation`, diagnostics,
photos, barcodes, roadmap rows, or catalog feedback logs.

#### Local store migration

The first Community-store version requires:

- store version and integrity metadata;
- stable IDs and immutable envelope hash;
- explicit delivery-state revision;
- attachment manifest version;
- safe startup bootstrap and empty-store creation;
- migration fixture from empty/no-store installation;
- rollback compatibility marker preventing older clients from resending unknown
  acknowledged data.

Future migrations must be idempotent and preserve submission identity,
observation time, payload hash, cancellation, acknowledgement, and attachment
linkage. A migration failure disables Community delivery and preserves/quarantines
recoverable data; it does not block or repair from the main Product store.

#### Compatibility retirement

Until the final cutover:

- `StoreRealityFeedback` remains unused;
- `FutureUserFeedbackSignal` and `FutureCommunityKnowledgeSignal` remain zero;
- no Community UI is publicly reachable;
- runtime does not consume a Community projection.

At final cutover, the later specification either removes the obsolete scaffold or
replaces its call site with a typed approved-projection adapter. There is no
dual-read or dual-write period in which raw/local feedback and published
projection both influence ranking.

#### Rollback

- Intake can be disabled without uninstalling or deleting queued user data.
- A client rollback must retain or safely ignore newer Community-store records
  and must not resend acknowledged/cancelled envelopes.
- Projection rollback restores the prior approved domain revision, not raw
  reports.
- Catalog rollback uses the existing release discipline.
- Removing UI does not silently abandon acknowledged privacy/status obligations;
  Settings/support access or a service route remains as policy requires.

### 16.3 Models and domain types

| File/component | Current responsibility | Planned change | Dependencies | Phase | Tests |
|---|---|---|---|---:|---|
| **Proposed:** `WayTask/CommunityFeedback/Domain/CommunityFeedbackTypes.swift` | Absent | Report taxonomy, target/scope, structured claims, source/provenance-safe types | Phase 0 taxonomy; shared fixture contract | 2 | Round-trip and distinct-type tests |
| **Proposed:** `WayTask/CommunityFeedback/Domain/CommunityDeliveryState.swift` | Absent | Local delivery semantics only; no moderation cases | State Matrix A | 2 | Allowed/denied transition tests |
| **Proposed:** `WayTask/CommunityFeedback/Domain/CommunityModerationState.swift` | Absent | Exactly eight official states and validated service transitions | WT-030C Section 12 | 2 | Matrix B and unknown-state tests |
| **Proposed:** `WayTask/CommunityFeedback/Domain/CommunitySubmission.swift` | Absent | Draft/envelope/receipt/status/publication-link value contracts | Privacy/API/idempotency | 2 | Immutability/hash/version tests |
| `WayTask/Models.swift` | User Product/list/location domain | Retain authority; do not add Community fields or relationships | WT-031A | — | Negative noninterference tests |
| `ProductKnowledge.swift`; `ProductHistory.swift`; `ShoppingSession.swift` | Private knowledge/history/session persistence | Retain; no report/trust/moderation properties | WT-031A/B | — | Negative migration/noninterference |
| `StoreRankingService.swift` `StoreRealityFeedback` | Unused scaffold | Deprecate, then remove/replace only in Phase 8; never migrate | Store projection cutover | 8 | No raw feedback influence |

### 16.4 Persistence and migration

| File/component | Current responsibility | Planned change | Dependencies | Phase | Tests |
|---|---|---|---|---:|---|
| **Proposed:** `WayTask/CommunityFeedback/Persistence/CommunityFeedbackStore.swift` | Absent | Dedicated store bootstrap/repository transaction boundary | Persistence technology/privacy | 2 | Open/create/corrupt/quarantine/in-memory refusal |
| **Proposed:** `WayTask/CommunityFeedback/Persistence/CommunityFeedbackStoreSchema.swift` | Absent | Versioned conceptual draft/outbox/receipt records; exact schema requires specification | Phase 0 fields/retention | 2 | Empty migration, round-trip, idempotent migration |
| **Proposed:** `WayTask/CommunityFeedback/Persistence/FeedbackAttachmentStore.swift` | Absent | Protected sanitized file lifecycle, manifest integrity, cleanup | Media gate | 3/deferred | EXIF, corruption, orphan, limit tests |
| `WayTask/Persistence/WayTaskSchema.swift` | Main Product/Shopping schema V3 | Retain without Community records; avoid migration coupling | WT-031A/B schemas | — | Assert Community types absent from main graph |
| `WayTask/Persistence/WayTaskStartupPersistence.swift` | Main store recovery | Retain main authority. Reuse patterns, not data, in Community bootstrap | Separate-store decision | 2 | Main recovery remains independent |
| `WayTask/WayTaskApp.swift` | Main composition/startup | Construct optional Community dependencies after core startup; start bounded recovery without synchronous network; fail Community only | Store/client/feature policy | 3/4 | Launch with service/store disabled/corrupt |

### 16.5 Repositories, networking, and services

| File/component | Current responsibility | Planned change | Dependencies | Phase | Tests |
|---|---|---|---|---:|---|
| **Proposed:** `WayTask/CommunityFeedback/Application/CommunityFeedbackRepository.swift` | Absent | Draft/queue/receipt command protocol and implementation | Domain/store | 2/3 | Repository contract |
| **Proposed:** `WayTask/CommunityFeedback/Application/CommunityFeedbackContextFactory.swift` | Absent | Per-surface allowlists; snapshots never authority | WT-031A/B types | 2/6 | Privacy/noninterference |
| **Proposed:** `WayTask/CommunityFeedback/Application/CommunityFeedbackOutboxService.swift` | Absent | Queue, lease, retry, cancel, acknowledgement transaction | Repository/API | 3/4 | Races, backoff, relaunch |
| **Proposed:** `WayTask/CommunityFeedback/Networking/CommunityFeedbackAPI.swift` | Absent | Versioned DTO/transport protocol; no domain truth calls | Approved backend | 4 | Mock/contract/fuzz/error |
| **Proposed:** `WayTask/CommunityFeedback/Networking/CommunityFeedbackSubmissionClient.swift` | Absent | Intake/status/withdrawal adapter | API/security/Keychain | 4 | Idempotency/lost ack/auth/rate limit |
| **Proposed:** `WayTask/CommunityFeedback/Application/CommunityProjectionRepository.swift` | Absent | Read-only validated published projection/cache | Store publisher/distribution | 5/8 | Revision/expiry/rollback |
| **Proposed:** `WayTask/CommunityFeedback/Application/CommunityFeedbackFeaturePolicy.swift` | Absent | Signed/approved capability and kill-state evaluation | Ops/config security | 1/4 | Fail-closed/config downgrade |
| `OpenFoodFactsProvider.swift`; `GeminiProductRecognitionService.swift` | Provider/AI Product lookup | Retain; never reuse provider endpoints/keys as Community backend; no automatic report | Scanner scope | — | Boundary tests |
| `ProductKnowledgeService.swift` | Local learning | Retain; explicit context copy only after user chooses report | Privacy | 6 | No implicit upload |
| `WayTask/SentryReportingService.swift` | Allowlisted operational diagnostics | Add enum-backed Community delivery operation/error buckets only after privacy review; never content/tokens | Diagnostic policy | 1/7 | Allowlist/redaction |
| `WayTask/BetaDiagnostics.swift`; `BetaDiagnosticsView.swift` | Developer-only local diagnostics/export | Optional aggregate Community health section only; label distinct from a user report; no body/query/media/ID | Privacy | 7 | Export exclusion |

### 16.6 View models and UI

| File/component | Current responsibility | Planned change | Dependencies | Phase | Tests |
|---|---|---|---|---:|---|
| **Proposed:** `WayTask/CommunityFeedback/Presentation/FeedbackComposerViewModel.swift` | Absent | Draft validation/review/queue; no network/truth direct calls | Repository/copy | 6 | State/error/double-submit |
| **Proposed:** `WayTask/CommunityFeedback/Presentation/FeedbackComposerView.swift` | Absent | Structured accessible review/consent/cancel UI | Scope/localization/privacy | 6 | Dynamic Type/RTL/VoiceOver/manual |
| **Proposed:** `WayTask/CommunityFeedback/Presentation/FeedbackStatusView.swift` | Absent | Queued/failed/receipt/moderation/publication status, retry/cancel/withdraw | Status policy/API | 6 | State copy/offline/unknown |
| **Proposed:** `WayTask/CommunityFeedback/Presentation/CommunityProvenanceView.swift` | Absent | Source/freshness/conflict explanation for approved projections | Provenance contract | 6/8 | Non-color/a11y/localization |
| `WayTask/ProductKnowledge/Presentation/AddProductAutocompleteViewModel.swift` | Search presentation state | Expose reviewed report-context command after explicit user choice; no submission/network in search | Search revision/report scope | 6 | Zero per-keystroke requests |
| `ProductListView.swift` | Product library/add Product UI | Add scoped “Report an issue” entry only when complete lane enabled; keep custom Product action separate | Composer/policy | 6 | Custom save vs report separation |
| `CameraViewModel.swift`; `CameraView.swift` | Scanner recognition/review/local Product save | Add explicit report draft entry after user review; preserve local correction and no implicit photo upload | SKU/media scope | 6/deferred | Scan noninterference/consent |
| `WayTask/ShoppingWorkspaceView.swift` | Shopping/list/session UI | Add optional report entry only after Store lane approved; report command separate from line outcome/Finish | WT-031B/Store identity | 6/deferred | Session byte/semantic isolation |
| `MapBottomSheet.swift`; `WayTask/MainMapView.swift` | Selected Store estimate/actions | Add Store issue entry and source/target disclosure only after durable Store lane; retain estimate copy | Store identity/projection | 6/deferred | Transient-ID rejection/a11y |
| `SettingsView.swift` | Settings/custom Store/notifications | Add Community availability, “Your reports,” privacy/status/deletion route as policy requires | Status store/policy | 6 | Offline/feature-off/privacy |
| `WayTask/AppStateManager.swift`; `ContentView.swift` | Navigation/deep links | Route to draft/status using typed context; no Community state ownership | Entry points | 6 | Stale/deep-link safety |

### 16.7 Catalog, Search, Store, Map, and notifications

| File/component | Current responsibility | Planned change | Dependencies | Phase | Tests |
|---|---|---|---|---:|---|
| `WayTask/ProductCatalog/CatalogProduct.swift`; `ProductCatalogService.swift`; `ProductCatalogValidator.swift` | Catalog contract/load/validation | Retain. Add provenance/revision input only through separately published catalog contract if approved; no raw report fields | Catalog publisher | 5/8 | Existing validator + artifact privacy scan |
| `WayTask/ProductCatalog/ProductCatalogSearch.swift`; `ProductCatalogPersonalization.swift` | Local Search projection | Retain local/no-keystroke-network behavior; consume only published content/rules | Search publication | 5/8 | Strong relevance and Community-origin regression |
| `tools/catalog/*`; shared catalog/review/audit | Catalog authoring/publication | Retain as Catalog Truth gate; later accept reviewed proposal reference without PII; no client automation | Catalog owner | 5 | Existing CLI + authorization/provenance tests |
| `CATALOG_FEEDBACK.md` | Maintainer issue log | Retain; optionally add opaque proposal/publication reference field under separate docs change; never raw Community intake | Publication workflow | 5 | Manual privacy review |
| `MapViewModel.swift`; `StoreSearchService.swift` | Runtime Store/source snapshots | Expose minimal selected Store source snapshot to context factory; do not establish durable identity | Store identity | 6/deferred | Runtime UUID not publication key |
| `StoreRankingService.swift` | Heuristic Store ranking | Phase 8 replace zero placeholder with approved projection adapter only; keep raw evidence types inaccessible | Store evidence publisher | 8/deferred | Bounded/expired/no-raw tests |
| `GeofenceNotificationService.swift` | Estimated Store/list notification and payload | Retain no-report behavior; future deep link may open current context, never submit. Only approved fresh projection may influence future eligibility | WT-031B/projection | 6/8 | Tap-not-evidence; expired suppression |
| `BuyingOptionsService.swift`; `BuyingOptionsSheet.swift` | Store recommendation surface | Future explainability/report entry only after Store lane; no direct evidence query | Projection/identity | 6/deferred | Source label/no raw report |

### 16.8 Project, resources, documentation, and tests

| File/component | Current responsibility | Planned change | Dependencies | Phase | Tests/review |
|---|---|---|---|---:|---|
| `WayTask.xcodeproj/project.pbxproj` | Target/source/package/settings | Add approved source/test/resource membership only; no background/account entitlement without separate approval | Final file set | 2-6 | Project diff audit/build |
| **Proposed:** `WayTask/Resources/Localization/Localizable.xcstrings` or approved existing-project equivalent | No current string catalog | English/Hebrew report types, states, reasons, privacy, errors, provenance | Copy/legal/localization | 6 | Missing-key/pseudo/RTL review |
| **Proposed:** Privacy manifest/Info configuration changes | Current location/Sentry disclosures only | Add only data use/capability approved by privacy review | Legal/platform | 7 | Built privacy report/manual gate |
| **Proposed:** `WayTaskTests/CommunityFeedback/*` | Absent | Domain, persistence, outbox, sync, privacy, projection, UI policy tests | Components | 1-8 | Section 21 matrix |
| `WayTaskTests/ProductCatalog/*`; `tools/catalog/test/*` | Current catalog/search validation | Extend with Community-origin proposal/release fixtures; retain all current regressions | Publisher | 5/7 | AC-042–050 |
| Existing Product/Shopping/Session tests | Current domain regressions | Add noninterference fixtures; do not modify authority to accommodate Community | WT-031A/B | 1/7 | AC-001/007/058/059/089 |
| `docs/75_STORE_RANKING.md`; catalog/search specs; privacy/operations docs | Current architecture/behavior docs | Update only in future authorized implementation to describe actual approved behavior | Final implementation | 8 | Documentation truth review |
| `BETA_BACKLOG.md`; `ROADMAP.md`; changelog | Roadmap/history | Update status only after implementation/release; never use as evidence store | Product process | 8 | Manual traceability |

### 16.9 External components not present in this repository

Separate approved specifications are required for:

- intake/evidence/status/privacy service;
- attachment service and safety processing;
- trust/abuse service;
- moderation tool, RBAC, audit, appeal, and queue operations;
- Catalog proposal bridge;
- Search publication owner/revision;
- durable Store identity/profile service;
- expiring Store-evidence publication/distribution;
- service feature flags, incident response, backup, deletion, and observability;
- future Android client and shared contract fixtures.

The iOS implementation must use mocked contracts until these services are real
and approved. Mocks cannot justify an external report UI or claim submission
success.

---

## 17. Implementation Phases

No phase below is a public mixed-authority release. Internal builds use
unreachable/disabled UI until the complete applicable chain passes Phase 7.

### Phase 0 — Decision and specification gate

**Objective:** turn all launch-affecting policy and service unknowns into one
approved implementation specification.

**Included work:**

- choose first report types/markets/languages and explicitly defer the rest;
- name evidence, moderation, privacy, abuse, and domain publication owners;
- approve backend/API/idempotency/status/withdrawal/capability contracts;
- approve account-free pseudonymous identity and rights handling;
- approve retention, consent, location, note/media, security, rate, trust,
  independence, expiry, appeal, and queue-capacity policies;
- approve Catalog/Search publication and rollback;
- approve durable Store and SKU prerequisites for any such lanes;
- freeze shared iOS/Android type/state/reason fixtures;
- define feature flags, emergency disablement, launch metrics, and rollback.

**Prerequisites:** WT-030 architecture and this plan.
**Migration impact:** none.
**Validation:** architecture/privacy/security/operations/domain-owner sign-off and
traceability to all open questions.
**Exit criteria:** no unresolved decision affects the selected implementation
scope; external services have owned specifications and test environments.
**Rollback boundary:** no code/data/collection exists.

### Phase 1 — Characterization and privacy baseline

**Objective:** lock current noninterference and diagnostic privacy before adding
the domain.

**Included work:**

- characterize zero current Community writes/network/storage/UI;
- add negative authority tests around Product, catalog, search, Store,
  Shopping/Session, notification, diagnostics, and scanner;
- define safe diagnostic enums/allowlists and log-scan tests;
- establish privacy threat model, data inventory, and manual review artifacts;
- preserve current catalog validation report and Store estimate wording.

**Prerequisites:** Phase 0 selected scope and privacy baseline.
**Migration impact:** none.
**Validation:** characterization and privacy tests fail on any hidden intake or
truth writer.
**Exit criteria:** current behavior is executable evidence and log policy is
enforced.
**Rollback boundary:** tests/docs only in the later authorized task; production
behavior unchanged.

### Phase 2 — Evidence identity and local persistence

**Objective:** establish typed local draft/delivery identity without network or
public UI.

**Included work:**

- domain types, official moderation decoder, target snapshots, revisioning;
- dedicated Community store and bootstrap;
- draft/receipt repository;
- stable submission ID, immutable envelope hash, cancellation/tombstone;
- main-store separation and migration/corruption behavior;
- shared platform fixtures.

**Prerequisites:** Phase 1; storage/security/retention specification.
**Migration impact:** create empty versioned Community store only; no legacy-data
conversion.
**Validation:** round trip, migration, 100 relaunches, corruption, main-store
noninterference.
**Exit criteria:** local identity cannot be duplicated or confused with evidence
or truth.
**Rollback boundary:** Community store can be ignored/quarantined; feature
unreachable.

### Phase 3 — Submission commands and offline outbox

**Objective:** make explicit user-authorized payload delivery durable and
idempotent, still disconnected from public service.

**Included work:**

- context allowlists;
- draft review/queue/cancel commands;
- outbox leases, retries, backoff, stale temporal disposition;
- optional attachment pipeline only if approved;
- failure/degraded storage behavior;
- mocked transport contract.

**Prerequisites:** Phase 2; finalized payload/media policy.
**Migration impact:** add only compatible Community-store fields/records through
its migration plan.
**Validation:** double tap, offline/relaunch, cancellation, partial media,
backoff, privacy, and Product/Session isolation.
**Exit criteria:** every queued envelope is immutable, durable, user-authorized,
and safe to retry; outbox has no truth capability.
**Rollback boundary:** stop worker, preserve/delete local drafts under policy;
no server evidence exists.

### Phase 4 — Synchronization and server acknowledgement

**Objective:** integrate one real intake/status/privacy authority.

**Included work:**

- production submission/status/withdrawal client;
- canonical receipt and lost-ack recovery;
- typed validation/rate/service errors;
- capability/kill state;
- bounded foreground/relaunch/status refresh;
- Keychain receipt credentials;
- service contract/security/load tests.

**Prerequisites:** real approved backend, privacy/security review, operations
owner, Phase 3.
**Migration impact:** receipt/status fields; no Product-store change.
**Validation:** idempotent replay, delayed/lost acknowledgement, stale target,
account-free rights, service outage, disablement.
**Exit criteria:** one device envelope produces one service report and truthful
status; no raw report reaches runtime truth.
**Rollback boundary:** intake flag off; preserve acknowledged obligations and
queued user data.

### Phase 5 — Moderation and publication integration boundaries

**Objective:** complete the server-side evidence-to-proposal-to-truth chain.

**Included work:**

- evidence normalization, reversible clusters, conflict, freshness;
- bounded trust/abuse priority;
- eight-state human moderation, audit, appeal/reopen;
- Catalog and Search proposal/publication proof;
- Store lanes only if identity/policy prerequisites exist;
- publication link/status and domain projection distribution;
- rollback/supersession.

**Prerequisites:** named/staffed queues, policies, domain publishers, Phase 4.
**Migration impact:** service-side only plus client read-compatible status/provenance
version.
**Validation:** moderation matrix, no-single-report, trust/AI non-authority,
domain validators, failed publication, rollback.
**Exit criteria:** `Implemented` cannot occur without proof; every launch type
has an owned complete disposition path.
**Rollback boundary:** publication lanes/Community projection disabled; existing
domain truth restored; evidence history retained.

### Phase 6 — UI, transparency, accessibility, and localization

**Objective:** expose only the complete approved lanes with honest UX.

**Included work:**

- contextual entry points;
- pre-submit review and disclosure;
- queue/receipt/moderation/publication status;
- retry/cancel/withdrawal;
- provenance/freshness/conflict presentation;
- English/Hebrew string catalog, RTL, Dynamic Type, VoiceOver, Switch Control,
  hardware keyboard, non-color state.

**Prerequisites:** Phases 4–5 complete for each exposed lane; approved copy/legal
notice.
**Migration impact:** none beyond client status/cache compatibility.
**Validation:** UX state fixtures, no dead/unowned entry, accessibility/localization
manual and automated evidence.
**Exit criteria:** users can distinguish draft/queued/received/verified/applied
and know reporting does not alter current Product/Shopping.
**Rollback boundary:** entry-point flag off; status/privacy access remains as
required.

### Phase 7 — Reliability, abuse, privacy, and release qualification

**Objective:** prove the whole selected capability against WT-030C.

**Included work:**

- full Section 21 matrix, load/performance/battery/storage/corruption drills;
- red-team abuse/brigading/media/authorization;
- privacy rights/retention/deletion/incident exercises;
- moderation capacity/backlog and domain rollback drills;
- iOS/Android shared contract fixtures where backend semantics are shared;
- external localization/accessibility QA;
- feature-disable and prior-version compatibility.

**Prerequisites:** complete integrated candidate.
**Migration impact:** rehearse fresh install, upgrade, downgrade/rollback, store
corruption.
**Validation:** all AC-001–AC-100 evidence accepted by named owners.
**Exit criteria:** no open launch-blocking defect/policy/queue; privacy, security,
operations, accessibility, localization, and domain owners sign off.
**Rollback boundary:** exercised intake/projection disable and domain revision
rollback.

### Phase 8 — Single authority cutover and compatibility retirement

**Objective:** enable one complete authority path and remove misleading
scaffolding.

**Included work:**

- enable only qualified report families/markets;
- confirm one intake/evidence/moderation/publication chain;
- retain existing catalog publisher as truth gate;
- if Store projection is approved, connect ranking only to that published
  adapter;
- remove/deprecate `StoreRealityFeedback` and zero placeholder compatibility at
  the same coherent cutover;
- update documentation/roadmap/changelog after actual release.

**Prerequisites:** Phase 7; approved release decision.
**Migration impact:** no legacy report conversion; projection/cache version
activation only.
**Validation:** production-like smoke, audit/receipt/publication trace, no dual
authority, kill/rollback drill.
**Exit criteria:** no raw/local feedback reader or hidden writer; every visible
status and runtime influence resolves to its owner.
**Rollback boundary:** disable intake/projection, restore prior domain revision,
preserve receipt/privacy obligations; never fall back to raw feedback.

---

## 18. UI and UX Transition Plan

### 18.1 UX goals

The transition must let a user:

- report one understandable issue from the context where it occurred;
- review exactly what will be sent;
- keep local correction/Product creation/Shopping outcomes independent;
- submit or queue without blocking core work;
- distinguish queued, received, reviewing, verified evidence, and applied change;
- recover, retry, cancel unsent work, request withdrawal, and understand failure;
- see when reviewed Community information influences a recommendation;
- use the flow in English/Hebrew, RTL, Dynamic Type, VoiceOver, Switch Control,
  and hardware keyboard.

It does not include a general visual redesign.

### 18.2 Entry-point rules

#### Products and Search

- Offer “Report an issue” only when the complete Product/Search lane is enabled.
- Product-not-found appears alongside, not instead of, explicit custom Product
  creation.
- The report draft shows the reviewed query, result/target, locale, and issue
  choices. No query is uploaded on typing or no-result display.
- Explain: reporting may help WayTask review the catalog; it does not add or
  rename the Product immediately.
- Duplicate, synonym, language, spelling, ranking, category, brand, and
  concept/SKU choices remain distinct.

#### Scanner

- Local correction and “Add Product” remain immediately available.
- A separate report action can prefill only the user-reviewed barcode/candidate
  and allowed source snapshot.
- Photo upload is off unless media is approved; the recognition image is not
  automatically reused.
- AI/provider output is context, not evidence until user review/queue.

#### Shopping

- Session-line actions such as collect, skip, unavailable, Finish, and Abandon
  remain Shopping commands.
- A report action is optional and follows the Shopping action rather than gating
  it.
- The draft includes only the selected Product/Store/observation context, not the
  full list, plan, session, or history.
- Submission never changes the active plan/session and never delays persistence.

#### Map and Store

- Report actions remain hidden until durable Store target/routing is approved.
- The composer displays Store name/source and explains whether the target is a
  provider result or private saved location.
- Current GPS is not required; the selected public Store supplies context.
- Profile problems and Product availability observations use distinct flows.
- “Likely here” and “Availability is estimated” remain unless a stronger
  published source justifies different wording.

#### Notifications

- No notification action submits or pre-confirms a report.
- A tap may deep-link to current Map/Shopping context, where the user explicitly
  starts and reviews a draft.
- Stale notification context is labeled and revalidated.
- Delivery/tap/geofence event is never evidence of presence or Product
  availability.

### 18.3 Composer flow

```text
Choose report type
  -> confirm target and scope
  -> select structured claim
  -> set/confirm observation time where relevant
  -> add optional note/media if approved
  -> review privacy and complete payload
  -> Submit now / Queue for upload
  -> Queued / Sending / Report received / actionable failure
```

The confirmation screen must show:

- report type in plain language;
- Product/Search/Store target and source;
- concept/SKU/unknown scope;
- relevant time, locale, and market;
- full authored note and attachment preview;
- data disclosure and policy link;
- whether offline queueing applies;
- that submission does not immediately change catalog or current Shopping;
- cancel/edit behavior and future status route.

### 18.4 Status UX

| Internal condition | User-facing meaning |
|---|---|
| Draft | Not submitted; editable |
| Pending Upload | Saved on this device and waiting to send |
| Sending | Delivery attempt; no receipt yet |
| Failed retryable | Could not send; original report remains queued; retry timing/action |
| Failed permanent | Cannot submit this version; show safe reason and correction path |
| Received | Report received, not confirmed |
| Under Review | WayTask is reviewing it |
| Needs More Evidence | More information is requested; optional/accessibly actionable |
| Verified | Evidence was reviewed; any domain change is still separate |
| Implemented | Applied in the linked catalog/search/store revision/projection |
| Rejected | Not applied under the stated reason; appeal/correction if allowed |
| Duplicate | Linked to an existing issue/outcome without exposing others |
| Expired | Observation is no longer current/actionable |
| Publication superseded/rolled back | The earlier applied change has since changed; historical report remains |

Raw enum names, provider codes, review notes, abuse signals, reporter counts, and
other-user content are never displayed.

### 18.5 Offline, empty, and degraded states

- Offline Draft/Pending explicitly says it is stored on this device.
- If durable Community storage is unavailable, do not claim a queue; preserve an
  editable in-memory draft only with clear loss warning or disable submission
  under the approved UX.
- If service capability is off, explain that reporting is temporarily
  unavailable while Product/Shopping remain usable.
- An empty “Your reports” view explains that only explicitly submitted issues
  appear; it does not list behavior or diagnostics.
- If local receipt cache is deleted/offline, do not infer server state.
- Unknown/temporarily unavailable status uses safe copy and retry, never
  “rejected” or “fixed.”
- Queue/storage/media limits have clear nonpunitive messages and deletion
  controls.

### 18.6 Cancellation, withdrawal, and deletion UX

- “Delete draft” and “Cancel upload” are local actions for unsent records.
- “Withdraw report/request deletion” is a service/privacy request after receipt
  and shows its own pending/completed result.
- “Remove from this device” does not imply service deletion.
- Explain that an independently validated catalog/store revision may remain even
  after contributor data is removed.
- Confirmation dialogs identify exactly which layer is affected.

### 18.7 Transparency UX

- Show source/freshness only when an approved projection materially affects the
  visible decision.
- Use nontechnical, localized labels and a detail disclosure when helpful.
- Never show public contributor names, leaderboards, raw counts, or “trusted
  user.”
- Conflicted evidence is described as mixed/uncertain.
- Expired evidence has zero runtime influence.
- No Community attribution appears where the decision is solely catalog,
  provider, local personalization, or existing heuristic.

### 18.8 Transition and rollout

- Before Phase 8, production builds expose no unowned/dead report action.
- Internal QA may use compile-time/test injection or authenticated internal
  capability, never a client-editable production flag.
- At cutover, all selected entry points use the same composer/outbox/status
  commands.
- Unsupported report families are absent or clearly unavailable; they are not
  squeezed into “Other.”
- Feature disablement removes new intake consistently but preserves required
  status/privacy access.

---

## 19. Accessibility and Localization

### 19.1 Current baseline and gap

The repository has SwiftUI accessibility labels in selected existing controls
and locale-aware Product autocomplete copy, but no string-catalog resource was
found and Community UI does not exist. Current mixed hard-coded English/Hebrew
copy is not a sufficient localization architecture for the new lifecycle and
privacy vocabulary.

### 19.2 Localization plan

- Create one approved string catalog or the project's approved equivalent for
  English and Hebrew.
- Localize report families/types, target/scope labels, every local/moderation/
  publication status, transition reason, validation error, rate-limit/retry
  message, consent/privacy notice, withdrawal/deletion/appeal action, provenance,
  freshness/conflict, empty/degraded state, and attachment action.
- Stable wire/domain codes are never user-visible.
- Locale and market remain separate; a Hebrew UI may report an English Store or
  Product, and vice versa.
- Do not construct sentences by concatenating fragments or enum raw values.
- Preserve original-script user text with explicit bidirectional isolation for
  Product names, brands, barcodes, URLs, and Store names.
- Search reports preserve the reviewed query's script/locale without automatic
  translation changing evidence.
- Moderator/publication reason codes have reviewed consumer translations
  independent of protected internal notes.

### 19.3 RTL requirements

- Navigation, back/cancel placement, disclosure indicators, selection rows,
  progress/status timelines, attachment order, and swipe actions follow RTL.
- Numeric IDs, barcodes, URLs, dates, versions, and mixed Latin/Hebrew names keep
  semantic order.
- Icons with directional meaning mirror; source/status icons without direction do
  not.
- Target, claim, observation time, privacy notice, and Submit order remain
  logically understandable in Hebrew.

### 19.4 Accessibility requirements

- Every action has visible text or a clear accessibility label/hint.
- Structured options expose role, selected value, error, and required/optional
  state.
- VoiceOver reads target, claim, time/scope, optional evidence, privacy
  consequence, delivery state, and outcome in logical order.
- Status, freshness, trust/conflict, error, and selection never rely on color or
  icon alone.
- Dynamic Type through accessibility sizes does not truncate the target,
  disclosure, Submit/Cancel, retry, or status meaning.
- Switch Control and hardware keyboard focus order are deterministic.
- Attachment preview/remove controls are labeled; photo is never mandatory.
- Any anti-bot challenge has a nonvisual accessible alternative.
- Motion/animation respects Reduce Motion; progress is not conveyed by animation
  alone.
- Touch targets meet platform guidance and error focus moves to the first
  actionable problem.

### 19.5 Verification artifacts

Required named artifacts:

- `CF-L10N-01` — English/Hebrew key and semantic-parity report;
- `CF-RTL-01` — Hebrew RTL mixed-script screenshot set;
- `CF-A11Y-01` — VoiceOver task transcript for every launch report lane;
- `CF-A11Y-02` — Dynamic Type, Switch Control, and keyboard matrix;
- `CF-A11Y-03` — non-color status/provenance audit;
- `CF-COPY-01` — product/legal/localization approval of status, privacy, expiry,
  rejection, and uncertainty copy.

---

## 20. Performance, Reliability, and Diagnostics

### 20.1 Performance boundaries

- Local catalog suggestion latency and behavior remain independent of Community
  network/service availability.
- Typing, result display, custom Product creation, list mutation, plan/session
  execution, Finish, and Abandon produce zero Community network dependency.
- No report upload may block Product persistence, Shopping-list mutation,
  session-line persistence, Finish, or Abandon.
- Opening the app performs no synchronous Community network call before the core
  UI.
- Outbox/status work is batched, bounded, cancellable, and lower priority than
  user Product/Shopping persistence.
- Runtime Store ranking consumes only relevant approved projection records, not
  raw evidence or a full Community corpus.
- Attachment work is explicit, bounded, off the main actor where safe, and
  cancellable.
- Disabled/unavailable Community Feedback performs no polling, media processing,
  or report-store scan during ordinary Product/Shopping interactions beyond a
  constant-time capability check.

Exact launch-time, database-size, attachment-byte, queue-count, request-latency,
and projection-cache budgets must be measured and approved in Phase 0/7 rather
than invented here.

### 20.2 Battery and background behavior

- Foreground/launch/manual retry is the correctness baseline.
- No continuous location, background polling, or keep-alive is introduced.
- A `NWPathMonitor` or equivalent, if used, is a retry hint only and should not
  remain active when there is no eligible work.
- Background `URLSession` is considered only for approved attachment transfer;
  its callbacks remain idempotent and its absence never loses core state.
- No general BackgroundTasks entitlement or schedule is required by this plan.
- Retry respects backoff, server rate limits, low-power/network policy as
  approved, and queue age.
- Projection refresh is bounded and never follows every Map movement or search
  keystroke.

### 20.3 Reliability invariants

- Durable queue write precedes network attempt.
- Receipt write precedes upload retirement/attachment cleanup.
- Same payload/key produces one report across timeout, relaunch, and crash.
- Different payload cannot reuse the same key.
- Cancellation races recheck durable state before send.
- Target and observation time are immutable after queue.
- Status updates are revision-monotonic.
- `Implemented` requires publication proof.
- Projection revision activation is atomic; invalid/partial data is not exposed.
- Expired projection has zero influence.
- Community failure cannot corrupt/block the main Product/Shopping store.
- Recovery never synthesizes claims from current app data.

### 20.4 Corruption and partial-failure handling

| Failure | Required behavior |
|---|---|
| Draft/store write fails | Keep prior state; no upload; visible safe error |
| Queue commit succeeds, worker crashes | Recover same pending ID on relaunch |
| Network commit succeeds, response lost | Retry same key; recover canonical receipt |
| Receipt response arrives, local save fails | Do not create new envelope; retry lookup/submit same key |
| Attachment missing/corrupt | Do not send misleading manifest; offer remove/review/cancel |
| Community store corrupt | Isolate/quarantine; core app opens; no reconstruction |
| Main Product store degraded | Community remains independently gated; no Product-data upload |
| Status response out of order/unknown | Preserve newest known revision; display safe unavailable state |
| Moderation unavailable | Stay `Received`; no truth effect |
| Publication validator fails | Stay `Verified`/domain review; never `Implemented` |
| Projection invalid/expired | Reject/zero influence; use last valid unexpired revision if policy allows |
| Kill switch | Stop intake/work/projection as configured; preserve core and required status/privacy route |

### 20.5 Client diagnostics

**Planned allowlisted events:**

- Community store opened/failed/recovered/quarantined;
- draft saved/deleted count;
- envelope queued/cancelled;
- attempt started/succeeded/retryable/permanent failure;
- acknowledgement recovered after retry;
- status refresh success/failure/unknown-version;
- attachment sanitization/upload category without content;
- feature capability/kill state;
- projection accepted/rejected/expired/rolled back;
- privacy/withdrawal command category without identity/content.

Allowed metadata is enum/reason, app/payload/store-schema version, attempt/latency/
size/count buckets, media-present Boolean, and aggregate totals. Sentry reporting
must pass through explicit allowlists. No arbitrary error localization, URL,
response body, query, target name/ID, receipt, token, coordinate, note, media, or
moderation detail.

### 20.6 Service diagnostics and operations

The backend/operations specification must define privacy-safe metrics for:

- accepted/idempotent/rejected/rate-limited intake;
- queue volume/age by approved nonidentifying dimensions;
- duplicate/conflict/correlation rate;
- moderation turnaround, reversal, appeal, and backlog capacity;
- proposal/validation/publication failure and rollback;
- retention/deletion job completion;
- media safety/quarantine aggregate;
- abuse incident and emergency-disable health;
- projection freshness/distribution.

Quality metrics must not reward raw report volume, expose contributor/Store
harassment targets, or silently create behavioral analytics.

### 20.7 Diagnostic acceptance

- Static/log-capture tests search all client diagnostic outputs for prohibited
  data.
- Raw `Error`, HTTP body/header/query, and request URLs are rejected at the
  diagnostic API boundary.
- Diagnostics can be disabled/unavailable without changing delivery, moderation,
  or truth behavior.
- Beta Diagnostics “report” remains a technical export and is never sent as
  Community Evidence.
- Sentry remains operational diagnostics only; Session Replay, screenshots,
  view hierarchy, network capture, product analytics, and automatic content
  breadcrumbs remain outside the approved boundary.

---

## 21. Testing Strategy

### 21.1 Test layers

The later implementation specification must allocate tests across:

1. **Pure domain tests:** report taxonomy, target/scope, local and moderation
   transitions, immutable envelopes, status/version decoding.
2. **Persistence tests:** draft/outbox/receipt transactions, migration,
   corruption/quarantine, attachment integrity, relaunch, cancellation, cleanup.
3. **Transport contract tests:** idempotency, lost acknowledgement, retry/backoff,
   rate limits, partial media, rejection, status order, withdrawal/deletion.
4. **Service/shared fixtures:** evidence normalization, duplicates/conflicts,
   trust caps, abuse, moderation, RBAC, publication authorization, expiry.
5. **Domain-publication tests:** current catalog validator/release, Search
   regressions, Store identity/evidence projection, rollback.
6. **Authority integration tests:** Product, list, plan, Session, history, Map,
   notification, scanner, AI, and Community noninterference.
7. **UI/accessibility/localization tests:** all states/failures, English/Hebrew,
   RTL, Dynamic Type, VoiceOver, Switch Control, keyboard, non-color status.
8. **Reliability/performance/privacy tests:** offline/relaunch/corruption/load,
   battery/background, storage, feature disablement, log redaction, EXIF,
   rights/retention.
9. **Manual operational artifacts:** moderation capacity, incident/rollback,
   privacy/legal, domain-owner, market/language, accessibility, and cross-platform
   approvals.

### 21.2 Proposed test suites

| Proposed suite/artifact | Coverage |
|---|---|
| `CommunityFeedbackDomainTests` | Report/target/scope types, immutable values, serialization |
| `CommunityDeliveryStateMachineTests` | Draft/queue/attempt/failure/ack/cancel/stale transitions |
| `CommunityModerationStateMachineContractTests` | Exactly eight states, allowed/denied transitions, reasons/revisions |
| `CommunityOutboxPersistenceTests` | Stable IDs, transactions, migration, relaunch, corruption, cleanup |
| `CommunitySubmissionIdempotencyContractTests` | Double taps, retries, lost ack, payload-hash mismatch |
| `CommunityAttachmentPrivacyTests` | EXIF, size/type, partial upload, removal, storage |
| `CommunitySynchronizationTests` | Status monotonicity, stale targets, replacement/deactivation, account/device cases |
| `CommunityDuplicateConflictSharedTests` | Exact/same-actor/equivalent/near duplicate, merge/split, conflict |
| `CommunityTrustAbuseContractTests` | Priority only, dimensions/caps, linked actors, brigading, rate limits |
| `CommunityModerationAuthorizationTests` | Human/default authority, audit, RBAC, appeal/reopen |
| `CommunityPublicationAuthorizationTests` | Proposal/validation/proof, no client/moderator publication, rollback |
| `CommunityCatalogPublicationTests` | Stable IDs, collision/redirect, catalog tool, runtime artifact privacy |
| `CommunitySearchPublicationTests` | Explicit query, regressions, no-keystroke network, relevance |
| `CommunityStoreProjectionTests` | Durable identity, source/freshness/conflict/expiry, bounded runtime use |
| `CommunityTruthNonInterferenceTests` | Product/List/Plan/Session/History/notification/scanner isolation |
| `CommunityPrivacyDiagnosticsTests` | Data minimization, Keychain, redaction, deletion/de-linking, logs |
| `CommunityFeedbackUXTests` | Review/queue/status/failure/degraded/withdrawal and source explanation |
| `CommunityLocalizationAccessibilityTests` | English/Hebrew, RTL, Dynamic Type, VoiceOver, keyboard, non-color |
| `CommunityPerformanceReliabilityTests` | Launch/search latency, 100 relaunches, load/storage/battery/disable |
| `CommunityAndroidParityFixtures` | Platform-neutral types/states/duplicate/trust/expiry/publication semantics |
| `CF-PRIV-01` | Approved data inventory, purpose/lawful basis/access/retention/deletion |
| `CF-OPS-01` | Owners, staffing, backlog capacity, escalation, pause-intake drill |
| `CF-SEC-01` | Threat model, abuse/red-team, RBAC, incident/emergency disable |
| `CF-PUB-01` | Catalog/Search/Store publication and rollback drill |
| `CF-PARITY-01` | iOS/Android shared-fixture attestation |
| `CF-REL-01` | Full release, downgrade, feature-disable, service-outage exercise |

### 21.3 Required scenario matrix

At minimum, executable tests cover:

- every positive and negative local/evidence/moderation transition;
- submission identity, double tap, exact retry, duplicate acknowledgement, and
  different-payload key rejection;
- offline queue, network loss, airplane mode, poor connectivity, relaunch,
  process termination, attempt-lease recovery, and recovered connectivity;
- retry limits/backoff/`Retry-After`, rate limit, service unavailability, and
  permanent payload rejection;
- draft edit, queued cancellation, withdrawal, local deletion, privacy deletion,
  account deletion, and future multi-device linking;
- missing/replaced/deactivated Catalog Product, stale Search revision,
  disappeared/merged Store target, and transient Store identity rejection;
- attachment removal, EXIF stripping, type/size rejection, partial upload,
  orphan cleanup, corrupt file, and storage limits;
- semantic duplicate, reversible merge/split, conflicting evidence, same-actor
  and coordinated reports;
- trust-prioritization-only, maximum reputation, AI-assistance-only, human
  moderation, RBAC, appeal/reversal, and audit;
- publication authorization, failed validator, no-client publication, rollback,
  supersession, and runtime artifact privacy;
- Product/List/Plan/Session/History byte/semantic noninterference;
- no notification from raw report and no report from notification tap;
- Store projection source, freshness, expiry, conflict, and bounded consumption;
- corrupted Community store and main-store independence;
- feature/report-family/media/projection disable and safe degradation;
- no network per search keystroke and no blocking Product/Shopping command;
- English, Hebrew, RTL, mixed scripts, Dynamic Type, VoiceOver, Switch Control,
  keyboard, non-color state, and photo-optional paths.

### 21.4 WT-030C acceptance-criterion traceability

Every approved criterion maps to a planned executable suite or a named manual
review artifact. Service/shared tests are required deliverables even though the
service is not in the current iOS repository.

| AC | Planned executable evidence or named artifact |
|---:|---|
| AC-001 | `CommunityTruthNonInterferenceTests.reportIntakeWritesNoTruthDomain` |
| AC-002 | `CommunityModerationAuthorizationTests.verifiedRequiresHumanDecision` |
| AC-003 | `CommunityPublicationAuthorizationTests.implementedRequiresPublishedProof` |
| AC-004 | `CommunityPublicationAuthorizationTests.verifiedAloneHasNoRuntimeEffect` |
| AC-005 | `CommunityTrustAbuseContractTests.singleReportCannotPublish` |
| AC-006 | `CommunityDuplicateConflictSharedTests.sameActorHundredRepeatsCountOnce` |
| AC-007 | `CommunityTruthNonInterferenceTests.allUserAndSessionRecordsRemainUnchanged` |
| AC-008 | `CommunityCatalogPublicationTests.deactivationPreservesUserUUIDAndSnapshot` |
| AC-009 | `CommunityFeedbackDomainTests.acceptedReportHasExactlyOneType` |
| AC-010 | `CommunityFeedbackDomainTests.missingProductSubtypeRoundTripsRemainDistinct` |
| AC-011 | `CommunityFeedbackDomainTests.searchIssueTypesRemainDistinct` |
| AC-012 | `CommunityFeedbackDomainTests.storeIssueTypesRemainDistinct` |
| AC-013 | `CommunityFeedbackDomainTests.searchReportRequiresQueryTargetLocaleRevisions` |
| AC-014 | `CommunityFeedbackDomainTests.observationAndUploadTimesRemainDistinct` |
| AC-015 | `CommunityFeedbackDomainTests.productScopeIsExplicitOrUnresolved` |
| AC-016 | `CommunityStoreProjectionTests.runtimeUUIDCannotPublishStoreProjection` |
| AC-017 | `CommunityFeedbackUXTests.preSubmitReviewShowsCompleteContextAndDelivery` |
| AC-018 | `CommunityModerationStateMachineContractTests.exactOfficialStateSet` |
| AC-019 | `CommunityModerationStateMachineContractTests.allAllowedTransitionsPass` |
| AC-020 | `CommunityModerationStateMachineContractTests.allUnlistedTransitionsAreAtomicFailures` |
| AC-021 | `CommunityModerationAuthorizationTests.transitionsRecordReasonTimePolicy` |
| AC-022 | `CommunityFeedbackUXTests.receivedCopyNeverClaimsVerificationOrFix` |
| AC-023 | `CommunityPublicationAuthorizationTests.implementedResolvesExactRevision` |
| AC-024 | `CommunityPublicationAuthorizationTests.supersessionPreservesHistory` |
| AC-025 | `CommunitySubmissionIdempotencyContractTests.hundredRetriesYieldOneReport` |
| AC-026 | `CommunitySubmissionIdempotencyContractTests.lostAckReturnsOriginalReceiptAndState` |
| AC-027 | `CommunityDuplicateConflictSharedTests.sameActorDoesNotIncreaseIndependence` |
| AC-028 | `CommunityDuplicateConflictSharedTests.scopeDifferencesBlockAutomaticMerge` |
| AC-029 | `CommunityDuplicateConflictSharedTests.mergePreservesReceiptsSourcesTimesDispositions` |
| AC-030 | `CommunityDuplicateConflictSharedTests.clusterSplitPreservesProvenance` |
| AC-031 | `CommunityDuplicateConflictSharedTests.contradictionsRemainConflict` |
| AC-032 | `CommunityTrustAbuseContractTests.conflictCannotPublishOrIncreaseCategoricalClaim` |
| AC-033 | `CommunityTrustAbuseContractTests.outputHasPriorityReasonsAndNoMutationCommand` |
| AC-034 | `CommunityTrustAbuseContractTests.allApprovedTrustDimensionsHaveFixtures` |
| AC-035 | `CommunityTrustAbuseContractTests.maximumTrustStillRequiresHumanAndPublisher` |
| AC-036 | `CommunityTrustAbuseContractTests.linkedDevicesCannotSelfCorroborate` |
| AC-037 | `CommunityTrustAbuseContractTests.coordinatedCampaignIsDiscounted` |
| AC-038 | `CommunityModerationAuthorizationTests.reversalCorrectsTrustWithoutDeletingAudit` |
| AC-039 | `CommunitySubmissionIdempotencyContractTests.rateLimitIsRecoverableAndDuplicateSafe` |
| AC-040 | `CF-A11Y-02` accessible anti-bot alternative review and test |
| AC-041 | `CommunityModerationAuthorizationTests.moderatorAuditSeparateFromReputation` |
| AC-042 | `CommunityCatalogPublicationTests.communityProposalRunsWholeCatalogValidator` plus current CLI suite |
| AC-043 | `CommunityCatalogPublicationTests.acceptedIssueRequiresRegressionFixture` |
| AC-044 | `CommunityCatalogPublicationTests.newConceptUsesNewStableID` |
| AC-045 | `CommunityCatalogPublicationTests.aliasPassesIdentityAndCollisionValidators` |
| AC-046 | `CommunityCatalogPublicationTests.mergeRedirectAndSplitReferenceSafety` |
| AC-047 | `CommunityCatalogPublicationTests.barcodeCannotPublishToConceptWithoutSKUAuthority` |
| AC-048 | `CommunityCatalogPublicationTests.runtimeArtifactContainsNoRawOrPrivateEvidence` |
| AC-049 | `CommunitySearchPublicationTests.onlyExplicitActionSubmitsQuery` |
| AC-050 | `CommunitySearchPublicationTests.personalizationRemainsBelowStrongerText` |
| AC-051 | `CommunityStoreProjectionTests.profileCorrectionRequiresDurableIdentityAndRevision` |
| AC-052 | `CommunityStoreProjectionTests.temporaryEvidenceHasExpiryAndZeroPostExpiryEffect` |
| AC-053 | `CommunitySynchronizationTests.uploadDelayPreservesObservationTime` |
| AC-054 | `CommunityStoreProjectionTests.oneNotFoundNeverProducesCategoricalCopy` |
| AC-055 | `CommunityStoreProjectionTests.foundAndNotFoundYieldConflictNotLastWriteWins` |
| AC-056 | `CommunityStoreProjectionTests.sourceClassesRemainAttributable` |
| AC-057 | `CommunityFeedbackUXTests.storeAvailabilityRemainsEstimatedWithoutCompetentSource` |
| AC-058 | `CommunityTruthNonInterferenceTests.reportDoesNotChangeSessionLineOutcome` |
| AC-059 | `CommunityTruthNonInterferenceTests.projectionDoesNotRewriteActiveSnapshot` |
| AC-060 | `CommunityTruthNonInterferenceTests.rawReportCannotScheduleNotification` |
| AC-061 | `CommunityPerformanceReliabilityTests.coreWorksWithCommunityUnavailable` |
| AC-062 | `CommunityOutboxPersistenceTests.pendingSurvivesHundredColdLaunches` |
| AC-063 | `CommunityOutboxPersistenceTests.cancelledUnsentNeverUploadsAfterReconnect` |
| AC-064 | `CommunityOutboxPersistenceTests.pendingExpiredObservationIsNotSilentlySent` |
| AC-065 | `CommunitySubmissionIdempotencyContractTests.accountFreeAndMultiDeviceCanonicalReceipt` |
| AC-066 | `CommunitySynchronizationTests.statusSyncUploadsNoProductShoppingOrRouteData` |
| AC-067 | `CommunityStoreProjectionTests.cacheLossAffectsProjectionOnly` |
| AC-068 | `CommunityPublicationAuthorizationTests.rollbackRestoresProjectionNotReportHistory` |
| AC-069 | `CommunityPrivacyDiagnosticsTests.accountFreeSubmissionContract` |
| AC-070 | `CommunityPrivacyDiagnosticsTests.prohibitedPersonalInputsAreNotRequired` |
| AC-071 | `CommunityFeedbackUXTests.storeReportWorksWithoutLocationPermission` |
| AC-072 | `CommunityFeedbackUXTests.reviewShowsAllAuthoredTextAndMedia` |
| AC-073 | `CommunityAttachmentPrivacyTests.exifLocationIsRemoved` |
| AC-074 | `CommunityAttachmentPrivacyTests.optionalMediaRemovalPreservesStructuredReport` |
| AC-075 | `CF-PRIV-01` approved purpose/lawful-basis/access/retention/deletion inventory |
| AC-076 | `CommunityPrivacyDiagnosticsTests.identityAndSecuritySignalsNeverReachPublicUI` |
| AC-077 | `CF-PRIV-01` rights-workflow test evidence and legal applicability matrix |
| AC-078 | `CommunityPrivacyDiagnosticsTests.deletionDelinksWithoutDeletingIndependentTruth` |
| AC-079 | `CommunityPrivacyDiagnosticsTests.rawEvidenceHasNoAITrainingPath` |
| AC-080 | `CommunityModerationAuthorizationTests.leastPrivilegeRoleMatrix` plus `CF-SEC-01` |
| AC-081 | `CF-L10N-01` English/Hebrew coverage report |
| AC-082 | `CommunityLocalizationAccessibilityTests.noRawCodesInConsumerUI` |
| AC-083 | `CF-RTL-01` mixed-script semantic-order screenshots |
| AC-084 | `CF-A11Y-01` VoiceOver task transcripts |
| AC-085 | `CF-A11Y-02` Dynamic Type, Switch Control, and keyboard matrix |
| AC-086 | `CF-A11Y-03` non-color status/trust/freshness audit |
| AC-087 | `CommunityFeedbackUXTests.allReportTypesHavePhotoFreePath` |
| AC-088 | `CommunityPerformanceReliabilityTests.zeroNetworkPerSearchKeystroke` |
| AC-089 | `CommunityTruthNonInterferenceTests.uploadNeverBlocksCorePersistenceCommands` |
| AC-090 | `CommunityStoreProjectionTests.rankingConsumesBoundedProjectionNotRawCorpus` |
| AC-091 | `CommunityPerformanceReliabilityTests.disabledModeHasNoPollingOrMediaWork` |
| AC-092 | `CommunityAndroidParityFixtures` plus `CF-PARITY-01` |
| AC-093 | `CommunityAndroidParityFixtures.catalogReleaseAndStableIDSemanticsMatch` |
| AC-094 | `CommunityTrustAbuseContractTests.aiRequiresUserReviewAndCannotModeratePublish` |
| AC-095 | `CF-OPS-01` named queue/domain-owner registry |
| AC-096 | `CF-OPS-01`, `CF-SEC-01`, `CF-PRIV-01`, and `CF-PUB-01` policy/drill approvals |
| AC-097 | `CF-OPS-01` demonstrated capacity and intake-pause exercise |
| AC-098 | `CF-PUB-01` durable Store identity/provider routing approval |
| AC-099 | `CF-PUB-01` SKU/barcode authority approval |
| AC-100 | `CF-PRIV-01` legal/privacy launch approval |

### 21.5 Migration, corruption, and rollback tests

- Fresh install with no Community store.
- Upgrade through every Community-store version.
- Interrupted migration before/after metadata/envelope/receipt commit.
- Idempotent re-entry.
- Corrupt metadata, envelope, payload hash, status revision, attachment manifest,
  missing file, and orphan file.
- Community store failure with healthy Product store and vice versa.
- Quarantine with prohibited-content diagnostic scan.
- App downgrade/older decoder with pending, acknowledged, unknown-state, and
  cancelled records.
- Feature disable during Draft, Pending, in-flight, acknowledged, status refresh,
  and projection activation.
- Domain publication rollback while reports remain available.
- Catalog replacement/deactivation with stable user Product UUID/snapshot.

### 21.6 Performance and reliability tests

- Large but policy-bounded draft/outbox/receipt sets.
- Maximum approved attachment count/bytes and partial transfers.
- Launch/foreground latency with empty, pending, failed, and acknowledged queues.
- Search latency comparison with Community enabled/disabled/offline.
- CPU/memory/storage/energy metrics for retry and projection refresh.
- One hundred cold launches and repeated process termination.
- Network timeout, connection loss, poor connectivity, airplane mode, service
  overload, rate limit, and recovered connectivity.
- Concurrent UI/manual/foreground/background triggers with one durable lease.
- No work when feature disabled or queue empty.

### 21.7 Execution and release gates

Required before external release:

- all new iOS unit/integration/UI suites;
- all existing Product, persistence, catalog, Product Knowledge, Map, Shopping,
  Sentry, and feature tests;
- catalog CLI validation and `node --test tools/catalog/test/*.test.js`;
- generic unsigned iOS build;
- Swift concurrency/data-race diagnostics appropriate to the implementation;
- privacy log/artifact scan;
- service contract/security/load suites;
- manual artifacts named above;
- successful intake disable, projection rollback, domain rollback, and restore
  drills;
- `git diff --check` and repository change-scope audit.

No criterion may be marked passed by a design statement alone when an executable
test is possible.

---

## 22. Risks and Mitigations

| Risk | Verified/planned cause | Consequence | Required mitigation / gate |
|---|---|---|---|
| Isolated report button | No current destination or operations path | False user promise and unowned data | No public entry before end-to-end lane passes Phase 7 |
| Community becomes truth | Convenient direct client/moderator/catalog/Store write | Identity, quality, and trust failure | Separate services/permissions/types; negative authorization tests |
| One report/volume/reputation authority | Counts mistaken for independence | Spam/brigading changes truth | Human moderation, domain publication, trust priority only |
| AI authority | Classification/summaries wired to state transitions | Opaque false verification/publication | AI has no authorization command; deterministic contract tests |
| User behavior becomes evidence | Search/no-result/visit/tap/outcome reused silently | Privacy breach and invalid consent | Explicit reviewed submission is the only intake; telemetry tests |
| Product/Shopping mutation | Report flow reuses local correction/session commands | Lost intent or falsified history | Separate commands/repositories and byte/semantic noninterference tests |
| Duplicate upload | Retry/ack race/process death | Inflated evidence and user confusion | Stable ID/key, immutable hash, canonical receipt, durable lease |
| Lost report | Queue not durable or cleanup before receipt save | Broken trust/rights | Persist before send; receipt before retirement; 100-relaunch tests |
| Mixed authority rollout | Scaffold/raw signal and published projection both score | Unexplainable ranking | Zero scaffold until one Phase 8 cutover; no dual reader |
| Runtime Store ID treated as global | Derived/local UUID sent as truth key | Wrong branch/profile/evidence | Block Store publication until durable identity/provider contract |
| SKU/barcode corrupts concept | Variant/package/scan forced into Global Product Concept | Duplicate/incorrect canonical identity | Distinct taxonomy; block publication until SKU authority |
| Catalog validator bypass | Proposal directly edits artifact | Collision, broken ID, unstable release | Existing tool/validator/version/audit/regressions remain mandatory |
| Search privacy leakage | Raw queries collected on every keystroke/no result | Sensitive behavioral dataset | Explicit report only; zero per-keystroke network test |
| Store evidence becomes inventory | Freshness/conflict ignored | Misleading plan/notification | Expiring scoped projection, source/conflict disclosure, no categorical copy |
| Active Session rewritten | New projection refreshes frozen execution state | WT-030B violation | Active snapshot isolation and explicit future revision command only |
| Notification becomes evidence | Tap/geofence/delivery treated as confirmation | False presence/report | Deep link only; explicit current-context review |
| Attachment privacy/safety | Original EXIF/people/payment data uploaded | Personal-data/security incident | Media deferred until sanitize/preview/safety/access/retention complete |
| Free-text PII | Unbounded notes/logs/moderator visibility | Privacy/abuse exposure | Optional bounded structured-first input; warning, access, redaction |
| Account-free called anonymous | Receipt/security linkage remains possible | Misleading privacy claim | Use pseudonymous/account-free wording unless anonymity demonstrated |
| Over-retention | No class-specific schedule | Legal/privacy exposure | `CF-PRIV-01` pre-collection gate and deletion jobs |
| Under-retention | Audit/appeal/proof deleted prematurely | No accountability or rights handling | Purpose-based separate audit/publication retention |
| Corrupt shared store | Community models coupled to Product/Shopping | Core-data loss or claim reconstruction | Dedicated Community store/recovery, main-store independence |
| Client secret/token leak | Receipt/auth in logs/storage/URLs | Account/report takeover | Keychain, typed redacted diagnostics, no request capture |
| Status regression | Out-of-order/unknown service response | False user outcome | Monotonic revision, transition validation, safe unknown |
| Partial media proof | Report committed while evidence silently missing | Moderator/user misled | Manifest commit protocol and user-confirmed structure-only fallback |
| Moderator access/misuse | Broad role/data visibility | Privacy and truth abuse | Least privilege, separate publish role, audited access, review |
| Moderation overload | Launch volume exceeds staffing | Unbounded `Received` backlog | Named capacity, queue threshold, report-family intake pause |
| Coordinated Store attack | Brigading/merchant targeting | Business harm/defamation risk | Correlation, high-impact review, appeal, incident/rollback, rate limit |
| Backend assumption | iOS built against mocks with no service | Dead/unsafe feature | Real approved contract/environment/owner before Phase 4 exit |
| Projection tampering/staleness | Dynamic cache lacks integrity/expiry | Bad runtime recommendation | Version/integrity validation, expiry, rollback, fail to zero |
| Feature-flag bypass | Client-editable/local flag | Unreviewed collection/publication | Approved fail-closed config and server authorization |
| Diagnostics purpose creep | Beta/Sentry “report” reused | Hidden evidence/analytics | Separate APIs and static prohibited-data scans |
| Localization ambiguity | Raw states/concatenated copy/mixed script | Misleading or inaccessible status | String catalog, semantic parity, RTL/a11y artifacts |
| Cross-platform divergence | iOS-only states/IDs/expiry | Different truth/duplicates | Shared fixtures, platform-neutral codes, Android attestation |
| Rollback loses obligations | UI/service disabled after reports accepted | No status/privacy route | Preserve receipt/rights access and audit under rollback plan |
| Test-only authority | Client assertions but server role can still publish | Security gap | Server authorization and domain proof tests, not UI tests alone |

---

## 23. Dependencies

### 23.1 Controlling documents

- `docs/Audits/1.0.3/WT-030C_CommunityFeedbackAudit.md` — binding
  Moderated Evidence-to-Truth architecture, taxonomy, states, acceptance criteria,
  open questions, and launch gates.
- `docs/Audits/1.0.3/WT-030_ArchitectureSummary.md` — combined authority,
  offline, privacy, explainability, platform, AI, and implementation-order
  constraints.
- `docs/Audits/1.0.3/WT-030A_ProductStateUXAudit.md` and
  `docs/ImplementationPlans/1.0.3/WT-031A_ProductStateImplementationPlan.md` —
  stable user Product/list/plan/session/history/catalog reference boundaries.
- `docs/Audits/1.0.3/WT-030B_ShoppingSessionBackgroundAudit.md` and
  `docs/ImplementationPlans/1.0.3/WT-031B_ShoppingSessionImplementationPlan.md`
  — active snapshot, recovery, background, notification, and offline
  noninterference.
- `design/v1.0/WayTask_Product_Specification_v1.0.pdf` — available Product
  Specification baseline.

### 23.2 Repository dependencies

- final WT-031A Product/list/catalog snapshot command contracts;
- final WT-031B Session snapshot/revision/notification validation contracts;
- SwiftData or approved local persistence capability for a separate versioned
  Community store;
- Keychain for opaque receipt/status/withdrawal credentials;
- current catalog/taxonomy schema, stable IDs, validator, CLI, review/audit,
  regression, and release workflow;
- `ProductCatalogSearch` revision/reproduction decision;
- MapKit/provider source fields and terms;
- existing Store ranking estimate/provenance call sites;
- existing Sentry privacy allowlist and Beta Diagnostics separation;
- approved localization resource approach and project membership;
- existing unit-test target plus any approved UI/shared-contract test target.

### 23.3 External prerequisites

- Community intake/evidence/status/privacy backend;
- operations-owned feature/capability configuration;
- moderation staffing/tool/RBAC/audit/appeal/incident response;
- trust, independence, rate-limit, expiry, abuse, and media policy/services;
- privacy/legal/security review and data-subject request operations;
- Catalog and Search proposal/publication owners;
- dynamic projection distribution/integrity/rollback if used;
- durable Store identity/provider routing for Store lanes;
- SKU/identifier authority for variant/package/barcode publication;
- future Android shared-fixture runner;
- AI policy/service only if an assistive scope is later approved.

### 23.4 Dependency order

```text
WT-031A authority cutover
  -> WT-031B session authority cutover
  -> WT-031C Phase 0 policy/service gate
  -> local evidence identity/outbox
  -> canonical intake/status
  -> moderation and domain publication
  -> complete UI and qualification
  -> one Community authority cutover
```

Product/Search-only reporting may not use missing Store/SKU prerequisites as a
reason to weaken the pipeline. Instead, Phase 0 narrows the first report taxonomy
to lanes with complete owners.

---

## 24. Deferred Work

The following is intentionally excluded from the first implementation unless
Phase 0 explicitly includes it and resolves every applicable gate:

- SKU, variant, package, and barcode truth/publication;
- durable cross-platform Store registry, provider contracts, Store merge/move,
  and global Store profile publication;
- Store/Product found/not-found/assortment influence and expiring runtime
  projection;
- attachments/media upload;
- AI-prepared drafts, AI moderation assistance, and AI evaluation/training;
- authenticated accounts, account linking, public contributor profiles, and
  multi-device draft/status sync;
- push/email report-status notifications and a cross-device notification
  authority;
- Android client implementation, while shared contract fixtures are required now;
- provider/merchant submission portals and verified merchant authority;
- general Cloud Sync and dynamic catalog distribution/signing;
- public aggregate Community displays, contributor counts, reputation, badges,
  leaderboards, or voting;
- privacy-safe aggregate no-result analytics, which is separate from explicit
  reports and requires its own approval;
- a general moderator tool vendor/topology beyond the required service boundary;
- calendar/background scheduling for feedback;
- automatic Community-driven plan/session refresh;
- live inventory, guaranteed availability, or retail-provider integrations;
- broad Product/Search/Map/Shopping visual redesign;
- conversion of `CATALOG_FEEDBACK.md` into a user-report database;
- conversion of existing diagnostics, Product Knowledge, behavior, or historical
  records into evidence.

The selected first release may defer report families, but it may not defer
idempotency, receipt/status truth, moderation, privacy, abuse control, domain
publication, rollback, accessibility, localization, or operations for any family
it exposes.

---

## 25. Open Questions

### 25.1 Classification

All unresolved questions from WT-030C remain open unless the approved architecture
already fixed the invariant. This plan does not invent answers.

- **S0:** must be resolved in the implementation specification before production
  coding for the affected scope.
- **COL:** must be resolved before any external data collection.
- **PUB:** must be resolved before the affected domain can publish or influence
  runtime behavior.
- **REL:** must be resolved before external release.
- **DEF:** may remain deferred only while the affected capability remains absent.

### 25.2 Launch product scope

| ID | Class | Unresolved question |
|---:|---|---|
| OQ-001 | S0 | Which report types are included in the first Community release? |
| OQ-002 | S0 | Do Product/Search lanes launch before Store lanes? |
| OQ-003 | S0/PUB | Is “Found here” included initially, only negative quality reports, or neither? |
| OQ-004 | S0 | Can a user report outside an active Shopping context? |
| OQ-005 | S0/REL | Does status show only personal reports or privacy-safe aggregate context? |
| OQ-006 | REL | What response expectation is communicated without an unsustainable SLA? |
| OQ-007 | S0 | Which rejection and expiry reason categories are user-visible? |
| OQ-008 | S0 | Which report types/impacts support appeal? |
| OQ-009 | DEF/REL | Are status changes in-app only, local notification, email, or future account activity? |
| OQ-010 | S0 | How are contributions acknowledged without competition/reputation pressure? |

### 25.3 Product, SKU, barcode, and catalog

| ID | Class | Unresolved question |
|---:|---|---|
| OQ-011 | PUB/DEF | When and by whom will SKU/variant/package/identifier authority be approved? |
| OQ-012 | PUB/DEF | Which barcode sources count as independently verified per market? |
| OQ-013 | PUB/DEF | How can an accepted custom Product be offered a canonical link without rewriting Product Truth? |
| OQ-014 | S0/PUB | Who owns Global Product Concept identity, merge, split, and redirect review? |
| OQ-015 | S0/PUB | Who owns taxonomy, cross-platform icon, and localization approval? |
| OQ-016 | PUB/DEF | Can catalog releases be distributed outside an app binary, and through what integrity/rollback contract? |
| OQ-017 | S0 | How may `CATALOG_FEEDBACK.md` reference Community cluster/publication IDs without personal data? |
| OQ-018 | S0/PUB | What evidence distinguishes a new generic concept from a regional synonym? |
| OQ-019 | REL | How will coverage and review avoid bias against minority languages, local Products, accessibility needs, and small markets? |

### 25.4 Search and localization

| ID | Class | Unresolved question |
|---:|---|---|
| OQ-020 | S0/PUB | Who adjudicates regional synonym conflicts? |
| OQ-021 | S0/PUB | What evidence justifies a normalization/misspelling rule rather than a keyword? |
| OQ-022 | S0 | What Search revision identifier is stored and what portion is user-visible? |
| OQ-023 | S0 | How are wrong-language catalog content and UI-localization defects routed separately? |
| OQ-024 | DEF/COL | Will privacy-safe aggregate no-result analytics ever be collected separately, under what purpose/notice/basis? |
| OQ-025 | REL | How are ranking fairness and bias reviewed across English, Hebrew, and future languages? |

### 25.5 Store identity and evidence

| ID | Class | Unresolved question |
|---:|---|---|
| OQ-026 | PUB/DEF | What is the durable cross-platform Store identity contract? |
| OQ-027 | COL/PUB | Which MapKit/provider identifiers and fields may be stored, processed, and redistributed? |
| OQ-028 | PUB/DEF | How are provider Store merges, moves, franchises, kiosks, and duplicates represented? |
| OQ-029 | PUB/DEF | Who verifies merchants and which facts may they assert? |
| OQ-030 | COL/PUB | What appeal path exists for affected Stores/merchants? |
| OQ-031 | PUB | What evidence distinguishes temporary from permanent closure? |
| OQ-032 | PUB | What evidence distinguishes temporary stock absence from assortment change? |
| OQ-033 | S0/PUB | What expiry/decay windows apply by claim/Product/market? |
| OQ-034 | COL | May expired evidence be retained for historical evaluation, for how long and under what purpose? |
| OQ-035 | PUB | How are provider, merchant, and fresh reviewed Community conflicts presented/resolved? |
| OQ-036 | PUB | How are holidays, special hours, seasonal Stores, and exceptions represented? |
| OQ-037 | S0/PUB | Who owns correction routing to MapKit or other providers? |

### 25.6 Trust, moderation, and anti-abuse

| ID | Class | Unresolved question |
|---:|---|---|
| OQ-038 | S0 | What are trust dimensions' weights, caps, decay, and review-priority bands? |
| OQ-039 | S0 | What qualifies as an independent source/reporter by context? |
| OQ-040 | COL | Which device/account/network correlation signals are lawful, necessary, and retained? |
| OQ-041 | S0/PUB | What confirmation/reviewer policy applies to each impact class? |
| OQ-042 | S0/PUB | Which decisions require two reviewers or escalation? |
| OQ-043 | COL | Who staffs every language/market/domain queue? |
| OQ-044 | REL | What review and appeal service levels are sustainable? |
| OQ-045 | REL | How are moderator consistency, reversal, bias, and conflicts of interest audited? |
| OQ-046 | S0/COL | What rate limits apply by account mode, report type, media, and impact? |
| OQ-047 | S0/REL | Which anti-bot method is accessible and privacy proportionate? |
| OQ-048 | S0 | When does suspicious activity cause temporary suppression, evidence quarantine, or rejection? |
| OQ-049 | COL/REL | What escalation handles brigading, coordinated manipulation, and merchant targeting? |
| OQ-050 | S0 | Is there an urgent correction channel, and how does it preserve review/publication gates? |

### 25.7 Privacy, legal, and retention

| ID | Class | Unresolved question |
|---:|---|---|
| OQ-051 | COL | Who is controller, processor, or joint controller for each service? |
| OQ-052 | COL | What purpose/lawful basis applies to intake, status, moderation, trust, abuse, media, and measurement? |
| OQ-053 | COL | Which countries, markets, languages, and age groups launch? |
| OQ-054 | COL | Is account-free participation pseudonymous, and can any supported mode truly be anonymous? |
| OQ-055 | S0/COL | What receipt/contributor identifier is necessary, rotated, linked, and stored where? |
| OQ-056 | COL | What exact retention, backup, expiry, and deletion period applies to every data class? |
| OQ-057 | COL/DEF | Which media types and safety/privacy screening are permitted? |
| OQ-058 | COL | Is a DPIA or equivalent assessment required? |
| OQ-059 | COL | What residency, international-transfer, processor, and security safeguards apply? |
| OQ-060 | S0/COL | How are account-free access/deletion rights verified without excess identity? |
| OQ-061 | COL | What audit may remain after erasure and how is contributor linkage removed? |
| OQ-062 | COL | Which Store/business, defamation, consumer-protection, and intermediary rules apply per market? |
| OQ-063 | COL/DEF | May de-identified evidence be retained for quality research, and how is anonymization demonstrated? |

### 25.8 Cloud and multi-device

| ID | Class | Unresolved question |
|---:|---|---|
| OQ-064 | DEF | Is an account always optional or only for the initial phase? |
| OQ-065 | DEF/COL | How are account-free receipts linked to a later account with explicit intent? |
| OQ-066 | S0/DEF | How are one person's devices discounted from independence? |
| OQ-067 | DEF/COL | Which draft/report/status content syncs and which remains local? |
| OQ-068 | COL/DEF | What happens to under-review/implemented reports on account deletion? |
| OQ-069 | PUB/DEF | What publication distribution, integrity/signing, cache, expiry, and rollback is approved? |
| OQ-070 | DEF | What Cloud conflict policy applies to status, attachments, withdrawal, and appeal? |
| OQ-071 | DEF | Which device/service owns report-status notifications? |

### 25.9 AI

| ID | Class | Unresolved question |
|---:|---|---|
| OQ-072 | DEF/S0 | Which AI classification, summary, clustering, or safety tasks are allowed? |
| OQ-073 | DEF | How are AI confidence/reasons shown to moderators? |
| OQ-074 | DEF | How are omissions and conflicting evidence detected in AI summaries? |
| OQ-075 | COL/DEF | May raw reports/media be used for any model training/evaluation, under what separate choice? |
| OQ-076 | DEF | What quality threshold and human sampling validate AI duplicate suggestions? |
| OQ-077 | DEF/REL | How are synthetic evidence, AI spam, and prompt injection detected? |
| OQ-078 | DEF | Who is accountable for AI misrouting or harmful proposals? |

### 25.10 Operations and measurement

| ID | Class | Unresolved question |
|---:|---|---|
| OQ-079 | S0/COL | Which system/tool and named team own moderation operations? |
| OQ-080 | COL | What launch volume can the team demonstrably review? |
| OQ-081 | S0/REL | What backlog age/volume pauses intake or narrows report types? |
| OQ-082 | S0 | Which metrics measure quality without rewarding volume or becoming analytics? |
| OQ-083 | REL | How are false publication, reversal, appeal, expiry, and review time measured? |
| OQ-084 | COL/REL | How are privacy incidents, moderator misuse, and Store attacks detected/responded to? |
| OQ-085 | DEF/COL | Which aggregate metrics could be public without contributor/Store harassment? |

### 25.11 Additional implementation questions

| ID | Class | Unresolved question |
|---:|---|---|
| OQ-086 | S0 | Which concrete persistence technology/versioning mechanism implements the separate Community store? |
| OQ-087 | S0 | What payload/API/status/reason versioning and minimum-client policy is approved? |
| OQ-088 | S0 | What exact retry cap, backoff, queue age, draft age, and cancelled-tombstone lifetime apply by report type? |
| OQ-089 | S0/COL | What draft/outbox/attachment count and byte budgets apply, and what user cleanup UX is approved? |
| OQ-090 | S0 | What user-visible wording and linkage represent the required cancel-and-new-identity flow when editing a queued envelope? |
| OQ-091 | S0 | What exact server transaction commits attachment manifest and report receipt without partial proof? |
| OQ-092 | S0 | How is feature/capability configuration authenticated, cached, expired, and audited? |
| OQ-093 | S0 | Which foreground/status refresh interval and batching contract balances freshness/privacy/battery? |
| OQ-094 | S0 | What approved string-catalog path and localization ownership fit the current project? |
| OQ-095 | S0 | Is a UI-test target added, or which manual/hosted tests prove complete consumer flows? |
| OQ-096 | S0 | How does an older app preserve/ignore a newer acknowledged status without resubmission? |
| OQ-097 | COL | What encryption/file-protection/key-rotation threat model applies beyond platform defaults? |
| OQ-098 | S0 | Which service and domain test environments provide deterministic publication/rollback proofs? |
| OQ-099 | REL | Who signs each manual artifact and owns failed release gates? |
| OQ-100 | S0 | Which existing Store scaffold types/call sites are removed versus adapted at final cutover? |

### 25.12 Blocking decision summary

At minimum, the next specification must resolve:

- selected report types, markets, languages, and unsupported/deferred behavior;
- all owners and end-to-end service/API contracts;
- pseudonymous receipt, privacy/legal/security, retention, rights, and consent;
- moderation states/reasons/appeal policy, staffing/capacity, trust/independence,
  rate limits, abuse, and emergency disablement;
- Catalog/Search publication/revision/rollback;
- Store identity/expiry only if a Store lane is selected;
- SKU/identifier authority only if those publication types are selected;
- local persistence, retry, storage, status, feature config, localization, test
  environment, and rollback decisions.

---

## 26. Implementation Readiness Checklist

### 26.1 Plan completeness

- [x] WT-030C and the Architecture Summary are the controlling authority.
- [x] WT-031A Product State and WT-031B Shopping Session boundaries are
  preserved.
- [x] Current repository files, types, persistence, networking, UI, diagnostics,
  tests, documentation, catalog artifacts, and unused scaffolding are inventoried.
- [x] Current behavior is distinguished from approved architecture, planned work,
  unresolved decisions, and deferred scope.
- [x] User Opinion, Community Evidence, Product Truth, Catalog Truth, Search Truth,
  Store profile truth, and Store/Product evidence have separate owners.
- [x] No client, report, trust score, report count, moderator decision, or AI
  output can publish truth.
- [x] The local delivery lifecycle, eight official moderation states, and domain
  publication lifecycle are separately defined.
- [x] The complete state matrix covers transitions, owners, client/server/
  moderation/publication/retry/offline/deletion/retention/terminal behavior.
- [x] Submission entry points, target identity, structured taxonomy, optional
  content, review, edit/cancel, acknowledgement, retry, and failure are planned.
- [x] Offline outbox identity, idempotency, backoff, relaunch, duplicate
  prevention, partial media, cleanup, and degraded storage are planned.
- [x] Synchronization distinguishes drafts, queued envelopes, receipts,
  moderation, publication links, and domain truth.
- [x] Moderation, trust/abuse, publication, explainability, privacy, accessibility,
  localization, diagnostics, and rollback boundaries are explicit.
- [x] Existing Catalog validation/release ownership is retained.
- [x] Existing Product, Product Knowledge, Search behavior, Store data, Shopping,
  Session, notifications, diagnostics, and analytics-like artifacts are
  classified for migration/non-migration.
- [x] A verified file-level plan names existing and proposed files.
- [x] Phases lead to one authority cutover with no public mixed-authority release.
- [x] Every WT-030C AC-001 through AC-100 maps to planned executable evidence or
  a named manual artifact.
- [x] Risks, dependencies, deferred scope, and all unresolved audit questions are
  recorded.

### 26.2 Gates before the implementation specification can authorize production work

- [ ] Select the first report families, markets, languages, and explicit
  deferrals.
- [ ] Name and fund every intake, evidence, moderation, privacy, abuse, and domain
  publication owner.
- [ ] Approve the production backend/API/idempotency/status/withdrawal and test
  environment contracts.
- [ ] Approve account-free pseudonymous identity, Keychain credential, future
  account, and multi-device boundaries.
- [ ] Approve data purposes/lawful bases, notices/consent, retention/deletion,
  rights, access control, residency/transfers, age/market, and incident response.
- [ ] Approve trust/independence/expiry, rate limits, abuse signals, queue
  capacity, appeal, and emergency disablement.
- [ ] Approve Catalog/Search proposal, revision, regression, publication proof,
  integrity/distribution, and rollback contracts.
- [ ] Approve durable Store identity/provider routing before any Store lane can
  publish.
- [ ] Approve SKU/variant/package/barcode authority before any such lane can
  publish.
- [ ] Choose the concrete separate Community-store technology, schema
  specification, migration, recovery, downgrade, and storage budgets.
- [ ] Approve retry/backoff/queue-age/media-transaction/status-refresh policies.
- [ ] Approve English/Hebrew copy, string-catalog integration, RTL,
  accessibility, and user research artifacts.
- [ ] Approve the full client/service/shared/domain test plan and ownership.
- [ ] Approve feature flags, safe disablement, privacy/status obligations during
  rollback, and domain revision rollback.
- [ ] Confirm WT-031A and WT-031B authority contracts required by the selected
  Community entry points are final.

### 26.3 Gates before external collection or release

- [ ] No selected report type has an unowned moderation or publication queue.
- [ ] No public UI exists without canonical receipt/status and a complete
  disposition path.
- [ ] Privacy, legal, security, abuse, operations, accessibility, localization,
  Catalog/Search/Store, and platform owners sign their named artifacts.
- [ ] All AC-001–AC-100 evidence passes for the selected scope.
- [ ] Feature-disable, service-outage, corruption, downgrade, publication-failure,
  and rollback drills pass.
- [ ] The built app privacy report, platform disclosures, permissions,
  entitlements, and network behavior match the approved data inventory.
- [ ] No raw report or Community store is visible to Product, list, plan, active
  Session, history, Search runtime, Store ranking, notification, or AI authority.
- [ ] No current data or behavior was silently converted into Community Evidence.
- [ ] Trust affects prioritization only; AI remains assistive only; one report
  remains non-authoritative.
- [ ] Only approved published projections can influence runtime behavior, with
  provenance, freshness, conflict, expiry, and rollback.

### 26.4 Readiness interpretation

This plan is complete enough to serve as the input to one approved implementation
specification. The unchecked items are deliberate specification, privacy,
service, operations, and release gates. They do not permit incremental production
coding or an isolated report surface. The implementation specification must
resolve every unchecked item applicable to its selected scope and receive
explicit approval before production files, tests, schemas, services, project
settings, catalog artifacts, or behavior change.

---

## 27. Terminal Decision

**READY FOR IMPLEMENTATION SPECIFICATION**

WT-031C provides a complete, dependency-aware plan for implementing the approved
Moderated Evidence-to-Truth Pipeline. It preserves Community Evidence separately
from Product, Catalog, Search, Store, Shopping, and Session authority; requires
human moderation and independent domain publication; makes trust priority-only
and AI assistive-only; and defines the local outbox, synchronization, privacy,
abuse, explainability, migration, testing, and rollback gates.

This decision authorizes only preparation and approval of the next implementation
specification. It does not authorize production code, tests, schemas, backend
services, project settings, catalog changes, data collection, application
behavior, or release.
