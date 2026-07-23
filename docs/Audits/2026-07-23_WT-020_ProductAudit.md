# WT-020 Product Audit

**Version:** 1.0  
**Status:** Complete  
**Audit date:** 2026-07-23  
**Scope:** Product creation, product data, product library, persistence, camera, barcode, AI recognition, and manual fallback  
**Source of evidence:** Effective local worktree at the audit date  

---

## 1. Executive Summary

WayTask already has more product structure than the original WT-020 problem statement implies. Products are not represented only as shopping-list strings. The current application has:

- A persistent `Product` library entity.
- Persistent `ShoppingListEntry` records that reference products.
- Legacy/compatibility `ShoppingItem` records used by shopping, planning, location, and memory features.
- A persistent `ProductKnowledge` cache.
- A persistent `ProductHistory` usage record.
- A transient `ProductCandidate` used by barcode, photo, and AI recognition.
- A local-first barcode cache followed by Open Food Facts and optional Gemini enrichment.

These are valuable foundations, but they do not yet form one canonical Product Knowledge Layer. Product identity, names, categories, search terms, and images are copied across several models. The knowledge cache supports exact barcode lookup only; it is not used for manual-entry autocomplete. Manual product creation creates a new library row on every save, requires a name, accepts an optional image, and does not classify or assign an icon.

The main WT-020 architectural need is therefore not to introduce the first product entity. It is to define one authoritative `ProductEntity`, move catalog knowledge behind a repository and indexed search boundary, and make library, shopping, camera, barcode, and future AI features reference that entity.

---

## 2. Audit Method and Evidence

The following implementation areas were traced:

| Area | Primary evidence |
|---|---|
| Product library UI and manual creation | `ProductListView.swift` |
| Persistent product and shopping models | `WayTask/Models.swift` |
| Product save and compatibility logic | `ShoppingListService.swift` |
| Product knowledge cache | `ProductKnowledge.swift`, `ProductKnowledgeService.swift` |
| Usage memory | `ProductHistory.swift`, `ShoppingMemoryService.swift` |
| Camera and manual barcode UI | `CameraView.swift` |
| Camera state and provider orchestration | `CameraViewModel.swift` |
| Barcode provider | `OpenFoodFactsProvider.swift` |
| AI provider | `GeminiProductRecognitionService.swift` |
| Recognition contracts | `ProductCandidate.swift`, `RecognitionResult.swift`, `ProductRecognitionService.swift` |
| Persistence registration and startup backfill | `WayTask/WayTaskApp.swift`, `WayTask/ContentView.swift` |
| Product thumbnails and search control | `WayTaskDesignSystem.swift` |

The audit did not modify source files. Pre-existing worktree modifications were treated as read-only evidence and preserved.

---

## 3. Current Product Creation

### 3.1 Entry points and navigation

The primary manual path is:

```text
Products tab
  -> bottom “Add” action
  -> “Add Product” modal sheet
  -> save
  -> sheet closes
  -> user remains on Products
```

The primary scanning path is:

```text
Products tab or Home
  -> Scan / camera action
  -> full-screen CameraView
  -> barcode/photo/AI result
  -> review or manual fallback
  -> save to Product Library
  -> scanner closes
```

`ProductListView` presents the manual form as a medium/large sheet. The product-name field is focused when the form appears. Closing the sheet clears its local form state.

### 3.2 Current manual UI

The standard Add Product sheet contains:

- Product name text field.
- Optional image chosen from the photo library.
- Informational copy explaining that the product is saved to the permanent Product Library before it is added to Shopping.
- Add Product button.
- Close button.
- Save-failure alert.

There is no category control, subcategory control, icon control, brand control, alias control, autocomplete list, recent-product list, or duplicate warning in this form.

### 3.3 Required and optional fields

| Field | Requirement | Current handling |
|---|---|---|
| Product name | Required | Trimmed before save; whitespace-only values are rejected |
| Photo | Optional | Loaded asynchronously from `PhotosPicker` into `Data` |
| Category | Not available in standard manual form | Saved as `nil` |
| Brand | Not available in standard manual form | Saved as `nil` |
| Icon | Not available | Generic `shippingbox` placeholder is used when no image exists |

The barcode manual-fallback form is different. It exposes:

- Product name: required.
- Brand: optional free text.
- Category: optional free text.
- Barcode: required implicitly because the form is reached from a confirmed scan.

### 3.4 Validation rules

Current standard manual validation consists of:

1. Trim leading/trailing whitespace and newlines.
2. Reject an empty result.
3. Disable and visually dim the Add Product button while invalid.
4. Allow the keyboard Done action to save when valid.

There is currently no:

- Maximum or minimum meaningful length.
- Duplicate detection.
- Unicode/control-character policy.
- Category validation.
- Image size validation at the form boundary.
- Normalized-name generation.
- Alias or keyword generation.

### 3.5 Save flow

`ProductListView.addItem()` calls `ShoppingListService.addManualProduct(...)`.

The service:

1. Creates a new `Product` with a random UUID.
2. Stores the trimmed name and optional image data.
3. Sets source to `manual`.
4. Inserts the product into the SwiftData model context.
5. Saves the context.

On success, the view:

- Records a beta diagnostic.
- Signals that product/shopping state changed.
- Marks any generated shopping plan stale.
- Clears the form.
- Dismisses the sheet.

On failure, the view:

- Captures a persistence report through the Sentry boundary.
- Keeps the form open and preserves entered state.
- Shows a retry-oriented alert.

The standard manual save does **not** directly create or update `ProductKnowledge`. A manually created library product can reach Product Knowledge later when it is added to Shopping and converted into a compatibility `ShoppingItem`.

### 3.6 Manual-save observations

- Every successful manual save inserts a new `Product`, even when an equivalent product already exists.
- The optional photo is loaded asynchronously. The form has no loading state that prevents a save before photo loading completes.
- The method marks the shopping plan stale even though the new product is saved only to the library and is not automatically added to Shopping.
- `selectedLocationID` remains in form state and reset logic, but the current standard form does not expose a location selector or use it during `addManualProduct`.

---

## 4. Current Product and Knowledge Models

### 4.1 Persistent models

#### `Product`

`Product` is the current permanent library record.

| Property | Type | Purpose |
|---|---|---|
| `id` | UUID | Library product identifier |
| `legacyShoppingItemID` | UUID? | Compatibility link to a `ShoppingItem` |
| `name` | String | Product display name |
| `imageData` | Data? | Locally stored image bytes |
| `brand` | String? | Free-text brand |
| `category` | String? | Free-text category |
| `barcode` | String? | One barcode string |
| `imageURLString` | String? | Remote image URL |
| `dateAdded` | Date | Creation date |
| `updatedAt` | Date | Last product refresh/image update |
| `sourceRawValue` | String | Manual, barcode, camera, AI, or Discover |
| `productType` | String? | Provider-derived free text |
| `flavor` | String? | Provider-derived free text |
| `packageSize` | String? | Provider-derived free text |
| `packageType` | String? | Provider-derived free text |
| `visibleText` | String? | Recognized packaging text |
| `searchKeywordsRawValue` | String? | Newline-delimited keyword array |

#### `ShoppingItem`

`ShoppingItem` predates the separated Product Library. It repeats most product fields and additionally stores `isCompleted`. Shopping, planning, store matching, locations, sessions, history, and geofencing still consume it.

#### `ShoppingListEntry`

`ShoppingListEntry` links a `Product` to a `ShoppingList` and stores:

- Its own UUID.
- `shoppingListID`.
- `productID`.
- Optional legacy `ShoppingItem` ID.
- Quantity.
- Checked state.
- Creation time.
- Sort order.
- Optional SwiftData relationship to `Product`.

#### `ProductKnowledge`

`ProductKnowledge` is a local recognition/learning cache with:

- UUID.
- Derived `knowledgeKey`.
- Barcode.
- Product and preferred display names.
- Brand and category.
- Product type, flavor, and package size.
- Thumbnail bytes and remote image URL.
- Newline-delimited search keywords.
- AI confidence and recognition source.
- Learned, last-used, usage-count, and update metadata.

Its current key is:

- `barcode:<normalized barcode>` when a barcode exists.
- `name:<trimmed lowercased name>` otherwise.

There is no declared unique attribute or explicit index on `knowledgeKey`.

#### `ProductHistory`

`ProductHistory` tracks usage frequency and recency using a separate key:

- Barcode key when available.
- Lowercased trimmed name key otherwise.

It stores add count, first/last added dates, source, average interval, and last completion date.

### 4.2 Transient recognition models

`ProductCandidate` is the provider-neutral result shape used by camera, barcode, photo-library, and AI flows. It includes a new random UUID plus name, brand, category, confidence, product details, source, hints, keywords, images, and one barcode.

`RecognitionResult` wraps one or more candidates with status, input source, message, and timestamp.

### 4.3 Persistence

All persistent models are registered in the app-level SwiftData model container. Storage is local to the device.

The application performs a startup/backfill process that:

- Ensures Weekly, Completed, and Recent shopping lists exist.
- Converts legacy `ShoppingItem` rows into `Product` rows when needed.
- Connects existing shopping entries to product IDs and legacy item IDs.
- Runs again when relevant legacy item state changes.

This migration layer is useful but leaves both the current and compatibility models active.

### 4.4 Product identity

There is no single canonical product identifier across the system:

| Concept | Identity |
|---|---|
| Library product | `Product.id` UUID |
| Shopping compatibility item | `ShoppingItem.id` UUID |
| Knowledge cache | `ProductKnowledge.id` UUID plus derived string key |
| Usage memory | `ProductHistory.id` UUID plus derived string key |
| Recognition candidate | New transient UUID |
| Shopping-list row | `ShoppingListEntry.id` UUID plus copied `productID` |

The same real-world product can therefore have multiple UUIDs and multiple name-derived keys. Barcodes improve matching, but each model currently supports only one barcode and manually created products commonly have none.

### 4.5 Category handling

Categories are optional, free-form strings across `Product`, `ShoppingItem`, `ProductCandidate`, and `ProductKnowledge`.

Consequences:

- There is no stable category ID.
- Capitalization, language, synonyms, and provider taxonomy can create duplicates.
- There is no subcategory model.
- An external category can become the app category without a controlled mapping step.
- Icons cannot be reliably resolved from taxonomy.
- Category changes must be copied between product and compatibility records.

### 4.6 Search-keyword handling

Keywords are serialized as a newline-delimited string on multiple models. They are decoded into arrays in memory. They are not used by the Product Library search and have no searchable index.

---

## 5. Current Product Library

### 5.1 Display

The Products tab displays:

- Total library count and current Shopping count.
- A search field.
- All, In Shopping, and Library Only filter chips.
- Product cards.
- Bottom actions for Add, Scan, and Shopping.

Each card can display:

- Product photo or remote image.
- Generic `shippingbox` placeholder when no image exists.
- Product name.
- Brand.
- Product type, flavor, package size, or category fallback.
- In-Shopping status.
- Frequency/recency indicators derived from `ProductHistory`.
- Add to Shopping or Remove from Shopping action.
- Change Product Image action.

### 5.2 Editing

There is no general product editor. A user can replace the product image from the row, but cannot edit:

- Name.
- Brand.
- Category.
- Barcode.
- Search keywords.
- Product details.

Recognized candidates can be edited before save in the scanner’s manual fallback, but saved library text is not editable from the Product Library.

### 5.3 Deleting

Swipe-to-delete is attached to the filtered product list.

For each deleted product, the view:

1. Finds every shopping-list ID that references the product.
2. Attempts to remove it from those lists.
3. Marks linked compatibility shopping items complete.
4. Deletes the `Product`.
5. Marks the current shopping plan stale.

Observed limitations:

- Errors while removing shopping references are discarded with `try?`.
- The delete function does not explicitly save after deleting the product.
- Related `ProductKnowledge` and `ProductHistory` records are not deleted or redirected.
- Compatibility `ShoppingItem` rows are completed, not removed.
- There is no confirmation or undo.

### 5.4 Sorting

Product cards are sorted by `updatedAt` descending. Updating an image or refreshing from recognition can move a product to the top. There is no user-selectable alphabetical, category, frequent, or recently used sort.

The initial product-selection sheet also sorts by `updatedAt` descending. Shopping entries separately use their stored `sortOrder`.

### 5.5 Filtering and searching

Filters are based on whether the selected Shopping list contains a matching `productID`.

Product Library search:

- Runs in memory over all queried products.
- Uses case-insensitive substring matching.
- Searches name, brand, and category.
- Does not search aliases, product type, flavor, package text, barcodes, or `searchKeywords`.
- Does not rank matches.
- Does not offer suggestions.
- Does not normalize the query beyond checking whether its trimmed form is empty.

This is acceptable for a small personal library but is not a knowledge-catalog search design.

---

## 6. Current Camera, Recognition, and Manual Fallback

### 6.1 Camera modes

`CameraViewModel` exposes three modes:

- Photo.
- Barcode.
- AI Vision.

Barcode is the default.

### 6.2 Barcode flow

```text
Detect barcode
  -> user confirms
  -> exact local ProductKnowledge barcode lookup
     -> hit: review known ProductCandidate
     -> miss: Open Food Facts network lookup
        -> hit: review candidate
        -> miss/error: manual barcode form or optional Gemini improvement
  -> save
  -> upsert Product Library
  -> learn ProductKnowledge
```

The local lookup is offline and is correctly attempted before the network lookup. Open Food Facts validates numeric barcodes between 6 and 18 digits and retrieves one product plus an optional image.

Recognized product upsert currently fetches all products, then matches in order:

1. Normalized barcode.
2. Normalized name plus matching brand when either brand exists.
3. Normalized name plus matching category when either category exists.

If no match is found, a new `Product` is inserted.

### 6.3 AI flow

Gemini integration already exists in the current worktree:

- AI Vision accepts a captured or photo-library image.
- Barcode fallback can request a front-of-package image.
- Gemini returns a provider-neutral `ProductCandidate`.
- Candidates below the 0.55 confidence threshold are not accepted.
- The UI asks the user to review before save.
- API absence or provider failure returns to a manual path.

Although future AI implementation is outside WT-020 Phase 1, architecture work must account for this existing adapter and avoid making local product creation depend on it.

### 6.4 Photo mode

The general `ProductRecognitionService` used by Photo mode is currently a stub that returns “AI recognition is not available yet.” AI Vision uses the separate Gemini service.

### 6.5 Manual paths

There are two manual concepts:

1. Standard Product Library creation: name plus optional photo.
2. Barcode fallback creation: required name, optional brand/category, and the scanned barcode.

Both save into the Product Library. Despite its current function name, the barcode manual-save path does not directly add the product to Shopping.

### 6.6 Save and learning behavior

Recognized and barcode-fallback candidates call `upsertRecognizedProduct`. That operation:

- Upserts the `Product`.
- Learns or refreshes `ProductKnowledge`.
- Saves locally.
- Closes the scanner on success.

Product Knowledge is therefore currently a barcode/recognition cache, not a reusable manual-entry knowledge catalog.

---

## 7. UX Pain Points

| Pain point | Current effect |
|---|---|
| No autocomplete in Add Product | Users retype known products and create inconsistent variants |
| No category/icon autofill | Manually created products remain visually and semantically sparse |
| Two different manual forms | Standard and barcode creation expose different fields and behavior |
| No duplicate warning | Equivalent manual products can be saved repeatedly |
| No text editor after save | Users cannot correct name/category/brand from the library |
| Generic missing-image icon | Different product types are not visually distinguishable |
| Photo load has no pending state | A quick save can omit the selected image |
| No clear unknown-product transition | Manual creation is a fallback form rather than part of one search-first flow |
| Scanner save immediately closes | Efficient for one item, but does not support rapid multi-scan without reopening |
| Search is library filtering only | The existing search field does not help create products |

---

## 8. Technical Pain Points

### 8.1 Competing representations

`Product`, `ShoppingItem`, `ProductKnowledge`, `ProductHistory`, and `ProductCandidate` repeat product attributes. Synchronization is manual and partial.

### 8.2 Weak canonical identity

Random IDs are scoped to each model. Name-derived keys are sensitive to spelling, whitespace beyond trimming, language, punctuation, and renaming. One barcode field is insufficient for product variants and packaging changes.

### 8.3 No controlled taxonomy

Category is free text and subcategory/icon semantics do not exist.

### 8.4 Incomplete normalization

Normalization generally means trim plus lowercase. There is no shared Unicode, diacritic, punctuation, whitespace, locale, or transliteration policy.

### 8.5 No alias model

Alternate names, multilingual names, abbreviations, and common misspellings cannot be stored with provenance.

### 8.6 No indexed suggestion search

Library search scans in-memory objects. Product Knowledge supports exact key lookup, not prefix, partial, alias, or ranked search.

### 8.7 Linear upsert

Recognized-product upsert fetches the entire product library and scans it in memory. This is workable at hundreds of rows but is not appropriate for a 50,000-product catalog.

### 8.8 Binary data in core rows

Full image bytes are stored on Product, ShoppingItem, and ProductKnowledge. Repeated image data increases database size and object-loading cost.

### 8.9 No enforced uniqueness

The code derives knowledge and history keys, but the audited models declare no uniqueness constraint or explicit search index for them.

### 8.10 Source-priority coupling

Product Knowledge contains a useful source-priority policy, but resolved fields and source observations are stored together. Future providers could overwrite fields without preserving individual claims and provenance.

### 8.11 Delete and merge semantics

Deleting a library product does not define whether knowledge should be forgotten, retained for suggestions, tombstoned, or merged. Future synchronization would require explicit redirect and tombstone behavior.

### 8.12 Limited automated safety net

No test target or test files were found in the audited repository tree. Identity resolution, migration, ranking, and source-priority rules will need automated characterization before migration.

---

## 9. Foundations Worth Preserving

WT-020 should evolve rather than discard:

- Permanent Product Library separated from Shopping.
- `ShoppingListEntry` as state separate from product attributes.
- Provider-neutral `ProductCandidate` idea.
- Protocol boundaries for recognition and external data providers.
- Local Product Knowledge lookup before network lookup.
- Explicit review before AI-derived data is saved.
- Source/provenance information.
- Product usage history.
- Offline persistence through a repository boundary.
- Startup backfill experience and compatibility awareness.

---

## 10. Audit Conclusion

The current implementation is functional for a small personal library and already demonstrates the correct product-versus-shopping separation. It does not yet satisfy Smart Product Knowledge because manual creation cannot search knowledge, product identity is fragmented, taxonomy is uncontrolled, icons are generic, and all catalog-scale search/upsert operations lack an indexed repository.

WT-020 should establish:

1. One canonical `ProductEntity`.
2. Separate user-library, shopping, usage, and provider-observation state.
3. Stable taxonomy and semantic icons.
4. A local indexed suggestion engine.
5. A single draft/resolution pipeline for text, barcode, camera, voice, and AI.
6. An idempotent, reversible migration from the current models.
