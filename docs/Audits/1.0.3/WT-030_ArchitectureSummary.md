# WT-030 - Architecture Summary

**Product:** WayTask iOS  
**Release context:** Version 1.0.3  
**Status:** Approved for implementation planning only  
**Authority:** Consolidated WT-030 architecture reference  
**Implementation authorized:** No

This document consolidates the approved architectural decisions in:

- `WT-030A_ProductStateUXAudit.md`
- `WT-030B_ShoppingSessionBackgroundAudit.md`
- `WT-030C_CommunityFeedbackAudit.md`

It does not replace their supporting analysis, create new product policy, or define an implementation. Where an implementation choice remains open in an audit, it remains open here.

## 1. Executive Summary

The WT-030 series established one coherent architecture for the three domains that govern WayTask's long-term shopping experience:

- **WT-030A:** the **Orthogonal Product Lifecycle**;
- **WT-030B:** the **Session-Scoped Persistent Hybrid**;
- **WT-030C:** the **Moderated Evidence-to-Truth Pipeline**.

Together, these decisions preserve the Product Specification's core model: Products are reusable, Shopping Lists express temporary intent, and Shopping Plans provide scoped intelligence. WT-030 extends that model by making Shopping execution durable and by defining how community claims may improve published knowledge without becoming truth automatically.

The result is an architecture in which user-owned state, shopping execution, catalog knowledge, Store evidence, notifications, AI, and future Cloud synchronization have explicit and non-overlapping authority. It is ready to guide approved implementation specifications. It does not authorize implementation.

## 2. Architecture Vision

WayTask is organized as cooperating domains rather than one shared state machine:

```text
Catalog Truth ---------------------> Search and planning projections
       ^                                           |
       | reviewed publication                      v
Community Evidence -> moderation -> domain validation

User Product -> Shopping List -> Shopping Plan -> Shopping Session -> History
                                      |                  |
Store profile + approved evidence ----+                  +-> Notifications

AI: proposes, classifies, and explains
Cloud: synchronizes approved domain records and commands
Platforms: implement shared domain semantics through platform-specific adapters
```

The long-term separation is:

- **Product** owns reusable user Product identity, snapshots, library membership, and explicit user edits. It does not own list, plan, session, recommendation, or global completion state.
- **Shopping** owns list intent, plan projections, and session execution outcomes. These states are scoped to a named list, list revision, plan, or session.
- **Community** owns claims, evidence, provenance, conflicts, trust inputs, and moderation lifecycle. It does not own published truth.
- **Catalog** owns validated, versioned Global Product Concepts, taxonomy, aliases, stable identifiers, and redirects. It does not own user Products or Store inventory.
- **Store** separates durable Store identity/profile truth from time- and market-scoped Product availability evidence.
- **AI** assists recognition, intake, triage, planning, and explanation. It never becomes an unreviewed state or publication authority.
- **Cloud** is a future synchronization and distribution mechanism. It does not redefine domain ownership or make device capability state into business state.

## 3. Official Architecture Principles

These are the binding principles adopted by WT-030:

1. **One authority per lifecycle.** Single source of truth means one scoped authority for each lifecycle, not one global flag, repository, or database for every concern.
2. **Orthogonal state ownership.** Product identity, library membership, list intent, plan state, session outcomes, history, catalog lifecycle, and community evidence remain independently representable.
3. **Explicit user ownership and intent.** User Product, Shopping, and Session changes occur only through explicit, scoped user-authorized commands.
4. **Durable, revisioned execution context.** A started Shopping Session owns an exact execution snapshot. That snapshot is stable for its revision and changes only through an explicit session command or revision.
5. **Derived projections are not truth.** Plans, search results, recommendation confidence, Map presentation, reminders, and compatibility fields are rebuildable or derived views of authoritative state.
6. **Evidence before truth.** Community input retains provenance, freshness, independence, and conflict until it passes the approved review and publication process.
7. **Human-reviewed, domain-validated publication.** Human moderation verifies substantive evidence; the responsible domain separately validates and publishes truth.
8. **Offline-first core behavior.** Product, List, and active Session behavior must remain usable and recoverable without network access.
9. **Privacy by design.** Collect only data required for the declared purpose, separate retention by data class, and do not require sensitive context by default.
10. **Explainability and honest uncertainty.** Inventory and Store availability remain probabilistic, and community-influenced decisions must be capable of explaining their primary source.
11. **Stable identity and conservative change.** Stable identifiers, timestamps, tombstones, revisions, idempotent commands, and explicit redirects protect user data and future migration.
12. **Platform-neutral domain semantics.** iOS and future Android share lifecycle meanings and fixtures while location, notification, and background behavior remain platform adapters.
13. **AI is an assistant, not an authority.** AI may propose, classify, summarize, or explain; users, moderators, and domain publication rules retain authority.

## 4. Approved Architectural Decisions

### 4.1 WT-030A - Orthogonal Product Lifecycle

WayTask Product State is a composition of scoped lifecycles, not a flat enum or checkbox:

- Product identity is stable and reusable.
- Library membership is `active` or a durable `removed` tombstone with explicit restoration.
- Shopping membership and need resolution belong to a Product entry in one named list.
- A Shopping Plan is a rebuildable projection of one list revision.
- Collection and other execution outcomes belong to one Shopping Session line.
- Purchase or usage belongs to repeatable historical events, never a global Product state.
- Catalog active, inactive, replaced, or missing status is independent of user-library membership.

Removing a Product from Shopping affects only the selected list. Finishing Shopping must reconcile every session line. Recommended Store context belongs to a plan or session. Map and notifications must consume the same scoped Shopping projection. The Product Library must not present shopping completion checkboxes, and legacy compatibility completion fields must never remain authoritative.

### 4.2 WT-030B - Session-Scoped Persistent Hybrid

A Shopping Session is durable business state independent of whether the app is foregrounded, backgrounded, suspended, terminated, relaunched, or rebooted.

The official session lifecycle is `active`, `expired`, `finished`, or `abandoned`. Finished and abandoned are terminal. Expiration preserves progress, disarms reminders, and requires an explicit user decision to resume or abandon.

A started session persists its source list and revision, plan and Store snapshot, stops, line snapshots, outcomes, timestamps, and revision. The general plan remains rebuildable; the session's execution snapshot is durable.

Background proximity is a best-effort capability derived from one active session revision:

- Core Location region monitoring is the default iOS background proximity mechanism.
- Standard location is foreground or bounded on-demand by default.
- No continuous background tracking or polling is implied by an active session.
- Every region event and notification must validate the persisted session, revision, eligibility, and expiration before presentation.
- Finish, abandon, and expire disarm reminders and suppress late events.
- Session restoration does not depend on notification permission.
- Force-quit and other iOS delivery limits must be communicated honestly.

Passive nearby opportunities, if retained, are a separate opt-in feature. Offline session execution is first-class. Future Cloud synchronization uses idempotent commands and device-local reminder ownership so synchronized devices do not duplicate proximity notifications.

### 4.3 WT-030C - Moderated Evidence-to-Truth Pipeline

Community Feedback follows this approved path:

```text
User Opinion
  -> normalized Community Evidence
  -> duplicate/conflict cluster
  -> trust-based review priority
  -> human moderation
  -> approved domain proposal
  -> domain validation and publication
  -> versioned Catalog, Search, or Store projection
```

A report is a claim, not truth. Trust, reputation, report volume, and AI may prioritize review but may not publish. No single report becomes authoritative automatically.

The architecture distinguishes:

- **Product Truth:** user-owned Product identity, snapshots, overrides, library/list/session state, and history;
- **Catalog Truth:** validated, versioned Global Product Concepts, taxonomy, aliases, stable identifiers, and redirects;
- **Search Truth:** a rebuildable projection of approved catalog, localization, and ranking rules plus bounded local personalization;
- **Store Truth:** durable Store identity/profile truth, separate from expiring Store/Product availability evidence;
- **Community Evidence:** provenance-bearing, time-scoped, potentially conflicting claims;
- **User Opinion:** the submitter's original assertion.

Human moderation verifies substantive evidence, but verification alone does not change runtime truth. The responsible Catalog, Search, Store profile, or Store evidence authority must validate and publish a versioned projection. Notifications never consume raw reports. Active plans and sessions are never silently rewritten by later community publication.

Reporting is optional and cannot block core Product, Shopping, or Session workflows. Participation is pseudonymous unless true anonymity is demonstrated. Exact location, route history, Product Library, Shopping List, and purchase history are not required report inputs by default.

## 5. Rejected Alternatives

| Rejected alternative | Reason for rejection |
|---|---|
| One flat global Product State or completion checkbox | Cannot represent independent library, list, plan, session, history, and catalog lifecycles without losing valid combinations. |
| Labels-only cleanup while retaining mixed authorities | Leaves contradictory behavior and migration debt behind a clearer interface. |
| Full event sourcing as the immediate Product architecture | Adds complexity beyond WayTask's current needs without solving the authority problem more directly. |
| Global geofences based on compatibility completion state | Produces stale, cross-list reminders and makes encoded payloads an accidental authority. |
| Continuous best-accuracy background location | Unnecessary battery, thermal, privacy, and platform risk for the approved experience. |
| Background refresh, polling, or Significant Location Change as arrival authority | Cannot provide the required timely or precise Shopping Session semantics. |
| Calendar or AI scheduling as session authority | Silently activates sensitive behavior without explicit user intent. |
| Direct community edits, majority voting, or reputation-based publication | Converts opinion and coordinated volume into truth without adequate validation. |
| Pure manual review of every mechanical case | Does not scale; safe automation is appropriate for intake, exact duplicates, clustering suggestions, prioritization, and expiry. |
| Local-only or provider-only Community Feedback as the complete architecture | Cannot provide both governed community growth and durable cross-platform truth. |
| Raw reports in search, Store ranking, plans, or notifications | Bypasses moderation, freshness, conflict, and domain publication boundaries. |
| AI as moderator or publisher | Removes accountable human and domain governance from substantive truth changes. |

## 6. Architecture Boundaries

| Concern | Authoritative owner | Owns | Must not own or silently change |
|---|---|---|---|
| Product State | The applicable Product, library, list-entry, plan, session-line, or history lifecycle | Its own stable identity, scoped state, and transitions | Another lifecycle's state |
| Shopping Session | One persisted session aggregate and revision | Lifecycle, execution snapshot, stops, line outcomes, recovery, expiration | App process state, permission state, notification delivery, global Product completion |
| Catalog Truth | Catalog publication governance | Versioned Global Product Concepts, taxonomy, aliases, identifiers, redirects | User Product state, Store inventory, raw community claims |
| Community Evidence | Community evidence domain and moderation lifecycle | Reports, provenance, freshness, independence, conflicts, clusters, review state | Published Catalog, Search, Store, Product, or Session truth |
| Store Truth | Store profile authority and separate Store evidence projection | Durable identity/profile revisions and approved expiring availability evidence | Permanent inventory certainty from temporary observations |
| Notifications | Platform notification adapter deriving from an authoritative revision | Delivery registration, capability state, and presentation of validated context | Session, Product, Catalog, Community, or Store truth |
| AI | Bounded assistant workflow | Proposals, recognition, classification, summaries, prioritization support, explanations | Silent user-state mutation, moderation verdicts, publication |
| Cloud | Future synchronization/distribution layer | Transport, conflict-safe synchronization, version distribution, idempotent command exchange | Domain ownership, last-write-wins truth, device reminder capability as business state |
| Persistence | Durable storage under each domain's repository boundary | Stable IDs, snapshots, tombstones, revisions, outcomes, and recovery data | Deciding business meaning merely because a field exists |
| User Data | The user through explicit domain commands, with local durable custody | Personal Products, lists, session decisions, snapshots, and private history | Silent rewriting by catalog, community, AI, notification, or Cloud processes |

Views, Map surfaces, scanners, notifications, AI workflows, and Cloud adapters are consumers or command initiators. They are not independent lifecycle writers.

## 7. Cross-Audit Relationships

WT-030A supplies the identity and state boundaries used by the other two decisions. A list entry states what is needed; a plan projects one list revision; a session line records what happened. This prevents WT-030B from treating global Product compatibility state as Shopping execution truth.

WT-030B specializes the Shopping Session portion of WT-030A. It freezes the selected list/plan context for execution, persists line outcomes, and makes reminders a validated capability projection rather than a second session state.

WT-030C may improve future Catalog, Search, Store profile, and Store evidence projections, but only after moderation and domain publication. It cannot mutate WT-030A Product Truth or rewrite a WT-030B active execution snapshot. A later published revision may inform a future plan or session.

Stable Global Product Concept and Store identifiers connect these domains without merging them. Notifications consume validated session context and, where relevant, published Store projections. AI and Cloud operate across domains only through their approved commands, projections, and publication boundaries.

## 8. Future Implementation Order

Subject to the Implementation Gate in Section 12, the approved dependency order is:

1. **Product State:** establish the Orthogonal Product Lifecycle as the shared domain foundation.
2. **Shopping Session:** establish the Session-Scoped Persistent Hybrid on the approved Product/List/Plan boundaries.
3. **Community Feedback:** establish required Store/SKU and operational governance prerequisites, then implement the Moderated Evidence-to-Truth Pipeline without bypassing Product or Session boundaries.

Each stage must reach one coherent authority cutover before dependent work treats it as a foundation.

## 9. Deferred Topics

The following remain intentionally deferred and are not decided by this summary.

### Product State

- Final list-resolution reason taxonomy and Finish Shopping outcome policy.
- Exact collected-versus-purchased semantics.
- Archive behavior.
- Completed and Recent system-projection semantics.
- Removal, restoration, privacy erasure, and retention UX details.
- Post-scan continuation behavior.

### Shopping Session

- Session expiration, inactivity, maximum-lifetime, quiet-hour, and reminder-budget thresholds.
- Exact active-session scope and conflicting-session UX.
- Product availability and policy for a separate passive nearby-opportunity feature.
- Calendar and AI scheduling behavior.
- Non-urgent background maintenance uses.
- Multi-device reminder lease policy and Cloud conflict details.
- Multi-Store and multi-list policies not already fixed by the shared architecture.

### Community, Catalog, and Store

- SKU, variant, package, and barcode authority.
- Durable cross-platform Store identity and provider contracts.
- Backend, service, API, database, deployment, and release-distribution design.
- Moderation tooling, staffing, ownership, service levels, appeals, trust weights, expiry periods, and abuse thresholds.
- Final privacy/legal policy, retention periods, residency, age policy, and account-linking rules.

### Future Platforms and Capabilities

- Cloud Sync and multi-device implementation.
- Android implementation.
- AI implementation beyond the approved authority boundaries.
- Future moderation automation and operational tooling.
- Shared lists, family accounts, live retail inventory, and other roadmap features.

## 10. Architecture Constraints

Future implementation work must never violate these rules:

1. No global Product enum, checkbox, or compatibility flag may represent multiple independent lifecycles.
2. Shopping membership and resolution must remain scoped to one named list entry.
3. Collection and execution outcomes must remain scoped to one session line.
4. Product Library UI must not present collection or completion state as Product identity.
5. Views, Map, notifications, scanner, AI, and Cloud must not write lifecycle state outside named domain commands.
6. A started session must retain its exact execution context and line outcomes across supported recovery paths.
7. App runtime, location permission, notification permission, and reminder registration must remain distinct from session business state.
8. Background behavior must not claim continuous execution or force-quit reliability that the platform cannot provide.
9. Every proximity event and notification must validate current authoritative context before presentation.
10. Finish, abandon, and expire must bound reminders; Finish must reconcile every session line.
11. Raw reports, report volume, reputation, trust scores, and AI output must never publish truth automatically.
12. Human moderation and separate domain validation/publication remain required for substantive community-originated changes.
13. Catalog or community changes must not silently rewrite user Product data or an active session snapshot.
14. Temporary Store observations must not become permanent inventory claims, and uncertainty must remain visible.
15. Notifications must consume published, scoped projections and never become state authorities.
16. Core Product, List, and Session behavior must remain offline-capable.
17. Sensitive user context must not be collected by default when the declared purpose does not require it.
18. Stable IDs, revisions, tombstones, provenance, and idempotency must be preserved through migration and synchronization.
19. Shared domain semantics must remain platform-neutral even when iOS and Android capabilities differ.
20. No partial visual patch, mixed-authority migration, unmoderated report surface, or hidden writer may be released as compliance with WT-030.

## 11. Architecture Readiness

WT-030 is architecturally ready for implementation planning because it now defines:

- the authoritative owner of every relevant lifecycle;
- the boundary between durable state and derived projections;
- the relationship between Product intent, plan intelligence, session execution, and history;
- an iOS-compatible background model with explicit battery, privacy, and reliability limits;
- a governed path from community claims to published truth;
- the role and limits of notifications, AI, Cloud, persistence, and platform adapters;
- the major rejected alternatives and non-negotiable constraints;
- a dependency order for future implementation specifications.

Readiness at this level does not resolve the deferred product, policy, privacy, and operational questions recorded by the audits. It means those questions can now be resolved within stable architecture boundaries rather than by changing the architecture during implementation.

## 12. Implementation Gate

Implementation may begin only through a separately approved, complete implementation specification for the applicable stage.

Each specification must:

- cite this WT-030 Architecture Summary as its controlling architecture reference;
- resolve every open audit question that affects the proposed stage;
- preserve all relevant audit acceptance criteria and constraints;
- define one coherent authority and migration cutover without a mixed-authority intermediate release;
- include recovery, offline, privacy, accessibility, localization, testing, and rollback requirements appropriate to its scope;
- receive explicit approval before production source, schema, capability, entitlement, backend, catalog artifact, or application behavior is changed.

This summary is not an implementation specification and grants no implementation authority.

## 13. Terminal Decision

**APPROVED FOR IMPLEMENTATION PLANNING ONLY:** WayTask Version 1.0.3 adopts the combined **Orthogonal Product Lifecycle**, **Session-Scoped Persistent Hybrid**, and **Moderated Evidence-to-Truth Pipeline** as its official WT-030 architecture.

These three decisions form one standard:

- user Product and Shopping state remain explicit, scoped, and user-owned;
- Shopping execution remains durable while background capabilities remain bounded and derived;
- community claims become published knowledge only through evidence preservation, human moderation, and domain validation.

This document is the official architectural bridge from the WT-030 audits to future implementation specifications. It introduces no new architecture, changes no prior WT-030 decision, and authorizes no implementation.

## Appendix A – Architecture Glossary
