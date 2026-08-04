# WT-033A T-19 Shopping Session Authority — Implementation Evidence

Date: 2026-08-04

Execution scope: WT-033A S-02 T-19 only

Release posture: compiled and qualified, internally inactive, not committed

## Pre-write verification

All required stop-condition checks passed before the first write:

- the repository was clean on `main`;
- `HEAD`, `main`, and `origin/main` were identical at
  `ee19bcf5d87a59cc2dccb99ed01367b48199b4c7`;
- T-01 through T-18 were committed contiguously from `d81df92` through
  `ee19bcf`;
- the final committed sequence was T-13 `b2be2ac`, T-14 `d0351ea`, T-15
  `feaf8d1`, T-16 `ef9fe59`, T-17 `591c258`, and T-18 `ee19bcf`;
- S-00, S-01, and S-02 SHA-256 values were respectively
  `16e336f54a4cb644465f1836e9d97410bffc1044de4322581398ab3f8517b920`,
  `2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c`,
  and
  `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361`;
- committed T-06 through T-18 tests and protected production inputs matched
  their recorded evidence hashes; and
- project, package, schema, migration, startup, repository, Product/history,
  legacy Session, Shopping, Map, Location, Notification, and geofence files
  matched their committed baselines.

No pre-write mismatch or stop condition existed.

## Exact S-02 T-19 authority and footprint

S-02 assigns T-19:

> Integrate co-approved normalized Session lifecycle, conflict handling,
> collection isolation, and atomic Finish.
>
> TC-11, TC-16, TC-04–TC-07; Session/Finish tests.
>
> Exact source snapshot; no silent reuse; protected entries; all outcomes;
> Finish one commit; Abandon no list/purchase effect; relaunch stable.
>
> Forward-compatible Session feature disable; never reopen with legacy Session
> writer.
>
> D-03–D-05, D-12, D-13, D-14, D-15, D-16, D-28–D-29, D-32, D-36.

The execution authorization further requires exact Session/List/Plan/entry/
Product/store identity, explicit lifecycle and recovery outcomes, immutable
Shopping/Map reads, and no T-20 or T-21 activation. The final pre-evidence
footprint is exactly:

- `WayTask/ProductState/Application/ProductStateShoppingSessionAuthority.swift`
  — the sole inactive normalized Session command authority;
- `WayTask/ProductState/Application/ProductStateCommands.swift` — additive
  Session effect and reconciliation values;
- `WayTask/ProductState/Application/ProductStateTransactionCoordinator.swift`
  — additive atomic validation, commit verification, and retry reconciliation
  for Session effects;
- `WayTask/ProductState/Application/ProductStateQueries.swift` — bounded exact
  current-list validation for Finish review while retaining the committed
  historical T-13 query behavior when no current revision is supplied;
- `ShoppingSessionService.swift` — an additive inactive façade exposing
  immutable T-13 reads and delegating writes to the sole T-19 authority; the
  legacy service body is unchanged;
- `WayTaskTests/ProductState/ProductStateShoppingSessionAuthorityTests.swift`
  — 17 focused tests; and
- this implementation-evidence document.

No project-file edit was needed because the existing synchronized source and
test groups discovered the new files automatically.

## Session identity and ownership

`ProductStateShoppingSessionCommandAuthority` accepts value-only command inputs
and preserves:

- exact `ProductStateSessionID` and Session revision;
- exact source `ProductStateListID` and durable List revision;
- exact `ProductStatePlanID`, canonical Plan fingerprint, and Plan evidence
  time;
- exact snapshot ID and deterministic SHA-256 content signature;
- exact entry, Product, line, stop, and store-reference identities;
- exact line and stop ordering; and
- exact command IDs, transition times, receipts, affected revisions, and
  deterministic Finish history-event IDs.

Start validates the command scope against the Plan owner, source List UUID and
revision, included-entry sequence, Product identities, stops, line assignments,
and snapshot identity. Display names are retained only as approved snapshots;
they never select or repair a Product, List, Plan, entry, stop, or Session.

A non-terminal Session is never silently reused. One existing candidate returns
an explicit conflict requiring a user decision; multiple candidates return a
deterministically ordered `nonTerminalSessions` conflict. Foreign ownership,
duplicate identity, stale Session/List revision, changed captured entries, and
missing exact rows have named bounded outcomes.

## Plan, List, revision, and entry binding

The Session freezes one Plan/List source snapshot. Plan evidence at or before 24
hours is fresh; evidence older than 24 hours and no older than seven days
requires an exact confirmation timestamp; future or older-than-seven-day
evidence is invalid. Confirmation never changes the Plan fingerprint or source
identity.

Captured entries are protected by the committed T-11 command boundary. A later
uncaptured List addition is permitted but does not enter the Session. Resume
retains the frozen source revision, Plan, entries, lines, and stops. Finish
requires the exact current List revision supplied by its command and verifies
that each captured entry still has one exact needed membership and one active
exact Product. No revision substitution, Plan refresh, default List, recent
List, first Plan, or display-text fallback exists.

## Lifecycle and transitions

The normalized lifecycle is `active`, `expired`, `finished`, or `abandoned`:

- Start creates a complete snapshot atomically and returns `started` only after
  the transaction coordinator proves durable commit.
- Collect and undo change only provisional Session line execution state.
  Collected is never treated as purchased.
- Selected, completed, skipped, and external-navigation-started stop activities
  are explicit commands. They are Session-only meaningful activity and advance
  the Session revision exactly once.
- Expiration is explicit at the inclusive earliest boundary of 12 hours without
  meaningful activity or 72 hours after activation. It never auto-finishes or
  resolves entries.
- Resume is valid only from `expired`, validates exact ownership/revision, and
  starts a new activation window without rewriting the frozen snapshot.
- Abandon is explicit from `active` or `expired`, becomes terminal, preserves
  snapshot/progress, and has no List, Product, or purchase-history effect.
- Finish is valid only from `active`; expired Sessions must be explicitly
  resumed and stale or terminal commands are rejected.

Backdated transitions, duplicate identities, stale revisions, invalid command
shape, invalid migration condition, wrong lifecycle, missing identity, and
unknown transaction outcome all fail closed. Same-command retry reconciles to
the already committed effect; a different command against a terminal Session is
rejected. Every durable result includes the exact command receipt and revision
evidence.

## Atomic Finish and history evidence

Finish requires one explicit outcome for every line. The approved six outcomes
are `purchased`, `alreadyHave`, `noLongerNeeded`, `unavailable`, `skipped`, and
`carriedForward`; no line is discarded or defaulted.

- `purchased`, `alreadyHave`, and `noLongerNeeded` resolve the exact source
  entries with their exact resolution reasons.
- `unavailable`, `skipped`, and `carriedForward` keep the exact source entries
  needed.
- every line records its final outcome, command ID, and effective time;
- every line appends one deterministic Product-UUID-keyed `sessionOutcome`
  history event with `sessionFinish` provenance;
- the exact source List revision advances once regardless of line count;
- Product identity, lifecycle, and Product revision remain unchanged; and
- Session finish, line outcomes, entry reconciliation, one List revision
  advance, and all history events form one prepared effect set and one T-05
  coordinator commit.

Injected-save failure proved rollback of the Session, lines, List, entries, and
history together. Same-command Finish retry creates no duplicate history and no
second List revision; another Finish command sees terminal state.

## Migration, recovery, and relaunch behavior

Native and exact `legacyMapped` Sessions can use the command boundary. A mapped
legacy Session preserves unknown source revision as unknown and never
fabricates a Plan identity. `legacyIncomplete` and `legacyUnresolved` evidence
cannot Finish until the committed authority has an explicit exact recovery;
unresolved or ambiguous identity is never guessed.

File-backed qualification reopened the target store and recovered the same
Session UUID, source owner, source revision state, Plan fingerprint, snapshot,
line/stop ordering, provisional progress, lifecycle, and revision. Multiple
legacy candidates remain explicit and may be individually abandoned without
outcome inference.

## Command, repository, and transaction authority

The new command authority imports `CryptoKit` and `Foundation`, not `SwiftData`.
It receives committed repositories and the T-05 transaction coordinator. It
does not create a `ModelContext`, open a transaction, or call `save()` directly.
All mutations are staged as named `ProductStateStagedEffect` values; the
coordinator validates before/after revisions and semantic state, performs the
single coordinated save, rolls back failures, and reconciles supported retries.

Repositories remain persistence mechanics only and do not decide Session
lifecycle policy. Presentation remains non-authoritative and has no repository,
transaction, context, or mutation closure.

## Immutable Shopping and Map consumer inputs

`ProductStateShoppingSessionService` returns only committed immutable T-13
projection outcomes:

- exact active-candidate lookup;
- exact Session snapshot;
- exact Finish review; and
- exact Session-owned Shopping/Map context.

Finish review requires an active Session and, when supplied by T-19, validates
the exact current List revision plus every captured entry/Product relationship.
The optional parameter preserves committed T-13 historical-query behavior for
existing qualified consumers.

The façade delegates commands to the sole command authority but has no
production caller. T-17 and T-18 presentation consumers remain internally
inactive; neither was edited or connected to the runtime. This is a bounded
non-cutover internal boundary only.

## T-20/T-21 and prohibited-system inactivity proof

Static and diff audits prove:

- no production path constructs `ProductStateShoppingSessionCommandAuthority`
  or `ProductStateShoppingSessionService`;
- `WayTaskApp.swift`, startup, migration, schema declarations,
  `project.pbxproj`, package resolution, assets, localization, and dependencies
  have no diff;
- the new authority has no Notification, geofence, `CLCircularRegion`,
  `UNUserNotificationCenter`, monitoring, or remote-notification dependency;
- `LocationManager.swift` and `GeofenceNotificationService.swift` remain
  byte-exact;
- no post-commit Notification/geofence reconciliation was implemented;
- no navigation, Shopping, Map, or presentation surface activates a Session;
- no legacy Session writer was reopened or invoked by the target boundary; and
- no T-20 or T-21 runtime cutover exists in the diff.

The authority operates on the already-committed inactive T-02 V4 persistence
types, but V4 is not activated: startup, migration, default-container selection,
and all production call sites are unchanged. T-21 remains the only authorized
runtime cutover.

## Formal qualification

Production behavior and test expectations were frozen before the formal
sequence. No production or test file changed after freeze. The required gates
then completed in order:

| Gate | Passed | Failed | Skipped | Result |
|---|---:|---:|---:|---|
| Focused T-19 run 1, clean root | 17 | 0 | 0 | Passed |
| Focused T-19 run 2, separate clean root | 17 | 0 | 0 | Passed |
| Affected regressions | 201 | 0 | 0 | Passed |
| Exact WT-032B Phase 1 gate | 49 | 0 | 0 | Passed |
| Complete unfiltered `WayTaskTests` | 734 | 0 | 0 | Passed |

The exact Phase 1 gate comprised
`ProductStateCharacterizationSupportSelfTests`,
`ProductStateDomainCharacterizationTests`,
`ProductStatePersistenceCharacterizationTests`,
`ProductStateConsumerCharacterizationTests`,
`ProductStateDiagnosticsCharacterizationTests`, and
`ProductStatePerformanceBaselineTests`.

The authoritative full pass ran all 734 tests on a clean task-owned iPhone 17
Pro iOS 26.5 simulator (`23F77`) with one isolated parallel worker. The result
reported zero failed, skipped, or expected-failure tests. All 17 T-19 tests
passed inside that unfiltered invocation.

Three preceding full-suite invocations were rejected as qualification evidence
without changing production or tests:

1. A four-clone invocation passed 733/734; the working-copy support digest
   reported `source-mutated` under clone I/O contention. The same support test
   passed the exact Phase 1 gate and subsequent full runs.
2. A serial invocation on the long-lived simulator passed 733/734; an unrelated
   shared Catalog JSON test received an asynchronous legacy Core Data
   `Product.revision` KVC exception. That test had passed the prior invocation.
3. A clean-device serial invocation passed 733/734; the same asynchronous KVC
   exception surfaced in an unrelated in-memory autocomplete test. The exact
   failing test then passed 1/1 unchanged, and passed again inside the final
   unfiltered run.

The final fresh-device, worker-isolated full invocation removed both observed
environmental hazards and is the sole full-suite result counted above.

Qualification used Xcode 26.6 (`17F113`), Apple Swift 6.3.3
(`swiftlang-6.3.3.1.3`), and macOS 26.6 (`25G72`).

## Builds

Both required builds used `CODE_SIGNING_ALLOWED=NO` and separate clean roots:

| Configuration | Destination | Result |
|---|---|---|
| Debug | `generic/platform=iOS` | `BUILD SUCCEEDED` (exit 0) |
| Release | `generic/platform=iOS` | `BUILD SUCCEEDED` (exit 0) |

No T-19 compiler error or warning was introduced. Xcode repeated the existing
Sentry artifact-identity/dependency-analysis notes only.

## Protected hash audit

Every prohibited or unchanged protected value matched its pre-write baseline:

```text
16e336f54a4cb644465f1836e9d97410bffc1044de4322581398ab3f8517b920  S-00 authority discovery
2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c  S-01 authority specification
49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361  S-02 technical roadmap
9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f  project.pbxproj
42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244  Package.resolved
90841edae9796af551c453f6a3bcb65737db975a61a05505ccdb3bcef0e8f9b8  WayTaskSchema.swift
1c79711332281f4b24af81696c7242784596bcdaa8b92f35fb17b9ca757418e8  WayTaskProductStateMigration.swift
f1729caf5c33cc7de19b0cd751ae0fdb6480190a4773ec8bf37e589fcd59b849  WayTaskStartupPersistence.swift
e549cd17859e9eac584a493e3b2654fb000d59cd2d6bf6d4a191bb11094d5262  ProductStateRepositories.swift
57dd2b13e4e68d2292e5b45f5fe090f3b64344fe4c777a91f19cc47961e8da8c  ProductHistory.swift
86c66430467c2b8b15a104c11cf0394709d4767a2e3ba7d1fbd2e711222eb8d5  ShoppingSession.swift
5a460b45f2922c096ee1a81ddd7da27fe13df49c50d632d1b5c91d568bb04251  WayTaskApp.swift
20660f1608a5ca4d499c09062fa31c9a0d5f6363ce8df08913d3364fafb5a3a6  ShoppingMemoryService.swift
656546d6a770ee5658d6aaf71f34ff450ff4215da6a068aae95981800a2cbb1d  ProductCatalogPersonalization.swift
028b5660c5e0ccdd8c73e9442a510fdc25cd6dbdd141d6e16c6e7ff1c038e07f  LocationManager.swift
bcbb1f076808897949ecdc9f445cea98f3f28dd51947c6437a58029869f76c4f  GeofenceNotificationService.swift
```

Committed T-06 through T-18 focused tests remain byte-exact:

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
e6a35fb72f0725ba423bfccc55f97012fcd633c56c5b3c08f40e74537a639b0c  T-17
9a49c78fee2f36016e72b7942260645772496e28cfd4acc76af8fba8425d0da3  T-18
```

Committed T-14 through T-18 production inputs remain exact. Representative
complete consumer-boundary values are:

```text
3c0a99d12c3cde8e7c1445eba5d27e604c88846e9b90e60bbd13faab42a0acb5  BuyingOptionsService.swift
cea54550e54868f7e3c1f5e38d927ab164eef74dc0f1bdcc6cfb03325425b554  DecisionEngine.swift
53ecdc967798d074023a217ec2a6ced38eb4eb1afa5e9666575a839bea43ed18  DiscoverViewModel.swift
5443e39e39f1fa9520ac6ec2db497d8a3cd228e79d003f609449fa8cd55426a1  ShoppingContext.swift
e3a29037fb3a0fd3fc2501ea62f0408bc02a47b3caf1d4c2804af3a004541fbf  ShoppingIntentMatcher.swift
7c94d7e281fd964e9b64bfedb4d98b93dde47a17e765662369d25933d0b07b40  ShoppingTripService.swift
05f5f763a9f64ca5456a9029e233ef4feb577f05d4d120c364e43c6734d9762f  StoreRankingService.swift
950588da093578bcd12de04fff169736636ea9f2b5befb789e275dcdedfd3726  StoreSearchService.swift
5de1559f69c7a9817309edd4dca18f26772cbd40967caa18f89118945b5c25b9  CameraViewModel.swift
68ef1d8c173fcc1c69501e34540003d66b916c5fbe7f00cb000cce1cc321a606  ProductKnowledgeService.swift
a0b7979e02ed0fcd66f760cb116eaf9c7bdf5d0c91365f030c596dbabf10dbac  AddProductSaveCoordinator.swift
c9864144ad8d1df38dc93e7a08226d2461c111d4ccfaa14adb96d30cb40da2d4  AddProductAutocompleteViewModel.swift
947e5331f4cc0c09412660b7df515f8b5e5da3eb15909ca2fdf5106c44e4ad54  ProductListView.swift
18b820a22f25586f96d75dc4e2e382c1f373b2e78262495bc1ee583db1f6b922  HomeView.swift
3cb8f26fb501854a51d61c9fca9872d2e3ac2fa9977e771ab3b3db30b9509be0  ContentView.swift
126e2375780164784f5abbb694018465826ca8562659883bb9d9a6ca42629f16  AppStateManager.swift
4677ffffe286d17de19361c866d1255a7369937f03dbd0f6e062ce13ba47b7db  ShoppingWorkspaceView.swift
1c98a9151c3c4516239cafab7fa58d9fcf57efbb9f361216d0d9d4b340a3762e  MapViewModel.swift
84ad3ea92cbfcf39b3f7b245b73a5f9e792a9c96129cdfe76cb34cc26599b9bf  MainMapView.swift
78673e72e74e288311aea849aeda588ad72dd9b23b74b92cd007bb586b9bd2a2  LocationDetailView.swift
```

The authorized tracked T-19 files began with:

```text
ea44ca295b4140937686d9d3b68cd63dec10b1a742c9c3e05c6af2c62961d5a3  ShoppingSessionService.swift
58e70e75cb74d5d5c43cac4074e8dd5c045805d28f0d9b5093c3f7758180c177  ProductStateCommands.swift
92e10ebd622314f026ccd83f92b88f7d863a5a21c532246c9969fae9c97b5b37  ProductStateQueries.swift
3ae8e4aadd9e427de50cdca0d20fe7037a5cdb546043d63f9dcd9f3c9d3d264a  ProductStateTransactionCoordinator.swift
```

Final implementation/test hashes before evidence creation are:

```text
945f0ca6b49a9e23d8f8c01fd12054f6668d9989287aa59abb8385f7f2bed74d  ShoppingSessionService.swift
2be900813206efee8040a346d26de0daa714bc2fe3c51067ff346d102c73913a  ProductStateCommands.swift
f35afed463f2f5cbdfe53e63020475683e1e097bd5020fafe62833003392698e  ProductStateQueries.swift
8b68aacf49d0b37952a4120e3b0e23f7794dba6a26db89601b3ae8d9e526ec30  ProductStateTransactionCoordinator.swift
ac286876a6a54df8b75d3293260bc201e239e38d6bd0d874b1c779c81d43ffc5  ProductStateShoppingSessionAuthority.swift
7e2e5700e03a59154cfa7fb44148526dd6cbd260dc751525e3c1a96cbd311943  ProductStateShoppingSessionAuthorityTests.swift
```

## Scope audit

Final pre-evidence audits prove:

- `HEAD`, `main`, and `origin/main` remain identical at
  `ee19bcf5d87a59cc2dccb99ed01367b48199b4c7`;
- the only production diffs are the five exact T-19 authority/boundary files;
- the only test addition is the focused T-19 suite;
- `git diff --check` passes;
- the target façade is additive after the byte-unchanged legacy Session service;
- there is no runtime construction or call site for either target Session type;
- no direct `save()`, context, independent transaction, presentation mutation,
  legacy fallback, Notification, or geofence code appears in the T-19 additions;
- T-06 through T-18 focused tests and committed consumer production files are
  byte-exact;
- no project, package, dependency, asset, localization, startup, migration,
  schema, default-container, V4 activation, T-20, or T-21 path is modified; and
- no commit was created.

## Cleanup and rollback

After all totals, builds, versions, diagnostics, and hashes were extracted, 23
explicitly enumerated T-19 development, diagnostic, focused, affected, Phase 1,
full, Debug, Release, package, DerivedData, and result-bundle roots were removed
from `/private/tmp`. The post-cleanup search returned no `WT033A-T19-*` path.

Two task-owned shutdown simulators were also deleted:

- `DBFCB823-AD16-46CE-9A2E-2B0D46D1A3B1` (`WT033A-T19-Full`); and
- `9FA810B3-125F-4899-BCC2-07E3485EE6F0` (`WT033A-T19-Full2`).

The post-cleanup simulator search returned no T-19 device. These caches,
result bundles, and simulators are not recoverable; no repository source,
fixture, store, sidecar, attachment, migration input, or user simulator was
removed.

Review rollback is source-only: remove the new authority and focused test,
remove the additive Session effect/query/coordinator/façade changes, and remove
this evidence file. Because the boundary has no runtime caller and V4 remains
inactive, rollback requires no Product, List, Plan, Session, history, Map,
Notification, geofence, startup, migration, schema, or data repair. The legacy
Session writer must remain disabled for target authority and must never be used
as rollback authority.

## Terminal decision

T-19 COMPLETE — READY FOR REVIEW
