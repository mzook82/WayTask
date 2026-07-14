# WayTask Project Status

Current Version:
1.0

Current Milestone:
Milestone 3 – Products & Shopping Separation

Current Sprint:
Sprint RC-1 – Privacy-Safe Sentry Integration for TestFlight

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
- Privacy-safe Sentry crash/non-fatal reporting with no product analytics
- DEBUG-only Sentry validation and archive-only dSYM upload preparation

Next Sprint:

RC-2 – On-Device Sentry/TestFlight Validation and Privacy Disclosure Review

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

RC-1 adds Sentry Cocoa through Swift Package Manager without changing product decisions. Sentry starts only with a valid locally supplied DSN; events pass through a strict privacy filter, automatic tracing/replay/screenshots/view hierarchy/network capture/PII are disabled, and only enum-backed generic workflow context plus aggregate counts are permitted. Release archives retain dSYMs and use a credential-gated, non-blocking symbol-upload phase.

`ShoppingItem` remains as a temporary compatibility adapter for Product Knowledge, Shopping Memory, planner inputs, saved-store item links, and Shopping Mode until native `ShoppingListEntry` planner/session migration is complete.

--------------------

Legacy Note

Products Library
