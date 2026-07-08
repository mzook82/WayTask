# AI Product Recognition

**Status:** Sprint 19.1 complete

**Last Updated:** July 2026

---

# Goal

WayTask uses AI product recognition to help users create better shopping-list items when barcode databases do not have enough information.

AI is assistive. It never automatically saves a product without user review.

---

# Current Architecture

WayTask uses a provider-based AI recognition architecture.

```text
AIProductRecognitionServicing
        |
        v
GeminiProductRecognitionService
```

Future providers can be added behind the same interface:

- OpenAIProductRecognitionService
- ClaudeProductRecognitionService
- LocalVisionService

The Camera flow depends on the protocol, not on Gemini directly.

---

# Secrets.plist Architecture

Gemini uses a local bundled `Secrets.plist` file.

`SecretsManager` loads:

- `Secrets.plist` from `Bundle.main`
- `GEMINI_API_KEY`

The key is treated as unavailable when:

- `Secrets.plist` is missing
- `GEMINI_API_KEY` is missing
- the value is empty
- the value is an unresolved placeholder

The API key must never be printed, hardcoded, or committed.

---

# API Key Loading Flow

Gemini key resolution order:

1. `SecretsManager.geminiAPIKey`
2. Legacy `Bundle.main` Info.plist key: `GEMINI_API_KEY`
3. Debug fallback: `ProcessInfo.environment["GEMINI_API_KEY"]`

Normal operation should use `Secrets.plist`.

The legacy Info.plist and environment paths exist only for compatibility and debugging.

---

# Recognition Flows

## Barcode Mode

```text
Scan barcode
    |
    v
Confirm barcode
    |
    v
Product Knowledge / Open Food Facts lookup
    |
    +-- Strong product found -> Review product -> Add to Shopping List
    |
    +-- Weak product found / product not found / lookup failed
            |
            v
        Improve with AI option
            |
            +-- User skips -> Original result or manual product form
            |
            +-- User taps -> Clear front package photo prompt
                    |
                    v
                Gemini Vision
                    |
                    +-- Good confidence -> AI review card
                    |
                    +-- Low confidence / unavailable / failed -> Original result or manual product form
```

Barcode metadata is preserved when Gemini returns a product suggestion. Existing Product Knowledge image data or image URLs remain available if Gemini fails.

## Weak Barcode Data

WayTask treats barcode product data as weak when the result has one or more of these signals:

- Short or partial product name.
- Generic product name such as `Product`, `Drink`, `Snack`, or `Food`.
- Missing brand.
- Missing category.
- Missing product type.
- Missing flavor.
- Missing package size.

Weak data does not trigger Gemini automatically. It only enables the `Improve with AI` action.

## AI Vision Mode

```text
Capture product photo
    |
    v
Use Photo
    |
    v
Gemini Vision
    |
    +-- Good confidence -> AI review card
    |
    +-- Low confidence / unavailable / failed -> Manual fallback
```

## Manual Fallback

Manual product entry remains available when:

- Gemini is not configured
- Gemini fails
- Gemini returns no usable product
- confidence is too low
- the user wants to edit the AI result
- barcode lookup returns no usable product

Manual fallback does not invent product data.

## Guidance on Low Confidence

When Gemini cannot confidently identify a product, WayTask avoids generic failure copy and gives the user a concrete next step.

Guidance examples:

- `Move closer to one product.`
- `Fill the frame with a single package.`
- `Center the package inside the guide frame.`
- `Try a clearer front photo.`
- `Retake the photo with one package filling the frame.`

Gemini still uses the same request and JSON response shape. The app maps low-confidence, unavailable, or unusable recognition results into clearer guidance while preserving manual fallback.

AI success uses a subtle haptic only when a confident product suggestion is ready for review.

---

# Gemini JSON Product Schema

Gemini is prompted to return structured JSON only:

```json
{
  "productName": "",
  "brand": "",
  "category": "",
  "confidence": 0.0,
  "description": "",
  "searchKeywords": []
}
```

Rules:

- Identify the visible commercial product.
- Use visible packaging.
- Avoid guessing.
- Return low confidence instead of hallucinating.
- Include brand only when visible or strongly indicated.
- Return 3 to 8 useful search keywords.

Search keyword examples:

- `protein drink`
- `banana`
- `milk`
- `oats`
- `dairy drink`
- `sports nutrition`

---

# Confidence Handling

Current threshold:

- AI candidate must meet the app confidence threshold before showing the AI review card.
- Low-confidence results fall back to manual product entry.

User confirmation is always required before saving.

AI results are labeled as AI-suggested.

---

# Metadata Preservation

Currently preserved on `ProductCandidate`:

- product name
- brand
- category
- confidence
- barcode when available
- optimized image data
- search keywords
- product hints
- source = AI

Currently persisted to `ShoppingItem`:

- product name
- brand
- category
- barcode
- image data
- source
- date added

Search keywords are not yet persisted to `ShoppingItem`. Persisting them requires a future SwiftData migration.

---

# Future AI Learning Roadmap

WayTask should eventually learn from user corrections.

Planned learning signals:

- AI suggestion accepted
- AI suggestion edited before save
- AI suggestion rejected
- manually corrected product name
- manually corrected brand
- manually corrected category
- successful store match after AI recognition

Future uses:

- Better product naming
- Better category assignment
- Better store matching
- Better notification copy
- Better Buying Options ranking
- Better Shopping Trip coverage

---

# Testing Instructions

## API Key

Verify without exposing the key:

- `Secrets.plist` is bundled
- `SecretsManager.geminiAPIKey` is non-empty
- `GeminiAPIKeyProvider` resolves a key

## AI Vision Mode

1. Open Camera.
2. Select AI Vision.
3. Capture a clear product photo.
4. Tap Use Photo.
5. Confirm Gemini logs show the call started.
6. Verify either an AI review card or manual fallback appears.

## Barcode Fallback

1. Open Camera.
2. Scan a barcode not found by Open Food Facts.
3. Confirm barcode.
4. Verify WayTask captures a reference image.
5. Verify Gemini runs before the manual form appears.
6. Confirm barcode metadata is preserved if a product is added.

## Manual Fallback

1. Disable or remove the Gemini key locally.
2. Repeat AI Vision or unknown barcode flow.
3. Verify the app does not crash.
4. Verify manual product entry remains available.

---

# Known Issues

- Gemini requires network access.
- Recognition quality depends on image quality and visible packaging.
- Search keywords are not persisted yet.
- Gemini does not know live store inventory.
- The app does not yet learn from accepted or corrected suggestions.

---

# Remaining Work For Sprint 19.2

- Persist AI search keywords on `ShoppingItem`.
- Add SwiftData migration for keyword storage.
- Add tests for `SecretsManager`.
- Add tests for Gemini JSON parsing.
- Add telemetry-safe AI result diagnostics.
- Improve edit-before-save experience for AI suggestions.
- Add retry behavior for temporary Gemini errors.
- Decide whether general Photo mode should use Gemini or remain separate from AI Vision.
