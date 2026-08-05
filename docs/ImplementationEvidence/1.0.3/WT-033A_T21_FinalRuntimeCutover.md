# WT-033A T-21 Final Runtime Cutover — Implementation Evidence

Date: 2026-08-05

Execution scope: WT-033A S-02 T-21 only

Release posture: final Product State authority cutover, qualified, not committed

## Pre-write verification

Every required stop-condition check passed before the first write:

- the repository was clean on `main`;
- `HEAD`, `main`, and `origin/main` were identical at
  `ea40ec82df0ccdfeeb5d27ae86394773d91192a2`;
- T-00 was committed at `6a3e85d` and T-01 through T-20 were committed
  contiguously from `d81df92` through `ea40ec8`;
- the committed consumer/infrastructure sequence was T-13 `b2be2ac`, T-14
  `d0351ea`, T-15 `feaf8d1`, T-16 `ef9fe59`, T-17 `591c258`, T-18
  `ee19bcf`, T-19 `1a8cb85`, and T-20 `ea40ec8`;
- S-00, S-01, and S-02 SHA-256 values were respectively
  `16e336f54a4cb644465f1836e9d97410bffc1044de4322581398ab3f8517b920`,
  `2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c`,
  and
  `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361`;
- all committed T-06 through T-20 evidence, focused tests, and protected
  production inputs matched the hashes recorded by their implementation
  evidence; and
- project, package resolution, schema, migration, startup, repository,
  Product/history, List, Session, Shopping, Map, notification, geofence,
  assets, and localization inputs had no unexpected drift.

No mismatch or stop condition existed before writing.

## Exact S-02 authority

S-02 assigns T-21 exactly:

> Enforce zero legacy authority, run full qualification, and perform the
> single release cutover.
>
> TC-08 removal from runtime access; all changed production/tests/evidence;
> no physical storage deletion.
>
> Legacy reader/writer counters zero; all target suites and regressions pass;
> Debug/Release builds; migration/recovery/rollback/privacy/a11y/localization/
> performance gates pass; one coherent authority enabled.

This implementation activates only the target authority already established
by T-13 through T-20. It adds no schema version, package, project-file,
localization, asset, Catalog, Product Knowledge, or unrelated product change.

## Runtime activation

`WayTaskApp` now has one release root:

1. `ProductStateRuntimeLaunchState` invokes the T-21 bootstrap before writable
   presentation is exposed.
2. A successful launch supplies one V4 `ModelContainer` to one
   `ProductStateRuntime`.
3. That runtime composes the committed repositories, one transaction
   coordinator, Product command authority, named-List/entry command authority,
   query boundary, normalized Shopping Session authority/service, Product/Home
   consumer, Shopping consumer, Map consumer, notification planner, and
   geofence monitoring coordinator.
4. Product, List, and Session command authorities use `.writableTarget` and
   share the same transaction-bound repository graph.
5. Presentation renders projections and submits commands. It owns no
   `ModelContext`, `@Query`, direct save, legacy lifecycle flag, or fallback
   identity.

The released target root exposes Home, Products, Shopping, and Map. It keeps
the previously approved onboarding boundary. No partially converted legacy
root or hidden runtime substitution remains.

## Store cutover and migration

The cutover uses three separately owned locations: candidate, staging, and
stable runtime. Their boundaries are deterministic and fail closed.

- A new install creates and validates an empty V4 Product State store, writes
  the owned cutover record, and atomically promotes the staging directory.
- An existing V3 install runs the committed T-06/T-07/T-08 protected
  candidate-store and semantic migration sequence. Only a complete validated
  V4 candidate is copied to owned staging and atomically promoted.
- Candidate cleanup must succeed and prove the protected source was not
  accessed by cleanup before promotion is allowed.
- The shipped V3 source and sidecars remain byte-preserved. T-21 does not
  delete legacy or compatibility storage.
- Relaunch opens only the owned stable V4 store with the exact owner marker and
  cutover record. It never reopens V3 and never creates an empty or in-memory
  substitute for an invalid promoted target.
- Missing records, wrong authority/schema, nonzero compatibility counters,
  incomplete runtime directories, foreign staging, failed migration, failed
  cleanup, failed promotion, and invariant failure all block the application.

The durable cutover record names Product State as authority, schema V4,
source kind, source and semantic fingerprints where applicable, exact migrated
counts, and zero legacy-authority reads/writes.

## Removed legacy runtime access

Only runtime access replaced by the approved target authority was removed:

- `WayTaskApp` no longer creates the legacy startup persistence owner,
  `AppStateManager`, `LocationManager`, legacy `ModelContext` root, or
  `ContentView` runtime route;
- no production caller constructs `ProductStateCompatibilityAdapter`;
- no reverse synchronization, legacy reader, legacy writer, root backfill,
  default/first/recent List selection, or legacy lifecycle substitution is
  reachable from the release root; and
- the committed static caller assertions now require exactly the one T-21
  migration caller and exactly the one T-21 transaction-coordinator caller.

TC-08 source and physical compatibility values remain present for retained
storage/recovery evidence. They are not constructed or consulted by the
runtime. Both durable and in-memory compatibility legacy-read and legacy-write
counters are fixed at zero.

## Preserved authority and identity

The promoted store is validated before presentation and again on every stable
relaunch. Validation rejects duplicates, missing owners, invalid revisions,
invalid lifecycle values, and broken relationships while preserving:

- Product UUID, lifecycle/tombstone state, revision, Catalog provenance, and
  Product history ownership;
- List UUID, purpose, durable revision, deterministic ordering, and exact
  membership scope;
- entry UUID plus exact List/Product UUID relationship, Needed/Resolved state,
  reason, quantity, unit, note, and sort order;
- Session UUID, revision, lifecycle, immutable snapshot UUID/version/content
  signature, exact source List/revision provenance, stops, lines, execution
  state, and outcome evidence;
- history-event UUID, Product/List/entry/Session ownership, causal ordering,
  and immutable meaning;
- notification, trigger, registration, Session, stop, line, entry, Product,
  store, and geofence identities already established by T-20; and
- deterministic created-at/UUID ordering for all-List reads and projections.

Named-List selection is exact. No default, first, recent, display-name,
barcode, global, or repaired identity can select a List. Missing or ambiguous
identity remains explicit.

## Consumers, Session, notifications, and geofences

- Product/Home reads only the Product Library, Removed Products, and named-List
  projections and sends Product/List commands through the target authorities.
- Shopping consumes the exact selected named-List projection and exposes only
  command-backed quantity, resolve, reopen, and remove operations.
- Map derives context, discovery, and store recommendation projections from
  the exact same List revision. An explicit empty-evidence publication version
  represents the absence of current store evidence without inventing a store
  identity.
- The Shopping Session service and command authority are live against the same
  repositories and transaction coordinator. Active Session lookup and exact
  snapshot retrieval feed reminder planning without legacy Session access.
- Notification planning and geofence reconciliation are live value
  authorities. With the current explicit disabled reminder intent and
  unavailable platform capabilities they deterministically produce zero
  registrations; they do not silently schedule, infer permission, or mutate
  Product/List/Session lifecycle.

## T-21 focused coverage

Eight cutover tests cover the exact release boundary:

1. new-install V4 activation and target writes surviving relaunch;
2. exact List selection across Shopping and Map with no fallback;
3. Product/List/entry identity and lifecycle preservation;
4. real protected V3 migration with unchanged source fingerprint and exact
   migrated identities;
5. real Shopping Session start plus exact notification/geofence planning;
6. incomplete and foreign staging state failing closed;
7. corrupted promoted target failing closed without legacy or empty
   substitution; and
8. static zero-legacy runtime access with compatibility storage retained.

An early development/defect-discovery run exposed two committed isolation
assertions that still required zero production callers. T-21 intentionally
replaced only those assertions with exact-one cutover caller checks. That run
was invalidated and is not counted below. Production and tests were then
frozen, and the complete formal sequence restarted from the first focused gate.

## Formal qualification

The required gates completed in the authorized order on separate clean roots,
with parallel testing disabled and one worker:

| Gate | Passed | Failed | Skipped | Expected failures | Result |
|---|---:|---:|---:|---:|---|
| Focused T-21 run 1 | 8 | 0 | 0 | 0 | Passed |
| Focused T-21 run 2 | 8 | 0 | 0 | 0 | Passed |
| Affected regressions | 451 | 0 | 0 | 0 | Passed |
| Exact WT-032B Phase 1 | 49 | 0 | 0 | 0 | Passed |
| Complete unfiltered `WayTaskTests` | 767 | 0 | 0 | 0 | Passed |

The affected gate used 26 target, migration, startup, repository, transaction,
command, query, consumer, Session, notification/geofence, cutover,
characterization, diagnostics/privacy, Sentry, and resilience selectors. The
unfiltered run includes every affected and focused test plus every remaining
repository test.

The exact Phase 1 gate retained all five Product State suites and the support
self-tests. Its controlled reference profile reported 285.321 seconds for the
semantic digest and 843.883 seconds for startup repair; the complete gate took
1,175.872 seconds. The complete unfiltered target took 1,225.869 seconds.
These remain deterministic functional results; expected negative-store and
temporary SQLite cleanup diagnostics did not produce failures.

Qualification used the task-owned `WT033A-T21-Qualification` iPhone 17 Pro
simulator, iOS 26.5 (`23F77`), arm64, with Xcode 26.6 (`17F113`), Apple Swift
6.3.3 (`swiftlang-6.3.3.1.3`), and macOS 26.6 (`25G72`).

No T-21 warning was introduced. Xcode reported only the pre-existing unused
`legacyByID` test warning and Sentry script-phase dependency-analysis note.

## Builds

Both required builds used `CODE_SIGNING_ALLOWED=NO` and independent clean
DerivedData roots:

| Configuration | Destination | Result |
|---|---|---|
| Debug | `generic/platform=iOS` | `BUILD SUCCEEDED` (exit 0) |
| Release | `generic/platform=iOS` | `BUILD SUCCEEDED` (exit 0) |

## Protected hash audit

The protected authority, project, package, schema, startup, and retained
cross-step inputs remain byte-exact after qualification and builds:

```text
16e336f54a4cb644465f1836e9d97410bffc1044de4322581398ab3f8517b920  S-00 authority discovery
2c08cb149d47b94f4e8edeb0bdfc11ced3feabdb69b81b4b527ae187b8a9654c  S-01 authority specification
49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361  S-02 technical roadmap
9b726ac5ef5fa01baf9a5d4789231f377dbc3221599356bd8ac6ec2b3ee2054f  project.pbxproj
42ea4be1f9d443ba125cb6f995d4ae0c2b49059ea5c65dfcd34382fb5f29e244  Package.resolved
90841edae9796af551c453f6a3bcb65737db975a61a05505ccdb3bcef0e8f9b8  WayTaskSchema.swift
f1729caf5c33cc7de19b0cd751ae0fdb6480190a4773ec8bf37e589fcd59b849  WayTaskStartupPersistence.swift
57dd2b13e4e68d2292e5b45f5fe090f3b64344fe4c777a91f19cc47961e8da8c  ProductHistory.swift
86c66430467c2b8b15a104c11cf0394709d4767a2e3ba7d1fbd2e711222eb8d5  ShoppingSession.swift
20660f1608a5ca4d499c09062fa31c9a0d5f6363ce8df08913d3364fafb5a3a6  ShoppingMemoryService.swift
656546d6a770ee5658d6aaf71f34ff450ff4215da6a068aae95981800a2cbb1d  ProductCatalogPersonalization.swift
```

Committed T-07 through T-20 focused artifacts remain byte-exact:

```text
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
0232b3106712999415c686432e63d8041b6819d2afb400f0e4c602b70b0faa9d  T-20
```

Committed T-19/T-20 production authorities outside the exact T-21 seams also
remain byte-exact:

```text
945f0ca6b49a9e23d8f8c01fd12054f6668d9989287aa59abb8385f7f2bed74d  ShoppingSessionService.swift
2be900813206efee8040a346d26de0daa714bc2fe3c51067ff346d102c73913a  ProductStateCommands.swift
8b68aacf49d0b37952a4120e3b0e23f7794dba6a26db89601b3ae8d9e526ec30  ProductStateTransactionCoordinator.swift
ac286876a6a54df8b75d3293260bc201e239e38d6bd0d874b1c779c81d43ffc5  ProductStateShoppingSessionAuthority.swift
b4995757488b7c79840f9fb4fbf0fb174fd0e520004899e26f0ab6b5c07be7f8  ProductStatePostCommitReconciler.swift
7bea5f3c443209b2fa9066502809ee6091829f5c2a7e85e0726b1936f5c1ede8  GeofenceNotificationService.swift
6536aab863f9eda3353a11b9a821cfee8ccc15caae29da485d831684a397ea7d  LocationManager.swift
34efd1df9e1dcb195ebfd33552fd39087182365371c250d493c9f4f28cb46c43  AppStateManager.swift
```

The exact T-21-authorized seams began at these committed baselines:

```text
1c79711332281f4b24af81696c7242784596bcdaa8b92f35fb17b9ca757418e8  WayTaskProductStateMigration.swift
e549cd17859e9eac584a493e3b2654fb000d59cd2d6bf6d4a191bb11094d5262  ProductStateRepositories.swift
f35afed463f2f5cbdfe53e63020475683e1e097bd5020fafe62833003392698e  ProductStateQueries.swift
5a460b45f2922c096ee1a81ddd7da27fe13df49c50d632d1b5c91d568bb04251  WayTaskApp.swift
702f6e7690b954a2dc93862d3f7c53254d4fb5ab1cebde5b488f78740e1d139a  T-06 migration foundation tests
```

Frozen final T-21 production/test hashes before evidence creation are:

```text
3036c8e0fb6bfa45b41a3fd05962cfbadaa44f031d8f5abc85500d66ca7f5872  WayTaskProductStateMigration.swift
f946bdd5e48bf580509f94877c41a9cdd4851aa00c3b6dc21888925f1afa3e57  ProductStateRepositories.swift
e6690f05283a9cb09bb1b6b1acb0f361f5604122348e8aeedcbdf10ae0576d34  ProductStateQueries.swift
fcbb59ec474524948a4c53ff351a90bdaf7423f57c8c552e9ebdfa03ddb26511  ProductStateRuntime.swift
c4fba342b0e5761d888c65f45b298cf0107e87f1f206bedf63de48fbc3233683  ProductStateRuntimeView.swift
e3b38424d8f564139568ec1bfa74ce30d8fa099b859e45a7da9f32565e9cca72  WayTaskApp.swift
99118dd2097a9e9fea975f0322ecabfe95ee2f6b91cb17039d5670a32893deeb  WayTaskProductStateMigrationFoundationTests.swift
1c1c6fcbb0515440ea7f6833e221decf8b1c3e21903e07c1a0e0ee7e50a98e29  ProductStateTransactionCoordinatorTests.swift
93464eb96cfd6b24a11f8bcdac3e794d7efb9a89cda27acbc070859460c96032  ProductStateFinalRuntimeCutoverTests.swift
```

## Scope audit

Final pre-evidence audits prove:

- `HEAD`, `main`, and `origin/main` remain identical at
  `ea40ec82df0ccdfeeb5d27ae86394773d91192a2`;
- `git diff --check` passes;
- the only tracked production diffs are the migration inspector visibility
  seam, all-List repository/query support, explicit empty Map-evidence
  provenance, and the application-root cutover;
- the only new production files are the 974-line runtime/bootstrap and the
  507-line target projection view;
- the only tracked test diffs replace two exact pre-cutover no-caller
  assertions; the only new test file is the 642-line T-21 suite;
- static scans find no compatibility-adapter construction, reverse sync,
  legacy root construction, direct persistence in the target presentation,
  legacy check/completion authority, fallback List selection, or additional
  production migration/transaction owner;
- synchronized Xcode groups discover the new files without a project edit;
- `project.pbxproj`, package resolution, dependency versions, schema,
  localization, and assets have no diff;
- all frozen production/test hashes remain exact after formal qualification,
  both builds, audits, and cleanup; and
- no commit was created.

## Privacy, accessibility, localization, and rollback audit

- Cutover records and failure messages contain bounded structural status,
  counts, versions, and fingerprints only; they contain no Product/List names,
  notes, coordinates, barcodes, or other record content.
- The full diagnostics/privacy and Sentry regressions pass. The cutover adds no
  network path and no Sentry metadata field.
- Target presentation uses semantic SwiftUI controls, system labels, scalable
  project typography, scrollable content, non-color lifecycle text, and an
  identified combined blocked state. It adds no fixed text-size layout,
  custom animation, or motion dependency.
- No localization resource exists in the project and none was created or
  modified. SwiftUI literal keys preserve the current localization posture;
  no locale, RTL, or language-specific behavior participates in identity or
  authority.
- Before promotion, rollback deletes only owned candidate/staging artifacts and
  leaves the protected source intact. After promotion but before target writes,
  recovery requires the separately approved protected-backup route. After any
  target write, a legacy-authority binary must never reopen the store; rollback
  is a forward-compatible disabled/fix build only.

## Cleanup

After totals, diagnostics, versions, and hashes were extracted, 20 explicitly
enumerated T-21 development, invalidated-run, formal focused, affected, Phase
1, full, Debug, Release, DerivedData, and `.xcresult` paths were removed from
`/private/tmp`. The post-cleanup search returned no `WT033A-T21*` path.

The dedicated simulator `635B5D99-96DF-4ABD-8D12-B0315E808756`
(`WT033A-T21-Qualification`) was shut down and deleted. The post-cleanup device
search returned no T-21 simulator. These task-owned caches, result bundles, and
simulator are not recoverable; no repository file, protected source store,
sidecar, fixture, attachment, user simulator, or user data was removed.

## Terminal decision

WT-033A COMPLETE
