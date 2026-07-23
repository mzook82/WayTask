# WT-020 Smart Product Creation UX Specification

**Version:** 1.0  
**Status:** Proposed  
**Sprint:** WT-020  
**Phase:** Architecture and product design only  
**Related:** `docs/Audits/2026-07-23_WT-020_ProductAudit.md`

---

## 1. Experience Goal

Adding a known product should take a few characters and one selection. WayTask should use its local Product Knowledge database to supply a consistent name, category, subcategory, and meaningful icon while keeping the user in control of the final save.

The primary interaction is search, not form completion.

Target experience:

```text
Add Product
  -> search is focused
  -> user types
  -> local suggestions appear
  -> user selects a suggestion
  -> name, category, subcategory, and icon are resolved
  -> user saves
  -> product appears in the Product Library
```

Unknown products remain fully usable offline:

```text
User types a name
  -> no suitable match
  -> “Create <name>” appears
  -> WayTask applies deterministic local classification when confident
  -> user reviews optional details
  -> save creates local Product Knowledge and a library reference
```

---

## 2. UX Principles

1. **Search first.** The initial screen contains one dominant, focused search field.
2. **Local first.** Suggestions never wait for a network or AI provider.
3. **Progressive disclosure.** Category, subcategory, aliases, and advanced details are shown only when useful.
4. **One product language.** Manual, barcode, camera, and future voice flows resolve to the same product summary and save behavior.
5. **Review before commitment.** Suggested or enriched data is visible before save.
6. **Do not invent confidence.** Unknown products may remain Uncategorized when deterministic local classification is uncertain.
7. **Preserve intent.** A failed save never clears typed text or dismisses the screen.
8. **Accessible by construction.** Icons reinforce text; they never replace the product name or category label.

---

## 3. Information Architecture

### 3.1 Entry points

Smart Product Creation is available from:

- Products tab: Add.
- Products empty state: Add Product.
- Home shortcut: Add Product.
- Shopping “Choose Products” experience: Add New Product.
- Camera/barcode result: Create or save the resolved product.
- Future voice search.

All entry points open the same creation state machine. The caller supplies a destination:

- `libraryOnly` by default.
- `libraryAndShopping(listID)` when launched explicitly from Shopping.

The destination must be visible near the final action so a product is never added to Shopping unexpectedly.

### 3.2 Screen structure

From top to bottom:

1. Navigation title: Add Product.
2. Close action.
3. Focused product search field.
4. Contextual content:
   - Recent/frequent products before typing.
   - Ranked suggestions while typing.
   - Selected-product summary after selection.
   - Unknown-product action when no adequate match exists.
5. Optional advanced details.
6. Sticky primary save action once a product draft is valid.

---

## 4. Primary Known-Product Flow

### 4.1 Open

On presentation:

- Focus the search field.
- Open the keyboard.
- Show up to six local recent/frequent suggestions when the query is empty.
- Do not perform any network request.
- Announce “Search products” to assistive technology.

### 4.2 Type

After each meaningful query change:

- Normalize the query locally.
- Cancel any older in-flight local search.
- Refresh results within the target latency.
- Keep the keyboard focused.
- Preserve results while a newer query is being evaluated to avoid flicker.

Search begins after one meaningful character for prefix results. Partial/substring matching begins after at least two or three normalized characters, according to script and index configuration.

### 4.3 Suggestions

Show up to eight primary suggestions, followed by the Create action when appropriate.

Each suggestion row contains:

- Semantic icon.
- Display name.
- Category and optional subcategory.
- Optional brand or distinguishing variant detail.
- Optional “Recent” or “Frequent” signal.

Example:

```text
🥛  Milk
    Dairy • Milk

🥛  Oat Milk
    Dairy Alternatives • Oat

🥛  Almond Milk
    Dairy Alternatives • Almond

🥛  Lactose Free Milk
    Dairy • Lactose Free
```

Text matching the query may be visually emphasized, but the emphasis is not required for accessibility.

### 4.4 Select

Tapping a result:

- Selects its canonical Product Entity.
- Replaces the results list with a compact product summary.
- Keeps the original query available if the user chooses Change.
- Resolves display name, category, subcategory, and icon.
- Shows optional brand/variant information.
- Enables Save.

Selection does not save automatically in Phase 1. This prevents accidental additions and gives the user a predictable review point.

### 4.5 Save

The primary action reads:

- “Save Product” for library-only creation.
- “Save and Add to Shopping” when the flow was explicitly launched with a Shopping destination.

While saving:

- Disable repeated submission.
- Show inline progress.
- Preserve the selected summary.

On success:

- Provide a subtle haptic and accessible confirmation.
- Close the sheet.
- Return to the caller.
- Ensure the saved product is visible without requiring manual search/filter reset.

If the entity is already in the Product Library:

- Do not create a duplicate.
- Explain “Already in Products.”
- If the destination is Shopping and the product is not on that list, change the action to “Add to Shopping.”

---

## 5. Unknown-Product Flow

### 5.1 Create action

When no result meets the selection threshold, always retain an explicit action:

`Create “<trimmed user text>”`

This action is also available below weak results, so an incorrect suggestion never blocks manual creation.

### 5.2 Manual draft

The manual draft contains:

| Field | Requirement | Behavior |
|---|---|---|
| Product name | Required | Initialized from the search query |
| Category | Recommended | Filled by the deterministic local classifier when confidence is adequate |
| Subcategory | Optional | Filled only when the local taxonomy can resolve it |
| Icon | Automatic | Derived from subcategory/category; falls back to a generic product icon |
| Brand | Optional | Hidden under More Details |
| Photo | Optional | Hidden under More Details |
| Barcode | Optional | Pre-filled when creation began from a scan |
| Aliases | Not exposed in Phase 1 UI | Original query is retained as an alias if it differs from the final display name |

Category and subcategory may be changed by the user through taxonomy pickers. Free-text category entry is not part of the primary flow.

### 5.3 Local classification

Phase 1 classification is deterministic and offline:

- Exact/alias category keyword rules.
- Existing catalog relationships.
- Optional user confirmation.

If confidence is below the agreed threshold:

- Use Uncategorized.
- Show “Choose category” as a non-blocking recommendation.
- Never label a guessed category as certain.

### 5.4 Unknown save

Saving an unknown product:

1. Creates a local Product Entity.
2. Stores normalized search terms and the original query alias.
3. Creates or reuses the user’s Product Library reference.
4. Optionally links the entity to the destination Shopping list.
5. Updates the local search index transactionally.

The new product must appear in future suggestions immediately and without network access.

---

## 6. Changing a Selected Product

The selected summary provides:

- Change: returns to the previous query and results.
- Edit Details: opens optional user-editable fields.
- Remove photo: when a user image exists.

Editing a known catalog product creates a user override or alias; it must not destructively rewrite the shipped catalog name for every user or locale.

---

## 7. Input and Validation

### 7.1 Name rules

The application layer should:

- Trim leading/trailing whitespace.
- Collapse internal whitespace for the normalized search key while preserving the user-visible form.
- Reject an empty or control-character-only name.
- Set a practical display-name limit agreed by Product and Engineering.
- Preserve valid Unicode and right-to-left scripts.
- Avoid forcing title case because it damages brands, acronyms, and some languages.

### 7.2 Duplicate resolution

Before creating a new entity, resolve in order:

1. Exact external identifier, such as normalized barcode.
2. Existing selected entity ID.
3. Exact normalized canonical name or alias in the same locale and compatible category/brand.
4. High-confidence composite match.

Name-only ambiguous matches must be shown to the user, not silently merged.

### 7.3 Save failures

On persistence failure:

- Keep the sheet open.
- Preserve query, selection, draft fields, and photo.
- Show an actionable inline error or alert.
- Allow retry.
- Do not update success diagnostics or dismiss.

### 7.4 Photo failures

While a selected photo loads:

- Show a loading state.
- Either prevent save or clearly allow a name-only save by explicit choice.

If loading fails:

- Preserve the rest of the draft.
- Explain that the product can still be saved without the photo.

---

## 8. Search and Result States

| State | UI |
|---|---|
| Empty query | Recent and frequent local products |
| Searching | Existing results retained with subtle activity indicator if needed |
| Results | Ranked local suggestions plus optional Create action |
| No results | Create action and a short “No saved match” explanation |
| Selected | Product summary and Save |
| Already in library | Existing-state message; no duplicate save |
| Saving | Disabled action with progress |
| Save failed | Preserved draft plus Retry |
| Local database unavailable | Manual draft remains available; log diagnostic |

Online enrichment status is intentionally absent from the Phase 1 creation-critical path.

---

## 9. Icon Behavior

Icons use a semantic key resolved by each platform, for example `food.dairy.milk`.

Display precedence:

1. User-selected/local product image.
2. Curated product image if already local.
3. Semantic product/subcategory icon.
4. Category icon.
5. Generic product icon.

Emoji may be used as a content fallback, but the stored knowledge value is a semantic key rather than an Apple SF Symbol name or Android resource identifier.

---

## 10. Camera, Barcode, and Future Voice Consistency

Camera, barcode, AI, and voice inputs create a `ProductDraft` that enters the same selection/review/save state machine.

### Barcode

- Resolve local identifiers first.
- If a known entity is found, show the same selected-product summary.
- If unknown, pre-fill the scanned identifier in manual creation.
- Optional network lookup may enrich the draft but must not block local save.

### Camera

- A recognized result maps to an existing Product Entity when possible.
- Unknown recognition produces a reviewable draft.
- Recognition failure returns to text/manual creation with the image preserved.

### AI

- AI output is labeled as suggested.
- It cannot silently overwrite confirmed local knowledge.
- User confirmation promotes accepted fields into local knowledge.
- AI absence does not change the manual or known-product flow.

### Voice

- Voice text is treated as a search query.
- Suggestions and ambiguity are displayed using the same engine.
- Voice does not bypass review when multiple products match.

---

## 11. Accessibility and Localization

- Every suggestion exposes name, category, distinguishing detail, and selection state as one coherent accessibility element.
- Icons are decorative when adjacent text provides the meaning.
- Dynamic Type must not truncate the only distinguishing field.
- Rows provide at least the platform minimum touch target.
- Search and result order work in left-to-right and right-to-left layouts.
- Normalization preserves Hebrew, Arabic, and other scripts.
- Transliterated aliases may supplement native-script names but never replace them.
- Color is not the only indicator for selected, recent, or error states.

---

## 12. Performance Requirements

| Measure | Target |
|---|---|
| Search response at 500 entities | p95 under 20 ms on a supported device |
| Search response at 50,000 entities | p95 under 50 ms after index warm-up |
| First usable Add Product UI | No network dependency |
| Results returned | 8 primary, hard cap 20 from repository |
| Memory behavior | No loading all catalog entities or images for each query |
| Stale search | Older query results never replace newer results |

Targets must be verified with representative multilingual fixtures and release builds.

---

## 13. Phase 1 Acceptance Criteria

- Add Product opens with search focused.
- Known products appear from the local database as the user types.
- Prefix, partial token, and alias matches are supported.
- Selecting a suggestion fills canonical name, category, subcategory, and icon.
- Saving a known product does not duplicate the library entry.
- An unknown name can always be created offline.
- Unknown creation writes back to local Product Knowledge.
- Low-confidence classification falls back safely.
- Save failure preserves all user input.
- Camera and barcode outputs can enter the same Product Draft boundary.
- No Gemini, barcode-scanner, cloud, community, or machine-learning implementation is required for Phase 1.

---

## 14. Product Decisions Required Before Implementation

The following choices do not block the architecture, but should be approved before UI implementation:

- Final display-name length limit.
- Whether save occurs in one tap after selection or remains an explicit second tap. This specification recommends explicit Save for Phase 1.
- Number of initial recent/frequent suggestions.
- Category confidence threshold for unknown products.
- Whether user-created products default to private/local provenance in future sync.
- Whether multi-scan mode is part of a later scanner sprint.
