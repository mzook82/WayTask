# Data Sources

WayTask currently uses local SwiftData, Open Food Facts, Gemini Vision, and Apple MapKit Local Search data sources. Price comparison, live inventory, online shopping APIs, and AI store ranking are not connected yet.

## Current Sources

### Local Store Data

`LocalStoreDataProvider` returns nearby fallback stores around the user's current map region. This keeps the Map and Discover foundations usable when Apple MapKit Local Search returns no results or is unavailable.

Current local store data is sample fallback data and should not be treated as verified retail inventory, pricing, opening hours, or availability.

### Apple MapKit Local Search

`MapKitStoreSearchService` uses Apple MapKit Local Search to discover real nearby stores for shopping suggestions and map display.

Supported search categories include:

- Grocery
- Supermarket
- Convenience Store
- Pharmacy
- Pet Store
- Electronics
- Home Improvement
- General stores

MapKit results are merged with user-saved stores. User-saved stores remain first and keep their user metadata. If MapKit and a saved store appear to represent the same physical place, WayTask prefers the saved store and avoids duplicate markers.

### User-Generated Data

User-created shopping items, saved places, images, and geofence-backed locations come from the app's local SwiftData models and app state.

### Local Product Knowledge

`ProductKnowledge` stores reusable product identity learned from confirmed products.

Barcode scanning checks local ProductKnowledge before external product providers. If a barcode has already been learned, WayTask can return the local product candidate without calling Open Food Facts or Gemini.

ProductKnowledge refreshes existing records conservatively when the same product is confirmed again. User-confirmed/manual values outrank Gemini, Gemini outranks Open Food Facts barcode data, and stored values are kept when incoming data is empty or lower priority.

Weak ProductKnowledge or Open Food Facts barcode results can be enriched with Gemini only after the user taps `Improve with AI` and provides a clear front package photo. Gemini enrichment preserves the barcode and updates the existing ProductKnowledge record through the normal confirmed-product learning path.

ProductKnowledge is separate from ProductHistory. ProductKnowledge stores identity; ProductHistory stores shopping usage memory.

### Product Recognition Data

`ProductRecognitionService` is a pipeline stub. It returns an unavailable recognition result with no product candidates until a real product recognition provider is implemented.

## Provider Types

`DataSourceType` defines the source categories WayTask is preparing for:

- `local`
- `appleMaps`
- `openStreetMap`
- `retailAPI`
- `publicDatabase`
- `aiProvider`
- `userGenerated`

## Planned Store Sources

Future `StoreDataProvider` implementations may include:

- Apple Maps for places, store metadata, directions, and map integration.
- OpenStreetMap for open local place data.
- Retail APIs for merchant-specific store and inventory data.
- Local fallback data for offline or development scenarios.

## Planned Product Sources

Future `ProductDataProvider` implementations may include:

- Open Food Facts for grocery product and barcode data.
- Barcode databases for packaged goods lookup.
- Retail catalogs for merchant-specific product availability.
- AI product recognition providers for camera and image-based recognition.

## Planned Shopping Intelligence

The provider foundation is designed to support later features without coupling UI screens to external APIs:

- AI recommendations.
- Price comparison.
- Online store suggestions.
- Indoor mall routing.
- Discover recommendations.
- Smart notifications.

## Current Policy

Until real providers are implemented, WayTask must not show local fallback data as verified availability, pricing, or AI-generated recommendations.

## Sprint 19.3 Store Data Limitation

Current map, buying option, shopping trip, and geofence behavior uses a combination of user-saved stores from SwiftData, Apple MapKit Local Search stores, and local fallback/demo stores. Saved user stores should be prioritized and shown before MapKit and fallback stores when relevant.

Fallback/demo stores should only appear when MapKit does not return usable nearby results. A future sprint should improve real-store metadata with richer Apple Maps details, hours, and provider-backed inventory where available.

## Open Food Facts

Status: Integrated

Purpose:

Provides real product information using barcode lookup.

Current Data:

- Product Name
- Brand
- Category
- Product Image

Future Expansion:

- Open Beauty Facts
- Open Pet Food Facts
- Retail APIs
