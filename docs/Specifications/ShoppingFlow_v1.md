# Shopping Flow Specification (Beta 1.0.1)

Version: 1.0

Status: Draft

Owner: WayTask

Last Updated: 2026-07-19

---

# Related Documents

- ShoppingFlowAudit.md

- BETA_BACKLOG.md (WT-001)

- ROADMAP.md

- CHANGELOG.md

---

# Objective

Complete the Shopping Flow by connecting the existing Shopping Plan, Shopping Session, and Map experience into one seamless user journey.

This specification defines the expected behavior for Beta 1.0.1.

---

# Background

The current Shopping Flow already includes:

- Shopping lists
- Shopping Plan generation
- Store ranking
- Store recommendations
- ShoppingSession persistence
- Apple Maps navigation

However, these components are only partially connected.

The goal of this release is to complete the end-to-end shopping experience without introducing advanced route optimization.

---

# Scope

This specification covers:

- Shopping Plan
- Store Selection
- Start Shopping
- Shopping Session
- Shopping Mode
- Finish Shopping

It does NOT cover:

- Multi-store optimization
- Inventory verification
- ETA calculations
- Turn-by-turn navigation
- Indoor navigation

---

# User Journey

```
Shopping List
        │
        ▼
Generate Shopping Plan
        │
        ▼
Review Suggested Stores
        │
        ▼
Select Preferred Store
        │
        ▼
Start Shopping
        │
        ▼
Open Apple Maps
        │
        ▼
Arrive at Store
        │
        ▼
Return to WayTask
        │
        ▼
Shopping Mode
        │
        ▼
Collect Products
        │
        ▼
Finish Shopping
```

---

# Shopping Plan

## Goal

Help the user decide where to shop.

## Requirements

- Generate a Shopping Plan.
- Display recommended stores.
- Display estimated product coverage.
- Display store distance.
- Sort stores by relevance.

---

# Store Selection

## Goal

Allow the user to explicitly choose the preferred store.

## Requirements

- Only one store may be selected.
- The best recommendation is selected by default.
- The user may change the selection.
- The selected store remains highlighted.

---

# Start Shopping

## Goal

Begin an active shopping session.

## Requirements

When the user taps Start Shopping:

- A new shopping session must begin.
- The selected shopping list must remain associated with the session.
- The selected store must remain associated with the session.
- The current shopping plan must remain available throughout the session.
- Display a confirmation state.
- Continue the shopping journey.

---

# Navigation

## Goal

Navigate the user to the selected store.

For Beta 1.0.1:

- The user must be able to navigate to the selected store using Apple Maps.
- Use the selected store.
- Do not implement in-app navigation.

---

# Shopping Mode

## Goal

Support the user while shopping.

Display:

- Store name
- Remaining products
- Collected products
- Progress
- Finish Shopping button

Allow:

- Mark product as collected.
- Undo collected product.

---

# Finish Shopping

## Goal

Close the active shopping session.

When completed:

- Mark Shopping Session as finished.
- Save completion time.
- Return to Shopping screen.

---

# Error Handling

If no Shopping Plan exists:

- Disable Start Shopping.

If no store is selected:

- Prevent session creation.

If session creation fails:

- Display a user-friendly error.

If Apple Maps cannot open:

- Inform the user.

---

# Acceptance Criteria

The feature is complete when:

- User can select a store.
- User can start shopping.
- Shopping Session is created.
- Apple Maps opens correctly.
- User returns to WayTask.
- Shopping Mode is available.
- User can mark collected products.
- User can finish the session.

---

# Out of Scope

The following features are intentionally excluded from Beta 1.0.1:

- Multi-store shopping
- Route optimization
- Live inventory
- AI shopping optimization
- ETA calculation
- Shopping history analytics

---

# Future Enhancements

Potential future improvements:

- Multi-store shopping routes
- Smart route optimization
- Live inventory integration
- AI-generated shopping routes
- Personalized shopping suggestions
- Estimated shopping duration
- Session recovery across devices

---

# Open Questions

To be answered before implementation:

- Should Apple Maps open automatically or only after confirmation?
- Should the app automatically return to Shopping Mode after navigation?
- How should unfinished Shopping Sessions be resumed?
- Should users be allowed to change stores after starting a session?

# Assumptions

The following assumptions apply to Beta 1.0.1:

- The shopping journey starts from a single selected store.
- Apple Maps is the primary navigation provider.
- Product availability is estimated and not guaranteed.
- Shopping sessions are intended to continue if the user leaves and returns to the app.
