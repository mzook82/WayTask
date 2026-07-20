• # WayTask Shopping Flow Audit

  No project files were modified. This is a static source audit of the current workspace.

  ## Executive assessment

  The Shopping Planner is substantially implemented and uses real SwiftData shopping items,
  saved stores, the user’s location, and live MapKit store discovery.

  The end-to-end Shopping Flow is not complete:

  - Suggested stores are displayed but cannot be selected from the Shopping Plan.
  - Start Shopping is connected and creates a persistent ShoppingSession.
  - After session creation, no navigation or Shopping Mode presentation occurs.
  - The existing Shopping Mode UI is unreachable code inside ProductListView.
  - Navigation exists only as a separate Map flow that launches external Apple Maps.
  - No shopping route, ETA, multi-stop order, or session-linked location tracking exists.

  The observed “button does nothing” behavior is therefore real, but it is primarily an
  unfinished integration rather than an empty button placeholder.

  ———

  # Part 1 — User Flow

  ## Expected versus actual flow

  CURRENT IMPLEMENTATION

  Shopping Tab
      ↓
  Choose Products / Shopping List
      ↓
  Generate Shopping Plan
      ↓
  Display Ranked Store Suggestions
      ├── View Map → Map auto-selects best store → user may select another pin
      │                                      ↓
      │                              Navigate in Apple Maps
      │
      └── Start Shopping → ShoppingSession persisted
                                ↓
                           No visible transition

   Step                       Status         Current behavior
  ━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Shopping Tab               ✅ Complete    The root TabView mounts ShoppingWorkspaceView
                                             as a real tab.
  ─────────────────────────  ─────────────  ─────────────────────────────────────────────────
   Shopping list/workspace    ✅ Complete    Reads persistent shopping lists and entries,
                                             allows product choice, checking, quantity
                                             changes, and removal.
  ─────────────────────────  ─────────────  ─────────────────────────────────────────────────
   Shopping Plan              🟡 Partial     Real generation, store discovery, intent
                                             grouping, coverage estimates, and ranking
                                             exist. It is runtime-only and not a route plan.
  ─────────────────────────  ─────────────  ─────────────────────────────────────────────────
   Store Selection            ❌ Missing     Stores are display rows, not selectable plan
                                             choices. No chosen store is stored in
                                             ShoppingPlan or ShoppingSession.
  ─────────────────────────  ─────────────  ─────────────────────────────────────────────────
   Start Shopping             🟡 Partial     Creates a SwiftData session, but performs no
                                             handoff, navigation, confirmation, or Shopping
                                             Mode presentation.
  ─────────────────────────  ─────────────  ─────────────────────────────────────────────────
   Navigation                 🟡 Partial     Separate Map flow supports pin selection and
                                             launching external Apple Maps. Start Shopping
                                             does not invoke it.
  ─────────────────────────  ─────────────  ─────────────────────────────────────────────────
   Shopping Session           🟡 Partial     Persistent model and service exist; an old
                                             Shopping Mode UI exists but is not mounted
                                             anywhere.
  ─────────────────────────  ─────────────  ─────────────────────────────────────────────────
   Location tracking          🟡 Partial     Current-location and geofence infrastructure
                                             exists, but no session route/progress/history
                                             tracking exists.

  The root tab setup is in WayTask/ContentView.swift:31.

  ———

  # Part 2 — File Discovery

  ## Core views

   File                Responsibility                                            Status
  ━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━
   WayTask/            Main Shopping screen, list presentation, plan             🟡 Partial
   ShoppingWorkspac    generation, plan sheet, and Start Shopping action.
   eView.swift:5
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   WayTask/            Root tabs, Shopping onboarding, list backfill, list       ✅ Complete
   ContentView.swif    selection, geofence refresh.
   t:31
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   WayTask/            Home plan summary and alternate Start Shopping entry.     🟡 Partial
   HomeView.swift:7    Also creates a session but then only opens Shopping
   19                  workspace.
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   ProductListView.    Product library plus unused legacy Shopping Mode UI       🟡 Partial
   swift:324           and item collection controls.
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   WayTask/            Displays a shared plan on Map, handles store pins, and    🟡 Partial
   MainMapView.swif    launches Apple Maps navigation.
   t:117
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   WayTaskMapView.s    MKMapView bridge, store/product annotations, user         ✅ Complete
   wift:4              location, and proximity circles.
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   MapBottomSheet.s    Selected-store card with matching items, Navigate,        ✅ Complete
   wift:3              website, and saved-store details actions.
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   MapFilterBar.swi    Map search/category/shopping-list filtering.              ✅ Complete
   ft:3
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   MapControls.swif    Follow-user and add-store controls.                       ✅ Complete
   t:3
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   BuyingOptionsShe    Alternate store/coverage presentation used from           ✅ Complete
   et.swift:3          Products.
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   WayTask/            Persistent saved-store item details.                      ✅ Complete
   LocationDetailVi
   ew.swift:5
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   SettingsView.swi    Allows user-created stores that can enter the planner.    ✅ Complete
   ft:7
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   WayTaskDesignSys    Shared button and store-card components, including        ✅ Complete
   tem.swift:202       actual disabled-button behavior.

  ## State, ViewModels, and models

   File                Responsibility                                            Status
  ━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━
   WayTask/            Owns runtime ShoppingPlan, plan state machine, current    🟡 Partial
   AppStateManager.    list, Map handoff, and tab selection.
   swift:119
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   MapViewModel.swi    Map stores, ranking/display order, Map-only selected      🟡 Partial
   ft:157              store, user coordinate, camera state, and Apple Maps
                       launch.
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   WayTask/            SwiftData Product, ShoppingItem, ShoppingList,            🟡 Partial
   Models.swift:459    ShoppingListEntry, and saved GeoLocation models.
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   ShoppingSession.    Persistent session with item IDs, collected IDs,          🟡 Partial
   swift:4             timestamps, and active state.
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   BuyingOption.swi    Store suggestion presentation model.                      ✅ Complete
   ft:3
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   StoreCoverage.sw    Matched/missing items, heuristic coverage, distance,      🟡 Partial
   ift:4               and ranking.
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   ShoppingIntentMa    Product intent classification, group creation, store-     ✅ Complete
   tcher.swift:828     category eligibility, and planner requests.
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   DataSourceType.s    Identifies MapKit, user-generated, local, debug, and      ✅ Complete
   wift:3              future store sources.
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   StoreAnnotation.    Map store annotation wrapper.                             ✅ Complete
   swift:4
  ──────────────────  ────────────────────────────────────────────────────────  ─────────────
   ProductAnnotatio    Map matching-product annotation wrapper.                  ✅ Complete
   n.swift:4

  There is no ShoppingPlanViewModel. Plan generation lives directly in ShoppingWorkspaceView,
  while shared plan state lives in AppStateManager.

  ## Services and data providers

   File                Responsibility                                         Status
  ━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━
   ShoppingListServ    Adds/removes Products from Shopping and creates        🟡 Partial
   ice.swift:141       legacy ShoppingItem adapters.
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   ShoppingTripServ    Calculates per-intent-group store coverage and         🟡 Partial
   ice.swift:25        sorts store/group candidates.
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   ShoppingSessionS    Starts, queries, updates, and finishes persistent      🟡 Partial
   ervice.swift:14     sessions.
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   StoreSearchServi    Unified saved-store plus live MapKit discovery,        ✅ Complete
   ce.swift:30         caching, merge, and deduplication.
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   StoreRankingServ    Heuristic Store Reality Score using category,          🟡 Partial
   ice.swift:90        distance, coverage, saved-store, and item-hint
                       signals.
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   BuyingOptionsSer    Converts resolved stores into ranked buying            🟡 Partial
   vice.swift:55       options.
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   WayTask/            Current coordinate, continuous location updates,       🟡 Partial
   LocationManager.    nearby detection, and shopping geofences.
   swift:6
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   GeofenceNotifica    Geofence payloads and nearby shopping                  ✅ Complete
   tionService.swif    notifications.
   t:164
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   StoreDataProvide    Generic store-provider abstraction. Not the current    ⚪ Placeholder
   r.swift:4           MapKit planner path.
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   LocalStoreDataPr    Generates synthetic “Nearby Market” and category       ⚪ Placeholder
   ovider.swift:4      sample stores.
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   DebugSeedStoreSe    Optional DEBUG-only seeded store.                      ⚪ Placeholder
   rvice.swift:5
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   ShoppingMemorySe    Records product-add history; it does not currently     ✅ Complete
   rvice.swift:12      optimize the plan.
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   ProductHistory.s    Persistent shopping-memory statistics.                 ✅ Complete
   wift:4

  ## Dormant shopping-intelligence foundation

   File                Responsibility                                         Status
  ━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━
   ShoppingContext.    Generic context representation used by recognition/    ⚪ Placeholder
   swift:67            discovery logic, not the current Shopping Planner.
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   ShoppingMission.    Generic shopping mission enumeration.                  ⚪ Placeholder
   swift:3
  ──────────────────  ─────────────────────────────────────────────────────  ────────────────
   DecisionEngine.s    Basic context-response engine, not used by Shopping    ⚪ Placeholder
   wift:36             Plan generation.

  ## Repositories

  ❌ Missing as a distinct layer.

  There are no Shopping or Store repository types. Views and services access SwiftData
  through @Query and ModelContext; live stores come through StoreResolutionEngine and MapKit.

  ———

  # Part 3 — Start Shopping Button

  ## Where it is

  Two buttons exist in ShoppingWorkspaceView:

  - Persistent bottom action bar: WayTask/ShoppingWorkspaceView.swift:463
  - Shopping Plan sheet: WayTask/ShoppingWorkspaceView.swift:528

  Home has another Start Shopping path in WayTask/HomeView.swift:719.

  ## Method chain

  Start Shopping button
      → handleBottomPrimaryAction()
      → startShopping()
      → ShoppingSessionService.startShopping(...)
      → insert ShoppingSession
      → save ModelContext
      → return session
      → returned session discarded

  The central action is WayTask/ShoppingWorkspaceView.swift:1080.

  ## Is an action connected?

  Yes. It is not an empty closure or placeholder.

  ShoppingSessionService:

  - Finishes any existing active session.
  - Copies active item IDs.
  - Inserts a new ShoppingSession.
  - Saves it to SwiftData.

  See ShoppingSessionService.swift:16.

  ## Is it disabled?

  It is disabled unless all of these are true:

  - A shopping list is selected.
  - There are active items.
  - Plan state is ready.
  - The ready plan still matches the active item IDs.
  - At least one recommended store row exists.

  The gate is at WayTask/ShoppingWorkspaceView.swift:646. The shared button applies
  SwiftUI .disabled at WayTaskDesignSystem.swift:223.

  ## Why it appears not to work

  After successful persistence, startShopping() ends. It does not:

  - Change tab.
  - Open Map.
  - Select a store.
  - Present Shopping Mode.
  - Show a success state.
  - Show a “Resume Shopping” state.
  - Store the selected plan/store in the session.

  Errors are sent only to assertionFailure, so a Release persistence failure would also lack
  user-facing feedback.

  The action is therefore not intentionally a no-op, but its visible handoff is missing.

  Repeated taps can silently finish the previous active session and create another one
  because the service always closes existing active sessions before starting a new one.

  ———

  # Part 4 — Shopping Plan

  ## Generation sequence

  generateShoppingPlan() in WayTask/ShoppingWorkspaceView.swift:912 performs:

  1. Validate selected list and active items.
  2. Convert selected ShoppingListEntry records to compatibility ShoppingItem records.
  3. Resolve product intents and groups.
  4. Resolve saved and nearby MapKit stores.
  5. Calculate ranked buying options.
  6. Calculate store coverage.
  7. Store a runtime ShoppingPlan in AppStateManager.

  ## Is optimization performed?

  🟡 Partial optimization exists:

  - Items are grouped by grocery, electronics, pet, pharmacy, or other.
  - Stores are filtered for category eligibility.
  - Stores receive a heuristic score.
  - Candidates are sorted by score, with distance as a tie-breaker.
  - Coverage is calculated per store and intent group.

  This is store recommendation optimization, not shopping-route optimization.

  ## Is order calculated?

  - Store suggestion display order: yes, by score and then distance.
  - Multi-store visit order: no.
  - Starting-store order: no.
  - Aisle/product collection order: no.
  - Route or waypoint order: no.
  - Shopping items retain their stored sortOrder; this is not optimized.

  ## Demo data?

  The current Shopping Planner normally uses:

  - Persistent user shopping data.
  - Persistent user-created/saved stores.
  - Live MapKit store discovery.

  Synthetic .local and .debugSeed results are filtered from Shopping’s displayed buying
  options. The shared resolver also suppresses synthetic local stores from discovered
  results.

  The mock infrastructure still exists in the project but is not the normal TestFlight
  Shopping Plan source.

  ## Business logic

  Substantial business logic is implemented, particularly in:

  - ShoppingIntentMatcher
  - StoreResolutionEngine
  - ShoppingTripService
  - StoreRankingService
  - BuyingOptionsService

  However, retailer inventory is not queried. “Matched products” and coverage are likelihood
  estimates based largely on product/store categories, text rules, saved item hints, and
  hardcoded scoring weights.

  ## ShoppingPlanViewModel

  ❌ Missing.

  ShoppingWorkspaceView performs generation directly, and AppStateManager owns the shared
  runtime state.

  ———

  # Part 5 — Store Selection

  ## Store sources

  The displayed plan stores come from:

  1. SwiftData GeoLocation records created/saved by the user.
  2. Live MKLocalSearch results around the current coordinate.
  3. A merge/deduplication step in StoreResolutionEngine.

  MapKit search is implemented at StoreSearchService.swift:541.

  There is no remote WayTask store repository and no live retailer inventory repository.

  ## Can the user choose a store before Start Shopping?

  No.

  Evidence:

  - Recommended store cards only open the Shopping Plan sheet.
  - Plan sheet rows are plain HStack content with no selection action.
  - ShoppingPlan contains [MapStore] but no selectedStoreID.
  - ShoppingSession contains only item IDs and collected item IDs.
  - startShopping() does not receive or resolve a store.

  Map has a separate selectedStoreID in MapViewModel, and users can select Map pins. That
  selection stays inside Map state and is not connected back to the Shopping Plan or session.

  Trip Map mode automatically selects the first/best coverage result at WayTask/
  MainMapView.swift:542, but this is an automatic display choice, not the user’s committed
  starting store.

  ———

  # Part 6 — Navigation

  ## What currently happens after Start Shopping

  Only a session is persisted. Nothing navigates.

  ## What the app supports separately

   Capability                        Status         Details
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Show plan stores on Map           ✅ Complete    View Map calls showTripOnMap, switches
                                                    tabs, and applies the shared plan.
  ────────────────────────────────  ─────────────  ──────────────────────────────────────────
   Choose a Map store                ✅ Complete    User can tap store/product annotations.
  ────────────────────────────────  ─────────────  ──────────────────────────────────────────
   External directions               ✅ Complete    “Navigate” opens Apple Maps with walking
                                                    directions.
  ────────────────────────────────  ─────────────  ──────────────────────────────────────────
   In-app route generation           ❌ Missing     No MKDirections, MKRoute, polyline, ETA,
                                                    or waypoint calculation exists.
  ────────────────────────────────  ─────────────  ──────────────────────────────────────────
   Start Shopping → Map              ❌ Missing     startShopping() never calls the Map
                                                    handoff.
  ────────────────────────────────  ─────────────  ──────────────────────────────────────────
   Map/navigation → Shopping Mode    ❌ Missing     No return or continuation handoff
                                                    exists.
  ────────────────────────────────  ─────────────  ──────────────────────────────────────────
   Shopping Session UI               🟡 Partial     UI code exists but is not mounted.
  ────────────────────────────────  ─────────────  ──────────────────────────────────────────
   Session location tracking         ❌ Missing     Current coordinates are not recorded
                                                    against a session.
  ────────────────────────────────  ─────────────  ──────────────────────────────────────────
   Geofence tracking                 ✅ Complete    Independent nearby-store notification
                                                    feature; not a session route tracker.

  External navigation is launched at MapViewModel.swift:527.

  ———

  # Part 7 — Data Sources

   Displayed value                  Classification           Actual source
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Shopping list name               Real                     SwiftData ShoppingList.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Products and product names       Real                     SwiftData Product/
                                                             ShoppingListEntry, adapted
                                                             through ShoppingItem.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Quantity and checked state       Real                     SwiftData ShoppingListEntry.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Store name                       Real                     MapKit result or user-created
                                                             GeoLocation; DEBUG seed
                                                             possible only in debug builds.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Store coordinate                 Real                     MapKit or user-entered/current
                                                             coordinate.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Distance                         Real                     Straight-line Core Location
                                                             distance; not road or walking
                                                             distance.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Products “matched” to a store    Hardcoded/derived        Product/store category
                                                             eligibility and text
                                                             heuristics; not actual
                                                             inventory.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Coverage percentage              Hardcoded/derived        Matched heuristic item count
                                                             divided by intent-group item
                                                             count.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Confidence label                 Hardcoded/derived        Local scoring thresholds such
                                                             as High confidence/Good match/
                                                             Possible match.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Store display order              Hardcoded/derived        Local ranking weights, then
                                                             distance tie-breaker.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Open status                      Placeholder/Hardcoded    MapKit stores use unavailable
                                                             status; saved stores are
                                                             constructed as open.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Rating                           Placeholder              MapKit planner stores do not
                                                             receive a rating; synthetic
                                                             providers contain fake ratings
                                                             but are filtered from normal
                                                             Shopping display.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Estimated shopping time          ❌ Missing               Not calculated or displayed.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Route/waypoints                  ❌ Missing               No source or model.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Route ETA                        ❌ Missing               No source or calculation.
  ───────────────────────────────  ───────────────────────  ─────────────────────────────────
   Shopping session progress        Real                     SwiftData
                                                             ShoppingSession.collectedItemID
                                                             s, but current UI has no
                                                             reachable controls to change
                                                             it.

  The most important distinction is that stores themselves are generally real, while “this
  store covers these products” is an estimate, not verified inventory.

  ———

  # Part 8 — Implementation Status

   Component           Classification
  ━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━
   Shopping Screen     🟡 Partial
  ──────────────────  ────────────────
   Shopping Plan       🟡 Partial
  ──────────────────  ────────────────
   Store Selection     ❌ Missing
  ──────────────────  ────────────────
   Start Shopping      🟡 Partial
  ──────────────────  ────────────────
   Shopping Session    🟡 Partial
  ──────────────────  ────────────────
   Navigation          🟡 Partial
  ──────────────────  ────────────────
   Shopping Route      ❌ Missing

  ———

  # Part 9 — Gap Analysis

  ## Critical

  - Present an actual Shopping Mode or other visible destination after session creation.
  - Add explicit store selection to the Shopping Plan.
  - Carry the chosen store and plan context into Start Shopping.
  - Define and implement the intended sequence: session creation → navigation → active
    Shopping Mode.

  - Expose reachable collect/uncollect and Finish Shopping actions.
  - Show user-facing persistence/navigation errors instead of assertion-only handling.
  - Prevent silent replacement of an active session on repeated taps.

  ## High Priority

  - Associate sessions with the selected shopping list, plan, and store; the current session
    stores only item IDs.

  - Add resume/recovery behavior for an existing active session after tab changes or app
    relaunch.

  - Synchronize session collection with ShoppingListEntry.isChecked; the current session
    service updates only session ID arrays.

  - Decide whether navigation should launch before the session starts or whether the session
    starts and resumes when returning from Apple Maps.

  - Add focused tests for eligibility gates, store selection, repeated taps, session
    persistence, finishing, and relaunch recovery.

  - Migrate the reachable Shopping Mode away from the obsolete Products-tab ownership
    assumption.

  ## Medium Priority

  - Persist sufficient plan context if a session must survive process termination.
  - Add clear selected-store visual state and accessibility state.
  - Add ETA/route distance only if Beta 1.0.1 promises them.
  - Clarify UI wording that product availability and coverage are estimates.
  - Handle plan staleness while a session is active.

  ## Future Improvements

  - Multi-stop store planning and route optimization.
  - Live retailer inventory.
  - Quantity-aware coverage.
  - In-app route rendering or turn-by-turn navigation.
  - Indoor/aisle navigation.
  - Session-linked location history, subject to privacy requirements.
  - Found Here/Not Found Here learning and personalized store ranking.

  ———

  # Part 10 — Final Assessment

  ## 1. Is WT-001 actually a bug?

  Yes, as a user-visible functional issue.

  It is not a missing tap handler: the handler creates a session. The bug is that the
  successful action has no visible continuation and does not enter the expected flow.

  ## 2. Is it an unfinished feature?

  Yes. The root cause is an unfinished Shopping Mode integration.

  The codebase itself records this explicitly: active Shopping Mode was removed from
  ownership of the Products tab, but its migration into Shopping was deferred in
  docs/60_CHANGELOG.md:1290.

  Older documentation still claims an end-to-end Planner → Map → Shopping Mode flow in
  docs/100_SHOPPING_TRIPS.md:61, so there is also documentation drift.

  ## 3. Should the backlog item be renamed?

  Yes.

  Suggested name:

  > Complete Start Shopping handoff: store selection → navigation → Shopping Mode

  This is more accurate than “Start Shopping button does not work,” because the button wiring
  and session persistence already exist.

  ## 4. Required work before Beta 1.0.1

  At minimum, if Beta 1.0.1 promises a usable Shopping Flow:

  1. Add a committed selected store.
  2. Connect Start Shopping to that store and the active plan/list.
  3. Create or resume a session without silently replacing it.
  4. Navigate to the store, using external Apple Maps if that remains the intended Beta
     scope.

  5. Mount Shopping Mode under the Shopping journey.
  6. Make collect/uncollect and Finish Shopping reachable.
  7. Add user-visible success/error/resume states.
  8. Verify the complete flow through relaunch and return from Apple Maps.

  In-app route optimization is not necessary for a minimal Beta fix if external Apple Maps is
  accepted.

  ## 5. Implementation complexity

  Large

  The work crosses Shopping UI, shared state, session persistence, Map handoff, store
  selection, lifecycle recovery, and testing.

  If Beta 1.0.1 also requires multi-stop optimization, route drawing, ETA, or session-linked
  location tracking, the scope becomes Very Large.

─ Worked for 8m 56s ─────────────────────────────────────────────────────────────────────────

 
› Use /skills to list available skills
 
  gpt-5.6-sol xhigh · ~/Desktop/IOS Build/WayTask

