# Version 0.4

**Date:** July 1, 2026

**Status:** Completed

## Sprint

Sprint 4 – Discover Foundation

## Added

- Discover tab
- DiscoverView
- DiscoverViewModel
- DiscoverItem model
- ShoppingContext integration
- DecisionEngine integration

## Improved

- Discover architecture
- Context-based recommendation foundation

## User Value Added

Users can now discover relevant nearby shopping opportunities through a dedicated Discover experience, laying the foundation for future personalized recommendations.

## Notes

Discover currently uses local/context-based sample data.

Real data providers and AI recommendations will be added in future sprints.

# Version 0.5

**Date:** July 2026

**Status:** Completed

## Sprint

Sprint 5 – Product Recognition Foundation

## Added

- ProductCandidate model
- RecognitionResult model
- Recognition pipeline
- Camera confirmation flow
- ShoppingContext bridge

## Improved

- Camera architecture
- Recognition workflow
- Future AI integration

## User Value Added

WayTask is now capable of processing captured products through a structured recognition pipeline, preparing the foundation for reliable AI-powered product recognition in future releases.

## Notes

Recognition currently returns unavailable until a real provider is connected.

The application never generates fake product recognition results.

# Version 0.6

**Date:** July 2026

**Status:** Completed

## Sprint

Sprint 6 – Data Providers Foundation

## Added

- DataProvider protocol
- StoreDataProvider protocol
- ProductDataProvider protocol
- LocalStoreDataProvider
- DataSourceType model

## Improved

- Provider architecture
- Data source abstraction

## User Value Added

WayTask is now prepared to integrate multiple real-world data providers without changing the core application architecture.

## Notes

Current providers remain local only.

Future integrations include Apple Maps, Open Food Facts, retail APIs, and AI providers.

# Version 0.7

**Date:** July 2026

**Status:** Completed

## Sprint

Sprint 7 – Barcode Recognition Foundation

## Added

- Native barcode recognition
- BarcodeResult model
- Barcode confirmation flow
- Recognition pipeline integration

## Improved

- Camera workflow
- Product recognition architecture

## User Value Added

Users can now scan real product barcodes, creating the foundation for future product lookup and shopping recommendations.

## Notes

Barcode recognition is independent from AI and external databases.

No products are added automatically.

Future releases will connect barcode recognition to real product databases.

# Version 0.8

**Date:** July 2026

**Status:** Completed

## Sprint

Sprint 8 – First Real Product Provider

## Added

- Open Food Facts provider
- Real barcode lookup
- Product image support
- Brand information
- Category information
- Real ProductCandidate generation

## Improved

- Camera recognition workflow
- Product provider architecture
- Recognition pipeline

## User Value Added

Users can now scan a real product barcode and retrieve accurate product information, including the product name, brand, category, and image before deciding whether to continue.

## Notes

Open Food Facts is the first production product provider.

Future releases will add additional providers, retail APIs, and price comparison services.

# Version 1.0 Beta

**Date:** July 2026

**Status:** Beta

## Sprint

Sprint 10 – Smart Store Suggestions

## Added

- Shopping Intent Matcher
- Store category matching
- Product-to-store recommendations
- Shopping List integration
- Map suggestion workflow

## Improved

- Product shopping flow
- Map intelligence
- Store recommendation architecture

## User Value Added

Users can now scan a product, add it to their shopping list, and immediately receive suggestions for nearby stores that are likely to sell it.

## Notes

Current recommendations are category-based.

Future versions will add live inventory, price comparison, and AI-assisted recommendations.

# Version 1.2 Beta

**Date:** July 2026

**Status:** Completed

## Sprint

Sprint 12 – Store Ranking Foundation

## Added

- StoreRankingService
- StoreScore model
- Best Match badge
- Recommendation reasons
- Confidence labels

## Improved

- Buying Options UI
- Store recommendation clarity
- Ranking architecture

## User Value Added

Users can now see why WayTask recommends a buying option, including category match, nearby availability, and confidence reasons.

## Notes

Ranking is rule-based and independent from AI.

Future versions may include price, availability, opening hours, user preferences, and AI-assisted ranking.

# Version 1.3 Beta

## Added

- ProductHistory
- ShoppingMemoryService
- Persistent shopping history
- Product tracking

## User Value Added

WayTask now remembers shopping history and prepares future shopping habit features.

## Notes

No user-facing interface yet.

# Version 1.5

## Added

- ShoppingTripService
- StoreCoverage
- Shopping Trip Planner
- Shopping Trip card
- Trip Map Mode
- Trip coverage calculation
- Coverage-based store ranking

## Improved

- Buying Options experience
- Map experience
- Store recommendation flow
- Shopping trip planning

## User Value Added

Users can now receive recommendations based on their entire shopping list instead of evaluating products one by one.

WayTask highlights the best nearby store for the current shopping trip and displays shopping coverage before navigation.

## Notes

Trip planning currently uses local store data and heuristic coverage estimation.

Future versions will support real retailer inventories, multi-stop trips, route optimization, and AI-assisted planning.

# Version 1.6 Beta

## Sprint

Sprint 16 – Shopping Mode

## Added

- ShoppingSession model
- ShoppingSessionService
- Shopping Mode
- Shopping progress tracking
- Session persistence
- Start / Finish Shopping

## Improved

- Shopping experience
- In-store workflow
- Session architecture

## User Value Added

WayTask now assists users during shopping by tracking collected items, remaining items, and overall shopping progress.

## Notes

Shopping sessions are persisted using SwiftData.

Future versions will include shopping history, indoor navigation, smart reminders, and AI shopping assistance.

# Version 1.7 Beta

## Sprint

Sprint 21B – Products-first Experience

## Improved

- Products screen hierarchy
- Daily shopping-list workflow
- Manual Add Product presentation
- Primary action access while scrolling

## Changed

- The shopping list now starts immediately below search and filters.
- Add Product, Scan Product, and Start Shopping are available from a compact bottom action bar instead of large cards above the list.
- The manual Add Product form now opens in a dedicated sheet while preserving the existing fields and add behavior.

## Preserved

- My Lists header and statistics
- Search and filters
- Product cards and product actions
- Shopping Mode and Shopping Trip flows
- Barcode scanning, Gemini AI, notifications, map navigation, and custom stores

## User Value Added

WayTask now treats the shopping list as the primary Products screen content, reducing visual clutter and unnecessary scrolling for short, medium, and long lists.

## Notes

This sprint is UX polish only. No new features were added.

# Version 1.8 Beta

## Sprint

Sprint 21C – Missed Nearby Alerts

## Added

- In-app nearby shopping opportunity state
- "Nearby now" Products card
- Bell red-dot indicator for undisclosed nearby opportunities
- Nearby opportunities sheet from the Products bell
- Short in-app dismissal cooldown for nearby cards
- Product Knowledge Engine
- Local AI Learning
- Barcode local recognition
- Products-first Experience
- Bottom Action Bar
- Better Product UX

## Improved

- App foreground behavior now checks current location, active shopping items, saved stores, and MapKit/fallback nearby stores.
- Nearby opportunities can appear inside WayTask without waiting for iOS geofence re-entry.
- Gemini fallback
- Product images
- MapKit filtering
- Store ranking
- Product persistence

## Preserved

- Existing push notification behavior
- Existing notification cooldown
- Existing geofence monitoring
- Shopping Mode, Shopping Trip, Map, barcode scanning, Gemini AI, custom stores, product cards, and product actions

## User Value Added

WayTask now gives users a second chance to act on relevant nearby shopping opportunities after opening or returning to the app.

## Notes

This sprint adds an in-app reminder surface only. Push notification spam prevention remains handled by the existing notification cooldown.

# Version 1.9 Beta

## Sprint

Sprint 22 – Product Knowledge Engine

## Added

- `ProductKnowledge` local SwiftData model
- `ProductKnowledgeService`
- Local barcode-first Product Knowledge lookup
- Product learning after successful shopping-list add
- Product Knowledge updates from final confirmed product values

## Improved

- Repeated barcode scans can return a learned product before calling Open Food Facts or Gemini.
- Confirmed product identity is now stored separately from shopping history.
- Product Knowledge records keep barcode, display name, brand, category, type, flavor, package size, thumbnail data, search keywords, confidence, source, learned date, last-used date, and usage count.

## Preserved

- ProductHistory
- ShoppingMemoryService
- Open Food Facts lookup
- Gemini fallback
- Barcode scanning and review flow
- Manual add and recognized-product add behavior

## User Value Added

WayTask now starts building long-term local product intelligence from products the user has confirmed, while keeping all existing scan and add flows intact.

## Notes

Product Knowledge is local only. The model is intentionally separate from ProductHistory and is structured so a future sprint can add cloud synchronization without changing the current scan flow.

# Version 1.10 Beta

**Date:** July 5, 2026

**Status:** Completed

## Sprint

Sprint 23 – Beta Polish (Day 1)

## Added

- Refresh action for suggested buying places.
- Product-row image replacement entry point.
- Lightweight haptic feedback for barcode detection, AI recognition completion, and successful product add.
- DEBUG-only Debug Store setting for the debug seed store.

## Improved

- Scan opens directly in Barcode mode.
- Products is now the single visible entry point for scanning.
- Suggested places refresh now reruns MapKit search and reranks current recommendations.
- Store merging continues to deduplicate nearby markers and options.
- Product images now prefer official image data or official image URLs before AI fallback photos.
- Grocery store filtering rejects jewelry, florists, law offices, insurance, and banks.
- Debug Seed Store can only influence results in DEBUG builds when Debug Store is enabled.

## Preserved

- Product Knowledge architecture
- Gemini integration
- Shopping memory
- Open Food Facts lookup
- Saved-store and MapKit recommendation flow

## User Value Added

WayTask is more predictable for beta testing: scanning starts in the expected mode, recommendations can be refreshed, irrelevant grocery matches are reduced, and product images can be corrected later without a photo editor.

## Notes

Build completed successfully after implementation and review. No P1/P2 issues were found in the review pass.

# Version 1.10.1 Beta

**Date:** July 5, 2026

**Status:** Completed

## Sprint

Sprint 23.1 – Store Ranking + Product Image Stability

## Fixed

- Far or unrelated stores could appear before nearby valid stores in Buying Options and Map suggestions.
- Grocery recommendations could still include unrelated businesses such as jewelry, florists, law offices, offices, banks, and unrelated retail.
- Saved/debug/custom stores could rank too strongly when they were not nearby.
- Product thumbnails could flicker from placeholder to image and back.
- Remote product images loaded in the UI were not persisted locally.

## Improved

- Buying Options and Map suggestions now use current user location for distance-sensitive ranking.
- Grocery suggestions use a practical 5 km distance cap.
- Nearby stores receive stronger ranking priority.
- Saved/custom store boost applies only when the store is nearby.
- Grocery filtering now uses relevant store categories and business-name allow/reject rules.
- Store eligibility is shared across Buying Options, Map suggestions, nearby opportunities, and geofence candidates.
- Product thumbnails retain successfully loaded remote image data and keep a stable placeholder on failure.
- Remote product images are cached into `ShoppingItem` and Product Knowledge when loaded successfully.

## Preserved

- Gemini integration
- Product Knowledge architecture
- Existing scan flow
- Existing saved-store model

## User Value Added

Store recommendations should now feel local and relevant during beta testing, and scanned product images should remain stable in the Products list.

## Notes

Build completed successfully after review and P2 cleanup.

# Version 1.10.2 Beta

**Date:** July 5, 2026

**Status:** Completed

## Sprint

Sprint 23.2 – Store Source Audit

## Added

- DEBUG-only store source audit logs for MapKit query/category, raw result count, accepted and rejected result counts, store name, source type, distance, category, rejection reason, and fallback usage.
- Buying Options audit logs showing initial versus MapKit-refreshed store sources and whether local fallback was used.

## Improved

- Grocery, supermarket, and convenience MapKit searches now accept nearby Apple Maps results without requiring English grocery words in the business name.
- Grocery filtering still rejects explicit irrelevant business categories and names including jewelry, florists, legal offices, insurance, banks, offices, real estate, and beauty/salon terms.
- Buying Options no longer shows local/demo fallback stores before MapKit refresh completes when current location is available.
- Local/demo fallback is only surfaced after MapKit returns zero usable stores.

## Preserved

- Saved/custom stores
- Product Knowledge architecture
- Gemini integration
- Existing UI design

## User Value Added

Beta testing can now distinguish real MapKit results from saved/debug/fallback stores, while nearby grocery suggestions should be less likely to disappear because a business name is not in English.

## Notes

Build completed successfully after focused P1/P2 review. One P2 false-rejection risk in explicit term matching was fixed before the final build.
