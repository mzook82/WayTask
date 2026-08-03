# WT-033A T-15 — Acquisition Outcome and Confirmation Consumer Conversion

## Decision and scope

T-15 converts only the target Product acquisition and explicit confirmation
consumers authorized by WT-033A S-02. Manual, custom, Catalog, barcode, Camera,
and reviewed-AI evidence now enter one bounded consumer boundary backed only by
the committed T-10 `ProductStateProductCommandAuthority`. The converted path is
library-only and remains inactive behind the current V3 presentation until its
separately authorized presentation/cutover steps.

No Product/Home presentation, Shopping UI, Map, notification, Session,
startup, migration, schema, V4 activation, package, or project-file change is
part of this implementation. T-16 and every later roadmap step remain
unstarted.

## Pre-write authorization gates

All mandatory gates passed before the first source edit:

- the repository was clean;
- T-01 through T-14 were committed contiguously;
- `HEAD`, `main`, and `origin/main` were identical at
  `d0351ea0906f3a2f2da23675bebe5fafbd730c3c`;
- the exact S-02 roadmap was
  `docs/Specifications/WT-033A_ProductStateTechnicalImplementation.md`, SHA-256
  `49e3021bd0415d344e37ff8c8b09245f9a8a76ba673cb535cf11704d85e94361`;
- S-02 authorizes T-15 only: scanner, Camera, Catalog acquisition, and Product
  Knowledge integration through TC-19 through TC-21, with a library-only
  default, exact outcomes, explicit Restore, separate Add to List, no
  Catalog/Knowledge lifecycle write, and no unrelated Plan change;
- committed T-06 through T-14 protected sources and focused tests matched their
  evidence hashes and had no pre-existing diff.

The governing WT-030, WT-031A, approved WT-031B, WT-032A D-01 through D-37,
WT-032B Phase 1, WT-033A S-00/S-01/S-02, and committed T-00 through T-14 were
treated as binding. No stop condition was reached.

## Acquisition authority

`AddProductSaveCoordinator` now exposes a target-only confirmation boundary:

- `confirmTargetAcquisition(_:using:)` accepts an immutable confirmation and
  an injected committed T-10 authority;
- the consumer has no `ModelContext` parameter and does not open a transaction,
  stage a Product State model, save, retry, restore, or create list membership;
- exactly one valid confirmation produces exactly one T-10 `acquire` call;
- local invalid/unavailable evidence produces one bounded result without a
  command call;
- the full confirmation, reviewed evidence, provenance, requested Product UUID,
  resolved Catalog identity, and authority diagnostic remain in the result.

The committed T-10 Product authority, commands, transaction coordinator,
repositories, schema, and persistence graph are unchanged. The existing T-10
Catalog adapter is reused for Catalog acquisition; it remains the only route
from the converted Catalog consumer to Product State.

## Confirmation semantics

`ProductAcquisitionConfirmation` contains the caller-supplied exact
`ProductStateProductID`, exact command ID, effective time, complete reviewed
evidence, derived acquisition provenance, and an explicit confirmation bit.
The evidence is a closed enum:

| Evidence | Preserved provenance and identity |
|---|---|
| Manual | exact reviewed name and image evidence; manual provenance |
| Custom | complete `AddProductCustomSelection`, including its preselection query, and image evidence; custom provenance |
| Catalog | complete `AddProductCatalogSelection`, including canonical `ProductID` and display snapshots, plus image evidence; Catalog-ID provenance |
| Barcode | complete `ProductCandidate`, exact `BarcodeResult`, and fallback image evidence; barcode-type provenance |
| Camera reviewed | complete selected candidate and `RecognitionResult`, including input source and candidate set, plus fallback image evidence |
| AI reviewed | complete selected AI candidate and `RecognitionResult`, optional exact reviewed barcode observation, and fallback image evidence |

Validation rejects zero Product/command IDs, non-finite times or confidence,
unconfirmed attempts, empty required fields, barcode mismatches, candidates not
present in the reviewed recognition result, invalid recognition source/status,
candidate-source/input-source mismatches, and fabricated barcode/AI
combinations. Product identity is never derived from name, brand, category,
visible text, or other display content.

Equivalent confirmations against equivalent authority state produce equal
outcomes and equal durable Product snapshots. There is no fallback identity,
silent merge, silent retry, or display-text match.

## Acquisition routes

### Manual and custom Product acquisition

Manual and custom confirmations submit the exact requested Product UUID and
reviewed content to T-10 with manual source provenance. A test with an existing
Product using identical display text proves the new UUID is created rather than
inferring or merging identity from the text.

### Catalog Product acquisition

Catalog confirmation resolves only the canonical Catalog `ProductID`, retains
the complete reviewed selection, and uses the committed T-10 Catalog adapter.
The resulting Product preserves exact user Product UUID, Catalog ID, display
name/locale snapshot, category ID/display snapshot, icon snapshot, image, and
snapshot time. An exact existing Catalog identity returns that Product's real
UUID; multiple exact matches return ambiguity without mutation or merge.

Catalog Truth remains read-only. No Product Catalog source, redirect, loader,
validator, search, personalization, or Catalog content changed.

### Barcode acquisition

Barcode evidence requires the selected candidate's barcode to equal the exact
reviewed `BarcodeResult.value`. The candidate UUID is evidence only and is
never promoted to Product identity; the confirmation's exact Product UUID is
submitted to T-10. The result preserves the original candidate and barcode
observation, including type, confidence, source, timestamp, and image evidence.

### Camera and AI-reviewed acquisition

`CameraViewModel` constructs target confirmations only from its already
reviewed barcode or recognition state. `ProductKnowledgeService` adds pure,
context-free evidence constructors for reviewed barcode and AI candidates.
Camera/AI evidence must contain the exact candidate in a recognized result with
the matching input source; reviewed barcode evidence must also match exactly.

Product Knowledge supplies evidence only. The new evidence constructors receive
no `ModelContext` and cannot create, restore, remove, or otherwise mutate a
Product. Existing learned-knowledge persistence behavior is untouched and is
not called by the target acquisition route.

## Created, Already Active, and Restore Required

Every acquisition attempt returns exactly one `ProductAcquisitionOutcome`:

| Outcome | Deterministic meaning |
|---|---|
| `created` | T-10 durably created the exact Product UUID at the returned revision |
| `alreadyActive` | T-10 found one exact active identity and returned its authoritative Product UUID/revision without mutation |
| `restoreRequired` | T-10 found one exact removed Product and returned its authoritative UUID/revision without restoring it |
| `ambiguity` | exact identity resolution produced multiple matches; nothing was merged or written |
| `validationFailure` | local confirmation validation or T-10 validation/conflict rejected the attempt |
| `unavailable` | Catalog evidence or Product authority was unavailable, or an impossible authority result was bounded explicitly |

The `ProductAcquisitionResult` embeds the original confirmation, so reviewed
evidence and provenance survive every outcome, including failures. Authority
results—not display strings—own the authoritative UUID for Already Active and
Restore Required.

## Explicit Restore and separate Add to List

`restoreRequired` is terminal for the acquisition attempt and never triggers a
follow-up command. A second `ProductAcquisitionRestoreConfirmation` must carry
that exact acquisition result, the authoritative removed Product UUID/revision,
a new command ID, a new history-event ID, an effective time, and explicit user
confirmation. Only then does `confirmTargetRestore(_:using:)` invoke the
committed T-10 Restore command with the exact expected Product revision.

Restore preserves the Product UUID and the complete prior acquisition evidence,
reactivates no other Product, appends the required restore history through T-10,
and creates no Shopping List or List Entry. Unconfirmed restore returns a local
validation failure and leaves the tombstone unchanged. Add to List remains a
separate future user action and is never synthesized by acquisition or Restore.

## Deterministic consumer state

`ProductAcquisitionPresentationState` gives the Camera and autocomplete
consumers one explicit state machine: idle, awaiting acquisition confirmation,
acquisition result, awaiting Restore confirmation, or Restore result. Each state
retains the immutable confirmation/result it represents. Resetting the reviewed
Camera state or autocomplete selection resets only this target presentation
state; it performs no lifecycle command.

The production `CameraView` and `ProductListView` do not call these methods.
This converts the authorized consumers and their outcome state without
activating T-16 presentation or V4 startup.

## Focused evidence and replacement of current defects

`WayTaskTests/Scanner/ProductStateScannerIntegrationTests.swift` contains 23
T-15 tests covering:

- manual, custom, Catalog, barcode, Camera, and AI-reviewed acquisition;
- exact Product UUID, Catalog snapshots, provenance, and reviewed evidence;
- Created, Already Active, Restore Required, explicit Restore, ambiguity,
  validation failure, and unavailable outcomes;
- no name-based identity, implicit merge, implicit Restore, retry, list
  membership, or unrelated Plan mutation;
- deterministic repeated confirmations and exact failed-commit attempt count;
- Camera/autocomplete confirmation state and Product Knowledge evidence-only
  behavior;
- static absence of target save/transaction/repository/startup/presentation
  activation.

This intentionally replaces the implicit-restore target expectation named by
S-02 with explicit Restore confirmation evidence. No legacy characterization
test was weakened or deleted.

## Qualification

Development builds/tests were used only for defect discovery and are excluded
from this table. Behavior and expectations were then frozen. The ordered formal
qualification ran on an iPhone 17 Pro simulator with iOS 26.5:

A final semantic audit found and corrected a provenance-source coherence edge
case. The entire ordered qualification was restarted after that correction;
only the corrected-code results below are final, and the superseded results are
excluded.

| Gate | Passed/result | Failed | Skipped | Expected failures |
|---|---:|---:|---:|---:|
| Focused T-15 acquisition/confirmation, run 1, clean roots | 23 | 0 | 0 | 0 |
| Focused T-15 acquisition/confirmation, run 2, separate clean roots | 23 | 0 | 0 | 0 |
| Affected acquisition/Catalog/Knowledge/Product-authority regressions | 370 | 0 | 0 | 0 |
| Exact six-suite WT-032B Phase 1 gate | 49 | 0 | 0 | 0 |
| Complete unfiltered `WayTaskTests` | 618 | 0 | 0 | 0 |
| Generic iOS unsigned Debug build | Succeeded, exit 0 | — | — | — |
| Generic iOS unsigned Release build | Succeeded, exit 0 | — | — | — |

The affected bundle covered the T-15 suite; existing Add Product and Catalog
persistence/compatibility; Product Catalog; Product Knowledge; canonical
Catalog selection; Product command authority, command pipeline, invariants,
transactions, repositories, persistence graph, immutable history and query
projection; and the unrelated T-14 Plan consumer. The exact Phase 1 selectors
were `ProductStateCharacterizationSupportSelfTests`,
`ProductStateDomainCharacterizationTests`,
`ProductStatePersistenceCharacterizationTests`,
`ProductStateConsumerCharacterizationTests`,
`ProductStateDiagnosticsCharacterizationTests`, and
`ProductStatePerformanceBaselineTests`.

The complete run logged transient simulator-clone launch-denial diagnostics.
The same `xcodebuild` execution recovered without a command rerun, exited 0,
and its final result bundle reported all 618 collected tests passed with zero
failed, skipped, or expected failures.

Qualification used Xcode 26.6 (17F113), Apple Swift 6.3.3, macOS 26.6, and the
iOS 26.5 simulator. No T-15 compiler or test warning was introduced.

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
| `ContentView.swift` | `2d30601201a2eac39673128cdac0f19907a7fe3ef7fc3e93c826d2943a3f70fc` |
| T-12 Shopping Memory | `20660f1608a5ca4d499c09062fa31c9a0d5f6363ce8df08913d3364fafb5a3a6` |
| T-12 Catalog personalization | `656546d6a770ee5658d6aaf71f34ff450ff4215da6a068aae95981800a2cbb1d` |
| T-13 queries | `92e10ebd622314f026ccd83f92b88f7d863a5a21c532246c9969fae9c97b5b37` |
| unchanged `CameraView.swift` | `44fe74b386e993d550142f8901f92c9180a33302404fffa68cb6b13e43e8301e` |
| unchanged `ProductListView.swift` | `565b4d664d9c224c305f57b6e8cf454f4487246b244ecec5db39d8fa428a553d` |

The committed T-06 through T-14 focused tests remain exact:

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
```

Final T-15 implementation/test hashes before evidence creation:

```text
5de1559f69c7a9817309edd4dca18f26772cbd40967caa18f89118945b5c25b9  CameraViewModel.swift
68ef1d8c173fcc1c69501e34540003d66b916c5fbe7f00cb000cce1cc321a606  ProductKnowledgeService.swift
a0b7979e02ed0fcd66f760cb116eaf9c7bdf5d0c91365f030c596dbabf10dbac  WayTask/Persistence/AddProductSaveCoordinator.swift
c9864144ad8d1df38dc93e7a08226d2461c111d4ccfaa14adb96d30cb40da2d4  WayTask/ProductKnowledge/Presentation/AddProductAutocompleteViewModel.swift
d89dbdb928357ad48975f10b6971e56c65548d61be149db22c210ea28d121ea7  WayTaskTests/Scanner/ProductStateScannerIntegrationTests.swift
```

After qualification, `HEAD`, `main`, and `origin/main` remain identical at
`d0351ea0906f3a2f2da23675bebe5fafbd730c3c`. No commit was created.

## Inactivity and scope proof

The final source and repository audits prove:

- the only production diffs are `CameraViewModel.swift`,
  `ProductKnowledgeService.swift`,
  `WayTask/Persistence/AddProductSaveCoordinator.swift`, and
  `WayTask/ProductKnowledge/Presentation/AddProductAutocompleteViewModel.swift`;
- the only test addition is the synchronized-group Scanner suite; the only
  documentation addition is this evidence file;
- the complete committed `WayTask/ProductState` command/query/domain/repository
  implementation has no diff, so T-10 remains the unchanged authority;
- the target consumer slice contains no direct `ModelContext`, save,
  transaction coordinator, repository staging, Shopping List service, Session,
  or retry;
- the production UI surfaces `CameraView.swift` and `ProductListView.swift`
  contain no target confirmation call; startup contains no target authority;
- project, package, schema, migration, startup, Catalog Truth, Shopping Memory,
  Product History, Session, App startup, and Content root hashes are unchanged;
- acquisition leaves an unrelated T-14 Plan byte-equivalent and creates no
  List or Entry;
- no Shopping UI, Map, Notifications, Sessions, Product/Home presentation,
  localization, asset, telemetry, Sentry, dependency, network, or V4 activation
  change exists;
- `project.pbxproj` has no diff; the synchronized group discovers the new test
  automatically;
- `git diff --check` passes.

This proves T-16 Product/Home presentation and every later roadmap conversion
remain inactive.

## Cleanup and review rollback

After result totals and protected hashes were extracted, all enumerated T-15
preflight, focused, affected, Phase 1, full-suite, Debug, and Release result or
DerivedData artifacts were removed from `/private/tmp`. The exact task artifact
search returned no T-15 path. No application-default, migration-source, or
candidate store was opened by qualification.

Review rollback is source-only: restore the four modified production files to
`HEAD`, then delete the focused Scanner test and this evidence document. Because
the converted target methods are not called by current production UI or startup,
rollback changes no V3 data and requires no schema, migration, Product State,
Catalog, Product Knowledge, Session, Shopping, Map, or notification repair.

## Terminal decision

T-15 COMPLETE — READY FOR REVIEW
