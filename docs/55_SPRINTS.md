# Sprint 4 – Discover Foundation

## Goal

Create the first Discover experience using ShoppingContext without AI.

## User Value

Help users discover relevant nearby shopping opportunities before searching manually.

## Completed

- DiscoverView
- DiscoverViewModel
- DiscoverItem
- Discover tab
- ShoppingContext integration
- Map navigation support

## Out of Scope

- AI recommendations
- Price comparison
- Online shopping
- Indoor mall navigation

## Result

Build completed successfully.

Status: ✅ Completed

# Sprint 5 – Product Recognition Foundation

## Goal

Build a production-ready recognition pipeline without introducing AI recognition.

## User Value

Prepare the camera flow for reliable product recognition while keeping the user experience clean and trustworthy.

## Completed

- ProductCandidate model
- RecognitionResult model
- Recognition pipeline
- Confirmation flow
- ShoppingContext bridge

## Out of Scope

- AI recognition
- Barcode recognition
- OCR
- Product database

## Result

Build completed successfully.

Status: ✅ Completed

# Sprint 6 – Data Providers Foundation

## Goal

Create a flexible provider architecture that allows WayTask to integrate multiple data sources without changing business logic.

## User Value

Prepare WayTask for real-world product, store, and shopping information while keeping the application independent from any specific provider.

## Completed

- DataProvider protocol
- StoreDataProvider protocol
- ProductDataProvider protocol
- LocalStoreDataProvider
- DataSourceType model
- Data source documentation

## Out of Scope

- Real APIs
- AI
- Product lookup

## Result

Build completed successfully.

Status: ✅ Completed

# Sprint 7 – Barcode Recognition Foundation

## Goal

Introduce real barcode recognition while preserving the existing camera workflow.

## User Value

Users can scan product barcodes and prepare products for future recognition and shopping intelligence.

## Completed

- Barcode recognition
- BarcodeResult model
- Barcode confirmation
- Recognition pipeline integration
- ShoppingContext barcode support

## Out of Scope

- Product lookup
- AI
- Barcode database

## Result

Build completed successfully.

Status: ✅ Completed

# Sprint 8 – First Real Product Provider

## Goal

Connect WayTask to its first real-world product database.

## User Value

Users can scan a real product barcode and retrieve accurate product information before adding it to their shopping experience.

## Completed

- Open Food Facts provider
- Barcode lookup
- Real ProductCandidate population
- Product image loading
- Brand support
- Category support
- Review flow

## Out of Scope

- AI
- Price comparison
- Retail APIs
- Shopping list integration

## Result

Build completed successfully.

Status: ✅ Completed

# Sprint 10 – Smart Store Suggestions

## Goal

Help users find nearby stores that are likely to sell products from their shopping list.

## User Value

After adding a product, users can instantly discover nearby stores where the product is likely available.

## Completed

- Shopping Intent Matcher
- Store category matching
- Suggest Places integration
- Product-to-store flow
- Map integration

## Out of Scope

- Live inventory
- Price comparison
- AI recommendations

## Result

Build completed successfully.

Status: ✅ Completed

# Sprint 12 – Store Ranking Foundation

## Goal

Rank buying options and explain why a store is recommended.

## User Value

Users can understand why WayTask recommends one buying option over another.

## Completed

- StoreRankingService
- StoreScore model
- Best Match badge
- Recommendation reasons
- Confidence labels
- Buying Options ranking integration
- Badge UI polish

## Out of Scope

- AI ranking
- Real prices
- Live inventory
- Paid APIs

## Result

Build completed successfully.

Status: ✅ Completed

# Sprint 13 – Shopping Memory Foundation

## Goal

Persist shopping history and prepare future shopping habit analysis.

## Completed

- ProductHistory
- ShoppingMemoryService
- Shopping history persistence
- Product add tracking
- Frequently added queries

## Out of Scope

- User interface
- Notifications
- AI

Status: ✅ Completed

### Sprint 15 – Shopping Trip Planner Foundation ✅

**Goal**
Create the foundation for planning an entire shopping trip instead of recommending stores for individual products.

**Completed**
- StoreCoverage model
- ShoppingTripService
- Coverage calculation
- Coverage-based ranking
- Integration with StoreRankingService
- AI-independent architecture

**User Value**
WayTask can now evaluate stores based on how many shopping-list items they are likely to satisfy.

**Status**
Completed

### Sprint 15.1 – Shopping Trip UI ✅

**Goal**
Expose Shopping Trip planning to users.

**Completed**
- Shopping Trip card
- Coverage summary
- Matched items
- Missing items
- Trip recommendation reasons
- View Trip on Map action

**Status**
Completed

### Sprint 15.2 – Trip Map Mode ✅

**Goal**
Differentiate trip planning from standard product navigation.

**Completed**
- Trip map mode
- Best trip store selection
- Trip context banner
- Trip bottom sheet
- Coverage indicator on map
- Dedicated View Trip on Map flow

**Status**
Completed

## Sprint 16 – Shopping Mode

### Goal

Introduce an in-store shopping mode that guides users through their shopping list while they are actively shopping.

### User Value

Users can start a shopping session, track their progress, mark items as collected, and complete the session.

### Completed

- ShoppingSession SwiftData model
- ShoppingSessionService
- Start Shopping
- Active Shopping Mode
- Progress indicator
- Collected / Remaining counter
- Checklist interaction
- Finish Shopping action

### Out of Scope

- AI assistance
- Indoor navigation
- Route optimization
- Permanent purchase history

### Result

Build completed successfully.

**Status:** ✅ Completed

## Sprint 21B – Products-first Experience

### Goal

Make the Products screen shopping-list first without adding new functionality or changing WayTask's visual identity.

### User Value

Users opening WayTask can see their products immediately, while Add Product, Scan Product, and Start Shopping remain reachable during everyday list management.

### Completed

- Moved the product list directly below search and filters.
- Replaced large pre-list action cards with a compact bottom action bar.
- Moved the manual Add Product form into a dedicated sheet.
- Preserved existing product cards, product actions, scanning, shopping mode, shopping trip, map navigation, and notification-driven flows.

### Out of Scope

- New shopping features
- Product card redesign
- Visual identity changes
- Architecture changes

### Result

Build completed successfully.

**Status:** ✅ Completed

## Sprint 21C – Missed Nearby Alerts

### Goal

Surface nearby shopping opportunities inside the app when the user may have missed, ignored, or not received a nearby push notification.

### User Value

Users returning to WayTask can immediately see that a relevant nearby store may match their active shopping list, without waiting for another iOS geofence entry event.

### Completed

- Added in-app nearby opportunity state.
- Refresh nearby opportunities on app launch, foreground return, shopping-list changes, saved-store changes, and location bucket changes.
- Check active shopping items against nearby saved stores and MapKit/fallback stores.
- Added a compact "Nearby now" Products card.
- Added short in-app dismissal cooldown for the nearby card.
- Added a red dot to the Products bell when an undisclosed nearby opportunity exists.
- Added a bell sheet listing current nearby opportunities.
- Preserved existing push notification scheduling and cooldown behavior.

### Out of Scope

- Push notification redesign
- New notification categories
- Background polling
- Live inventory or price validation

### Result

Build completed successfully.

**Status:** ✅ Completed

## Sprint 22 – Product Knowledge Engine

### Goal

Create a local Product Knowledge Engine that remembers confirmed product identity separately from shopping history.

### User Value

WayTask can recognize products it has already learned from the user, making repeated barcode scans faster and reducing unnecessary external lookup or AI work.

### Completed

- Added a separate `ProductKnowledge` SwiftData model for reusable product identity.
- Added `ProductKnowledgeService` for barcode lookup, learning, and updates.
- Barcode confirmation now checks local ProductKnowledge before Open Food Facts or Gemini.
- Confirmed products are learned after they are successfully added to the shopping list.
- Final confirmed values update ProductKnowledge and are treated as authoritative.
- Preserved `ProductHistory` and the existing shopping memory flow.

### Out of Scope

- Cloud sync
- Product Knowledge UI
- Bulk import/export
- Changes to ProductHistory
- Changes to external provider behavior

### Result

Build completed successfully.

**Status:** ✅ Completed

## Sprint 23 – Beta Polish (Day 1)

### Goal

Prepare WayTask for a real-world testing session with focused polish and real-usage fixes.

### User Value

Users can start barcode scanning faster, refresh nearby store recommendations, avoid irrelevant grocery store suggestions, and recover from imperfect product images without changing Product Knowledge or Gemini architecture.

### Completed

- Scan now opens in Barcode mode by default.
- Removed the duplicate Camera tab shortcut; Products remains the clear scan entry point.
- Added refresh for Buying Options suggested places, including MapKit refresh, reranking, and deduplicated merged stores.
- Improved product image priority so official product image URLs are preserved before AI fallback photos.
- Added a lightweight product image replacement path from product rows.
- Strengthened grocery recommendation filtering against jewelry, florists, law offices, insurance, and banks.
- Gated Debug Seed Store behavior behind DEBUG builds and an explicit Debug Store setting.
- Added subtle haptics for barcode detection, AI recognition completion, and successful product add.

### Preserved

- Product Knowledge architecture
- Gemini integration
- Existing shopping history and memory flows
- Existing saved-store and MapKit merge behavior

### Result

Build completed successfully.

**Review:** No P1/P2 issues found after the review pass.

**Status:** ✅ Completed

## Sprint 23.1 – Store Ranking + Product Image Stability

### Goal

Fix real-world beta testing issues found in Map suggestions and product image loading.

### User Value

WayTask now keeps grocery recommendations local and relevant, prevents debug/custom stores from dominating unrelated suggestions, and keeps product images stable after scan and remote image loading.

### Completed

- Added grocery recommendation eligibility. Sprint 25A later changed distance from a hard grocery cutoff into a ranking signal.
- Buying Options now calculates initial and refreshed distance from the current user location.
- Ranking now gives stronger priority to nearby stores and only boosts saved/custom stores when they are nearby.
- Grocery filtering now rejects irrelevant business names and generic unrelated retail while allowing relevant grocery, supermarket, convenience, market, bakery, coffee, and pharmacy matches when appropriate.
- MapKit search results were originally filtered by practical distance before deduping and display. Sprint 25A later removed this hard distance rejection.
- Map, Buying Options, nearby opportunities, and geofence candidates now share the same store eligibility rules.
- Stabilized product thumbnails so loaded remote images are not replaced by nil placeholders.
- Persisted successfully loaded remote product images into `ShoppingItem` and refreshed Product Knowledge from the saved item.
- Preserved AI/Gemini and Product Knowledge architecture.

### Result

Build completed successfully.

**Review:** Fixed one P2 mixed-category filtering risk before the final build.

**Status:** ✅ Completed

## Sprint 23.2 – Store Source Audit

### Goal

Confirm when WayTask uses MapKit versus saved/debug/fallback store sources, then apply the smallest safe fix for beta store suggestions.

### User Value

Buying Options should wait for real Apple Maps results when current location is available, avoid showing demo stores prematurely, and provide DEBUG audit logs that explain store acceptance, rejection, distance, category, source, and fallback behavior.

### Completed

- Added DEBUG-only store audit logging for MapKit query/category, raw result count, accepted/rejected count, store name, source type, distance, category, rejection reason, and fallback usage.
- Softened grocery MapKit acceptance for grocery, supermarket, and convenience searches so nearby Apple Maps results are accepted without requiring English grocery words in the business name.
- Kept explicit grocery rejection for irrelevant categories and names such as jewelry, florists, legal, insurance, banks, offices, real estate, and beauty/salon terms.
- Prevented Buying Options from showing local/demo fallback stores before MapKit refresh finishes when current location exists.
- Preserved saved/custom stores, Product Knowledge, Gemini, and existing UI design.

### Result

Build completed successfully.

**Review:** Fixed one P2 false-rejection risk in explicit term matching before the final build.

**Status:** ✅ Completed

## Sprint 24 - Store Reality Score

### Goal

Improve store recommendations so they rank stores by real-world likelihood instead of implying certain inventory.

### User Value

Users should see nearby, relevant, category-appropriate stores first, with clear reasons for why each store is suggested and without claims of guaranteed availability.

### Completed

- Added Store Reality Score as the source of truth for local store likelihood.
- Refactored Store Reality Score into independent scoring signals for category relevance, item hints, known store type, distance, list coverage, saved stores, and future provider inputs.
- Added stricter category matching for grocery, supermarket, convenience, pharmacy, pet, electronics, and related title signals.
- Added lower-confidence large grocery/supermarket fallback matching for pet food.
- Added store type confidence reasons such as known grocery, pharmacy, pet, and electronics stores.
- Kept saved/custom store boost conditional on nearby and relevant signals.
- Routed Buying Options ranking through Store Reality Score.
- Routed Map suggestion ordering and automatic selected-store choice through Store Reality Score.
- Routed nearby recommendation ordering through Store Reality Score.
- Added exact shopping-list coverage scoring and reasons such as `Covers 3/5 items`.
- Tightened grocery MapKit rejection so non-allowed grocery results are filtered before display.
- Updated recommendation wording to safer labels including `Suggested store`, `Likely available`, `High confidence`, `Good match`, `Possible match`, and `May have this item`.
- Prepared a local `StoreRealityFeedback` structure for future found/not-found signals.

### Out of Scope

- Paid external inventory APIs
- Gemini changes
- Product Knowledge architecture changes
- User feedback UI
- Cloud sync
- Guaranteed inventory claims

### Result

Build completed successfully.

**Review:** Fixed mixed-category reason generation and nearby saved-store relevance consistency before the final build.

**Status:** ✅ Completed

## Sprint 24.1 – Product Knowledge Refresh

### Goal

Improve local Product Knowledge so older learned product identities can be refreshed when a better confirmed product is later available.

### User Value

Products learned before later Gemini improvements can now become more accurate over time instead of returning the older identity forever.

### Completed

- Updated Product Knowledge refresh behavior without changing the Product Knowledge model or lookup architecture.
- Existing records now merge confirmed product data instead of blindly replacing every field.
- Product name, display name, brand, category, product type, flavor, package size, thumbnail data, image URL, confidence, source, and keywords can refresh when incoming data is equal-or-higher priority.
- Empty incoming fields no longer overwrite stored values.
- Lower-priority sources no longer overwrite existing higher-priority identity fields.
- Existing thumbnail data is replaced only by equal-or-higher priority sources, while missing thumbnails can still be filled.
- Preserved barcode, date learned, times used, last used, and existing learning history.

### Refresh Priority

1. User-confirmed/manual values
2. Gemini
3. Open Food Facts barcode data
4. Existing stored values

### Out of Scope

- Product Knowledge architecture changes
- Product Knowledge deletion or rebuild
- Shopping History changes
- Gemini changes
- Camera UI changes

### Result

Build completed successfully.

**Review:** Fixed one P2 merge-risk so shorter but legitimate brand/category/type/flavor/package-size improvements are not blocked by the descriptive-name safety check.

**Status:** ✅ Completed

## Sprint 24.2 – Better AI Recognition Guidance

### Goal

Improve the user experience when Gemini cannot confidently recognize a product.

### User Value

Users now get practical capture guidance instead of a generic AI failure message, while manual fallback remains available.

### Completed

- Replaced generic Gemini failure copy with clearer capture guidance.
- Added guidance mapping for common capture issues: product too small, multiple products, blurry image, and package outside the guide frame.
- Updated AI loading copy to `Analyzing product...`.
- Kept the manual fallback path for low-confidence, unavailable, or unusable AI results.
- Added subtle haptic feedback only when AI returns a confident product suggestion.
- Preserved the existing screen layout.

### Guidance Messages

- `Move closer to one product.`
- `Fill the frame with a single package.`
- `Center the package inside the guide frame.`
- `Try a clearer front photo.`
- `Retake the photo with one package filling the frame.`

### Out of Scope

- Gemini API changes
- Product Knowledge changes
- Barcode logic changes
- Camera UI redesign

### Result

Build completed successfully.

**Review:** Fixed one P1/P2 manual-fallback edge case so low-confidence Gemini candidates are treated as unavailable for UI fallback purposes.

**Status:** ✅ Completed

## Sprint 24.3 – Smart AI Enrichment

### Goal

Allow users to improve weak Barcode, Open Food Facts, and Product Knowledge results with AI.

### User Value

Partial barcode results such as `Pro 20, Banana` can be improved into a fuller package identity after the user explicitly chooses AI enrichment and provides a front package photo.

### Completed

- Added weak product-data detection for short, partial, generic, or incomplete barcode product results.
- Added an `Improve with AI` action for weak Product Knowledge/Open Food Facts results and for barcode lookup failures.
- Kept Gemini opt-in for barcode enrichment. Barcode lookup does not auto-call Gemini.
- Added a clear front package photo prompt before AI enrichment starts.
- Preserved the original barcode result when Gemini fails or returns a low-confidence candidate.
- Preserved barcode metadata on improved AI candidates.
- Kept existing Product Knowledge image data or image URLs available when Gemini fails.
- Routed accepted improved results through the existing Product Knowledge learning/update path.
- Preserved Product Knowledge barcode keys, usage history, date learned, last used, and learning history.

### Weak-Data Rules

- Short or partial product name.
- Generic product name such as `Product`, `Drink`, `Snack`, or `Food`.
- Missing brand.
- Missing category.
- Missing product type.
- Missing flavor.
- Missing package size.

### Out of Scope

- Barcode detection changes
- Gemini API key handling changes
- Store Reality Score changes
- Scan screen redesign

### Result

Build completed successfully before and after focused review.

**Review:** Fixed one P2 interaction risk so existing candidate accept/edit actions are disabled while AI enrichment is actively analyzing.

**Status:** ✅ Completed

## Sprint 24.4 – Store Grouping Logic

### Goal

Stop treating a mixed shopping list as one store category when recommending stores.

### User Value

Mixed lists now produce more realistic recommendations: grocery stores cover grocery items, electronics stores cover electronics items, pet stores cover pet items, and pharmacies cover health items.

### Completed

- Added shopping intent groups for grocery/supermarket, electronics, pet store, pharmacy/health, and other/unknown.
- Grouped active shopping items before Buying Options, Shopping Trip coverage, map store matching, and nearby opportunities.
- Kept Store Reality Score as the scoring engine and moved grouping before scoring.
- Updated Buying Options to generate group-specific store options and coverage reasons.
- Updated Shopping Trip coverage to return group-specific store coverage instead of whole-list coverage.
- Updated map store item names and product annotations so stores show only relevant group items.
- Updated nearby opportunity item names so cards do not claim unrelated mixed-list coverage.

### Grouping Logic

- Electronics signals route items to electronics stores first.
- Pet signals route items to pet stores before grocery fallback.
- Pharmacy/health signals route items to pharmacies.
- Grocery, supermarket, and convenience signals route items to grocery/supermarket.
- Unknown or home-improvement style items route to other/unknown.

### Out of Scope

- UI redesign
- Product Knowledge changes
- Gemini changes
- Store Reality Score removal or replacement

### Result

Build completed successfully before and after focused review.

**Review:** Fixed one P1 overclaim risk so generic/unknown stores no longer inherit every active item from provider tagging, and fixed map product annotations to follow the narrowed store item list.

**Status:** ✅ Completed

## Sprint 24.6 – Product Intent Resolver

### Goal

Add a normalized Product Intent layer before Store Reality Score.

### User Value

Products now resolve to explicit shopping intent before store ranking. Unknown items no longer become broad general-store searches that can recommend unrelated businesses.

### Completed

- Added `ProductIntentResolver` and `ProductIntentProfile`.
- Added normalized categories, confidence, evidence, primary/secondary/fallback allowed store types, and excluded store types.
- Added explicit intent handling for baking soda, vinegar, coffee, milk, protein drink, cat food, dog food, USB-C charger, iPhone cable, medicine, bleach, and cleaning products.
- Changed unresolved/Other behavior so unknown products have no allowed discovered-store categories.
- Kept saved/custom item history eligible for unknown products when the saved store directly matches the item.
- Added product intent eligibility before Store Reality Score.
- Added DEBUG logs for resolved product intent and store eligibility accept/reject reasons.
- Updated Buying Options empty state for unresolved items.
- Updated Map, Buying Options, Shopping Trip, nearby opportunities, and geofence matching to use resolved intent eligibility.

### Intent Model

Each `ProductIntentProfile` includes:

- normalized category
- intent group
- confidence
- evidence/reasons
- primary allowed store types
- secondary allowed store types
- fallback store types
- excluded store types

### Out of Scope

- Product Knowledge schema changes
- Gemini changes
- UI redesign
- Store Reality Score removal or replacement

### Result

Build completed successfully after implementation.

**Review:** Focused P1/P2 review removed a stale general-store fallback from trip item matching and confirmed unresolved products no longer broaden MapKit/local discovery.

**Status:** ✅ Completed

## Sprint 25 – Group-first Store Discovery

### Goal

Use shopping groups before store discovery instead of merging all group categories into one request.

### User Value

Mixed shopping lists now search for realistic stores per intent group before results are merged. A grocery group searches grocery stores, a pet group searches pet stores, and an electronics group searches electronics stores.

### Completed

- Removed the full-list merged category request from Buying Options discovery.
- Added group-specific store discovery in Product List suggestions.
- Added group-specific store discovery in Map suggested places.
- Added group-specific store discovery for nearby recommendations.
- Updated geofence fallback discovery to use shopping groups.
- Merged discovered stores only after each group search completes.
- Kept local fallbacks per group unless an equivalent Apple Maps result exists for that group/category.
- Kept Product Knowledge unchanged.
- Kept Product Intent unchanged.
- Kept Store Reality Score unchanged.

### Old Discovery Flow

Shopping list items were grouped, but Product List and Map discovery flattened the groups into one category union before searching stores.

### New Discovery Flow

Shopping list items are grouped first. Each `ShoppingIntentGroupResult` runs its own `ShoppingStoreSuggestionRequest` through Store Search. Discovered stores are deduplicated and retagged after discovery.

### Result

Build completed successfully after implementation and after focused review.

**Review:** Fixed one P1 grouped fallback issue so a saved or Apple Maps result in one group no longer removes local fallback stores for unrelated groups.

**Status:** ✅ Completed

## Sprint 25A – Discovery Pipeline Verification

### Goal

Verify the actual runtime discovery pipeline before making more architecture changes.

### Completed

- Added DEBUG discovery logs at the runtime entry points for Suggest Places, Buying Options, Shopping Trip, Map suggested discovery, Nearby opportunities, and geofence fallback discovery.
- Logs now print the number of `ShoppingIntentGroups`, group names, items in each group, StoreSearch request count, requested categories, and grouped-versus-merged discovery status.
- `Grouped discovery active` prints when group-specific requests are running.
- `Legacy merged discovery path still active` prints when multiple groups collapse into one StoreSearch request.
- Removed hard grocery distance rejection from store eligibility and MapKit post-filtering.
- Kept explicit unrelated-store rejection for jewelry, lawyers, florists, banks, insurance, offices, and other clearly impossible business types.
- Kept distance as a Store Reality Score ranking signal.

### Result

Build completed successfully before and after focused review.

**Review:** Removed stale distance-cap helper code and updated docs so no active or documented path treats distance alone as a hard grocery rejection.

**Status:** ✅ Completed

## Sprint 26A – Design System Foundation

### Goal

Create the reusable Version 1.0 SwiftUI design-system foundation and prepare the new application shell.

### User Value

Future Version 1.0 screens can be implemented consistently without rewriting existing business logic or duplicating UI styling.

### Completed

- Added design tokens for colors, typography, spacing, corner radius, elevation, glass effects, animation, and haptics.
- Added reusable components:
  - Primary Button
  - Secondary Button
  - Glass Card
  - Store Card
  - Product Card
  - Shopping List Card
  - Coverage Ring
  - Progress Ring
  - Badge
  - Search Bar
  - Empty State
  - Loading Skeleton
  - Offline State
  - Bottom Sheet
  - Section Header
  - Floating Scan Button
  - Navigation Bar
- Prepared the Version 1.0 tab shell:
  - Home
  - Products
  - Shopping
  - Map
  - Settings
- Kept current Products and Map screens attached.
- Added placeholder foundation views for Home, Shopping, and Settings.

### Preserved

- Product Knowledge
- Product Intent Resolver
- Store Reality Score
- Store Aggregation
- Shopping Planner
- Gemini
- MapKit logic
- SwiftData models
- Existing Services and ViewModels

### Out of Scope

- Product model migration
- Shopping list model migration
- Home screen implementation
- Shopping screen implementation
- Settings screen migration
- Store Details redesign
- Shopping Mode redesign

### Result

Build completed successfully after implementation and after focused review.

**Review:** Focused review found no P1/P2 business-logic changes. The only follow-up was documentation alignment for the new foundation boundary.

**Status:** Completed

## Sprint 27B.1 – Introduce Product Library and Shopping Lists

### Goal

Introduce the Product Library and Shopping List architecture without removing the legacy `ShoppingItem` model or rewriting existing planner/product intelligence services.

### Completed

- Added persistent `Product`, `ShoppingList`, and `ShoppingListEntry` models.
- Registered the new models in the SwiftData container.
- Added default list support for `Weekly Shopping`, `Completed`, and `Recent`; only `Weekly Shopping` is active for planning in this sprint.
- Added safe backfill from existing `ShoppingItem` records into `Product` records and Weekly list entries.
- Kept `ShoppingItem` writes intact for scanner, barcode, Gemini, Product Knowledge, planner, Map, and Shopping Mode compatibility.
- Added app-state handles for current shopping list, selected shopping list, and current product library IDs.
- Updated Shopping to read selected/default Shopping List entries when available, with a legacy incomplete-`ShoppingItem` fallback.
- Prepared Products to act as the Product Library by syncing the current `Product` collection into app state.

### Compatibility Layer

`ShoppingListBackfillService` mirrors legacy `ShoppingItem` data into the new models. New scan/manual product inserts still create `ShoppingItem` first, then backfill creates/updates the matching `Product` and Weekly list entry.

Shopping uses `ShoppingListEntry.legacyShoppingItemID` to adapt entries back to real `ShoppingItem` instances for the existing planner and session services.

### Remaining `ShoppingItem` Dependencies

- Scanner and manual add still insert `ShoppingItem`.
- Product Knowledge and Shopping Memory still learn from `ShoppingItem`.
- Planner services still accept `[ShoppingItem]`.
- Home metrics and recent products still query `ShoppingItem`.
- Shopping sessions still store `ShoppingItem` IDs.
- Saved-store relationships still attach `ShoppingItem` records to `GeoLocation`.

### Preserved

- Product Knowledge
- Gemini
- Barcode
- ShoppingTripService
- BuyingOptionsService
- StoreSearchService
- StoreRankingService
- Store Reality Score
- Store Aggregation
- MapKit

### Notes

This sprint introduces the architecture only. It does not complete the UX migration from Products to Product Library, does not remove `ShoppingItem`, and does not persist Shopping Plan snapshots.

**Status:** Completed

## Sprint 27B.2 – Products to Shopping Workflow

### Goal

Connect the permanent Product Library to the temporary Shopping list without rewriting planner, scanner, barcode, Gemini, Product Knowledge, store, or MapKit services.

### Completed

- Products now render persistent `Product` records as the Product Library.
- Product cards show whether the product is already in the selected Shopping list.
- Added Product card actions for `Add to Shopping` and `Remove from Shopping`.
- Scanning, barcode lookup, and Gemini recognition now save/update `Product` records without automatically adding them to Shopping.
- Shopping now displays selected `ShoppingListEntry` records only; it no longer falls back to all incomplete `ShoppingItem` records.
- Shopping shows the selected list, item count, grouped items, and a `Generate Plan` action.
- Generate Plan refreshes the shared plan inside Shopping and does not navigate to Map.
- Product add/remove invalidates stale plans so Shopping does not display a plan for an old item set.

### Compatibility Layer

`ShoppingListEntry.legacyShoppingItemID` still points to a temporary `ShoppingItem` adapter because the current planner, Shopping Mode, Product Knowledge, Shopping Memory, saved-store links, and Home metrics still operate on `ShoppingItem`.

Removing a product from Shopping deletes the `ShoppingListEntry` and marks the adapter `ShoppingItem` completed so the legacy backfill does not recreate the entry. The `Product` remains in the permanent library.

### Preserved

- Product Knowledge
- Gemini
- Barcode
- ShoppingTripService
- BuyingOptionsService
- StoreSearchService
- StoreRankingService
- Store Reality Score
- Store Aggregation
- MapKit

### Notes

Next sprint should migrate planner/session inputs from the temporary `ShoppingItem` adapter to native `ShoppingListEntry`/`Product` data, then retire compatibility backfill behavior.

**Status:** Completed

## Sprint 27B.3 – Runtime Workflow Fix

### Goal

Make the Products to Shopping to Plan to Map workflow visible and usable on device after the model separation introduced in Sprint 27B.1 and the first workflow pass in Sprint 27B.2.

### Completed

- Removed the active `ShoppingSession` takeover from the Products tab so Products always displays the Product Library.
- Kept Product cards visible with `Add to Shopping`, `Remove from Shopping`, and `Already in Shopping` state.
- Added interactive Shopping row actions for checked/needed state, list removal, and quantity adjustment.
- Added a Shopping empty-state `Add products` action that opens Products.
- Kept Generate Plan inside Shopping and based on the selected list's needed entries.
- Added `View Map` only when a usable shared plan is ready.
- Updated Home visible list counts, product counts, and recent product cards to prefer `Product` and `ShoppingListEntry` data when available.
- Updated Map focus so ready plans fit relevant plan stores and user location, while no-plan map opens follow the user location when available.

### Preserved

- Product Knowledge
- Gemini
- Barcode
- ShoppingTripService
- BuyingOptionsService
- StoreSearchService
- Store Reality Score
- Store Aggregation
- MapKit search logic

### Compatibility Layer

`ShoppingListEntry.legacyShoppingItemID` and temporary `ShoppingItem` adapters remain in place for planner, Shopping Mode, saved-store links, Product Knowledge, and Shopping Memory compatibility.

Shopping Mode itself is still owned by existing `ShoppingSessionService` behavior. This sprint only prevents active sessions from hiding Products; it does not redesign or fully migrate Shopping Mode into the Shopping journey.

### Notes

Next sprint should migrate Shopping Mode and planner/session inputs to native Shopping List Entry and Product data, then reduce the temporary `ShoppingItem` adapter surface.

**Status:** Completed

## Sprint 26B – Home v1.0

### Goal

Replace the Home placeholder with the approved Version 1.0 Home dashboard using the Sprint 26A design system.

### Completed

- Added `HomeView` as the Home tab content.
- Added the approved dashboard structure:
  - Greeting/date header
  - Shopping Today card
  - Coverage ring
  - Best store summary
  - Start Shopping button
  - Shopping Lists section
  - Best Shopping Plan preview
  - Nearby Opportunity card
  - Recent Products section
  - Monthly stats section
  - Quick Scan entry point
- Reused existing scanner flow through `CameraView`.
- Reused existing shopping-session entry through `ShoppingSessionService`.
- Reused existing `AppStateManager` buying options, trip coverage, and nearby opportunity state where available.
- Added reusable compact product and metric cards to the design system.

### Real Data

- Active shopping item count comes from `ShoppingItem`.
- Start Shopping creates an existing `ShoppingSession` from current active items.
- Recent Products come from existing `ShoppingItem` records.
- Monthly trips come from completed `ShoppingSession` records.
- Monthly item count comes from `ShoppingItem.dateAdded`.
- Best plan preview uses `AppStateManager.shoppingTripCoverages` when available.
- Nearby opportunity uses `AppStateManager.visibleNearbyOpportunity` when available.

### Placeholder Data

- User display name remains a safe Home-only placeholder.
- Shopping-list cards are summaries over existing `ShoppingItem` state until the future `ShoppingList` model exists.
- Best plan preview falls back to approved prototype sample stores when no trip coverage has been generated.
- Nearby Opportunity falls back to the approved prototype sample when no real nearby opportunity exists.
- Recent Products fall back to approved prototype sample products when there are no saved products.

### Preserved

- Product Knowledge
- Gemini
- Store Reality Score
- Store Aggregation
- MapKit logic
- SwiftData models
- Existing Products and Map screens

### Result

Build completed successfully after implementation.

**Review:** Focused P1/P2 review confirmed the sprint is UI-only except for invoking the existing scanner and shopping-session service entry points.

**Status:** Completed

## Sprint 27A – Shopping Workspace

### Goal

Replace the Shopping placeholder with the approved Version 1.0 Shopping Workspace while preserving existing planner, store, session, and product-intent systems.

### Completed

- Added `ShoppingWorkspaceView` as the Shopping tab content.
- Added Shopping List selector chips.
- Added Shopping Summary with open item count, grouped intent count, collected count, and progress.
- Added Recommended Stores section.
- Added Coverage Cards section.
- Added Grouped Products section.
- Added Plan bottom sheet.
- Added Start Shopping action using the existing `ShoppingSessionService`.
- Reused existing `AppStateManager.shoppingTripCoverages`, `AppStateManager.buyingOptions`, and `ShoppingIntentMatcher` for presentation data.
- Replaced only the Shopping tab placeholder in `ContentView`.

### Real Data

- Active/open shopping items come from `ShoppingItem`.
- Session progress and collected count come from `ShoppingSession`.
- Store coverage comes from existing `StoreCoverage` state when available.
- Recommended store fallback can use existing `BuyingOption` state.
- Product grouping uses existing `ShoppingIntentMatcher`.
- Start Shopping uses existing `ShoppingSessionService`.

### Placeholder Data

- Shopping list selector remains a presentation summary over current `ShoppingItem` data until real v1.0 Shopping List models are migrated.
- Recommended store cards fall back to approved prototype sample stores when planner state is empty.
- Grouped product rows fall back to approved prototype sample products only when there are no active items.

### Preserved

- Product Knowledge
- Gemini
- Barcode
- Store Reality Score
- Store Aggregation
- Product Intent Resolver
- MapKit
- ShoppingTripService
- BuyingOptionsService
- ShoppingSession model
- SwiftData schema

### Result

Build completed successfully after implementation and after focused review.

**Review:** Fixed one P2 empty-state issue by using view-local product-row placeholders and disabling Map plan routing when no real plan/list state exists.

**Status:** Completed

## Sprint 27A.1 – Remove Demo Data From Home & Shopping

### Goal

Remove prototype store, plan, metric, nearby opportunity, and product fallback data from the Home and Shopping screens while preserving the existing visual implementation and business systems.

### Completed

- Removed Home fallback plan stores, prototype coverage percentages, prototype distances, fake duration, fake open-state label, sample nearby opportunity, and sample recent products.
- Removed the Home header scan button; the orange floating scan button remains wired to `CameraView`.
- Updated Home to show real `AppStateManager.shoppingTripCoverages` rows only, with `Plan not ready yet` empty states when planner data is unavailable.
- Updated Home Nearby Opportunity to render only `AppStateManager.visibleNearbyOpportunity`.
- Removed Shopping fallback recommended stores, coverage metrics, and grouped sample product rows.
- Updated Shopping Recommended Stores and Plan sheet to use real `StoreCoverage` and displayable real `BuyingOption` store rows only.
- Added a `Plan not ready yet` empty state with a Generate plan action that routes through the existing trip-map planner entry point when active shopping items exist.
- Kept grouped list behavior using `ShoppingIntentMatcher`, but no longer labels groups as prototype stores.

### Real Data

- Home item counts, recent products, monthly stats, and shopping sessions come from `ShoppingItem` and `ShoppingSession`.
- Home best plan and plan rows come from `AppStateManager.shoppingTripCoverages`.
- Home nearby opportunity comes from `AppStateManager.visibleNearbyOpportunity`.
- Shopping products come from real `ShoppingItem` records.
- Shopping plan rows come from `AppStateManager.shoppingTripCoverages`, or displayable non-local store `BuyingOption` rows when available.

### Preserved

- Product Knowledge
- Gemini
- Barcode
- Store Reality Score
- Store Aggregation
- ShoppingTripService
- BuyingOptionsService
- ShoppingItem models
- Existing product grouping behavior

### Notes

- Product Intelligence validation is still needed in a later sprint, including validation of health/pharmacy product classification such as Acamol.
- Real v1.0 Shopping List and Shopping Plan model migration remains future work.

**Status:** Completed

## Sprint 27A.2 – Shared Shopping Plan Integration

### Goal

Create one shared Shopping Plan in app state so Home, Shopping, and Map observe the same generated planner output.

### Completed

- Added a lightweight `ShoppingPlan` app-state value containing the planner request, active items, stores, buying options, trip coverage rows, and generation timestamp.
- Made `AppStateManager.shoppingPlan` the single shared planner state.
- Kept compatibility accessors for `storeSuggestionRequest`, `buyingOptions`, and `shoppingTripCoverages`, all derived from the shared plan.
- Updated Generate Plan to create or refresh the shared plan once, then hand that plan to Map.
- Updated Home, Shopping, and Products Start Shopping flows to refresh the shared plan before starting a shopping session.
- Updated Map to apply the shared plan's stores and items directly instead of generating a separate map-only plan.
- Updated Product suggestions and Map refreshes to write planner output through `AppStateManager.setShoppingPlan`.

### Reused

- `ShoppingTripService`
- `BuyingOptionsService`
- `ShoppingIntentMatcher`
- Existing saved-store `GeoLocation` data
- Existing `StoreCoverage`, `BuyingOption`, and `MapStore` presentation models

### State Flow

Generate Plan or Start Shopping creates/refreshes `AppStateManager.shoppingPlan`.

Home reads best store and plan rows from `shoppingPlan`.

Shopping reads recommended stores and coverage cards from `shoppingPlan`.

Map applies `shoppingPlan` and displays the same stores, coverage, and selected trip context.

### Preserved

- Product Knowledge
- Gemini
- Barcode
- Store Reality Score
- Store Aggregation
- ShoppingTripService implementation
- BuyingOptionsService implementation
- StoreSearchService implementation
- StoreRankingService implementation
- SwiftData models

### Notes

- ETA remains unavailable when the existing planner has no ETA output; Home shows the ETA slot without inventing a duration.
- Real v1.0 Shopping List and Shopping Plan persistence remains future work.

**Status:** Completed

## Sprint 27B.4 – Shopping UX, Plan States, and Runtime Clarity

### Goal

Complete the visible Products to Shopping to Plan to Map workflow without changing recommendation engines or persistence structure.

### Completed

- Added shared Shopping plan state in app state: `idle`, `generating`, `ready`, `failed`, and `stale`.
- Made Shopping generation explicit, in-place, and duplicate-tap safe.
- Added visible planning progress with elapsed time and high-level real stages:
  - Preparing your shopping list
  - Finding nearby stores
  - Matching products to stores
  - Calculating coverage
  - Ranking the best options
- Kept checked Shopping rows visible and visually distinct.
- Clarified the circular row control as needed/checked, not delete.
- Kept trash as Remove from Shopping, removing only the `ShoppingListEntry`.
- Kept quantity controls at minimum quantity 1.
- Marked shared Shopping plans stale after membership, checked-state, quantity, or removal changes.
- Updated Shopping bottom action by plan state:
  - Generate Plan
  - Planning
  - Start Shopping
  - Try Again
- Kept Generate Plan inside Shopping.
- Gated View Map behind a ready plan with usable stores.
- Gated Start Shopping behind selected list, needed entries, ready plan, and usable stores.
- Updated Home to observe shared plan state instead of generating its own plan.
- Preserved coverage display from shared `ShoppingPlan` and existing `ShoppingTripService` coverage rows.

### Reused

- `ShoppingTripService`
- `BuyingOptionsService`
- `ShoppingIntentMatcher`
- `ShoppingSessionService`
- Existing `ShoppingPlan`
- Existing `StoreCoverage`, `BuyingOption`, and `MapStore`
- Existing saved `GeoLocation` store data

### Preserved

- Product Knowledge
- Gemini
- Barcode and Open Food Facts
- Store Reality Score
- Store Aggregation
- Store Search
- Store Ranking
- MapKit discovery logic
- `Product`, `ShoppingList`, and `ShoppingListEntry` persistence structure
- Temporary `ShoppingItem` compatibility

### Deferred Roadmap Items

- Products category tiles
- Grocery first by default
- User-defined category ordering
- Drag-and-drop category reordering
- CloudKit backup and sync
- Offline action queue
- Persisted offline ShoppingPlan
- Found Here / Not Found Here learning
- WayTask-owned store and branch database
- Manual store submission
- Merchant portal
- Website importer
- Private backend migration

### Notes

Coverage remains based on the existing planner definition: matched eligible shopping entries divided by total eligible shopping entries in `ShoppingTripService` coverage rows. Quantities are preserved on `ShoppingListEntry`, but the current planner still counts entries until the native planner migration.

Shopping Mode remains on the legacy `ShoppingSession` path. It is gated by plan readiness, but a later sprint should move Shopping Mode fully under the Shopping journey and native `ShoppingListEntry` inputs.

**Status:** Completed

## Sprint 27B.4.1 – Initial Shopping List Selection

### Goal

Replace automatic legacy Product-to-Weekly-Shopping population with an explicit one-time user selection flow.

### Completed

- Removed automatic `ShoppingListEntry` creation from legacy backfill.
- Kept legacy backfill responsible for default lists and permanent `Product` records.
- Added one-time initial product selection sheet when Products exist, Weekly Shopping is empty, and the initial selection flag is incomplete.
- Added product image, name, brand/category, checkbox, Select All, Clear All, Add Selected to Shopping, and Skip for Now.
- Added `Choose products` entry point in Shopping that opens the same selection UI later.
- Added duplicate-safe selected-product insertion through existing `ShoppingListService.addProductToShopping`.
- Marked Shopping plans stale after selected products are added.
- Preserved existing Weekly entries and treated them as intentionally configured.

### Migration Guard

The guard uses:

- `waytask.initialShoppingSelectionCompleted.v1` in local app storage.
- Products must exist.
- Weekly Shopping must exist.
- Weekly Shopping must have zero entries.

If Weekly Shopping already has entries, the app marks the initial selection complete and does not remove, replace, or overwrite those entries.

### Reused

- `ShoppingListBackfillService` for Product/default-list backfill.
- `ShoppingListService.addProductToShopping` for entry creation.
- Existing `Product`, `ShoppingList`, `ShoppingListEntry`, and temporary `ShoppingItem` compatibility.

### Notes

Skip for Now marks the one-time initial selection complete so the sheet does not block every launch. The user can reopen the same flow from Shopping with `Choose products`.

**Status:** Completed

## Sprint 27B.4.2 – First Shopping Experience & Shopping Workflow Completion

### Goal

Make the Products to Shopping to Plan workflow understandable for new and legacy users without changing planner, recommendation, recognition, MapKit, or persistence engines.

### Completed

- Added lightweight one-time onboarding that explains Products as the permanent library, Shopping as the selected trip list, and Generate Plan as the store-finding action.
- Added one-time legacy review for users who already have Weekly Shopping entries from earlier migration behavior.
- Added legacy review choices: Keep Current Shopping List, Edit Shopping List, and Start Fresh.
- Kept Products safe during legacy review; `Start Fresh` clears only Weekly Shopping entries and marks linked compatibility `ShoppingItem` records completed.
- Promoted `Choose Products` to a primary Shopping action near the top of the screen.
- Updated the empty Shopping state to say no products are selected and show a large `Choose Products` action.
- Prevented the empty Shopping state from showing `Generate Plan`.
- Kept Shopping row behavior explicit: circular control toggles needed/checked, trash removes only from Shopping, and quantity changes invalidate stale plans.
- Updated Home generation messaging to display elapsed time from the shared planning state.

### Preserved

- Product Knowledge.
- Gemini.
- Barcode and Open Food Facts.
- Shopping planner services.
- ShoppingTripService.
- BuyingOptionsService.
- ShoppingIntentMatcher.
- StoreSearchService.
- StoreRankingService.
- Store Reality Score.
- Store Aggregation.
- MapKit discovery logic.
- Product persistence.
- ShoppingList persistence.
- Temporary ShoppingItem compatibility.

### Deferred

- Products category tiles.
- Drag-and-drop category ordering.
- Cloud Sync.
- Offline Queue.
- Found / Not Found learning.
- Product Learning.
- Store Database.
- Merchant Portal.
- Website Importer.
- Native ShoppingListEntry planner/session migration.
- Full Shopping Mode ownership migration.

**Status:** Completed
