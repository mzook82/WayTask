# WT-030B - Shopping Session & Background Audit

**Product:** WayTask iOS

**Audit type:** Architecture, system behavior, battery, privacy, and UX

**Status:** Complete

**Audit date:** 2026-07-29

**Evidence baseline:** `main` at `35a0775`

**Implementation authorization:** None

**Terminal decision:** Approve the Session-Scoped Persistent Hybrid architecture in Section 19 as the official WayTask Shopping Session standard.

---

## 1. Executive Summary

WayTask currently has a durable `ShoppingSession`, but it does not have a complete Shopping Session background architecture.

The current implementation combines three mechanisms whose lifecycles are different:

1. A SwiftData `ShoppingSession` persists a list of legacy item IDs, collected item IDs, one list ID, and one selected store snapshot.
2. A runtime-only `ShoppingPlan` and related store state live in `AppStateManager`.
3. `LocationManager` registers Core Location regions from all globally incomplete legacy `ShoppingItem` records, independent of whether a Shopping Session is active.

As a result, the phrase "Shopping continues in the background" has no single current meaning:

- The committed Shopping Session record survives ordinary suspension, system termination, crash, relaunch, and reboot.
- Shopping code does not continue executing after normal iOS suspension.
- The runtime Shopping Plan survives only while the process remains resident and is lost on cold launch.
- Standard best-accuracy location updates are started whenever location permission exists, but the target has no background-location capability and does not set `allowsBackgroundLocationUpdates`.
- Registered geofences can be monitored by iOS and can wake or relaunch the app under supported conditions, but they are not scoped to the active session.
- A user force quit prevents WayTask from relying on background relaunch until the user manually opens the app again.

The highest-risk current inconsistencies are:

1. **Geofence authority is global, not session-scoped.** Starting or finishing a Shopping Session does not define whether reminders are active. Global incomplete compatibility items do.
2. **Finishing Shopping generally does not stop Shopping reminders.** The session closes, but its items remain globally incomplete, so the same geofences can remain registered.
3. **A geofence refresh can retain an old list/item payload.** Candidate equality includes list and item IDs, but the monitored-region signature omits them. If store, coordinate, radius, source, and item names are unchanged, WayTask skips re-registration even when the owning list or IDs changed.
4. **Notifications trust frozen region payloads.** A region event is not validated against the current session, current list revision, current line outcomes, expiration, or persistence-recovery mode before a notification is produced.
5. **Foreground location use is unnecessarily expensive.** `kCLLocationAccuracyBest` standard updates start for every authorized app run, with no `distanceFilter`, explicit activity type, lifecycle stop, or one-shot request strategy.
6. **Permission escalation is not contextual.** Notification permission is requested during `LocationManager` initialization, and When In Use location permission is immediately escalated to Always from the authorization callback.
7. **Exact recovery is incomplete.** Session progress persists, but the plan, plan revision, store coverage, line snapshots, reminder registrations, expiration, and per-line reconciliation outcomes do not.
8. **Relaunch recovery is coupled to notification authorization.** A valid active session is not automatically selected while notification status remains `.notDetermined`, even though session restoration does not require notification permission.

### Official recommendation

Adopt a **Session-Scoped Persistent Hybrid**:

- A Shopping Session is a durable domain aggregate with explicit `active`, `expired`, `finished`, and `abandoned` states.
- Session state is independent of whether the app process is foreground, background, suspended, or terminated.
- A session persists its list revision, plan/store snapshot, stops, line snapshots, and line outcomes needed for exact offline recovery.
- Background reminders are a derived, best-effort capability of an active session, not evidence that the session exists.
- Core Location region monitoring is the primary background proximity mechanism.
- Standard location updates are foreground-only and short-lived unless a future separately approved use case genuinely requires continuous background location.
- Geofences are registered only for relevant active-session stops and remaining session lines.
- Every location event is validated against persisted session authority before notification content is created.
- Finish, abandon, expiration, permission loss, store recovery, and context revision all reconcile and disarm reminder registrations.
- Passive "nearby shopping opportunity" reminders, if retained, become a separately named, separately consented feature with a different authority and budget.
- BGAppRefresh, Significant Location Change, calendar activity, and AI scheduling may assist maintenance or suggestions, but none becomes the source of truth or a real-time proximity guarantee.

This recommendation is compatible with the WT-030A Orthogonal Product Lifecycle. Product identity, list membership, plan state, session execution, and notification delivery remain separate authorities.

### Terminal decision summary

| Decision | Result |
|---|---|
| Persisted session equals continuous background execution | Rejected |
| Keep current global geofences as session architecture | Rejected |
| Continuous best-accuracy background location | Rejected |
| BGAppRefresh or polling as the session engine | Rejected |
| Significant Location Change as store-arrival detection | Rejected |
| Calendar or AI schedule as authoritative session state | Rejected |
| Explicit persistent session plus bounded session geofences | **Approved** |
| Foreground-only standard location by default | **Approved** |
| Automatic session expiration with explicit recovery UX | **Approved in principle; thresholds remain open** |
| Separate passive nearby-opportunity feature | **Approved boundary; product availability remains open** |
| Implementation under WT-030B | Not authorized |

---

## 2. Audit Mandate, Method, and Evidence

### 2.1 Scope

This audit covers:

- Shopping Plan generation and runtime ownership.
- Shopping Session creation, progress, finish, and relaunch recovery.
- Home, Shopping, Map, Apple Maps handoff, Settings, and notification navigation.
- Standard location updates, smart-nearby detection, and geographic region monitoring.
- Notification authorization, scheduling, cooldown, content, delivery, and deep links.
- App foreground/background/suspension/termination behavior.
- Cold launch, warm launch, reboot, force quit, crash, schema migration, and store recovery.
- Offline operation, poor connectivity, restored connectivity, and future Cloud Sync.
- Battery, wakeups, network use, thermal risk, and platform limits.
- Accessibility, localization, privacy, Android parity, Global Product Concepts, Community Feedback, and future AI workflows.

### 2.2 Source-of-truth order

Where sources disagree, this audit uses:

1. Current implementation and tests at `35a0775`.
2. Current project capabilities, Info.plist values, and SwiftData schemas.
3. Current Apple Developer documentation.
4. `WT-030A_ProductStateUXAudit.md`.
5. Current architecture, Shopping, store-resolution, diagnostics, changelog, beta, and testing documents.
6. The approved v1.0 Product Specification PDF.
7. Historical audits and backlog language.

Historical documents that describe "resume after relaunch" as complete are accurate only for the persisted session row and foreground routing. They do not establish a continuous background-execution or session-scoped reminder guarantee.

### 2.3 Evidence limitations

The following requested files do not exist in the working tree or reachable Git history:

- `Version_1.0.3_ProductSpec.md`
- A pre-existing `WT-030B_ShoppingSessionBackgroundAudit.md` template
- Standalone WT-029 audit/specification documents

`docs/10_PRODUCT_SPECIFICATION.md` and `KNOW_ISSUES.md` contain no usable product requirements. The beta feedback table in `BETA_BACKLOG.md` is unpopulated.

The audit therefore uses:

- `design/v1.0/WayTask_Product_Specification_v1.0.pdf`;
- current WT-029 commits and persistence tests;
- the completed WT-030A audit;
- current source and project configuration;
- current Apple documentation.

The PDF confirms:

- Shopping is intended to be a persistent trip state machine.
- Leaving a trip should save progress.
- Shopping Mode must reconcile uncollected items.
- Manual arrival is the v1 behavior.
- Geofenced automatic arrival is deferred.
- Offline caching and a sync indicator are deferred.

### 2.4 Platform-source policy

All platform-limit conclusions use Apple sources. Principal references are:

- [iOS Background Execution Limits](https://developer.apple.com/forums/thread/685525)
- [Choosing Background Strategies for Your App](https://developer.apple.com/documentation/BackgroundTasks/choosing-background-strategies-for-your-app)
- [Requesting authorization to use location services](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)
- [Getting the current location of a device](https://developer.apple.com/documentation/corelocation/getting-the-current-location-of-a-device)
- [Monitoring the user's proximity to geographic regions](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions)
- [Region Monitoring and iBeacon](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html)
- [`allowsBackgroundLocationUpdates`](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates)
- [`accuracyAuthorization`](https://developer.apple.com/documentation/corelocation/cllocationmanager/accuracyauthorization)
- [`backgroundRefreshStatus`](https://developer.apple.com/documentation/uikit/uiapplication/backgroundrefreshstatus)
- [Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications)
- [Scheduling and handling local notifications](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html)
- [Reducing location accuracy and duration](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html)
- [Reducing your app's battery use](https://developer.apple.com/documentation/xcode/reducing-your-app-s-battery-use)
- [Reducing terminations in your app](https://developer.apple.com/documentation/xcode/reduce-terminations-in-your-app)

### 2.5 Audit terminology

This document distinguishes:

| Term | Meaning |
|---|---|
| Session active | Persisted business state permits continued shopping |
| App active | Scene is foreground and interactive |
| App background | Process transitioned away from foreground and may have brief runtime |
| App suspended | Process remains in memory but executes no code |
| System terminated | Process removed by iOS; background relaunch may still be possible for supported events |
| User force quit | User removed the app from the multitasking UI; background relaunch must not be relied on |
| Reminder armed | Required permissions/settings exist and desired session geofences are registered |
| Notification scheduled | A request has been accepted by `UNUserNotificationCenter` |
| Notification delivered | The system presented or recorded the notification |
| Plan cached | Plan data is recoverable after process death |

These are not interchangeable.

---

## 3. Current Architecture at a Glance

```text
ShoppingListEntry + Product
          |
          | compatibility adapter
          v
     ShoppingItem.isCompleted
          |
          +-------------------------+
          |                         |
          v                         v
 Runtime ShoppingPlan         Global geofence input
 AppStateManager              LocationManager
          |                         |
          | Start Shopping          | region identifier contains
          v                         | frozen list/item/store payload
 Persistent ShoppingSession         v
 item IDs + collected IDs      GeofenceNotificationService
 list/store snapshot                 |
          |                          v
          | UI only             Local notification
          v                          |
 Shopping Workspace                 v
                                  Map deep link
```

The current system has no single coordinator that owns:

- whether a session should have reminders;
- which exact session lines are reminder-eligible;
- whether the registered regions match the current session revision;
- whether the session expired;
- whether a notification event remains valid;
- whether store recovery made the payload unsafe;
- whether notification delivery should open Shopping Mode or Map.

### 3.1 Current authorities

| Concern | Current authority | Persistence |
|---|---|---:|
| Active/finished trip | `ShoppingSession.isActive` | Yes |
| Started/finished time | `startedAt`, `finishedAt` | Yes |
| Session products | Comma-separated legacy `ShoppingItem` UUIDs | Yes |
| Collected products | Comma-separated UUIDs | Yes |
| Session list | Optional `shoppingListID` | Yes |
| Session store | Optional ID/name/coordinate snapshot | Yes |
| Plan and coverage | `AppStateManager.shoppingPlan` | No |
| Plan generation state | `ShoppingPlanGenerationState` | No |
| Selected/recommended plan store | View state and runtime plan | No until session start |
| Location stream | `CLLocationManager` | OS/runtime |
| Monitored regions | Core Location plus encoded identifier | OS-managed between app launches |
| Reminder cooldown | Store-keyed timestamp in `UserDefaults` | Yes |
| Notification deep-link context | Notification payload and runtime app state | Payload survives delivery |
| Nearby opportunities | `AppStateManager` runtime state | No, except dismissal cooldown |
| Background capability status | Not modeled | No |
| Session expiration | Not modeled | No |
| Session abandonment | Not modeled | No |
| Per-line unavailable/skipped/carry-forward | Not modeled | No |

### 3.2 Project capability baseline

The current target has:

- location purpose strings for When In Use and Always;
- a notification purpose string;
- no `UIBackgroundModes`;
- no background-location mode;
- no BackgroundTasks permitted identifiers;
- no BGAppRefresh or BGProcessing registration;
- no remote-notification background mode;
- no APNs entitlement;
- no app entitlements file.

Therefore:

- region monitoring remains technically available because it does not require the continuous background-location mode;
- supported continuous standard background location is not enabled;
- no background refresh, background processing, silent push, or Cloud wake path exists;
- notification behavior is local-only.

---

## 4. Current Shopping Session Data Model

### 4.1 Persisted fields

`ShoppingSession` stores:

- `id`
- `startedAt`
- `finishedAt`
- `isActive`
- `itemIDListRawValue`
- `collectedItemIDListRawValue`
- `shoppingListID`
- `selectedStoreID`
- `selectedStoreName`
- `selectedStoreLatitude`
- `selectedStoreLongitude`

### 4.2 Real current states

Only two durable business states are implemented:

| State | Representation | Notes |
|---|---|---|
| Active | `isActive == true`, normally `finishedAt == nil` | No invariant enforces the combination |
| Finished | `isActive == false`, `finishedAt` set by service | No outcome or reconciliation record |

The following are not current session states:

- planning;
- navigating;
- arrived;
- suspended;
- expired;
- paused;
- abandoned;
- recovered;
- corrupt;
- store completed;
- purchased.

App suspension is an OS process state, not a Shopping Session state.

### 4.3 Current line states

Each session item can be:

- remaining because its UUID is absent from `collectedItemIDs`;
- collected because its UUID is present.

There are no durable states for:

- unavailable;
- skipped;
- carried forward;
- removed after session start;
- missing locally;
- substituted;
- quantity partially collected;
- collected at a specific store;
- collected by another device.

Malformed UUID fragments are silently discarded while decoding. Missing `ShoppingItem` records are omitted from displayed rows, while totals continue to use the stored UUID count.

### 4.4 Missing recovery context

The model does not persist:

- plan identity or plan content signature;
- source list revision;
- plan generation time or freshness;
- store coverage and matched/missing line decisions;
- multi-stop order or current stop;
- product/list-entry display snapshots;
- line quantities;
- last user activity;
- automatic expiration;
- reminder preference;
- geofence/notification registration IDs;
- geofence payload revision;
- authorization/capability snapshot;
- sync revision, tombstone, or device metadata.

### 4.5 Current single-active behavior

`ShoppingSessionService.activeSession` fetches only the newest active row.

If Start Shopping is invoked while any active row exists:

- the service returns the newest existing row;
- newly requested list, items, plan, and store are ignored;
- no explicit Resume confirmation is shown;
- no context-conflict error is produced;
- any older active rows remain active in storage.

This prevents common duplicate creation, but it is not a complete single-active invariant.

---

## 5. Current Shopping Session Lifecycle

### 5.1 Start

The primary current start path is Shopping Workspace:

1. User selects a Shopping list.
2. User generates a current runtime plan.
3. User selects a recommended store.
4. Start Shopping requires the selected list, selected store, and ready plan.
5. `ShoppingSessionService` filters supplied legacy items to `!isCompleted`.
6. If no active session exists, a new persisted session is inserted and saved.
7. The selected list ID and store ID/name/coordinates are copied into the session.
8. The runtime plan is not copied into the session.
9. Shopping Workspace switches to Shopping Mode because its query now finds an active session.

The Home primary action does not create a session directly. It routes to Shopping or resumes the active session.

Legacy session-start code remains in `ProductListView`, but Products no longer presents that Shopping Mode path in its current body. It is latent duplicate code, contrary to the approved decision that Shopping Workspace owns the journey.

### 5.2 Collect and undo

Collect:

- appends the item UUID to the session item list if it was missing;
- appends the UUID to collected IDs;
- saves immediately.

Undo:

- removes the UUID from collected IDs;
- saves immediately.

Neither action:

- changes the Shopping List Entry;
- marks a Product purchased;
- updates `ShoppingItem.isCompleted`;
- changes the plan;
- changes geofence item eligibility;
- updates Product History completion;
- records a store or quantity outcome.

The session-local separation is correct in principle, but the finish boundary never reconciles it.

### 5.3 Navigate

Navigate:

- reads the store name and coordinate persisted in the session;
- opens external Apple Maps in driving mode;
- backgrounds WayTask;
- does not change the session state.

WayTask does not provide turn-by-turn navigation or automatic arrival. That matches the v1 Product Specification's manual-arrival scope, although the current UI enters Shopping Mode immediately after session start rather than implementing a distinct Route -> Navigation -> Arrived state machine.

### 5.4 Finish

Finish Shopping:

1. sets `isActive = false`;
2. sets `finishedAt = Date()`;
3. saves;
4. clears selected/recommended/expanded store UI state;
5. clears the runtime Shopping Plan.

It does not:

- reconcile remaining lines;
- mark unavailable, skipped, or carried-forward outcomes;
- resolve Shopping List Entries;
- stop global geofences as a direct session operation;
- cancel pending session notifications;
- write purchase history;
- close or reset a multi-store route;
- distinguish success from abandonment.

The session change triggers ContentView's geofence refresh signature, but candidate generation still uses all globally incomplete `ShoppingItem` records. Because the candidate signature ignores session state and can remain identical, finishing generally leaves the same regions monitored.

### 5.5 No explicit pause, abandon, or expiration

Leaving Shopping, opening Maps, locking the phone, or backgrounding:

- does not change session state;
- does not write last activity;
- does not show reminder capability;
- does not set an expiration.

An active session can therefore remain active indefinitely until the user explicitly finishes it or the store is lost.

---

## 6. Current Lifecycle by App and Device Event

### 6.1 Behavior matrix

| Event | Session record | Runtime plan | Shopping UI | Standard location | Geofences | New notifications |
|---|---|---|---|---|---|---|
| Foreground use | Persists | Available if generated | Active | Best-accuracy stream runs when authorized | Refreshed from global items | Smart-nearby or region entry |
| App backgrounds | Unchanged | Remains in memory while process lives | Not interactive | No supported continuous-background guarantee | OS may continue registered monitoring | Region callback possible under supported conditions |
| App suspended | Unchanged | Frozen in memory | None | App code does not process updates | OS monitoring is independent | Only if OS wakes app for a region event |
| Warm foreground return | Unchanged | Usually still present | Query shows session | Restarts/continues when authorized | Re-resolved and refreshed | Nearby check runs |
| System terminates process | Persists if last save committed | Lost | None | Stops | Registered regions can remain OS-managed | Region monitoring may relaunch under supported conditions |
| Cold manual launch | Loaded from SwiftData | Lost | Recovery may route to Shopping | Starts when authorized | Rebuilt from current global graph | Nearby/geofence behavior resumes |
| Crash | Last committed session survives | Lost | None until relaunch | Stops with process | OS region state is separate | Future supported region event may relaunch; not crash-specific |
| Device reboot | SwiftData session survives | Lost | None until launch | Stops | No app-owned reboot recovery; OS behavior must be treated as conditional | No guaranteed WayTask execution before supported post-reboot conditions |
| User force quit | Session survives | Lost | None | Stops | Must not be presented as reliably active | No background relaunch guarantee until manual launch |
| Store recreated | Old session moved with quarantined store | Lost | New store has no session | Starts against new graph | Foreground refresh removes/replaces managed regions | Old contextual reminders must not be trusted |
| In-memory fallback | No old persistent session | Lost | No durable session | Runtime only | Runtime registrations may occur | New state is lost on next launch |

### 6.2 Backgrounding while plan generation is running

Plan generation is an in-process `Task` on the main actor:

- its timer is also an in-process task;
- its timeout is checked between stages;
- no `beginBackgroundTask` is used;
- no BGTask is registered;
- no persisted generation job exists;
- no scene-background cancellation or checkpoint exists.

If the app backgrounds:

- work may continue briefly;
- suspension pauses code and timers;
- process termination loses the operation and all partial state;
- foreground return may continue only if the task remained resident;
- a cold launch begins with no plan.

This is acceptable only if plan generation is explicitly foreground work. It is not a background planner.

### 6.3 Relaunch recovery

On app appearance or active-scene transitions, `ContentView` attempts one-time session recovery.

Current recovery:

1. requires the scene to be active;
2. waits until onboarding/startup sheets are absent;
3. asynchronously reads notification settings;
4. refuses to complete while notification status is `.notDetermined`;
5. if an active session exists, selects the Shopping tab.

Problems:

- session recovery is incorrectly gated by notification authorization;
- it restores navigation, not the runtime plan;
- it does not validate list/store/item integrity;
- it does not repair multiple active sessions;
- it does not expire old sessions;
- it does not expose reminder availability;
- it does not distinguish warm, crash, system termination, or force quit.

### 6.4 Reboot

The persisted SwiftData session and committed progress survive reboot.

The current app has no reboot-specific code. On the next manual launch it performs ordinary startup recovery and geofence refresh.

Apple documents that location monitoring is system-managed and that post-reboot monitoring is subject to unlock and API-specific restoration rules. The current legacy `monitoredRegions` API persists region data between app launches, but WayTask does not store a matching registration ledger or verify a reboot transition. Therefore the official current guarantee is:

- **Session recovery after manual launch:** yes, subject to store health and the notification-status gating defect.
- **Reminder delivery before manual relaunch:** not a WayTask guarantee.
- **Payload freshness after reboot:** not guaranteed by current architecture.

### 6.5 Force quit

Apple states that a swipe-up force quit sets a flag preventing background launch until the user manually launches the app again; exceptions are undocumented and must not be relied on. See [iOS Background Execution Limits](https://developer.apple.com/forums/thread/685525).

Current WayTask behavior:

- the committed session remains in SwiftData;
- the runtime plan is lost;
- standard location stops;
- no region-event relaunch can be promised;
- WayTask does not pre-schedule future geographic local notifications;
- its immediate notification request is created only after the app receives a location callback;
- manual relaunch can restore the session and refresh regions.

The product must never promise that proximity reminders remain active after force quit.

### 6.6 Crash recovery

For a normal crash:

- the last successfully saved start/collect/undo/finish state survives;
- any interaction not committed before the crash can be lost;
- the plan and view state are lost;
- no write-ahead session journal or idempotent command log exists;
- relaunch follows the same notification-gated routing recovery.

Apple explicitly recommends state restoration because system terminations cannot be fully eliminated. See [Reducing terminations in your app](https://developer.apple.com/documentation/xcode/reduce-terminations-in-your-app).

---

## 7. Current Location and Geofence Behavior

### 7.1 Standard location stream

`LocationManager`:

- creates one `CLLocationManager` at app initialization;
- sets `desiredAccuracy = kCLLocationAccuracyBest`;
- starts standard updates for both When In Use and Always authorization;
- has no `stopUpdatingLocation` call;
- has no `distanceFilter`;
- has no explicit `activityType`;
- has no explicit auto-pause policy;
- leaves `allowsBackgroundLocationUpdates` at its default `false`;
- does not use `requestLocation`;
- does not use Significant Location Change or Visits.

UI coordinate publication is throttled to the first update, at least 15 meters of movement, or 10 seconds. This reduces SwiftUI invalidation but does not reduce Core Location hardware activity. Every raw update still evaluates smart-nearby detection.

### 7.2 Permission sequence

Current behavior:

- notification authorization is checked/requested when `LocationManager` initializes;
- an explicit Map or Shopping action can request When In Use location;
- when the authorization callback reports When In Use, the app immediately calls `requestAlwaysAuthorization`;
- Settings has a notification permission button but no location authorization status, explanation, or reminder toggle;
- the public `requestAlwaysLocationPermission` method has no caller.

Apple recommends asking for location and notification authorization in context, after the user engages the feature that needs it. It also identifies When In Use as the preferred location access level and reserves Always for necessary automatic updates. See [Requesting authorization to use location services](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services) and [Asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications).

### 7.3 Geofence candidate generation

At app appearance, foreground return, or a signature change:

1. all globally incomplete legacy `ShoppingItem` records are collected;
2. saved stores and MapKit stores are resolved;
3. stores are matched to eligible global items;
4. candidates are capped at 12 managed regions;
5. total monitored regions are capped at 20;
6. radius is clamped to 150-250 meters;
7. entry is enabled and exit is disabled;
8. list/store/item context is serialized into the region identifier.

Candidate selection does not require:

- an active Shopping Session;
- a ready Shopping Plan;
- the session's selected store;
- a current session stop;
- a remaining session line;
- explicit per-session reminder consent.

### 7.4 Geofence signature defect

`ShoppingGeofenceCandidate` equality includes:

- item IDs;
- shopping list ID;
- distance;
- notification type;
- all store fields.

The signature used to decide whether to re-register regions includes only:

- store ID;
- title;
- coordinate;
- radius;
- source;
- item names.

It omits:

- item IDs;
- shopping list ID;
- session ID;
- session state;
- session/list revision;
- expiration;
- notification type;
- computed distance.

Therefore:

- changing from List A to List B with the same product names and stores can leave List A's region payload registered;
- relinking Products to different IDs with the same names can leave old IDs;
- finishing a session does not change the signature;
- a future session with the same store/names can inherit old context;
- notification cooldown and deep link can be applied to stale authority.

This is a correctness and privacy defect, not only a caching optimization issue.

### 7.5 Initial region state

The app handles `didEnterRegion`, but it does not request current region state after registration.

Apple documents that registering a region while already inside it does not produce an immediate entry event; the user must cross a boundary, or the app must explicitly request state for a registered legacy region. See [Region Monitoring and iBeacon](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html).

WayTask partly compensates with its foreground smart-nearby check, but that check:

- requires the app to be running;
- depends on continuous standard updates;
- is based on the same global item set;
- does not make the background path complete.

### 7.6 Region capacity and delivery

Core Location limits an app to 20 monitored conditions/regions. WayTask's 12-region managed cap leaves headroom and is a sound safeguard. Apple also advises prioritizing monitored conditions because the limit is shared and delivery is system-controlled. See [Monitoring the user's proximity to geographic regions](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions).

Region delivery:

- is a boundary-change signal, not continuous tracking;
- can be delayed by system-defined cushion and device conditions;
- does not provide live inventory;
- can wake/relaunch an eligible app;
- requires brief, bounded handling;
- is unavailable or constrained when authorization/settings/hardware conditions do not permit it.

### 7.7 Reduced accuracy and Background App Refresh

WayTask does not inspect:

- `accuracyAuthorization`;
- `UIApplication.backgroundRefreshStatus`;
- whether the user disabled precise location;
- whether Low Power Mode disabled Background App Refresh.

Apple states that reduced accuracy prevents region monitoring and that Background App Refresh availability affects background relaunch behavior. See [`accuracyAuthorization`](https://developer.apple.com/documentation/corelocation/cllocationmanager/accuracyauthorization), [`backgroundRefreshStatus`](https://developer.apple.com/documentation/uikit/uiapplication/backgroundrefreshstatus), and [Region Monitoring and iBeacon](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html).

The current UI can therefore imply reminders are available when they are not.

---

## 8. Current Notification Architecture

### 8.1 Generation paths

WayTask currently generates a shopping notification in two ways:

1. `didEnterRegion` decodes the monitored region identifier and creates an immediate local request.
2. Every raw foreground location update can run smart-nearby detection and create the same kind of immediate request inside 50 meters.

There are no:

- time-triggered shopping reminders;
- calendar triggers;
- server pushes;
- background-refresh notification jobs;
- deferred notification queues;
- scheduled expiration notices;
- session-resume reminders;
- Cloud-generated notifications.

### 8.2 Payload

The region identifier and notification payload can carry:

- store ID;
- saved location ID;
- store title;
- source;
- coordinate;
- item names;
- item IDs;
- shopping list ID;
- distance captured during registration;
- notification type.

It does not carry:

- session ID;
- session revision;
- plan ID/revision;
- session state;
- current stop;
- line outcome revision;
- expiration;
- reminder registration ID;
- idempotency token;
- authoritative timestamp.

The displayed distance is the distance measured when the candidate was registered, not at region entry, so it can be stale and misleading.

### 8.3 Validation

Before scheduling, the service validates only:

- the region identifier can be decoded;
- item names are nonempty;
- the store-specific cooldown elapsed.

It does not read SwiftData to verify:

- the session still exists and is active;
- the list still owns the lines;
- the lines remain needed/remaining;
- the store is still in the session plan;
- the session has not expired;
- reminders remain enabled;
- the local store is not in degraded recovery;
- the payload revision matches the current registration.

### 8.4 Cooldown

Cooldown is:

- 45 seconds in Debug;
- six hours in Release;
- keyed only by store UUID;
- persisted in `UserDefaults`.

Consequences:

- one list/session can suppress another;
- a stale event can suppress a later valid event;
- separate notification types for the same store share the key;
- the cooldown is recorded before `UNUserNotificationCenter.add` completes, so a scheduling failure still suppresses a retry.

The existence of a cooldown is good. Its authority and write timing are not.

### 8.5 Delivery

The request uses `trigger: nil`, so it is an immediate local notification handed to the notification center after the location event.

Apple documents that a local notification already scheduled with the system can be delivered while the app is not running. See [Scheduling and handling local notifications](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html).

That does not mean current WayTask can generate a new reminder while absent in every condition:

- the request must first be created;
- current creation requires a WayTask location callback;
- force quit can prevent that callback from launching the app;
- no future geographic request is pre-scheduled with UserNotifications.

### 8.6 Tap behavior

A notification tap:

- parses the payload;
- can switch the selected shopping list;
- clears a ready plan if the list changes;
- selects the Map tab;
- focuses/materializes/selects the referenced store;
- shows matched products.

It explicitly sets `opensTripMode = false`.

It does not:

- resume Shopping Mode;
- validate or select an active session;
- open the current session stop;
- explain that the notification is stale;
- reconcile the payload with session progress.

Therefore a user can receive a "shopping" reminder while an active session exists and be routed away from the active session to Map.

### 8.7 Context parity

Current context parity is not guaranteed:

```text
Notification item IDs
    = up to three globally incomplete ShoppingItem IDs

Notification list ID
    = currently selected/current list ID at registration time

Active session item IDs
    = frozen IDs from session start
```

These sets can differ.

---

## 9. Current Background Execution Findings

### 9.1 Default iOS behavior

iOS normally suspends an app shortly after it leaves the foreground. There is no general-purpose supported mechanism for continuous code execution, guaranteed periodic execution, or exact-time background polling. See [iOS Background Execution Limits](https://developer.apple.com/forums/thread/685525).

Current WayTask has no general background-task implementation, which means:

- Shopping Session persistence does not require background runtime;
- UI timers and Tasks stop when suspended;
- store search and plan generation are not guaranteed to finish;
- foreground standard location processing does not establish continuous background behavior.

### 9.2 Standard background location

Apple requires the background location mode plus `allowsBackgroundLocationUpdates = true` for supported continuous standard background location. Setting the property without the capability is a fatal configuration error. See [`allowsBackgroundLocationUpdates`](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates).

WayTask has neither the capability nor the property enabled. Therefore:

- it must not claim continuous standard background location;
- the current absence of a background location mode is correct for a geofence-oriented product;
- adding the mode solely to keep the process alive would be unsupported product reasoning and an unnecessary privacy/battery cost.

### 9.3 Region monitoring

Region monitoring is the one current mechanism designed for the store-proximity use case:

- the system monitors registered regions;
- an eligible suspended or non-running app can be woken/launched;
- no continuous app runtime is required;
- the callback must perform minimal work;
- availability and delivery remain conditional.

This mechanism is architecturally appropriate. The current authority and payload lifecycle are the problem.

### 9.4 BGAppRefresh

Apple schedules BGAppRefresh at system discretion for short content refresh work. It is not a real-time scheduler and does not guarantee an exact interval. See [Choosing Background Strategies for Your App](https://developer.apple.com/documentation/BackgroundTasks/choosing-background-strategies-for-your-app).

Current WayTask does not configure it.

Even if added later, it is unsuitable for:

- store-entry detection;
- continuous session execution;
- guaranteed session expiration at an exact minute;
- exact deferred notification timing.

It may be suitable for non-urgent cache maintenance or future Cloud reconciliation.

### 9.5 Significant Location Change

Apple describes Significant Location Change as a lower-power alternative to standard tracking for large movements, not precise store-boundary detection. Region or visit monitoring should be considered first for bounded place-entry use cases. See [Getting the current location of a device](https://developer.apple.com/documentation/corelocation/getting-the-current-location-of-a-device) and [Reducing location accuracy and duration](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html).

Current WayTask does not use it.

It could later help reprioritize distant candidate regions for an explicit passive nearby feature, but it must not be the primary session arrival or notification trigger.

### 9.6 Background push

No APNs entitlement, remote-notification mode, backend, or push token architecture exists.

A future background push:

- remains system-discretionary;
- requires a server;
- cannot substitute for local geofence authority;
- should be reserved for Cloud Sync or server-originated data changes;
- must not become a continuous tracking workaround.

---

## 10. Current Offline and Connectivity Behavior

### 10.1 Fully local operations

After a session has started and the required legacy records still exist, these operations are local:

- display the active session;
- display persisted store name/coordinate;
- collect;
- undo collection;
- finish;
- resume after cold launch;
- hand the stored coordinate to Apple Maps.

Apple Maps route availability is outside WayTask's offline guarantee.

### 10.2 Plan generation

Current plan generation can use persisted saved stores without a current coordinate.

MapKit discovery:

- requires a coordinate;
- requires connectivity and regional Apple Maps data;
- has a 120-second in-memory cache;
- returns no synthetic runtime fallback in the shared resolution engine when MapKit returns no usable result.

The runtime `ShoppingPlan` is not persisted. Therefore:

- a ready plan is lost on cold launch;
- a session cannot reconstruct its coverage/missing-item reasoning;
- poor connectivity after relaunch can prevent rebuilding the same plan;
- a MapKit-only selected store survives in the session only as ID/name/coordinate, not full plan evidence;
- no generated-at/freshness banner exists.

### 10.3 Existing geofences offline

An already registered geographic region and its encoded payload can support a local notification without internet:

- Core Location determines the entry;
- the payload already contains copy inputs;
- UserNotifications is local.

Limitations:

- registration must already have happened;
- full location/background conditions must still permit events;
- a cold-launch refresh cannot rediscover MapKit-only candidates offline;
- the encoded payload may be stale;
- no authoritative validation currently occurs.

### 10.4 Poor connectivity

Poor connectivity can:

- delay or fail MapKit search;
- cause the planner to fail with no eligible stores;
- increase radio energy through repeated/retried searches;
- leave only saved stores available;
- prevent recreation of a lost runtime plan.

Current behavior has no explicit network state, cached-plan state, or "using saved snapshot" state.

### 10.5 Airplane mode

In Airplane mode:

- session progress remains local and functional;
- saved store/session data remains readable;
- MapKit discovery is unavailable;
- region monitoring availability/reliability can be affected by disabled radios and device conditions;
- no deferred Cloud synchronization exists;
- no offline queue is needed for current local-only session commands, but one will be needed for future Cloud Sync.

### 10.6 Recovered connectivity

Current WayTask has no connectivity observer or synchronization coordinator.

Recovered connectivity does not automatically:

- rebuild the plan;
- refresh a persisted plan snapshot;
- retry a failed background plan;
- upload session actions;
- refresh registered geofence payloads.

The user or a foreground lifecycle refresh must trigger current work.

---

## 11. Current Persistence, Migration, and Store Recovery

### 11.1 Normal persistence

Session creation, collect, undo, and finish save the SwiftData context immediately.

This is a correct local-first baseline:

- normal suspension requires no extra save;
- committed progress survives process loss;
- there is no need to keep the app awake merely to preserve session state.

### 11.2 Schema migration

`ShoppingSession` is included in schema V1, V2, and V3. Current migrations are lightweight. Migration tests verify that session records survive normal migration with their fields.

Gaps:

- the migration fixture covers a finished session, not every active-session failure mode;
- no tests cover multiple active sessions;
- no tests cover malformed UUID strings;
- no tests cover missing session items;
- no tests cover reminder reconciliation after migration;
- no session version/revision exists.

### 11.3 Startup repair

Startup repair focuses on Products, Shopping Lists, entries, and compatibility relationships.

It does not:

- validate active session invariants;
- repair multiple active rows;
- expire old sessions;
- rebuild line snapshots;
- verify selected store coordinates;
- reconcile reminder registrations;
- detect stale geofence payloads;
- produce an explicit session recovery result.

### 11.4 Persistent store recovery

If opening or repairing the persistent store fails:

1. WayTask reports diagnostics.
2. It quarantines the store files.
3. It opens a new empty persistent store.
4. If that fails, it opens an in-memory store.
5. If all paths fail, app initialization terminates.

The bootstrap returns `.persistent`, `.recreatedPersistentStore`, or `.inMemoryFallback`, but `WayTaskApp` discards that mode after receiving the container.

Consequences:

- an active session in a quarantined store is not restored into the new store;
- an in-memory session is lost on next launch;
- the user receives no degraded-durability or recovered-store explanation;
- OS-held region identifiers may still reference data from the old store until foreground reconciliation;
- current notification creation does not validate recovery mode.

Store recovery must fail closed for contextual notifications.

### 11.5 Persistence save failure

The session service mutates model fields before calling `save`.

On save failure:

- an error is reported and shown by Shopping Workspace;
- no explicit rollback is performed;
- the in-memory context may still contain dirty mutated values;
- a retry/idempotency contract does not exist.

The official architecture requires command-level atomicity and an observable committed result.

---

## 12. Current Battery and Thermal Analysis

### 12.1 Current energy-positive choices

The following should be retained:

- Core Location region monitoring instead of explicit background polling.
- A 12-region app budget below the platform's 20-region ceiling.
- Bounded 150-250 meter regions.
- Entry-only regions.
- A release notification cooldown.
- Store-resolution caching, in-flight reuse, refresh throttling, and generation counters.
- No plan generation from every location callback.
- UI coordinate throttling.
- Local session writes only on state changes.
- External Apple Maps navigation rather than duplicate in-app navigation tracking.
- No continuous background-location capability.

### 12.2 Current battery risks

The main current risk is not geofencing. It is the foreground standard location stream:

- best accuracy is requested for the lifetime of every authorized process;
- no stop condition exists;
- no one-shot location path exists;
- no distance filter exists;
- every raw update evaluates proximity;
- foreground movement buckets can trigger geofence/store refresh work;
- MapKit searches can involve multiple category queries;
- poor network conditions can extend radio use.

Apple advises choosing the most power-efficient service, reducing requested accuracy and duration, setting the largest useful distance filter, using activity/auto-pause, and stopping updates when no longer needed. See [Getting the current location of a device](https://developer.apple.com/documentation/corelocation/getting-the-current-location-of-a-device) and [Reducing location accuracy and duration](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html).

### 12.3 Background battery reality

Because WayTask lacks continuous-background location configuration:

- the current foreground stream does not become a supported indefinite background stream;
- app suspension limits continued CPU/network drain;
- system geofence monitoring remains comparatively efficient;
- current battery cost is likely concentrated in foreground/transition periods and OS-managed monitoring.

This is an architectural assessment, not a measured battery result. The repository contains no Energy Log baseline, MetricKit energy telemetry, or physical-device battery study.

### 12.4 Thermal risk

Geofence-only idle sessions should have low direct thermal impact.

Thermal risk rises with:

- persistent best-accuracy GPS while the app is open;
- repeated MapKit query groups;
- poor cellular conditions;
- simultaneous Map rendering, planning, and location work;
- future continuous background tracking;
- repeated small wakeups or network retries.

The current code does not inspect thermal state or degrade nonessential work. No current evidence demonstrates a thermal incident, so no thermal redesign is recommended beyond removing documented unnecessary work and adding measurement.

### 12.5 Privacy cost

Battery and privacy are aligned:

- always-started precise location exposes more continuous intent than a user-triggered request;
- immediate escalation to Always is broader than the Map-only foreground need;
- global geofences remain active without an active session;
- the user cannot see whether reminders are armed or disable the specific feature in-app.

The official architecture must make the feature boundary visible and revocable.

---

## 13. Official iOS Constraint Matrix

| Constraint | Apple rule | WayTask implication |
|---|---|---|
| Normal backgrounding | App is normally suspended; no arbitrary continuous runtime | Session must persist without needing code to run |
| Short completion work | `beginBackgroundTask` is limited and must end | May finish a started save, not run a session |
| BGAppRefresh | System-discretionary short refresh, not exact scheduling | Maintenance only; not proximity or expiry authority |
| BGProcessing | System chooses appropriate time, often for deferred heavy work | Not a shopping-session engine |
| Standard background location | Requires location background mode and `allowsBackgroundLocationUpdates` | Current target does not support it; recommendation does not require it |
| Region monitoring | OS-managed, bounded, event-driven | Preferred reminder mechanism |
| Region capacity | Maximum 20 monitored conditions/regions per app | Maintain explicit app budget and priorities |
| Initial inside state | Registration alone does not guarantee an entry callback | Foreground state check/reconciliation required |
| Always authorization | Needed for terminated-app launch for relevant services | Ask only for explicit reminder value |
| When In Use | Preferred; no terminated-app launch for location events | Sufficient for foreground Map/planning |
| Reduced accuracy | Region monitoring unavailable under reduced accuracy | Surface reminder unavailable/degraded state |
| Background App Refresh disabled | Background location event relaunch can be unavailable | Surface status; do not claim armed reminders |
| Low Power Mode | Can disable Background App Refresh/reduce background opportunity | Session survives; reminders are best effort |
| Force quit | Background relaunch is prevented until manual launch, with undocumented exceptions | Never promise force-quit reminders |
| System termination/crash | Persistent state may recover; supported event relaunch can occur | Restore session; validate reminders on every launch |
| Reboot | Monitoring has post-reboot/unlock and API restoration constraints | Reconcile on launch/unlock opportunity; do not guarantee prelaunch delivery |
| Local notifications | Once scheduled, system can deliver without the app running | Current location request must still be generated first |
| Thermal/resource pressure | iOS may throttle/terminate resource-heavy apps | Persist state and keep background callback minimal |

### 13.1 Unsupported promises

WayTask must not promise:

- "Shopping keeps running continuously in the background."
- "We always know when you arrive."
- "A reminder will fire at exactly the configured time."
- "Reminders work after you force quit."
- "An active session means location monitoring is active."
- "A geofence event proves a Product is in stock."
- "Background refresh will keep the plan current."
- "Always permission guarantees delivery."

### 13.2 Supported product promise

WayTask can promise:

> Your Shopping Session and committed progress are saved on this device. If you enable location reminders and iOS allows them, WayTask can notify you near relevant stores. Reminder timing and background delivery are controlled by iOS and may be unavailable after force quit or permission/settings changes.

---

## 14. Cross-Screen and UX Consistency Audit

### 14.1 Home

Home:

- derives active trip progress from the newest active session;
- changes its CTA to Resume Shopping;
- opens Shopping for an active session;
- loses ready-plan presentation after cold launch.

It does not show:

- session age;
- selected store after process loss unless Shopping is opened;
- reminder armed/unavailable state;
- expired/abandoned distinction;
- offline snapshot state.

### 14.2 Shopping

Shopping is the best current session authority:

- shows persisted progress;
- shows persisted selected store;
- allows collect/undo;
- allows Finish;
- can navigate with the stored coordinate.

It does not:

- expose Pause/Leave/Abandon;
- reconcile uncollected lines;
- show reminder state;
- show plan loss after recovery;
- explain that location/background availability is separate;
- prevent silent resume of conflicting context.

### 14.3 Map

Map:

- consumes a ready runtime plan when present;
- otherwise uses global legacy items;
- receives notification context;
- does not project the active session as its default authority.

Therefore:

- active session lines can differ from Map lines;
- session collection does not remove Map/notification items;
- a notification can open a store unrelated to the active session;
- cold-launch Map cannot reconstruct the session's original plan.

### 14.4 Notifications

Notifications:

- can carry a current list label;
- use up to three global legacy items;
- open Map;
- do not identify or resume a Shopping Session;
- do not explain whether the session is active/expired/finished;
- can survive context changes in an OS-held region identifier.

### 14.5 Settings and permissions

Settings says nearby reminders use saved coordinates and active shopping items.

The phrase "active shopping items" currently means global incomplete compatibility items, not active-session lines. Settings has:

- no reminder enable/disable toggle;
- no per-session preference;
- no location status;
- no precise-location status;
- no Background App Refresh status;
- no "after force quit" expectation;
- no region budget/status.

### 14.6 Navigation friction

WT-030A identified that:

- Home cards can route without preserving the intended list;
- notification taps open Map even when an active session may be the likely destination;
- runtime list/plan/session context is not carried consistently.

WT-030B finds the same root cause in background behavior: **context is represented as view state and frozen payload fields rather than a durable, revisioned session identity.**

### 14.7 Beta feedback root causes

The named beta observations cluster as follows:

| Observation | WT-030B relationship | Shared root cause |
|---|---|---|
| Meaning of checkmark | Session collected differs from list checked | Scope is not explicit |
| Removing from Shopping | Global compatibility state alters Map/reminders | Wrong authority crosses scopes |
| Workflow confusion | Plan, session, Map, reminders use different lifecycles | No durable journey aggregate |
| Scan workflow | Scan saves Product, not active trip/list | Context is not carried |
| Navigation friction | Notification opens Map, Home opens generic surfaces | Deep links lack owning context |
| Catalog icon quality | Not a background/session root cause | Taxonomy/presentation issue |
| Input alignment | Not a background/session root cause | Layout/RTL issue |

The first five are different symptoms of missing scoped authority. Icon quality and input alignment should not be incorrectly folded into this architecture.

---

## 15. Current Risk Register

| ID | Severity | Finding | Product/reliability impact |
|---|---|---|---|
| SS-01 | Critical | Geofences use global incomplete items, not the active session | Reminders can be unrelated to current Shopping |
| SS-02 | Critical | Finish/collect do not directly disarm/update session reminders | Finished or collected items can still notify |
| SS-03 | Critical | Geofence signature omits list ID and item IDs | OS region can retain stale authority |
| SS-04 | Critical | Region event is not validated against persistence | Stale/expired/recovered context can notify |
| SS-05 | High | Session and reminder capability are conflated in product language | User cannot know what is actually active |
| SS-06 | High | Runtime plan is not persisted into session context | Cold launch/offline recovery is incomplete |
| SS-07 | High | Best-accuracy standard location runs for entire authorized foreground lifetime | Avoidable battery, privacy, and thermal cost |
| SS-08 | High | Notification permission is requested at initialization | Low-context consent and denial risk |
| SS-09 | High | When In Use immediately escalates to Always | Privacy/value mismatch |
| SS-10 | High | Reduced accuracy and Background App Refresh status are ignored | UI can imply unsupported reminders |
| SS-11 | High | Relaunch recovery is blocked by `.notDetermined` notification state | A durable session may not auto-resume |
| SS-12 | High | Start silently returns an active session with different requested context | Wrong list/store can be resumed |
| SS-13 | High | No expiration, abandon, or active-row repair | Forgotten and duplicate sessions persist |
| SS-14 | High | Store recreation/in-memory fallback is invisible | Session durability can be lost without explanation |
| SS-15 | High | No session/geofence/notification lifecycle tests | Core guarantees lack regression protection |
| SS-16 | Medium | Notification cooldown is store-only and written before schedule success | Valid reminders can be suppressed |
| SS-17 | Medium | Notification distance is frozen at registration | Copy can be misleading |
| SS-18 | Medium | Registering while inside does not request state | Entry reminder can be missed |
| SS-19 | Medium | Notification opens Map, not active session | Context and user intent diverge |
| SS-20 | Medium | No persisted offline plan/store evidence | Recovered connectivity requires manual rebuild |
| SS-21 | Medium | Session UUID arrays silently drop malformed IDs | Corruption is hidden rather than recovered |
| SS-22 | Medium | Missing legacy items disappear while totals retain them | Recovered progress can be internally inconsistent |

---

## 16. Areas That Are Already Correct

No change is recommended solely for architectural purity. The following current decisions address real product needs and should remain:

1. **Persist the session locally.** Session start and progress do not depend on a server.
2. **Save after every user transition.** Collect, undo, and finish are immediately durable when save succeeds.
3. **Keep session collection separate from Product identity.** Collected is session-local, not a global Product purchase flag.
4. **Snapshot selected store name and coordinate.** Navigation remains available if a transient MapKit store is no longer discoverable.
5. **Use external Apple Maps.** WayTask does not need continuous route tracking for v1.
6. **Use region monitoring for proximity.** It is the correct low-power iOS primitive.
7. **Retain a monitored-region budget below 20.** The current 12-region safety cap is prudent.
8. **Clamp region radius.** Bounded radii reduce noisy monitoring.
9. **Retain notification cooldown and probabilistic copy.** Spam prevention and "likely/estimated" language are correct; scope and authority need refinement.
10. **Keep location callbacks from regenerating the Shopping Plan.** Planning remains user/Shopping-owned.
11. **Keep saved stores usable without live MapKit.** This is a valuable offline baseline.
12. **Keep Sentry location/product data sanitized.** No exact location or Product content should be added to remote diagnostics.
13. **Do not add continuous background location by default.** No documented current requirement justifies it.

---

## 17. Time-Based Activity Analysis

### 17.1 Always-active until Finish

**Definition:** A session remains active indefinitely until the user finishes it.

Advantages:

- simplest mental model;
- no surprise expiration during a long trip;
- exact current behavior for persistence.

Disadvantages:

- forgotten sessions remain active for days;
- stale reminders and store context remain eligible;
- Home stays in Resume mode;
- future sync can carry stale active state across devices;
- no privacy/battery bound for reminder registrations.

Decision: rejected as the complete official policy.

### 17.2 Fixed automatic expiration

**Definition:** Every session expires at a fixed duration after start.

Advantages:

- deterministic upper bound;
- easy to test and sync;
- disarms forgotten reminders.

Disadvantages:

- can expire during a legitimate long trip;
- start time alone does not represent ongoing activity;
- exact duration is a product decision not established by evidence.

Decision: useful as a maximum lifetime, not sufficient alone.

### 17.3 Inactivity-based expiration

**Definition:** Expiration is based on last meaningful user/session activity.

Meaningful activity can include:

- collect/undo;
- change current stop;
- explicit resume;
- user-confirmed reminder interaction;
- finish/abandon.

Advantages:

- better matches actual continued use;
- bounds stale sessions without penalizing ordinary foreground/background transitions;
- can stop reminders while retaining recoverable progress.

Disadvantages:

- a long drive or store visit without taps can appear inactive;
- exact inactivity threshold is unresolved;
- background location must not silently extend activity.

Decision: approved as one input to expiration, with an absolute maximum.

### 17.4 User-defined active hours

**Definition:** Session/reminders operate only during configured hours.

Advantages:

- privacy and interruption control;
- can avoid nighttime reminders;
- predictable user preference.

Disadvantages:

- active hours do not prove a user is shopping;
- time zones, travel, daylight-saving changes, and overnight trips complicate behavior;
- hiding a still-active session outside hours would be incorrect;
- requires localization and accessibility work.

Decision: active hours may become **notification quiet hours**, not the session state machine.

### 17.5 Calendar-based behavior

**Definition:** Calendar events start or schedule Shopping automatically.

Advantages:

- useful for recurring shoppers;
- can prewarm a plan or suggest a session.

Disadvantages:

- Calendar permission and sensitive metadata add privacy scope;
- schedules are not proof that a trip occurred;
- iOS background execution is not guaranteed at an exact time;
- false starts can register irrelevant reminders;
- no current product requirement exists.

Decision: defer. Calendar may propose a user-confirmed session; it must never create one silently.

### 17.6 AI smart scheduling

**Definition:** AI predicts when Shopping should become active.

Advantages:

- potentially reduces setup;
- can learn recurring patterns.

Disadvantages:

- probabilistic intent is not consent;
- false positives affect location/privacy/notifications;
- requires explainability and feedback;
- background timing remains constrained by iOS;
- Cloud/community signals may be stale or biased.

Decision: AI may recommend Start/Resume or quiet hours. It may not silently activate session tracking or Always location.

### 17.7 Official time policy

The official architecture uses:

- explicit user Start;
- durable active state independent of app process state;
- last meaningful activity;
- an inactivity threshold;
- an absolute maximum lifetime;
- transition to `expired`, not silent deletion;
- immediate reminder disarm on expiration;
- explicit Resume or Abandon on next user interaction;
- optional quiet hours applied only to notification presentation.

Exact durations and quiet-hour defaults remain Open Questions.

---

## 18. Design Alternatives

### Alternative A - Preserve Current Global Geofence Architecture

**Definition:** Keep persistent sessions, runtime plans, global incomplete-item geofences, and current permission behavior.

Advantages:

- lowest migration effort;
- current nearby-opportunity breadth remains;
- existing payload/deep-link flow remains;
- low background CPU compared with polling.

Disadvantages:

- does not solve list/session/payload drift;
- reminders remain after Finish;
- active session is not reminder authority;
- privacy scope remains broader than user intent;
- plan/session recovery remains incomplete;
- stale payloads remain possible.

Battery: low background, unnecessarily high authorized foreground cost.

Thermals: generally low when suspended; avoidable foreground GPS/MapKit heat.

Implementation complexity: low.

Scalability: poor; global scan and 20-region limit conflict with more lists/stores/users.

Android compatibility: poor; copies an iOS compatibility boolean rather than a platform-neutral domain.

Cloud compatibility: poor; no revision or device registration ownership.

Decision: rejected.

### Alternative B - Always-Active Continuous Location Session

**Definition:** Enable background location mode and run standard high-accuracy updates while a session is active.

Advantages:

- more frequent location samples;
- can support richer route tracking;
- foreground/background behavior appears more continuous.

Disadvantages:

- not required for store-entry reminders;
- high permission and trust cost;
- visible background location indicator may be required;
- higher battery and thermal load;
- force quit and system policy still prevent absolute reliability;
- invites route-history collection and retention questions;
- increases App Review justification burden.

Battery: high.

Thermals: medium to high during movement/navigation/network work.

Implementation complexity: high.

Scalability: poor on each device; Cloud scale does not solve device energy.

Android compatibility: technically possible but subject to different foreground-service and permission rules; UX parity would be difficult.

Cloud compatibility: route uploads create major privacy/security scope.

Decision: rejected for current and recommended WayTask scope. Reconsider only for a separately approved in-app navigation or safety use case.

### Alternative C - Background Refresh or Periodic Polling

**Definition:** Use BGAppRefresh/background fetch to periodically inspect location/session and generate reminders.

Advantages:

- can perform short maintenance;
- could reconcile future Cloud changes;
- no continuous GPS stream is required.

Disadvantages:

- no guaranteed frequency or exact time;
- not an arrival detector;
- location work during refresh still costs energy;
- force quit and system scheduling remain constraints;
- polling duplicates event-driven geofencing;
- encourages misleading reliability promises.

Battery: low to medium depending on frequency and network.

Thermals: low per task, cumulative if abused.

Implementation complexity: medium.

Scalability: medium for maintenance, poor for real-time proximity.

Android compatibility: WorkManager has similar deferral semantics, not exact parity.

Cloud compatibility: useful for reconciliation only.

Decision: rejected as the session/reminder engine; allowed later for non-urgent maintenance.

### Alternative D - Significant Location Change Recalculation

**Definition:** Monitor large movements and recalculate nearby stores/geofences when the device changes area.

Advantages:

- lower power than continuous standard location;
- can update a regional candidate set;
- can relaunch an eligible app under supported conditions.

Disadvantages:

- too coarse for store entry;
- continues around the clock until stopped;
- requires Always permission for terminated-app behavior;
- still subject to force quit and Background App Refresh;
- network search in a brief background callback is unreliable and energy-sensitive;
- does not solve session authority.

Battery: low to medium; potentially higher than bounded regions if left always active.

Thermals: low unless callbacks trigger broad network/search work.

Implementation complexity: medium.

Scalability: useful only for reprioritizing region sets.

Android compatibility: approximate equivalent behavior differs by platform.

Cloud compatibility: neutral.

Decision: rejected as primary. May later support a separately consented passive nearby feature with cached, local candidate data.

### Alternative E - Time-Window or Calendar-Driven Sessions

**Definition:** Arm Shopping and reminders during fixed hours, calendar events, or predicted schedules.

Advantages:

- bounded reminder periods;
- can fit recurring habits;
- user-defined quiet hours improve control.

Disadvantages:

- time does not prove shopping intent;
- exact background activation is unsupported;
- Calendar/AI adds privacy and false-positive risk;
- timezone and schedule complexity;
- does not solve session/revision/payload authority.

Battery: low if only state gating; higher if windows start location streams.

Thermals: low if no continuous tracking.

Implementation complexity: medium to high.

Scalability: scheduling data scales, but behavior becomes hard to explain.

Android compatibility: domain schedule is portable; execution timing is not.

Cloud compatibility: possible, with timezone/version complexity.

Decision: rejected as primary. Quiet hours and user-confirmed suggestions are allowed extensions.

### Alternative F - Session-Scoped Persistent Hybrid

**Definition:** Persist the complete session execution snapshot; use foreground on-demand location and a bounded set of session-derived geofences; validate every event against current persistence; expire and disarm stale sessions.

Advantages:

- aligns UX, persistence, Map, and reminders;
- preserves session progress without continuous runtime;
- low battery and thermal impact;
- respects iOS limits;
- supports exact offline recovery;
- provides a clear permission value proposition;
- scales to multi-stop, Android, Cloud, AI, and community evidence.

Disadvantages:

- requires a deliberate session model migration;
- requires registration reconciliation and a background-safe repository path;
- requires explicit expired/abandoned/recovery UX;
- cannot make iOS geofence delivery deterministic;
- passive nearby opportunities need a separate product decision.

Battery: low.

Thermals: low.

Implementation complexity: medium to high.

Scalability: high; regions are bounded per active session, domain is revisioned.

Android compatibility: high at domain level; platform adapters differ.

Cloud compatibility: high with device-local reminder leases and idempotent commands.

Decision: **approved**.

### 18.1 Comparative decision matrix

| Criterion | Current global | Continuous location | BG refresh | Significant change | Time/calendar | Session hybrid |
|---|---:|---:|---:|---:|---:|---:|
| Session/list correctness | Low | Medium | Low | Low | Low | **High** |
| Background proximity fit | Medium | High | Low | Low | Low | **High** |
| iOS policy fit | Medium | Medium | High | High | Medium | **High** |
| Battery | Medium | Low | Medium | Medium | High | **High** |
| Privacy | Low | Low | Medium | Medium | Medium | **High** |
| Offline recovery | Low | Low | Low | Low | Low | **High** |
| Multi-device scalability | Low | Medium | Medium | Medium | Medium | **High** |
| Android domain parity | Low | Medium | Medium | Medium | Medium | **High** |
| Explanation to user | Low | Medium | Low | Low | Medium | **High** |

---

## 19. Recommended Official Architecture

### 19.1 Architecture name

**Session-Scoped Persistent Hybrid**

### 19.2 Core principles

1. **The session is durable domain state.**
2. **App process state is not session state.**
3. **A plan is rebuildable, but the execution snapshot used by a started session is durable.**
4. **Location reminders are a derived capability, not the source of truth.**
5. **Only explicit user intent can start location-aware Shopping.**
6. **Every background event is validated against current local authority.**
7. **No network or planner work is required in a geofence callback.**
8. **Finish, abandon, and expiration are real lifecycle boundaries.**
9. **One scoped projection feeds Shopping, Map, and Notifications.**
10. **Platform-specific background behavior is isolated behind adapters.**

### 19.3 Domain aggregates

#### Shopping Session

Required conceptual fields:

- stable session ID;
- explicit state: `active`, `expired`, `finished`, `abandoned`;
- started, last-activity, expiration, and ended timestamps;
- owning Shopping list ID and source revision;
- plan snapshot identity/content signature;
- reminder policy;
- current stop;
- schema/domain revision;
- future sync metadata and tombstone semantics.

#### Session Stop

Required conceptual fields:

- stable stop ID;
- order;
- store identity and immutable display/coordinate snapshot;
- state: planned/current/completed/skipped;
- line IDs assigned to the stop;
- plan evidence timestamp and confidence snapshot;
- optional arrival/navigation timestamps.

#### Session Line

Required conceptual fields:

- stable session-line ID;
- source Shopping List Entry ID;
- Product/global concept ID where available;
- Product display snapshot for offline recovery;
- quantity snapshot;
- assigned stop;
- outcome: remaining/collected/unavailable/skipped/carriedForward;
- outcome timestamp and optional actor/device metadata.

#### Reminder Registration

This is a local projection, not Product or session business state.

Required conceptual fields:

- compact registration ID;
- session ID and revision;
- stop ID/store ID;
- region/notification identifier;
- registration status;
- created/updated/expiry timestamps;
- device ID for future sync;
- last event and last successful notification timestamps;
- suppression reason.

### 19.4 Capability projection

The UI derives:

| Capability | Example state |
|---|---|
| Session | Active |
| App | Foreground/background/suspended is not shown as session state |
| Location access | When In Use / Always / denied |
| Accuracy | Precise / approximate |
| Background refresh | Available / unavailable |
| Notifications | Allowed / quiet / denied |
| Reminder | Armed / foreground-only / unavailable / expired |

Example:

> Shopping active - progress saved
>
> Nearby reminder unavailable because Precise Location is off

The second line does not demote or cancel the first.

### 19.5 Authority flow

```text
ShoppingSessionRepository
        |
        | active session + revision + remaining lines + stops
        v
ReminderProjection
        |
        | desired compact registrations
        v
LocationPlatformAdapter
        |
        | OS region event with registration ID
        v
BackgroundSessionValidator
        |
        | reload session; validate state/revision/expiry/line set
        v
NotificationProjection
        |
        | local content from persisted snapshots
        v
UNUserNotificationCenter
        |
        v
Session-aware deep link
```

### 19.6 Foreground location policy

Use:

- one-shot location for planning and recentering when possible;
- standard updates only while a visible Map/flow genuinely needs them;
- the lowest useful accuracy;
- a meaningful distance filter;
- explicit stop when the consumer disappears;
- no continuous background mode by default.

Region monitoring remains independently registered by the platform adapter.

### 19.7 Reminder policy

Session reminders:

- are offered when the user explicitly starts Shopping or explicitly enables reminders;
- use active-session remaining lines only;
- prioritize current and near-future stops;
- fit within a declared app region budget;
- use compact opaque identifiers;
- never encode Product names as the authoritative identifier;
- expire with the session;
- are removed on finish/abandon/expiration;
- are reconciled on launch, foreground, permission change, migration, and store recovery;
- fail closed if persistence authority cannot be read.

### 19.8 Passive nearby opportunities

Current global nearby reminders are not silently inherited by the session architecture.

If product chooses to retain them, they become:

- a separately named feature;
- explicitly opt-in;
- driven by one named list/revision;
- clearly different from "Shopping Session reminders";
- separately budgeted;
- separately cooled down;
- disabled when its source list no longer matches;
- not allowed to open or mutate a session implicitly.

### 19.9 Why this becomes the product standard

It is the only evaluated design that simultaneously:

- preserves local session reliability;
- respects iOS background limits;
- eliminates session/list/notification drift;
- reduces unnecessary battery/privacy cost;
- provides honest UX;
- supports exact offline recovery;
- scales to multi-stop Shopping;
- supports future Cloud/Android without copying iOS runtime assumptions;
- gives AI and community data safe, scoped command boundaries.

### 19.10 Why competing alternatives are rejected

- Continuous background location addresses a problem WayTask does not currently need and adds material battery/privacy cost.
- BGAppRefresh cannot detect arrival reliably.
- Significant Location Change is too coarse for store entry.
- Time/calendar/AI scheduling is intent prediction, not session authority.
- The current global geofence model cannot guarantee context correctness.

---

## 20. Official Session State and Transition Contract

### 20.1 State machine

```text
                         +----------------+
                         |                |
                         v                |
No Session -- Start --> Active -- Expire -+
                         |  |             |
                         |  +--> Finished |
                         |                |
                         +----> Abandoned |
                                          |
Expired -------- explicit Resume ---------+
Expired -------- explicit Abandon -------> Abandoned
```

`Finished` and `Abandoned` are terminal.

`Expired` retains progress but has no armed reminders. It is resumable only by explicit user action.

Foreground/background/suspended/terminated are not nodes in this state machine.

### 20.2 Start transition

Required preconditions:

- explicit user action;
- a named Shopping list and revision;
- at least one eligible session line;
- selected plan/store context adequate for the supported journey;
- no unresolved active-session context conflict.

Required result:

- session, stops, lines, and execution snapshot commit atomically;
- runtime UI may then project the committed session;
- reminder enrollment is a separate capability outcome;
- failure leaves no partial active session.

### 20.3 Existing-session conflict

If Start is requested while a session is:

- active with the same context: present explicit Resume;
- active with different context: present Continue Existing, Finish/Abandon Existing, or Cancel;
- expired: present Resume or Abandon;
- finished/abandoned: start a new session.

Never silently return a different session.

### 20.4 Collect/undo

Collect:

- updates one session line;
- saves atomically;
- updates session last activity;
- updates reminder projection if line eligibility changed;
- does not mutate Product identity or another list.

Undo:

- returns the same line to remaining;
- saves atomically;
- can reintroduce reminder eligibility if policy permits.

### 20.5 Finish

Finish requires explicit reconciliation of every remaining line:

- unavailable;
- skipped;
- carried forward;
- or another approved outcome.

Required result:

- terminal `finished` state;
- ended time;
- all line outcomes durable;
- list/history effects committed according to WT-030A;
- all session reminder registrations disarmed;
- pending session notifications canceled where possible;
- late background events suppressed by revision/state validation;
- summary becomes recoverable history.

### 20.6 Abandon

Abandon is distinct from Finish:

- progress/history retention follows approved policy;
- no successful-trip claim is produced;
- reminders stop;
- list lines are not inferred purchased;
- active-session uniqueness is released.

### 20.7 Expire

Expiration:

- is deterministic from persisted timestamps/policy;
- can be evaluated on launch, foreground, background event, and Cloud merge;
- moves session to `expired`;
- disarms reminders;
- preserves progress;
- never silently marks items purchased or the trip finished.

### 20.8 List/plan mutation during a session

The active session uses its frozen execution snapshot.

Mutating the source list:

- does not silently rewrite the active session;
- makes any future plan projection stale;
- may offer an explicit "Update active session" command;
- must not change notification payloads without a new session revision and registration reconciliation.

### 20.9 Single and multi-store

Single-store Shopping is one-stop execution of the same state machine.

Multi-store support extends:

- stop order;
- current stop;
- line assignment;
- carry-forward outcomes;
- next-stop reminders.

It must not create a separate session architecture.

---

## 21. Official Background and Notification Contract

### 21.1 Background transition

When the app enters background:

- no session-state transition occurs;
- any user-initiated persistence operation already in progress may request only the short time needed to finish safely;
- plan generation is canceled/checkpointed as foreground-only work;
- standard location stops unless a separately approved active foreground-to-background feature requires it;
- region monitoring remains OS-managed;
- no timer is relied on for expiry or notification delivery.

### 21.2 Background geofence event

The handler must:

1. decode only a compact registration ID;
2. open the local authoritative store;
3. find the registration and session;
4. validate session state, revision, expiry, reminder preference, stop, and remaining lines;
5. create notification content from persisted snapshots;
6. update cooldown only after notification scheduling succeeds;
7. finish promptly.

It must not:

- run MapKit search;
- regenerate a plan;
- call AI;
- perform broad Cloud synchronization;
- trust Product names in an OS identifier;
- mutate list/session outcomes;
- send a stale notification because validation failed.

### 21.3 Notification content authority

Notification content is a projection of:

- one active session revision;
- one session stop;
- currently remaining eligible lines;
- current reminder policy.

The content can say "likely available" but must never claim inventory certainty.

### 21.4 Notification tap

For a valid active-session reminder:

1. load and validate session;
2. open Shopping Mode/current stop;
3. offer Map/navigation as a secondary action;
4. if the session expired/finished, show a safe contextual result rather than silently opening stale Map state.

Passive nearby-opportunity notifications, if retained, may open Map because they are not session reminders.

### 21.5 Finish/event race

Finish and event delivery can race.

The contract is:

- terminal session state wins;
- every event re-reads authority;
- an old registration revision is suppressed;
- notification scheduling uses an idempotency key;
- finish cancels known pending requests;
- a delivered notification tap still validates current state.

### 21.6 Capability changes

On notification denial, location denial, approximate location, Background App Refresh unavailability, or region-monitoring failure:

- session stays active;
- reminder state changes;
- registrations are reconciled/stopped where applicable;
- UI explains the specific limitation;
- no repeated automatic permission prompt occurs;
- Settings offers the appropriate user-controlled path.

### 21.7 Force quit contract

No implementation can guarantee code execution after force quit.

The official product behavior is:

- progress remains saved;
- reminders are described as unavailable/unreliable until manual reopen;
- on the next manual launch, session and registrations reconcile;
- no hidden API or background-mode workaround is permitted.

---

## 22. Official Offline and Synchronization Contract

### 22.1 Offline session baseline

With no internet, a started session must support:

- exact session/stop/line display from snapshots;
- collect and undo;
- finish/abandon/expire;
- persisted progress across relaunch;
- selected store coordinate/name;
- local reminder validation for already registered regions;
- clear "saved snapshot" freshness copy.

### 22.2 Cached plan snapshot

The session execution snapshot must include enough data to explain:

- selected store/stops;
- assigned lines;
- likely/missing status at start;
- plan generated time;
- source/provenance;
- confidence/availability disclaimer.

It is not live inventory and must be labeled accordingly.

### 22.3 Offline plan generation

Official behavior:

- saved stores may produce a local plan;
- MapKit-only discovery requires network;
- failure to discover new stores does not erase a cached session snapshot;
- a user can continue the started session offline;
- no background callback should attempt MapKit.

### 22.4 Deferred synchronization

Future Cloud actions use an idempotent local queue:

- session start;
- line outcome changes;
- finish/abandon;
- list reconciliation;
- session tombstone/revision.

Queue requirements:

- ordered per session;
- retry-safe;
- durable;
- no duplicate purchase/history outcome;
- conflict-visible;
- independent of notification delivery.

### 22.5 Recovered connectivity

On foreground/connectivity recovery:

- upload queued commands;
- reconcile remote changes;
- do not replace an active local execution snapshot silently;
- mark store/plan evidence stale when appropriate;
- ask before switching stops/context;
- refresh reminder projection only after a committed session revision.

### 22.6 Future Cloud notification ownership

Cloud Sync must not cause every device to notify for the same region.

Use a device-local reminder lease/ownership concept:

- session data syncs;
- geofence registrations remain device-local;
- one or explicitly selected devices own proximity reminders;
- lease revision prevents duplicate notifications;
- force quit/permission status remains device-specific.

---

## 23. Official Recovery Strategy

### 23.1 Recovery coordinator

Recovery must be a domain coordinator independent of notification permission.

Order:

1. Open the store and retain startup persistence mode.
2. Run schema migration and graph repair.
3. Load all resumable sessions.
4. enforce the active-session invariant or produce a recovery decision.
5. Validate stop/line snapshots and source references.
6. Evaluate expiration.
7. Publish a session recovery result to UI.
8. Evaluate reminder capabilities.
9. Reconcile desired versus actual registrations.
10. Refresh noncritical plan/store data only in foreground.

### 23.2 Warm launch

On active-scene return:

- query current session authority;
- apply expiration;
- reconcile permissions and regions;
- retain runtime plan only if its session/list revision remains valid;
- avoid rerouting the user if they are already handling the session.

### 23.3 Cold launch

On cold manual launch:

- recover exact committed session progress;
- restore Shopping Mode/current stop;
- show saved plan snapshot;
- show reminder capability separately;
- never require notification authorization to restore the session.

### 23.4 Background location launch

On a background region launch:

- initialize only the minimum persistence/reminder path;
- avoid startup sheets, UI routing, broad MapKit resolution, and AI;
- validate one event;
- schedule or suppress;
- finish within system budget.

### 23.5 Crash recovery

Recovery guarantees:

- last committed command survives;
- commands are idempotent;
- incomplete commands do not appear successful;
- the UI can state when the last interaction was not committed;
- reminder projection is recomputed from committed state.

### 23.6 Store recreation

If the persistent store is quarantined/recreated:

- surface a durable-data recovery notice;
- mark session state unavailable rather than pretending no trip existed;
- stop all WayTask-managed regions;
- suppress old contextual events;
- keep quarantine available for support/recovery policy;
- never create notifications from old frozen payloads.

### 23.7 In-memory fallback

In-memory fallback is degraded mode:

- the user must be told changes will not survive app exit;
- location reminders should not arm against nondurable session authority;
- Cloud upload should not claim local durability;
- normal operation may continue only with explicit limitations.

### 23.8 Migration

Migration to the official model must:

- preserve session IDs and timestamps;
- conservatively map current item/collected IDs to line outcomes;
- snapshot current Product display data where resolvable;
- preserve missing items as explicit unresolved lines rather than dropping them;
- not infer unavailable/purchased/skipped;
- disarm legacy regions until validated against migrated revisions;
- resolve multiple active rows by an approved, observable policy;
- be fully local/offline.

The exact multiple-active and missing-item migration UX remains open.

---

## 24. Impact Analysis

### 24.1 UX

Positive:

- Resume always means the same persisted session.
- Users can distinguish saved progress from active reminders.
- Finish and Abandon have predictable outcomes.
- Expired sessions no longer linger silently.
- Notifications open the owning session.
- Offline recovery preserves context.

Cost:

- reminder status and expiration add copy/UI states;
- conflicting-session and remaining-item reconciliation require explicit choices;
- permission education must be concise.

### 24.2 Battery

Positive:

- standard best-accuracy tracking no longer runs for the whole foreground lifetime;
- background behavior uses bounded OS-managed regions;
- no polling or background MapKit;
- finished/expired sessions stop monitoring.

Cost:

- registration reconciliation and one-shot foreground location still use energy;
- multi-stop sessions require prioritization within a budget.

### 24.3 Thermals

Positive:

- no continuous background GPS;
- no background planner/network work;
- fewer foreground updates and searches.

Required:

- physical-device Energy Log/thermal validation;
- defer nonessential refresh if thermal state is serious/critical;
- no claim of improvement without measurement.

### 24.4 Architecture

Positive:

- one domain authority for journey execution;
- platform background details are adapters;
- revisioned projections eliminate stale payload authority;
- compatible with WT-030A.

Cost:

- session/stop/line repositories and migration;
- background-safe validation path;
- explicit capability and registration coordinators.

### 24.5 Persistence

Required:

- normalized session/stop/line storage;
- atomic transitions;
- snapshots and revisions;
- expiration and sync metadata;
- registration ledger.

Risk:

- legacy UUID strings are ambiguous and can reference missing compatibility items;
- migration must be conservative.

### 24.6 Notifications

Positive:

- exact session context;
- stale events suppressed;
- correct deep links;
- independent passive-opportunity feature;
- cooldown success semantics.

Cost:

- local persistence read during background event;
- cancellation/reconciliation logic;
- capability copy and testing.

### 24.7 Geofencing

Positive:

- region budget is tied to current journey value;
- finish/expire disarms;
- compact identifiers reduce stale/private payload risk;
- event validity is revisioned.

Cost:

- current/next stop prioritization policy;
- device field testing remains necessary.

### 24.8 Privacy

Positive:

- permission is requested at the moment of value;
- Always is limited to location reminders;
- no continuous route tracking by default;
- passive discovery is separately consented;
- no Product names need to be placed in region identifiers.

Required:

- clear purpose strings and in-app explanation;
- user-visible reminder controls;
- no precise location in remote diagnostics;
- retention rules for future location-derived events.

### 24.9 Accessibility

Required semantics:

- "Shopping active. Progress saved."
- "Nearby reminders on/off/unavailable."
- explicit store and scope;
- no status by color/icon alone;
- 44-point targets;
- VoiceOver action/result parity;
- Dynamic Type wrapping;
- Reduce Motion;
- Switch Control and keyboard focus.

Permission/status instructions must identify the setting without relying on screenshots.

### 24.10 Localization

Required:

- shared terms for Active, Expired, Finished, Abandoned, Remaining, Collected, Unavailable, Skipped, Carried Forward, Reminder, Precise Location, and Offline Snapshot;
- English/Hebrew parity;
- RTL-safe store/product interpolation;
- local date/time/calendar formatting;
- plural rules for line/store counts;
- timezone-safe quiet hours and expiration;
- no raw enum values.

### 24.11 Offline support

Positive:

- exact local session execution;
- persisted plan/store snapshots;
- local geofence validation;
- idempotent future sync queue.

Cost:

- snapshot freshness and conflict UX;
- more durable data.

### 24.12 Performance

Positive:

- no global full-library scan for every session reminder;
- indexed query by active session/revision;
- bounded registration set;
- less standard location churn.

Cost:

- more normalized rows;
- reconciliation query on lifecycle/event boundaries.

These costs are bounded by active-session size and preferable to global compatibility scans.

### 24.13 Testing

Testing expands from UI happy paths to:

- state transitions and invariants;
- process/device lifecycle;
- background capability combinations;
- race conditions;
- migration;
- offline/Cloud queues;
- energy and field behavior;
- accessibility/localization.

### 24.14 Future Android parity

Shared domain:

- session states;
- stop and line outcomes;
- revisions and timestamps;
- expiration;
- reminder policy;
- notification context;
- sync commands.

Platform-specific:

- iOS Core Location/BackgroundTasks;
- Android geofencing, background limits, and notification permissions;
- force-stop semantics;
- device reminder lease.

Android must not copy iOS `CLRegion` identifiers or legacy `ShoppingItem.isCompleted`.

### 24.15 Future Cloud Sync

Required:

- stable IDs;
- local-first commands;
- idempotency;
- revision/conflict policy;
- tombstones;
- device-local capability/registration state;
- duplicate-notification prevention;
- server time skew handling.

### 24.16 Future AI workflows

AI may:

- suggest starting/resuming a session;
- propose stop order;
- propose expiration/quiet-hour preferences;
- explain stale plan evidence;
- propose unavailable/carry-forward outcomes;
- learn from explicit outcomes.

AI may not:

- silently enable Always location;
- silently start a session;
- silently mark a line collected/purchased;
- claim background delivery;
- treat geofence entry as purchase evidence.

### 24.17 Global Product Concepts

Session lines reference stable Product/global concept identity where available while preserving a display snapshot.

Catalog/global concept changes:

- can improve future plans;
- do not rewrite active session lines silently;
- do not erase offline display;
- do not change collection outcomes;
- require explicit revision if applied to an active session.

### 24.18 Community Feedback

Community availability feedback is evidence, not session truth.

It may:

- adjust future confidence;
- explain recommendation provenance;
- improve plan refresh after connectivity returns.

It may not:

- generate a collected outcome;
- override explicit user state;
- mutate an active snapshot without confirmation;
- be required for offline execution;
- leak another user's location or trip.

---

## 25. Measurable Acceptance Criteria

These criteria define the official architecture outcome. They do not authorize implementation.

### 25.1 Session domain

- **AC-01:** Exactly one session aggregate can be `active` per approved user/account scope.
- **AC-02:** Start with no active session atomically persists session, stops, lines, source list revision, and plan/store snapshot.
- **AC-03:** Start against a conflicting active/expired session produces an explicit decision and never silently returns different context.
- **AC-04:** Collect/undo survives 100 consecutive cold-launch test cycles after successful commit with identical line outcomes.
- **AC-05:** Finish, Abandon, and Expire are distinct persisted transitions.
- **AC-06:** Every terminal Finish has an explicit outcome for every line.
- **AC-07:** Backgrounding, suspension, system termination, and warm return do not themselves change session business state.
- **AC-08:** No Product or another list is mutated by collect/undo unless an explicit finish-reconciliation command requires it.

### 25.2 Recovery

- **AC-09:** Cold launch restores the exact active/expired session stop, line order, quantities, outcomes, and selected store snapshot without network.
- **AC-10:** Session restoration runs when notification status is `.notDetermined`, denied, provisional, or authorized.
- **AC-11:** Missing source Product/list records remain visible as recoverable snapshot lines; counts never silently drop them.
- **AC-12:** Migration tests cover active, finished, expired, abandoned, malformed legacy IDs, missing items, and multiple-active fixtures.
- **AC-13:** Store recreation stops/suppresses every WayTask-managed contextual region before any new reminder is allowed.
- **AC-14:** In-memory fallback displays a nondurable-mode warning and does not arm session reminders.

### 25.3 Background and location

- **AC-15:** With no visible location consumer, no standard location stream remains active.
- **AC-16:** A stationary, screen-off active session produces no WayTask standard-location updates, plan searches, or periodic polling during a 60-minute Energy Log run.
- **AC-17:** The target contains no continuous background-location capability unless a separately approved product requirement and privacy review exists.
- **AC-18:** Region registration is derived only from the active session revision or a separately consented passive feature.
- **AC-19:** Desired and actual region sets converge after start, collect/undo, finish, abandon, expire, permission change, foreground return, and migration.
- **AC-20:** The app never exceeds its declared region budget or the platform maximum.
- **AC-21:** Approximate location, denied permission, unavailable monitoring, and disabled Background App Refresh each produce a distinct capability state.
- **AC-22:** No UI or notification claims force-quit background reliability.

### 25.4 Notifications

- **AC-23:** Every session notification resolves to one valid active session ID and revision.
- **AC-24:** Notification line IDs equal the eligible remaining line IDs in the validated source projection, subject only to a documented display-count limit.
- **AC-25:** A stale, finished, abandoned, expired, missing-store, or mismatched-revision event schedules no contextual notification.
- **AC-26:** Finish/abandon/expire cancels known pending session requests and disarms desired registrations in the same lifecycle reconciliation.
- **AC-27:** Cooldown is scoped by feature/session/store/context and is recorded only after scheduling succeeds.
- **AC-28:** A session notification tap opens the exact active session/stop; a passive opportunity tap opens its separately defined destination.
- **AC-29:** Notification copy never displays registration-time distance as current distance unless it was revalidated.
- **AC-30:** Permission prompts occur only after an explanatory, user-initiated feature action.

### 25.5 Offline

- **AC-31:** Collect, undo, finish, abandon, expire, and relaunch work with all networking disabled.
- **AC-32:** A started session displays its plan/store/line snapshot after cold launch with no network.
- **AC-33:** Existing valid local region events can create notification content without MapKit, AI, or Cloud access.
- **AC-34:** Recovered connectivity syncs queued commands idempotently and never duplicates a terminal outcome.
- **AC-35:** A stale cached plan is labeled with source time/freshness and is not presented as live inventory.

### 25.6 Battery and thermal

- **AC-36:** Foreground planning and Map flows use one-shot/bounded location and stop it when the last consumer leaves.
- **AC-37:** A 60-minute stationary active-session Energy Log test shows no continuous WayTask GPS activity after the foreground consumer closes.
- **AC-38:** A 30-minute representative plan/Map/session test causes no WayTask-attributable transition to serious or critical thermal state.
- **AC-39:** No background region callback performs MapKit search, AI work, plan generation, or broad Cloud synchronization.
- **AC-40:** Device battery/energy comparison is recorded on at least one oldest-supported and one current device before release; regression against the approved baseline is zero for idle-session background work.

### 25.7 Accessibility and localization

- **AC-41:** VoiceOver announces session state and reminder capability as separate values.
- **AC-42:** State and capability are never communicated by icon or color alone.
- **AC-43:** English and Hebrew tests cover all session states, permission states, plural counts, expiration, and quiet-hour time formatting.
- **AC-44:** Dynamic Type through accessibility sizes preserves the differentiating state and action.
- **AC-45:** RTL order and notification interpolation are verified with mixed Hebrew store names and Latin Product names.

### 25.8 Cross-platform and sync

- **AC-46:** Shared transition fixtures produce equivalent domain outcomes on iOS and future Android.
- **AC-47:** Device-local reminder registration/capability fields never become Cloud session business state.
- **AC-48:** Two-device sync tests deliver no duplicate proximity notification under the approved device reminder-lease policy.
- **AC-49:** Global Product Concept/community updates cannot mutate active line outcomes without an explicit session revision/command.
- **AC-50:** AI suggestions require confirmation before Start, Finish reconciliation, permission escalation, or schedule activation.

---

## 26. Open Questions

These questions are intentionally unresolved. Implementation must not invent answers.

### Session policy

1. What inactivity duration should move an active session to `expired`?
2. What absolute maximum lifetime should apply regardless of activity?
3. Does explicit Navigate reset inactivity, or only user mutations?
4. Can an expired session be resumed indefinitely, or is there a retention limit?
5. What progress/history is retained after Abandon?
6. What exact user choices reconcile remaining lines at Finish?
7. Should a source-list change offer an explicit Update Session command during a trip?
8. What is the approved policy when migration finds multiple active legacy sessions?
9. How should missing legacy items be named and reconciled during migration?

### Reminder product policy

10. Are session proximity reminders opt-in per session, enabled by a persistent preference, or both?
11. Should Always location be requested at the first reminder opt-in or through a separate education step?
12. Should WayTask request temporary precise location, direct users to Settings, or run foreground-only when approximate location is selected?
13. What exact region budget is reserved for active-session stops versus passive nearby opportunities?
14. Should only the current stop be monitored, or current plus future stops?
15. Should reminder quiet hours exist in v1, and what are their defaults?
16. Should a notification delayed into quiet hours be discarded, delivered quietly, or delivered when quiet hours end?
17. Does WayTask retain passive global nearby opportunities as a separate feature?
18. If retained, which named list owns passive nearby opportunities?
19. What copy communicates Background App Refresh, Low Power Mode, reboot, and force-quit limits without overwhelming users?

### Notification UX

20. Should a valid session reminder open Shopping Mode directly or first show a session-aware store sheet?
21. What should a tap do if the session finished after notification delivery?
22. If persistence cannot be opened during a region callback, should WayTask suppress completely or send a generic noncontextual notification?
23. How many Product names should appear in notification copy?
24. Should current distance be omitted entirely from region notification copy?
25. Should notification actions include Resume, Navigate, or Dismiss for this session?

### Offline and planning

26. How long is a plan/store evidence snapshot considered fresh?
27. Which saved-store data is sufficient to generate an offline plan?
28. Should the app allow Start Shopping from a stale cached plan with explicit confirmation?
29. Should connectivity recovery refresh a plan automatically in foreground or require user action?
30. What happens when the selected transient store no longer resolves after connectivity returns?

### Store recovery and diagnostics

31. What user-facing recovery experience is approved for a quarantined store?
32. How long are quarantined stores retained and how can support recover them?
33. Is in-memory fallback allowed for a production shopping session?
34. Which device-only energy/background diagnostics may be retained, and for how long?
35. Should MetricKit energy/termination collection be enabled under the existing privacy policy?

### Cloud, Android, AI, and community

36. Is the one-active-session invariant per device, user, household, or list?
37. Which device owns proximity reminders in a multi-device account?
38. How is reminder ownership transferred when the owning device is offline or force-quit?
39. What conflict policy applies when two devices collect the same line differently?
40. Are session timestamps server-normalized, device-local, or hybrid?
41. What Calendar access, if any, is acceptable for future scheduling?
42. What evidence/explanation is required before AI proposes active hours or session start?
43. How does Community Feedback freshness affect a cached plan without rewriting the active snapshot?
44. Which Global Product Concept changes may be offered to an active session as an explicit update?

---

## 27. Terminal Decision

### 27.1 Decision

Approve the **Session-Scoped Persistent Hybrid** as the official WayTask Shopping Session architecture.

### 27.2 Binding product standard

The official standard is:

1. A Shopping Session is durable and process-independent.
2. Active does not mean the app is continuously running.
3. Active does not mean reminders are armed.
4. The session persists exact execution context and line outcomes.
5. Region monitoring is the default background proximity mechanism.
6. Standard location is foreground/on-demand by default.
7. Every reminder is derived from and validated against one active session revision.
8. Finish, Abandon, and Expire immediately disarm session reminders.
9. Force quit, permission, approximate location, Background App Refresh, and system delivery limits are communicated honestly.
10. Passive nearby opportunities are separate from Shopping Session reminders.
11. Offline session execution is first-class.
12. Cloud, Android, AI, Global Product Concepts, and Community Feedback extend the domain contract without becoming hidden state owners.

### 27.3 Rejected standards

The following must not become WayTask's official architecture:

- global `ShoppingItem.isCompleted` as reminder authority;
- encoded region payload as authoritative session state;
- continuous best-accuracy tracking solely to keep Shopping alive;
- background polling as arrival detection;
- time/calendar/AI inference that silently activates location-aware Shopping;
- notification authorization as a prerequisite for restoring a session;
- silent reuse of a conflicting active session;
- Finish that leaves unresolved lines and active reminders;
- Cloud synchronization that duplicates device notifications.

### 27.4 Implementation boundary

WT-030B authorizes no implementation.

No production code, project capability, entitlement, schema, test, or app behavior is changed by this audit.

### 27.5 Final conclusion

The current persisted `ShoppingSession` is a sound foundation and does not need replacement merely for purity. The required change in product standard is to complete its authority boundary:

- persist the execution snapshot;
- separate session state from OS execution/capability;
- scope geofences and notifications to the session;
- validate every event;
- bound reminders by finish/abandon/expiration;
- stop unnecessary foreground location;
- make recovery and offline behavior explicit.

This architecture provides the strongest reliability WayTask can honestly offer within iOS constraints while minimizing battery, thermal, privacy, and future migration risk.

---

## Appendix A - Current Lifecycle Truth Table

| Question | Current answer |
|---|---|
| Does Shopping Session survive normal backgrounding? | Yes, as persisted state |
| Does Shopping code keep executing while suspended? | No |
| Does Shopping Plan survive suspension? | Only if the process remains resident |
| Does Shopping Plan survive cold launch? | No |
| Does session progress survive system termination/crash? | Last committed state does |
| Does session survive reboot? | Persisted session does; reminders are not a prelaunch guarantee |
| Does session survive force quit? | Data does; background relaunch/reminders cannot be relied on |
| Does current standard location continue indefinitely in background? | No supported guarantee |
| Can registered regions work while app is not foreground? | Yes, under iOS conditions |
| Are current regions scoped to active session? | No |
| Does Finish stop reminders? | Not reliably; generally no |
| Does Collect remove reminder eligibility? | No |
| Does a region event validate current session? | No |
| Do notifications always match the named list? | No |
| Do notification taps resume session? | No; they open Map |
| Can an already scheduled local notification deliver while app is absent? | Yes |
| Does WayTask pre-schedule future geographic notifications? | No |
| Does BGAppRefresh maintain Shopping? | No; not configured |
| Does Significant Location Change maintain Shopping? | No; not configured |
| Is offline collect/finish supported? | Yes |
| Is offline plan recovery supported? | No |
| Does normal schema migration retain ShoppingSession? | Yes |
| Does startup repair validate ShoppingSession? | No |
| Is store recovery visible to user? | No |

---

## Appendix B - Current to Official Authority Map

| Concern | Current | Official |
|---|---|---|
| Session lifecycle | `isActive` Boolean | Explicit active/expired/finished/abandoned |
| Line lifecycle | UUID in collected set | Persisted session-line outcome |
| Session context | Item IDs + one store | List revision + plan/stop/line snapshots |
| Plan recovery | Runtime only | Durable execution snapshot; plan remains rebuildable |
| Reminder source | Global incomplete ShoppingItems | Active session revision and remaining lines |
| Region identifier | Encoded store/list/item payload | Compact opaque registration ID |
| Event validation | Decode + cooldown | Repository validation of session/revision/expiry |
| Foreground location | Lifetime best accuracy | One-shot/bounded consumer-scoped |
| Background location | Implicit expectation | Region monitoring only by default |
| Finish | Close session only | Reconcile lines + terminal state + disarm |
| Relaunch | Notification-gated tab routing | Domain recovery independent of notifications |
| Offline | Progress only | Progress + stop/line/plan snapshot |
| Cloud | None | Idempotent commands + device reminder lease |
| Android | No contract | Shared domain fixtures, platform adapters |
| AI | Runtime suggestions | Confirmed commands only |

---

## Appendix C - Evidence Inventory

### Product and architecture

- `WT-030A_ProductStateUXAudit.md`
- `design/v1.0/WayTask_Product_Specification_v1.0.pdf`
- `docs/15_ENGINEERING_BLUEPRINT.md`
- `docs/20_ARCHITECTURE.md`
- `docs/00_PROJECT_STATUS.md`
- `DECISIONS.md`
- `ROADMAP.md`
- `README.md`

### Shopping and planning

- `ShoppingSession.swift`
- `ShoppingSessionService.swift`
- `ShoppingTripService.swift`
- `ShoppingContext.swift`
- `ShoppingMission.swift`
- `ShoppingMemoryService.swift`
- `WayTask/ShoppingWorkspaceView.swift`
- `WayTask/HomeView.swift`
- `ProductListView.swift`
- `WayTask/AppStateManager.swift`
- `StoreSearchService.swift`
- `ShoppingFlow.md`
- `ShoppingFlowAudit.md`
- `ShoppingFlow_Implementation.md`
- `docs/Specifications/ShoppingFlow_v1.md`
- `docs/100_SHOPPING_TRIPS.md`
- `docs/140_STORE_RESOLUTION_ENGINE.md`

### Location, Map, and notifications

- `WayTask/LocationManager.swift`
- `GeofenceNotificationService.swift`
- `WayTask/MainMapView.swift`
- `MapViewModel.swift`
- `WayTaskMapView.swift`
- `MapBottomSheet.swift`
- `SettingsView.swift`
- `WayTask/Info.plist`
- `WayTask.xcodeproj/project.pbxproj`

### App lifecycle and persistence

- `WayTask/WayTaskApp.swift`
- `WayTask/ContentView.swift`
- `WayTask/Persistence/WayTaskSchema.swift`
- `WayTask/Persistence/WayTaskSchemaV1.swift`
- `WayTask/Persistence/WayTaskStartupPersistence.swift`
- `WayTaskTests/Persistence/WayTaskSchemaMigrationTests.swift`
- `WayTaskTests/Persistence/StartupPersistenceResilienceTests.swift`
- `WayTaskTests/Persistence/StartupRepairIdempotencyTests.swift`

### Beta, diagnostics, changelogs, and tests

- `BETA_BACKLOG.md`
- `CHANGELOG.md`
- `docs/55_SPRINTS.md`
- `docs/60_CHANGELOG.md`
- `docs/65_BETA_CHECKLIST.md`
- `docs/130_BETA_RELEASE_PLAN.md`
- `docs/170_BETA_DIAGNOSTICS.md`
- `docs/180_SENTRY_INTEGRATION.md`
- `TESTING.md`
- `RELEASE_CANDIDATE_CHECKLIST_1.0.1.md`
- `WayTaskTests/ShoppingUX/ShoppingWorkspaceUXTests.swift`
- `WayTaskTests/Map/MapBottomSheetProductLabelTests.swift`

---

## Appendix D - Apple Platform References Applied

| Source | Applied conclusion |
|---|---|
| [iOS Background Execution Limits](https://developer.apple.com/forums/thread/685525) | No arbitrary continuous/periodic execution; force quit prevents relied-upon background relaunch |
| [Choosing Background Strategies](https://developer.apple.com/documentation/BackgroundTasks/choosing-background-strategies-for-your-app) | Background tasks are purpose-specific and system-scheduled |
| [Requesting location authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services) | Prefer When In Use; ask in context; Always enables certain terminated-app launches |
| [`allowsBackgroundLocationUpdates`](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates) | Continuous background standard location requires capability and property |
| [Getting current location](https://developer.apple.com/documentation/corelocation/getting-the-current-location-of-a-device) | Select the lowest-power service; stop/reduce accuracy/distance |
| [Monitoring geographic regions](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions) | System-managed event monitoring; 20-condition limit; post-reboot conditions |
| [Region Monitoring and iBeacon](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html) | Background wake, short handling, initial-inside behavior, delivery cushion, Background App Refresh dependency |
| [`accuracyAuthorization`](https://developer.apple.com/documentation/corelocation/cllocationmanager/accuracyauthorization) | Approximate location prevents region monitoring |
| [`backgroundRefreshStatus`](https://developer.apple.com/documentation/uikit/uiapplication/backgroundrefreshstatus) | Background refresh can be disabled/restricted, including by Low Power Mode |
| [Asking notification permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications) | Ask in context and recheck settings |
| [Scheduling local notifications](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html) | System delivers accepted scheduled local notifications without app runtime |
| [Location energy guidance](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html) | Reduce accuracy/duration; prefer regions for place entry; stop updates |
| [Reducing battery use](https://developer.apple.com/documentation/xcode/reducing-your-app-s-battery-use) | Do less work, work efficiently, avoid API misuse, and measure on device |
