## Current AI Foundation

WayTask now has a provider-based AI product recognition path.

Current flow:

1. User scans a barcode or captures a product photo.
2. Barcode mode checks Open Food Facts first.
3. If Product Knowledge or Open Food Facts returns weak product data, WayTask shows `Improve with AI`.
4. If the user chooses to improve, WayTask asks for a clear front package photo and sends that photo to Gemini Vision.
5. Gemini returns a structured product suggestion.
6. The user reviews, edits, or rejects the suggestion before saving.
7. If Gemini is unavailable, fails, or returns a low-confidence result, the original barcode result and manual product form remain available.

Current provider:

- GeminiProductRecognitionService

Provider abstraction:

- AIProductRecognitionServicing

Future providers can be added behind the same abstraction:

- OpenAIProductRecognitionService
- ClaudeProductRecognitionService
- LocalVisionService

## Secrets And API Keys

Gemini uses SecretsManager as the primary key-loading mechanism.

Key loading priority:

1. Secrets.plist from Bundle.main
2. Legacy Info.plist value for GEMINI_API_KEY
3. ProcessInfo environment value for GEMINI_API_KEY

The API key must never be printed, hardcoded, or committed.

If the key is missing, empty, or unresolved, Gemini fails gracefully and the user can still add product details manually.

## Gemini Product Recognition

Gemini is used only when it adds value:

- Direct AI Vision photo recognition.
- User-requested barcode enrichment after Product Knowledge or Open Food Facts returns weak data.
- User-requested barcode enrichment after product lookup fails and the user provides a reference image.

Gemini should not be called automatically from barcode lookup. It should not automatically create shopping-list items. User confirmation is required.

## Planned JSON Product Schema

Gemini should return structured JSON only:

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

Field intent:

- productName: Best visible commercial product name.
- brand: Brand only when visible or strongly indicated.
- category: Useful shopping category.
- confidence: 0.0 to 1.0.
- description: Short optional explanation.
- searchKeywords: 3 to 8 terms for future store matching and product search.

## Confidence Handling

Current behavior:

- High enough confidence: show AI review card.
- Low confidence: show manual product form.
- Missing API key: show manual product form.
- Gemini/network failure: show manual product form.

AI results are labeled as AI-suggested and require user action before saving.

## Search Keywords

Gemini searchKeywords are currently stored on ProductCandidate and merged into productHints during the recognition flow.

They are not yet persisted on ShoppingItem. Persisting them requires a future SwiftData migration.

Future uses:

- Store matching
- Buying Options
- Shopping Trip coverage
- Notifications
- Product search

## Sprint 19.2 Remaining Work

- Persist AI search keywords safely on ShoppingItem.
- Add a migration plan for existing shopping items.
- Improve AI result editing before save.
- Add retry handling for temporary Gemini failures.
- Add internal diagnostics for Gemini response status without exposing private data.
- Add test coverage for SecretsManager and Gemini response parsing.
- Evaluate whether direct photo mode should use Gemini or remain separate from AI Vision mode.

## Known Issues And Limitations

- Gemini accuracy depends on image quality and visible packaging.
- No offline AI recognition exists yet.
- Search keywords are not persisted yet.
- Gemini does not know real local inventory.
- The app does not yet learn from corrected AI suggestions.

## Future AI Capabilities

### Fridge Scan

Users can scan their fridge or pantry, and WayTask can identify available food items, estimate quantities when possible, suggest recipes, and recommend missing ingredients to add to the shopping list.

### Wardrobe Scan

Users can scan clothing items or a wardrobe, and WayTask can identify available clothing, suggest outfit combinations, and recommend complementary items to buy.

### AI Scan Sessions

Future scanning experiences may support a guided scan mode where the user starts a scan, moves the camera across an area, and taps Finish Scan. WayTask then summarizes detected items and suggests useful next actions.
