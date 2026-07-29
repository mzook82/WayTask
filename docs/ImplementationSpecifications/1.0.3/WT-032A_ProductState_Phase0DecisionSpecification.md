# WT-032A — Product State Phase 0 Decision Specification

**Product:** WayTask iOS  
**Version:** 1.0.3  
**Status:** Decision specification  
**Document type:** Phase 0 policy and authority decisions only  
**Date:** 2026-07-29  
**Implementation authority:** None

---

## 1. Executive Summary

WT-030A approved an Orthogonal Product Lifecycle: Product identity, Product Library membership, named Shopping-list membership, Shopping Plan state, Shopping Session execution, Product History, and Catalog lifecycle are separate authorities. WT-031A translated that architecture into a dependency-aware implementation plan but intentionally left Product and migration policies unresolved.

This specification resolves those Phase 0 decisions. Its binding outcomes are:

- a Product is never globally complete;
- a named list entry, not a Product or compatibility item, owns Shopping need state;
- `collected` means placed in the basket during a Session and does not mean purchased;
- an explicit Finish confirmation assigns a final outcome to every Session line;
- Finish commits Session, list-entry, list-revision, and Product History effects as one local authoritative transaction;
- Product History is stable-Product-UUID event history, not a reconstruction from completion booleans;
- ordinary Product deletion means recoverable removal from the Library;
- restoration is explicit, preserves the Product UUID, and recreates no list membership;
- any number of named lists may coexist, while each plan and Session has exactly one source list;
- each `(list ID, Product ID)` has at most one current entry;
- list revisions, plan snapshots, and Session snapshots have explicit, non-overlapping meanings;
- legacy ambiguity is preserved as `legacyUnknown`, never promoted to purchase truth;
- the semantic migration has one owner and must complete before target Product State becomes writable;
- compatibility fields cease to be authorities at one cutover and cannot remain runtime fallbacks.

The specification does not design a SwiftData schema, define implementation tasks, or authorize production changes. It establishes the policy contract that later implementation specifications must consume.

---

## 2. Scope

### 2.1 Included

This document decides:

- Product completion and lifecycle vocabulary;
- Library removal, restoration, and retention;
- named Shopping-list entry state, resolution, removal, reopening, duplication, and multi-list behavior;
- durable list-revision semantics;
- Product History ownership and retention;
- Shopping Session interaction with Products and list entries;
- immutable plan and Session snapshot behavior;
- Finish reconciliation and its atomic boundary;
- legacy Product/list/history/session interpretation;
- migration ownership, failure, and rollback policy;
- compatibility authority retirement;
- Product State navigation, scanner, saved-location, and visual-state policy needed to remove ambiguity.

### 2.2 Excluded

This document does not:

- change the WT-030A architecture;
- decide WT-030B background execution, geofence scheduling, Session expiration timing, or battery strategy;
- decide WT-030C Community Evidence policy;
- design models, fields, indexes, migrations, APIs, files, or tests;
- implement code, tests, schemas, project changes, or catalog changes;
- define Cloud, Android, account, or synchronization conflict behavior;
- define a privacy-erasure implementation;
- authorize implementation.

### 2.3 Evidence and authority

The binding source order is:

1. `docs/Audits/1.0.3/WT-030A_ProductStateUXAudit.md`;
2. `docs/Audits/1.0.3/WT-030_ArchitectureSummary.md`;
3. this specification for Phase 0 decisions inside that architecture;
4. `docs/ImplementationPlans/1.0.3/WT-031A_ProductStateImplementationPlan.md` for sequencing and verified inventory;
5. the available Product Specification, `design/v1.0/WayTask_Product_Specification_v1.0.pdf`, where it does not conflict with the approved WT-030 architecture.

No repository file named `Version_1.0.3_ProductSpec.md` exists. The available v1.0 Product Specification confirms permanent Products, temporary multiple lists, one active list per trip, Product cards without completion state, multi-store Shopping, and mandatory uncollected-line reconciliation.

### 2.4 Current implementation facts revalidated for this decision

This is not a new audit. The following WT-031A findings were revalidated against the current repository to ensure that the decisions still address the live implementation:

| Current component | Verified current behavior relevant to this specification |
| --- | --- |
| `WayTask/Models.swift` — `Product` | Stable `id`; durable `deletedAt`; `restoreToLibrary`; compatibility `legacyShoppingItemID`. |
| `WayTask/Models.swift` — `ShoppingListEntry` | Membership by `shoppingListID` and `productID`; state compressed into `isChecked`; no reason, resolution time, or revision. |
| `WayTask/Models.swift` — `ShoppingItem` | Global `isCompleted` remains widely read and written. |
| `ShoppingListService.swift` | Adds/reopens an entry by setting `isChecked = false`; mirrors `isCompleted`; removes one list entry; barcode upsert restores a tombstone implicitly. |
| `ProductLibraryDeletionService` | Tombstones the Product, removes entries from `.weekly` lists only, and completes compatibility items. |
| `ShoppingListBackfillService` | Creates Weekly, Completed, and Recent list shells and continues runtime graph repair. |
| `WayTask/AppStateManager.swift` | Uses runtime UUID `shoppingListRevision`; plans contain compatibility items and no durable source revision or exact entry set. |
| `ShoppingSession.swift` / `ShoppingSessionService.swift` | Persist encoded compatibility item IDs and collected IDs; the first active Session is silently resumed; Finish updates only the Session header. |
| `ProductHistory.swift` / `ShoppingMemoryService.swift` | Aggregate history is keyed by barcode/name; `lastCompletedDate` can derive from `ShoppingItem.isCompleted`. |
| Product and Shopping UI | Product/list/session screens directly read or write overlapping state; the Shopping entry checkmark has no resolution reason. |
| Map, location, and notification inputs | Continue filtering and materializing global `ShoppingItem.isCompleted` state. |
| SwiftData persistence | Current schema is V3; V1→V2→V3 are lightweight migrations followed by runtime repair. |
| Existing tests | Characterize tombstone persistence, runtime repair, compatibility links, catalog restore, and V1/V2/V3 migration; they do not establish the approved target authority. |

Correct current ownership is retained: Product UUID, `deletedAt` tombstone meaning, catalog identity and display snapshots, exact catalog-ID deduplication, Product Knowledge separation, and scanner recognition state remain valid foundations.

---

## 3. Decisions Being Resolved

The decisions are grouped into six binding sets:

1. **Meaning:** Product completion, list resolution, Session collection, final outcomes, and history.
2. **Lifecycle:** removal, restoration, deletion retention, and tombstone behavior.
3. **List ownership:** multiple lists, entry uniqueness, reopening, resolved-entry presentation, and revision behavior.
4. **Session interaction:** immutable snapshots, active-Session conflicts, source-list editing, and Finish reconciliation.
5. **Migration:** ambiguous flags, duplicates, orphans, legacy Sessions, Completed/Recent records, history, failure, and rollback.
6. **Cutover:** compatibility retirement, transaction boundaries, navigation consumers, and authority enforcement.

Decision IDs `D-01` through `D-37` are stable references for later implementation specifications. A later specification may refine storage or API mechanics but may not change an approved outcome.

---

## 4. Decision Matrix

Every row has one approved outcome. No competing alternative remains inside a row.

| ID | Issue | Approved decision | Architectural rationale | Implementation impact | Migration impact | Affected components | WT source / phase |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D-01 | Product completion | No global Product-completed state exists. “Completed” may describe a finished Session or a resolved list need only. | Product identity is orthogonal to list and Session state. | Remove Product-level completion reads, writes, filters, and UI. | Never migrate a boolean into Product state. | Product, projections, UI, Map, notifications, AI context | WT-030A §§13.1–13.4, 14.1; P3–P7 |
| D-02 | List resolution | An entry is `needed` or `resolved(reason, effectiveAt, provenance)`. Approved reasons are `purchased`, `alreadyHave`, `noLongerNeeded`, and `legacyUnknown`; `legacyUnknown` is migration-only. | Resolution needs scope, reason, and time. | Named resolve/reopen commands replace direct checks. | Checked legacy evidence may become `legacyUnknown`, never purchase. | ShoppingListEntry, Shopping UI, projections, history | WT-030A §§13.5, 15.2; BI-01; P2–P5 |
| D-03 | Collected versus purchased | `collected` is provisional Session execution state only. Purchase exists only after explicit Finish confirmation. | Basket collection is not purchase truth. | Session UI and history must use distinct terms and commands. | Legacy collected IDs remain collected evidence only. | Session lines, Finish UI, history | WT-030A §§13.7–13.8, 14.5; BI-02; P5 |
| D-04 | Finish outcomes | Every Session line must end as `purchased`, `alreadyHave`, `noLongerNeeded`, `unavailable`, `skipped`, or `carriedForward`. No line is silently dropped. | Every line needs an explainable disposition. | Finish review assigns/validates every outcome. | No outcome may be fabricated for legacy unfinished lines. | Session, entries, history, Shopping UI | WT-030A §§13.7, 15.4; BI-03; P5 |
| D-05 | Abandonment | Abandon is terminal for the Session, preserves its snapshot and provisional progress, and performs no Product-list resolution or purchase-history write. | Abandonment is not Finish. | Separate explicit command and presentation. | Multiple/legacy Sessions may be explicitly abandoned without outcome inference. | Session, history, recovery UI | WT-030A §§13.7, 15.4; BI-04; P5 |
| D-06 | Product History ownership | Product History owns immutable, named outcome events keyed by stable Product UUID. Current aggregate rows remain legacy read models, not target authority. | History must be repeatable and cannot be a global state. | Domain commands append events; aggregates derive from events. | Unprovable aggregates remain legacy and unlinked. | ProductHistory, ShoppingMemoryService, personalization | WT-030A §13.8; WT-031A §5.6; P2–P5 |
| D-07 | History retention | Ordinary list removal, Product removal, restoration, Session Finish, and catalog changes never delete Product History. Local history has no automatic expiry in v1.0.3. | User-owned history outlives current Library/list membership. | Retention becomes an invariant; privacy erasure remains separate. | Preserve all existing rows and snapshots. | History, Product tombstones, recovery | WT-030A §§13.3, 13.8, 17.2; P2–P7 |
| D-08 | Multiple lists | Any number of named open lists may coexist. “Selected/active list” is presentation context, not a persisted Product lifecycle. A plan and a Session each use exactly one source list. | List membership is scoped and platform-neutral. | Explicit list IDs are required at all commands/consumers. | Preserve all list IDs; do not collapse to Weekly. | Lists, Home, Shopping, plan, Session | WT-030A §§13.4–13.6; BI-07, BI-13; P2–P5 |
| D-09 | Duplicate entries and add semantics | At most one current entry exists for `(listID, productID)`. Add is idempotent when needed; an existing resolved entry requires explicit Reopen. | Membership cannot have competing current rows. | Command serialization and typed outcomes are mandatory. | Duplicates use D-26’s deterministic merge. | List service, chooser, scanner destination | WT-030A §§13.5, 15.2; BI-09, BM-02; P2–P4 |
| D-10 | Resolved-entry behavior | Resolution retains the same entry in the same list, hides it from the default Needed view, and exposes it in a Resolved section/filter. Reopen preserves the entry ID and prior history event. | Moving rows would create a second lifecycle authority. | No “move to Completed list”; explicit Reopen. | Preserve entry IDs and resolution provenance. | Shopping UI, lists, history | WT-030A §§13.5, 14.3; BI-06, BI-08, BI-09; P2–P4 |
| D-11 | List revision | Each list owns a durable monotonic content revision. A committed projection-affecting transaction increments it once; an idempotent no-op does not. Commands use the expected revision. | Plans and consumers need a durable staleness contract. | Replace runtime UUID invalidation with durable comparison. | Migrated lists begin at a deterministic migration baseline. | ShoppingList, commands, plan, notifications | WT-030A §§13.5–13.6, 15.2–15.3; P2–P5 |
| D-12 | Immutable plan and Session snapshots | A plan records one list ID/revision and exact entry IDs. A started Session freezes plan/store/stop/line identity and approved display snapshots; later Product, catalog, plan, or list changes do not rewrite it. | Execution must remain recoverable and explainable. | New plan/session creation copies exact source context. | Preserve legacy snapshot evidence; mark gaps explicitly. | Plan, Session, Map, notifications, history | WT-030A §§13.6–13.7; WT-030 summary; P3–P5 |
| D-13 | Source-list edits during an active Session | New entries may be added but do not enter the active Session. Captured entries cannot be removed, resolved, reopened, or quantity-edited outside Session commands until that Session is terminal. Other lists remain editable. | This preserves immutable lines and avoids silent Finish conflicts. | Commands return an active-Session conflict for protected entries. | Legacy contradictions become explicit exceptions. | List commands, Shopping UI, Session | WT-030A §§13.7, 15.4; BI-12; P3–P5 |
| D-14 | Session scope and start conflict | v1.0.3 Sessions are single-source-list and may contain one or more planned store stops. A new start while a non-terminal Session exists offers Resume, Finish, Abandon, or Cancel; it never silently resumes or replaces a different context. | Matches the Product Specification and WT-030B ownership. | Start requires validated list/plan identity and explicit conflict handling. | Multiple active legacy Sessions follow D-29. | Session service, Shopping, Home, Map | WT-030A §§13.7, 15.4; BI-11, BI-13; P5 |
| D-15 | Library removal | The ordinary “Delete” Product action becomes “Remove from Product Library.” After confirmation it tombstones the Product and removes its current entries from all editable named lists in one transaction. | Library removal is recoverable and distinct from list removal. | All-list impact summary and named command are required. | Tombstones and history are preserved. | Product, list entries, Product UI, plans | WT-030A §§13.3, 15.1; BI-05; P2–P4 |
| D-16 | Removal during active Session | Library removal is blocked while any non-terminal Session contains that Product. The user must first Finish or Abandon the Session; no Library command mutates a Session snapshot. | Cross-aggregate deletion must not rewrite execution truth. | Typed conflict and navigation to the Session. | Active legacy references are preserved until recovery. | Product removal, Session recovery, UI | WT-030A §§13.3, 13.7; mandatory blocker; P3–P5 |
| D-17 | Restore | Restore is explicit, uses the same Product UUID, preserves user fields/snapshots/history/knowledge, and recreates no list membership. “Add to list” is a separate later command. | Restoration changes Library membership only. | All acquisition paths return `restoreRequired` for tombstones. | Migration and repair never restore. | Product, scanner, catalog persistence, startup | WT-030A §§13.3, 14.8, 15.1; BI-10, BI-17, BI-18; P2–P4 |
| D-18 | Restoration after deletion | A tombstoned Product is restorable indefinitely in v1.0.3. A future approved privacy erasure is irreversible; reacquisition after physical erasure creates a new Product identity. | Tombstone and erasure are different operations. | Product State exposes no physical-erasure command in v1.0.3. | Never treat a missing erased record as a tombstone. | Product Library, privacy boundary, acquisition | WT-030A §§13.3, 19; mandatory blocker; P3–P4 |
| D-19 | Completed and Recent semantics | `Completed` is retired as a Shopping-list label. Per-list Resolved is a scoped projection. `Recent Products` is a read-only history projection, not a Shopping list. Existing `.completed`/`.recent` records become a legacy activity archive. | System projections must not masquerade as editable lists. | Remove both kinds from active-list commands/navigation. | Apply D-30; create no purchase truth. | Lists, Home, Products, migration | WT-030A §§13.5, 13.8, 14.3; BI-06, BM-07; P2–P4 |
| D-20 | Visual and language semantics | Library has no lifecycle checkmark. List and Session controls always pair text with any icon/color. The bilingual semantic vocabulary in §5.5 is binding. | State must be scoped, localizable, and accessible. | Shared presentation vocabulary and accessibility values. | Migrated unknown state is visibly qualified. | Product UI, Shopping UI, VoiceOver, localization | WT-030A §§14.1–14.10; BI-19, BI-20; P4–P6 |
| D-21 | Home and notification destination | A Home list card opens that named list in Shopping. A valid active-Session notification opens the exact Session; a non-Session list reminder opens its owning named list. Stale context opens a safe Shopping state with an explanation. | Consumers route to authority; they do not reconstruct it. | Payload and route validation require owning IDs/revisions. | Legacy payloads cannot mutate state. | Home, notifications, AppStateManager, Shopping | WT-030A §§14.7, 15.5; BI-14, BI-15; P4–P5 |
| D-22 | Scanner and catalog tombstones | Product acquisition defaults to Library-only. A tombstone shows “Restore to Product Library”; no barcode/catalog/AI path restores automatically. After save/restore, adding to a named list is explicit. | Acquisition is not Shopping membership. | Typed outcomes and exact success copy. | Existing implicit restoration is retired at cutover. | Camera, autocomplete, save coordinator, catalog persistence | WT-030A §§14.8, 15.1; BI-16–BI-18; P3–P4 |
| D-23 | Saved-location records | Saved-location `ShoppingItem` relationships are legacy store-note/reminder evidence, not Product, list, plan, or Session authority. Target reminders consume revisioned list/Session projections. | Location cannot own a parallel Product lifecycle. | Remove lifecycle toggles from saved-location surfaces. | Preserve legacy notes; map only exact provable Product/list links. | GeoLocation, LocationDetail, LocationManager, Map | WT-030A §§5.14, 13.11; BI-21; P2–P5 |
| D-24 | Migration ownership | One Product State semantic migration coordinator owns interpretation, normalization, validation, completion marking, and exception reporting after schema evolution and before writable Product State UI. | Runtime views/backfill cannot co-own data conversion. | Startup gates target UI on one completed migration version. | Staged, idempotent, fail-closed migration is mandatory. | Persistence startup, migration, backfill | WT-030A §17; WT-031A §§7.9–7.10; BM-09; P2 |
| D-25 | Legacy completion flags | Entry existence establishes exact-list membership. `isChecked == false` becomes needed. `isChecked == true` becomes resolved `legacyUnknown`. `ShoppingItem.isCompleted` never overrides an entry and creates no purchase or membership; contradictions are counted. | Preserve visible checked intent without inventing truth. | Target reads never consult legacy flags after migration. | Deterministic mapping for every flag combination. | Migration, entries, compatibility items, history | WT-030A §17.3; BM-01; P2 |
| D-26 | Duplicate migration | For each exact duplicate group, retain the earliest `createdAt` entry, breaking ties by UUID. Preserve the maximum valid quantity, minimum sort order, earliest creation time; state is needed if any row is needed, otherwise `legacyUnknown` resolved. Rebind exact references through an alias ledger and record every merge. | Conservative preservation avoids quantity inflation and false completion. | No later add may recreate a duplicate. | Deterministic, idempotent merge; ambiguous cross-Product rows are exceptions. | Migration, entries, legacy Sessions | WT-030A §§13.12, 17; BM-02; P2 |
| D-27 | Orphans and unprovable compatibility | Repair a missing relationship only when the stored Product UUID resolves exactly. Otherwise preserve the row/evidence as a migration exception, exclude it from authoritative active state, and never name/barcode-match or silently delete it. | Unknown is safer than fabricated identity. | Exception presentation and recovery boundary are required. | Unprovable compatibility items do not create Products or memberships. | Migration, recovery UI, compatibility | WT-030A §§11.6, 17.3; BM-03, BM-04; P2, P6 |
| D-28 | Legacy Session mapping | Resolve a legacy item by exact compatibility UUID, then source list ID, then exact entry alias. Zero or multiple matches create an unresolved snapshot line. Collected IDs remain provisional collected evidence. | Session migration cannot invent final outcomes. | WT-031B consumes normalized lines and exceptions. | Preserve Session UUID, context, times, snapshots, and all evidence. | Migration, Session, recovery | WT-030A §17; BM-05; P2, P5 |
| D-29 | Multiple active legacy Sessions | Preserve every Session as a recovery candidate. Before normal shopping, the user selects one to resume or explicitly abandons Sessions; no Session is silently discarded or auto-finished. | Progress is user-owned and context must be explicit. | Recovery chooser precedes new Session start. | Abandoned candidates retain snapshots/progress and create no Product outcome. | Startup recovery, Session UI, migration | WT-030A §15.4; BM-06; P2, P5 |
| D-30 | Legacy Completed/Recent records | Preserve records and IDs in a read-only legacy activity archive. If an exact Product UUID and exact source entry are already durable, a `legacyUnknown` activity event may reference them; otherwise keep an exception. Never create purchased history. | Their old labels do not prove semantics. | Target Resolved/Recent projections ignore archive rows as current state. | No row is silently moved, reclassified as purchase, or deleted. | Migration, Home, history, lists | WT-030A §§13.8, 17.3; BM-07; P2–P4 |
| D-31 | Legacy Product History mapping | Preserve current aggregate rows unchanged and non-authoritative. Do not attach them to a Product based only on name or barcode. Target UUID-keyed events begin at cutover unless an existing durable UUID link is proven. | Historical overclaim is worse than an explicit legacy gap. | Personalization may read legacy aggregates only through a labeled compatibility projection. | No reconstructed purchase or resolution event. | ProductHistory, ShoppingMemory, personalization | WT-030A §§13.8, 17.3; BM-08; P2–P5 |
| D-32 | Tombstones with active references | Tombstones remain removed. Historical/terminal references remain valid. Current list or non-terminal Session references are migration exceptions; they do not restore the Product or disappear. | Library membership cannot be inferred from a reference. | Recovery resolves protected Session context before normal mutation. | Preserve IDs/snapshots and classify the contradiction. | Migration, Product, lists, Session | WT-030A §§13.3, 17.3; BM-12; P2, P5 |
| D-33 | Compatibility retirement | At the Phase 7 cutover, legacy fields/models have zero authoritative readers and writers. Any internal mirror before cutover is target-derived only. Physical storage may remain read-only through v1.0.3 and is removed only by a later validated schema release. | Retention for rollback cannot retain authority. | Static enforcement and call-site counters reach zero before release. | One semantic cutover; no post-migration fallback. | `ShoppingItem`, legacy IDs, views, services, Map, payloads | WT-030A §§17.1, 17.5; WT-031A §6.6; P3–P7 |
| D-34 | Migration failure and rollback | Capture a recoverable original-store boundary before semantic writes. Failure leaves it intact and blocks writable target UI. After successful target writes, rollback uses a forward-compatible build; restoring an old backup is explicit and warns that later changes are lost. | Old authority cannot safely reopen a target store. | No silent quarantine-to-empty success and no old-binary downgrade assumption. | Original store/sidecars, stage result, and exception counts are validated. | Startup persistence, release recovery | WT-030A §§5.13, 17; BM-10, BM-11; P2, P6–P7 |
| D-35 | Atomic Product/list commands | Add, resolve, reopen, remove-from-list, remove-from-Library, and restore each commit their owned state, affected list revisions, and named history events together. Failed saves expose no success. | User intent must have one durable result. | Views cannot compose partial writes. | Migration adapters, if present, are updated in the same transaction but remain non-authoritative. | Commands, Product, entries, revisions, history | WT-030A §§13.11–13.12; P3–P4 |
| D-36 | Atomic Finish | One local authoritative transaction validates Session revision and every line, writes final line outcomes, reconciles source entries, increments each affected list revision once, appends history events, invalidates source plans, and marks the Session finished. External notification/geofence cleanup is post-commit and idempotent. | Finish must never partially commit Product meaning. | One shared command owner coordinates Product State and WT-031B Session persistence. | Legacy or unresolved lines block Finish until explicitly reconciled. | Session, list, history, plan, reminders | WT-030A §§13.7–13.8, 15.4; BI-22; P5 |
| D-37 | Uniqueness and revision enforcement | The command boundary serializes and transactionally enforces uniqueness and expected revision on every supported iOS version. A database constraint/index may add defense but is never the sole invariant. | Correctness cannot depend on unproven SwiftData features. | Later specification must prove the chosen mechanism without weakening this rule. | Migration validates the same invariants before completion. | Persistence, list service, tests | WT-030A §13.12; BI-23; P1–P3 |

---

## 5. Product State Definitions

### 5.1 Product identity

A Product is the user-owned identity for a thing the user recognizes and may shop for.

- Identity is the stable Product UUID.
- Catalog ID and display snapshots may describe that identity but do not replace it.
- Product identity has no Shopping, plan, Session, purchase, or completion state.
- Catalog active/inactive/replaced state does not change Product lifecycle.

### 5.2 Library lifecycle

| State | Meaning | Allowed transition |
| --- | --- | --- |
| Active | Visible in the Product Library and available for explicit list commands. | Remove from Product Library. |
| Removed | Tombstoned, recoverable, excluded from normal Library and new list selection. | Explicit Restore to Product Library. |

Archive is not a v1.0.3 Product state. Physical privacy erasure is not a Library state.

### 5.3 Named list-entry lifecycle

| State | Meaning | Allowed transition |
| --- | --- | --- |
| Absent | No current entry for the Product in that exact list. | Add → Needed. |
| Needed | The named list currently expresses a need for the Product. | Resolve or Remove. |
| Resolved | The need was explicitly reconciled with an approved reason and effective time. | Reopen → Needed, or Remove. |

The approved resolution reasons are:

- `purchased` — explicitly confirmed at Finish;
- `alreadyHave` — the user states the need is satisfied by something already owned;
- `noLongerNeeded` — the user intentionally cancels the need;
- `legacyUnknown` — migration preserved a legacy resolved-like check without claiming why.

`unavailable`, `skipped`, and `carriedForward` do not resolve the source entry. The entry remains Needed.

### 5.4 Session execution and outcome vocabulary

Session execution state and final outcome are separate:

- `remaining` — not currently collected in the active Session;
- `collected` — placed in the basket; provisional and reversible;
- `purchased` — explicitly confirmed final outcome;
- `alreadyHave` — final non-purchase outcome that resolves the source entry;
- `noLongerNeeded` — final non-purchase outcome that resolves the source entry;
- `unavailable` — final observation; source entry remains Needed;
- `skipped` — final user choice for this Session; source entry remains Needed;
- `carriedForward` — explicitly retained for a later Session; source entry remains Needed.

A store-stop handoff may carry a remaining line to a later stop in the same active Session. That routing action is not the final `carriedForward` outcome.

### 5.5 Binding presentation vocabulary

Semantic keys are platform-neutral. The following English and Hebrew base labels are approved for v1.0.3. Grammatical inflection may adapt to sentence context but may not change meaning.

| Semantic meaning | English | Hebrew |
| --- | --- | --- |
| Product Library | Product Library | ספריית המוצרים |
| Shopping List | Shopping List | רשימת קניות |
| Needed | Needed | דרוש |
| Resolved | Resolved | טופל |
| Remaining | Remaining | נותר |
| Collected | Collected | נאסף |
| Purchased | Purchased | נרכש |
| Already Have | Already Have | כבר יש לי |
| No Longer Needed | No Longer Needed | כבר לא דרוש |
| Unavailable | Unavailable | לא זמין |
| Skipped | Skipped | דילוג |
| Carry Forward | Carry Forward | העברה להמשך |
| Keep Needed | Keep Needed | השאר כדרוש |
| Removed from Library | Removed from Library | הוסר מהספרייה |
| Restore to Product Library | Restore to Product Library | שחזור לספריית המוצרים |
| Reopen | Reopen | פתיחה מחדש |
| Finish Shopping | Finish Shopping | סיום הקנייה |
| Legacy reason unknown | Legacy reason unknown | סיבת מצב קודם אינה ידועה |

“Checked,” “complete Product,” and “incomplete Product” are not approved user-facing Product State terms.

---

## 6. Product Lifecycle Decisions

### 6.1 Creation

- Manual, scanner, AI-reviewed, and catalog acquisition create or return a Product in the Library.
- Default acquisition destination is Library-only.
- Creation does not create a list entry, plan, Session line, history purchase event, or store truth.
- An existing active exact identity returns an already-present outcome without lifecycle mutation.
- A tombstone returns `restoreRequired`; it is not a create result.

### 6.2 Product completion

Product completion is deliberately undefined because it would collapse independent lifecycles.

The following are valid and may coexist:

- Product active in Library;
- Needed in list A;
- Resolved in list B;
- collected in Session C;
- referenced by prior purchase and non-purchase history;
- catalog reference inactive or replaced.

No combination produces a global Product state.

### 6.3 Catalog interaction

- Catalog lifecycle remains read-only input to Product display/reference resolution.
- Catalog deactivation or replacement never removes, restores, resolves, reopens, or purchases a Product.
- User-owned Product UUID and saved snapshots remain stable.
- An approved catalog redirect may resolve catalog reference identity; it does not alter any Product lifecycle.

### 6.4 Archive

Archive is not introduced in v1.0.3. A future need for Archive requires a later architecture decision that distinguishes it from Removed; it cannot be implemented as another name for `deletedAt`.

---

## 7. Shopping List Decisions

### 7.1 Named-list ownership

Every membership command names one list ID. There is no context-free “in Shopping” mutation.

- Add affects one list.
- Remove from Shopping affects one list.
- Resolve affects one entry in one list.
- Reopen affects the same entry in one list.
- A Product may be Needed in multiple lists independently.
- State or revision changes in list A do not change list B.

### 7.2 List selection

WayTask supports multiple named open lists. Exactly one list may be selected by a Shopping presentation at a time, but selection is navigation/presentation state rather than list-domain state. One default list may provide a convenience selection; it is not the only list that can exist.

### 7.3 Entry uniqueness and retry

For a given `(list ID, Product ID)`:

- absent + Add creates one Needed entry;
- Needed + Add returns the same entry without revision/history drift;
- Resolved + Add does not reopen silently; the caller must obtain explicit Reopen intent;
- concurrent Adds produce one entry and one committed add event;
- retry after an unknown save result is idempotent by stable command/entry identity.

### 7.4 Resolve, remove, and reopen

- Resolve retains the entry and records its reason, effective time, and history event.
- The default list view shows Needed entries. A clearly labeled Resolved section/filter shows retained resolved entries.
- Reopen changes the retained entry back to Needed and appends a reopen event; it never erases the earlier resolution event.
- Remove deletes current membership only. It preserves Product identity and history.
- Removing a resolved entry does not delete its historical resolution.

### 7.5 Revision rules

A list content revision advances exactly once for a transaction that changes any plan/session/reminder-relevant content, including:

- entry addition or removal;
- Needed/Resolved transition or resolution reason;
- quantity, unit, order, or user note used by a projection;
- list title when it is captured in plan, Session, deep-link, or reminder context;
- a batch of multiple such changes committed together.

It does not advance for:

- an idempotent Add/Remove/Reopen retry that makes no change;
- Product Library-only acquisition;
- edits in another list;
- presentation-only selection, expansion, or filter changes;
- Session collection state.

Product attributes that influence planning use their own declared planning-input version or fingerprint. They do not falsify a list revision by mutating it outside the list owner.

### 7.6 Completed and Recent

- The Completed Shopping-list kind and label are retired.
- Resolved entries remain scoped to their owning named list.
- Recent Products is a read-only Product History projection.
- Neither projection accepts add/remove/check commands.
- Legacy Completed/Recent rows follow D-30 and are not current Product State.

---

## 8. Product History Decisions

### 8.1 Authority

Product History is the authority for repeatable past Product/list/Session outcomes. It is not the authority for current Library state, current list state, active Session state, Catalog Truth, or purchase verification outside user confirmation.

Target history events have:

- stable event identity;
- stable Product UUID;
- event type and explicit outcome/reason;
- occurrence/effective time and recording time where they differ;
- source list/entry and Session/line identity when applicable;
- immutable display snapshot sufficient to explain the past event;
- provenance, including `userConfirmed`, `sessionFinish`, or `legacyMigration`.

Exact storage representation belongs to a later implementation specification.

### 8.2 Named event meanings

The target history must distinguish at least:

- need added;
- need resolved with reason;
- need reopened;
- membership removed;
- Session line finalized with an approved final outcome;
- Product removed from Library;
- Product restored to Library.

Implementations may derive read models from these events. They may not collapse them into a single `completed` flag.

### 8.3 Purchase truth

Only a successful Finish transaction with explicit purchase confirmation may append a `purchased` outcome. The following never create purchase history:

- `ShoppingItem.isCompleted`;
- `ShoppingListEntry.isChecked`;
- collected state;
- list removal;
- Product removal;
- Finished Session header without reconciled lines;
- legacy Completed/Recent membership;
- store recommendation or availability;
- catalog or barcode recognition;
- analytics or AI inference.

### 8.4 Retention and erasure boundary

- History is retained without automatic expiry for v1.0.3.
- Tombstoning or restoring a Product retains all history and snapshots.
- List deletion/removal retains Product events; a later list-retention policy may remove the list container without erasing Product history.
- The separate future privacy-erasure policy may delete or anonymize history after legal/product approval.
- Ordinary Product State UI does not expose irreversible physical erasure in v1.0.3.

---

## 9. Finish Reconciliation Decisions

### 9.1 Finish is a review and confirmation

Selecting Finish does not immediately terminate the Session. It opens or enters reconciliation:

1. collected lines are proposed as `purchased`;
2. the user may change any proposed outcome;
3. every remaining line must receive an approved final outcome;
4. a batch action may explicitly carry all remaining lines forward, but no default is silently committed;
5. the final action explicitly confirms purchases and all other dispositions;
6. only the successful atomic commit marks the Session finished.

If a later planned store can cover an uncollected line, store-stop reconciliation may route it to that stop while the Session remains active. At whole-Session Finish it must still receive one final outcome.

### 9.2 Outcome-to-list mapping

| Final line outcome | Source list-entry result | Product History result |
| --- | --- | --- |
| Purchased | Resolve as `purchased`. | Append user-confirmed purchased outcome. |
| Already Have | Resolve as `alreadyHave`. | Append non-purchase resolution outcome. |
| No Longer Needed | Resolve as `noLongerNeeded`. | Append non-purchase resolution outcome. |
| Unavailable | Keep Needed. | Append unavailable Session observation. |
| Skipped | Keep Needed. | Append skipped Session observation. |
| Carried Forward | Keep Needed. | Append carry-forward Session outcome. |

No outcome removes the Product from Library. No outcome changes another list.

### 9.3 Failure and retry

- Validation failure leaves the Session active and makes no authoritative change.
- Save failure leaves Session, entries, revisions, history, and plan validity unchanged.
- The UI does not show completion success before the durable commit.
- Retrying the same Finish command cannot duplicate events or revisions.
- An unresolved migrated line blocks Finish until the user assigns an outcome or explicitly abandons the Session.

---

## 10. Restore Decisions

### 10.1 Restore preconditions

Restore is available only for an existing tombstoned Product identity. It requires explicit user confirmation identifying the Product and the destination “Product Library.”

Acquisition surfaces use these outcomes:

- exact active Product → Already in Product Library;
- exact removed Product → Restore required;
- no exact Product → Create;
- ambiguous possible match → do not merge or restore; require user resolution.

### 10.2 Restore effects

A successful Restore transaction:

- clears the Library tombstone;
- retains the same Product UUID;
- retains user fields, images, catalog ID/snapshots, Product Knowledge, and history;
- records a restore event;
- creates no list entry;
- changes no list revision;
- restores no plan or Session;
- does not refresh a catalog snapshot unless a separate, explicitly approved snapshot action is confirmed.

### 10.3 Acquisition and scanner behavior

- Barcode, catalog selection, scanning, AI recognition, startup repair, migration, background work, and future sync cannot restore automatically.
- The approved action label is “Restore to Product Library” / “שחזור לספריית המוצרים.”
- After restore, the user may separately choose “Add to [named list].”
- Default post-scan persistence remains Library-only; list addition is a separate explicit command.

---

## 11. Deletion Decisions

### 11.1 Ordinary Product deletion

The Product action currently described as Delete is defined as recoverable removal:

- user-facing action: Remove from Product Library;
- lifecycle effect: Active → Removed tombstone;
- scope: Product Library plus current entries in all editable named lists;
- retained: Product UUID, user fields, snapshots, history, Product Knowledge, terminal plan/Session references;
- excluded after commit: normal Library, chooser, new plan input, and new Session input.

Before confirmation, the UI identifies the number/names of lists from which the Product will also be removed.

### 11.2 Active Session protection

If any non-terminal Session contains the Product:

- Remove from Product Library is blocked;
- no list entry or Session line is changed;
- the user is directed to Resume the Session and Finish or Abandon it;
- a finished or abandoned Session remains a historical reference and does not block later removal.

This policy avoids a cross-owner command that would rewrite or orphan an immutable active snapshot.

### 11.3 Removed Product discovery and retention

v1.0.3 provides a Removed Products discovery surface or filter sufficient to:

- identify removed Products;
- show removal status without calling it completed;
- Restore explicitly;
- preserve accessibility and English/Hebrew meaning.

Removed Products do not auto-expire. A time-limited undo is optional presentation convenience, not the only restoration path.

### 11.4 Physical erasure

Physical privacy erasure is not implemented or authorized by this Product State decision. It remains a separate policy/legal specification. When later approved, it must:

- be clearly distinguished from Remove from Product Library;
- address history, Session snapshots, diagnostics, and backups;
- be irreversible for the erased Product identity;
- never be used as an ordinary list or Library workflow.

---

## 12. Multiple List Decisions

### 12.1 Coexistence

- Multiple named lists are supported concurrently.
- A Product may appear in zero, one, or many lists.
- Each list owns its own entry instance, state, quantity, order, notes, and revision.
- “Weekly Shopping” may remain a default title but not a singleton domain category.
- No list is globally “the Shopping list.”

### 12.2 Planning and Sessions

- Each plan uses exactly one named source list and one source revision.
- Each v1.0.3 Session uses exactly one source list and may span multiple stores/stops.
- Cross-list trips are deferred, consistent with the available Product Specification.
- A user must finish or abandon a non-terminal Session before starting from another list.

### 12.3 Active-Session edit boundary

During a Session:

- captured source entries are mutation-protected outside Session commands;
- new entries may be added to the source list, increment its revision, and remain outside the Session;
- changes to other lists are allowed and isolated;
- Product display edits do not rewrite the Session snapshot;
- Product removal is blocked under §11.2;
- a new plan may be generated for future use but cannot replace the active Session snapshot.

### 12.4 Duplicate prevention

Uniqueness is a command invariant, not a UI convention. All entry creation paths—Product Library, chooser, scanner continuation, Home quick action, restored Product, migration, retry, and future AI command—must use the same `(listID, productID)` rule.

---

## 13. Migration Decisions

### 13.1 Owner and execution boundary

One semantic migration owner runs after physical schema evolution and before writable Product State UI. It owns:

- pre-migration inventory and recoverable-store boundary;
- deterministic interpretation;
- entry normalization and reference aliasing;
- legacy Session normalization;
- history preservation;
- exception classification;
- invariant validation;
- atomic completion marking;
- privacy-safe diagnostics.

Runtime views, startup backfill, catalog repair, and compatibility services do not reinterpret migrated lifecycle meaning.

### 13.2 Deterministic flag mapping

For every entry/compatibility flag combination:

| Entry relationship/state | Compatibility state | Target result |
| --- | --- | --- |
| Exact entry exists; `isChecked == false` | Either value or absent | Needed in that exact list. Count contradiction if compatibility says completed. |
| Exact entry exists; `isChecked == true` | Either value or absent | Resolved `legacyUnknown`; effective time is the migration recording time with migration provenance, not a claimed historical purchase time. |
| No entry | `isCompleted == false` | Compatibility evidence only; no list membership is created after cutover. |
| No entry | `isCompleted == true` | Compatibility evidence only; no Product completion, list resolution, or purchase is created. |
| Tombstoned Product with entry/evidence | Any | Preserve tombstone; classify non-terminal references under D-32. |

Migration never uses a Product name, category, or barcode to create Catalog identity or substitute a missing Product UUID.

### 13.3 Duplicate merge

Duplicate grouping occurs only when list ID and Product UUID are exact.

For each group:

1. survivor is earliest `createdAt`, ties resolved by lexicographically smallest UUID;
2. survivor keeps the earliest creation time;
3. quantity is the maximum valid positive quantity, never the sum;
4. sort order is the minimum valid order;
5. if any row is Needed, the survivor is Needed;
6. otherwise it is Resolved `legacyUnknown`;
7. exact legacy/session references are rebound through a recorded old-entry-ID → survivor-ID alias;
8. non-survivor records are removed only after reference validation and recoverable-store protection;
9. merge category/count and no private content are recorded in diagnostics;
10. a second run produces no data or timestamp drift.

Rows that disagree on exact Product UUID or list ID are not duplicates and become exceptions.

### 13.4 Orphans

- Missing relationship + exact existing stored Product UUID: repair the relationship.
- Missing Product for stored UUID: preserve as an exception and exclude from active authoritative projections.
- Missing exact list: preserve as an exception; do not place it in the default list.
- Unprovable compatibility item: retain as legacy evidence/archive; do not create Product/list state.
- Available stored snapshots may render an explicitly non-authoritative recovery row.
- No exception is silently deleted or guessed by text matching.

### 13.5 Legacy Sessions

Migration preserves:

- Session UUID;
- recorded start/finish/active evidence;
- source list/store context;
- item and collected ID evidence;
- display data available from exact references;
- every unmatched line as an unresolved snapshot line.

Collected remains provisional. A finished legacy header without line outcomes does not create purchased or resolved entries. Multiple active Sessions require the explicit recovery decision in D-29.

### 13.6 Completed, Recent, and history

- Existing Completed/Recent Shopping-list records are archived read-only.
- They are never used as current list state or purchase proof.
- Exact already-durable Product/entry relationships may be retained as legacy activity provenance.
- Current ProductHistory aggregate rows remain unchanged and non-authoritative.
- No name-only or barcode-only association creates a UUID-keyed event.
- New target events begin at cutover.

### 13.7 Tombstones

- Preserve `Product.id`, `deletedAt`, user fields, snapshots, and history.
- Migration cannot call Restore.
- Terminal historical references remain valid.
- Active list/non-terminal Session references are exceptions requiring the recovery policies in D-16, D-29, and D-32.
- Restore later uses the same UUID and no list recreation.

### 13.8 Staging, idempotency, and failure

The semantic contract is:

1. open the existing store without exposing writable target UI;
2. capture counts, stable-ID checks, and a recoverable original-store boundary;
3. perform the later approved schema evolution;
4. apply these semantic decisions;
5. validate identity, uniqueness, references, snapshots, revisions, Sessions, history, and exception counts;
6. mark the semantic version complete in the same durable boundary as final validation;
7. expose target UI only after success.

Interrupted re-entry uses stable migration identity and invariants, not timestamps alone. Failure preserves the original store and reports a non-success state. An empty recreated store or in-memory store cannot be presented as successful Product State recovery.

### 13.9 Rollback

- Before semantic completion, retry or recovery starts from the protected original-store boundary.
- After target writes, a legacy-authority binary must not open the store for normal mutation.
- Operational rollback uses a forward-compatible build capable of reading target state and disabling affected UI without reactivating legacy authority.
- Restoring the pre-migration backup is a separate explicit recovery action with a warning that post-migration user changes will be lost.
- Compatibility storage retention is not permission for reverse migration or mixed authority.

---

## 14. Compatibility Decisions

### 14.1 Transitional reads

Before cutover:

- legacy values may be read only by migration, characterization, or the one-way compatibility boundary;
- target code cannot fall back to a legacy value when target data is missing;
- missing target data is an explicit migration/recovery error.

After cutover:

- no Product State selection, filtering, routing, plan input, Session input, history inference, Map input, notification input, or UI state reads `ShoppingItem.isCompleted`, entry `isChecked`, or legacy UUID arrays as authority.

### 14.2 Transitional writes

If an internal pre-release build must mirror target values:

- the named target command commits first and is the sole decision owner;
- the mirror is target-derived in the same local transaction;
- there is no reverse synchronization;
- no view or compatibility service writes the target from a legacy change;
- the mirror cannot restore, delete, resolve, reopen, purchase, or choose a list.

### 14.3 Semantic and physical retirement

- Semantic retirement occurs at the single Phase 7 authority cutover.
- At that point, legacy-authority reader count and direct-writer count are zero.
- Physical fields/models may remain read-only for all of v1.0.3.
- Their removal requires a later separately approved and tested schema migration.
- No support-window duration may delay semantic retirement.

### 14.4 Compatibility consumers

- Map and notification surfaces receive revisioned projections from list/Session owners.
- Scanner and catalog persistence receive typed active/tombstone/create outcomes.
- Saved locations are legacy note/reminder evidence under D-23.
- Product History compatibility aggregates are labeled legacy and never purchase authority.
- Unknown or stale payloads navigate safely but cannot mutate Product State.

---

## 15. Atomic Transaction Boundaries

### 15.1 General rule

All authoritative local mutations caused by one user intent either commit together or do not occur. UI success, history, list revision, and compatibility output cannot disagree about the commit.

External operating-system side effects—notification scheduling, geofence registration, analytics, and haptics—are not part of the SwiftData business transaction. They observe the committed identity/revision through an idempotent post-commit reconciliation path.

### 15.2 Command boundaries

| Command | Required authoritative local commit |
| --- | --- |
| Add to named list | Entry creation/state, list revision, need-added history event. |
| Resolve list need | Entry reason/time/provenance, list revision, resolution history event. |
| Reopen list need | Entry state, list revision, reopen history event. |
| Remove from named list | Membership removal, list revision, membership-removed history event. |
| Remove from Product Library | Active-Session precondition; Product tombstone; all editable-list membership removals; one revision increment per affected list; Product/list history events. |
| Restore to Product Library | Product lifecycle transition and restore history event; no list mutation. |
| Start Session | Validated source list/revision/plan identity, immutable Session snapshot/lines, and initial Session revision. The detailed Session lifecycle remains governed by WT-030B. |
| Finish Session | The complete boundary in §15.3. |

### 15.3 Finish boundary

The Finish transaction must:

1. validate the Session is non-terminal and at the expected Session revision;
2. validate all line IDs and final outcomes;
3. reject any unresolved migrated line or protected-source inconsistency;
4. persist every final Session-line outcome;
5. resolve or retain each exact source entry according to §9.2;
6. increment each affected list revision once;
7. append idempotent Product History events;
8. invalidate or supersede source plans according to their list/revision contract;
9. mark the Session finished with its final revision and time;
10. commit once.

If any step fails, none is authoritative. Notification/geofence disarm occurs after commit and retries safely from the committed Session identity/revision.

### 15.4 Migration boundary

Semantic migration completion is atomic with final invariant validation. Batch mechanics may be used later for measured scale, but no partially migrated store becomes writable and no batch completion may imply overall semantic completion.

---

## 16. Decision Impact Analysis

### 16.1 UX

- Product Library becomes unambiguously permanent and loses completion-style controls.
- List actions name their list and distinguish Resolve from Remove.
- Resolved entries remain discoverable without becoming another list.
- Collected and Purchased become distinct.
- Finish becomes a short reconciliation step but prevents silent data loss.
- Removed Products are recoverable and cannot silently reappear.

### 16.2 Architecture

- One authority exists per lifecycle.
- Named commands replace view-owned mutation.
- Product, list, plan, Session, history, catalog, location, Map, and notification boundaries remain orthogonal.
- No global Product enum or full event-sourced application is introduced.

### 16.3 Persistence and migration

- A target event history and explicit list/session semantics require later schema design.
- Migration preserves stable IDs/snapshots and makes ambiguity visible.
- Cutover cannot use runtime reverse backfill.
- Original-store protection and forward-compatible rollback are release gates.

### 16.4 Shopping and Sessions

- Each Session has one source list but may follow a multi-store plan.
- Active snapshots do not drift.
- Source-entry protection avoids lost-update reconciliation.
- Finish can reliably resolve or retain exact source entries.
- Abandonment does not overclaim Product outcomes.

### 16.5 Catalog, scanner, Map, and notifications

- Catalog and scanner identify acquisition intent without owning lifecycle.
- Map consumes exact plan/Session/list context.
- Notifications deep-link to their owner and validate revision.
- Saved-location data stops acting as a shadow Shopping list.

### 16.6 Accessibility and localization

- State is never conveyed by checkmark, icon, or color alone.
- Controls announce Product, named scope, current meaning, and action.
- English/Hebrew base vocabulary is fixed.
- Dynamic Type and RTL must retain reason and scope labels.

### 16.7 Performance and reliability

- Scoped list queries replace full-library compatibility filtering.
- Revision comparison is cheaper and more reliable than rebuilding content signatures as authority.
- Migration may add launch cost once; normal launches must not rerun semantic backfill.
- Immutable snapshots add bounded storage proportional to plan/Session lines and protect recovery.

### 16.8 Testing

Later specifications must translate these decisions into:

- command transition and idempotency evidence;
- multi-list isolation and uniqueness evidence;
- list-revision and stale-plan evidence;
- active-Session protection and snapshot evidence;
- full Finish outcome/rollback evidence;
- V1/V2/V3 migration fixtures covering every ambiguity class;
- legacy-authority zero-reader/zero-writer enforcement;
- English/Hebrew, RTL, Dynamic Type, VoiceOver, and non-color evidence.

### 16.9 Future parity

The decisions use IDs, revisions, explicit outcomes, and snapshots rather than iOS-only UI concepts. They are suitable for future Android and Cloud contracts. Conflict resolution, serialization, and sync are deferred; future platforms may not redefine Product completion or allow a second lifecycle authority.

### 16.10 AI and Community

- AI may suggest a list command or Finish outcome but cannot commit it without the approved user-intent policy.
- AI may not infer purchase from collection or legacy completion.
- Community Evidence may not remove, restore, resolve, purchase, or change Product/Catalog Truth.

---

## 17. Decision Traceability

Downstream specification roles:

- **PS-Domain:** Product/list/history command and projection specification.
- **PS-Migration:** schema, semantic migration, recovery, and rollback specification.
- **PS-Session:** WT-031A/WT-031B shared Session-line and Finish integration specification.
- **PS-UX:** Product/Shopping/Home/Map/notification/scanner accessibility and localization specification.
- **PS-Cutover:** single-authority release, compatibility retirement, and qualification specification.

These role names identify consumers; they do not create implementation tasks or authorize files.

| Decision | Originating WT-030A section | WT-031A blocker or gate resolved | Phase affected | Expected consuming specification |
| --- | --- | --- | --- | --- |
| D-01 | §§13.1–13.4, 14.1, 15 | BI-01, global-completion authority defect | P3–P7 | PS-Domain, PS-UX, PS-Cutover |
| D-02 | §§13.5, 15.2 | BI-01 | P2–P5 | PS-Domain, PS-Migration, PS-Session |
| D-03 | §§13.7–13.8, 14.5 | BI-02 | P5 | PS-Session, PS-UX |
| D-04 | §§13.7, 15.4 | BI-03 | P5 | PS-Session, PS-Domain |
| D-05 | §§13.7, 15.4 | BI-04 | P5 | PS-Session |
| D-06 | §13.8 | Product History ownership blocker; WT-031A §5.6 | P2–P5 | PS-Domain, PS-Migration |
| D-07 | §§13.3, 13.8, 17.2 | History-retention blocker | P2–P7 | PS-Domain, PS-Migration |
| D-08 | §§13.4–13.7 | BI-07, BI-13 | P2–P5 | PS-Domain, PS-Session, PS-UX |
| D-09 | §§13.5, 13.12, 15.2 | BI-09, BM-02 | P2–P4 | PS-Domain, PS-Migration |
| D-10 | §§13.5, 14.3 | BI-06, BI-08, BI-09 | P2–P4 | PS-Domain, PS-UX, PS-Migration |
| D-11 | §§13.5–13.6, 15.2–15.3 | durable revision/cutover gate | P2–P5 | PS-Domain, PS-Migration, PS-Session |
| D-12 | §§13.6–13.7 | immutable snapshot blocker; WT-031A §5.4–5.5 | P3–P5 | PS-Domain, PS-Session |
| D-13 | §§13.7, 15.4 | BI-12 | P3–P5 | PS-Domain, PS-Session, PS-UX |
| D-14 | §§13.7, 15.4 | BI-11, BI-13 | P5 | PS-Session, PS-UX |
| D-15 | §§13.3, 15.1 | BI-05 | P2–P4 | PS-Domain, PS-Migration, PS-UX |
| D-16 | §§13.3, 13.7 | Product-removal/active-Session blocker | P3–P5 | PS-Domain, PS-Session, PS-UX |
| D-17 | §§13.3, 14.8, 15.1 | BI-10, BI-17, BI-18 | P2–P4 | PS-Domain, PS-Migration, PS-UX |
| D-18 | §§13.3, 19 | restore-after-deletion and retention blocker | P3–P4 | PS-Domain, PS-UX |
| D-19 | §§13.5, 13.8, 14.3 | BI-06, BM-07 | P2–P4 | PS-Domain, PS-Migration, PS-UX |
| D-20 | §§14.1–14.10 | BI-19, BI-20 | P4–P6 | PS-UX |
| D-21 | §§14.7, 15.5 | BI-14, BI-15 | P4–P5 | PS-UX, PS-Session |
| D-22 | §§14.8, 15.1 | BI-16, BI-17, BI-18 | P3–P4 | PS-Domain, PS-UX |
| D-23 | §§5.14, 13.11 | BI-21 | P2–P5 | PS-Migration, PS-Domain, PS-UX |
| D-24 | §17 | BM-09; migration-owner gate | P2 | PS-Migration |
| D-25 | §17.3 | BM-01 | P2 | PS-Migration |
| D-26 | §§13.12, 17.3–17.4 | BM-02 | P2 | PS-Migration |
| D-27 | §§11.6, 17.3 | BM-03, BM-04 | P2, P6 | PS-Migration, PS-UX |
| D-28 | §17.3 | BM-05 | P2, P5 | PS-Migration, PS-Session |
| D-29 | §15.4 | BM-06 | P2, P5 | PS-Migration, PS-Session, PS-UX |
| D-30 | §§13.5, 13.8, 17.3 | BM-07 | P2–P4 | PS-Migration, PS-Domain, PS-UX |
| D-31 | §§13.8, 17.3 | BM-08 | P2–P5 | PS-Migration, PS-Domain |
| D-32 | §§13.3, 17.3 | BM-12 | P2, P5 | PS-Migration, PS-Session |
| D-33 | §§17.1, 17.5 | compatibility retirement/support-window gate | P3–P7 | PS-Cutover, PS-Migration |
| D-34 | §§5.13, 17.4 | BM-10, BM-11 | P2, P6–P7 | PS-Migration, PS-Cutover |
| D-35 | §§13.11–13.12, 15 | atomic Product/list command gate | P3–P4 | PS-Domain |
| D-36 | §§13.7–13.8, 15.4 | BI-22 | P5 | PS-Session, PS-Domain |
| D-37 | §13.12 | BI-23 | P1–P3 | PS-Domain, PS-Migration |

All WT-031A “blocking before implementation” IDs BI-01…BI-23 and “blocking before migration” IDs BM-01…BM-12 have a decision or an explicit implementation-specification boundary above. None remains an unowned Product policy alternative.

---

## 18. Dependencies

### 18.1 Binding documents

- `docs/Audits/1.0.3/WT-030A_ProductStateUXAudit.md`
- `docs/Audits/1.0.3/WT-030_ArchitectureSummary.md`
- `docs/ImplementationPlans/1.0.3/WT-031A_ProductStateImplementationPlan.md`
- `design/v1.0/WayTask_Product_Specification_v1.0.pdf`

### 18.2 Cross-audit dependencies

- WT-030B and WT-031B must consume D-03–D-05, D-12–D-14, D-16, D-21, D-28–D-29, and D-36 without creating a competing line or Finish authority.
- WT-030C and WT-031C must preserve D-01, D-06, and the rule that Community Evidence cannot mutate Product/list/Session/history truth.

### 18.3 Technical dependencies for later specifications

- supported SwiftData versioned-schema and custom-migration capabilities;
- service-level command serialization on every minimum-supported iOS version;
- recoverable handling of the store and sidecars;
- stable Product, list, entry, plan, Session, line, and event identifiers;
- exact catalog ID/redirect and user snapshot contracts;
- forward-compatible release rollback;
- existing migration and persistence characterization fixtures;
- final Version 1.0.3 Product Specification reconciliation before release.

### 18.4 Required implementation-specification relationship

The eventual Product State implementation specification must be co-reviewed with the WT-031B-derived Session implementation specification. Neither may define a different:

- source-list identity;
- list revision contract;
- Session line identity;
- collected meaning;
- final outcome taxonomy;
- Finish transaction owner;
- active-Session Product-removal policy.

---

## 19. Open Decisions Remaining

No Product State policy blocker from WT-031A remains open. The following are deliberately left to later approved specifications because resolving them here would design implementation or exceed WT-030A authority.

| ID | Remaining decision | Classification | Fixed boundary from this specification |
| --- | --- | --- | --- |
| OD-01 | Exact SwiftData models, attributes, relationships, indexes, migration stages, and project files. | Blocking before production implementation. | Must represent D-01–D-37; may not introduce mixed authority. |
| OD-02 | Exact transaction/serialization mechanism used to enforce D-37 on supported iOS versions. | Blocking before production implementation. | Command-level invariant is mandatory even without a database constraint. |
| OD-03 | Exact original-store copying, validation, disk-space, and sidecar procedure. | Blocking before migration implementation. | Must satisfy D-24 and D-34; silent empty-store recovery is prohibited. |
| OD-04 | Exact exception-ledger representation and recovery-screen copy. | Blocking before migration implementation. | Unknown rows remain preserved, excluded from authority, and visible as exceptions. |
| OD-05 | Exact notification payload format and legacy payload support duration. | Blocking before release. | Payload must carry owner/revision and cannot mutate lifecycle; semantic legacy authority ends at cutover. |
| OD-06 | Exact privacy-erasure, backup-retention, and legal policy. | Non-blocking for Product State implementation; blocking before physical-erasure work. | Tombstone retention and history preservation remain binding until separately approved. |
| OD-07 | Production-scale fixture sizes and measured performance thresholds beyond WT-030A AC-43. | Blocking before release qualification. | Correctness and recoverability may not be traded for performance. |
| OD-08 | Final sentence-level English/Hebrew grammar, plurals, and bidirectional QA. | Blocking before release. | §5.5 semantic base labels and meanings cannot change. |
| OD-09 | Official Version 1.0.3 Product Specification publication/reconciliation. | Blocking before release. | WT-030A and this specification govern Product State meanwhile. |
| OD-10 | Future Archive and physical compatibility-storage removal release. | Non-blocking follow-up. | Neither is part of v1.0.3 Product State authority. |
| OD-11 | Cloud/Android event serialization and conflict policy. | Deferred. | Must preserve stable identity, scoped ownership, explicit outcomes, and no global completion. |
| OD-12 | Future AI suggestion/confirmation policy and replenishment learning eligibility. | Deferred. | AI is not Product/list/history authority and may not infer purchase. |

These items do not reopen an approved outcome in the Decision Matrix.

---

## 20. Implementation Authorization Checklist

This checklist gates later specifications and code authorization. Checked items mean the decision prerequisite is complete; unchecked items confirm that implementation is still unauthorized.

### 20.1 Decision readiness

- [x] WT-030A Orthogonal Product Lifecycle remains unchanged.
- [x] Product completion has one decision.
- [x] Finish behavior and every final outcome have one decision.
- [x] Product History ownership and retention have one decision.
- [x] Restore, Product removal, and active-Session interaction have one decision.
- [x] Multiple lists, duplicate entries, resolved entries, and reopening have one decision.
- [x] List revision and immutable snapshot behavior have one decision.
- [x] Every BI-01…BI-23 blocker maps to an approved decision.
- [x] Every BM-01…BM-12 blocker maps to an approved decision or prohibited schema-design boundary.
- [x] Compatibility semantic retirement and one authority cutover are fixed.
- [x] Product State and WT-031B share one required Finish boundary.

### 20.2 Repository-scope verification

- [x] The current inventory was verified against repository types and call sites rather than assumed.
- [x] Correct Product UUID, tombstone, catalog snapshot, and Product Knowledge ownership is retained.
- [x] No previous WT document is changed by this specification.
- [x] No production source, test, schema, project, or catalog change is part of this specification.
- [x] The only repository artifact produced by WT-032A is this document.
- [x] Section 21 contains the single permitted final disposition.

### 20.3 Gates still required before production implementation

- [ ] One or more approved implementation specifications define exact models, APIs, files, migration mechanics, and test evidence.
- [ ] The WT-031B-derived implementation specification adopts the same Session-line and Finish contract.
- [ ] SwiftData and command-serialization mechanisms are proven on every supported iOS version.
- [ ] Migration fixtures, original-store recovery, and forward-compatible rollback are specified and approved.
- [ ] Accessibility/localization behavior and exact UI copy are specified and reviewed.
- [ ] Static enforcement for zero legacy-authority readers/writers is specified.
- [ ] Implementation authorization is explicitly granted by a later approved specification.

WT-032A authorizes decision consumption only. It does not authorize production code changes.

---

## 21. Terminal Decision

**READY FOR IMPLEMENTATION SPECIFICATION**

WT-032A resolves the Product State policy and migration interpretation decisions required to write the next implementation specification. Implementation remains unauthorized until later approved implementation specifications resolve the technical items in §19, satisfy §20.3, preserve the single-authority cutover, and explicitly authorize production work.
