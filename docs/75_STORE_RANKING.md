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

Store Reality Score only runs after product intent eligibility. `ProductIntentResolver` first converts product text into a normalized `ProductIntentProfile` with:

- normalized product category
- intent group
- confidence
- evidence/reasons
- primary, secondary, and fallback allowed store types
- excluded store types

If an item cannot be resolved, it does not become a broad general-store request. Unresolved intent has no allowed store types, so discovered generic stores are rejected before scoring. Saved/custom stores can still match when they have direct item history.

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
- Shopping-list coverage from grouped trip planning.
- Item hints from saved stores or category-relevant discovered stores.
- Safe wording reasons such as `Grocery store`, `Covers 3/5 grocery items`, `Nearby`, `Saved by you`, `Known grocery chain`, and `May have this item`.

## Category Safety

Food requests should prefer grocery, supermarket, market, and convenience stores. Grocery searches explicitly reject irrelevant business names and categories such as jewelry, florists, lawyers, banks, offices, insurance, salons, auto, and unrelated retail.

Non-food requests are ranked by the requested category:

- Health and personal care prefer pharmacies or drugstores.
- Pet food prefers pet stores or pet supply stores, with large grocery/supermarket stores treated as lower-confidence fallback matches.
- Cables and devices prefer electronics, phone, mobile, or computer stores.
- Household cleaning products prefer grocery/supermarket stores, with pharmacies and home-improvement stores treated as secondary matches.

Supported explicit product intents include baking soda, vinegar, coffee, milk, protein drinks, cat food, dog food, USB-C chargers, iPhone cables, medicine, bleach, and cleaning products.

## Saved Stores

Saved/custom stores do not automatically outrank discovered stores. They receive a score boost only when they are both nearby and relevant to the requested item/category.

## Ranking Flow

- Shopping list items are grouped by likely store intent before scoring: grocery/supermarket, electronics, pet store, pharmacy/health, and other/unknown.
- Product intent eligibility rejects impossible store types before Store Reality Score runs.
- Store discovery runs per shopping intent group. Grocery, pet, electronics, and pharmacy groups each search with their own request before results are merged.
- Buying Options generates group-specific store options, then calls Store Reality Score for each relevant group/store pair.
- Shopping Trip coverage calls `StoreRankingService.score` with group-specific coverage metadata.
- Suggested Places and Map selection use Store Reality Score after store item names are narrowed to relevant group items.
- Nearby recommendations carry a group-aware `realityScore` and sort by score before distance.
- Store relevance checks go through `StoreRankingService.isRelevant`.
- Distance is a ranking signal. A far store can lose score, but it is not rejected only because it is beyond a grocery distance cap.
- Explicit impossible-store rejection remains for unrelated grocery results such as jewelry stores, lawyers, florists, banks, insurance offices, and office businesses.

Grouping happens before discovery and scoring. Store Reality Score remains the scoring engine; it no longer receives the full mixed list as if every store could cover every item.

## DEBUG Discovery Verification

DEBUG builds log the runtime discovery pipeline from the user-facing entry points:

- `Suggest Places` / initial Buying Options
- Buying Options map handoff
- Shopping Trip map handoff
- Map suggested discovery
- Nearby opportunities
- Nearby geofence fallback

The logs print `ShoppingIntentGroups created`, item names in each group, `StoreSearch request #N`, requested categories, and whether grouped discovery is active or a legacy merged discovery path is still active.

## Feedback-Ready Model

The local `StoreRealityFeedback` structure is prepared for future found/not-found learning:

- `foundHere`
- `notFoundHere`
- `lastConfirmedAt`
- `confidenceScore`

No feedback UI or cloud sync exists yet.
