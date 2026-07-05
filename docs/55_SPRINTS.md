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

- Added grocery recommendation eligibility with a practical 5 km distance cap.
- Buying Options now calculates initial and refreshed distance from the current user location.
- Ranking now gives stronger priority to nearby stores and only boosts saved/custom stores when they are nearby.
- Grocery filtering now rejects irrelevant business names and generic unrelated retail while allowing relevant grocery, supermarket, convenience, market, bakery, coffee, and pharmacy matches when appropriate.
- MapKit search results are filtered by practical distance before deduping and display.
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
