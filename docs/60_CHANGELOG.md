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
