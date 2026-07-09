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
- Grocery suggestions use distance-sensitive ranking. Sprint 25A later removed the hard 5 km grocery cutoff.
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

# Version 1.11 Beta

**Date:** July 5, 2026

**Status:** Completed

## Sprint

Sprint 24 - Store Reality Score

## Added

- Store Reality Score as a signal-based local likelihood engine for store recommendations.
- Store reality signal metadata for category relevance, item hints, known store type, distance, list coverage, saved stores, and future provider signals.
- Local feedback-ready `StoreRealityFeedback` structure for future found/not-found learning.
- Store coverage metadata for exact list coverage reasons such as `Covers 3/5 items`.

## Improved

- Buying Options and Map suggestions now rank through the same Store Reality Score.
- Map display ordering and automatic selected-store choice now use Reality Score.
- Nearby recommendations now carry and sort by Reality Score before distance.
- Category relevance is stricter for grocery, pharmacy, pet, and electronics requests.
- Pet food can rank large grocery/supermarket stores as lower-confidence fallback matches.
- Grocery MapKit filtering rejects non-grocery results that are not allowed by category or business name.
- Saved/custom stores receive a boost only when nearby and relevant.
- Store recommendation wording now uses safer labels such as `Suggested store`, `Likely available`, `High confidence`, `Good match`, `Possible match`, and `May have this item`.

## Preserved

- No paid external inventory APIs.
- No Gemini changes.
- No Product Knowledge architecture changes.
- No user feedback UI or cloud sync.

## User Value Added

Store recommendations should feel closer to real-world product availability while remaining honest that WayTask is ranking likelihood, not guaranteed inventory.

## Notes

Build completed successfully after implementation. Focused P1/P2 review fixed mixed-category reason generation and nearby saved-store relevance consistency before the final build.

# Version 1.11.1 Beta

**Date:** July 6, 2026

**Status:** Completed

## Sprint

Sprint 24.1 – Product Knowledge Refresh

## Improved

- Product Knowledge now refreshes existing records conservatively when better confirmed product data is learned later.
- Product name, display name, brand, category, product type, flavor, package size, thumbnail data, image URL, confidence, source, and keywords can improve over time.
- Empty incoming values no longer overwrite stored Product Knowledge fields.
- Lower-priority sources no longer overwrite higher-priority stored identity fields.
- Product Knowledge refresh priority is user-confirmed/manual values, then Gemini, then Open Food Facts barcode data, then existing stored values.
- Missing thumbnails can still be filled by later product image learning.

## Preserved

- Product Knowledge architecture.
- Barcode, date learned, usage count, last-used timestamp, and learning history.
- Shopping History and ShoppingMemoryService.
- Gemini behavior.
- Camera UI and scan flow.

## User Value Added

Products learned before later recognition improvements can become more accurate after a better confirmed product is added, instead of returning older barcode identity forever.

## Notes

Build completed successfully after implementation. Focused P1/P2 review fixed one merge-risk so shorter but legitimate brand/category/type/flavor/package-size improvements are not blocked by the descriptive-name safety check.

# Version 1.11.2 Beta

**Date:** July 6, 2026

**Status:** Completed

## Sprint

Sprint 24.2 – Better AI Recognition Guidance

## Improved

- Gemini low-confidence and unusable recognition results now produce clearer user guidance instead of generic failure copy.
- Guidance covers common capture issues including product too small, multiple products, blurry images, and package outside the guide frame.
- AI loading copy now says `Analyzing product...`.
- Manual fallback remains available when AI is unavailable, low confidence, or cannot produce a usable product.
- AI success now uses a subtle haptic only when a confident product suggestion is ready for review.

## Guidance Messages

- `Move closer to one product.`
- `Fill the frame with a single package.`
- `Center the package inside the guide frame.`
- `Try a clearer front photo.`
- `Retake the photo with one package filling the frame.`

## Preserved

- No Gemini API changes.
- No Product Knowledge changes.
- No barcode logic changes.
- No Camera UI redesign.

## User Value Added

Users get a clear next action when AI cannot confidently recognize the product, instead of being stranded by generic failure text.

## Notes

Build completed successfully after implementation. Focused P1/P2 review fixed one manual-fallback edge case so low-confidence Gemini candidates are treated as unavailable for UI fallback purposes.

# Version 1.11.3 Beta

**Date:** July 7, 2026

**Status:** Completed

## Sprint

Sprint 24.3 – Smart AI Enrichment

## Added

- `Improve with AI` action for weak barcode, Open Food Facts, and Product Knowledge results.
- Weak-data detection for short or generic names and missing brand, category, product type, flavor, or package size.
- Explicit clear front package photo step before Gemini enrichment starts.

## Improved

- Barcode enrichment now calls Gemini only after the user chooses `Improve with AI`.
- Improved AI suggestions preserve barcode metadata and can be accepted or edited before saving.
- Product Knowledge updates existing barcode records through the normal confirmed-product learning path when an improved result is accepted.
- Gemini failure keeps the original barcode result available and leaves manual entry available.

## Preserved

- Barcode detection.
- Gemini API key handling.
- Store Reality Score.
- Existing Scan screen layout.
- Existing Product Knowledge barcode keys, usage history, dates, and learning history.
- Existing product images when Gemini fails.

## User Value Added

Users can repair weak barcode database results without losing the original scan result or silently spending AI calls.

## Notes

Build completed successfully before and after focused P1/P2 review. One P2 interaction risk was fixed so existing candidate accept/edit actions are disabled while AI enrichment is actively analyzing.

# Version 1.11.4 Beta

**Date:** July 7, 2026

**Status:** Completed

## Sprint

Sprint 24.4 – Store Grouping Logic

## Added

- Shopping intent grouping for grocery/supermarket, electronics, pet store, pharmacy/health, and other/unknown.
- Group-specific Buying Options and Shopping Trip coverage.
- Group-aware map matching item labels and nearby opportunity item names.

## Improved

- Store recommendations now group mixed shopping lists before scoring with Store Reality Score.
- Grocery stores no longer claim electronics coverage.
- Electronics stores no longer claim grocery coverage.
- Shopping Trip coverage now prefers realistic grouped stops, such as one grocery stop plus one electronics stop.
- Map store cards and product annotations now show only relevant matching items for the store group.

## Preserved

- Store Reality Score remains the scoring engine.
- Product Knowledge was not changed.
- Gemini was not changed.
- The overall UI layout was not redesigned.

## User Value Added

Mixed shopping lists should produce realistic store suggestions instead of making one broad store appear to cover unrelated product categories.

## Notes

Build completed successfully before and after focused P1/P2 review. One P1 overclaim risk was fixed so generic/unknown stores no longer inherit every active item from provider tagging, and map product annotations now follow the narrowed store item list.

# Version 1.11.5 Beta

**Date:** July 7, 2026

**Status:** Completed

## Sprint

Sprint 24.6 – Product Intent Resolver

## Added

- `ProductIntentResolver` for normalized product intent before store scoring.
- `ProductIntentProfile` with normalized category, intent group, confidence, evidence, primary/secondary/fallback allowed store types, and excluded store types.
- Product intent support for baking soda, vinegar, coffee, milk, protein drink, cat food, dog food, USB-C charger, iPhone cable, medicine, bleach, and cleaning products.
- DEBUG logs for product intent resolution and store eligibility accept/reject decisions.

## Improved

- Store eligibility now runs before Store Reality Score.
- Store Reality Score only scores eligible store/product matches.
- Cat food and dog food can match pet stores first and grocery/supermarket stores as secondary matches.
- Cleaning products can match grocery/supermarket stores first and pharmacy/home-improvement stores as secondary matches.
- Buying Options can show no suitable store for unresolved products instead of surfacing generic store suggestions.
- Map matching, trip coverage, nearby opportunities, and geofence candidates now use resolved intent eligibility.

## Changed

- Unknown/Other intent no longer falls back to broad general-store discovery.
- Empty allowed-store categories with active shopping items return no discovered stores.
- Saved/custom item history can still make an unknown product eligible when the saved store directly contains that item.

## Preserved

- Product Knowledge schema.
- Gemini behavior and API key handling.
- Store Reality Score as the scoring engine.
- Existing UI layout.

## User Value Added

WayTask should stop recommending unrelated door stores, electronics stores, and random businesses for grocery-like products that previously fell into Other/general store.

## Notes

Build completed successfully before and after focused P1/P2 review. The review removed a stale general-store trip-matching fallback and confirmed unresolved intent no longer broadens store discovery.

# Version 1.12.0 Beta

**Date:** July 7, 2026

**Status:** Completed

## Sprint

Sprint 25 – Group-first Store Discovery

## Improved

- Store discovery now runs per shopping intent group before results are merged.
- Product List suggestions no longer merge all active item categories into one pre-discovery request.
- Map suggested-place discovery now searches each group separately.
- Nearby recommendations now search each group separately instead of flattening categories first.
- Geofence fallback discovery now uses grouped requests.
- Store results are merged after discovery, then retagged to show only relevant matching items.

## Preserved

- Product Knowledge schema.
- Product Intent model.
- Store Reality Score scoring behavior.
- Existing UI layout.

## User Value Added

Mixed lists should discover realistic stores per group, such as grocery stores for grocery items, pet stores for pet food, and electronics stores for chargers, before ranking and display.

## Notes

Build completed successfully before and after focused review. One P1 fallback issue was fixed so Apple Maps or saved results for one group do not remove local fallback stores for unrelated groups.

# Version 1.12.1 Beta

**Date:** July 7, 2026

**Status:** Completed

## Sprint

Sprint 25A – Discovery Pipeline Verification

## Improved

- DEBUG builds now log the actual runtime discovery pipeline from Suggest Places, Buying Options, Shopping Trip, Nearby opportunities, map suggested discovery, and geofence fallback discovery.
- Discovery logs include `ShoppingIntentGroups created`, group item names, StoreSearch request count, requested categories, and grouped-versus-merged discovery status.
- Removed hard grocery distance rejection; distance now reduces Store Reality Score instead of making a store ineligible by itself.
- Explicit unrelated-store rejection remains for jewelry, lawyers, florists, banks, insurance, offices, and similar impossible business types.

## Notes

Build completed successfully before and after focused review. The review removed stale distance-cap helper code and kept Store Reality Score as the place where distance affects ranking.

# Version 1.13.0 Beta

**Date:** July 8, 2026

**Status:** Completed

## Sprint

Sprint 26A – Design System Foundation

## Added

- Version 1.0 design tokens for color, typography, spacing, corner radius, elevation, glass effects, animation, and haptics.
- Reusable SwiftUI components for primary and secondary buttons, glass cards, store cards, product cards, shopping list cards, coverage rings, progress rings, badges, search, empty states, loading skeletons, offline states, bottom sheets, section headers, floating scan, and navigation.
- Version 1.0 navigation shell with Home, Products, Shopping, Map, and Settings tabs.
- Foundation placeholders for Home, Shopping, and Settings.

## Preserved

- Product Knowledge behavior.
- Gemini behavior.
- Store Reality Score.
- Store aggregation and MapKit discovery.
- Shopping Planner and Shopping Session logic.
- Existing SwiftData models.

## Notes

Build completed successfully after implementation and after focused review. This sprint prepares UI architecture only and does not migrate Products, Shopping, Store Details, Shopping Mode, Map, or Settings screens to the approved Version 1.0 UI.

# Version 1.13.1 Beta

**Date:** July 8, 2026

**Status:** Completed

## Sprint

Sprint 26B – Home v1.0

## Added

- Approved Version 1.0 Home dashboard.
- Shopping Today card with coverage ring, best-store summary, trip progress, and Start Shopping.
- Shopping Lists, Best Shopping Plan, Nearby Opportunity, Recent Products, and monthly stats sections.
- Home Quick Scan entry using the existing scanner.
- Reusable compact product card and metric card components in the design system.

## Reused

- Existing `ShoppingItem` data for active item count, recent products, and monthly item stats.
- Existing `ShoppingSessionService` for Start Shopping.
- Existing `CameraView` for Quick Scan.
- Existing `AppStateManager` trip coverage, buying options, and nearby opportunity state.

## Preserved

- Product Knowledge behavior.
- Gemini behavior.
- Store Reality Score.
- Store aggregation and MapKit discovery.
- SwiftData model schema.
- Existing Products and Map screens.

## Notes

Build completed successfully after implementation and focused review. Placeholder Home-only data remains where Version 1.0 backing models are not available yet.

# Version 1.14.0 Beta

**Date:** July 8, 2026

**Status:** Completed

## Sprint

Sprint 27A – Shopping Workspace

## Added

- Version 1.0 Shopping Workspace as the Shopping tab content.
- Shopping List selector, Shopping Summary, Recommended Stores, Coverage Cards, Grouped Products, Plan bottom sheet, and Start Shopping action.
- Presentation-only grouped product rows for empty-state prototype coverage.

## Reused

- Existing `ShoppingItem` data.
- Existing `ShoppingSession` and `ShoppingSessionService`.
- Existing `AppStateManager.shoppingTripCoverages` and `AppStateManager.buyingOptions`.
- Existing `ShoppingIntentMatcher`.
- Existing design-system components.

## Preserved

- Product Knowledge.
- Gemini.
- Barcode.
- Store Reality Score.
- Store aggregation and MapKit discovery.
- Product Intent Resolver.
- ShoppingTripService and BuyingOptionsService.
- SwiftData model schema.

## Notes

Build completed successfully after implementation and focused review. The Shopping Workspace is presentation-only; real v1.0 Shopping List and Shopping Plan model migration remains future work.

# Version 1.14.1 Beta

**Date:** July 9, 2026

**Status:** Completed

## Sprint

Sprint 27A.1 – Remove Demo Data From Home & Shopping

## Changed

- Home no longer falls back to prototype stores, coverage percentages, distances, fake duration, fake open status, sample nearby opportunity, or sample recent products.
- Shopping no longer falls back to prototype recommended stores, coverage cards, or sample grouped products.
- Empty planner states now show `Plan not ready yet` instead of invented stores.
- Shopping can route to the existing trip-map planner entry point with Generate plan when active shopping items exist.
- Removed the small Home header scan button; the orange floating scan button remains the scanner entry point and opens `CameraView`.

## Reused

- Existing `ShoppingItem` data.
- Existing `ShoppingSession` and `ShoppingSessionService`.
- Existing `AppStateManager.shoppingTripCoverages`.
- Existing `AppStateManager.visibleNearbyOpportunity`.
- Existing displayable real `BuyingOption` rows.
- Existing `ShoppingIntentMatcher` grouped list behavior.

## Preserved

- Product Knowledge.
- Gemini.
- Barcode.
- Store Reality Score.
- Store aggregation and MapKit discovery.
- ShoppingItem models.

## Notes

Product Intelligence validation remains needed in a later sprint, including health/pharmacy classification review. Real v1.0 Shopping List and Shopping Plan model migration remains future work.
