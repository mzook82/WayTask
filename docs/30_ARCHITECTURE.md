# Architecture

**Project:** WayTask  
**Version:** 0.1  
**Status:** Draft  
**Owner:** Mordechai Zukerman  
**Last Updated:** June 30, 2026

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

This architecture keeps presentation logic separated from reusable services.

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
