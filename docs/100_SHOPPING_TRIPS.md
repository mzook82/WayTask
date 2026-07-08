## Current Capabilities

### ✅ Shopping Trip Planner

WayTask can now:

- Analyze the current shopping list
- Group items by likely store type
- Estimate store coverage
- Rank nearby stores
- Recommend the best store for the trip
- Show matched items
- Show missing items
- Display shopping coverage
- Open Trip Map Mode

## Store Grouping

Shopping Trip Planning groups active items before recommending stores:

- Grocery / supermarket
- Electronics
- Pet store
- Pharmacy / health
- Other / unknown

Coverage is calculated inside each group. A grocery store can cover grocery items such as baking soda, coffee, or protein drinks, but it should not claim electronics items such as a USB-C charger or iPhone cable. An electronics store can cover electronics items, but it should not claim baking soda.

Store discovery also happens inside each group. WayTask searches once for grocery stores, once for pet stores, once for electronics stores, and so on, then merges the discovered stores after discovery. Store Reality Score is still the scoring engine. Grouping happens before discovery and scoring so each store is scored only against realistic matching items.

## Product Intent Resolution

Before grouping and scoring, WayTask resolves each product into a `ProductIntentProfile`. The profile includes a normalized category, confidence, evidence, allowed store types, fallback store types, and excluded store types.

Examples:

- Baking soda, vinegar, coffee, milk, and protein drinks resolve to grocery-oriented intents.
- Cat food and dog food resolve to pet-store primary intent with supermarket/grocery as secondary matches.
- USB-C chargers and iPhone cables resolve to electronics.
- Medicine resolves to pharmacy.
- Bleach and cleaning products resolve to grocery/supermarket primary intent with pharmacy and home-improvement as secondary matches.

Unresolved items remain unknown. They do not automatically search broad general stores; WayTask shows no suitable store unless saved/custom item history provides a direct match.

## Map Matching Items

Trip Map Mode and nearby store cards show only the relevant item names for the store group. A mixed list may produce multiple realistic trip options, such as one grocery stop, one electronics stop, and one pet store stop, instead of one unrealistic full-list store.

## Discovery Merge

Group-specific discovery results are merged only after each group has searched independently. Duplicate stores are removed by title and nearby coordinate. Local fallback stores are kept for groups that did not receive an equivalent Apple Maps result, so one successful grocery search does not erase a pet or electronics fallback.

### Planned

- Multi-stop shopping
- Route optimization
- Live inventory
- Price-aware trip planning
- AI trip optimization

## Shopping Mode Integration

Shopping Trip Planning now connects directly with Shopping Mode.

Current flow:

Shopping List

↓

Shopping Trip Planner

↓

Best Store Recommendation

↓

Trip Map Mode

↓

Shopping Mode

↓

Finish Shopping

Future extensions:

- Multi-store trips
- Indoor navigation
- Purchase confirmation
- Smart reminders
- AI shopping assistant
