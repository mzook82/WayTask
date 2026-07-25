# WT-023B — Product Search UX Contract

**Version:** 1.0
**Status:** Ready for implementation
**Scope:** Product and UX behavior only; no production implementation
**Last updated:** 2026-07-24
**Related implementation plan:** `docs/Implementation/WT-023A_ProductSearchFoundation_Plan.md`

---

## 1. Executive Summary

This document defines the complete Phase 1 user-experience contract for local
Product Knowledge search inside WayTask's Add Product flow. It translates the
deterministic search behavior approved in WT-023A into visible interaction
rules without implementing search, autocomplete, persistence integration, or
UI.

The contract has four central decisions:

- Search begins after one normalized Hebrew or English character.
- An empty query shows no suggestions and no recent products.
- A catalog suggestion is selected explicitly and is never saved
  automatically.
- A valid typed name always retains an explicit custom-product path, even when
  catalog results are present or Product Knowledge is unavailable.

Suggestions are local, immediate, stable, and capped at eight. Each row uses
the application language for the primary product name and category. When the
matched catalog name differs from the primary display name, the matched name is
shown as a compact secondary recognition cue. Product IDs, ranking internals,
and technical errors are never visible.

WT-023B does not authorize catalog identity persistence. The current
user-owned `Product`, `ShoppingListEntry`, and legacy shopping models have no
Product Knowledge Product ID field. Catalog selection therefore remains
transient until a separately approved Smart Product Creation task defines and
implements stable Product ID plus display-name snapshot persistence.

## 2. Product Goal

The primary goal is:

> A user should be able to add a common catalog product in less than five
> seconds.

The experience should require little typing while preserving deliberate user
choice:

- the name field is focused when Add Product opens;
- useful local suggestions appear after one meaningful character;
- a result can be recognized from its name, category, and semantic icon;
- selecting a result prepares a review state;
- the user confirms with the existing Add Product action;
- an unknown product is never blocked by catalog coverage.

The same interaction contract applies to Hebrew and English. Network, AI,
barcode, fuzzy matching, and user-history signals are outside this phase.

Success means speed without surprise. The top row may be likely, but it is
never auto-selected, and keyboard submission never silently creates a product.

## 3. User Journey

### 3.1 Known catalog product

```text
Open Add Product
  -> name field receives focus and keyboard opens
  -> user types one or more characters
  -> local catalog suggestions appear
  -> user explicitly taps one suggestion
  -> localized name, category, and semantic icon appear in a selected summary
  -> user confirms with Add Product
  -> product is added
```

Selection and confirmation are separate actions. This prevents an accidental
row tap or Return key press from saving.

### 3.2 Unknown custom product

```text
User types a valid name
  -> no suitable catalog result exists, or the user rejects the results
  -> WayTask shows Add "<typed text>" as a custom product
  -> user explicitly chooses the custom action
  -> the existing manual name and photo state is preserved
  -> user confirms with Add Product
  -> the existing manual-product save path continues
```

The custom action is present for every valid nonempty query, not only for zero
results. A catalog suggestion can therefore never trap the user in an incorrect
choice.

### 3.3 Responsibility by phase

| Journey step | Owning phase |
|---|---|
| Define activation, rows, states, copy, accessibility, and interactions | WT-023B |
| Normalize, match, rank, deduplicate, and return bounded result values | Future Search Implementation following WT-023A |
| Render suggestions, selected state, custom action, and keyboard behavior | Future Autocomplete UI |
| Persist stable catalog Product ID plus user-visible name snapshot | Future Smart Product Creation |
| Continue saving an unknown name through current `addManualProduct` behavior | Existing manual flow, later exposed by Autocomplete UI |

The complete known-product journey cannot ship as catalog-linked persistence
until the final integration phase is approved. WT-023B specifies the intended
experience but does not collapse these approval gates.

## 4. Search Activation Rules

### 4.1 Minimum query

Suggestions activate after one normalized letter or decimal digit.

- Hebrew and English use the same one-character minimum.
- A one-character query is allowed.
- No script-specific delay or threshold is applied.
- Punctuation and combining marks that normalize away do not activate search.

This rule uses WT-023A normalization. It does not use the raw Swift `String`
count.

### 4.2 Empty query

An empty query shows:

- the focused name field;
- the existing photo action and form guidance;
- no catalog suggestion rows;
- no recent or frequent products;
- no custom-product action;
- a disabled Add Product button.

Recent and frequent products are not approved for this phase. The proposed
recent-product behavior in the broader Smart Product Creation document is
superseded for this Phase 1 contract.

### 4.3 Whitespace-only and normalization-empty queries

A whitespace-only query behaves exactly like an empty query. Search is not
called, suggestions are cleared, the custom action is hidden, and Add Product
remains disabled.

A raw query that becomes empty under search normalization also returns no
catalog suggestions. Custom-product validity remains governed by the current
manual validation contract: leading and trailing whitespace/newlines are
trimmed, and the remaining name must be nonempty. WT-023B does not introduce a
new name-length or punctuation restriction.

### 4.4 Clearing

Clearing the name field immediately:

- cancels or invalidates outstanding search work;
- removes all suggestion and search-status rows;
- removes any custom-product action;
- clears a selected catalog result;
- returns focus to the empty name field;
- disables Add Product.

A selected user photo is preserved when only the name is cleared. Closing the
sheet continues to reset the whole current form.

### 4.5 Query changes

Every change that produces a different normalized query starts a new local
search. Repeated raw edits that normalize to the same query do not need to
re-search. Results from an older query must never reappear over a newer query.

## 5. Suggestion Presentation

### 5.1 Row contents

Each catalog suggestion row contains:

1. the semantic category icon;
2. the product display name resolved for the application locale;
3. the localized category label;
4. the matched catalog name only when it differs from the primary display
   name.

Standard same-language row:

```text
[icon]  Paper Towels
        Household
```

Cross-language or alias row:

```text
[icon]  חלב
        Milk · מוצרי חלב ותחליפים
```

```text
[icon]  Paper Towels
        Kitchen Paper · Household
```

The matched name is a recognition aid, not a technical “match reason.” Labels
such as “alias,” “exact,” “prefix,” score values, and Product IDs are not shown.

### 5.2 Deliberately omitted row content

Phase 1 does not show:

- a second translated name when it did not cause the match;
- brand, package, size, barcode, or subtype;
- match-type badges;
- ranking position or confidence;
- recent/frequent badges;
- highlighted matched characters.

Matched-text highlighting is omitted because it adds little recognition value
for a 15-product local catalog and becomes difficult to communicate
consistently across aliases, normalization, mixed scripts, RTL, and VoiceOver.
The optional matched-name line carries the useful context.

### 5.3 Result count and scrolling

- At most eight catalog suggestions are presented.
- The custom-product action is not counted as a catalog result.
- The suggestion area participates in the sheet's vertical scrolling.
- No pagination, “show more,” or infinite scroll exists in Phase 1.
- If the keyboard, Dynamic Type, or medium sheet detent prevents all rows from
  fitting, the user can scroll without dismissing the keyboard.

The custom-product action follows the catalog rows and remains in the same
scrolling content.

### 5.4 Row dimensions and interaction

- Every row has a minimum height of 56 points.
- Every row provides at least a 44-by-44-point activation target.
- The whole row, not only the text or icon, is tappable.
- Rows use visible separation and pressed/focused feedback.
- Dynamic Type may increase row height; text must not be forced into 56 points.

### 5.5 Loading perception

Normal local search displays no spinner, skeleton, progress bar, or “loading”
row. Results should feel like an immediate continuation of typing.

If a query has not completed after 150 milliseconds, show a small,
non-blocking status:

- English: `Searching products…`
- Hebrew: `מחפש מוצרים…`

The custom-product action remains available while that status is shown. The
status disappears when current-query results arrive or an unavailable state is
entered.

### 5.6 Duplicate-looking rows

The same catalog `ProductID` appears at most once even when canonical,
localized, and alias names all match. The row may mention the selected
matched-name cue, but it is still one product.

Two distinct Product Concepts may both appear when they legitimately match.
They must be distinguishable by display name, matched name, or category. A
future catalog must not ship two user-indistinguishable concepts with identical
display and category text; raw IDs are not an acceptable UI distinguisher.

## 6. Localization and RTL

### 6.1 Primary display language

The primary row name always follows the effective application locale, not the
query script:

1. exact application locale;
2. application primary language;
3. English;
4. catalog default name.

The category uses the effective application language, then English, then a
safe generic localized label. Category IDs are never displayed.

### 6.2 Hebrew application

In a Hebrew interface:

- the primary product name is Hebrew when available;
- the category is Hebrew;
- a matched English canonical name or alias is shown on the secondary line
  when it differs from the Hebrew primary name;
- the row and list use right-to-left layout.

Example: typing `milk` presents `חלב` as the primary name and `Milk · מוצרי חלב
ותחליפים` as secondary context.

### 6.3 English application

In an English interface:

- the primary product name is English;
- the category is English;
- a matched Hebrew display name or alias is shown on the secondary line when
  it differs from the English primary name;
- the row and list use left-to-right layout.

Example: typing `חלב` presents `Milk` as the primary name and `חלב · Dairy &
Alternatives` as secondary context.

### 6.4 Cross-language matching

All approved canonical, localized-display, and alias records are searchable
regardless of application language. A query does not change the interface
language and does not create a second row for the same product.

There is no automatic transliteration. A term in another script matches only
when that exact script is represented by a catalog name or approved alias.

### 6.5 Aliases and borrowed terms

When an alias caused the match and differs from the app-language display name,
the alias is shown on the secondary line. It retains the catalog's reviewed
spelling and capitalization.

Borrowed, brand-like, and foreign terms are not title-cased, translated, or
corrected by the UI. The Phase 1 catalog contains generic Product Concepts and
does not treat a brand as an alias for a generic concept.

### 6.6 Bidirectional layout

- The semantic icon occupies the visual leading edge: right in RTL, left in
  LTR.
- Text aligns to the natural leading edge.
- Product and category strings preserve their own Unicode direction.
- Mixed-language secondary text must isolate the matched-name and category
  runs so punctuation does not reorder them.
- Row ordering is unchanged by layout direction.
- User-entered text is never manually reversed.

## 7. User-Facing Ranking Contract

WT-023A's match-quality-first tuple is authoritative. “Alias” and
“cross-language” are not separate match types placed after all prefix matches;
they are name-source and locale dimensions within each match-quality tier.

### 7.1 Visible priority tiers

Results are ordered in these tiers:

1. exact normalized matches;
2. full-name prefix matches;
3. contiguous word-prefix matches.

Within each tier:

1. the app-locale resolved display name;
2. another preferred canonical or localized-display name;
3. another canonical or localized-display name;
4. an alias.

Within the same quality and name authority:

1. exact application locale;
2. same primary language;
3. English fallback;
4. another locale.

Remaining ties use:

1. the earlier matching word;
2. the shorter normalized matched name;
3. stable normalized scalar order;
4. normalized app-language display-name scalar order;
5. stable Product ID.

These final tie-breakers are invisible but make the ordering repeatable.

### 7.2 Exact alias versus display prefix

Yes: an exact approved alias outranks a display-name prefix because exact match
quality is evaluated before name authority.

Example:

- an exact `Kitchen Paper` alias match for Paper Towels ranks ahead of another
  product that only begins with `Kitchen Paper...`;
- within two exact matches, a display/canonical record ranks above an alias.

This is deterministic and understandable: what the user fully typed is a
stronger signal than a different name that merely begins the same way.

### 7.3 Cross-language expectation

A strong exact match in another language can outrank a weaker prefix in the
application language. Locale is a tie-break within equal match quality and name
authority; it does not erase a clear exact match.

### 7.4 No usage-based movement

Recency, frequency, Product Library membership, current time, and network
signals do not affect Phase 1 order. Identical inputs and catalog revision
produce identical ordered rows.

## 8. Selection Behavior

### 8.1 Explicit selection

Tapping a catalog row:

- selects that one Product Concept;
- closes the suggestion list;
- dismisses the software keyboard;
- replaces results with a compact selected-product summary;
- fills the visible name with the app-language catalog display name;
- applies category text and the semantic category icon to transient form
  state;
- preserves an already selected user photo;
- enables Add Product.

Selection does not save or dismiss the sheet.

### 8.2 Selected summary

The summary displays:

- semantic icon, or the selected user photo when one exists;
- localized product display name;
- localized category;
- a `Change` action.

Taxonomy version 1.0 has no canonical subcategory, so no subtype or subcategory
is invented.

### 8.3 Changing selection

`Change`:

- restores the preselection query;
- clears the selected Product Concept;
- restores the suggestion list for that query;
- refocuses the name field and reopens the keyboard.

The user may then select another catalog result, alter the query, or choose the
custom-product action.

### 8.4 Name editing

While a catalog result is selected, its display name is not edited inline.
Editing begins through `Change`, which intentionally clears catalog selection.
This prevents an edited visible name from appearing to remain safely linked to
a different canonical concept.

A future user-visible name-override feature requires its own persistence and
identity contract.

### 8.5 Persistence boundary

WT-023B selection is a transient UX state. It does not create, modify, or copy a
catalog `ProductEntity`.

The current `Product` persistence model has no catalog Product ID reference.
Therefore:

- Future Search Implementation only returns read-only results.
- Future Autocomplete UI may render and select those results.
- A production catalog-selection save must wait for Future Smart Product
  Creation to store a stable catalog Product ID and a user-visible display-name
  snapshot.
- Until that integration is approved, no UI may claim that a manually saved
  `Product` is linked to Product Knowledge.

Custom-product confirmation continues through the existing manual save path
and creates no `ProductEntity`.

## 9. Keyboard Behavior

### 9.1 Return in the name field

The future autocomplete field uses a Search submit action. Pressing Return:

- never auto-selects the top suggestion;
- never saves a catalog or custom product;
- commits the current text as the active search query;
- dismisses the software keyboard;
- leaves current suggestions and the custom-product action available.

Selection always requires an explicit row or custom-action activation.

Today, before autocomplete exists, `ProductListView` uses Return to submit the
current manual product. WT-023B does not alter that production behavior. The
Return-key contract above replaces it only when the separately approved Future
Autocomplete UI is implemented together with the explicit catalog/custom
selection states.

### 9.2 Empty or invalid query

When the query is empty or whitespace-only:

- Return performs no product action;
- no suggestion or custom option is selected;
- Add Product remains disabled.

### 9.3 Add Product button

Add Product is enabled only after either:

- a catalog suggestion has been explicitly selected; or
- the custom-product action has been explicitly selected for a currently valid
  manual name.

Typing alone does not trigger a save in the future autocomplete flow. A
disabled button must remain visibly and semantically disabled.

Until that future UI is implemented, the current button continues to use its
existing trimmed-nonempty validation and manual save behavior.

### 9.4 Keyboard after selection and save

- Explicit suggestion or custom selection dismisses the keyboard.
- `Change` restores focus and reopens it.
- Successful save dismisses the sheet through the current success behavior.
- Save failure keeps the sheet and all input; the keyboard remains in its
  pre-save state and can be restored by focusing the editable field.

### 9.5 Hardware keyboard

When hardware keyboard navigation is available:

- Tab or directional navigation can move focus among result rows, the custom
  action, Change, and Add Product;
- Return or Space activates the focused row but does not perform the later Add
  Product confirmation;
- Return in the text field follows the search behavior above;
- a visible focus indicator is required.

## 10. No-Result and Custom-Product Behavior

### 10.1 Custom action availability

For every query that passes the current manual validation contract, show one
custom-product action after the catalog results. This includes:

- zero catalog results;
- one or more exact or prefix results;
- results the user considers irrelevant;
- Product Knowledge loading, search, or availability failure.

There is no separate “weak result” score in WT-023A. Every qualifying
exact/prefix result may be shown, and the always-present custom action is the
escape path.

### 10.2 Exact copy

English:

```text
Add “<trimmed typed text>” as a custom product
```

Hebrew:

```text
הוספת ״<הטקסט שהוקלד לאחר חיתוך רווחים>״ כמוצר מותאם אישית
```

Example:

```text
הוספת ״פודינג חלבון וניל״ כמוצר מותאם אישית
```

The user-visible typed text is quoted. Leading and trailing
whitespace/newlines are omitted; internal visible text is preserved.

### 10.3 No-result explanation

When there are no catalog rows, show:

- English: `No catalog match`
- Hebrew: `לא נמצא מוצר מתאים בקטלוג`

The explanation is secondary to the custom action and does not imply an error.

### 10.4 Invalid input

WT-023B preserves the current manual validity rule:

- input is trimmed of leading/trailing whitespace and newlines;
- an empty trimmed name is invalid;
- whitespace-only input cannot be added.

This documentation task does not add a new production length, punctuation, or
character-class validator. Any future validation expansion must preserve
entered text and receive separate approval.

### 10.5 Selecting and confirming custom creation

Tapping the custom action:

- enters a manual confirmation state;
- keeps the trimmed typed name;
- preserves the selected photo;
- clears any catalog selection;
- dismisses the keyboard;
- enables Add Product.

The custom action itself does not save. Add Product remains the explicit second
confirmation and calls the existing manual-product behavior.

## 11. Ambiguous and Partial Match Behavior

### 11.1 Multiple products with a shared prefix

All qualifying distinct products may appear, up to eight. The search ranking is
stable, but the top result is not treated as automatically correct. The user
must explicitly select a row.

Examples:

- `to` returns Tomato before Toothpaste because both are display-name prefixes
  and Tomato has the shorter normalized matched name.
- `מג` returns Paper Towels and Baby Wipes as distinct category-labeled rows.

### 11.2 Broad concepts and subtypes

A broad Product Concept and a subtype are distinct identities when both are
approved catalog entries. One must not be silently treated as the alias of the
other.

The current pilot deliberately does not treat:

- Whole Wheat Bread as Bread;
- Instant Coffee as Coffee;
- White Rice as Rice;
- Mixed Frozen Vegetables as Frozen Vegetables.

If the user types one of those longer subtype names today, the custom-product
action is offered rather than forcing the broad concept.

### 11.3 Alias results

An alias match returns the owning Product Concept once. If the alias differs
from the app-language primary name, the alias appears as secondary recognition
text.

Example:

```text
Query: Kitchen Paper
Result: Paper Towels
Secondary: Kitchen Paper · Household
```

### 11.4 Very short queries

One-character queries are valid and may be broad. Up to eight deterministic
rows are shown. The UI does not claim that the top row is a confident
selection, and Return never chooses it.

### 11.5 Unexpected results

The UI does not hide technically valid WT-023A matches using an undefined
confidence threshold. The user can:

- continue typing;
- clear the query;
- select another row;
- use the custom action.

No result is silently substituted.

### 11.6 Brand-like input

The Phase 1 catalog contains generic concepts, not retail brands or packages.
A multiword brand-like query such as `Tnuva Milk` does not collapse to generic
Milk unless that full expression becomes an approved alias in a later catalog
revision. The current behavior is custom-product fallback.

## 12. Error and Recovery States

### 12.1 Catalog load failure

If the bundled Product Knowledge catalog cannot load:

- keep the name field and existing manual form usable;
- preserve all typed text and selected photo;
- show no stale catalog rows;
- show the custom-product action for a valid name;
- do not disable or delay manual confirmation;
- record technical diagnostics outside the user interface.

User copy:

- English: `Product suggestions are unavailable. You can still add this
  product manually.`
- Hebrew: `הצעות למוצרים אינן זמינות כרגע. עדיין אפשר להוסיף את המוצר ידנית.`

### 12.2 Search error

An internal current-query search error uses the same nontechnical unavailable
copy and manual fallback. The next normalized query may retry search. A failed
query must not clear text, photos, or a manually selected confirmation state.

### 12.3 Temporarily unavailable

Temporary unavailability never produces a blocking retry screen. Manual entry
is the primary recovery path. If suggestions become available during the same
editing session, a later query may show them normally; the UI must not replace
an already selected custom confirmation state without user action.

### 12.4 Slow search

After 150 milliseconds, show the non-blocking Searching products status from
Section 5. The user can continue typing or select the custom action without
waiting. Old-query rows are not interactive for the new query.

### 12.5 Existing manual save failure

Preserve the current reliability contract:

- keep the sheet open;
- preserve the name, photo, and selected/custom state;
- report the persistence failure to diagnostics;
- show a user-facing alert;
- allow retry;
- dismiss only after a successful save.

Current user-facing copy remains:

```text
Product wasn’t saved
Couldn’t save this product. Please try again.
```

No catalog or search error should be presented as a save failure, and no
technical error description is shown to the user.

## 13. Accessibility

### 13.1 Touch and focus

- Suggestion and custom-action rows have at least a 44-by-44-point touch
  target.
- Standard suggestion rows are at least 56 points high before Dynamic Type
  expansion.
- The whole row is interactive.
- Visible keyboard and assistive-technology focus indicators are required.

### 13.2 VoiceOver

Each suggestion is one coherent accessibility element. The label follows:

```text
<primary product name>, <category>
```

When a different name caused the match:

```text
<primary product name>, <category>, matched as <matched name>
```

Localized Hebrew equivalents are used in a Hebrew interface. The row has the
Button trait. No rank score, Product ID, or implementation match kind is
announced.

After selection, announce:

```text
<product name> selected, <category>. Add Product to confirm.
```

The custom action reads its full quoted name. A disabled Add Product button is
announced as disabled.

### 13.3 Icon ownership

The icon is decorative because the adjacent product and category text owns the
meaning. Hide the icon from assistive technology to prevent duplicate or
platform-specific symbol announcements. Icon color or shape is never the only
category or selection indicator.

### 13.4 Dynamic Type

- Rows grow vertically.
- Product names and the only distinguishing secondary text may wrap.
- The category must not be permanently truncated when it is the only
  differentiator.
- The results region remains scrollable.
- Text does not overlap the icon, custom action, or selection controls.

### 13.5 RTL and bidirectional text

The RTL rules in Section 6 apply at every Dynamic Type size and under
VoiceOver. The reading order is primary name, matched name when present,
category, then action semantics. Mixed English/Hebrew runs must not cause
punctuation or quoted custom names to be announced in the wrong order.

### 13.6 Enabled, disabled, and selected states

Enabled versus disabled and selected versus unselected states use more than
color:

- opacity/color plus control semantics for disabled state;
- summary replacement and accessible selected announcement for selection;
- visible pressed/focus feedback for rows.

## 14. Performance Perception

### 14.1 User-facing target

For the Phase 1 15-product catalog, suggestions should appear without visible
loading. Search must not freeze typing, delay focus, move the cursor, or close
the keyboard.

WT-023A's technical expectations remain the source of truth:

- warm search p95 at 15 products: at most 2 ms;
- warm search p95 at 100 products: at most 5 ms;
- warm search p95 at 500 products: less than 20 ms;
- at most eight results presented.

### 14.2 Debounce decision

Phase 1 uses no artificial debounce: **0 milliseconds**.

Justification:

- the catalog is local and small;
- the search operation is bounded and actor-isolated;
- a debounce would consume a meaningful share of the five-second goal;
- WT-023A already requires cancellation/stale-result protection at the
  integration boundary.

### 14.3 Rapid input and deletion

- Every changed normalized query starts immediately.
- Older work is canceled when possible and always logically invalidated.
- Only the latest query may update rows.
- Input remains editable while search runs.
- Rapid deletion updates against the shorter latest query.
- Deletion to empty clears all search state immediately.
- A repeated equivalent normalized query does not cause visible flicker.

### 14.4 Activity indicators

There is no spinner for normal local search. The 150-millisecond text status is
an exceptional perception aid, not a reason to block input or hide the custom
action.

## 15. Search Acceptance Examples

The expected top result is written in the application display language.
Parenthetical text identifies a different matched catalog name when it should
appear as secondary row context.

| Query | App Language | Expected Top Result | Other Expected Results | Match Type | Notes |
|---|---|---|---|---|---|
| `חלב` | Hebrew | חלב | None | Exact localized display | Standard Hebrew exact match. |
| `Milk` | English | Milk | None | Exact canonical | English comparison is case-insensitive. |
| `חָלָב` | Hebrew | חלב | None | Exact localized display after normalization | Niqqud is ignored by WT-023A normalization. |
| `mil` | English | Milk | None | Full-name prefix, canonical | Approved short English search example. |
| `ביצי` | Hebrew | ביצים (`ביצי תרנגולת`) | None | Full-name prefix, alias | Alias identifies Eggs; no duplicate row. |
| `dishw` | English | Dish Soap (`Dishwashing Liquid`) | None | Full-name prefix, alias | Approved alias prefix. |
| `soap` | English | Dish Soap | None | Word prefix, canonical | Matches the second word of `Dish Soap`. |
| `towels` | English | Paper Towels | None | Word prefix, canonical | Matches the second canonical-name word. |
| `נייר ס` | Hebrew | מגבות נייר (`נייר סופג`) | None | Full-name prefix, alias | Alias remains secondary recognition text. |
| `אוכל ל` | Hebrew | מזון לכלבים (`אוכל לכלבים`) | None | Full-name prefix, alias | Dog Food remains one Product Concept. |
| `ירקות ק` | Hebrew | ירקות קפואים | None | Full-name prefix, localized display | Frozen Vegetables, not fresh produce. |
| `עגבניה` | Hebrew | עגבנייה (`עגבניה`) | None | Exact alias | Approved Hebrew orthographic alias. |
| `Tooth Paste` | English | Toothpaste (`Tooth Paste`) | None | Exact alias | Spacing alias outranks prefix matches. |
| `Washing-Up` | English | Dish Soap (`Washing-Up Liquid`) | None | Full-name prefix, alias | Hyphen normalizes to a word separator. |
| `Kitchen` | English | Paper Towels (`Kitchen Paper`) | None | Full-name prefix, alias | No separate Kitchen Paper product row. |
| `milk` | Hebrew | חלב (`Milk`) | None | Exact canonical, cross-language | UI stays Hebrew; English matched name is secondary. |
| `חלב` | English | Milk (`חלב`) | None | Exact localized display, cross-language | UI stays English; Hebrew matched name is secondary. |
| `coffee` | Hebrew | קפה (`Coffee`) | None | Exact canonical, cross-language | Query script does not change UI language. |
| `קפה` | English | Coffee (`קפה`) | None | Exact localized display, cross-language | One Product ID, one row. |
| `to` | English | Tomato | Toothpaste | Ambiguous full-name prefix | Both are display names; shorter matched name ranks first. |
| `מג` | Hebrew | מגבות נייר | מגבונים לתינוקות | Ambiguous full-name prefix | Household and Baby category labels distinguish the rows. |
| `w` | English | Water | Dish Soap (`Washing-Up Liquid`) | One-character full-name prefix | Display-capable Water outranks alias-matched Dish Soap. |
| `מ` | Hebrew | מים | מגבות נייר; מזון לכלבים; משחת שיניים; מגבונים לתינוקות | One-character full-name prefix | Broad but deterministic; Water has the shortest matched display name. |
| `liquid` | English | Dish Soap (`Dishwashing Liquid`) | None | Word prefix, alias | Multiple aliases for one product are deduplicated. |
| `Frozen Veg` | English | Frozen Vegetables (`Frozen Veg`) | None | Exact alias | Alias maps to the approved frozen concept. |
| `Tnuva Milk` | English | No catalog result | Custom product action | No match | Brand-like text is not forced to generic Milk. |
| `Whole Wheat Bread` | English | No catalog result | Custom product action | No match | A subtype is not an alias for Bread. |
| `ilk` | English | No catalog result | Custom product action | No match | No substring, fuzzy, or typo correction. |
| `פודינג חלבון וניל` | Hebrew | No catalog result | Custom product action | No match | Explicitly a custom example; not in the pilot catalog. |
| `Protein Vanilla Pudding` | English | No catalog result | Custom product action | No match | Explicitly a custom example; not in the pilot catalog. |
| `␠␠␠` | English | No results | None | Empty after trimming/normalization | No custom action; Add Product remains disabled. |

Every catalog result above exists in catalog revision 1. Rows explicitly marked
No catalog result are intentional custom-product acceptance cases, not invented
catalog content.

## 16. Interaction Scenarios

### Scenario A — Common catalog product

1. The user opens Add Product.
2. The name field receives focus and the keyboard opens.
3. The user types `mil`.
4. Milk appears first without a visible loading indicator.
5. The row shows Milk, Dairy & Alternatives, and the dairy semantic icon.
6. The user taps Milk.
7. The suggestion list closes, the keyboard dismisses, and a selected Milk
   summary appears.
8. The user taps Add Product.
9. Once Future Smart Product Creation persistence is approved, the saved
   user-owned record retains the stable catalog identity and display-name
   snapshot. Before that phase, no linked catalog save may be implied.

### Scenario B — Unknown custom product

1. The user types `Protein Vanilla Pudding`.
2. No catalog result is forced.
3. The UI shows `No catalog match`.
4. The UI shows `Add “Protein Vanilla Pudding” as a custom product`.
5. The user taps the custom action.
6. The name and any selected photo remain intact.
7. The user taps Add Product.
8. The existing manual-product save path runs.

### Scenario C — Cross-language search

1. The application interface is Hebrew.
2. The user types `milk`.
3. One Milk concept appears as `חלב`.
4. `Milk · מוצרי חלב ותחליפים` appears as secondary context.
5. The product is not duplicated by its Hebrew and English name records.
6. Selection and confirmation remain explicit.

The reciprocal English-interface/`חלב` behavior follows the same rule.

### Scenario D — Product Knowledge unavailable

1. The catalog fails to load or current-query search reports failure.
2. The name and photo remain untouched.
3. The UI explains in nontechnical language that suggestions are unavailable.
4. The custom-product action remains available for a valid name.
5. The user selects custom and confirms through Add Product.
6. The current manual save remains fully usable.

### Scenario E — Ambiguous prefix

1. The user types `to`.
2. Tomato and Toothpaste appear in stable order.
3. Each row has its category and semantic icon.
4. Neither row is auto-selected.
5. Return does not choose Tomato.
6. The user explicitly taps the intended product, continues typing, or chooses
   the custom action.

## 17. Future Measurement Plan

No analytics code is authorized by WT-023B. A later, separately reviewed
analytics task may measure:

| Metric | Product question |
|---|---|
| Time from Add Product open to successful addition | Are common products added within five seconds? |
| Query length at catalog selection | How much typing is required? |
| Catalog-selection rate | How often does the pilot catalog satisfy intent? |
| Custom-product rate | How often is manual fallback used? |
| No-result rate | Where is catalog coverage missing? |
| Suggestion abandonment rate | Do users leave after seeing results? |
| Rank of selected suggestion | Is user-facing ordering useful? |
| Product Knowledge unavailable rate | Is local catalog reliability acceptable? |
| Top missing queries | Which concepts may merit governed catalog review? |

### Privacy requirements

- Prefer on-device aggregation.
- Do not collect photos, barcodes, free-form notes, or product form contents.
- Do not transmit raw custom-product names or raw no-result queries by default.
- Query length, result count, selected catalog Product ID, timing bucket, and
  language may be measured without raw text when consent and product policy
  permit.
- “Top missing queries” must remain on-device unless a separately approved,
  consented, frequency-thresholded, and redacted collection design exists.
- Analytics must not alter ranking, availability, or save behavior.

## 18. Phase Boundaries

### WT-023B

Defines:

- activation and empty-query rules;
- suggestion content and localization;
- user-facing ranking expectations;
- selection, keyboard, custom fallback, error, accessibility, and performance
  behavior;
- acceptance examples and measurement recommendations.

Creates documentation only.

### Future Search Implementation

Implements the WT-023A contract:

- normalization;
- exact/full-prefix/word-prefix matching;
- alias and localized-name matching;
- stable ranking and duplicate suppression;
- result models, bounded API, actor safety, and tests.

It does not render UI or save products.

### Future Autocomplete UI

Implements:

- search-field query lifecycle;
- rows and scrolling;
- localized and RTL presentation;
- selected summary and Change behavior;
- custom action;
- keyboard, error, loading, and accessibility states.

It must not silently modify existing persistence or claim catalog linkage.

### Future Smart Product Creation

Defines and implements:

- composition of catalog search with Add Product;
- stable Product ID plus display-name snapshot persistence;
- mapping of selected category/icon into user-owned state;
- known-product duplicate policy;
- transaction and migration behavior.

It must preserve the current manual/custom path and existing shopping-item
storage until an explicit persistence change is approved.

## 19. Risks and Mitigations

### Old proposal suggests recents before typing

Risk: the broader Smart Product Creation proposal describes recent/frequent
rows, but WT-023A has no usage input and specifies empty results.

Mitigation: WT-023B explicitly defines no recent products and no empty-query
suggestions for Phase 1.

### Exact alias feels surprising

Risk: an exact alias may appear above a prefix on another display name.

Mitigation: show the matched alias as secondary context and document that exact
text outranks partial text.

### Cross-language result looks unrelated

Risk: the app-language primary name may not resemble what the user typed.

Mitigation: show the different matched catalog name on the secondary line while
keeping the primary UI language predictable.

### One-character results are broad

Risk: several plausible products may appear.

Mitigation: cap at eight, keep stable ordering, show categories, require
explicit selection, and never bind Return to the top result.

### Catalog selection implies unsupported persistence

Risk: users or implementers may assume a selected concept is stored when the
current `Product` model has no catalog reference.

Mitigation: keep selection transient and gate production catalog-linked saving
on Future Smart Product Creation.

### Custom fallback becomes hidden

Risk: valid catalog rows could make users believe they must choose one.

Mitigation: show the quoted custom action for every valid query, including
queries with results and failure states.

### Stale results can be selected

Risk: rapid typing could leave rows from an older query.

Mitigation: invalidate older work immediately and permit only the latest
normalized query to update interactive rows.

### Dynamic Type and RTL reduce recognition

Risk: secondary language/category text may truncate or reorder.

Mitigation: allow row growth and wrapping, isolate bidirectional runs, maintain
natural alignment, and test Hebrew at accessibility sizes.

## 20. UX Approval Checklist

| # | Approval requirement | Result | Evidence |
|---:|---|---|---|
| 1 | Common products can be found with minimal typing. | PASS | Search begins after one normalized character; examples cover short prefixes. |
| 2 | Hebrew behavior is defined. | PASS | Activation, normalization expectation, copy, rows, RTL, and examples are explicit. |
| 3 | English behavior is defined. | PASS | Case-insensitive activation, copy, rows, and examples are explicit. |
| 4 | Cross-language behavior is defined. | PASS | App-language primary name plus different matched-name secondary cue. |
| 5 | Ranking is deterministic. | PASS | WT-023A quality, authority, locale, scalar, and ID order is preserved. |
| 6 | Duplicate rows are prevented. | PASS | One row per ProductID; distinct concepts require visible differentiation. |
| 7 | No-result behavior is defined. | PASS | Exact English/Hebrew status copy and state behavior are specified. |
| 8 | Custom-product fallback is always available. | PASS | One quoted custom action appears for every valid query and failure state. |
| 9 | Keyboard behavior avoids accidental creation. | PASS | Return never selects the top row or saves; explicit activation and Add are required. |
| 10 | Selection behavior preserves current persistence constraints. | PASS | Selection is transient; Product ID persistence remains a later gate. |
| 11 | Product Knowledge failure does not block manual creation. | PASS | Manual UI, text, photo, custom action, and save path remain available. |
| 12 | Accessibility requirements are defined. | PASS | Touch, VoiceOver, Dynamic Type, RTL, focus, and icon ownership are specified. |
| 13 | Performance expectations are defined. | PASS | Immediate local updates, zero debounce, stale-work rules, and 150 ms status are fixed. |
| 14 | Search examples are testable. | PASS | Thirty-one catalog, alias, language, ambiguity, and custom cases are tabulated. |
| 15 | Phase boundaries are explicit. | PASS | UX, search engine, autocomplete UI, and persistence integration are separate. |

All fifteen checks pass. No user-facing behavior in the WT-023B scope remains
materially ambiguous.

## 21. Final Decision

The activation, presentation, localization, ranking, selection, keyboard,
custom fallback, error recovery, accessibility, performance, and phase
boundaries are sufficiently specific for future implementation and acceptance
testing.

APPROVED UX CONTRACT FOR IMPLEMENTATION
