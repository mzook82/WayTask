# WayTask Engineering Blueprint

**Project:** WayTask

**Document:** Engineering Blueprint

**Version:** 1.0

**Status:** Approved

**Platform:** iOS (SwiftUI)

**Owner:** Engineering

**Related Documents:**

- Product Specification v1.0
- Architecture Documentation
- Sprint Documentation

**Last Updated:** July 8, 2026

---

# Revision History

| Version | Date | Description |
|----------|------------|----------------------------|
| 1.0 | 2026-07-08 | Initial Engineering Blueprint |

---

# Document Purpose

This document defines the engineering strategy for WayTask Version 1.0.

It does not describe the product.

Instead, it describes how the approved product should be implemented while preserving the existing architecture and business logic.

This document should always be read together with:

- Product Specification v1.0
- Architecture Documentation

If any conflict exists between documents:

1. Product Specification has the highest priority.
2. Engineering Blueprint defines implementation strategy.
3. Architecture Documentation defines technical implementation details.

---

# Table of Contents

1. Executive Summary

2. Engineering Philosophy

3. Existing Foundation

4. Current Architecture

5. Target Architecture

...

---

# 1. Executive Summary

WayTask Engineering Blueprint defines how the existing application
will evolve into the approved Version 1.0 product.

Unlike the Product Specification, which defines the user experience,
this document defines the engineering strategy, migration approach,
reuse policy, implementation phases, and architecture evolution.

Its primary goal is to ensure that engineering reuses the existing
business logic while implementing the new user experience.

---

# 2. Engineering Philosophy

WayTask is not being rebuilt.

WayTask is being evolved.

Existing business logic is considered an engineering asset.

Every engineering decision should first ask:

"Can the existing engine be reused?"

If yes:

Reuse it.

Only replace the presentation layer.

---

# 3. Existing Foundation

## Product Intelligence

- Barcode Recognition
- Gemini Product Recognition
- Product Knowledge
- Product Intent Resolver

## Store Intelligence

- Store Reality Score
- Store Aggregation
- Store Search
- Store Ranking

## Platform

- SwiftData
- MapKit
- Camera
- Notifications
- Location
- Haptics

---

# 4. Existing Architecture
Barcode
        │
        ▼
Product Knowledge
        │
        ▼
Product Intent Resolver
        │
        ▼
Store Search
        │
        ▼
Store Aggregation
        │
        ▼
Store Reality Score
        │
        ▼
Shopping Planner
        │
        ▼
Shopping Journey

This architecture is approved.

Future work should extend it.

Not replace it.

---

# 5. Future Data Model

The future product separates Products from Shopping.

Product
        │
        ▼
Shopping List
        │
        ▼
Shopping List Item
        │
        ▼
Shopping Plan
        │
        ▼
Shopping Session

Product Knowledge remains independent.

It supports Products.

It does not become Shopping data.

---

# 6. Reuse Strategy
Never Replace

These modules are considered production assets.

Product Knowledge
Product Intent Resolver
Store Reality Score
Store Aggregation
Barcode
Gemini
MapKit Integration
SwiftData
Refactor

Current ShoppingItem

↓

Future

Product

ShoppingList

ShoppingListItem

Replace

UI only.

Home
Products
Shopping
Store Details
Shopping Mode
Settings

---

# 7. Design System

Engineering must implement the approved Design System.

Never invent new components.

Reuse components everywhere.

Core Components:

Store Card
Coverage Ring
Product Card
Shopping List Card
Bottom Sheet
Navigation Bar
Floating Scan Button
Progress Ring
Toast
Search
Badges

Every component must remain visually identical across the application.

---

# 8. Application Layers
SwiftUI Views

↓

ViewModels

↓

Services

↓

Models

↓

SwiftData

↓

System APIs

Business logic belongs to Services.

Views never calculate business rules.

---

# 9. Development Order
Phase 1

Foundation

Theme
Navigation
Design System
Components
Phase 2

Products

Product Library
Scanner
AI Review
Product Editing
Phase 3

Shopping

Shopping Lists
Planner
Coverage
Recommended Stores
Phase 4

Shopping Journey

Route
Navigation
Shopping Mode
Next Store
Shopping Complete
Phase 5

Map

Reuse:

MapKit
Store Aggregation
Reality Score

Replace:

UI only.

Phase 6

Settings

Developer

Notifications

About

Preferences

Phase 7

Polish

Animations
Offline
Loading
Empty States
Accessibility
Performance

---

# 10. Migration Strategy

Migration must be incremental.

Never rewrite everything.

Each migration should preserve compatibility.

Example:

Current:

ShoppingItem

↓

Introduce

Product

↓

Move Features

↓

Replace references

↓

Remove ShoppingItem

Only after migration is complete.

---

# 11. Engineering Risks
Highest Risk

ShoppingItem migration.

Mitigation:

Introduce Product model first.

High Risk

Store recommendation accuracy.

Mitigation:

Continue improving taxonomy.

Never rewrite Reality Score.

Medium Risk

AI latency.

Mitigation:

Graceful fallback.

Manual editing.

Medium Risk

Map integration.

Mitigation:

Keep MapKit abstraction layer.

---

# 12. Acceptance Criteria

A feature is complete only if:

UI matches Product Specification.
Existing Services are reused.
No duplicate business logic exists.
Documentation updated.
Build succeeds.
Review completed.
Regression tests pass.

---

# 13. Sprint Rules

Every Sprint follows the same lifecycle:

Inspect

↓

Plan

↓

Implement

↓

Build

↓

Review

↓

Fix

↓

Build

↓

Documentation

↓

Stop before Commit

No Sprint skips documentation.

---

# 14. Future Compatibility

Version 1.0 must remain compatible with future features.

Architecture should support:

Cloud Sync
Shared Lists
Family Accounts
Community Knowledge
Retail APIs
Inventory APIs
Cart Scanning

without structural redesign.

---

# 15. Engineering Manifest

Every implementation decision must answer:

Can the existing engine be reused?

If the answer is yes:

Reuse it.

Only redesign the presentation layer.

Never rebuild intelligence that already works.

---

# 16. Definition of Success

WayTask Version 1.0 is complete when:

Products Library is stable.
Shopping Lists are stable.
Shopping Planner recommends stores correctly.
Shopping Journey is complete.
Shopping Mode guides users through stores.
Store Coverage is consistent.
Product Knowledge continuously improves.
The complete user journey matches the approved Product Specification.

---

# 17. Final Engineering Approval

This document becomes the engineering source of truth.

Future implementation should reference:

Product Specification
Engineering Blueprint
Existing Architecture

in this order.

Any deviation requires updating the Product Specification before implementation.

---

# 18. Sprint 26A Foundation Update

Sprint 26A establishes the Version 1.0 Design System Foundation.

The design system is implemented as the reusable SwiftUI UI layer and should be used by future Version 1.0 screens before introducing screen-specific styling.

## Implemented Foundation

- Design tokens for colors, typography, spacing, corner radius, elevation, animation, glass effects, and haptics.
- Reusable UI components for primary buttons, secondary buttons, glass cards, store cards, product cards, shopping list cards, coverage rings, progress rings, badges, search, empty states, loading skeletons, offline states, bottom sheets, section headers, floating scan, and navigation bars.
- Version 1.0 navigation shell with Home, Products, Shopping, Map, and Settings tabs.

## Migration Boundary

Sprint 26A does not migrate product, shopping, map, recommendation, AI, or persistence business logic.

The following modules remain unchanged by design:

- Product Knowledge
- Product Intent Resolver
- Store Reality Score
- Store Aggregation
- Shopping Planner
- Gemini
- MapKit integration
- SwiftData models

Future UI work should consume the design system components instead of creating one-off styles.

---

# 19. Sprint 26B Home Update

Sprint 26B replaces the Home placeholder with the approved Version 1.0 Home dashboard.

## Implemented Home Surface

- Greeting/date header with scan and settings actions.
- Shopping Today hero with coverage ring, best-store summary, trip progress, and Start Shopping.
- Shopping Lists section using current `ShoppingItem` state until the future `ShoppingList` model migration.
- Best Shopping Plan preview using existing `AppStateManager.shoppingTripCoverages` when available.
- Nearby Opportunity card using existing nearby opportunity state when available.
- Recent Products section using existing `ShoppingItem` records.
- Monthly stats section using existing `ShoppingSession` and `ShoppingItem` records.
- Quick Scan entry point using the existing `CameraView`.

## Reuse Boundary

Sprint 26B remains a UI migration sprint.

It does not change:

- Product Knowledge
- Gemini
- Store Reality Score
- Store Aggregation
- MapKit discovery
- SwiftData models
- Product, shopping, or map business logic

Any placeholder Home data is isolated inside `HomeView` and should be replaced by real Product v1.0 and Shopping v1.0 models in later migration phases.
