# WayTask Project Status

Current Version:
1.0

Current Milestone:
Milestone 3 – Products & Shopping Separation

Current Sprint:
Sprint 27B.5E – Post-Plan Performance Fix

Completed:

- Design Freeze
- Product Specification
- Engineering Blueprint
- Design System
- Home Foundation
- Home v1.0 real-data cleanup
- Shopping Workspace real-data cleanup
- Shared Shopping Plan integration
- Product Library and Shopping List model foundation
- Products-to-Shopping workflow
- Runtime Products to Shopping to Plan to Map workflow
- Shopping UX plan-state completion
- Explicit initial Shopping list selection
- First-shopping onboarding and legacy Shopping review
- Unified saved-store and MapKit resolution across Planner, Map, Nearby, Notifications, and Geofence
- Stable runtime identity for persisted and transient stores
- Notification-to-store Map deep links with matching products
- Hidden Beta Diagnostics Center with runtime decision telemetry
- In-memory Beta Snapshot with non-exported screen capture
- Privacy-reviewed Markdown and optional JSON diagnostics export
- Stable-signature Map annotation and overlay update guard
- Hidden-Map deferred ShoppingPlan application
- Batched Map display publication and plan-aware filter caching
- Throttled UI location publication with raw geofence accuracy preserved
- Stable Shopping/Home row identities and lazy Shopping presentation

Next Sprint:

Sprint 27B.5F – On-Device Post-Plan Performance Validation

Blockers:

None

Known Technical Debt:

ShoppingItem migration
ShoppingListEntry-to-planner native migration
Product Intelligence health/pharmacy classification validation
ShoppingPlan persistence
Offline action queue and persisted offline ShoppingPlan

Milestone 1

Foundation

✅ Complete

--------------------

Milestone 2

Planner Integration

✅ Complete

--------------------

Milestone 3

Products & Shopping Separation

In progress

Sprint 27B.5E removes the post-plan global performance cliff without changing Planner, store ranking, notification, geofence, coverage, or Map results. The retained Map defers plan application until its tab is active, Map state publishes as one coherent update, native annotations/overlays rebuild only when their stable content signature changes, and map filters reuse one cached result per relevant input set. UI-facing location updates are movement/time guarded while raw Core Location data continues to drive nearby, notification, and geofence decisions. Shopping uses lazy presentation and semantic row identities; Home disconnects its one-second publisher outside active plan generation.

`ShoppingItem` remains as a temporary compatibility adapter for Product Knowledge, Shopping Memory, planner inputs, saved-store item links, and Shopping Mode until native `ShoppingListEntry` planner/session migration is complete.

--------------------

Legacy Note

Products Library
