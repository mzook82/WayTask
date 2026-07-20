# WayTask Project Decisions

This document records important product and technical decisions made during the development of WayTask.

Its purpose is to preserve the reasoning behind major decisions, making future maintenance and development easier.

---

# Decision Template

## YYYY-MM-DD

### Title

**Category**
Product / UI / UX / AI / Architecture / Release / Infrastructure

**Decision**

Describe the decision that was made.

**Reason**

Explain why this decision was made.

**Alternatives Considered**

List other options that were evaluated.

**Status**

Approved / Superseded / Deprecated

---

# Decisions

Once development of a beta release has started, new ideas discovered during testing are added to the backlog but are not automatically included in the current release.

Only critical bugs or changes that significantly improve the planned user experience may be added after review.

Reason

* Prevent scope creep.
* Keep releases predictable.
* Improve testing quality.
* Avoid delaying releases indefinitely.

Status

Approved

---

## 2026-07-19

### Weekly Beta Release Cycle

**Category**

Release Process

**Decision**

Adopt a weekly beta release cycle whenever enough improvements are ready.

Critical issues may be released earlier as hotfixes.

**Reason**

- Provide testers with predictable updates.
- Collect feedback in manageable batches.
- Improve release quality.
- Avoid releasing every small change individually.

**Alternatives Considered**

- Daily releases
- Releases only when large features are completed

**Status**

Approved

---

## 2026-07-19

### Documentation Language

**Category**

Project Management

**Decision**

Maintain all project documentation in English.

**Reason**

- Easier collaboration.
- Better compatibility with AI development tools.
- Industry standard.
- Future contributors can easily understand the project.

**Alternatives Considered**

- Hebrew documentation
- Mixed Hebrew and English

**Status**

Approved

---

## 2026-07-19

### Beta Backlog as Single Source of Truth

**Category**

Project Management

**Decision**

All feature requests, bugs, tester feedback, and improvements must first be added to BETA_BACKLOG.md before implementation.

**Reason**

Keeps project planning centralized and prevents losing tasks.

**Alternatives Considered**

- Personal notes
- GitHub Issues only

**Status**

Approved

---

## 2026-07-19

### Small Incremental Releases

**Category**
Release Strategy

**Decision**

Prefer small, stable releases over large feature-packed releases.

**Reason**

- Easier testing.
- Faster feedback.
- Lower risk.
- Simpler debugging.

**Alternatives Considered**

Large milestone releases.

**Status**

Approved

---

## 2026-07-19

### User Experience Before New Features

**Category**
Product

**Decision**

Prioritize usability improvements and bug fixes before adding major new features.

**Reason**

A polished experience creates more value than many unfinished features.

**Alternatives Considered**

Rapid feature expansion.

**Status**

Approved

---

## 2026-07-19

### AI as an Assistant, Not the Main Product

**Category**

AI

**Decision**

Artificial Intelligence should enhance the shopping experience, not replace it.

WayTask remains a shopping assistant first.

**Reason**

The primary goal is helping users complete shopping efficiently.
AI should support that goal instead of becoming the focus.

**Alternatives Considered**

AI-first application.

**Status**

Approved

---

## 2026-07-19

### Product Quality First

**Category**

Development

**Decision**

Every release must pass internal testing before being published to TestFlight.

**Reason**

Prevent avoidable bugs from reaching beta testers.

**Alternatives Considered**

Publishing immediately after development.

**Status**

Approved

---

## 2026-07-20

### Shopping Flow Ownership

**Category**

Architecture

**Decision**

ShoppingWorkspace is the single owner of the shopping experience.

**Reason**

Avoid duplicate shopping flows and keep session management centralized.

**Status**

Approved

---

## 2026-07-20

### Product Row Layout

**Category**

UI

**Decision**

Adopt the Compact Two-Tier Row layout.

**Reason**

Improves readability while preserving all Shopping functionality.

**Status**

Approved

---

## 2026-07-20

### UI Review Before Removal

**Category**

UX

**Decision**

Functional UI elements must be audited before removal.

**Reason**

Some visual elements also contain business logic.

**Status**

Approved

---

## 2026-07-20

### Sprint Scope Protection

**Category**

Project Management

**Applies From**

Beta 1.0.1

**Decision**

Once development of a beta release has started, new ideas discovered during testing are added to the backlog but are not automatically included in the current release.

Only critical bugs or changes that significantly improve the planned user experience may be added after review.

**Reason**

- Prevent scope creep.
- Keep releases predictable.
- Improve testing quality.
- Avoid delaying releases indefinitely.
- Ensure each beta release has a clear and achievable scope.

**Alternatives Considered**

- Continuously adding new ideas during development.
- Delaying releases until every improvement is completed.

**Status**

Approved

---

## 2026-07-20

### AI Development Workflow

**Category**

Development

**Applies From**

Beta 1.0.1

**Decision**

For significant features, AI-assisted development must follow a structured workflow before implementation.

Required workflow:

1. Audit
2. Product Specification
3. Implementation Specification
4. Implementation Review
5. Code Generation
6. QA
7. Release

AI should not generate implementation code for major features until the implementation approach has been reviewed and approved.

**Reason**

- Improve implementation quality.
- Reduce unnecessary refactoring.
- Preserve project architecture.
- Ensure development decisions are intentional.
- Produce predictable and reviewable changes.

**Alternatives Considered**

- Generating code immediately from a feature request.
- Skipping the audit and specification phases.

**Status**

Approved

---

## 2026-07-20

### Documentation First

**Category**

Project Management

**Applies From**

Beta 1.0.1

**Decision**

Major features should be documented before implementation.

Documentation should include the relevant planning artifacts before development begins.

Typical workflow:

- Backlog
- Audit
- Product Specification
- Implementation Specification
- Implementation
- QA
- Changelog

**Reason**

Planning before implementation reduces misunderstandings, improves AI-assisted development, and keeps the project documentation synchronized with the codebase.

**Alternatives Considered**

- Writing documentation only after implementation.
- Developing features without formal documentation.

**Status**

Approved

### Trustworthy Store Recommendations

**Category**

Product

**Applies From**

Beta 1.0.1

**Decision**

Store recommendations must communicate estimated product coverage without implying verified inventory.

Coverage should always refer to the user's complete shopping list, not only to a single product category.

Language should be simple, honest, and easy to understand.

Preferred wording:

- Likely here
- Recommended Store
- Another store may be needed

Avoid:

- 100% Match
- Best
- Available

unless the information has been verified.

**Status**

Approved

## 2026-07-20

### Trustworthy Store Recommendations

**Category**

Product

**Applies From**

Beta 1.0.1

**Decision**

Store recommendations must communicate estimated product coverage without implying verified inventory.

Coverage must always refer to the user's complete shopping list.

Preferred wording:

- Recommended Grocery Store
- Likely here
- Other items
- Some items may require another store

Avoid:

- Best
- 100% Match
- Available

unless inventory has actually been verified.

**Reason**

Accurate language builds long-term user trust and better reflects the current capabilities of WayTask.

**Status**

Approved
