# WT-031B — Shopping Session Implementation Specification

**Product:** WayTask iOS  
**Version:** 1.0.3  
**Document type:** Implementation contract  
**Status:** Final re-gate candidate  
**Authority:** WT-030, WT-031A, WT-031B, WT-032A D-01 through D-37, WT-032B, and WT-033A S-00 through T-00  
**Implementation authorization:** Not granted by this document  
**Permitted change:** This documentation artifact only

---

## Contract Status and Interpretation

This specification closes the Shopping Session policy, identity, lifecycle,
outcome, Finish, recovery, and migration-definition gaps recorded by WT-033A
T-00. It is the co-review contract for WT-033A T-02, T-08, and T-19.

The following precedence applies:

1. WT-032A D-01 through D-37 remain binding and are not redefined here.
2. WT-030 and WT-031A define domain ownership.
3. This specification selects the parameters and exception policies left open
   by WT-031B.
4. WT-033A S-01 and S-02 define the implementation authority layers and
   execution sequence.
5. If an implementation choice cannot satisfy all of the above, implementation
   stops for re-gating; it does not reinterpret this contract.

“Must” and “shall” are normative. Examples are explanatory. This document
defines no Swift, API signature, physical schema, migration stage, test change,
project change, entitlement, or production behavior.

---

## 1. Executive Summary

### 1.1 Purpose

The purpose of this specification is to give Product State and Shopping Session
one implementation-grade definition of:

- the durable Session aggregate and its identities;
- lifecycle and recovery semantics;
- immutable lines and snapshots;
- provisional collection and final outcomes;
- atomic Finish reconciliation;
- legacy Session preservation and recovery;
- repository and integration responsibilities.

It removes the WT-031B uncertainty that caused WT-033A T-00 to stop before
T-01.

### 1.2 Goals

The contract shall:

1. preserve the Session-Scoped Persistent Hybrid architecture;
2. use one source list and one captured source revision per Session;
3. keep a started execution snapshot stable and offline-readable;
4. separate Session execution state from final Product State outcomes;
5. reconcile every target-created line exactly once at Finish;
6. preserve legacy evidence without inventing purchase, resolution, identity,
   provenance, or history;
7. provide deterministic conflict, expiration, recovery, and migration rules;
8. keep notifications, location, Map, planning, discovery, Camera, and AI as
   consumers or command initiators rather than Session authorities;
9. give WT-033A T-02, T-08, and T-19 the same semantic persistence graph.

### 1.3 Non-goals

This specification does not:

- authorize implementation;
- define Swift types or APIs;
- define a SwiftData schema, attributes, relationships, indexes, or migration
  stages;
- change V1, V2, or V3;
- implement or modify production, tests, project settings, packages,
  capabilities, entitlements, localization resources, or catalog artifacts;
- introduce Update Session, passive nearby shopping, Cloud synchronization,
  multi-device ownership, cross-list Sessions, continuous background location,
  background planning, inventory truth, or automatic AI actions;
- reopen any Product State outcome approved by D-01 through D-37.

### 1.4 Implementation boundary

This is a semantic and transactional contract. The later WT-033A steps may
choose physical representation and internal composition only if they preserve:

- every identity and invariant in Sections 2–5;
- the single atomic boundary in Section 6;
- the recovery and conversion rules in Sections 7–8;
- the ownership and integration limits in Sections 9–10;
- the acceptance and traceability requirements in Sections 11–12.

No released build may expose both legacy and target Session authority.

---

## 2. Session Lifecycle

### 2.1 Lifecycle states

| State or condition | Definition | Allowed business transitions | Reminder authority | Terminal |
|---|---|---|---|---|
| **No Session** | Absence of a non-terminal aggregate. It is not a persisted state. Terminal history may still exist. | Explicit Start → Active. | None. | Not applicable. |
| **Active** | Durable execution authority for one frozen source-list/plan snapshot. | Collect, Undo, stop activity; Finish → Finished; Abandon → Abandoned; due expiration → Expired. | May derive reminders from the current Session revision when the user enabled them and device capability permits. | No. |
| **Expired** | Durable, non-terminal Session whose automatic active-authority window ended. Progress and snapshot remain intact. | Explicit Resume → Active; explicit Abandon → Abandoned. | None. | No; resumable. |
| **Finished** | Successful atomic reconciliation committed for every target-created line. | Read-only summary/history. | None. | Yes. |
| **Abandoned** | Explicit user termination without list resolution or Product History outcomes. Snapshot and provisional progress remain historical evidence. | Read-only summary. | None. | Yes. |

There is no `paused` Session state in v1.0.3. Backgrounding, suspension, system
termination, reboot, force quit, notification denial, loss of location
capability, offline operation, and opening another screen do not pause or
otherwise transition a Session.

### 2.2 Creation and Start

Start is explicit and is valid only when:

1. durable persistent authority is available;
2. no active, expired, or unresolved active-claim recovery candidate blocks
   creation;
3. the source is exactly one named list;
4. the plan carries that list ID, an exact durable list revision, and exact
   source-entry IDs;
5. the plan entry set still identifies eligible Needed entries;
6. the plan satisfies the freshness rule in Section 10.3;
7. at least one line and one usable planned stop can be frozen;
8. all target-created lines have exact source-entry and Product identities;
9. the complete Session header, execution snapshot, stops, and lines can commit
   together.

Successful Start creates an Active Session at revision 1. A partial aggregate
is never authoritative. Reminder enrollment occurs only after Start commits and
cannot roll back or invalidate the Session.

### 2.3 Expiration policy

The v1.0.3 policy snapshot is:

- **inactivity threshold:** 12 hours after `lastActivityAt`;
- **maximum automatic active-authority window:** 72 hours after the current
  activation began;
- **due boundary:** expiration is due when the authoritative clock is greater
  than or equal to the earlier boundary;
- **evaluation:** before every Session command, on cold launch, on foreground
  recovery, and during a validated background event;
- **no suspended timer:** no timer or background process is required to fire at
  the boundary.

Start begins the first activation window. Explicit Resume begins a new
activation window and records the prior expiration evidence. Thus no Session
can remain Active for more than 72 hours without renewed explicit user intent;
the aggregate itself is not automatically deleted.

Only these committed user actions update meaningful activity:

- Collect or Undo;
- selecting, completing, or skipping a stop through a Session command;
- starting external navigation for a frozen Session stop;
- explicit Resume.

Start supplies the initial timestamps. Foregrounding, opening the Session,
opening Finish review, changing a non-authoritative review draft, receiving a
location event, scheduling a notification, capability changes, network refresh,
and failed commands do not update meaningful activity.

### 2.4 Finish, Abandon, and terminal state

- Finish is permitted only from Active and only through Section 6.
- Abandon is permitted from Active or Expired after explicit confirmation.
- Abandon preserves the frozen snapshot and provisional collection, writes no
  Product History event, and changes no Product, list entry, or list revision.
- Finished and Abandoned are the only terminal lifecycle states.
- Terminal status is derived from lifecycle state; it is not an independent
  mutable flag.
- `endedAt` exists semantically only for Finished or Abandoned.
- Expired is not terminal and blocks a new Start until Resume or Abandon.

Finished, Abandoned, and Expired Session aggregates have no automatic retention
expiry in v1.0.3. Expired progress remains until the user resolves it. Product
History retention continues to follow D-07. A future privacy-erasure policy
requires separate approval.

### 2.5 Resume

Resume:

1. is an explicit command from Expired only;
2. validates expected Session identity/revision and aggregate integrity;
3. preserves every committed line execution value and frozen snapshot;
4. begins a new 72-hour activation window;
5. sets `lastActivityAt` to the committed Resume time;
6. increments Session revision once;
7. evaluates reminder intent and capability after commit;
8. creates registrations for the new revision rather than reusing old ones.

Opening an already Active Session after relaunch is recovery, not Resume, and
does not change its revision or activity timestamp.

### 2.6 Recovered and migration state

`Recovered` is a recovery result, not a business state. Recovery may publish:

- no resumable Session;
- restored Active Session;
- Expired Session requiring Resume or Abandon;
- multiple-candidate conflict;
- legacy-incomplete Session;
- unresolved migration evidence;
- recreated-store mode;
- in-memory degraded mode;
- unrecoverable aggregate.

Migration condition is also orthogonal to lifecycle:

| Migration condition | Meaning |
|---|---|
| **Native** | Created under the target contract with exact identities and complete snapshots. |
| **Legacy mapped** | Legacy evidence mapped deterministically with sufficient integrity for the stated lifecycle. |
| **Legacy incomplete** | A lifecycle can be shown, but one or more historical source, plan, stop, line, or outcome facts were never persisted. Gaps remain explicit. |
| **Legacy unresolved** | Contradictory or unprovable evidence is preserved outside normal authority until explicit recovery or support-safe disposition. |

Recovery alone does not change lifecycle, activity, or revision. A recovery-time
Expire, Resume, Abandon, or repair is a separate named command with its own
commit.

### 2.7 Binding transition matrix

| Command | Valid source | Target | Revision effect | Product/list/history effect |
|---|---|---|---|---|
| Start | No non-terminal conflict | Active | Initial revision 1 | None. |
| Collect | Active | Active | +1 | None. |
| Undo | Active | Active | +1 | None. |
| Stop activity | Active | Active | +1 when authoritative state/activity changes | None. |
| Expire | Active and due | Expired | +1 | None. |
| Resume | Expired | Active | +1 | None. |
| Finish | Active | Finished | +1 in the one Finish transaction | Section 6 reconciliation. |
| Abandon | Active or Expired | Abandoned | +1 | None. |
| Recovery open | Any persisted state | Same | None | None. |
| Region event / notification tap | Any | Same, except a separately committed due Expire | None unless Expire commits | None. |

Terminal state wins every race. A due Expire suppresses a reminder. A committed
Finish wins over a concurrent Expire. Revision mismatch suppresses background
work and causes foreground commands to reload.

---

## 3. Session Identity

### 3.1 Identity contract

| Identity | Contract |
|---|---|
| **Session identity** | A stable, globally unique identifier created once and never reused. It identifies one shopping journey across lifecycle, recovery, history, and reminder cleanup. |
| **Source List identity** | The stable ID of exactly one named Shopping List. Presentation selection or a default-list title is not source identity. |
| **Source Revision** | The durable monotonic list revision captured by the source plan at Start. A target-created Session requires an exact value. Legacy conversion may carry the explicit provenance `legacyUnknown`; it may not fabricate a historical value. |
| **Session revision** | A durable monotonic value scoped to the Session. Start uses 1. Every successful business-state commit increments it exactly once; no-op retries, reads, capability checks, and post-commit reminder work do not increment it. |
| **Snapshot identity** | A stable, globally unique identity for the frozen execution snapshot plus generation 1 and a deterministic content signature. Update Session is excluded, so v1.0.3 never replaces the snapshot or creates generation 2. |
| **Line identity** | A stable, globally unique Session-line ID created at Start or deterministic legacy conversion. It is the only normal Session line command key and never equals or aliases a legacy compatibility-item ID. |

### 3.2 Source revision rules

- The source plan and Session must carry the same list ID, exact revision, and
  exact captured entry IDs at Start.
- A later list revision does not rewrite the Session.
- New list entries may be added while a Session is Active but remain outside
  the snapshot.
- Captured entries cannot be removed, resolved, reopened, or quantity-edited
  outside Session commands while the Session is non-terminal.
- Finish validates the current expected list revision obtained for Finish
  review; it does not require the current revision to equal the historical
  source revision.
- `legacyUnknown` is provenance, not revision zero, a random revision, or the
  current list revision.

### 3.3 Snapshot identity and content

The execution snapshot signature covers, in a canonical order:

- Session and snapshot identity/version;
- source list identity and source-revision provenance;
- source plan identity, signature, and evidence time;
- exact ordered line identities, source-entry identities, Product identities,
  quantity snapshots, and display snapshots;
- exact ordered stop identities, store-reference provenance, display/location
  snapshots, and line assignments.

Mutable collection state, final outcomes, lifecycle, activity timestamps,
capability state, and reminder registrations are not part of the frozen content
signature.

### 3.4 Command and history identity

Every mutation has a stable command identity for idempotency. Finish history
event identity is deterministically bound to the Finish command, Session, line,
and final outcome. A retry may return the existing committed result but may not
create a second Session, revision increment, list revision increment, or
history event.

---

## 4. Session Line Model

### 4.1 Ownership and semantic graph

One Session owns one frozen execution snapshot, one or more stops, and one or
more lines for target-created Sessions. Each line belongs to exactly one
Session and references exactly one captured source entry and Product. Migration
exceptions may lack a provable source or Product reference, but the line and
all available evidence remain owned by the Session and are never silently
dropped.

The implementation-grade semantic graph is:

```text
Session 1 ── 1 Execution Snapshot
Session 1 ── 1...n Session Stops        (native Sessions)
Session 1 ── 1...n Session Lines        (native Sessions)
Session Line ── 1 captured Source Entry (native Sessions)
Session Line ── 1 captured Product      (native Sessions)
Session 1 ── 0...n migration exceptions
Session revision ── 0...n device-local reminder registrations
```

The physical persistence graph is chosen and proved by WT-033A T-02. It may
not weaken these ownership or cardinality rules.

### 4.2 Frozen snapshot and immutable fields

For a native line, these values are immutable after Start:

- line ID and owning Session ID;
- source list ID, source revision provenance, and source-entry ID;
- Product ID and Global Product Concept ID when one existed;
- Product display snapshot needed for offline presentation;
- quantity/unit/note snapshot approved for Session display;
- initial assigned stop ID and ordering;
- snapshot provenance and version.

Later Product, Catalog, list, plan, discovery, Store, Camera, AI, or community
changes do not rewrite these values.

### 4.3 Mutable fields

Session execution and final disposition are separate:

- **execution state:** `remaining` or `collected`;
- **final outcome:** unset until successful Finish, then exactly one of
  `purchased`, `alreadyHave`, `noLongerNeeded`, `unavailable`, `skipped`, or
  `carriedForward`;
- **execution timestamp:** changed by a successful Collect or Undo;
- **final outcome timestamp/provenance:** written only by successful Finish;
- **legacy disposition:** optional migration-only `legacyUnknown`, never a
  selectable native outcome.

This separation is the binding harmonization of WT-031B with D-03 and D-04.
The older WT-031B conceptual use of one “outcome” property for `collected` and
final dispositions must not survive into the target model.

### 4.4 Collection and Undo

Collect changes exactly one line from Remaining to Collected. Undo changes
exactly one line from Collected to Remaining. Both:

- require Active lifecycle, expected Session revision, and line identity;
- update meaningful activity;
- commit atomically and increment Session revision once;
- are idempotent by command identity;
- create no Product, list, plan, or Product History effect;
- cause reminder projection reconciliation only after commit.

Collected is provisional basket evidence. It is not purchase, list resolution,
Product completion, inventory truth, or history.

### 4.5 Finish review draft

Finish review may propose Purchased for Collected lines. The proposal and any
uncommitted review choices are presentation draft state, not authoritative
line outcomes. Every choice remains editable until the user confirms Finish.
Opening or editing the review does not mutate Session revision or activity.

### 4.6 History

Only successful Finish appends target Product History events for line outcomes.
Each event is immutable, keyed by stable Product UUID, and carries exact source
list, source entry, Session, line, outcome, time, provenance, and approved
display snapshot identity.

Collect, Undo, Expire, Resume, Abandon, recovery, reminder delivery, Map use,
Camera recognition, and AI suggestions append no Product History outcome.

---

## 5. Outcome Vocabulary

### 5.1 Normal final outcomes

| Outcome | Meaning | History effect | Source-list effect | Product effect | Session effect | Plan effect |
|---|---|---|---|---|---|---|
| **Purchased** | The user explicitly confirms at Finish that the item was purchased. Collection alone is insufficient. | Append one `purchased` outcome event. | Resolve the exact entry as `purchased`. | No Product Library or Product identity change. | Store final outcome; contribute to purchased summary. | Finish invalidates/supersedes the exact source plan. Future plans exclude the resolved entry unless reopened. |
| **Already Have** | The user confirms the need is satisfied by something already owned; it is not a purchase. | Append one non-purchase `alreadyHave` outcome event. | Resolve the exact entry as `alreadyHave`. | No Product Library or Product identity change. | Store final outcome; contribute to non-purchase resolved summary. | Invalidate/supersede the source plan. Future plans exclude the resolved entry unless reopened. |
| **No Longer Needed** | The user intentionally cancels this need; it is not a purchase. | Append one non-purchase `noLongerNeeded` outcome event. | Resolve the exact entry as `noLongerNeeded`. | No Product Library or Product identity change. | Store final outcome; contribute to non-purchase resolved summary. | Invalidate/supersede the source plan. Future plans exclude the resolved entry unless reopened. |
| **Unavailable** | The user records a Session-scoped observation that the item was unavailable. It does not establish Store inventory truth. | Append one `unavailable` Session observation. | Keep the exact entry Needed. | No Product Library, Catalog, or Store Truth change. | Store final outcome; contribute to unresolved-need summary. | Invalidate/supersede the source plan. A future plan may include the Needed entry. |
| **Skipped** | The user chose not to address this line in this Session without asserting future intent beyond the still-Needed entry. | Append one `skipped` Session outcome. | Keep the exact entry Needed. | No Product Library or Product identity change. | Store final outcome; contribute to unresolved-need summary. | Invalidate/supersede the source plan. A future plan may include the Needed entry. |
| **Carry Forward** | The user explicitly confirms that the need should remain for a later Session. This is a final Session outcome, not an in-Session stop handoff. | Append one `carriedForward` Session outcome. | Keep the exact entry Needed. | No Product Library or Product identity change. | Store final outcome; contribute to carried-forward summary. | Invalidate/supersede the source plan. A future plan may include the Needed entry. |

No normal outcome removes or restores a Product, changes another list, changes
Catalog or Store Truth, or becomes a global Product completion state.

### 5.2 Legacy Unknown

**Legacy Unknown** is not a seventh normal Finish outcome. It is a
migration-only marker meaning that legacy data indicates a resolved-like or
terminal historical condition but does not prove which normal outcome occurred.

Its effects are:

- **History:** no purchased or normal target outcome event is created. An
  already-provable migration activity reference permitted by D-30 may remain
  explicitly labeled legacy.
- **List:** Session migration alone performs no retrospective list mutation. A
  checked legacy entry is handled independently by D-25 as list resolution
  `legacyUnknown`.
- **Product:** no Product state effect.
- **Session:** preserve the historical line and execution evidence; mark it
  legacy-incomplete and exclude it from normal outcome metrics.
- **Plan:** no reconstructed historical plan effect.

Users cannot select Legacy Unknown for a native Session. A non-terminal
unresolved migrated line must be repaired to exact identity before Finish or the
Session must be explicitly Abandoned.

### 5.3 Whole-Session Finish choices

- Every line receives exactly one normal final outcome.
- Collected lines are proposed as Purchased but remain editable.
- Remaining lines have no silent default.
- The user may explicitly apply Carry Forward to all Remaining lines in one
  reversible review action.
- Bulk Carry Forward never changes Collected lines.
- An in-Session handoff to a later stop is routing, not the final Carry Forward
  outcome.

---

## 6. Finish Transaction

### 6.1 Validation

Finish validation shall prove:

1. persistent authority is durable and writable;
2. command identity is present and has not committed a different payload;
3. the Session exists, is Active, and matches the expected revision;
4. the current source list exists and matches the expected current list
   revision loaded for Finish review;
5. every submitted line ID belongs exactly once to the Session;
6. every Session line appears exactly once in the submission;
7. every line has one allowed normal final outcome;
8. no Legacy Unknown value was submitted as a native outcome;
9. every native line still has its protected exact source-entry and Product
   identity;
10. no migrated unresolved line or tombstone contradiction remains;
11. every source entry is still eligible for the required resolution or
    keep-Needed effect;
12. required history identities are unique and idempotent;
13. source-plan invalidation can join the same authoritative transaction.

Finish from Expired is invalid; the user must Resume first.

### 6.2 Required inputs

The semantic Finish request contains:

- stable command identity;
- Session ID and expected Session revision;
- source list ID and expected current list revision;
- one explicit `(line ID, final outcome)` decision for every line;
- explicit user confirmation and authoritative commit time;
- user/device provenance only to the extent already approved and required for
  local history.

No UI-owned model context, compatibility-item completion flag, Product name,
barcode, notification payload, runtime plan, or inferred collection value may
substitute for these inputs.

### 6.3 Conflict handling

| Conflict | Required result |
|---|---|
| Session revision changed | Commit nothing; reload the committed Session. Reapply still-valid review choices by stable line ID only after revalidation. |
| Current list revision changed | Commit nothing; reload list and Session authority. New uncaptured entries remain outside the Session; protected captured entries must still be intact. |
| Session already Finished by the same command | Return the existing committed result without duplicate events or revisions. |
| Session terminal through another command | Return an explicit terminal conflict; never reopen. |
| Missing, duplicate, foreign, or unresolved line | Block Finish and identify a safe recovery action; never drop the line. |
| Missing/tombstoned Product or protected-source contradiction | Block Finish as a migration/invariant conflict; do not restore or infer. |
| History or plan identity collision | Block and roll back the whole domain transaction. |

No “last write wins” behavior is permitted.

### 6.4 Atomic boundary

One coordinator-owned local transaction shall:

1. perform all validation;
2. persist one final outcome and outcome time for every line;
3. resolve Purchased, Already Have, and No Longer Needed source entries with
   the matching reason;
4. retain Unavailable, Skipped, and Carried Forward source entries as Needed;
5. increment the affected source list revision exactly once;
6. append exactly one immutable Product History outcome event per line;
7. invalidate or supersede the exact source plan;
8. set Session state to Finished, set `endedAt`, record the final summary, and
   increment Session revision exactly once;
9. commit once.

The Session Repository, Shopping Repository, History Repository, and plan
invalidation participant may not save independently inside Finish.

### 6.5 Post-commit work

After the authoritative commit:

- publish the Finished projection;
- make desired Session reminder registrations empty;
- cancel known pending notification requests;
- remove known delivered Session notifications;
- stop actual managed regions;
- retry any failed cleanup idempotently.

These operating-system side effects are not part of the domain transaction.
Cleanup failure cannot roll back Finish or make a late event valid; every late
event is suppressed by state/revision validation.

### 6.6 Failure behaviour and rollback

- Pre-commit validation or save failure exposes no success and no partial
  Product, list, history, plan, or Session effect.
- The transaction scope is discarded or reloaded from committed authority.
- UI optimism is cleared and the committed projection is shown.
- A retry with the same command identity is safe.
- External reminder cleanup does not begin before commit.
- A post-commit cleanup failure records only bounded projection failure and is
  retried; the successful Finish remains authoritative.
- Recovery never activates legacy Finish behavior or an old writer as rollback.

---

## 7. Resume and Recovery

### 7.1 Recovery order

Recovery shall execute in this order:

1. determine durable, recreated-store, or in-memory persistence mode;
2. complete the separately authorized schema/semantic migration and repair;
3. load every non-terminal or active-claim recovery candidate;
4. validate identities, revisions, snapshots, lines, stops, and exception
   evidence;
5. detect multiple candidates without selecting one;
6. evaluate deterministic expiration;
7. publish one typed recovery result;
8. evaluate reminder/location/notification capability;
9. reconcile desired, ledger, and actual registrations;
10. allow optional foreground refresh that cannot mutate the snapshot.

Notification permission is not consulted before the Session recovery result is
known.

### 7.2 Recovery candidates

Candidates include:

- one valid native Active or Expired Session;
- a deterministically mapped legacy active claim;
- multiple legacy active claims;
- an Active/Expired Session with legacy-incomplete evidence;
- contradictory legacy active evidence requiring explicit resolution;
- a malformed target aggregate preserved for support-safe handling.

Finished and Abandoned Sessions are history/deep-link targets, not normal
resume candidates. A legacy inactive record with no active claim remains an
archive/exception and does not block normal shopping.

### 7.3 Multiple Sessions, selection rules, and conflict rules

Normal target operation permits at most one non-terminal Session. Migration
may temporarily expose multiple recovery candidates.

Every Start request first resolves existing authority:

| Existing authority | Requested context | Required result |
|---|---|---|
| None | Valid plan | Offer normal Start confirmation. |
| Active, same exact Session/list/plan context | Same context | Offer Continue Existing. Opening it is not a lifecycle Resume and creates no new Session. |
| Active, different list/revision/plan/store context | Different context | Offer Continue Existing, Finish Existing, Abandon Existing, or Cancel. A new Start is available only after the existing Session becomes terminal. |
| Expired | Any context | Explain saved progress and offer Resume, Abandon, or Cancel. |
| Multiple active/non-terminal claims | Any context | Enter the recovery chooser below; no normal Start. |
| Finished/Abandoned history only | Valid plan | Offer normal Start confirmation. |

When more than one active/non-terminal claim exists:

- reminders for all candidates remain disarmed;
- Start and normal Session mutation remain blocked;
- the chooser displays every candidate, ordered newest `startedAt` first only
  for presentation;
- no candidate is auto-selected, auto-finished, auto-expired, or deleted;
- the user may choose one candidate to keep and must explicitly Abandon every
  competing active/non-terminal candidate, either individually or through one
  confirmation that names the count and effect;
- canceling the chooser preserves all candidates and the block.

The chosen candidate is then recovered in its validated lifecycle. If it is
Expired, the user still explicitly Resumes it.

### 7.4 Resume flow

The Resume flow:

1. displays frozen source/stop/line context and any legacy limitations;
2. validates minimum resumability and expected revision;
3. requires explicit confirmation;
4. applies Section 2.5 atomically;
5. publishes the recovered Active projection;
6. separately offers or evaluates Session reminder intent;
7. creates registrations only for the new revision.

Minimum resumability requires a stable Session ID, a coherent active/expired
claim, at least one stable line ID, unique line identities, readable line state
(a localized generic legacy label is sufficient), and no structural corruption
that would make mutation ambiguous. Valid stop coordinates are not required for
manual recovery, but their absence disables Map navigation and reminders.

### 7.5 Abandon flow

Abandon:

- requires Session ID, expected revision, and explicit confirmation;
- is valid from Active or Expired, including a selected legacy candidate;
- preserves snapshot and collection evidence;
- writes Abandoned and `endedAt`, incrementing Session revision once;
- performs no Product, list, list-revision, plan, or Product History mutation;
- releases the non-terminal Start block after commit;
- disarms/cancels reminder projections after commit.

There is no Product History “abandoned” event in v1.0.3. The retained Session
record is the abandonment evidence.

### 7.6 Recreated store and in-memory mode

When the persistent store was recreated:

- all WayTask-managed target and legacy regions are stopped;
- identifiable Session notifications are canceled;
- callbacks fail closed;
- the UI shows that local shopping data could not be opened and reminders are
  off;
- actions are limited to Retry, view privacy-safe support details, and an
  explicit quarantine-recovery path if a forward-compatible build supports it;
- “No active Session” is never presented as proof that no prior Session
  existed.

In in-memory fallback:

- creating or mutating a Shopping Session is blocked;
- reminders remain off;
- the UI may show read/manual reference content but may not claim durable save
  or recovery;
- existing managed regions are stopped and callbacks are suppressed.

### 7.7 Process and connectivity recovery

- Cold and warm recovery load the last committed aggregate without network.
- Crash recovery uses the last committed revision; uncommitted UI state is
  discarded.
- Reboot and system termination do not alter lifecycle.
- Force quit preserves progress but reminders are treated as unavailable or
  unreliable until manual reopen and reconciliation.
- Connectivity restoration may offer a user-invoked plan/store refresh for a
  future plan; it never refreshes the active snapshot automatically.

### 7.8 Migration compatibility

- After semantic cutover, recovery reads the target Session aggregate and its
  explicit migration condition; it never falls back to legacy arrays or
  `isActive`.
- Exact legacy mappings may supply preserved identity/evidence only through the
  conversion rules in Section 8.
- Legacy incomplete and unresolved conditions remain visible to recovery and
  cannot be relabeled as native completeness.
- A compatibility payload can initiate lookup only. It cannot select a
  candidate, Resume, Abandon, collect, assign an outcome, or route directly to
  Map.
- Recovery of a migrated Session uses the same expected-revision commands as a
  native Session, subject to the unresolved-line Finish restriction.

---

## 8. Migration

### 8.1 Boundary

This section defines semantic conversion and compatibility only. It does not
define or authorize a schema, migration stage, migration code, or store change.
WT-033A T-08 must implement these rules within D-24 and D-34 after T-02
provides an approved physical representation.

### 8.2 Legacy Session conversion

Conversion preserves:

- Session UUID;
- every available start/finish/active datum;
- raw item and collected-token evidence under the bounded rules below;
- exact source list and entry mappings where provable;
- exact Product identities and display snapshots where provable;
- selected-store name, ID, and valid coordinates as a legacy stop snapshot;
- every missing, malformed, duplicate, foreign, contradictory, or unresolved
  fact as classified evidence.

Deterministic interpretation is:

| Legacy evidence | Conversion |
|---|---|
| `isActive == true` and no terminal timestamp | Preserve as an active-claim recovery candidate. Initialize activity under Section 8.4, evaluate expiry, and keep reminders off until recovery resolves uniqueness and integrity. |
| `isActive == false` with `finishedAt` | Preserve as Finished with migration condition Legacy incomplete. Preserve collected/remaining execution evidence; mark unprovable final dispositions Legacy Unknown; write no retrospective list/history effect. |
| `isActive == false` without `finishedAt` | Preserve as Legacy unresolved inactive evidence outside normal lifecycle authority. It does not block Start. |
| Active evidence plus terminal timestamp | Preserve as Legacy unresolved active-claim evidence. It blocks normal Session work until the user explicitly Resumes a sufficiently coherent snapshot or Abandons it. |
| Exact item → exact compatibility UUID → source list → entry alias → Product | Create one stable line retaining all exact identities and available snapshots. |
| Zero or multiple exact matches | Create or retain an unresolved line/evidence record; never name-, barcode-, or order-match. |
| Collected token present in item set | Preserve provisional Collected execution evidence. |
| Valid collected token absent from item set | Preserve as foreign collected evidence; do not append a guessed line or Product. |
| Missing/invalid store context | Preserve the Session with degraded stop completeness; do not fabricate Store identity or coordinates. |

### 8.3 Source and snapshot provenance

- A missing historical list revision is `legacyUnknown`.
- It is not replaced by a random value, zero, the migration baseline, or the
  current list revision.
- A missing plan remains an explicitly incomplete legacy snapshot.
- Current network, Catalog, Store, discovery, recommendation, or AI data is
  never used to reconstruct historical plan evidence.
- A transient Store with valid legacy snapshot data uses a Session-scoped stop
  identity and explicit transient provenance.

### 8.4 Legacy activity and expiration

For a legacy active claim:

- `lastActivityAt` initializes from `startedAt`;
- the current activation start also initializes from `startedAt`;
- provenance is `legacyStartedAt`;
- the v1.0.3 12-hour/72-hour policy snapshot is attached with migration
  provenance;
- recovery evaluates expiration immediately with no hidden grace period;
- a due candidate becomes Expired through the idempotent expiration boundary;
- the user may explicitly Resume, which begins a new activation window.

Missing or invalid `startedAt` makes the candidate Legacy unresolved and keeps
reminders off.

### 8.5 Incomplete Sessions and unresolved lines

- Legacy Finished Sessions may contain Legacy Unknown lines and are excluded
  from normal purchased/resolved metrics.
- Native Finished Sessions may not contain Legacy Unknown or unset outcomes.
- A non-terminal migrated Session may be manually resumed when it meets the
  minimum integrity rule in Section 7.4.
- Map/reminder capability requires a valid stop snapshot separately.
- A migrated unresolved line is shown with available safe snapshot data or the
  localized label “Legacy item unavailable”; it is never hidden.
- An unresolved line blocks Finish until an exact supported repair establishes
  its Product/source identity. The alternative is explicit Abandon.
- Migration does not restore tombstoned Products. A tombstone referenced by a
  non-terminal Session remains an explicit contradiction under D-32.

### 8.6 Multiple legacy active Sessions

Every active claim is preserved as a candidate. Section 7.3 is the only
selection policy. “Newest wins,” silent expiry for uniqueness, silent Finish,
silent Abandon, deletion, and candidate merging are prohibited.

### 8.7 Exception evidence

Per Session, conversion retains at most 100 detailed token exceptions plus an
overflow count:

- valid foreign UUIDs may retain their normalized UUID because it is required
  for exact support/recovery matching;
- invalid token text is not retained verbatim;
- invalid tokens retain a keyed digest, original ordinal, byte length, source
  collection, and classification;
- duplicate tokens retain one normalized identity plus occurrence count and
  ordinals;
- exception diagnostics contain no Product/store names, notes, barcodes,
  coordinates, or raw invalid text.

No exception is silently discarded when the cap is reached; the overflow count
and category counts preserve bounded loss evidence.

### 8.8 Idempotency and compatibility

- Stable legacy Session identity plus stable source token/alias identity
  determine converted identity.
- A repeated conversion produces no new lines, stops, exceptions, timestamps,
  lifecycle changes, or registrations.
- Legacy fields and payloads are migration/cleanup inputs only after cutover.
- A legacy payload may resolve only through an exact persisted mapping to one
  current Session/revision; otherwise it is suppressed and cleaned up.
- Compatibility never writes target lifecycle from a legacy value.

### 8.9 Quarantine and recovery policy

- A recoverable original-store boundary remains protected as required by D-34.
- Recreated/quarantined stores are retained for 30 days or until an explicit
  user-confirmed support recovery/removal action, whichever occurs first.
- At most the three most recent quarantines are retained; creating a fourth
  removes only the oldest after the newer boundary is validated.
- Support diagnostics expose mode, stage, counts, digests, and safe error codes,
  never Product/list/store content or precise location.
- Recovery is performed only by a forward-compatible build against an explicit
  working copy; it never silently replaces current authority.
- Automatic restoration, old-binary downgrade, and “empty store equals
  success” are prohibited.

---

## 9. Repository Responsibilities

### 9.1 Responsibility matrix

| Owner | Must own | Must not own |
|---|---|---|
| **Session Repository** | Scoped load of exact Session/revision; load of all recovery candidates; persistence of Session header, snapshot, stops, lines, migration conditions/exceptions, and Session-only mutation within a coordinator transaction; exact non-terminal conflict lookup. | Product/list/history policy; plan generation; reminder scheduling; silent candidate selection; independent save during a coordinated command. |
| **History Repository** | Scoped lookup and append of immutable, UUID-keyed named events; idempotency lookup by causal command/line/outcome; legacy aggregate compatibility reads labeled non-authoritative. | Inferring purchase; mutating Product/list/Session; attaching legacy data by name/barcode; independent save during Finish. |
| **Shopping Repository** | Named list, current durable revision, exact entries, entry protection, resolve/keep-Needed effects, and one revision increment per affected list inside the coordinator transaction. | Session lifecycle; collection; Product History inference; global completion; changing uncaptured or other-list entries during Finish. |
| **Transaction Coordinator** | Command serialization; one transaction scope; expected Session/list revision validation; idempotency; ordered participation; single commit; rollback/reload; committed result publication. | Domain policy invention; OS notification/geofence work inside the business transaction; separate participant contexts/saves; last-write-wins conflict resolution. |

The plan participant may mark the exact source plan invalid/superseded inside
Finish but remains a projection owner. The Product Repository participates only
in validation that exact Products exist and are not contradictory; Finish does
not mutate Product lifecycle.

### 9.2 Command ownership

- Start, Collect, Undo, Expire, Resume, Finish, and Abandon enter through the
  Session command boundary.
- Product/list commands query non-terminal Session protection through the
  Session Repository.
- Finish is the only command jointly coordinating Session, Shopping, History,
  and plan invalidation.
- Views and integration adapters submit intent and render committed
  projections. They never save lifecycle state directly.
- Repositories expose persistence operations but do not decide business
  meaning or commit independently.

### 9.3 Failure ownership

- The coordinator owns domain commit failure and rollback.
- The reminder coordinator owns post-commit desired/ledger/actual convergence.
- The platform adapter owns OS registration/scheduling results.
- Recovery distinguishes domain failure, projection cleanup failure,
  capability denial, migration failure, recreated store, and in-memory mode.
- No projection or platform failure is translated into a Session lifecycle
  change.

---

## 10. Integration Contracts

### 10.1 Notifications, location, and reminder projection

Session reminders are a local, best-effort projection of one Active Session
revision:

- reminder intent is **per Session** in v1.0.3 and defaults off until the user
  explicitly enables it;
- notification permission is requested only from that explicit action or a
  user-invoked Settings action;
- Always location access is requested only after a durable Active Session
  exists, the user selects “Enable nearby reminders,” the explanation is
  shown, and When In Use status is already resolved;
- temporary full accuracy may be requested only from user-invoked foreground
  Map/current-stop or reminder setup, never from a callback;
- a decline or capability loss degrades reminders but never Session progress;
- WayTask reserves at most 12 regions for the Active Session: current stop
  first, then up to 11 ordered future stops with Remaining lines;
- passive nearby shopping is removed for v1.0.3 and receives zero regions;
- there are no app-defined quiet hours in v1.0.3; system Focus/notification
  controls remain external capability;
- successful reminder cooldown is two hours per Session and stop, and a
  revision change does not bypass it;
- cooldown advances only after successful scheduling;
- notification copy contains zero Product names and no distance;
- userInfo and region identity contain only versioned opaque routing identity;
- no notification actions mutate state; tap is the only v1.0.3 interaction;
- if local authority cannot open, contextual and generic notifications are both
  suppressed;
- valid taps open the exact Session in Shopping Mode/current stop; Map is a
  secondary action;
- Expired, Finished, Abandoned, missing, or superseded taps open a localized
  Session-status surface and never mutate selected list, plan, Map, or Session;
- known pending and delivered Session notifications are removed on Finish,
  Abandon, Expire, opt-out, revision replacement, and recreated-store cleanup;
- every event and tap still revalidates persisted state because delivery cannot
  be recalled reliably.

Notification content may name the frozen Store and remaining count, with
uncertainty preserved. A suitable semantic form is: “{count} items remain at
{store}. Availability is not guaranteed.”

The binding limitation copy is:

> Nearby reminders are best effort. iOS may delay or stop them when Background
> App Refresh is off, in Low Power Mode, after restart, or after you force quit
> WayTask. Your shopping progress stays saved; reopen WayTask to refresh
> reminders.

Binding Hebrew meaning:

> תזכורות בקרבת מקום פועלות כמיטב היכולת. iOS עשויה לעכב או להפסיק אותן כאשר
> רענון יישומים ברקע כבוי, במצב צריכת חשמל נמוכה, לאחר הפעלה מחדש או לאחר סגירה
> כפויה של WayTask. התקדמות הקנייה שלך נשמרת; יש לפתוח מחדש את WayTask כדי לרענן
> את התזכורות.

Native Hebrew and accessibility review may correct grammar or inflection
without changing the meaning or platform limitation.

### 10.2 Integration matrix

| Integration | Inputs from authority | Allowed behavior | Prohibited behavior |
|---|---|---|---|
| **Map** | Frozen Session stop/line projection and Session revision. | Display stops/lines offline; open navigation; submit the explicit navigation activity command. | Rebuild or rewrite the snapshot; use global open items; infer collection/purchase; treat notification payload as Map truth. |
| **Notifications** | Opaque registration → exact Active Session/revision/stop/Remaining-line projection. | Schedule best-effort content after full validation; route a valid tap to the exact Session. | Carry Product names/distance/coordinates as authority; mutate lifecycle; notify without local authority; route stale data directly to Map. |
| **Shopping Plan** | One list ID, exact revision, exact entry IDs, plan identity/signature/evidence time, ordered stop evidence. | Supply Start input; remain rebuildable; become invalid/superseded on Finish; generate a future plan on explicit request. | Mutate an Active snapshot; silently refresh on connectivity; act as Session authority. |
| **History** | Successful Finish line decisions and stable Product/source/Session/line identities. | Append exactly one immutable named event per line in the Finish transaction. | Infer purchase from collection, legacy flags, notifications, Store evidence, Abandon, or AI. |
| **Product State** | Protected Product/source identities and outcome-to-entry mapping. | Block Product removal while a non-terminal Session references it; reconcile exact entries at Finish; preserve Product lifecycle. | Global completion; Product removal/restoration from Session outcomes; cross-list mutation. |
| **Discovery** | Current Product/list/plan projections or frozen Session projection when explaining context. | Suggest Products or future plan inputs; add a new source-list entry through the named list command. | Add a line to an Active Session; resolve/purchase; silently update a snapshot. |
| **Store Recommendations** | Current plan inputs before Start; frozen stop evidence after Start. | Rank or explain candidate stores for a new/future plan; show uncertainty. | Claim inventory; rewrite Active stops/assignments; run in a region callback. |
| **Camera** | Recognition result plus explicit Product/list/Session context. | Create/identify/restore Product only through approved explicit Product commands; add to a named list explicitly; if an exact line match exists, offer a user-confirmed Collect command. | Auto-restore, auto-add to an Active Session, auto-collect, infer purchase, or mutate outcomes. |
| **AI** | Read-only approved projections and privacy-approved context. | Suggest, classify, summarize, or explain; propose a future explicit command. | Start, Resume, Expire, Finish, Abandon, collect, assign outcomes, modify lists/Products, publish Store truth, or run background Session mutation. |

### 10.3 Plan freshness and offline Start

A plan is:

- **fresh** when its source list ID/revision/entry IDs still match and its
  evidence age is at most 24 hours;
- **stale but confirmable** when identity/revision/entries still match and age
  is greater than 24 hours but at most 7 days;
- **invalid** when any identity/revision/entry differs, evidence is in the
  future, required snapshot data is missing, or age is greater than 7 days.

A stale-but-confirmable plan may start only after explicit copy identifies its
saved evidence time and warns that Store information may have changed. There is
no confirmation override for revision or identity mismatch or for a plan older
than 7 days.

Offline Start additionally requires:

- source list ID/revision and exact entry IDs;
- plan ID/signature and evidence timestamp;
- at least one ordered stop with stable or Session-scoped transient identity,
  display name, valid coordinates, source/provenance, and evidence time;
- exact line-to-stop assignments and Product display snapshots.

Opening hours, current distance, inventory certainty, network reachability, and
live Store resolution are not required. A transient Store uses a stable
Session-scoped stop ID and explicit transient provenance. It may support Map and
reminders only when its persisted coordinates are valid.

Connectivity recovery never refreshes automatically. The user may request a new
future plan; the Active Session remains unchanged.

### 10.4 Stale and degraded presentation

The required semantic labels are:

| Meaning | English | Hebrew |
|---|---|---|
| Frozen Session snapshot | Saved when session started | נשמר בתחילת הקנייה |
| Stale plan time | Saved plan from {date/time} | תוכנית שמורה מ־{date/time} |
| Stale Store warning | Store information may have changed | ייתכן שמידע החנות השתנה |
| Durable progress with reminder failure | Shopping is active and progress is saved. Nearby reminders are unavailable. | הקנייה פעילה וההתקדמות נשמרה. תזכורות בקרבת מקום אינן זמינות. |

Icons and color may supplement but never replace text. VoiceOver must announce
Session state, progress, snapshot age/source, reminder capability, and available
remedy independently.

### 10.5 Performance, energy, compatibility, and field qualification

Release budgets for the WT-032B reference profile are:

- exact non-terminal Session lookup p95: no more than 10 ms;
- cold local Session recovery after an already-open durable store p95: no more
  than 500 ms;
- background event local validation/projection p95: no more than 250 ms and
  maximum 1 second, excluding OS scheduling callback latency;
- desired-registration computation p95: no more than 100 ms for 12 regions;
- one-time semantic migration/recovery of the reference profile: no more than
  30 seconds, with a visible non-writable recovery state for work over 2
  seconds;
- no correctness, identity, or recovery requirement may be traded for a
  performance budget.

Device-side energy diagnostics may retain only counts, durations, capability
categories, result codes, and thermal/low-power categories. They retain no
Session/Product/list/store IDs, names, coordinates, route, or payload content;
the rolling limit is 14 days and 500 records. MetricKit integration is deferred
for v1.0.3.

Physical qualification covers these four configurations:

1. oldest supported iPhone class on the minimum supported OS;
2. current representative iPhone class on the release-target OS;
3. supported iPad class on the minimum supported OS;
4. supported iPad class on the release-target OS.

Each configuration covers foreground/background, cold launch, reboot,
force-quit then manual reopen, Low Power Mode, Background App Refresh off,
Precise Location off, permission denial/change, and offline/reconnection.
Unsupported combinations are documented rather than represented as guarantees.

The legacy payload adapter remains cleanup-only after cutover and is eligible
for removal only after both:

- the oldest supported v1.0.3 upgrade path has been public for at least 90
  days; and
- privacy-safe aggregate evidence shows at least 99.9% of eligible launches for
  30 consecutive days require no legacy payload resolution.

Removal occurs in the first forward-compatible release meeting both conditions.
The adapter never delays semantic authority retirement.

Privacy approval requires the designated Product privacy owner and iOS
engineering owner. English/Hebrew terminology requires the Product owner, a
native Hebrew reviewer, and the accessibility owner. These are release
evidence gates, not open product decisions and not prerequisites to pure T-01
domain vocabulary work.

---

## 11. Acceptance Criteria

### 11.1 Lifecycle, identity, and line contract

- [x] The only normal lifecycle states are Active, Expired, Finished, and
  Abandoned.
- [x] Paused, Recovered, migration condition, app lifecycle, and capability are
  not competing Session states.
- [x] Finished and Abandoned are the only terminal states.
- [x] Inactivity, maximum automatic authority, meaningful activity, Resume, and
  retention policies are exact.
- [x] Session, source list, source revision, Session revision, snapshot, and
  line identity are defined.
- [x] One frozen snapshot supports single- and multi-stop Sessions.
- [x] Execution state is Remaining/Collected; final outcomes are the six D-04
  values only.
- [x] Legacy Unknown is migration-only and cannot be selected at Finish.

### 11.2 Finish, recovery, and migration

- [x] Every native line receives one explicit final outcome.
- [x] Collected remains provisional until the atomic Finish commit.
- [x] Finish validation, inputs, conflicts, participants, atomic effects,
  idempotency, failure, rollback, and post-commit cleanup are specified.
- [x] Abandon performs no list resolution or Product History write.
- [x] Normal operation permits one non-terminal Session; migration preserves
  every candidate and requires explicit user resolution.
- [x] Recovery works without notification permission or network.
- [x] Recreated-store and in-memory behavior fail closed and do not claim
  durability.
- [x] Legacy identity, activity, source revision, incomplete terminal outcomes,
  missing items/stops, foreign tokens, multiple active claims, quarantine, and
  compatibility are deterministic.

### 11.3 Integration and authority

- [x] Session, Shopping, History, plan, transaction, reminder, and platform
  responsibilities do not overlap.
- [x] Map, notifications, Shopping Plan, History, Product State, Discovery,
  Store Recommendations, Camera, and AI have explicit read/command limits.
- [x] Passive nearby shopping is removed for v1.0.3.
- [x] Reminder intent, permission timing, 12-region budget, current/future
  priority, cooldown, copy, payload minimization, tap routing, stale handling,
  and cleanup are exact.
- [x] Offline/stale Start and transient Store policies are exact.
- [x] No integration may mutate an Active snapshot or infer purchase.

### 11.4 WT-031B 68-item readiness ledger

“Specified” means this document closes the decision/contract. “Execution
evidence” means no decision remains, but the named later WT-033A step must prove
the implementation result. This distinction avoids claiming code, schema,
tests, review, or release work that this documentation-only task did not
perform.

#### Architecture compliance — 5/5 addressed

| ID | Readiness item | Disposition |
|---|---|---|
| R-01 | WT-030B state machine and matrix preserved | **Specified:** Section 2 is the binding implementation matrix without reinterpretation. |
| R-02 | Orthogonal Session/list/plan/reminder/capability/app/Map/notification ownership | **Specified:** Sections 2, 9, and 10. |
| R-03 | No continuous background location, polling, background planner, or force-quit promise | **Specified:** Sections 2.1, 7.7, and 10.1. |
| R-04 | Passive nearby removed or separately namespaced | **Specified:** removed for v1.0.3; zero region budget. |
| R-05 | One model supports single/multi-store | **Specified:** one or more stops in one snapshot. |

#### WT-031A contract — 7/7 addressed

| ID | Readiness item | Disposition |
|---|---|---|
| R-06 | Stable Product and entry identity | **Specified dependency:** exact native identities required by Sections 3–4; provided by D-08–D-12 and WT-033A T-01/T-02. |
| R-07 | Durable list revision semantics | **Specified dependency:** D-11 and Section 3.2. |
| R-08 | Plan identity includes list/revision/entries | **Specified:** Sections 3.2 and 10.3. |
| R-09 | Product/store display snapshot policy | **Specified:** Sections 3.3, 4.2, and 10.3. |
| R-10 | Shared Session line | **Specified:** Section 4 is the sole PS-Session line contract. |
| R-11 | Atomic Finish list/history reconciliation | **Specified:** Section 6 and D-36. |
| R-12 | Compatibility migration-only after cutover | **Specified:** Sections 8.8 and 10.5; T-21 evidence required. |

#### Lifecycle and UX — 8/8 addressed

| ID | Readiness item | Disposition |
|---|---|---|
| R-13 | Inactivity and maximum lifetime | **Specified:** 12 hours and 72 hours per explicit activation. |
| R-14 | Meaningful activity events | **Specified:** Section 2.3 exhaustive list. |
| R-15 | Finish remaining-line choices | **Specified:** all six outcomes; explicit bulk Carry Forward for Remaining only. |
| R-16 | Abandon/expired retention and history | **Specified:** no automatic expiry; Abandon writes no Product History. |
| R-17 | Existing-session conflict UX | **Specified:** Section 7.3; Resume/Finish/Abandon/Cancel semantics remain explicit. |
| R-18 | Update Session inclusion | **Specified:** excluded from v1.0.3. |
| R-19 | Valid/expired/terminal/missing tap UX | **Specified:** Section 10.1 Session-status routing. |
| R-20 | In-memory/recreated-store UX | **Specified:** Section 7.6. |

#### Persistence and migration — 10/10 addressed

| ID | Readiness item | Disposition |
|---|---|---|
| R-21 | Target graph and transaction boundaries | **Contract closed:** semantic graph in Section 4.1 and atomic boundaries in Sections 6 and 9; physical schema is T-02 implementation evidence and is intentionally not defined here. |
| R-22 | V1–V3 frozen | **Specified:** no change permitted; T-02 proves hashes/freeze. |
| R-23 | Multiple-active policy | **Specified:** Sections 7.3 and 8.6. |
| R-24 | Missing/malformed/duplicate/foreign token policy | **Specified:** Sections 8.2 and 8.7. |
| R-25 | Legacy finished unresolved-outcome policy | **Specified:** Legacy incomplete + Legacy Unknown, no inferred effects. |
| R-26 | Legacy activity/expiration initialization | **Specified:** Section 8.4. |
| R-27 | Plan/list revision provenance | **Specified:** Section 8.3. |
| R-28 | Migration/repair idempotency | **Specified:** Section 8.8; T-08 evidence required. |
| R-29 | Quarantine retention/support | **Specified:** Section 8.9. |
| R-30 | Forward-fix/phased rollback tested | **Execution evidence:** D-34 and WT-033A T-08/T-21; policy fixed in Sections 8.9 and 6.6. |

#### Background, location, and notifications — 11/11 addressed

| ID | Readiness item | Disposition |
|---|---|---|
| R-31 | Minimal background entry path | **Specified:** one opaque event → local validation/projection; Section 10.1. |
| R-32 | Background excludes MapKit/planner/AI/Catalog/sync | **Specified:** Sections 7.7 and 10.2. |
| R-33 | Foreground location lease and stop rules | **Contract closed:** only user-invoked Map/current-stop/setup use; no API signature defined. |
| R-34 | Contextual user-initiated prompts | **Specified:** Section 10.1. |
| R-35 | Region budget and priority | **Specified:** 12; current then up to 11 future; passive zero. |
| R-36 | Compact identity/userInfo privacy review | **Contract closed:** content rules fixed; release signatories fixed in Section 10.5. |
| R-37 | Desired/ledger/actual reconciliation | **Specified:** post-commit, revisioned, terminal zero; T-20 evidence required. |
| R-38 | Cooldown/quiet/idempotency | **Specified:** two hours per Session/stop, no app quiet hours, command/event idempotency. |
| R-39 | Cooldown after success only | **Specified:** Section 10.1. |
| R-40 | Event/tap terminal/revision/expiry validation | **Specified:** mandatory and fail-closed. |
| R-41 | Recreated/in-memory region suppression | **Specified:** Section 7.6. |

#### File inventory and authority cutover — 7/7 addressed

| ID | Readiness item | Disposition |
|---|---|---|
| R-42 | Verified files assigned to owners | **Contract closed:** Section 9 ownership plus WT-033A S-02 TC-01/02/04–07/11/13/16/18/26. |
| R-43 | Proposed files accepted/folded without lost testability | **Contract closed:** no new WT-031B parallel authority; responsibilities fold into the named WT-033A components. |
| R-44 | Transitional reads limited | **Specified:** Section 8.8. |
| R-45 | No released dual writes | **Specified:** one T-21 cutover. |
| R-46 | Consumer cutover together | **Specified:** WT-033A T-18–T-21 remain one unreleased conversion unit. |
| R-47 | Static forbidden legacy reads/writes | **Execution evidence:** T-21 proves zero runtime compatibility authority. |
| R-48 | Legacy region/payload cleanup retirement | **Specified:** Section 10.5 bounded 90-day/99.9% criterion; semantic authority retires at cutover. |

#### Test and reliability — 9/9 addressed

| ID | Readiness item | Disposition |
|---|---|---|
| R-49 | Exhaustive state transition fixtures | **Execution evidence:** Section 2.7 is the fixture oracle for T-01/T-19. |
| R-50 | WT-030B AC-01–AC-50 executable evidence | **Execution evidence:** retain WT-031B §17.13 mapping; T-19/T-20/T-21 must attach results. |
| R-51 | V1/V2/V3 ambiguity/corruption/multiple corpus | **Execution evidence:** Section 8 is the T-08 oracle; WT-032B fixtures remain protected. |
| R-52 | 100 cold-cycle progress test | **Execution evidence:** T-19 recovery qualification. |
| R-53 | Races/save/disk/interruption tests | **Execution evidence:** Sections 2.7, 6, 7, and 8 define expected results. |
| R-54 | Offline/reconnection tests | **Execution evidence:** Sections 7.7 and 10.3. |
| R-55 | Physical-device lifecycle matrix | **Specified:** Section 10.5; T-21 executes it. |
| R-56 | Performance/callback/battery/thermal budgets | **Specified:** Section 10.5; T-21 executes them. |
| R-57 | Redacted bounded diagnostics | **Specified:** Sections 8.7, 8.9, and 10.5. |

#### Localization, accessibility, privacy, and support — 6/6 addressed

| ID | Readiness item | Disposition |
|---|---|---|
| R-58 | English/Hebrew semantic vocabulary | **Specified:** D-20 plus Sections 10.1 and 10.4. |
| R-59 | RTL/interpolation/Dynamic Type cases | **Execution evidence:** T-21 uses D-20 vocabulary and Section 10 plural/date placeholders. |
| R-60 | VoiceOver state/progress/capability/remedy | **Specified:** Section 10.4; T-21 evidence required. |
| R-61 | Accurate permission/force-quit/stale/degraded copy | **Specified:** Sections 7.6, 10.1, and 10.4. |
| R-62 | Retention and identifier/ledger privacy | **Specified:** Sections 2.4, 8.7, 8.9, and 10.5; release signoff required. |
| R-63 | Support-safe mode differentiation | **Specified:** Sections 7.6, 8.9, and 9.3. |

#### Release gate — 5/5 addressed

| ID | Readiness item | Disposition |
|---|---|---|
| R-64 | Approved specification authorizes exact implementation footprint | **Re-gate action:** this contract is complete; WT-033A re-gate must explicitly authorize the already bounded S-02 step footprint. This document itself grants no code authority. |
| R-65 | No implementation from WT-031B plan alone | **Satisfied:** this specification replaces the open-decision dependency but still requires re-gate approval. |
| R-66 | All BI and BM questions closed | **Satisfied:** 27/27 and 8/8 in Section 12. |
| R-67 | Release blockers closed before cutover | **Contract closed:** 14/14 in Section 12; review/test evidence remains T-21 work. |
| R-68 | One authority cutover and forward-fix | **Specified:** T-21 only; old writer never reactivates. |

**Readiness result:** 68 of 68 items are addressed. Items explicitly labeled
Execution evidence or Re-gate action are not falsely represented as completed
implementation work; none contains an unresolved Session product or migration
decision.

---

## 12. Traceability

### 12.1 WT-031B blocking-before-implementation — 27/27

| WT-031B blocker | Resolution in this specification | WT-032A decision preserved | WT-033A dependency unblocked |
|---|---|---|---|
| BI-01 | 12-hour inactivity threshold; inclusive boundary. | D-12, D-14 | T-01 lifecycle vocabulary; T-19 expiration/recovery. |
| BI-02 | 72-hour maximum automatic active-authority window per explicit activation. | D-12, D-14 | T-01, T-19. |
| BI-03 | Collect, Undo, stop selection/completion/skip, external navigation, and Resume are exhaustive meaningful activity. | D-03, D-12 | T-01 invariants; T-19 commands. |
| BI-04 | Six D-04 outcomes; every line explicit; Remaining-only bulk Carry Forward allowed. | D-03, D-04, D-36 | T-01 outcomes; T-19 Finish. |
| BI-05 | Update Session excluded from v1.0.3; snapshot generation remains 1. | D-12, D-13, D-14 | T-01 snapshot invariant; T-19 command scope. |
| BI-06 | Reminder intent is per Session, default off, separately mutable from lifecycle. | D-12, D-20, D-21 | T-19 projection source; T-20 reminders. |
| BI-07 | Always access only after durable Active Session and explicit reminder action/education. | D-20, D-21, D-23 | T-20 permission flow. |
| BI-08 | Temporary full accuracy only from foreground user-invoked Map/stop/reminder setup. | D-20, D-21, D-23 | T-18 Map; T-20 capability. |
| BI-09 | 12 regions to Active Session; passive allocation zero. | D-12, D-21, D-23 | T-20 registration projection. |
| BI-10 | Current stop first, then up to 11 ordered future stops with Remaining lines. | D-12, D-21 | T-20 desired-state computation. |
| BI-11 | No app-defined quiet hours in v1.0.3. | D-20, D-21 | T-20 scheduling policy. |
| BI-12 | No delayed app-quiet queue; system controls delivery; all later delivery/taps revalidate. | D-20, D-21 | T-20 event/tap validation. |
| BI-13 | Passive nearby shopping removed for v1.0.3. | D-21, D-23, D-33 | T-18/T-20 cutover. |
| BI-14 | Not applicable after removal; no named list/revision owns passive reminders. | D-08, D-21, D-23 | T-18/T-20 zero-passive proof. |
| BI-15 | Binding best-effort/reboot/force-quit limitation copy in Section 10.1. | D-20, D-21 | T-20 presentation; T-21 localization. |
| BI-16 | Valid tap opens exact Session in Shopping Mode/current stop; Map secondary. | D-21 | T-20 router. |
| BI-17 | Stale/terminal tap opens non-mutating Session-status surface. | D-20, D-21 | T-20 router/fallback. |
| BI-18 | Always fail closed when local authority cannot open; no generic notification. | D-21, D-24, D-34 | T-20 background validator. |
| BI-19 | Zero Product names and zero distance in notification copy. | D-20, D-21 | T-20 content/privacy. |
| BI-20 | No notification actions; validated tap only. | D-21, D-35, D-36 | T-20 categories/actions. |
| BI-21 | Fresh ≤24h; stale-confirmable >24h and ≤7d; older/mismatched invalid. | D-11, D-12, D-14 | T-18 plan; T-19 Start. |
| BI-22 | Exact offline plan/store/assignment snapshot fields defined in Section 10.3. | D-11, D-12 | T-02 representation; T-18/T-19. |
| BI-23 | Connectivity refresh is user-triggered and future-plan-only. | D-12, D-13 | T-18 planning; T-19 snapshot. |
| BI-24 | Transient Store receives stable Session-scoped stop identity and explicit provenance. | D-12, D-21, D-23 | T-02 stop representation; T-18/T-19. |
| BI-25 | In-memory mode blocks new Session creation and mutation; reminders off. | D-24, D-34, D-36 | T-08 recovery; T-19 safety. |
| BI-26 | Distance is omitted entirely from Session notification copy. | D-20, D-21 | T-20 content/privacy. |
| BI-27 | Explicit stale Start allowed only within seven days with exact revision/identity and confirmation. | D-11, D-12, D-14 | T-19 Start validation. |

### 12.2 WT-031B blocking-before-migration — 8/8

| WT-031B blocker | Resolution in this specification | WT-032A decision preserved | WT-033A dependency unblocked |
|---|---|---|---|
| BM-01 | Preserve every candidate; user chooses one and explicitly Abandons competing active/non-terminal claims; no silent selection. | D-05, D-28, D-29 | T-08 candidate migration; T-19 recovery. |
| BM-02 | Preserve unresolved lines; show safe snapshot or “Legacy item unavailable”; never guess/drop. | D-27, D-28 | T-02 exception representation; T-08/T-19. |
| BM-03 | Legacy Finished remains terminal Legacy incomplete; unprovable lines use migration-only Legacy Unknown; no list/history inference. | D-03, D-04, D-28 | T-08 mapping; T-19 native terminal invariant. |
| BM-04 | Initialize activity and activation from `startedAt` with legacy provenance; apply current policy immediately, no grace. | D-12, D-28, D-29 | T-08 conversion; T-19 recovery. |
| BM-05 | Missing historical list revision is explicit `legacyUnknown`, never a fabricated value. | D-11, D-12, D-28 | T-02 source-revision representation; T-08. |
| BM-06 | Manual resume minimum defined; invalid stop degrades Map/reminders; structural ambiguity remains unresolved; Finish requires exact repair. | D-12, D-27, D-28, D-29 | T-08 recovery condition; T-19. |
| BM-07 | Bounded 100-detail exception evidence, safe digest/ordinal/category, overflow counts, no raw invalid text/private content. | D-27, D-28, D-34 | T-08 exception ledger/privacy. |
| BM-08 | Quarantine retained 30 days, maximum three, forward-compatible working-copy recovery only, privacy-safe support actions. | D-24, D-34 | T-08 failure/recovery; T-21 support gate. |

### 12.3 WT-031B blocking-before-release — 14/14

| WT-031B blocker | Resolution in this specification | WT-032A decision preserved | WT-033A dependency |
|---|---|---|---|
| BR-01 | Expired Sessions have no automatic retention expiry; explicit Resume/Abandon required. | D-05, D-07, D-14 | T-19; T-21 retention review. |
| BR-02 | Abandoned snapshots/progress have no automatic expiry in v1.0.3. | D-05, D-07 | T-19; T-21 privacy review. |
| BR-03 | Abandon writes no Product History event; Session record is the evidence. | D-05, D-06 | T-19. |
| BR-04 | Recreated-store notice and Retry/support/quarantine actions defined; no false empty state. | D-24, D-34 | T-08; T-21 support. |
| BR-05 | Energy diagnostics limited to safe categories/counts/durations, 14 days, 500 records. | D-20, D-34 | T-20; T-21 privacy/performance. |
| BR-06 | MetricKit deferred for v1.0.3. | D-33 | T-21 scope. |
| BR-07 | Lookup, recovery, callback, registration, and migration budgets fixed in Section 10.5. | D-34, D-37 | T-08; T-19/T-20/T-21. |
| BR-08 | Binding best-effort/force-quit copy defined in English and Hebrew meaning. | D-20, D-21 | T-20/T-21. |
| BR-09 | Snapshot/stale-source labels and warnings defined in Section 10.4. | D-12, D-20 | T-18/T-19/T-21. |
| BR-10 | Adapter removal requires ≥90 days plus 99.9% no-use for 30 days. | D-33 | T-20/T-21 and later removal release. |
| BR-11 | Known pending and delivered notifications are removed on terminal/expiry/opt-out/revision/recovery transitions. | D-21, D-36 | T-20. |
| BR-12 | Four-configuration iPhone/iPad matrix and nine lifecycle/capability scenarios fixed. | D-20, D-21 | T-21 physical qualification. |
| BR-13 | Product privacy owner and iOS engineering owner sign privacy review. | D-20, D-34 | T-21. |
| BR-14 | Product owner, native Hebrew reviewer, and accessibility owner sign terminology/copy. | D-20 | T-21. |

### 12.4 Shared WT-033A contract

| Shared definition identified by T-00 | One contract | T-02 use | T-08 use | T-19 use |
|---|---|---|---|---|
| Session source list and revision | Sections 3.1–3.2 | Represent exact target revision plus explicit legacy provenance. | Preserve exact or `legacyUnknown`; never fabricate. | Validate Start and Finish/current revision conflicts. |
| Immutable Session lines | Sections 4.1–4.2 | Represent one owned line per exact native source entry plus exception support. | Deterministically map or preserve unresolved evidence. | Use line ID as the only command/outcome key. |
| Provisional collection | Sections 4.3–4.4 | Represent execution state separately from final outcome. | Preserve collected evidence without purchase promotion. | Collect/Undo Session-only. |
| Final outcomes | Section 5 | Represent six native values; Legacy Unknown is separate migration metadata. | Use Legacy Unknown only for incomplete historical evidence. | Require one of six for every native line. |
| Finish transaction | Section 6 and Section 9 | Permit all participants in one coordinator scope. | Do not synthesize a historical Finish. | Commit line/list/revision/history/plan/Session exactly once. |
| Abandon | Sections 2.4 and 7.5 | Represent terminal Abandoned and retained snapshot/progress. | Permit explicit candidate Abandon only. | No list or Product History effect. |
| Recovery candidates | Sections 7–8 | Represent lifecycle separately from migration condition/exceptions. | Preserve all candidates and evidence. | Require explicit selection/Resume/Abandon and disarm reminders until resolved. |

Accordingly:

- **T-02** has one schema-neutral semantic graph and may now select a physical
  persistence representation without inventing Session meaning.
- **T-08** has one deterministic conversion, exception, candidate, provenance,
  and quarantine policy.
- **T-19** has one lifecycle, conflict, collection, outcome, Finish, Abandon,
  and recovery contract.

### 12.5 Validation totals

| Validation requirement | Result |
|---|---|
| WT-031B blocking-before-implementation | **27/27 resolved** |
| WT-031B blocking-before-migration | **8/8 resolved** |
| WT-031B blocking-before-release | **14/14 contractually resolved** |
| WT-031B readiness items | **68/68 addressed** |
| WT-032A decisions | **D-01 through D-37 preserved; none redefined** |
| Shared T-02/T-08/T-19 definitions | **7/7 unified** |
| Production/schema/migration/test/project changes | **0** |

There is no remaining Shopping Session semantic or migration-policy dependency
that prevents WT-033A from re-evaluating T-01 authorization. Later execution
evidence, physical representation, code review, privacy/localization signoff,
and release qualification remain work inside the already-defined WT-033A
steps; they are not open Session-contract decisions.

---

## Terminal Decision

**READY FOR WT-033A RE-GATE**

This terminal decision means the WT-031B implementation contract is complete
enough for WT-033A to repeat its dependency and protected-hash gate and decide
whether T-01 may begin. It does not itself authorize production, schema,
migration, test, project, capability, entitlement, or release changes.
