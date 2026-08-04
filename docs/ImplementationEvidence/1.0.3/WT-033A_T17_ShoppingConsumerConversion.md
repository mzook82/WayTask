# WT-033A T-17 Shopping Consumer Conversion

## Record status

This document records execution of WT-033A step T-17 only. The step adds and
qualifies the Shopping target presentation consumer in
`WayTask/ShoppingWorkspaceView.swift` and its focused Shopping UX coverage. It
does not begin T-18 or any later step, activate the target consumer, perform the
T-21 authority cutover, or create a commit.

Evidence was collected on 2026-08-04. Production and test behavior was frozen
before the formal qualification sequence. Development preflights preceding
that freeze were used only to discover compile/test defects and are not counted
as qualification.

## Mandatory pre-write gate

The mandatory gate passed before the first write:

- the repository was clean;
- T-01 through T-16 were present as the committed, contiguous implementation
  sequence ending at `ef9fe5975caae637f646b232243ef96b769aecaf`;
- `HEAD`, `main`, and `origin/main` were identical at that full SHA;
- the exact S-02 authority SHA-256 was
  `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361`;
- the S-00 and S-01 authority hashes were respectively
  `16e336f54a4cb644465f1836e9d97410bffc1044de4322581398ab3f8517b920`
  and
  `2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c`;
- every recorded T-06 through T-16 focused-test and protected implementation
  hash matched committed evidence; and
- `project.pbxproj`, package resolution, schema, migration, startup, Product
  State commands/queries/repositories/transaction coordination, Session,
  Product/Home, and T-14/T-15 inputs matched their protected baselines.

The committed step sequence immediately preceding T-17 was T-13 `b2be2ac`,
T-14 `d0351ea`, T-15 `feaf8d1`, and T-16 `ef9fe59`. No mismatch or stop
condition was present.

## Shopping authority and exact footprint

S-02 assigns T-17 exactly:

> Convert Shopping presentation and plan controls.
>
> `WayTask/ShoppingWorkspaceView.swift`; Shopping UX tests.
>
> Needed/Resolved/reason semantics; command-only
> quantity/resolve/reopen/remove; exact list/revision; no `isChecked`/
> `isCompleted` authority.

S-02 also defines T-14 through T-20 as internal conversion stages that are not
independently releasable and reserves the single authority cutover for T-21.
The T-17 rollback boundary is therefore an internally inactive target consumer
whose command/query authority remains intact.

The final review footprint is exactly:

- `WayTask/ShoppingWorkspaceView.swift` — a bounded target presentation
  section consuming immutable T-13/T-14/T-15/T-16 values; the committed legacy
  runtime view below the boundary is not changed;
- `WayTaskTests/ShoppingUX/ProductStateShoppingConsumerConversionTests.swift`
  — 30 focused target presentation tests; and
- this evidence document.

No Map, Notification, Session, startup, migration, schema, V4, dependency,
package, asset, localization, or project file was modified. T-18 and later work
was not started.

## Immutable projection boundary

`ShoppingWorkspaceProjectionConsumer.make` accepts only immutable values from
the committed boundaries:

- T-13 `ProductStateProjectionOutcome<ProductStateNamedListProjection>`;
- T-14 `ShoppingPlanConsumerStatus`;
- T-16 `ProductChooserPresentationState`; and
- T-15 `ProductAcquisitionPresentationState`.

The consumer receives no SwiftData model, `ModelContext`, repository,
transaction coordinator, command coordinator, mutation closure, or Session.
It performs no fetch, insert, delete, save, transaction, restore, acquisition,
Map activation, Notification activation, or Session creation.

The adjacent chooser and acquisition values are retained without execution.
Plan presentation wraps the committed T-14 status through
`ProductHomePlanPresentation` and exposes only exact-list/read-only controls:
empty, generate, generating, current, regenerate, review-list, or unavailable.
It does not create a plan, write a list, or activate a planning service.

`ShoppingWorkspaceListActionRequest` is an inert presentation-intent value
containing exact entry, Product, List, and revision identities. It is not a
Product State command, creates no Product or Shopping command, has no executor,
and is not connected to production runtime. Purchased and legacy-unknown
resolution requests are expressly unavailable from this presentation boundary.

## Shopping ordering

The consumer validates every T-13 entry before presentation:

- projection scope must be the exact named List UUID;
- metadata revision must be the exact List revision;
- every entry UUID must be unique;
- every entry must carry the exact List UUID and Product UUID represented by
  its immutable Product projection;
- each entry must appear in the T-13 section matching its Needed, Resolved, or
  unresolved state; and
- quantity and sort order must be finite, with quantity greater than zero.

Needed, Resolved, and unresolved section arrays retain their T-13 order.
The combined Shopping sequence uses the committed T-13 deterministic ordering:
ascending projected `sortOrder`, with exact entry UUID string as the stable tie
breaker. Search and filters return stable subsequences; they never re-sort,
merge, infer, or substitute entries.

## Shopping grouping

List-order grouping exposes one group containing the exact visible sequence.
Shopping-intent grouping derives only from immutable row values through the
committed T-14 `ShoppingIntentMatcher` and `ShoppingPlanInputItem` boundary.

Group order follows `ShoppingIntentGroup.allCases`. Entry order within every
group is the already-authoritative visible order. A row with unavailable
Product projection, non-active lifecycle, projection issues, or unresolved
intent remains explicit in the final `Needs review` group; it is never silently
dropped or guessed into another group.

## Shopping filters and search

Filters distinguish exactly:

- all entries;
- Needed entries;
- Resolved entries;
- a specific committed resolution reason; and
- unresolved entries.

Filtering does not consult legacy `ShoppingListEntry.isChecked` or
`ShoppingItem.isCompleted` and preserves the incoming order.

Search uses only immutable projected Product presentation fields already used
by Shopping semantics: display name, brand, and category. Text is normalized
deterministically with canonical Unicode composition and fixed `en_US_POSIX`
case/diacritic/width folding. Matching is a stable containment filter over the
projected fields. Search text cannot create, infer, replace, merge, or order a
Product identity.

## Shopping completion presentation

`ShoppingWorkspaceCompletionPresentation` is explicitly read-only
(`isReadOnly == true`). It retains ordered exact entry-ID sets for:

- Needed;
- Resolved;
- unresolved;
- Purchased;
- Already Have;
- No Longer Needed;
- legacy-unknown; and
- unresolved/missing reason.

Counts and the resolved fraction are derived only from those immutable IDs.
The presentation neither writes a completion flag nor creates a Product
completion command. It performs no Product State mutation, List mutation, or
Session creation. A Purchased resolution is display evidence only and cannot
be requested through the T-17 intent boundary.

## Product and List identity preservation

Every row retains the exact T-13 `ProductStateListEntryProjection` and exposes
its exact entry UUID, Product UUID, List UUID, Product lifecycle, state,
quantity, unit, note, and sort order. Display text and Catalog snapshots never
act as identity fallbacks.

Product/List disagreement is a bounded invalid state rather than a fallback.
The Plan source List/revision and every included, excluded, and unresolved plan
entry must belong to the exact current Named List projection. T-16 chooser rows
must also carry the exact List UUID, revision, and Product UUID. A current,
generating, or stale Plan without exact source scope is invalid rather than
implicitly attached to a selected or default List.

Product lifecycle remains presentation evidence only. Removed, missing, or
issue-bearing Product rows cannot produce an action request; no Product is
restored, acquired, activated, completed, or recreated.

## Formal qualification

After behavior was frozen, the required sequence completed in order on an
iPhone 17 Pro iOS 26.5 simulator (`23F77`):

| Gate | Passed | Failed | Skipped | Result |
|---|---:|---:|---:|---|
| Focused T-17, run 1, clean roots | 30 | 0 | 0 | Passed |
| Focused T-17, run 2, separate clean roots | 30 | 0 | 0 | Passed |
| Affected regressions | 589 | 0 | 0 | Passed |
| Exact WT-032B Phase 1 gate | 49 | 0 | 0 | Passed |
| Complete unfiltered `WayTaskTests` | 676 | 0 | 0 | Passed |

The affected bundle covered Shopping UX/classification, T-13 queries, T-14
Plan, T-15 acquisition, T-16 Product/Home, Product and list-entry commands,
command pipeline, repositories, transactions, invariants, transitions,
persistence graph/history, Catalog/Product Knowledge, scanner, migration,
startup/schema, consumer characterization, diagnostics, performance, Map label
regression, and Sentry stability.

The exact Phase 1 gate comprised:

- `ProductStateCharacterizationSupportSelfTests`;
- `ProductStateDomainCharacterizationTests`;
- `ProductStatePersistenceCharacterizationTests`;
- `ProductStateConsumerCharacterizationTests`;
- `ProductStateDiagnosticsCharacterizationTests`; and
- `ProductStatePerformanceBaselineTests`.

The complete run emitted one transient cloned-simulator launch denial. Xcode
recovered the worker within the same invocation; the command exited zero and
the finalized result bundle reported `Passed` with 676 passed, zero failed,
zero skipped, and zero expected failures. A device-services notification-proxy
warning was also non-terminal and did not change the selected simulator.

The only compiler warning was the pre-existing unused `legacyByID` local in
`WayTaskTests/ProductCatalog/ProductCatalogMigrationTests.swift`; T-17 did not
change that file. Xcode also repeated the pre-existing Sentry symbol-upload
dependency-analysis note.

Qualification used Xcode 26.6 (`17F113`), Swift 6.3.3, and macOS 26.6.

## Builds

Both required unsigned generic iOS builds used `CODE_SIGNING_ALLOWED=NO` and
separate clean DerivedData roots:

| Configuration | Destination | Result |
|---|---|---|
| Debug | `generic/platform=iOS` | `BUILD SUCCEEDED` (exit 0) |
| Release | `generic/platform=iOS` | `BUILD SUCCEEDED` (exit 0) |

No T-17 compilation warning was introduced.

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

The committed T-06 through T-16 focused tests remain byte-exact:

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
ffb9729c92a26a42f31d8110f6969d597e22ac0ecb04b8ab8950800b0e107d2b  T-16
```

Committed T-14 production hashes for `BuyingOptionsService.swift`,
`DecisionEngine.swift`, `DiscoverViewModel.swift`, `ShoppingContext.swift`,
`ShoppingIntentMatcher.swift`, `ShoppingTripService.swift`,
`StoreRankingService.swift`, and `StoreSearchService.swift` remain exact.
Committed T-15 hashes for `CameraViewModel.swift`,
`ProductKnowledgeService.swift`, `AddProductSaveCoordinator.swift`, and
`AddProductAutocompleteViewModel.swift` also remain exact. T-16 production
hashes remain:

```text
947e5331f4cc0c09412660b7df515f8b5e5da3eb15909ca2fdf5106c44e4ad54  ProductListView.swift
18b820a22f25586f96d75dc4e2e382c1f373b2e78262495bc1ee583db1f6b922  WayTask/HomeView.swift
3cb8f26fb501854a51d61c9fca9872d2e3ac2fa9977e771ab3b3db30b9509be0  WayTask/ContentView.swift
126e2375780164784f5abbb694018465826ca8562659883bb9d9a6ca42629f16  WayTask/AppStateManager.swift
```

The pre-T-17 `ShoppingWorkspaceView.swift` hash was
`f7ebb56e6a2702082ddd39481161ef77cd25874382172b19bf0fcab84badd307`.
Final T-17 implementation/test hashes before evidence creation are:

```text
4677ffffe286d17de19361c866d1255a7369937f03dbd0f6e062ce13ba47b7db  WayTask/ShoppingWorkspaceView.swift
e6a35fb72f0725ba423bfccc55f97012fcd633c56c5b3c08f40e74537a639b0c  WayTaskTests/ShoppingUX/ProductStateShoppingConsumerConversionTests.swift
```

## Scope and inactivity proof

The final source and repository audits prove:

- `HEAD`, `main`, and `origin/main` remain identical at
  `ef9fe5975caae637f646b232243ef96b769aecaf`;
- the final review footprint is exactly the authorized Shopping production
  path, focused test, and this evidence document;
- `project.pbxproj`, package resolution, schema, migration, startup,
  `WayTaskApp.swift`, Product State commands/queries/repositories/transaction
  coordinator, Product/Home, Map, Notifications, Session, and T-06 through
  T-16 committed paths have no diff;
- no production path invokes `ShoppingWorkspaceProjectionConsumer.make`;
- the target section ends before the committed runtime
  `ShoppingWorkspaceView` and contains no `@Query`, `ModelContext`, legacy
  `ShoppingItem`/`ShoppingListEntry`, `isChecked`, `isCompleted`, Product or
  Shopping command, transaction, Session, save, delete, restore, acquisition,
  Map, or Notification authority;
- the target action value has no executor and is limited to exact immutable
  row/List/revision identities;
- the legacy runtime body remains byte-identical within the modified file;
  T-17 adds only the bounded target section before it;
- `git diff --check` and the focused trailing-whitespace/static audits pass;
  and
- no T-18-or-later path is present in the diff.

This is the required inactivity proof: T-17 compiles and is fully qualified as
the target Shopping presentation consumer, but it cannot mutate Product State,
change V3 runtime behavior, or activate any later consumer before the separate
T-21 cutover.

## Cleanup and review rollback

After result totals, build outcomes, versions, and protected hashes were
extracted, all 20 explicitly enumerated T-17 development, focused, affected,
Phase 1, full-suite, Debug, and Release DerivedData/result roots were removed
from `/private/tmp`. The exact post-cleanup search returned no
`WT033A-T17-*` path.

No source fixture, store, sidecar, attachment, generated file, or qualification
artifact remains. No commit was created. Removing the bounded T-17 target
section, its focused test, and this evidence document restores the exact
pre-T-17 checkout without changing committed Product State authority.

T-17 COMPLETE — READY FOR REVIEW
