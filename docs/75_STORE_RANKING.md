# Store Reality Score

WayTask ranks stores by likelihood, not certainty. The Store Reality Score is the shared local ranking engine for Buying Options, shopping-trip coverage, suggested places, map selection, and nearby recommendations.

## Principles

- Do not claim guaranteed inventory.
- Do not depend on paid external inventory APIs.
- Do not change Gemini or Product Knowledge architecture.
- Prefer relevant nearby stores over generic or far stores.
- Treat saved/custom stores as useful only when they are nearby and relevant.

## Engine

`StoreRankingService` is the single source of truth for store recommendation scoring. It evaluates a store through independent signal objects and combines their outputs into one `StoreScore`.

Each signal returns:

- `kind`
- score contribution
- optional confidence cap
- optional user-facing reason

Current signal kinds:

- `itemHint`
- `categoryRelevance`
- `knownStoreType`
- `distance`
- `shoppingListCoverage`
- `savedStore`
- `userFeedback`
- `communityKnowledge`
- `inventoryProvider`

The last three are zero-score placeholders so future feedback, community knowledge, cloud Product Knowledge, or retail APIs can be added without changing the recommendation call sites.

## Active Signals

The current score combines:

- Store category relevance for grocery, supermarket, convenience, pharmacy, pet, electronics, home improvement, and coffee requests.
- Store type confidence from known local title patterns and strong chain/title matches.
- Distance from the user when available.
- Saved/custom store relevance and proximity.
- Shopping-list coverage from trip planning.
- Item hints from saved stores or category-relevant discovered stores.
- Safe wording reasons such as `Grocery store`, `Covers 3/5 items`, `Nearby`, `Saved by you`, `Known grocery chain`, and `May have this item`.

## Category Safety

Food requests should prefer grocery, supermarket, market, and convenience stores. Grocery searches explicitly reject irrelevant business names and categories such as jewelry, florists, lawyers, banks, offices, insurance, salons, auto, and unrelated retail.

Non-food requests are ranked by the requested category:

- Health and personal care prefer pharmacies or drugstores.
- Pet food prefers pet stores or pet supply stores, with large grocery/supermarket stores treated as lower-confidence fallback matches.
- Cables and devices prefer electronics, phone, mobile, or computer stores.

## Saved Stores

Saved/custom stores do not automatically outrank discovered stores. They receive a score boost only when they are both nearby and relevant to the requested item/category.

## Ranking Flow

- Buying Options calls `StoreRankingService.rankedStores`.
- Shopping Trip coverage calls `StoreRankingService.score` with exact list coverage metadata.
- Suggested Places and Map selection use `StoreRankingService.rankedStores`.
- Nearby recommendations carry a `realityScore` and sort by score before distance.
- Store relevance checks go through `StoreRankingService.isRelevant`.

## Feedback-Ready Model

The local `StoreRealityFeedback` structure is prepared for future found/not-found learning:

- `foundHere`
- `notFoundHere`
- `lastConfirmedAt`
- `confidenceScore`

No feedback UI or cloud sync exists yet.
