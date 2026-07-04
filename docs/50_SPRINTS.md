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
