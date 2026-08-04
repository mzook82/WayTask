# WT-033A T-18 Map Consumer Conversion

## Record status

This document records execution of WT-033A step T-18 only. The step adds and
qualifies the internally inactive target Map presentation boundary. It does not
begin T-19 or later work, activate the target consumer, perform the T-21
cutover, or create a commit.

Evidence was collected on 2026-08-04. Production behavior and test
expectations were frozen before the formal qualification sequence. Earlier
development runs were used only for defect discovery and are not counted as
formal qualification.

## Mandatory pre-write gate

The mandatory gate passed before the first write:

- the repository was clean;
- T-01 through T-17 were committed as a contiguous implementation sequence;
- `HEAD`, `main`, and `origin/main` were identical at
  `591c25889b0c75cb3e7f6494c681c1cff5f0a099` on `main`;
- S-00, S-01, and exact S-02 authority SHA-256 values were respectively
  `16e336f54a4cb644465f1836e9d97410bffc1044de4322581398ab3f8517b920`,
  `2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c`,
  and
  `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361`;
- every recorded T-06 through T-17 test and protected implementation hash
  matched committed evidence; and
- project, package, schema, migration, startup, Product State, Session,
  T-14 through T-17 inputs, Location infrastructure, and the existing Map
  files matched their protected baselines.

The final sequence immediately preceding T-18 was T-13 `b2be2ac`, T-14
`d0351ea`, T-15 `feaf8d1`, T-16 `ef9fe59`, and T-17 `591c258`. No mismatch or
stop condition was present.

## Exact S-02 authority and footprint

S-02 assigns T-18:

> Convert Map, saved locations, discovery, store recommendations, and reminder
> input creation.
>
> TC-25, TC-28; `WayTask/LocationManager.swift` input boundary;
> Map/location/consumer tests.
>
> Explicit list/plan/Session context; no global fallback; saved-location notes
> separated; store estimates read-only; parity/exclusions proven.

The execution authorization narrows this step to the Map presentation
conversion and expressly prohibits Session authority, geofence/Notification
work, T-19/T-20/T-21 behavior, startup, migration, schema, V4, dependencies,
assets, localization, and `project.pbxproj` changes. The exact final footprint
before this evidence file is:

- `MapViewModel.swift` — additive immutable target Map projection consumer;
- `WayTask/MainMapView.swift` — additive target screen presentation adapter;
- `WayTask/LocationDetailView.swift` — additive exact saved-location detail
  adapter and inactivity marker; and
- `WayTaskTests/Map/ProductStateMapConsumerConversionTests.swift` — 41 focused
  tests.

`WayTask/LocationManager.swift` was evaluated as the authorized optional input
boundary but was not needed for the presentation-only conversion and remains
byte-exact. `GeofenceNotificationService.swift`, Session, and Notification
surfaces are untouched. The legacy runtime bodies remain unchanged, and the
target presentation has no production caller. This is the required internal
feature-disable posture before T-21.

## Immutable Map inputs

`ProductStateMapProjectionConsumer.make` accepts immutable values only:

- committed T-17 `ShoppingWorkspaceProjectionConsumerState`, retaining the
  exact Named List UUID, durable revision, entry order, and T-14 Plan state;
- committed T-13 Map context, discovery context, store recommendation, and
  saved-location evidence projection outcomes;
- committed T-14 `ShoppingPlanStoreCoverage` values; and
- immutable store presentation inputs adapted from committed store discovery
  and ranking output.

The store adapter copies value semantics and deliberately ignores legacy
`itemNames` and `completedItemNames`. The target receives no SwiftData object,
`ModelContext`, repository, command/transaction coordinator, mutation closure,
Session service, notification center, geofence, or navigation executor.

Unavailable inputs remain explicit. Projection freshness produces named stale
or unavailable output; Plan staleness and unavailability remain separately
named. Invalid scope, revision, provenance, ordering, identity, coverage, or
selection produces a bounded invalid state rather than a fallback.

## Product, List, and Store identity preservation

Every marker carries the exact List UUID and durable revision. Product markers
carry `ProductStateProductID` directly. Store markers use the exact UUID and
retain the exact T-13 published store-ID string. Saved-location markers and
details carry the exact location UUID and authoritative Product/List/entry
links.

The consumer validates Shopping List scope/revision, Plan source and included
entry sequence, Map/discovery/recommendation owner and provenance, published
store evidence, Store UUID existence/uniqueness, exact entry-to-Product
relationships, and exact selection scope. Display names participate only in
display and search; they never infer or replace identity. Missing stores,
duplicate markers, mismatched links, unknown selection, or mismatched scope is
rejected explicitly.

Session-owned context and any `sessionLineID` produce the explicit invalid
reason `sessionContextRequiresT19`. No Session is queried, created, updated,
selected, reused, or treated as authority in T-18.

## Marker and recommendation ordering

Equivalent immutable inputs produce the same marker and clustering sequence:

1. saved locations by exact UUID, followed by exact current-List Product links
   in committed link order;
2. stores by exact UUID; and
3. each store's covered Products in committed T-13 Product-ID order.

Store Product markers use exact Product/Store IDs; saved-location Product
markers also include exact entry and location IDs. Duplicate final marker
identity is invalid instead of silently merged. `clusteringInputIDs` is exactly
the marker sequence, with no independent fallback sort.

Recommendation order must equal the committed T-13 deterministic order:
covered count descending, confidence descending, exact store ID, evidence time,
then exact Product-ID coverage. Covered/uncovered Product arrays must be
canonical, disjoint, and together equal the exact discovery eligible set.

Coverage must equal committed T-14 order and use a unique Store/group identity.
The presentation retains exact matched/missing entry and Product IDs, coverage
score, distance, ranking score/confidence, reasons, signals, estimated-only
claim, named exclusions, and unresolved classification entries. Coverage
without a corresponding recommendation is rejected.

## Selection, filtering, and search

Selection is an immutable exact marker/List/revision value. A selected marker
remains named even when hidden by a filter; `isVisible` records that state. An
unknown marker or mismatched List/revision is invalid, never a first-marker
fallback.

Filters produce stable subsequences for all, open stores, Shopping List,
stores, Products, saved locations, unresolved values, or one exact Product
UUID. The Shopping List filter retains an exact scoped saved location when it
has an exact current-List link. Unresolved rows remain explicit and ordered.

Search uses immutable display snapshots only, with canonical Unicode
composition and fixed `en_US_POSIX` case/diacritic/width folding. A Product-name
match retains the exact Product marker and its owning recommended store or
exact linked saved-location marker. Search cannot change identity, ordering,
selection, reasons, or coverage.

## Saved, unresolved, and unavailable presentation

Saved-location title, note, coordinate, links, issues, and metadata remain
separate immutable fields. The note is never identity. A current-List exact
link must match an exact entry/Product relationship. Another-List link remains
`outsideCurrentList`; an unproven link remains `unproven`.

Missing and half-present coordinates remain named issues; invalid ranges are
rejected. Unavailable location outcomes remain listed by exact location scope.
The detail consumer returns `notFound(exactID)` rather than choosing another
location.

Shopping unresolved entries, Plan classification-unresolved entries,
discovery unresolved items, and non-current saved-location links retain source
and ordinal. Named exclusions retain exact entry, Product, and reason evidence.
Nothing unresolved or excluded is silently dropped or fabricated into
coverage.

## Navigation and read-only proof

Navigation output is an inert enum created only when requested for an exact
existing marker. It contains exact Product, List, revision, Store, location,
and coordinate values as applicable. It never calls `openURL`, `MKMapItem`,
`openInMaps`, or route activation.

Static audits of all bounded target sections found no `@Query`, `ModelContext`,
legacy completion authority, Product/List command coordinator, transaction
coordinator, Session service, save, insert/delete, acquisition, restore,
notification center, geofence, monitoring, or platform navigation execution.
The target cannot mutate Product State or Lists, create commands or Sessions,
alter the Plan, acquire/restore Products, schedule Notifications, create
geofences, or activate navigation.

## Formal qualification

After behavior and expectations were frozen, the required sequence completed
in order on an iPhone 17 Pro iOS 26.5 simulator (`23F77`):

| Gate | Passed | Failed | Skipped | Result |
|---|---:|---:|---:|---|
| Focused T-18 run 1, clean root | 41 | 0 | 0 | Passed |
| Focused T-18 run 2, separate clean root | 41 | 0 | 0 | Passed |
| Affected regressions | 655 | 0 | 0 | Passed |
| Exact WT-032B Phase 1 gate | 49 | 0 | 0 | Passed |
| Complete unfiltered `WayTaskTests` | 717 | 0 | 0 | Passed |

The affected gate covered Map/location, Shopping/classification, T-13 through
T-17 boundaries, Product/list commands, repositories/transactions/invariants,
persistence/history, Catalog/Product Knowledge, scanner, migration,
startup/schema, characterization/performance, and Sentry stability.

The exact Phase 1 gate comprised support self-tests and Product State domain,
persistence, consumer, diagnostics, and performance suites. The only compiler
warning was the pre-existing unused `legacyByID` in
`ProductCatalogMigrationTests.swift`; Xcode also repeated the pre-existing
Sentry dependency-analysis note. No T-18 warning was introduced.

Qualification used Xcode 26.6 (`17F113`), Apple Swift 6.3.3, and macOS 26.6
(`25G72`).

## Builds

Both builds used `CODE_SIGNING_ALLOWED=NO` and separate clean roots:

| Configuration | Destination | Result |
|---|---|---|
| Debug | `generic/platform=iOS` | Succeeded, exit 0 |
| Release | `generic/platform=iOS` | Succeeded, exit 0 |

## Protected hash audit

Every protected value matched its pre-write baseline after qualification:

```text
16e336f54a4cb644465f1836e9d97410bffc1044de4322581398ab3f8517b920  S-00 authority discovery
2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c  S-01 authority specification
49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361  S-02 technical roadmap
9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f  project.pbxproj
42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244  Package.resolved
90841edae9796af551c453f6a3bcb65737db975a61a05505ccdb3bcef0e8f9b8  WayTaskSchema.swift
1c79711332281f4b24af81696c7242784596bcdaa8b92f35fb17b9ca757418e8  WayTaskProductStateMigration.swift
f1729caf5c33cc7de19b0cd751ae0fdb6480190a4773ec8bf37e589fcd59b849  WayTaskStartupPersistence.swift
3ae8e4aadd9e427de50cdca0d20fe7037a5cdb546043d63f9dcd9f3c9d3d264a  ProductStateTransactionCoordinator.swift
e549cd17859e9eac584a493e3b2654fb000d59cd2d6bf6d4a191bb11094d5262  ProductStateRepositories.swift
57dd2b13e4e68d2292e5b45f5fe090f3b64344fe4c777a91f19cc47961e8da8c  ProductHistory.swift
86c66430467c2b8b15a104c11cf0394709d4767a2e3ba7d1fbd2e711222eb8d5  ShoppingSession.swift
5a460b45f2922c096ee1a81ddd7da27fe13df49c50d632d1b5c91d568bb04251  WayTaskApp.swift
20660f1608a5ca4d499c09062fa31c9a0d5f6363ce8df08913d3364fafb5a3a6  ShoppingMemoryService.swift
656546d6a770ee5658d6aaf71f34ff450ff4215da6a068aae95981800a2cbb1d  ProductCatalogPersonalization.swift
92e10ebd622314f026ccd83f92b88f7d863a5a21c532246c9969fae9c97b5b37  ProductStateQueries.swift
028b5660c5e0ccdd8c73e9442a510fdc25cd6dbdd141d6e16c6e7ff1c038e07f  LocationManager.swift
```

The committed T-06 through T-17 focused tests remain byte-exact:

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
```

Committed T-14 production inputs remain exact:

```text
3c0a99d12c3cde8e7c1445eba5d27e604c88846e9b90e60bbd13faab42a0acb5  BuyingOptionsService.swift
cea54550e54868f7e3c1f5e38d927ab164eef74dc0f1bdcc6cfb03325425b554  DecisionEngine.swift
53ecdc967798d074023a217ec2a6ced38eb4eb1afa5e9666575a839bea43ed18  DiscoverViewModel.swift
5443e39e39f1fa9520ac6ec2db497d8a3cd228e79d003f609449fa8cd55426a1  ShoppingContext.swift
e3a29037fb3a0fd3fc2501ea62f0408bc02a47b3caf1d4c2804af3a004541fbf  ShoppingIntentMatcher.swift
7c94d7e281fd964e9b64bfedb4d98b93dde47a17e765662369d25933d0b07b40  ShoppingTripService.swift
05f5f763a9f64ca5456a9029e233ef4feb577f05d4d120c364e43c6734d9762f  StoreRankingService.swift
950588da093578bcd12de04fff169736636ea9f2b5befb789e275dcdedfd3726  StoreSearchService.swift
```

Committed T-15 through T-17 production inputs remain exact:

```text
5de1559f69c7a9817309edd4dca18f26772cbd40967caa18f89118945b5c25b9  CameraViewModel.swift
68ef1d8c173fcc1c69501e34540003d66b916c5fbe7f00cb000cce1cc321a606  ProductKnowledgeService.swift
a0b7979e02ed0fcd66f760cb116eaf9c7bdf5d0c91365f030c596dbabf10dbac  AddProductSaveCoordinator.swift
c9864144ad8d1df38dc93e7a08226d2461c111d4ccfaa14adb96d30cb40da2d4  AddProductAutocompleteViewModel.swift
947e5331f4cc0c09412660b7df515f8b5e5da3eb15909ca2fdf5106c44e4ad54  ProductListView.swift
18b820a22f25586f96d75dc4e2e382c1f373b2e78262495bc1ee583db1f6b922  HomeView.swift
3cb8f26fb501854a51d61c9fca9872d2e3ac2fa9977e771ab3b3db30b9509be0  ContentView.swift
126e2375780164784f5abbb694018465826ca8562659883bb9d9a6ca42629f16  AppStateManager.swift
4677ffffe286d17de19361c866d1255a7369937f03dbd0f6e062ce13ba47b7db  ShoppingWorkspaceView.swift
```

Initial authorized T-18 hashes were:

```text
e094c8eb938bcdfad34bad0e18ca698dca6c43f913991dd9c01d260c5339f9a3  MapViewModel.swift
3c6657ce2d07f5d8522cd0a4f0a5cf546e9d30c4654233b81500a06e189b2438  WayTask/MainMapView.swift
4092933bcf17620e86bc0d5c447d4621efb65545be597f0e358d7e48b22489f5  WayTask/LocationDetailView.swift
028b5660c5e0ccdd8c73e9442a510fdc25cd6dbdd141d6e16c6e7ff1c038e07f  WayTask/LocationManager.swift
```

Final implementation/test hashes before evidence creation were:

```text
1c98a9151c3c4516239cafab7fa58d9fcf57efbb9f361216d0d9d4b340a3762e  MapViewModel.swift
84ad3ea92cbfcf39b3f7b245b73a5f9e792a9c96129cdfe76cb34cc26599b9bf  WayTask/MainMapView.swift
78673e72e74e288311aea849aeda588ad72dd9b23b74b92cd007bb586b9bd2a2  WayTask/LocationDetailView.swift
9a49c78fee2f36016e72b7942260645772496e28cfd4acc76af8fba8425d0da3  ProductStateMapConsumerConversionTests.swift
```

## Scope and inactivity proof

Final pre-evidence audits prove:

- `HEAD`, `main`, and `origin/main` remain identical at
  `591c25889b0c75cb3e7f6494c681c1cff5f0a099`;
- the only production diffs are the three exact TC-25 presentation files;
- the only test addition is the focused synchronized-group Map suite;
- `git diff --check` passes;
- production hunks are additive target sections plus one inactivity comment
  after the unchanged legacy location view;
- no production path invokes any of the three target consumer `make` methods;
- `LocationManager` and `GeofenceNotificationService` contain no target Map
  consumer reference;
- Product State, Session, persistence, startup, Product/Home, Shopping,
  Location/Notification, package, schema, migration, and project boundaries
  have no diff;
- no startup, migration, schema, V4, dependency, package, asset, localization,
  or project path is modified; and
- no T-19-or-later implementation exists in the diff.

This proves T-18 is compiled and qualified but cannot change runtime authority
or activate Map, Session, geofence, Notification, or navigation behavior before
the separately authorized cutover.

## Cleanup and rollback

After totals, builds, versions, and hashes were extracted, all 24 explicitly
enumerated T-18 development, focused, affected, Phase 1, full, Debug, and
Release DerivedData/result roots were removed from `/private/tmp`. The exact
post-cleanup search returned no `WT033A-T18-*` path. These task-owned Xcode
caches are not recoverable; no repository source, fixture, store, sidecar,
attachment, migration source, or candidate store was removed.

No commit was created. Review rollback is source-only: remove the bounded
target sections from the three production files, remove the inactivity comment,
and delete the focused test and this evidence file. Because there is no
production caller or writer, rollback requires no Product State, List, Plan,
Session, Map, geofence, Notification, migration, schema, or data repair.

## Terminal decision

T-18 COMPLETE — READY FOR REVIEW
