# WT-033A T-20 Notifications & Geofences — Implementation Evidence

Date: 2026-08-04

Execution scope: WT-033A S-02 T-20 only

Release posture: compiled and qualified, internally inactive, not committed

## Pre-write verification

All required stop-condition checks passed before the first write:

- the repository was clean on `main`;
- `HEAD`, `main`, and `origin/main` were identical at
  `1a8cb854d29b61acaa84c8d7f23d103980cee9a9`;
- T-01 through T-19 were committed contiguously from `d81df92` through
  `1a8cb85`;
- the final committed sequence was T-13 `b2be2ac`, T-14 `d0351ea`, T-15
  `feaf8d1`, T-16 `ef9fe59`, T-17 `591c258`, T-18 `ee19bcf`, and T-19
  `1a8cb85`;
- S-00, S-01, and S-02 SHA-256 values were respectively
  `16e336f54a4cb644465f1836e9d97410bffc1044de4322581398ab3f8517b920`,
  `2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c`,
  and
  `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361`;
- committed T-06 through T-19 focused tests and protected production inputs
  matched their recorded evidence hashes; and
- project, package, schema, migration, startup, repository, Product/history,
  Session, Shopping, Map, Location, Notification, and geofence inputs matched
  their committed baselines.

No pre-write mismatch or stop condition existed.

## Exact S-02 authority and footprint

S-02 assigns T-20:

> Convert notification/geofence payload validation and post-commit
> reconciliation.
>
> New TC-18; TC-26; `WayTask/AppStateManager.swift`; notification tests.
>
> Owner/revision payload; pre-delivery/tap validation; exact route; stale
> suppression/safe fallback; idempotent disarm/register; no lifecycle
> mutation.
>
> Disable scheduling/actions; keep committed Product State; retry ledger
> safely.
>
> D-11–D-12, D-21, D-23, D-33, D-36.

TC-18 is the new post-commit infrastructure reconciler. TC-26 covers the
Location/Notification infrastructure boundary. TC-22 assigns notification
route validation through the committed query boundary. WT-031B additionally
binds per-Session opt-in, at most 12 Active-Session regions, current-stop-first
ordering, up to 11 future stops with Remaining lines, two-hour successful
cooldown per Session/stop across revisions, no app-defined quiet hours,
versioned opaque platform identifiers, pre-delivery/tap revalidation, and zero
passive nearby-shopping regions.

The final pre-evidence footprint is exactly:

- `WayTask/ProductState/Infrastructure/ProductStatePostCommitReconciler.swift`
  — new value-only notification planning, lifecycle, validation,
  reconciliation, recovery, and scheduling-result authority;
- `GeofenceNotificationService.swift` — additive inert platform projection and
  compact opaque-token adapter after the unchanged legacy body;
- `WayTask/LocationManager.swift` — additive value-only desired/ledger/actual
  monitoring coordinator after the unchanged legacy body;
- `WayTask/AppStateManager.swift` — additive inert exact notification route
  intent after the unchanged legacy body;
- `WayTaskTests/Notifications/ProductStateNotificationIntegrationTests.swift`
  — 25 focused fake/value-only tests; and
- this implementation-evidence document.

No project-file edit was required because the synchronized source and test
groups discovered both new files automatically.

## Notification authority

`ProductStateNotificationPlanner` accepts only committed immutable inputs:

- exact T-19 Session snapshot, revision, snapshot ID, source List/revision,
  source Plan ID/signature, stops, lines, entries, Products, and stores;
- exact T-13 notification-opportunity and notification-route projections;
- explicit per-Session reminder intent and current stop;
- an explicit bounded region policy and capability projection; and
- either the full committed command receipt with its exact Session revision
  effect or an exact durable recovery identity.

Planning rejects stale Session/opportunity metadata, foreign owners, mismatched
intent, missing List/Plan authority, invalid Plan signature, absent committed
revision effect, non-durable or foreign recovery, noncanonical/duplicate stop
or line identity, unresolved lines, invalid line state, foreign List ownership,
mismatched opportunity items, missing store identity, and invalid coordinates.
No display name, selected UI state, legacy completion value, global value, or
first/recent/default object participates in identity resolution.

Equivalent immutable inputs produce equivalent projections and deterministic
SHA-256-derived UUIDs. Current stop is considered first; completed future stops
are retained as explicit omissions and skipped when filling the approved
future-region budget. Remaining future stops preserve frozen Plan order.
Before-current, no-Remaining-line, and outside-budget omissions are named and
ordered rather than silently discarded.

Activation eligibility is explicit. Disabled intent, non-Active lifecycle,
notification/location authorization, precise-location availability, region
monitoring, background refresh, and durable authority each produce a bounded
outcome. Terminal, unavailable, opt-out, and no-Remaining-line inputs produce
zero desired registrations and never mutate Session or Product State.

## Geofence authority and monitoring coordination

Each immutable desired registration preserves:

- registration, geofence, notification, and trigger UUIDs;
- Session UUID, revision, and snapshot UUID;
- List UUID and durable revision;
- Plan UUID;
- stop UUID and exact store reference identity;
- exact ordered line, entry, and Product UUIDs;
- coordinate/radius snapshot, remaining count, and deterministic ordinal; and
- the full committed command receipt or exact recovery UUID.

The radius policy is bounded to the approved 150–250 metre range. Total desired
regions are bounded to 12, passive reminders receive no projection, and the
successful cooldown is exactly two hours. Cooldown authority is separately
keyed by exact Session UUID and stop UUID, so a revision replacement cannot
bypass it.

`ProductStatePostCommitReconciler` compares three immutable inputs:

1. desired revisioned registrations;
2. the exact registration/delivery ledger; and
3. enumerated actual managed geofence, pending-notification, and
   delivered-notification identities.

It deterministically emits inert actions to register missing desired values,
disarm actual values absent from desired state, cancel obsolete pending
notifications, remove obsolete delivered notifications, mark removed
projections, invalidate obsolete navigation owners, record actual or missing
registrations, and retry unknown registration outcomes. Registered-but-missing
values are marked and safely re-registered. Registering/removing unknown
outcomes are retried. Duplicate ledger identities produce named conflict
evidence and cannot crash or silently select one entry.

The coordinator decodes only `wt-r1-g-<opaque UUID>` and
`wt-r1-n-<opaque UUID>` tokens. Legacy, malformed, wrong-kind, and unknown
identifiers remain explicit invalid inputs. The tokens contain no Session,
List, Product, Store, name, coordinate, distance, quantity, or revision
content; exact authority is resolved from the ledger and current projections.

## Lifecycle, event validation, and recovery

The bounded registration lifecycle is `desired`, `registering`, `registered`,
`failed`, `removing`, `removed`, or `suppressed`. Delivery is `idle`,
`scheduling`, `scheduled`, `failed`, or `unknown`. Attempt, event, and result
identities remain explicit; no state transition occurs inside a projection.

Before a delivery intent is returned, the trigger evaluator requires an exact
geofence UUID, trigger UUID, registration payload, registered ledger entry,
current payload owner, and exact current Session route. Stale routes return a
named stale outcome, unavailable authority is suppressed, foreign or malformed
events are invalid, and in-flight/succeeded duplicate events are idempotent.
There is no app-defined quiet suppression or delayed quiet queue.

The immutable delivery projection carries exact notification, trigger, event,
Session, stop, store, line, entry, and Product identities plus a semantic
remaining-count value. It contains no Product name or distance. Scheduling
results become exact ledger intents: only successful scheduling records the
Session/stop cooldown timestamp; failure remains retryable; an unknown result
retains its attempt UUID for reconciliation.

The recovery input requires exact recovery UUID, Session UUID, Session
revision, and snapshot UUID plus durable-authority evidence. Recreated,
in-memory, or otherwise non-durable authority fails closed and produces no
desired registrations.

## Immutable projections and route semantics

`ProductStateGeofenceNotificationProjectionAdapter` converts target values to
inert platform descriptions only. Its notification userInfo contains exactly a
version and opaque notification token. Its geofence projection contains the
opaque identifier and validated geometry but owns no `CLLocationManager` or
`UNUserNotificationCenter`.

`ProductStateNotificationNavigationIntentProjector` revalidates an opaque
notification token against the desired registration and the committed T-13
route projection. A valid tap produces only an inert exact Shopping Session and
current-stop intent. Stale/terminal authority produces the committed safe
Shopping status intent; unavailable authority is suppressed; malformed,
foreign, named-list, or mismatched Session routes are invalid. No selected tab,
Map state, Session state, List state, or Product State value changes, and Map is
never opened automatically.

All T-20 public values are immutable structs/enums. The new infrastructure file
imports `CryptoKit` and `Foundation` only. It has no SwiftData, Core Location,
User Notifications, MapKit, network, repository, transaction, `ModelContext`,
or direct-save dependency.

## Runtime inactivity proof

Static, diff, focused-test, and full-suite audits prove:

- no production caller constructs the planner, platform adapter, monitoring
  coordinator, trigger evaluator, or navigation-intent projector;
- the only production construction is the monitoring coordinator's private
  value-only reconciler, while the coordinator itself has no production caller;
- no T-20 addition calls `startMonitoring`, creates a region, prompts for
  permission, schedules with `UNUserNotificationCenter`, dispatches a
  notification, registers background runtime, opens navigation, or changes an
  application route;
- no T-20 addition creates `ModelContext`, calls `save()`, opens a transaction,
  bypasses a repository/coordinator, or mutates Product, List, Plan, Session,
  Shopping, Map, notification, or geofence persistence;
- the existing active legacy runtime bodies were not edited; all changes to
  their three host files are additions after explicit inactive T-20 markers;
- legacy payload parsing remains available for cleanup characterization, but it
  is not target authority;
- `WayTaskApp.swift`, startup, migration, schema declarations,
  `project.pbxproj`, package resolution, dependencies, assets, and localization
  have no diff; and
- no T-21 cutover, runtime connection, geofence registration, notification
  scheduling, background activation, V4 activation, or production dispatch is
  present.

T-21 therefore remains the sole step authorized to connect these inert values
to platform calls and the production runtime.

## Formal qualification

Production behavior and test expectations were frozen before the formal
sequence. No production or test file changed after freeze. The required gates
completed in order:

| Gate | Passed | Failed | Skipped | Expected failures | Result |
|---|---:|---:|---:|---:|---|
| Focused T-20 run 1, clean root | 25 | 0 | 0 | 0 | Passed |
| Focused T-20 run 2, separate clean root | 25 | 0 | 0 | 0 | Passed |
| Affected regressions | 174 | 0 | 0 | 0 | Passed |
| Exact WT-032B Phase 1 gate | 49 | 0 | 0 | 0 | Passed |
| Complete unfiltered `WayTaskTests` | 759 | 0 | 0 | 0 | Passed |

The affected gate comprised
`ProductStateConsumerCharacterizationTests`,
`ProductStateDiagnosticsCharacterizationTests`, `SentryStabilityTests`,
`ProductStateQueryProjectionBoundaryTests`,
`ProductStateShoppingSessionAuthorityTests`,
`ProductStateMapConsumerConversionTests`,
`ProductStateProductHomeConsumerConversionTests`,
`ProductStateShoppingPlanConsumerConversionTests`, and
`ProductStateShoppingConsumerConversionTests`. This covers the S-02-required
legacy payload, diagnostics/consumer, Sentry, Location/Map, query, Session,
Product/Home, Plan, and Shopping regressions.

The exact Phase 1 gate comprised
`ProductStateCharacterizationSupportSelfTests`,
`ProductStateDomainCharacterizationTests`,
`ProductStatePersistenceCharacterizationTests`,
`ProductStateConsumerCharacterizationTests`,
`ProductStateDiagnosticsCharacterizationTests`, and
`ProductStatePerformanceBaselineTests`. Its 2,000-Product reference profile
reported a 274.932-second semantic-digest case and an 853.478-second
startup-repair case. Expected negative-store and temporary SQLite cleanup logs
did not produce a failure.

The authoritative full pass ran all 759 tests on a fresh task-owned iPhone 17
Pro iOS 26.5 simulator (`23F77`) with parallel testing disabled and one worker.
Its reference profile reported 267.933 seconds for semantic digest and 832.346
seconds for startup repair. All 25 T-20 tests passed inside that unfiltered
invocation.

Qualification used Xcode 26.6 (`17F113`), Apple Swift 6.3.3
(`swiftlang-6.3.3.1.3`), and macOS 26.6 (`25G72`).

## Builds

Both required builds used `CODE_SIGNING_ALLOWED=NO` and separate clean roots:

| Configuration | Destination | Result |
|---|---|---|
| Debug | `generic/platform=iOS` | `BUILD SUCCEEDED` (exit 0) |
| Release | `generic/platform=iOS` | `BUILD SUCCEEDED` (exit 0) |

No T-20 compiler error or warning was introduced. Xcode repeated the existing
Sentry build-phase/dependency-analysis notes only.

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
```

Committed T-06 through T-19 focused tests remain byte-exact:

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
7e2e5700e03a59154cfa7fb44148526dd6cbd260dc751525e3c1a96cbd311943  T-19
```

Committed T-19 production authority remains exact:

```text
945f0ca6b49a9e23d8f8c01fd12054f6668d9989287aa59abb8385f7f2bed74d  ShoppingSessionService.swift
2be900813206efee8040a346d26de0daa714bc2fe3c51067ff346d102c73913a  ProductStateCommands.swift
f35afed463f2f5cbdfe53e63020475683e1e097bd5020fafe62833003392698e  ProductStateQueries.swift
8b68aacf49d0b37952a4120e3b0e23f7794dba6a26db89601b3ae8d9e526ec30  ProductStateTransactionCoordinator.swift
ac286876a6a54df8b75d3293260bc201e239e38d6bd0d874b1c779c81d43ffc5  ProductStateShoppingSessionAuthority.swift
```

The three authorized tracked host files began at these committed baselines:

```text
bcbb1f076808897949ecdc9f445cea98f3f28dd51947c6437a58029869f76c4f  GeofenceNotificationService.swift
028b5660c5e0ccdd8c73e9442a510fdc25cd6dbdd141d6e16c6e7ff1c038e07f  LocationManager.swift
126e2375780164784f5abbb694018465826ca8562659883bb9d9a6ca42629f16  AppStateManager.swift
```

Frozen final T-20 production/test hashes before evidence creation are:

```text
b4995757488b7c79840f9fb4fbf0fb174fd0e520004899e26f0ab6b5c07be7f8  ProductStatePostCommitReconciler.swift
7bea5f3c443209b2fa9066502809ee6091829f5c2a7e85e0726b1936f5c1ede8  GeofenceNotificationService.swift
6536aab863f9eda3353a11b9a821cfee8ccc15caae29da485d831684a397ea7d  LocationManager.swift
34efd1df9e1dcb195ebfd33552fd39087182365371c250d493c9f4f28cb46c43  AppStateManager.swift
0232b3106712999415c686432e63d8041b6819d2afb400f0e4c602b70b0faa9d  ProductStateNotificationIntegrationTests.swift
```

## Scope and inactivity audit

Final pre-evidence audits prove:

- `HEAD`, `main`, and `origin/main` remain identical at
  `1a8cb854d29b61acaa84c8d7f23d103980cee9a9`;
- `git diff --check` passes;
- the only tracked production diffs are 101 additive lines in
  `GeofenceNotificationService.swift`, 83 additive lines in
  `WayTask/LocationManager.swift`, and 50 additive lines in
  `WayTask/AppStateManager.swift`;
- the only new production file is the 1,025-line TC-18 value boundary and the
  only new test file is the 1,233-line focused suite;
- all three legacy-host diffs contain additions only after inactive markers;
- exact construction scans find no target runtime caller;
- forbidden-call scans find no platform activation, persistence, transaction,
  navigation activation, network, MapKit, app-defined quiet queue, or Product
  State mutation in the additions;
- protected hashes and frozen production/test hashes are unchanged after all
  qualification and builds;
- no project, package, dependency, asset, localization, startup, migration,
  schema, default-container, V4, or T-21 path is modified; and
- no commit was created.

## Cleanup and rollback

After all result summaries, totals, versions, diagnostics, and hashes were
extracted, 15 explicitly enumerated T-20 development, focused, affected,
Phase 1, full, Debug, Release, DerivedData, and result-bundle roots were removed
from `/private/tmp`. The post-cleanup search returned no `WT033A-T20*` path.

The shutdown task-owned simulator
`41056811-0A44-4EA3-A90A-A56113EA0A52` (`WT033A-T20-Full`) was deleted. The
post-cleanup simulator search returned no T-20 device. These caches, result
bundles, and the test simulator are not recoverable; no repository source,
fixture, store, sidecar, attachment, migration input, or user simulator was
removed.

Review rollback is source-only: remove the new reconciler and focused test,
remove the three additive inactive host sections, and remove this evidence
file. Because no target runtime caller exists and T-21 was not started,
rollback requires no Product, List, Plan, Session, notification, geofence,
startup, migration, schema, or data repair. Committed Product State and T-19
Session authority remain intact.

## Terminal decision

T-20 COMPLETE — READY FOR REVIEW
