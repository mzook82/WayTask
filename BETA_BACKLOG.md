# WayTask Beta Backlog

Current Version: **1.0.0 (TestFlight)**

Next Planned Version: **1.0.1**

---

# Current Sprint Goal

Improve the overall shopping experience by fixing critical functionality, simplifying the Shopping tab, and improving store data quality based on beta tester feedback.

---

# 🔴 Critical

## WT-001 — Complete Shopping Flow Integration

**Status:** ✅ Completed

**Priority:** Critical

**Affected Screen:** Shopping

**Reported By:** Internal Testing

**Description**
The **Start Shopping** button does not respond.
Users cannot begin a shopping session.

**Acceptance Criteria**
- User can tap **Start Shopping**
- Shopping session starts successfully
- Navigation begins correctly

**Target Version:** 1.0.1

* Store Selection
* Shopping Session
* Shopping Mode
* Map Handoff
* Resume Session

**Notes**
-

---

## WT-002 — Implement Store Selection

**Status:** Planned

**Priority:** Critical

**Affected Screen:** Shopping

**Reported By:** Internal Testing

**Description**
Users cannot select which store to start shopping from.
The Shopping Plan flow is incomplete.

**Acceptance Criteria**
- User can choose a store
- Shopping Plan loads correctly
- Start Shopping works after selecting a store

**Target Version:** 1.0.1

**Notes**
-

---

# 🟠 High Priority

## WT-003A — Remove Shopping Summary

**Status:** Completed

**Priority:** High

**Affected Screen:** Shopping

**Reported By:** Internal Review

**Description**

Remove the **Shopping Summary** card to simplify the Shopping screen.

**Acceptance Criteria**

- Shopping Summary is removed.
- Screen layout remains clean and balanced.
- No empty spacing remains.
- Shopping functionality is unchanged.

**Target Version:** 1.0.1

**QA:** Passed

**Notes**

Completed successfully during Beta 1.0.1.

---

## WT-003B — Review Shopping List Selector UX

**Status:** Deferred

**Priority:** Medium

**Affected Screen:** Shopping

**Reported By:** Internal Review

**Description**

Review the current Shopping List Selector ("Weekly Shopping") and determine the best long-term UX.

The audit confirmed that this section is not only a visual element—it is the actual shopping list selector.

Removing it would remove the user's ability to switch between shopping lists.

**Acceptance Criteria**

- A long-term UX decision is made.
- Shopping list switching remains intuitive.
- No shopping functionality is lost.

**Target Version:** TBD

**Notes**

Deferred after UI Audit.

Requires a separate UX decision before implementation.

---

## WT-003C — Improve Product Row Layout

**Status:** Completed

**Priority:** High

**Affected Screen:** Shopping

**Reported By:** Internal Testing

**Description**

Improve the Shopping product row layout to increase product name readability while preserving all existing functionality.

The previous layout truncated long product names because horizontal controls consumed most of the available width.

**Accepted Solution**

Option 2 — Compact Two-Tier Row

**Acceptance Criteria**

- Product names support up to two lines.
- Subtitle remains below the product name.
- Quantity controls move beneath the text.
- Delete button remains visible.
- Completion control remains fully functional.
- Shopping behavior is unchanged.

**Target Version:** 1.0.1

**QA:** Passed

**Notes**

Implemented using the approved UI Review recommendation (Option 2).

No Shopping logic was modified.

---

## WT-004 — Remove Weekly Shopping Section

**Status:** Planned

**Priority:** High

**Affected Screen:** Shopping

**Reported By:** Internal Review

**Description**
Remove the **Weekly Shopping** section.
The current information does not provide meaningful value.

**Acceptance Criteria**
- Weekly Shopping section is removed
- No empty spacing remains

**Target Version:** 1.0.1

**Notes**
-

---

## WT-005 — Simplify Product List

**Status:** Planned

**Priority:** High

**Affected Screen:** Shopping

**Reported By:** Internal Review

**Description**
Remove the circular indicators displayed next to products in **Your List**.

**Acceptance Criteria**
- Product list displays without circular indicators
- Layout remains aligned and easy to read

**Target Version:** 1.0.1

**Notes**
-

---

# 🟡 Medium Priority

## WT-006 — Store Reporting

**Status:** Planned

**Priority:** Medium

**Affected Screen:** Map

**Reported By:** Internal Testing

**Description**
Allow users to report stores that are closed, relocated, or inactive.

**Acceptance Criteria**
- User can report an inactive store
- Report is submitted successfully

**Target Version:** TBD

**Notes**
-

---

## WT-007 — Product Reporting

**Status:** Planned

**Priority:** Medium

**Affected Screen:** Map

**Reported By:** Internal Testing

**Description**
Allow users to report products that are unavailable or incorrectly listed.

**Acceptance Criteria**
- User can report unavailable products
- Report is submitted successfully

**Target Version:** TBD

**Notes**
-

---

## WT-008 — Resume Shopping Session After App Relaunch

**Status:** ✅ Completed

**Priority:** High

**QA:** Passed

**Target Version:** 1.0.1

---

## WT-009 — Trustworthy Store Coverage

**Status:** Completed

**Priority:** High

**Affected Screen:** Shopping

**Reported By:** Internal Testing

**Description**

Improve the presentation of store recommendations to communicate estimated product coverage honestly and clearly.

Replace misleading percentage-based coverage with complete shopping-list coverage and product grouping.

**Accepted Solution**

Option 1 — Whole-List Coverage Presentation

**Acceptance Criteria**

- No percentage-based coverage is displayed.
- "Best" wording is removed.
- Recommendation refers to the complete shopping list.
- Products are grouped into:
  - Likely here
  - Other items
- Recommendation language clearly communicates estimated availability.
- Existing Shopping functionality remains unchanged.

**Target Version:** 1.0.1

**QA:** Passed

**Notes**

Implemented using the approved UX Review recommendation.

Presentation only.

No recommendation algorithm was modified.

## WT-009A — Recommendation Language Consistency

**Status:** Completed

**Priority:** High

**Affected Screens:** Home, Shopping, Map, Notifications

**Reported By:** Internal Testing

**Description**

Ensure recommendation language is consistent across WayTask and clearly communicates estimated product availability without misleading percentage or “Best” terminology.

**Acceptance Criteria**

- Home displays a compact recommendation summary.
- Shopping retains detailed “Likely here” and “Other items” presentation.
- No visible percentage rings remain.
- No misleading “Best” or “Match” terminology remains.
- Recommendation algorithms and application behavior remain unchanged.
- Map and notification wording use the same estimated-availability language.

**Target Version:** 1.0.1

**QA:** Passed

**Notes**

Presentation-only consistency update.

Internal diagnostics and unrelated search wording were intentionally excluded.

---

## WT-010 — First-Time Guidance

**Status:** Deferred

**Priority:** Medium

**Affected Screen:** App Launch / Camera

**Reported By:** Product Review

**Description**

Provide lightweight first-time guidance explaining the core WayTask workflow without introducing a full onboarding experience.

Planned scope:

- Welcome screen
- AI Camera explanation
- "View Again" from Settings
- Versioned What's New

**Acceptance Criteria**

- New users understand the basic workflow.
- Guidance appears only when appropriate.
- Guidance can be reopened later.

**Target Version:** 1.0.2

**Notes**

Deferred to keep Beta 1.0.1 focused on Shopping Flow and User Trust.

---

# 📝 Beta Feedback

| Date | Tester | Feature | Feedback | Linked Task | Status |
|------|--------|---------|-----------|-------------|--------|

---

# ✅ Completed

Move completed tasks here after they are released.

## WT-011A — Improve Manual Product Creation Reliability

**Status:** Completed

**Priority:** Critical

**Affected Screen:** Products / Add Product

**Reported By:** Internal Testing

**Description**

Improve the manual Add Product flow by clarifying validation, preventing card overlays from interfering with controls, and handling persistence failures safely.

**Acceptance Criteria**

- Product name field receives focus when the Add Product sheet opens.
- Empty or whitespace-only names cannot be submitted.
- The disabled Add Product button is visually clear.
- A valid name can be submitted from the keyboard.
- Valid products save to the Product Library.
- The sheet closes only after successful persistence.
- Save failures are reported to Sentry.
- Save failures preserve the entered data and show a user-facing error.
- Card border overlays do not interfere with form controls.

**Target Version:** 1.0.2

**QA:** Passed

**Notes**

The manual flow continues to create user-owned Product records and does not create or modify Product Knowledge ProductEntity records.

Duplicate manual product names remain supported.

---

# 🚧 Deferred

Tasks postponed to a future version.

---

# 💡 Parking Lot

Ideas that should not be implemented yet but should not be forgotten.

- None

---

# 📊 Task Summary

| ID | Title | Priority | Status | Version |
|----|-------|----------|--------|---------|
| WT-001 | Fix Start Shopping | Critical | Planned | 1.0.1 |
| WT-002 | Fix Shopping Plan Flow | Critical | Planned | 1.0.1 |
| WT-003 | Remove Shopping Summary | High | Planned | 1.0.1 |
| WT-004 | Remove Weekly Shopping | High | Planned | 1.0.1 |
| WT-005 | Simplify Product List | High | Planned | 1.0.1 |
| WT-006 | Store Reporting | Medium | Planned | TBD |
| WT-007 | Product Reporting | Medium | Planned | TBD |
| WT-011A | Improve Manual Product Creation Reliability | Critical | Completed | 1.0.2 |
