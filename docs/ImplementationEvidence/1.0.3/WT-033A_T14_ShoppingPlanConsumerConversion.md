# WT-033A T-14 Shopping Plan Consumer Conversion Evidence

Date: 2026-08-03
Execution step: T-14 only
Decision under review: complete, uncommitted

## Authority and pre-write gate

The binding authority was WT-030, WT-031A, approved WT-031B, WT-032A
D-01 through D-37, WT-032B Phase 1, WT-033A S-00/S-01/S-02, and
committed T-00 through T-13. The exact S-02 row authorizes T-14 to convert
Shopping Plan and derived decision/store inputs in these candidate production
paths:

- `WayTask/AppStateManager.swift`;
- `ShoppingTripService.swift`;
- `ShoppingIntentMatcher.swift`;
- `ShoppingContext.swift`;
- `DecisionEngine.swift`;
- `DiscoverViewModel.swift`;
- `StoreSearchService.swift`;
- `StoreRankingService.swift`;
- `BuyingOptionsService.swift`;
- Plan-focused tests.

Before the first write:

- the worktree was clean;
- `HEAD`, `main`, and `origin/main` were identical at
  `b2be2accba7a9dfd0218420d7b60984fc1a1beaa`;
- T-01 through T-13 formed the expected contiguous committed sequence;
- the S-02 SHA-256 was
  `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361`;
- all recorded T-06 through T-13 protected hashes matched;
- no mismatch with the execution instruction existed.

No revision cache was required or authorized by S-02. None was added or
activated.

## Final footprint

The final production footprint is exactly the nine S-02 candidate files listed
above. One synchronized-group test file was added:

- `WayTaskTests/ProductState/ProductStateShoppingPlanConsumerConversionTests.swift`.

This evidence document is the only other task-owned path. No project-file edit
was required. No existing test, fixture, expectation, threshold, or performance
profile was changed or renamed.

## Exact Plan Input authority

`ShoppingPlanConsumerBoundary` consumes one
`ProductStatePlanInputProjection` created by the committed T-13 query boundary.
It validates that the projection scope and metadata revision match its exact
List UUID and durable List revision. It then preserves:

- List UUID and durable revision;
- ordered eligible Entry identities and exact Product UUIDs;
- quantity, unit, sort order, and approved planning snapshots;
- T-13 provenance/freshness metadata through the retained source projection;
- every explicit exclusion and unresolved/malformed exclusion with its bounded
  `ProductStatePlanInputExclusionReason`;
- the complete `allNeededEntryIDs` accounting set;
- a deterministic T-14 input fingerprint.

Validation rejects duplicate identities, overlapping included/excluded sets,
foreign List identities, invalid eligible rows, and any union that does not
equal `allNeededEntryIDs`. Consequently, the internal `compactMap` from a
validated eligible row to its Product snapshot cannot silently drop an Entry.

The boundary never selects a default or first List, scans global incomplete
compatibility items, infers List membership, or infers Product identity from a
name, barcode, Catalog display value, or store text.

## Plan Status semantics

The target consumer status has these bounded readiness states:

- `noUsablePlan`;
- `generating`;
- `currentReady`;
- `stale`;
- `unavailable`;
- `invalidOrIncomplete`.

Attention is orthogonal and bounded as none, explicit exclusions, unresolved
entries, or both. Invalid states carry allowlisted reasons, including invalid
scope/accounting, mismatched T-13 Plan Status, mismatched derived projection,
and unclassified planning intent. Unavailability carries only the T-13 bounded
unavailability enum.

A Plan is current only when all of the following agree:

- exact Plan ID, List UUID, and source revision;
- T-13 Plan Status scope and metadata revision;
- ordered included Entry IDs and excluded Entry IDs;
- the stored and current canonical T-14 input fingerprints;
- no current T-13 status or projection staleness reason exists.

The refresh path repeats Plan Status owner/Entry/exclusion validation. A List
UUID match alone is insufficient.

## Fingerprint and staleness dependency set

The fingerprint is a stable, length-prefixed FNV-1a digest with a
`t14-plan-input-v1` domain separator. It does not use process-randomized Swift
hashing. Its canonical dependency fields are:

- List UUID and durable revision;
- the caller-declared T-13 planning input fingerprint;
- eligible Entry UUID, exact Product UUID, quantity bit pattern, unit, and sort
  order;
- approved planning display/category/Catalog snapshots and Product lifecycle;
- exclusion Entry/Product identities and named reason;
- the complete ordered Needed Entry identity set.

Only the digest is exposed as status/derived-input metadata. No private name,
barcode, note, image, coordinate, account value, raw row, path, credential, or
raw error is emitted as a diagnostic.

Changes to List identity/revision, eligible Entries, quantity or other declared
planning values, exclusions, required Product availability, or the declared
fingerprint therefore stale or invalidate the Plan. T-13 freshness reasons are
mapped into the bounded Plan stale reasons. The focused repository spy proves
that an unrelated Product Library-only change outside the selected Entry
Product UUID set is neither read nor treated as Plan staleness.

## Exclusion and unresolved accounting

Every Needed Entry remains visible in exactly the T-13 included/excluded
partition. Explicit user exclusions remain named `explicitUserExclusion` and
do not become resolved, removed, purchased, collected, or store-unavailable.
Missing, ambiguous, removed, and malformed Product evidence remains named and
causes invalid/incomplete attention rather than disappearance.

An otherwise valid Product whose planning classification is uncertain remains
in the exact Plan input with its Entry/Product identity intact. It is also
reported through bounded `unclassifiedPlanningIntent` attention, and no false
store claim is produced for it. Named T-13 exclusions and classification
uncertainty are retained through Shopping Context, Store Resolution intents,
trip coverage, and buying-option results.

## Deterministic consumer pipeline

The target path in `AppStateManager` accepts the exact T-13 Plan Input, Plan
Status, Discovery Context, and Store Recommendations projections. It requires
the derived projections to share the same exact Plan/List/revision owner and
scope, and requires Discovery eligible Product IDs to equal the exact Plan
input Product set. It retains the T-13 projections in the published target Plan
value.

The one authority produces:

- Product-State-aware classification and grouped planner requests;
- Store Resolution intents with List/revision/fingerprint, Entry/Product IDs,
  named exclusions, and classification uncertainty;
- exact `ShoppingContext` items with Entry/Product identities and quantity;
- conservative `DecisionResult` identity, exclusion, and unresolved metadata;
- read-only trip coverage with matched/missing Entry and Product IDs;
- ranked buying options with exact ownership and estimated-only availability.

Ordering is total and reproducible: Plan items use sort order then Entry UUID;
intent groups use the enum order; stores use score, distance, Store UUID, group,
and Entry identity tie-breakers; contexts and decisions use stable UUID order.
Equivalent store arrays in reverse order produce identical target trip and
buying-option order.

The target store path says `estimatedOnly` and never claims verified inventory.
Trip preparation does not start Shopping, collect an item, create a Session, or
promote a store.

## Compatibility boundary and KD replacement trace

The exact target overloads do not filter on `ShoppingItem.isCompleted`,
`ShoppingListEntry.isChecked`, or a global incomplete list. The only added
`isCompleted` references are compatibility guards in Discover/Context code:
the `.exactPlanInput` branch explicitly bypasses completion while the frozen
legacy branch retains its existing behavior for T-16/T-17/T-18 consumers.

The target replacement evidence is:

| Known defect | Authority trace | Target replacement evidence |
|---|---|---|
| KD-04, non-durable runtime invalidation | D-11; S-02 T-14 | exact durable List revision is retained and revision change deterministically stales the Plan |
| KD-05, Plan lacks exact immutable source | D-12; S-02 T-14 | Plan retains exact List/revision/Entry identities, exclusions, declared/canonical fingerprint, provenance, and currentness validation |
| KD-12, mixed consumer filtering | D-20/D-21; S-02 T-14 | exact Context, planner, trip, discovery, and store overloads preserve Product State identities and bypass compatibility completion |

No committed legacy characterization expectation was weakened. The replacement
is intentionally limited to the new target overloads proven by the T-14 suite;
legacy presentation remains inactive pending its separately authorized steps.

## Read-only and inactivity proof

The target boundary and all derived services operate only on immutable value
projections and caller-supplied store evidence. Static and repository audits
prove:

- no Product, List, Entry, Session, or History repository is called by the
  target path;
- no `ModelContext`, stage, save, delete, transaction, command, reverse
  compatibility write, or default-store access was added;
- no Session is created, started, finished, or activated;
- no acquisition, Camera/AI, Product/Home UI, Shopping UI, Map/location
  presentation, notification/geofence, startup, migration, schema, candidate
  promotion, production cutover, dependency, network dependency, localization,
  asset, telemetry, or Sentry change exists;
- the new publish/refresh/discard API has no production caller outside
  `AppStateManager`; only the focused tests call it;
- the legacy `shoppingPlan` and presentation state remain untouched and idle in
  target qualification;
- `project.pbxproj` has no diff and the synchronized group discovered the new
  test file automatically;
- the complete `WayTask/ProductState` implementation, including T-13 queries,
  has no diff.

This proves T-15 acquisition, T-18 Map/location presentation, and T-19 Session
authority remain inactive.

## Qualification

Development preflights were used only for defect discovery and are excluded
from the table. After behavior and expectations were frozen, every formal gate
passed on its first execution on an iPhone 17 Pro simulator running iOS 26.5:

| Gate | Passed/result | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| Focused T-14 Plan consumer, run 1, clean roots | 19 | 0 | 0 | 0 |
| Focused T-14 Plan consumer, run 2, separate clean roots | 19 | 0 | 0 | 0 |
| Affected Shopping/Product State/Catalog/Knowledge/Map/migration/startup/performance bundle | 564 | 0 | 0 | 0 |
| Exact six-suite WT-032B Phase 1 gate | 49 | 0 | 0 | 0 |
| Complete unfiltered `WayTaskTests` | 595 | 0 | 0 | 0 |
| Generic iOS unsigned Debug build | Succeeded, exit 0 | — | — | — |
| Generic iOS unsigned Release build | Succeeded, exit 0 | — | — | — |

The affected and complete bundles each report seven tests collecting
performance metrics. The exact Phase 1 selectors were
`ProductStateCharacterizationSupportSelfTests`,
`ProductStateDomainCharacterizationTests`,
`ProductStatePersistenceCharacterizationTests`,
`ProductStateConsumerCharacterizationTests`,
`ProductStateDiagnosticsCharacterizationTests`, and
`ProductStatePerformanceBaselineTests`.

The affected selection covered the T-14 suite; Shopping classification and UX;
T-13 queries; repositories; command pipeline, Product commands, List/Entry
commands, and transactions; immutable history, invariants, transitions, and
persistence graph; all Phase 1 characterization/performance suites; Product
Catalog and Product Knowledge; Map label characterization; persistence,
migration, startup, deletion, and Sentry regressions.

Xcode 26.6 (17F113), Swift 6.3.3, macOS 26.6, and the iOS 26.5 simulator were
used. Xcode repeated the pre-existing unused local warning at
`ProductCatalogMigrationTests.swift:136` and the existing Sentry build-phase
note. That protected test file and the project file remain unchanged; no T-14
warning was introduced.

## Protected hash audit

The final protected values match the pre-write baseline:

| Artifact | SHA-256 |
|---|---|
| S-00 authority discovery | `16e336f54a4cb644465f1836e9d97410bffc1044de4322581398ab3f8517b920` |
| S-01 authority specification | `2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c` |
| S-02 technical roadmap | `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361` |
| `project.pbxproj` | `9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f` |
| `Package.resolved` | `42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244` |
| `WayTaskSchema.swift` | `90841edae9796af551c453f6a3bcb65737db975a61a05505ccdb3bcef0e8f9b8` |
| TC-13 migration | `1c79711332281f4b24af81696c7242784596bcdaa8b92f35fb17b9ca757418e8` |
| TC-14 startup | `f1729caf5c33cc7de19b0cd751ae0fdb6480190a4773ec8bf37e589fcd59b849` |
| TC-05 transaction coordinator | `3ae8e4aadd9e427de50cdca0d20fe7037a5cdb546043d63f9dcd9f3c9d3d264a` |
| TC-07 repositories | `e549cd17859e9eac584a493e3b2654fb000d59cd2d6bf6d4a191bb11094d5262` |
| `ProductHistory.swift` | `57dd2b13e4e68d2292e5b45f5fe090f3b64344fe4c777a91f19cc47961e8da8c` |
| `ShoppingSession.swift` | `86c66430467c2b8b15a104c11cf0394709d4767a2e3ba7d1fbd2e711222eb8d5` |
| `WayTaskApp.swift` | `5a460b45f2922c096ee1a81ddd7da27fe13df49c50d632d1b5c91d568bb04251` |
| `ContentView.swift` | `2d30601201a2eac39673128cdac0f19907a7fe3ef7fc3e93c826d2943a3f70fc` |
| T-12 Shopping Memory | `20660f1608a5ca4d499c09062fa31c9a0d5f6363ce8df08913d3364fafb5a3a6` |
| T-12 Catalog personalization | `656546d6a770ee5658d6aaf71f34ff450ff4215da6a068aae95981800a2cbb1d` |
| T-12 focused tests | `c5a15b9bb62c5ab4999774390d561e2024dbd932aeca7cd1c66d79793c4fc35e` |
| T-13 queries | `92e10ebd622314f026ccd83f92b88f7d863a5a21c532246c9969fae9c97b5b37` |
| T-13 focused tests | `df2956e2b542267c36e4c2aa4722b47ae6fab14ae792b84eed529a560689fc1b` |

The committed T-06 through T-11 focused tests also remain exact:

```text
702f6e7690b954a2dc93862d3f7c53254d4fb5ab1cebde5b488f78740e1d139a  T-06
e9d6a7d305b57cfb565f46431f87ec66fadd92eff0971ecd5006b4bc36a64d97  T-07
385d7f4e48f58668b756138cddd2791044d180163dbe42cd8521b3ae2c8b8e5a  T-08
02b1eacf1f76941eac6c438b88f5f5d931b8a4ff405353d37393a32b34cd76c2  T-09
9447478c6658b52e77fba644bbf73aa537c13fa16d46a75aa5275e7b6c661682  T-10
df2eaee4b41302a16cab6501d6d295b11e3907a5f0faf01205670e6cf109d51f  T-11
```

Final T-14 implementation/test hashes before evidence creation:

```text
3c0a99d12c3cde8e7c1445eba5d27e604c88846e9b90e60bbd13faab42a0acb5  BuyingOptionsService.swift
cea54550e54868f7e3c1f5e38d927ab164eef74dc0f1bdcc6cfb03325425b554  DecisionEngine.swift
53ecdc967798d074023a217ec2a6ced38eb4eb1afa5e9666575a839bea43ed18  DiscoverViewModel.swift
5443e39e39f1fa9520ac6ec2db497d8a3cd228e79d003f609449fa8cd55426a1  ShoppingContext.swift
e3a29037fb3a0fd3fc2501ea62f0408bc02a47b3caf1d4c2804af3a004541fbf  ShoppingIntentMatcher.swift
7c94d7e281fd964e9b64bfedb4d98b93dde47a17e765662369d25933d0b07b40  ShoppingTripService.swift
05f5f763a9f64ca5456a9029e233ef4feb577f05d4d120c364e43c6734d9762f  StoreRankingService.swift
950588da093578bcd12de04fff169736636ea9f2b5befb789e275dcdedfd3726  StoreSearchService.swift
80079c22009cbef54abb8e2055cb500488499a54d3ba50edd6f24332889651b2  WayTask/AppStateManager.swift
a2af8b1872c5ea7d12ed4fc2246c0e4b9157dbf3dacb98d96dacf0b58b5ae29e  WayTaskTests/ProductState/ProductStateShoppingPlanConsumerConversionTests.swift
```

After qualification, `HEAD`, `main`, and `origin/main` remain identical at
`b2be2accba7a9dfd0218420d7b60984fc1a1beaa`. No commit was created.

## Cleanup and review rollback

After totals and hashes were extracted, all enumerated T-14 preflight/focused/
affected/Phase-1/full result bundles, separate DerivedData roots, Debug/Release
build roots, shared package checkout, task-owned anonymous result bundle, and
temporary package lock files were removed. Final searches under `/private/tmp`
and the task temporary root returned no T-14 artifact. No application-default,
protected migration-source, or candidate store was opened by qualification.

Review rollback is source-only: restore the nine modified production files to
`HEAD`, then delete the focused test and this evidence document. The target Plan
API has no production caller, so rollback changes no V3 data, startup,
migration, Product/List command authority, Session, or presentation behavior.

## Terminal decision

T-14 COMPLETE — READY FOR REVIEW
