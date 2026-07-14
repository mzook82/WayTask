# Architecture

**Project:** WayTask  
**Version:** 0.1  
**Status:** Draft  
**Owner:** Mordechai Zukerman  
**Last Updated:** July 14, 2026

---

# 1. Architecture Goal

WayTask is built as a modular iOS application designed to grow from an MVP into a long-term AI-powered shopping platform.

The architecture must support:

- Native iOS experience
- Camera and Vision features
- Location and Map intelligence
- AI-powered recommendations
- Future backend integration
- Replaceable AI providers
- Privacy-first design

---

# 2. Engineering Principles

## 2.1 User First

Every feature must solve a real user problem.

## 2.2 Replaceable Architecture

Every major component should be replaceable without rewriting the entire app.

## 2.3 Keep It Simple

Complexity belongs inside the system, not in the user interface.

## 2.4 Privacy by Design

User data belongs to the user.

## 2.5 Build for the Next Five Years

Major decisions should still make sense years from now.

---

# 3. High-Level Architecture

The current WayTask architecture follows a layered approach.

```text
SwiftUI Views
        │
        ▼
ViewModels
        │
        ▼
Services & Managers
        │
        ▼
Models
        │
        ▼
Apple Frameworks
```

Sentry is an optional boundary service, not a business-logic layer. `SentryReportingService` is the only source file that imports the SDK. Planner, store resolution, Map, notification, geofence, recognition, persistence, and Shopping code can report only enum-backed operations/messages/areas and aggregate integers through that abstraction. With no valid build-supplied DSN, the boundary is never initialized and all calls no-op.

```text
Existing failure/workflow path
        │
        ▼
SentryReportingService
        │
        ├── missing/invalid DSN ──► no-op
        │
        └── configured ──► beforeSend privacy allowlist ──► Sentry
```

Tracing, profiling, Session Replay, screenshots, view hierarchy, network capture, automatic breadcrumbs/sessions, app-hang tracking, and product analytics are outside this boundary. See `docs/180_SENTRY_INTEGRATION.md`.

### Layer Responsibilities

**SwiftUI Views**

Responsible for presenting information and handling user interaction.

**ViewModels**

Manage screen state and coordinate business logic.

**Services & Managers**

Handle reusable functionality such as camera access, location updates, and future AI integration.

**Models**

Represent the application's business data.

**Apple Frameworks**

Provide native iOS capabilities such as:

- SwiftUI
- MapKit
- CoreLocation
- AVFoundation
- Photos

---

# 4. Current Project Structure

The current project is organized into feature-specific components.

```text
WayTask

├── Camera
│   ├── CameraView
│   ├── CameraViewModel
│   ├── CameraService
│   ├── CameraPreviewView
│   └── ProductRecognitionService (Stub)
│
├── Map
│   ├── MainMapView
│   ├── WayTaskMapView
│   ├── MapViewModel
│   ├── MapBottomSheet
│   ├── MapControls
│   └── StoreSearchService
│
├── Products
│   └── ProductListView
│
├── Core
│   ├── Models
│   ├── LocationManager
│   ├── AppStateManager
│   └── DesignSystem
│
└── Resources
```

This structure will evolve over time as additional features are introduced.

---

# 5. Current Data Flow

The current implementation follows a predictable data flow.

Example: Camera

```text
User
        │
        ▼
CameraView
        │
        ▼
CameraViewModel
        │
        ▼
CameraService
        │
        ▼
ProductRecognitionService (Stub)
```

Example: Map

```text
User
        │
        ▼
MainMapView
        │
        ▼
MapViewModel
        │
        ▼
LocationManager
        │
        ▼
MapKit
```

Example: Shared Shopping Plan

```text
Generate Plan / Start Shopping
        │
        ▼
Existing planner services
        │
        ▼
AppStateManager.shoppingPlan
AppStateManager.shoppingPlanState
        │
        ├── HomeView
        ├── ShoppingWorkspaceView
        └── MainMapView
```

`ShoppingPlan` is an app-state value, not a SwiftData model. It contains the current planner request, active shopping items, planner stores, buying options, trip coverage rows, and generation timestamp. Home, Shopping, and Map observe this single shared value so they display the same generated plan.

`shoppingPlanState` is the shared runtime state machine for the current plan:

- `idle`
- `generating`
- `ready`
- `failed`
- `stale`

Shopping owns explicit generation actions. Home observes the same state and does not generate an independent plan. Map receives the existing shared plan only after the plan is ready and contains usable stores.

### Plan-to-Map Performance Flow

`MainMapView` and its `MapViewModel` remain retained by the root `TabView`; tab changes do not recreate either object. A ready `ShoppingPlan` follows this visibility-aware path:

```text
AppStateManager.shoppingPlan
        │
        ├── Map active ──► apply once to MapViewModel
        │                         │
        │                         ├── one batched display publication
        │                         └── cached filtered stores/products
        │
        └── Map inactive ─► retain pending plan ID
                                  │
                                  └── apply once when Map becomes active
```

Map visibility gates only native presentation work. Shared store resolution, notification scheduling, nearby opportunity evaluation, and geofence monitoring remain independent of the selected tab.

`WayTaskMapView` derives a stable native-content signature from store identity, coordinate, raw radius, title, source, matched item names, and product marker identity. `updateUIView` continues to process legitimate camera changes, but it skips annotation and circle replacement when that signature is unchanged. User-location annotations are never included in removal.

Core Location has two coordinate paths. `LocationManager` retains every raw valid coordinate for nearby, notification, and geofence decisions. Its `@Published` UI coordinate emits for the first fix, movement of at least 15 meters, or a maximum interval of 10 seconds. `MapViewModel` applies the same guard to MapKit user-location callbacks so unchanged display coordinates cannot repeatedly invalidate the retained map.

Example: Product Library and Shopping Lists

```text
Product
        │
        ▼
ShoppingList
        │
        ▼
ShoppingListEntry
        │
        ▼
Temporary ShoppingItem adapter
        │
        ▼
ShoppingPlan
```

Sprint 27B.1 introduced persistent `Product`, `ShoppingList`, and `ShoppingListEntry` models. Sprint 27B.2 connected Products to Shopping: scanning and manual product creation now save/update `Product` records first, and users explicitly add Products to the selected Shopping list.

Sprint 27B.4.1 changed migration behavior so legacy `ShoppingItem` records backfill `Product` records and default Shopping lists only. They no longer auto-create Weekly Shopping entries. Sprint 27B.4.2 added explicit first-shopping ownership: new users see a one-time onboarding and chooser, while legacy users with existing Weekly Shopping entries see a one-time review before those entries are treated as intentional. `Start Fresh` removes only temporary Weekly Shopping entries and marks linked compatibility `ShoppingItem` records completed; it never deletes Products.

Shopping reads `ShoppingListEntry` records only. Each entry still adapts to a temporary `ShoppingItem` record for current planner, Shopping Mode, Product Knowledge, Shopping Memory, and saved-store compatibility. This preserves existing services while keeping the user-facing distinction clear: Products are permanent library records; Shopping is a temporary list.

Sprint 27B.3 removed the runtime UI override where an active Shopping Session replaced the Products tab. Sprint 27B.4 formalized Shopping plan state and gated Map/Shopping Mode entry behind a ready shared plan. Shopping Mode remains on the legacy `ShoppingSession` path, but it no longer owns Product Library presentation.

This architecture keeps presentation logic separated from reusable services.

## Unified Runtime Store Resolution

All runtime store consumers enter `StoreResolutionEngine.shared`:

```text
Saved GeoLocation stores
        +
Grouped shopping intents
        +
Current coordinate
        │
        ▼
StoreResolutionEngine
        │
        ├── coordinate-bucket + intent cache
        ├── in-flight request reuse and refresh throttle
        ├── grouped MapKitStoreSearchService searches
        ├── synthetic local-store suppression
        ├── saved-store-priority merge
        └── stable identity deduplication
        │
        ▼
RuntimeStore (MapStore compatibility alias)
        │
        ├── Planner / Buying Options / Coverage
        ├── Map suggestions and proximity overlays
        ├── Nearby opportunities
        ├── Notification validation and navigation
        └── Geofence candidates
```

Persisted stores retain `GeoLocation.id`. Transient MapKit/fallback stores derive a deterministic UUID from source type, normalized title, and a tight coordinate bucket. Transient stores remain runtime-only and are materialized in Map state when a notification or nearby opportunity references one.

Planner ordering is strict: saved stores, awaited discovery, merge, deduplicate, buying options, coverage, then `ShoppingPlan`. A missing saved store set is not a failure while discovery can still run.

Map discovery is independent of `ShoppingPlan`. Opening Map without a ready plan performs cached nearby discovery but does not publish or generate a plan. Applying a ready plan still uses that plan's stores and preserves existing user-follow behavior.

Notification payloads carry store identity, coordinate, title, source type, matched `ShoppingItem` IDs/names, Shopping list ID, and notification type when available. `StoreNavigationContext` reconstructs and selects transient stores. Opening a notification preserves a valid `ShoppingPlan` unless the payload switches to a different Shopping list.

Geofence monitored-region limits and Core Location behavior remain unchanged. Candidate selection now uses the shared resolved stores, and Map circles are drawn from the same stable runtime store set.

See `docs/140_STORE_RESOLUTION_ENGINE.md` for invariants, safeguards, limitations, and field validation.

---

# 6. Future Architecture

After the MVP is completed, the project will gradually transition into a modular architecture.

Future modules may include:

- Shopping Engine
- Camera Engine
- Location Engine
- AI Engine
- Recommendation Engine
- Notification Engine
- Discover Engine

These modules are intentionally planned for a future milestone and are **not part of the current implementation**.

The goal is to improve scalability, maintainability, and long-term flexibility without affecting the MVP timeline.

---

# 7. Architecture Decisions

The following architectural decisions define how WayTask is built today and how it will evolve.

## Business Logic

Business logic should remain outside SwiftUI Views.

Views are responsible only for presenting information and handling user interaction.

---

## State Management

Each screen owns its own ViewModel.

ViewModels coordinate user actions and communicate with reusable Services.

---

## Services

Reusable functionality belongs inside Services.

Examples include:

- CameraService
- StoreSearchService
- LocationManager

Services should remain independent of SwiftUI whenever possible.

---

## Native First

WayTask should always prefer Apple's native frameworks before introducing third-party dependencies.

Current native technologies include:

- SwiftUI
- MapKit
- CoreLocation
- AVFoundation
- Photos

---

## AI Independence

Artificial Intelligence must remain replaceable.

The application should never depend directly on one provider.

Future providers may include:

- OpenAI
- Apple Foundation Models
- Gemini
- Claude

The rest of the application should not require changes when switching providers.

---

# 8. Scalability Strategy

The MVP focuses on a simple project structure.

As the application grows, features will gradually become independent modules.

Future examples:

- Camera Module
- Shopping Module
- Discover Module
- Notification Module
- AI Module

This transition will happen only after the MVP has stabilized.

---

# 9. Performance Goals

WayTask should feel lightweight and responsive.

Performance priorities:

- Fast application launch
- Smooth scrolling
- Instant map interaction
- Responsive camera preview
- Minimal loading delays

Artificial Intelligence should never block the user interface.

Heavy processing should run asynchronously whenever possible.

---

# 10. Privacy Principles

Privacy is a core architectural requirement.

The application should:

- Request only required permissions.
- Clearly explain why permissions are needed.
- Minimize cloud processing whenever possible.
- Keep sensitive user information under user control.

Whenever possible, processing should occur directly on the device.

---

# 11. Open Questions

The following questions should be revisited as WayTask evolves:

- Which AI provider should be used first?
- Should product recognition start with Apple Vision, OpenAI, Gemini, or a hybrid approach?
- When should backend storage be introduced?
- Should shopping history remain local-first or sync through the cloud?
- How should recommendation caching work?
- When should the project be refactored into feature modules?
- Should Discover use local data first or external APIs?

---

# 12. Future Improvements

Future architecture improvements may include:

- Modular feature folders
- AI Engine abstraction
- Prompt Library
- Recommendation Engine

---

# 13. Version 1.0 UI Foundation

Sprint 26A introduces the Version 1.0 design-system foundation without changing business logic.

## Design System Layer

`WayTaskDesignSystem.swift` is the shared SwiftUI UI layer for Version 1.0 screens.

It contains:

- Design tokens for color, typography, spacing, radius, elevation, animation, glass effects, and haptics.
- Shared components for buttons, cards, rings, badges, search, empty states, loading, offline states, bottom sheets, section headers, floating scan, and navigation.

Future screens should use this layer first and avoid duplicating visual styles inside feature views.

## Navigation Foundation

`ContentView` now defines the Version 1.0 application shell:

```text
Home
Products
Shopping
Map
Settings
```

Only shell structure is introduced in Sprint 26A.

Existing feature screens, services, models, ViewModels, and providers remain in place until their migration sprint.

## Current Layering Policy

The approved layer order remains:

```text
SwiftUI Views
        │
        ▼
ViewModels
        │
        ▼
Services
        │
        ▼
Models
        │
        ▼
SwiftData / System APIs
```

Business logic must continue to live in Services and ViewModels, not reusable UI components.
- Feature Flags
- Backend API layer
- Cloud sync
- Test coverage
- Analytics layer
- Error reporting

These improvements should be added gradually and only when they support the MVP or long-term scalability.

---

# 13. Related Documents

- README.md
- docs/00_INDEX.md
- docs/05_PRODUCT_VISION.md
- docs/10_PRD.md
- docs/20_ROADMAP.md
- docs/40_AI_ROADMAP.md
- docs/70_DEVELOPMENT_GUIDE.md

# Shopping Intelligence Layer

WayTask now includes a dedicated Shopping Intelligence layer.

Flow:

Camera
↓

Recognition

↓

Product Provider

↓

Shopping List

↓

Shopping Intent

↓

Store Search

↓

Map

↓

Future AI
