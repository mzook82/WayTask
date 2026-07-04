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

The current ProductKnowledge layer is local only. It stores identity and recognition metadata in a shape that can later synchronize with a cloud database, but no cloud sync exists yet.

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
