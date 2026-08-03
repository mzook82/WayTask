# WT-033A T-16 Product/Home Consumer Conversion Evidence

**Execution step:** T-16 only

**Authority:** WT-030; WT-031A; approved WT-031B; WT-032A D-01 through
D-37; WT-032B Phase 1; WT-033A S-00/S-01/S-02; committed T-00 through
T-15

**Commit status:** review worktree only; no commit created

## Pre-write gate

The mandatory pre-write gate passed before any T-16 content was created:

- the worktree was clean;
- T-01 through T-15 were present as the expected contiguous committed
  implementation sequence;
- `HEAD`, `main`, and `origin/main` were identical at
  `feaf8d1b3730263bde6f146317bb41e509e6ce28`;
- the exact S-02 authority SHA-256 was
  `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361`;
- every recorded T-06 through T-15 focused-suite and implementation hash
  matched its committed evidence;
- the four authorized production paths matched their committed pre-T-16
  hashes; and
- `project.pbxproj`, package resolution, schema, migration, startup, and the
  Product State command/query authorities matched their protected baselines.

The committed sequence immediately preceding this work was T-13
`b2be2ac`, T-14 `d0351ea`, and T-15 `feaf8d1`. No mismatch or stop condition
was present.

## Product/Home authority and exact footprint

S-02 assigns T-16 exactly:

> Convert Product Library, chooser, Home, and root presentation using
> `ProductListView.swift`, `WayTask/HomeView.swift`,
> `WayTask/ContentView.swift`, `WayTask/AppStateManager.swift`, and
> Product/Home presentation tests. Use projections only, retain named-list
> scope, expose removal/Restore explicitly, perform no direct `ModelContext`
> mutation or backfill, and route exact identities.

The implementation footprint is limited to:

- `ProductListView.swift` — immutable Product Library, removed Product,
  Catalog, Product Knowledge, search, filter, and grouping presentation;
- `WayTask/HomeView.swift` — deterministic Product and named-list Home cards,
  plus read-only T-14 Plan and T-15 acquisition presentation;
- `WayTask/ContentView.swift` — exact Product/Home routes and a revision-aware
  chooser projection;
- `WayTask/AppStateManager.swift` — non-authoritative target presentation,
  selected-list scope, and exact-route state; and
- `WayTaskTests/ProductState/ProductStateProductHomeConsumerConversionTests.swift`
  — 28 focused T-16 tests.

No Shopping screen/workflow, Map, Notifications, Sessions, startup,
migration, schema, V4 activation, dependency, asset, localization, or project
file was modified. T-17 and later work was not started.

The target presentation consumers remain internally inactive pending the
later single approved cutover. Existing V3 Product/Home runtime behavior was
not switched in this step. This is the S-02 T-16 rollback boundary: the target
consumer can be disabled without changing the committed T-10 command or T-13
query authority.

## Projection-only presentation

The target Product/Home presentation accepts only immutable values already
produced by the committed boundaries:

- T-13 `ProductStateProductLibraryProjection`,
  `ProductStateRemovedProductsProjection`,
  `ProductStateCatalogLinkedProductProjection`,
  `ProductStateKnowledgeSearchProjection`, and
  `ProductStateNamedListProjection` outcomes;
- T-14 `ShoppingPlanConsumerStatus`; and
- T-15 `ProductAcquisitionPresentationState`.

No target presentation type accepts a SwiftData `Product`, `ModelContext`,
repository, transaction coordinator, or mutation closure. It creates no
Product command, Product State record, list entry, Session, Catalog Knowledge,
or Shopping state and performs no save, backfill, retry, Restore, or
acquisition.

`AppStateManager` holds only the resulting target presentation and navigation
values. Its publisher composes immutable inputs, validates an existing route
against the new projection, and clears an invalid route without substituting a
fallback identity. It does not change the legacy selected tab, current list,
Shopping Plan, or Product-library authority.

## Product identity and lifecycle

Every Product row is identified by the exact `ProductStateProductID` from its
T-13 projection. Duplicate Product UUIDs are rejected explicitly. Display
name, brand, category, Catalog text, and search text never create or replace a
Product identity.

The active Library consumer accepts only Products whose projected lifecycle
is `.active` and whose removal time is absent. The removed surface accepts only
Products whose lifecycle is `.removed` and whose removal time is present.
Removed projections retain their exact UUID, removal time, and query-supplied
Restore availability. Presentation never changes lifecycle and never silently
restores a Product.

## Product ordering and grouping

The Product Library retains the exact order of
`ProductStateProductLibraryProjection.products`. Search and filters are stable
subsequences of that order; there is no display-name sort, fallback sort, or
hidden filtering. Home cards use the first eight rows of that same projection
order and therefore remain identical for equivalent input projections.

Grouping is deterministic and order-preserving:

- ungrouped presentation emits the stable Library order;
- category grouping uses projected Catalog category identity first, then the
  Product's immutable Catalog snapshot, then the projected Product category,
  and finally the explicit `uncategorized` bucket;
- group order is first appearance in the already-authoritative Product order;
  and
- row order inside each group is unchanged.

Named-list Home cards are sorted by projected creation time and then exact
List UUID. Duplicate List UUIDs and unavailable projections become sorted,
bounded issues rather than inferred or merged Lists. Each card preserves the
exact List UUID, durable revision, title, metadata, and separate Needed,
Resolved, and unresolved counts.

## Product filters and named-list scope

Filters are explicit: all Products, membership in the named List, or Library
only relative to that named List. Any membership filter without an exact
`ProductStateListScopeRequest` is rejected. Each membership must match the
Product UUID, List UUID, expected durable revision, and projection metadata
revision. Missing, unexpected, stale, or mismatched membership is an explicit
invalid outcome; presentation never scans another List or chooses a default.

The chooser consumes that same validated projection. It retains the exact
Product, List, membership, Catalog projection, and revision. A chooser intent
contains only the exact Product UUID, List UUID, durable revision, and a
query-authorized membership action. `.restoreProduct` is deliberately rejected
by the chooser, so a list action cannot silently restore a removed Product.

## Product search

Search is presentation-only. It normalizes projected display fields with a
fixed POSIX locale and canonical Unicode/case/diacritic/width folding, then
matches only projected Product and Catalog presentation fields. It does not
parse or synthesize UUIDs, consult legacy Product objects, mutate state, change
ordering, or treat search text as identity. Empty search exposes the complete
stable projection.

## Product Knowledge presentation

Product Knowledge is consumed only through the read-only T-13 Knowledge
projection. Candidate evidence, attribution, metadata, explicit Product UUID,
and ordering are retained as immutable values. If a candidate Product identity
does not equal the query's explicit Product identity, presentation returns an
identity mismatch instead of substituting the candidate or inferring identity
from candidate text. T-16 creates, persists, or edits no Knowledge.

## Catalog presentation

Catalog presentation is keyed by exact projected Product UUID. It preserves
the committed Catalog identity and displayed name/category snapshots supplied
by T-13. A Catalog projection carrying a different Product UUID becomes an
explicit identity mismatch. Catalog outcomes for Product UUIDs absent from the
Library are retained as deterministically UUID-sorted unused identities; they
are neither merged into the Library nor silently discarded. T-16 does not
mutate Catalog Truth or personalization.

## Plan and acquisition presentation

Home copies the complete T-14 read-only Plan status needed for presentation:
readiness, attention, stale and invalid reasons, unavailable reason, exact
source List UUID and revision, input fingerprint, included Entry UUIDs,
explicit exclusions, and unresolved Entry UUIDs. It creates no Plan and writes
no Shopping state.

The complete T-15 acquisition presentation state is retained unchanged. Route
derivation uses only an authoritative Product UUID already present in the
committed confirmation/result:

- awaiting confirmation routes the exact confirmed Product UUID;
- Created and Already Active results route the exact authoritative Product
  UUID;
- Restore Required remains an explicit confirmation/result path and never
  invokes Restore; and
- ambiguity, conflict, validation failure, or unavailability produces no
  fabricated Product route.

Equivalent acquisition states produce the same route. No silent merge,
Restore, retry, or display-text identity inference exists.

## Exact navigation

Routes are bounded to Product Library, removed Products, an exact Product UUID,
an exact List UUID plus revision, or an exact T-15 confirmation/result Product
UUID. Before publication, `AppStateManager` validates the requested route
against the current immutable presentation. A stale Product, List revision, or
acquisition state clears the route and selected scope. There is no name-based
lookup, first-List fallback, most-recent fallback, or revision fabrication.

## Qualification

Development builds and focused runs used before behavior freeze were defect
discovery only and are not counted below. After behavior was frozen, the
required qualification sequence completed serially:

| Gate | Passed | Failed | Skipped | Result |
|---|---:|---:|---:|---|
| Focused T-16, run 1, clean roots | 28 | 0 | 0 | Passed |
| Focused T-16, run 2, separate clean roots | 28 | 0 | 0 | Passed |
| Affected regressions | 436 | 0 | 0 | Passed |
| Exact WT-032B Phase 1 gate | 49 | 0 | 0 | Passed |
| Complete unfiltered `WayTaskTests` | 646 | 0 | 0 | Passed |

The affected set covered T-13 queries; T-14 Plan consumers; T-15 acquisition;
Product commands; List/Entry commands; command pipeline; repositories;
transactions; invariants; migration/startup; legacy Product acquisition;
Catalog persistence, search, validation, migration, and personalization;
Product Knowledge; Product Library deletion; scanner integration; and
Shopping UX.

The exact Phase 1 gate comprised:

- `ProductStateCharacterizationSupportSelfTests`;
- `ProductStateDomainCharacterizationTests`;
- `ProductStatePersistenceCharacterizationTests`;
- `ProductStateConsumerCharacterizationTests`;
- `ProductStateDiagnosticsCharacterizationTests`; and
- `ProductStatePerformanceBaselineTests`.

The complete run emitted one transient iOS Simulator clone launch denial.
Xcode recovered that worker within the same invocation; the command exited
zero, reported `TEST SUCCEEDED`, and the finalized result bundle reported
`Passed` with 646 passed, zero failed, zero skipped, and zero expected
failures. No behavior change or manual test retry followed.

Qualification used Xcode 26.6 (17F113), Swift 6.3.3, macOS 26.6, and an iPhone
17 Pro iOS 26.5 simulator (23F77).

## Builds

Both required unsigned generic iOS builds succeeded with
`CODE_SIGNING_ALLOWED=NO`:

| Configuration | Destination | Result |
|---|---|---|
| Debug | `generic/platform=iOS` | `BUILD SUCCEEDED` |
| Release | `generic/platform=iOS` | `BUILD SUCCEEDED` |

No T-16 compilation warning was introduced. The existing Sentry symbol-upload
build phase remained unchanged and did not upload without configured
credentials.

## Protected hash audit

Every protected value matches the pre-write baseline:

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
| T-12 Shopping Memory | `20660f1608a5ca4d499c09062fa31c9a0d5f6363ce8df08913d3364fafb5a3a6` |
| T-12 Catalog personalization | `656546d6a770ee5658d6aaf71f34ff450ff4215da6a068aae95981800a2cbb1d` |
| T-13 queries | `92e10ebd622314f026ccd83f92b88f7d863a5a21c532246c9969fae9c97b5b37` |

The committed T-06 through T-15 focused tests remain byte-exact:

```text
702f6e7690b954a2dc93862d3f7c53254d4fb5ab1cebde5b488f78740e1d139a  T-06
e9d6a7d305b57cfb565f46431f87ec66fadd92eff0971ecd5006b4bc36a64d97  T-07
385d7f4e48f58668b756138cddd2791044d180163dbe42cd8521b3ae2c8b8e5a  T-08
02b1eacf1f76941eac6c438b88f5f5d931b8a4ff405353d37393a32b34cd76c2  T-09
9447478c6658b52e77fba644bbf73aa537c13fa16d46a75aa5275e7b6c661682  T-10
df2eaee4b41302a16cab6501d6d295b11e3907a5f0faf01205670e6cf109d51f  T-11
c5a15b9bb62c5ab4999774390d561e2024dbd932aeca7cd1c66d79793c4fc35e  T-12
df2956e2b542267c36e4c2aa4722b47ae6fab14ae792b84eed529a560689fc1b  T-13
a2af8b1872c5ea7d12ed4fc2246c0e4b9157dbf3dacb98d96dacf0b58b5ae29e  T-14
d89dbdb928357ad48975f10b6971e56c65548d61be149db22c210ea28d121ea7  T-15
```

The committed T-14 and T-15 production implementation hashes also match their
recorded evidence, including `AppStateManager.swift`'s pre-T-16 T-14 baseline
`80079c22009cbef54abb8e2055cb500488499a54d3ba50edd6f24332889651b2`.
The other committed pre-T-16 consumer baselines were:

```text
565b4d664d9c224c305f57b6e8cf454f4487246b244ecec5db39d8fa428a553d  ProductListView.swift
1d0402315db07282893c6d302313987f34861b21c349d501fa027a62fa5c34df  WayTask/HomeView.swift
2d30601201a2eac39673128cdac0f19907a7fe3ef7fc3e93c826d2943a3f70fc  WayTask/ContentView.swift
```

Final T-16 implementation/test hashes before evidence creation:

```text
947e5331f4cc0c09412660b7df515f8b5e5da3eb15909ca2fdf5106c44e4ad54  ProductListView.swift
18b820a22f25586f96d75dc4e2e382c1f373b2e78262495bc1ee583db1f6b922  WayTask/HomeView.swift
3cb8f26fb501854a51d61c9fca9872d2e3ac2fa9977e771ab3b3db30b9509be0  WayTask/ContentView.swift
126e2375780164784f5abbb694018465826ca8562659883bb9d9a6ca42629f16  WayTask/AppStateManager.swift
ffb9729c92a26a42f31d8110f6969d597e22ac0ecb04b8ab8950800b0e107d2b  WayTaskTests/ProductState/ProductStateProductHomeConsumerConversionTests.swift
```

## Scope and inactivity proof

The final source and repository audits prove:

- `HEAD`, `main`, and `origin/main` remain identical at
  `feaf8d1b3730263bde6f146317bb41e509e6ce28`;
- the final review footprint is exactly the four authorized production files,
  the focused T-16 test, and this evidence document;
- `project.pbxproj`, package resolution, schema, migration, startup,
  `WayTaskApp.swift`, Product State commands/queries/repositories/transaction
  coordinator, Shopping presentation, Map, Notifications, and Session have no
  diff;
- no production file invokes `publishProductHomeConsumerState`,
  `presentProductHomeRoute`, or `discardProductHomeConsumerState`; only the
  focused T-16 test exercises those target entry points;
- existing `ProductListView`, `HomeView`, and `ContentView` bodies remain on
  their committed runtime path; T-16 adds the bounded target consumer sections
  without V4 or startup activation;
- target sections contain no `ModelContext`, insert, delete, save, Product
  command, transaction, Session, Shopping write, backfill, acquisition, or
  Restore call;
- route validation uses exact projected Product/List/acquisition identity and
  never display text;
- `git diff --check` and the focused test's trailing-whitespace audit pass; and
- no T-17-or-later path is present in the diff.

This is the required inactivity proof: T-16 compiles and is completely
qualified as a target presentation consumer, but it cannot change production
Product State or V3 runtime behavior before the separately approved cutover.

## Cleanup and review rollback

After result totals, build outcomes, and protected hashes were extracted, all
16 explicitly enumerated T-16 development, focused, affected, Phase 1,
full-suite, Debug, and Release DerivedData/result roots were removed from
`/private/tmp`. The exact post-cleanup search returned no
`/private/tmp/WT033A-T16-*` path. No application-default, protected migration
source, or migration-candidate store was opened by qualification.

Review rollback is source-only: restore the four modified production files to
`HEAD`, then delete the focused T-16 test and this evidence document. Because
the target publisher has no production caller, rollback changes no V3 data,
Product State authority, Plan, acquisition, Catalog, Knowledge, Shopping, Map,
Notification, or Session state.

## Terminal decision

T-16 COMPLETE — READY FOR REVIEW
