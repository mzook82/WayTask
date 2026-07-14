# Unified Store Resolution Engine

**Sprint:** 27B.5A  
**Date:** July 12, 2026  
**Status:** Implemented

## Scope

This sprint unifies runtime store resolution without adding a server, long-term store database, or persisted transient-store schema. Existing intent matching, MapKit search, ranking, buying options, trip coverage, SwiftData models, and Core Location monitoring remain in place.

## Shared Flow

```text
Saved GeoLocation stores
        │
        ├── persisted IDs and saved item associations
        │
        ▼
Grouped shopping intents
        │
        ▼
MapKit discovery (when a coordinate is available)
        │
        ▼
Stable identity materialization
        │
        ▼
Saved-priority merge and deduplication
        │
        ├── Planner -> Buying Options -> Coverage -> ShoppingPlan
        ├── Map suggestions and circles
        ├── Nearby opportunities
        ├── Notification navigation
        └── Geofence candidates
```

The planner fails for missing stores only after the discovery step completes. With no coordinate, saved stores remain usable. With no saved stores, usable MapKit stores can produce a plan.

## Runtime Identity

`RuntimeStore` is the canonical runtime representation. `MapStore` remains a compatibility alias to avoid redesigning current services.

- Persisted store: `id == GeoLocation.id`, `locationID == GeoLocation.id`.
- Transient MapKit/fallback store: deterministic ID from source type, normalized title, and latitude/longitude bucket.
- Notification-only transient store: materialized into Map state with the same identity algorithm when coordinate/title are available.

Deduplication prioritizes persisted stores, merges matching item/category evidence, and treats close same-name or sub-35-meter results as the same branch.

## Discovery And Cache

`StoreResolutionEngine.shared` owns one `MapKitStoreSearchService` instance.

- Search input is grouped by shopping intent.
- Category-specific queries execute through the existing grouped MapKit search implementation.
- Results are merged and deduplicated before any consumer uses them.
- Synthetic `LocalStoreDataProvider` demo stores are suppressed from runtime resolution.
- Cache key: coordinate bucket plus sorted shopping item/category intent.
- Cache lifetime: 120 seconds.
- Forced-refresh throttle: 1.5 seconds per cache key.
- Identical in-flight requests reuse one task.
- Consumer generation counters reject stale Product, Nearby, and Geofence results.

## Planner Contract

```text
Preparing list
-> Saved stores
-> Await MapKit discovery
-> Merge
-> Deduplicate
-> Buying options
-> Coverage
-> Ranking
-> ShoppingPlan
```

`ShoppingPlan.contentSignature` remains the publication guard. Location callbacks do not regenerate a plan.

## Notification Contract

Geofence notifications include these fields when available:

- `storeID`
- `geoLocationID`
- `storeTitle`
- `latitude` / `longitude`
- `sourceType` / `storeSourceType`
- `matchedShoppingItemIDs`
- `matchedItemNames`
- `shoppingListID`
- `notificationType`

The response creates `StoreNavigationContext`, switches to Map, focuses the coordinate, materializes a transient store when required, selects it, and exposes matched products in `MapBottomSheet`. Existing valid plans are preserved unless the payload switches to a different Shopping-list context. The navigation context is consumed after successful selection so later plan updates do not reopen stale notification state.

## Map And Geofence

Map performs cached nearby discovery with active shopping intent even when no plan exists. With no active items it uses a broad store-browsing category intent. This does not publish a plan. User-follow behavior and the 50-meter map refresh threshold remain in place.

Map proximity circles are rendered from resolved runtime stores. Geofence candidate creation uses the same resolved store objects and IDs. Existing limits remain 12 managed shopping regions and 20 total monitored regions; notification radii remain clamped to 150-250 meters.

## Known Limitations

- MapKit discovery depends on permission, connectivity, and regional Apple Maps data quality.
- Transient runtime stores are not persisted across a cold launch except through notification payload reconstruction.
- The notification payload carries up to three matched item IDs/names, matching current notification copy limits.
- Apple Maps does not provide authoritative per-product inventory; matches remain category/intent estimates.
- Core Location decides actual region delivery and may delay events.
- `ShoppingPlan` and native `ShoppingListEntry` planner/session inputs are not persisted/migrated by this sprint.

## Field-Test Checklist

1. Create a list whose products match one saved non-debug store; generate a plan and confirm the saved store, coverage, View Map, and Start Shopping.
2. Repeat with a matching saved store plus Apple Maps results; confirm saved-store priority and no duplicate branch pins/options.
3. Remove all saved stores; generate with location enabled and confirm a MapKit-only plan reaches Ready.
4. Disable location with no saved stores; confirm generation fails only after the saved-only resolution path and offers Enable Location.
5. Open Map with no plan; confirm nearby real stores and circles appear without changing plan state.
6. Pan/follow through several location callbacks; confirm the plan is not regenerated and searches are not repeated inside one coordinate/intent bucket.
7. Trigger a saved-store geofence notification; tap it and confirm Map focuses, selects the store, opens the bottom sheet, and shows only matched products.
8. Trigger a transient MapKit-store notification; tap it and confirm the store is materialized with the same pin/circle and matching products.
9. Tap a notification while a valid plan exists; confirm the plan remains available after inspecting the store.
10. Confirm monitored region logs use the same store ID/title/coordinate as the Map pin and circle.
11. Confirm no Debug Seed store appears unless its explicit debug flag is enabled.
12. Confirm no `Nearby Market`, `Local Pharmacy`, `Corner Grocery`, or category sample names appear as runtime results.
13. Run Shopping -> Generate Plan -> Coverage -> View Map -> Start Shopping and confirm no duplicate stores or stale bottom-sheet selection.

## Recommended Next Sprint

Sprint 27B.5B – Store Resolution Field Validation & Observability: execute the matrix above across saved-only, mixed, and MapKit-only regions; add deterministic unit coverage for identity/dedup/cache behavior; add notification/geofence integration diagnostics; and tune query acceptance using real field evidence before resuming native `ShoppingListEntry` planner/session migration.
