# Data Sources

WayTask currently uses local, in-app data providers only. No external store, product, price, online shopping, or AI provider is connected yet.

## Current Sources

### Local Store Data

`LocalStoreDataProvider` returns nearby fallback stores around the user's current map region. This keeps the Map and Discover foundations usable while real store data sources are added later.

Current local store data is sample fallback data and should not be treated as verified retail inventory, pricing, opening hours, or availability.

### User-Generated Data

User-created shopping items, saved places, images, and geofence-backed locations come from the app's local SwiftData models and app state.

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
