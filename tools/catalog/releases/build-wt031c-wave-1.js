#!/usr/bin/env node
"use strict";

// This is an explicitly curated release builder, not a product generator. Every
// addition below names its repository evidence and every transferred alias is
// asserted against catalog version 5 before the release is emitted.

const fs = require("node:fs");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..", "..", "..");
const catalogPath = path.join(
  repoRoot,
  "WayTask",
  "Resources",
  "product_catalog_he.json",
);
const localizationPath = path.join(
  repoRoot,
  "WayTask",
  "Resources",
  "ProductKnowledge",
  "product-knowledge-localizations-v1.json",
);
const outputPath = path.join(
  repoRoot,
  "shared",
  "catalog",
  "releases",
  "wt-031c-wave-1.json",
);

const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
const localizations = JSON.parse(fs.readFileSync(localizationPath, "utf8"));

if (catalog.catalogVersion !== 5 || catalog.products.length !== 647) {
  throw new Error(
    "WT-031C Wave 1 must be built from the reviewed 647-product catalog version 5 baseline.",
  );
}

const productsByID = new Map(
  catalog.products.map((product) => [product.id, product]),
);
const namesByProductID = new Map();
for (const name of localizations.names) {
  const names = namesByProductID.get(name.productID) ?? [];
  names.push(name);
  namesByProductID.set(name.productID, names);
}

function localized(locale, value) {
  return { locale, value };
}

function editorialFromRuntime(product) {
  const canonicalNames = { "he-IL": product.canonicalName };
  const localizedDisplayNames = [];
  const aliases = product.aliases.map((value) => localized("he-IL", value));
  const keywords = product.keywords.map((value) => localized("he-IL", value));
  const brandTerms = product.brandTerms.map((value) =>
    localized("he-IL", value)
  );
  const legacyNames = (product.legacyNames ?? []).map((value) =>
    localized("he-IL", value)
  );

  for (const name of namesByProductID.get(product.id) ?? []) {
    if (
      name.kind === "localizedDisplay" &&
      name.isPreferred &&
      canonicalNames[name.locale] === undefined
    ) {
      canonicalNames[name.locale] = name.value;
    } else if (name.kind === "canonical" || name.kind === "localizedDisplay") {
      localizedDisplayNames.push(localized(name.locale, name.value));
    } else if (name.kind === "alias") {
      aliases.push(localized(name.locale, name.value));
    } else if (name.kind === "keyword") {
      keywords.push(localized(name.locale, name.value));
    }
  }

  return {
    id: product.id,
    canonicalNames,
    localizedDisplayNames,
    aliases,
    keywords,
    brandTerms,
    ...(legacyNames.length > 0 ? { legacyNames } : {}),
    brand: product.brand ?? null,
    categoryId: product.categoryId,
    subcategoryId: product.subcategoryId,
    barcodes: product.barcodes ?? [],
    semanticKey: product.semanticKey ?? null,
    variantDescriptors: product.variantDescriptors ?? [],
    packageDescriptor: product.packageDescriptor ?? null,
    unit: product.unit ?? null,
    provenance: product.provenance ?? null,
    popularityScore: product.popularityScore,
    status: { state: product.isActive ? "active" : "inactive" },
  };
}

const replacementEdits = {
  bread_rolls: { removeAliases: ["לחמניות המבורגר"] },
  bread_sourdough: { removeAliases: ["מחמצת"] },
  croissant: { removeAliases: ["קרואסון חמאה"] },
  yeast_cake: { removeAliases: ["עוגת שמרים שוקולד"] },
  brioche_rolls: { removeAliases: ["בריוש"] },
  grapes: { removeAliases: ["ענבים ירוקים", "ענבים שחורים"] },
  lettuce: { removeAliases: ["לבבות חסה"] },
  fresh_mushrooms: { removeAliases: ["פטריות שמפיניון"] },
  beef_steak: { removeAliases: ["אנטרקוט"] },
  beef_liver: { removeAliases: ["כבד עגל"] },
  dry_lentils: { removeAliases: ["עדשים ירוקות", "עדשים כתומות"] },
  tahini_raw: { removeAliases: ["טחינה מלאה"] },
  sugar: { removeAliases: ["סוכר לבן"] },
  popcorn: { removeAliases: ["תירס לפופקורן"] },
  black_pepper: { removeAliases: ["פלפל שחור טחון"] },
  cumin: { removeAliases: ["כמון טחון"] },
  turmeric: { removeAliases: ["כורכום טחון"] },
  cinnamon: { removeAliases: ["קינמון טחון"] },
  hot_paprika: { removeAliases: ["פפריקה חריפה טחונה"] },
  white_pepper: { removeAliases: ["פלפל לבן טחון"] },
  nutmeg: { removeAliases: ["מוסקט טחון"] },
  shredded_coconut: { removeAliases: ["פתיתי קוקוס"] },
  chocolate_bar: { removeAliases: ["שוקולד חלב"] },
  wafers: { removeAliases: ["ופל שוקולד"] },
  black_tea: { removeAliases: ["תיונים", "שקיקי תה"] },
  laundry_detergent: { removeAliases: ["נוזל כביסה", "אבקת כביסה"] },
  dishwasher_tablets: { removeAliases: ["קפסולות למדיח"] },
  deodorant: { removeAliases: ["דאודורנט ספריי", "דאודורנט סטיק"] },
  shaving_foam: { removeAliases: ["ג׳ל גילוח"] },
  baby_puree: { removeAliases: ["מחית פירות לתינוק"] },
  disposable_cups: { removeAliases: ["כוסות פלסטיק"] },
  disposable_plates: { removeAliases: ["צלחות פלסטיק"] },
  disposable_forks: { removeAliases: ["מזלגות פלסטיק"] },
  disposable_knives: { removeAliases: ["סכינים פלסטיק"] },
  disposable_spoons: { removeAliases: ["כפיות פלסטיק"] },
  food_storage_bags: {
    removeAliases: ["שקיות סנדוויץ׳", "שקיות כריכים"],
  },
  pet_harness: { removeAliases: ["רתמה לכלב", "רתמה לחתול"] },
  pet_bed: { removeAliases: ["מיטה לכלב", "מיטה לחתול"] },
  pet_flea_treatment: { removeAliases: ["חומר נגד קרציות"] },
  small_pet_hay: { removeAliases: ["חציר לארנבים"] },
  pet_carrier: { removeAliases: ["תיק נשיאה לחיות מחמד"] },
  antacid: { removeAliases: ["טבליות לצרבת"] },
  yellow_cheese: {
    removeAliases: ["פרוסות גבינה", "גבינה לפרוסות"],
  },
  baking_paper: { addAliases: ["נייר פרגמנט"] },
  strawberry_jam: { removeAliases: ["ריבה"] },
  baby_snack_puffs: { removeAliases: ["חטיף תינוקות תפוח"] },
};

function replacementOperation(id, edits) {
  const runtime = productsByID.get(id);
  if (!runtime) {
    throw new Error(`Missing replacement source ${id}.`);
  }
  const product = editorialFromRuntime(runtime);
  const hebrewAliases = product.aliases
    .filter((term) => term.locale === "he-IL")
    .map((term) => term.value);
  for (const alias of edits.removeAliases ?? []) {
    if (!hebrewAliases.includes(alias)) {
      throw new Error(`${id} no longer owns reviewed alias ${alias}.`);
    }
  }
  product.aliases = product.aliases.filter(
    (term) => !(edits.removeAliases ?? []).includes(term.value),
  );
  for (const alias of edits.addAliases ?? []) {
    if (!product.aliases.some((term) => term.value === alias)) {
      product.aliases.push(localized("he-IL", alias));
    }
  }
  product.provenance =
    `WT-031C editorial refinement of production catalog v5:${id}`;
  return { operation: "replace", product };
}

function add(spec) {
  const source = spec.sourceId ? productsByID.get(spec.sourceId) : null;
  if (spec.sourceId && !source) {
    throw new Error(`Missing addition source ${spec.sourceId}.`);
  }
  const canonicalNames = { "he-IL": spec.name };
  if (spec.english) {
    canonicalNames.en = spec.english;
  }
  return {
    operation: "add",
    product: {
      id: spec.id,
      canonicalNames,
      localizedDisplayNames: [],
      aliases: (spec.aliases ?? []).map((value) => localized("he-IL", value)),
      keywords: (spec.keywords ?? source?.keywords ?? []).map((value) =>
        localized("he-IL", value)
      ),
      brandTerms: (spec.brandTerms ?? []).map((value) =>
        localized("he-IL", value)
      ),
      brand: null,
      categoryId: spec.categoryId ?? source.categoryId,
      subcategoryId:
        spec.subcategoryId !== undefined
          ? spec.subcategoryId
          : source.subcategoryId,
      barcodes: [],
      semanticKey: spec.semanticKey ?? spec.sourceId ?? spec.id,
      variantDescriptors: spec.variantDescriptors ?? [],
      packageDescriptor: null,
      unit: null,
      provenance: spec.provenance,
      popularityScore: spec.popularityScore ?? source.popularityScore,
      status: { state: "active" },
    },
  };
}

const aliasSource = (sourceId) =>
  `WayTask/Resources/product_catalog_he.json catalogVersion 5 ${sourceId}.aliases`;
const keywordSource = (sourceId) =>
  `WayTask/Resources/product_catalog_he.json catalogVersion 5 ${sourceId}.keywords`;

const additions = [
  add({ id: "hamburger_buns", name: "לחמניות המבורגר", sourceId: "bread_rolls", variantDescriptors: ["לחמניות המבורגר"], provenance: aliasSource("bread_rolls") }),
  add({ id: "sourdough_starter", name: "מחמצת", sourceId: "bread_sourdough", categoryId: "pantry", subcategoryId: "pantry.baking", semanticKey: "sourdough_starter", variantDescriptors: [], keywords: ["אפייה", "לחם"], provenance: aliasSource("bread_sourdough") }),
  add({ id: "butter_croissant", name: "קרואסון חמאה", sourceId: "croissant", variantDescriptors: ["קרואסון חמאה"], provenance: aliasSource("croissant") }),
  add({ id: "chocolate_yeast_cake", name: "עוגת שמרים שוקולד", sourceId: "yeast_cake", variantDescriptors: ["עוגת שמרים שוקולד"], provenance: aliasSource("yeast_cake") }),
  add({ id: "brioche", name: "בריוש", sourceId: "brioche_rolls", semanticKey: "brioche", variantDescriptors: [], provenance: aliasSource("brioche_rolls") }),
  add({ id: "green_grapes", name: "ענבים ירוקים", sourceId: "grapes", variantDescriptors: ["ענבים ירוקים"], provenance: aliasSource("grapes") }),
  add({ id: "black_grapes", name: "ענבים שחורים", sourceId: "grapes", variantDescriptors: ["ענבים שחורים"], provenance: aliasSource("grapes") }),
  add({ id: "lettuce_hearts", name: "לבבות חסה", sourceId: "lettuce", variantDescriptors: ["לבבות חסה"], provenance: aliasSource("lettuce") }),
  add({ id: "champignon_mushrooms", name: "פטריות שמפיניון", sourceId: "fresh_mushrooms", variantDescriptors: ["פטריות שמפיניון"], provenance: aliasSource("fresh_mushrooms") }),
  add({ id: "entrecote", name: "אנטרקוט", sourceId: "beef_steak", variantDescriptors: ["אנטרקוט"], provenance: aliasSource("beef_steak") }),
  add({ id: "calf_liver", name: "כבד עגל", sourceId: "beef_liver", variantDescriptors: ["כבד עגל"], provenance: aliasSource("beef_liver") }),
  add({ id: "green_lentils", name: "עדשים ירוקות", sourceId: "dry_lentils", variantDescriptors: ["עדשים ירוקות"], provenance: aliasSource("dry_lentils") }),
  add({ id: "orange_lentils", name: "עדשים כתומות", sourceId: "dry_lentils", variantDescriptors: ["עדשים כתומות"], provenance: aliasSource("dry_lentils") }),
  add({ id: "whole_tahini", name: "טחינה מלאה", sourceId: "tahini_raw", variantDescriptors: ["טחינה מלאה"], provenance: aliasSource("tahini_raw") }),
  add({ id: "white_sugar", name: "סוכר לבן", sourceId: "sugar", variantDescriptors: ["סוכר לבן"], provenance: aliasSource("sugar") }),
  add({ id: "popcorn_kernels", name: "תירס לפופקורן", sourceId: "popcorn", categoryId: "pantry", subcategoryId: null, semanticKey: "popcorn", variantDescriptors: ["תירס לפופקורן"], keywords: ["תירס", "נשנוש"], provenance: aliasSource("popcorn") }),
  add({ id: "ground_black_pepper", name: "פלפל שחור טחון", sourceId: "black_pepper", variantDescriptors: ["פלפל שחור טחון"], provenance: aliasSource("black_pepper") }),
  add({ id: "ground_cumin", name: "כמון טחון", sourceId: "cumin", variantDescriptors: ["כמון טחון"], provenance: aliasSource("cumin") }),
  add({ id: "ground_turmeric", name: "כורכום טחון", sourceId: "turmeric", variantDescriptors: ["כורכום טחון"], provenance: aliasSource("turmeric") }),
  add({ id: "ground_cinnamon", name: "קינמון טחון", sourceId: "cinnamon", variantDescriptors: ["קינמון טחון"], provenance: aliasSource("cinnamon") }),
  add({ id: "ground_hot_paprika", name: "פפריקה חריפה טחונה", sourceId: "hot_paprika", variantDescriptors: ["פפריקה חריפה טחונה"], provenance: aliasSource("hot_paprika") }),
  add({ id: "ground_white_pepper", name: "פלפל לבן טחון", sourceId: "white_pepper", variantDescriptors: ["פלפל לבן טחון"], provenance: aliasSource("white_pepper") }),
  add({ id: "ground_nutmeg", name: "מוסקט טחון", sourceId: "nutmeg", variantDescriptors: ["מוסקט טחון"], provenance: aliasSource("nutmeg") }),
  add({ id: "coconut_flakes", name: "פתיתי קוקוס", sourceId: "shredded_coconut", variantDescriptors: ["פתיתי קוקוס"], provenance: aliasSource("shredded_coconut") }),
  add({ id: "buckwheat_flour", name: "קמח כוסמת", categoryId: "pantry", subcategoryId: "pantry.baking", semanticKey: "buckwheat_flour", aliases: ["קמח מכוסמת"], keywords: ["אפייה", "כוסמת"], brandTerms: [], popularityScore: 78, provenance: "PRODUCT_CATALOG_GUIDE.md lines 191-203 reviewed canonical example" }),
  add({ id: "hazelnut_spread", name: "ממרח אגוזי לוז", english: "Hazelnut Spread", categoryId: "pantry", subcategoryId: "pantry.breakfast", semanticKey: "hazelnut_spread", aliases: [], keywords: [], brandTerms: ["נוטלה"], popularityScore: 82, provenance: "docs/Specifications/CanonicalProductCatalogSpecification.md sections 6.1-6.2; popularity baseline from catalog v5 chocolate_spread" }),
  add({ id: "dried_fruit", name: "פירות יבשים", sourceId: "chocolate_coated_raisins", semanticKey: "dried_fruit", variantDescriptors: [], keywords: [], provenance: keywordSource("chocolate_coated_raisins") }),
  add({ id: "milk_chocolate", name: "שוקולד חלב", sourceId: "chocolate_bar", variantDescriptors: ["שוקולד חלב"], provenance: aliasSource("chocolate_bar") }),
  add({ id: "chocolate_wafers", name: "ופל שוקולד", sourceId: "wafers", variantDescriptors: ["ופל שוקולד"], provenance: aliasSource("wafers") }),
  add({ id: "coffee", name: "קפה", english: "Coffee", categoryId: "drinks", subcategoryId: "drinks.coffee", semanticKey: "coffee", aliases: [], keywords: [], brandTerms: [], popularityScore: 93, provenance: "docs/Product/PilotProductCatalog.md canonical bilingual product prd_pilot_0008; popularity baseline from catalog v5 instant_coffee" }),
  add({ id: "tea_bags", name: "תיונים", sourceId: "black_tea", aliases: ["שקיקי תה"], variantDescriptors: ["תיונים"], provenance: aliasSource("black_tea") }),
  add({ id: "laundry_powder", name: "אבקת כביסה", sourceId: "laundry_detergent", variantDescriptors: ["אבקת כביסה"], provenance: aliasSource("laundry_detergent") }),
  add({ id: "laundry_liquid", name: "נוזל כביסה", sourceId: "laundry_detergent", variantDescriptors: ["נוזל כביסה"], provenance: aliasSource("laundry_detergent") }),
  add({ id: "dishwasher_capsules", name: "קפסולות למדיח", sourceId: "dishwasher_tablets", variantDescriptors: ["קפסולות למדיח"], provenance: aliasSource("dishwasher_tablets") }),
  add({ id: "deodorant_spray", name: "דאודורנט ספריי", sourceId: "deodorant", variantDescriptors: ["דאודורנט ספריי"], provenance: aliasSource("deodorant") }),
  add({ id: "deodorant_stick", name: "דאודורנט סטיק", sourceId: "deodorant", variantDescriptors: ["דאודורנט סטיק"], provenance: aliasSource("deodorant") }),
  add({ id: "shaving_gel", name: "ג׳ל גילוח", sourceId: "shaving_foam", variantDescriptors: ["ג׳ל גילוח"], provenance: aliasSource("shaving_foam") }),
  add({ id: "fruit_baby_puree", name: "מחית פירות לתינוק", sourceId: "baby_puree", variantDescriptors: ["מחית פירות לתינוק"], brandTerms: [], provenance: aliasSource("baby_puree") }),
  add({ id: "plastic_disposable_cups", name: "כוסות פלסטיק", sourceId: "disposable_cups", variantDescriptors: ["כוסות פלסטיק"], provenance: aliasSource("disposable_cups") }),
  add({ id: "plastic_disposable_plates", name: "צלחות פלסטיק", sourceId: "disposable_plates", variantDescriptors: ["צלחות פלסטיק"], provenance: aliasSource("disposable_plates") }),
  add({ id: "plastic_disposable_forks", name: "מזלגות פלסטיק", sourceId: "disposable_forks", variantDescriptors: ["מזלגות פלסטיק"], provenance: aliasSource("disposable_forks") }),
  add({ id: "plastic_disposable_knives", name: "סכינים פלסטיק", sourceId: "disposable_knives", variantDescriptors: ["סכינים פלסטיק"], provenance: aliasSource("disposable_knives") }),
  add({ id: "plastic_disposable_spoons", name: "כפיות פלסטיק", sourceId: "disposable_spoons", variantDescriptors: ["כפיות פלסטיק"], provenance: aliasSource("disposable_spoons") }),
  add({ id: "sandwich_bags", name: "שקיות סנדוויץ׳", sourceId: "food_storage_bags", aliases: ["שקיות כריכים"], variantDescriptors: ["שקיות סנדוויץ׳"], provenance: aliasSource("food_storage_bags") }),
  add({ id: "dog_harness", name: "רתמה לכלב", sourceId: "pet_harness", variantDescriptors: ["רתמה לכלב"], provenance: aliasSource("pet_harness") }),
  add({ id: "cat_harness", name: "רתמה לחתול", sourceId: "pet_harness", variantDescriptors: ["רתמה לחתול"], provenance: aliasSource("pet_harness") }),
  add({ id: "dog_bed", name: "מיטה לכלב", sourceId: "pet_bed", variantDescriptors: ["מיטה לכלב"], provenance: aliasSource("pet_bed") }),
  add({ id: "cat_bed", name: "מיטה לחתול", sourceId: "pet_bed", variantDescriptors: ["מיטה לחתול"], provenance: aliasSource("pet_bed") }),
  add({ id: "tick_treatment", name: "חומר נגד קרציות", sourceId: "pet_flea_treatment", semanticKey: "pet_parasite_treatment", variantDescriptors: ["קרציות"], provenance: aliasSource("pet_flea_treatment") }),
  add({ id: "rabbit_hay", name: "חציר לארנבים", sourceId: "small_pet_hay", variantDescriptors: ["חציר לארנבים"], provenance: aliasSource("small_pet_hay") }),
  add({ id: "soft_pet_carrier", name: "תיק נשיאה לחיות מחמד", sourceId: "pet_carrier", variantDescriptors: ["תיק נשיאה לחיות מחמד"], provenance: aliasSource("pet_carrier") }),
  add({ id: "antacid_tablets", name: "טבליות לצרבת", sourceId: "antacid", variantDescriptors: ["טבליות לצרבת"], provenance: aliasSource("antacid") }),
  add({ id: "sliced_cheese", name: "פרוסות גבינה", sourceId: "yellow_cheese", aliases: ["גבינה לפרוסות"], variantDescriptors: ["פרוסות גבינה"], provenance: aliasSource("yellow_cheese") }),
];

const release = {
  schemaVersion: 1,
  catalogVersion: 6,
  taxonomyVersion: 1,
  generationDate: "2026-08-06",
  productCount: catalog.products.length + additions.length,
  releaseId: "wt-031c-wave-1",
  supportedLocales: ["en", "he-IL"],
  operations: [
    ...Object.entries(replacementEdits).map(([id, edits]) =>
      replacementOperation(id, edits)
    ),
    ...additions,
  ],
};

if (additions.length !== 53 || release.productCount !== 700) {
  throw new Error("WT-031C curated count invariant failed.");
}

fs.writeFileSync(outputPath, `${JSON.stringify(release, null, 2)}\n`);
console.log(
  `Wrote ${path.relative(repoRoot, outputPath)} with ${additions.length} additions and ${Object.keys(replacementEdits).length} replacements.`,
);
