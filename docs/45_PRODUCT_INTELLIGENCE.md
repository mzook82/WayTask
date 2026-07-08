# Product Intelligence

## Mission

WayTask should help users make better shopping decisions.

The application should not simply display information.

It should understand context and recommend the best next action.

---

# Intelligence Flow

Shopping Need

↓

Product Recognition

↓

Product Knowledge

↓

Shopping Context

↓

Store Intelligence

↓

Future Price Intelligence

↓

Future AI Recommendations

---

# Principles

Every recommendation should answer:

"How does this help the user buy this product more easily?"

---

# Local Product Knowledge

WayTask now has a local `ProductKnowledge` layer for reusable product identity.

This is separate from `ProductHistory`:

- `ProductKnowledge` answers "What is this product?"
- `ProductHistory` answers "How has this product been used in shopping behavior?"

When a product is confirmed and added to the shopping list, WayTask learns or updates the local ProductKnowledge record. Barcode scans check ProductKnowledge first; learned products can be returned before Open Food Facts or Gemini are used.

When an existing ProductKnowledge record is learned again, WayTask refreshes it conservatively. Better confirmed values can update the product name, display name, brand, category, product type, flavor, package size, thumbnail, image URL, confidence, source, and keywords. Empty or lower-priority incoming values do not replace existing data.

Refresh priority:

1. User-confirmed/manual values
2. Gemini
3. Open Food Facts barcode data
4. Existing stored values

Barcode, date learned, usage count, last-used timestamp, and learning history are preserved.

## Smart AI Enrichment

Product Knowledge and barcode lookup results can be improved when the returned identity looks weak. Weak signals include a short or generic product name, missing brand, missing category, missing product type, missing flavor, or missing package size.

When weak data is detected, the Scan flow shows `Improve with AI`. Gemini is called only after the user chooses that action and provides a clear front package photo. If Gemini returns a confident suggestion, the user can accept it or edit the suggested details before saving. If Gemini fails, the original barcode/Product Knowledge result remains available.

Accepting an improved suggestion uses the existing Product Knowledge learning path. The barcode key is preserved, better Gemini fields can refresh the existing record, existing image data or image URLs are kept when Gemini does not provide a replacement, and prior usage history is not reset.

The current ProductKnowledge layer is local only. It stores identity and recognition metadata in a shape that can later synchronize with a cloud database, but no cloud sync exists yet.

---

## Product Knowledge

Lookup order:

1. Product Knowledge

2. Open Food Facts

3. Gemini Vision

4. Manual

Once a product has been confirmed,
future scans bypass external providers.

---

# Future Capabilities

- Store Ranking
- Price Comparison
- Online Shopping
- Indoor Mall Navigation
- Personalized Recommendations
- Smart Notifications
- Shopping History
- AI Decision Support
