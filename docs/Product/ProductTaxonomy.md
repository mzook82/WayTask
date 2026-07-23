# WT-021B — Product Taxonomy

**Document:** `docs/Product/ProductTaxonomy.md`<br>
**Version:** 1.0<br>
**Status:** Approved for Phase 1<br>
**Sprint:** WT-021B<br>
**Engine:** Product Knowledge Engine<br>
**Owner:** Product<br>
**Last updated:** 2026-07-23<br>
**Authority:** This is the authoritative WayTask Phase 1 Product Taxonomy.

Related documentation:

- [Smart Product Knowledge Blueprint](SmartProductKnowledge.md)
- [Smart Product Creation UX Specification](../Specifications/SmartProductCreation.md)
- [Product Entity Data Model](../Architecture/ProductEntityDataModel.md)

---

## 1. Executive Summary

This document defines the official Product Taxonomy for WayTask Phase 1.

The taxonomy classifies reusable **Product Concepts** such as Milk, Bread, Shampoo, and Dog Food. It does not classify store inventory, brands, package sizes, or barcode-level retail variants.

Phase 1 establishes:

- Fifteen canonical top-level categories.
- Stable, language-independent category IDs.
- Exactly one primary category for every Product Entity.
- A two-level structural limit: category plus optional subcategory.
- No published canonical subcategories in taxonomy version 1.0.
- Required Hebrew and English category names.
- One semantic default icon for every canonical category.
- Explicit assignment and boundary rules.
- `uncategorized` as a safe local fallback, not a normal catalog destination.

The taxonomy supports Product Knowledge, autocomplete, search filtering, semantic icons, Shopping, and future acquisition channels while remaining offline-first and platform-independent.

---

## 2. Normative Language

The terms **must**, **must not**, **should**, and **may** define requirements:

- **Must / must not:** mandatory for Phase 1 conformance.
- **Should / should not:** expected unless an approved exception is documented.
- **May:** optional behavior that does not change taxonomy meaning.

---

## 3. Design Principles

### 3.1 User-first

Classification follows the product concept a person intends to add to a shopping list. It does not attempt to mirror a specific store’s aisle layout.

### 3.2 Product Concepts, not retail inventory

Phase 1 classifies generic concepts:

- Milk.
- Oat Milk.
- Bread.
- Shampoo.
- Dog Food.

It does not create separate taxonomy entries for:

- A brand.
- A package size.
- A flavor-specific SKU.
- A store listing.
- A barcode.
- A price.

### 3.3 One primary category

Each Product Entity has exactly one primary canonical category. Phase 1 does not support multiple primary categories.

### 3.4 Stable identifiers

Category IDs are durable data identifiers. Display names, translations, descriptions, and icons may be revised through taxonomy governance, but an existing ID must not be repurposed to mean a different category.

### 3.5 Minimal hierarchy

Phase 1 permits no more than:

```text
Category
  -> optional Subcategory
```

Deeper trees are prohibited.

### 3.6 Offline-first

All category assignment, display names, icon keys, and boundary rules required by Phase 1 must be available locally.

### 3.7 Platform-independent

The taxonomy stores semantic IDs and localized text. It does not store Apple or Android resource names.

### 3.8 Controlled evolution

Ambiguous products fall back safely. The taxonomy must not grow through ad hoc categories, aliases, or user-generated IDs.

---

## 4. Product Philosophy

### 4.1 Phase 1 Product Entity

For taxonomy purposes, a Phase 1 Product Entity represents a Product Concept.

Examples:

| Valid Product Concept | Not a Phase 1 Product Concept |
|---|---|
| Milk | Tnuva Milk 3% 1 L |
| Cola | Coca-Cola Zero 1.5 L |
| Toothpaste | Colgate Triple Action 75 ml |
| Dog Food | A store-specific dog-food listing |

Retail variants may be introduced later and associated with their parent Product Concept. Unless a later taxonomy revision explicitly provides an override, a retail variant inherits the parent concept’s category and semantic icon.

### 4.2 Classification intent

Classification is based on the product’s primary shopper intent:

- What is the product?
- What is its primary purpose?
- Is it intended for a specific audience such as babies or pets?
- Is frozen state fundamental to how the product is bought?
- Is it a ready-to-consume item or an ingredient?

Brand, package size, price, and store placement do not determine the canonical category.

---

## 5. Taxonomy Structure

### 5.1 Canonical level

All Phase 1 products must reference one of the canonical top-level category IDs in Section 6.

### 5.2 Subcategory level

The schema may support an optional `subcategoryID`, but taxonomy version 1.0 publishes no canonical subcategory registry. Therefore:

- Phase 1 content should leave `subcategoryID` empty.
- Applications must not invent local subcategory IDs.
- A future controlled taxonomy revision may add subcategories.
- A future subcategory must have exactly one canonical parent.
- A future subcategory ID should be namespaced under its parent, for example `dairy.milk`.
- A third hierarchy level must not be introduced during Phase 1.

### 5.3 ID rules

Canonical category IDs:

- Use lowercase ASCII letters and underscores.
- Are language-independent.
- Are unique.
- Must match `^[a-z][a-z0-9_]*$`.
- Must never contain a localized name.
- Must never be reused after deprecation.

### 5.4 Assignment shape

Every Product Entity must resolve to:

```text
productID
primaryCategoryID
subcategoryID?       // empty in taxonomy v1.0
resolvedIconKey
```

Product names, aliases, identifiers, and search keywords are Product Knowledge fields. They are related to taxonomy but are not category definitions.

---

## 6. Canonical Categories

The following fifteen IDs are the complete Phase 1 canonical category set.

| ID | English display name | Hebrew display name | Default semantic icon |
|---|---|---|---|
| `dairy` | Dairy & Alternatives | מוצרי חלב ותחליפים | `product.dairy` |
| `bakery` | Bakery | מאפייה | `product.bread` |
| `fruits_vegetables` | Fruits & Vegetables | פירות וירקות | `product.fruit` |
| `meat_fish` | Meat, Fish & Alternatives | בשר, דגים ותחליפים | `product.meat` |
| `pantry` | Pantry | מזווה | `product.pantry` |
| `drinks` | Drinks | משקאות | `product.drink` |
| `frozen` | Frozen | קפואים | `product.frozen` |
| `snacks` | Snacks & Sweets | חטיפים ומתוקים | `product.snack` |
| `household` | Household | מוצרי בית | `product.household` |
| `cleaning` | Cleaning | ניקיון | `product.cleaning` |
| `personal_care` | Personal Care | טיפוח אישי | `product.personalcare` |
| `pharmacy` | Pharmacy & Health | פארם ובריאות | `product.pharmacy` |
| `baby` | Baby | תינוקות | `product.baby` |
| `pets` | Pets | בעלי חיים | `product.pet` |
| `uncategorized` | Uncategorized | ללא קטגוריה | `product.generic` |

The table is authoritative. Display-name changes require a documented taxonomy revision; ID changes are not permitted.

---

## 7. Category Definitions

### 7.1 Dairy & Alternatives

**ID:** `dairy`

Refrigerated or shelf-stable dairy staples, eggs, and direct dairy alternatives that shoppers use in the same role.

Includes:

- Milk.
- Oat Milk.
- Almond Milk.
- Soy Milk.
- Yogurt and plant-based yogurt alternatives.
- Cheese and cheese alternatives.
- Butter and direct butter alternatives.
- Cream.
- Eggs.

Excludes:

- Ice Cream, which belongs to `frozen`.
- Ready-to-drink coffee, juice, soda, and water, which belong to `drinks`.
- Baking ingredients whose primary concept is an ingredient rather than a dairy staple, which belong to `pantry`.

### 7.2 Bakery

**ID:** `bakery`

Bread-led baked products and bakery goods commonly selected as prepared foods.

Includes:

- Bread.
- Pita.
- Rolls.
- Baguettes.
- Tortillas and flatbreads.
- Prepared pastries.
- Whole cakes.

Excludes:

- Flour, yeast, sugar, and other baking ingredients, which belong to `pantry`.
- Cookies, candy, chocolate bars, and individually packaged snack cakes, which belong to `snacks`.
- Frozen bakery products whose frozen state is fundamental to purchase, which belong to `frozen`.

### 7.3 Fruits & Vegetables

**ID:** `fruits_vegetables`

Fresh produce and fresh culinary herbs.

Includes:

- Fresh fruit.
- Fresh vegetables.
- Fresh herbs.
- Fresh mushrooms.

Excludes:

- Frozen produce, which belongs to `frozen`.
- Canned or jarred produce, which belongs to `pantry`.
- Ready-to-eat dried fruit sold primarily as a snack, which belongs to `snacks`.
- Fruit juice, which belongs to `drinks`.

### 7.4 Meat, Fish & Alternatives

**ID:** `meat_fish`

Fresh or chilled meat, poultry, fish, seafood, and direct plant-based substitutes used as the same meal component.

Includes:

- Chicken.
- Beef.
- Lamb.
- Turkey.
- Fresh fish.
- Seafood.
- Chilled plant-based burgers, mince, and meat substitutes.

Excludes:

- Frozen meat, fish, seafood, or substitutes, which belong to `frozen`.
- Canned fish or meat, which belong to `pantry`.
- Pet food, which belongs to `pets`.

### 7.5 Pantry

**ID:** `pantry`

Shelf-stable staples, cooking ingredients, condiments, canned goods, and dry meal components.

Includes:

- Rice.
- Pasta.
- Flour.
- Sugar.
- Salt.
- Oils.
- Spices.
- Sauces and condiments.
- Canned and jarred foods.
- Breakfast cereal.
- Baking ingredients.
- Protein powder and other dry nutritional powders used as ingredients or mixes.

Excludes:

- Ready-to-drink beverages, which belong to `drinks`.
- Ready-to-eat confectionery and snack products, which belong to `snacks`.
- Frozen versions of pantry foods, which belong to `frozen`.

### 7.6 Drinks

**ID:** `drinks`

Non-dairy beverages and products whose primary purpose is preparing a beverage.

Includes:

- Water.
- Juice.
- Soda.
- Coffee.
- Tea.
- Energy drinks.
- Ready-to-drink protein beverages.

Excludes:

- Milk and direct milk alternatives, which belong to `dairy`.
- Protein powder and dry nutritional mixes, which belong to `pantry`.
- Medicines and therapeutic hydration products, which belong to `pharmacy`.

### 7.7 Frozen

**ID:** `frozen`

Food Product Concepts for which frozen state is fundamental to how the product is purchased and stored.

Includes:

- Frozen vegetables.
- Frozen fruit.
- Frozen meals.
- Frozen pizza.
- Frozen meat and fish.
- Frozen plant-based substitutes.
- Ice Cream.

Excludes:

- Fresh or chilled equivalents.
- Shelf-stable products that a user may personally freeze after purchase.

Frozen state overrides the product’s ingredient-based food category during Phase 1.

### 7.8 Snacks & Sweets

**ID:** `snacks`

Ready-to-eat snack foods, confectionery, and sweet treats.

Includes:

- Chips.
- Crackers.
- Chocolate and candy.
- Cookies.
- Snack cakes.
- Snack bars.
- Ready-to-eat nuts and dried fruit sold primarily as snacks.

Excludes:

- Baking chocolate, cooking nuts, and ingredient-oriented products, which belong to `pantry`.
- Whole bakery cakes and prepared bakery goods, which belong to `bakery`.
- Ice Cream, which belongs to `frozen`.

### 7.9 Household

**ID:** `household`

Non-cleaning household consumables, storage products, paper goods, and general home-use disposables.

Includes:

- Garbage bags.
- Aluminum foil.
- Baking paper.
- Food-storage bags and containers.
- Paper towels.
- Tissues.
- Disposable tableware.

Excludes:

- Products and tools whose primary purpose is cleaning, disinfecting, dishwashing, or laundry, which belong to `cleaning`.
- Personal hygiene products, which belong to `personal_care`.

### 7.10 Cleaning

**ID:** `cleaning`

Products and tools whose primary purpose is cleaning, disinfecting, dishwashing, or laundry.

Includes:

- Laundry detergent.
- Fabric softener.
- Dish soap and dishwasher detergent.
- Floor, bathroom, glass, and surface cleaners.
- Surface disinfectants.
- Cleaning wipes.
- Sponges, brushes, and cleaning gloves.

Excludes:

- Hand and body soap, which belong to `personal_care`.
- Baby wipes, which belong to `baby`.
- General wet wipes intended for personal use, which belong to `personal_care`.
- Garbage bags and general paper goods, which belong to `household`.

### 7.11 Personal Care

**ID:** `personal_care`

Routine personal hygiene, grooming, oral care, and non-therapeutic body-care products for general human use.

Includes:

- Shampoo and conditioner.
- Hand and body soap.
- Toothpaste and oral-care products.
- Deodorant.
- Shaving and grooming products.
- Menstrual-care products.
- General personal wet wipes.
- General-use sunscreen and routine skin-care products.

Excludes:

- Medicines, vitamins, first aid, and medical supplies, which belong to `pharmacy`.
- Products explicitly intended for babies, which belong to `baby`.
- Products explicitly intended for animals, which belong to `pets`.
- Surface cleaning or disinfecting products, which belong to `cleaning`.

### 7.12 Pharmacy & Health

**ID:** `pharmacy`

Human medicines and products whose primary purpose is active treatment, supplementation, first aid, or medical support.

Includes:

- Pain relief and other non-prescription medicines.
- Vitamins and supplements.
- Bandages and first-aid supplies.
- Thermometers and basic medical supplies.
- Therapeutic creams and treatments.
- Infant medicines.

Excludes:

- Routine hygiene and grooming products, which belong to `personal_care`.
- General-use sunscreen and non-therapeutic skin care, which belong to `personal_care`.
- Non-therapeutic baby-care products, which belong to `baby`.
- Veterinary and pet-specific products, which belong to `pets`.

### 7.13 Baby

**ID:** `baby`

Non-therapeutic products designed specifically for infant feeding, diapering, hygiene, and care.

Includes:

- Diapers.
- Baby wipes.
- Baby food.
- Infant formula.
- Baby shampoo and non-therapeutic baby skin care.
- Nursing and feeding consumables.

Excludes:

- Infant medicines and therapeutic products, which belong to `pharmacy`.
- General household or personal-care products that are not specifically intended for babies.

### 7.14 Pets

**ID:** `pets`

Products intended specifically for animals.

Includes:

- Dog food.
- Cat food.
- Pet treats.
- Pet litter.
- Pet shampoo and hygiene products.
- Veterinary and pet-care consumables.

Excludes:

- Human food purchased incidentally for a pet.
- Human personal-care or pharmacy products.
- General household cleaning products.

### 7.15 Uncategorized

**ID:** `uncategorized`

A safe fallback for a Product Entity that cannot be assigned confidently under the current rules.

Use is permitted for:

- A manually created unknown product.
- An ambiguous migrated product.
- A provider observation awaiting review.
- A concept not yet covered by an approved taxonomy revision.

Use is discouraged for:

- Curated or official Product Concepts that can be classified through existing rules.
- Avoiding a documented boundary decision.

`uncategorized` must never be treated as a source category for automatic inference or a search synonym.

---

## 8. Product Assignment Rules

Every Phase 1 Product Entity must:

1. Represent a Product Concept rather than a retail variant.
2. Have one stable Product ID.
3. Have one primary display name.
4. Reference exactly one canonical `primaryCategoryID`.
5. Leave `subcategoryID` empty under taxonomy version 1.0.
6. Resolve to exactly one semantic icon through the inheritance rules in Section 10.
7. Support optional localized names and aliases without changing category identity.

Every assignment must:

- Use a category ID from Section 6.
- Follow the precedence and boundary rules in Section 9.
- Ignore brand, package size, price, and store placement.
- Preserve uncertainty by using `uncategorized`; it must not invent a confident classification.

Products must not:

- Reference more than one primary category.
- Create a new category or subcategory locally.
- Store localized display text as a category ID.
- Use an icon to imply a different category.
- Change category solely because a provider uses another taxonomy.

---

## 9. Boundary Rules

### 9.1 Assignment precedence

Apply these rules in order:

1. **Animal-specific intent:** A product intended specifically for animals belongs to `pets`.
2. **Human therapeutic intent:** A human medicine, supplement, first-aid, or medical-support product belongs to `pharmacy`, including infant medicine.
3. **Baby-specific non-therapeutic intent:** A non-therapeutic product explicitly designed for babies belongs to `baby`.
4. **Frozen state:** A food concept purchased and stored as frozen belongs to `frozen`.
5. **Direct substitute intent:** A direct milk alternative belongs to `dairy`; a direct meat/fish alternative belongs to `meat_fish`.
6. **Primary use:** Classify by what the product is mainly used for, not by its material or ingredient.
7. **Consumption form:** Ready-to-eat snack concepts belong to `snacks`; ingredient-oriented equivalents belong to `pantry`.
8. **Unresolved ambiguity:** Use `uncategorized` and require review.

### 9.2 Canonical boundary assignments

These assignments are normative:

| Product Concept | Canonical category | Reason |
|---|---|---|
| Eggs | `dairy` | Conventional dairy-led grocery staple |
| Oat Milk | `dairy` | Direct milk alternative |
| Almond Milk | `dairy` | Direct milk alternative |
| Chilled Plant-Based Burger | `meat_fish` | Direct meat alternative |
| Frozen Plant-Based Burger | `frozen` | Frozen-state rule has precedence |
| Frozen Vegetables | `frozen` | Frozen state is fundamental |
| Frozen Chicken | `frozen` | Frozen state is fundamental |
| Ice Cream | `frozen` | Canonical frozen product |
| Fresh Fish | `meat_fish` | Fresh/chilled protein concept |
| Canned Tuna | `pantry` | Shelf-stable canned good |
| Coffee | `drinks` | Beverage/preparation concept |
| Tea | `drinks` | Beverage/preparation concept |
| Protein Powder | `pantry` | Dry mix/ingredient concept |
| Ready-to-Drink Protein Shake | `drinks` | Ready-to-drink beverage |
| Whole Cake | `bakery` | Prepared bakery good |
| Snack Cake | `snacks` | Individually consumed snack concept |
| Chocolate Bar | `snacks` | Ready-to-eat confectionery |
| Baking Chocolate | `pantry` | Cooking ingredient |
| Fresh Herbs | `fruits_vegetables` | Fresh produce |
| Frozen Fruit | `frozen` | Frozen-state rule has precedence |
| Baby Wipes | `baby` | Baby-specific care product |
| General Wet Wipes | `personal_care` | Personal hygiene use |
| Disinfecting Wipes | `cleaning` | Surface cleaning/disinfection use |
| Infant Pain Relief | `pharmacy` | Human therapeutic use |
| Pet Shampoo | `pets` | Animal-specific use |
| Pet Medication | `pets` | Animal-specific use |
| Hand Soap | `personal_care` | Body/personal hygiene use |
| Dish Soap | `cleaning` | Dish-cleaning use |
| General-Use Sunscreen | `personal_care` | Routine non-therapeutic personal care |
| Medicated Treatment Cream | `pharmacy` | Active human therapeutic use |
| Paper Towels | `household` | General household paper good |
| Sponges | `cleaning` | Cleaning tool |
| Vitamins | `pharmacy` | Human supplementation |

### 9.3 Provider disagreement

An external provider category is an observation, not canonical truth. When provider data conflicts with this taxonomy:

- Preserve the provider’s original category as provenance if needed.
- Map through approved local rules.
- Keep the WayTask canonical category stable.
- Use `uncategorized` when no safe mapping exists.

---

## 10. Icon Strategy

### 10.1 Semantic icon identifiers

The taxonomy stores semantic icon keys only. Canonical mappings are defined in Section 6.

Examples:

- `product.dairy`
- `product.bread`
- `product.drink`
- `product.cleaning`
- `product.generic`

The Product Knowledge database must not store:

- Emoji.
- SF Symbol names.
- Android drawable or Material icon names.
- Platform-specific file paths.

### 10.2 Icon resolution

Every Product Entity must resolve to one icon using this precedence:

1. Approved Product Concept semantic icon override, when one exists.
2. Approved subcategory icon, when a future subcategory exists.
3. Primary category default icon.
4. `product.generic` fallback.

The taxonomy owns category default keys. A future Product Catalog may own approved Product Concept overrides.

### 10.3 Platform requirements

Each platform must:

- Map every canonical semantic key to a local visual asset.
- Provide a visual fallback for unknown keys.
- Treat the product/category text label as the accessible meaning.
- Never depend on icon color alone.
- Validate icon-map completeness for all fifteen categories.

Visual assets may differ by platform; semantic meaning must not.

---

## 11. Localization

### 11.1 Required locales

Taxonomy version 1.0 requires:

- English: `en`.
- Hebrew: `he`.

Hebrew content must render correctly in right-to-left layouts.

### 11.2 Localization rules

- Category IDs never change with language.
- English and Hebrew names must describe the same category scope.
- A translation change must not create a new category ID.
- Transliteration is not a canonical display name.
- Category search aliases are separate from localized display names.
- Localized text must not be used as a persistence key.

### 11.3 Display fallback

Category display resolution should use:

1. Exact supported application language.
2. English.
3. A safe generic localized label.

The raw category ID should not be shown as a normal user-facing fallback.

### 11.4 Future languages

Additional BCP-47 locales may be added as localized category-name records. Adding a language must not change:

- Category IDs.
- Assignment rules.
- Hierarchy.
- Icon keys.

---

## 12. Search Compatibility

The taxonomy supports Product Knowledge search but does not define the full search-ranking algorithm.

### 12.1 Searchable taxonomy data

The local search projection may include:

- Localized category display names.
- Approved category search aliases.
- The assigned category ID as internal filter metadata.

Category text should have lower ranking weight than a Product Concept’s canonical name or product alias.

### 12.2 Product aliases

Product aliases belong to the Product Entity, not the category. A product alias:

- May improve prefix and alias search.
- Must not change category assignment.
- Must not be created from an unconfirmed typo.

### 12.3 Category filters

Canonical category IDs provide stable local filters. A localized label change must not alter filtering behavior.

### 12.4 Deferred search behavior

The following are not taxonomy responsibilities in Phase 1:

- Fuzzy matching.
- Typo correction.
- Semantic or AI search.
- Provider taxonomy search.
- Store-aisle search.

---

## 13. Product Assignment Workflow

```text
Candidate input
  -> confirm Product Concept scope
  -> check for an existing Product Entity
  -> apply assignment precedence
  -> assign one canonical category
  -> resolve semantic icon
  -> attach localized names and approved aliases
  -> validate
  -> publish or route for review
```

### 13.1 Workflow requirements

1. **Confirm concept scope.** Remove brand, package, price, and store-specific detail from the taxonomy decision.
2. **Check identity.** Reuse an existing Product Entity when identity resolution is safe.
3. **Apply boundary rules.** Use Section 9 before relying on provider text.
4. **Assign category.** Select exactly one canonical ID.
5. **Resolve icon.** Use the inheritance chain in Section 10.
6. **Localize.** Require valid English and Hebrew category resources; Product Concept localization follows Product Knowledge rules.
7. **Validate.** Run the checklist in Section 17.
8. **Escalate uncertainty.** Assign `uncategorized` and request review rather than creating a new category.

### 13.2 Category changes

A category correction:

- Changes the Product Entity assignment.
- Does not change the Product ID.
- Does not change category ID meanings.
- Must rebuild or update affected search projections.
- Should preserve prior provider observations as provenance when relevant.

---

## 14. Future Expansion

### 14.1 Subcategories

Future subcategories may be introduced when:

- A top-level category has repeatable user-facing ambiguity.
- The distinction improves search, icons, filtering, or assignment.
- Inclusion, exclusion, and boundary rules can be documented.
- Hebrew and English names and semantic icons are available.

Subcategories must not be introduced only to mirror a provider or store aisle.

### 14.2 Retail variants

Future brands, barcodes, package sizes, flavors, nutrition, and images extend a Product Concept. They do not require new top-level taxonomy IDs.

A retail variant should inherit:

- Parent Product Concept category.
- Parent semantic icon.

An override requires an explicit future rule.

### 14.3 Tags and secondary facets

Future dietary, lifestyle, preparation, or community labels should be modeled as tags/facets rather than additional primary categories.

Examples:

- Vegan.
- Gluten Free.
- Organic.
- Kosher.
- Sugar Free.

Tags must not weaken the one-primary-category rule.

### 14.4 Category evolution

A future taxonomy revision may:

- Add a category.
- Add a subcategory.
- Add a localization.
- Update descriptions and boundary examples.
- Deprecate a category through an explicit migration.

A revision must not silently:

- Reuse an ID.
- Change an ID’s meaning.
- Introduce a third hierarchy level.
- Move products without migration and review.

---

## 15. Deferred Capabilities

The following are outside Phase 1 taxonomy:

- Product Catalog content.
- Retail inventory.
- Store-specific products or aisle taxonomies.
- Brands and brand hierarchy.
- Package sizes and package types.
- Pricing and availability.
- Barcode databases.
- Nutrition.
- Product images.
- Multi-category assignment.
- User-created categories.
- Canonical subcategory content.
- Deeper hierarchy.
- AI-generated category assignment.
- Community-generated taxonomy changes.

These may integrate with Product Knowledge later without changing the fifteen Phase 1 category IDs.

---

## 16. Risks

| Risk | Impact | Control |
|---|---|---|
| Categories are too broad | Reduced filtering precision | Add governed subcategories only after evidence |
| Frozen overlaps ingredient categories | Inconsistent assignments | Frozen-state precedence rule |
| Household overlaps Cleaning | Unpredictable results | Primary-purpose boundary and examples |
| Personal Care overlaps Pharmacy | Health products drift between categories | Therapeutic-intent rule |
| Baby/Pets overlap functional categories | Audience-specific products scatter | Audience precedence rules |
| Ready-to-eat products overlap Pantry | Search inconsistency | Consumption-form rule |
| Provider categories leak into canonical data | Platform/provider divergence | Local mapping and provenance |
| `uncategorized` becomes a default | Catalog quality declines | Review metrics and curated-content restriction |
| English/Hebrew labels diverge in scope | Localization inconsistency | Same-scope translation review |
| Platform icons diverge semantically | Inconsistent product meaning | Semantic keys and icon-map validation |
| Ad hoc subcategories appear | Taxonomy fragmentation | No local IDs; controlled revision only |
| Future retail variants duplicate concepts | Identity fragmentation | Parent-concept inheritance |

---

## 17. Validation Checklist

### 17.1 Structure

- [ ] Exactly fifteen canonical top-level category IDs exist.
- [ ] Every category ID is unique.
- [ ] Every ID is language-independent and matches the ID format.
- [ ] No category has more than one parent.
- [ ] No hierarchy deeper than category plus optional subcategory exists.
- [ ] Taxonomy version 1.0 publishes no canonical subcategory IDs.

### 17.2 Definitions and boundaries

- [ ] Every canonical category has a purpose statement.
- [ ] Every canonical category has inclusion examples.
- [ ] Every canonical category has exclusion or boundary guidance.
- [ ] Frozen precedence is applied consistently.
- [ ] Household and Cleaning are separated by primary purpose.
- [ ] Personal Care and Pharmacy are separated by therapeutic intent.
- [ ] Baby and Pets audience rules are applied consistently.
- [ ] Ingredient versus ready-to-eat rules are applied consistently.
- [ ] Unresolved products use `uncategorized`.

### 17.3 Localization

- [ ] Every category has an English display name.
- [ ] Every category has a Hebrew display name.
- [ ] English and Hebrew names express the same scope.
- [ ] Hebrew renders correctly right-to-left.
- [ ] No localized text is used as a persistent ID.

### 17.4 Icons

- [ ] Every category has one default semantic icon key.
- [ ] Every icon key is platform-independent.
- [ ] Every platform maps all fifteen keys.
- [ ] `product.generic` is available as fallback.
- [ ] No emoji, SF Symbol name, or Android resource name is stored as taxonomy data.

### 17.5 Product assignment

- [ ] Every Product Entity has exactly one canonical primary category.
- [ ] Product assignment ignores brand, package size, price, and store.
- [ ] Product aliases do not change category assignment.
- [ ] Retail variants inherit their Product Concept category unless a future rule says otherwise.
- [ ] Provider disagreements do not overwrite canonical assignments directly.

---

## 18. Success Criteria

The Phase 1 taxonomy is successful when:

- Common Product Concepts can be assigned consistently without network access.
- The same input produces the same canonical category on every platform.
- Category IDs remain stable across localization and visual changes.
- Product autocomplete and category filters can use taxonomy data predictably.
- Product icons resolve consistently from semantic keys.
- Ambiguous products have documented boundary outcomes or a safe fallback.
- Curated content rarely uses `uncategorized`.
- Future subcategories, variants, languages, and tags can be added without repurposing existing IDs.

Recommended operational measures:

- Percentage of curated Product Concepts assigned to `uncategorized`.
- Category correction rate during review.
- Cross-platform taxonomy conformance failures.
- Missing icon-map entries.
- English/Hebrew localization completeness.
- Number of unresolved boundary cases per taxonomy revision.

---

## 19. Final Decision

**APPROVED — WAYTASK PRODUCT TAXONOMY VERSION 1.0**

The approved Phase 1 taxonomy consists of:

- Fifteen canonical top-level categories.
- No published canonical subcategories.
- One primary category per Product Concept.
- Stable language-independent IDs.
- Required English and Hebrew display names.
- Semantic platform-independent category icons.
- Explicit assignment precedence and boundary rules.
- `uncategorized` as a controlled fallback.

This document is the authoritative taxonomy reference for WayTask Phase 1. Product Catalog content, generators, validators, and production implementation are separate future work.
