# WayTask Project Status

Current Version:
1.0

Current Milestone:
Milestone 3 – Products & Shopping Separation

Current Sprint:
Sprint 27B.4.2 – First Shopping Experience & Shopping Workflow Completion

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

Next Sprint:

Native ShoppingListEntry planner/session migration and Shopping Mode ownership

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

Sprint 27B.4.2 completes the first shopping experience. New users see a lightweight one-time explanation that Products are permanent, Shopping is temporary, and Generate Plan finds stores for the selected list. Legacy users with existing Weekly Shopping entries see a one-time review before those entries are treated as intentional. Shopping now makes `Choose Products` a primary action, hides Generate Plan when no products are selected, and keeps Home synchronized with the shared planning stage and elapsed time.

`ShoppingItem` remains as a temporary compatibility adapter for Product Knowledge, Shopping Memory, planner inputs, saved-store item links, and Shopping Mode until native `ShoppingListEntry` planner/session migration is complete.

--------------------

Legacy Note

Products Library
