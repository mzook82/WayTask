"use strict";

const { normalizedValue } = require("./normalization");

const DEFAULT_STABLE_ID = "^[a-z][a-z0-9_]*$";
const DEFAULT_SUBCATEGORY_ID =
  "^[a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*$";
const REVIEW_STATUSES = new Set([
  "confirmed",
  "reclassified",
  "canonical_name_updated",
  "alias_updated",
  "brand_term_updated",
]);

function issue(code, message, details = {}) {
  return { code, message, ...details };
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function nonEmptyText(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function normalizedBarcode(value) {
  if (typeof value !== "string") {
    return null;
  }
  const normalized = value.replace(/[\s-]+/g, "");
  return /^(?:\d{8}|\d{12}|\d{13}|\d{14})$/.test(normalized)
    ? normalized
    : null;
}

function hasValidGTINCheckDigit(value) {
  const barcode = normalizedBarcode(value);
  if (barcode === null) {
    return false;
  }
  const digits = [...barcode].map(Number);
  const checkDigit = digits.pop();
  let sum = 0;
  for (let index = digits.length - 1, weight = 3;
    index >= 0;
    index -= 1, weight = weight === 3 ? 1 : 3) {
    sum += digits[index] * weight;
  }
  return (10 - (sum % 10)) % 10 === checkDigit;
}

function addError(errors, code, message, details = {}) {
  errors.push(issue(code, message, details));
}

function schemaPatterns(schema) {
  return {
    stableId: new RegExp(
      schema?.$defs?.stableId?.pattern ?? DEFAULT_STABLE_ID,
    ),
    subcategoryId: new RegExp(
      schema?.$defs?.product?.properties?.subcategoryId?.oneOf?.find(
        (entry) => entry.type === "string",
      )?.pattern ?? DEFAULT_SUBCATEGORY_ID,
    ),
    locale: new RegExp(
      schema?.properties?.locale?.pattern ??
        "^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$",
    ),
  };
}

function validateTextArray({
  product,
  field,
  errors,
  productIndex,
}) {
  const values = product[field];
  if (!Array.isArray(values)) {
    addError(
      errors,
      "schema.invalid_type",
      `Product ${product.id ?? `at index ${productIndex}`} field ${field} must be an array.`,
      { productId: product.id, field },
    );
    return;
  }

  const raw = new Set();
  const normalized = new Map();
  for (const [index, value] of values.entries()) {
    if (!nonEmptyText(value)) {
      addError(
        errors,
        "product.empty_text_value",
        `Product ${product.id ?? `at index ${productIndex}`} has an empty ${field}[${index}].`,
        { productId: product.id, field, index },
      );
      continue;
    }
    if (raw.has(value)) {
      addError(
        errors,
        "schema.duplicate_array_item",
        `Product ${product.id} repeats ${JSON.stringify(value)} in ${field}.`,
        { productId: product.id, field, value },
      );
    }
    raw.add(value);

    const key = normalizedValue(value);
    if (normalized.has(key)) {
      addError(
        errors,
        "product.duplicate_normalized_value",
        `Product ${product.id} has multiple ${field} values that normalize to ${JSON.stringify(key)}.`,
        {
          productId: product.id,
          field,
          normalizedValue: key,
          values: [normalized.get(key), value],
        },
      );
    } else {
      normalized.set(key, value);
    }
  }
}

function validateProductShape(product, index, schema, patterns, errors) {
  const required = schema?.$defs?.product?.required ?? [
    "id",
    "canonicalName",
    "categoryId",
    "subcategoryId",
    "aliases",
    "keywords",
    "brandTerms",
    "popularityScore",
    "isActive",
  ];
  const allowed = new Set(
    Object.keys(schema?.$defs?.product?.properties ?? {}),
  );

  if (!isObject(product)) {
    addError(
      errors,
      "schema.invalid_product",
      `Catalog product at index ${index} must be an object.`,
      { productIndex: index },
    );
    return;
  }

  for (const field of required) {
    if (!Object.hasOwn(product, field)) {
      addError(
        errors,
        "schema.missing_required_field",
        `Product ${product.id ?? `at index ${index}`} is missing required field ${field}.`,
        { productId: product.id, field, productIndex: index },
      );
    }
  }
  for (const field of Object.keys(product)) {
    if (allowed.size > 0 && !allowed.has(field)) {
      addError(
        errors,
        "schema.unknown_product_field",
        `Product ${product.id ?? `at index ${index}`} contains unsupported field ${field}.`,
        { productId: product.id, field, productIndex: index },
      );
    }
  }

  if (
    typeof product.id !== "string" ||
    !patterns.stableId.test(product.id)
  ) {
    addError(
      errors,
      "product.invalid_id",
      `Product at index ${index} has invalid stable ID ${JSON.stringify(product.id)}.`,
      { productId: product.id, productIndex: index },
    );
  }
  for (const field of ["canonicalName", "categoryId"]) {
    if (!nonEmptyText(product[field])) {
      addError(
        errors,
        "product.empty_required_field",
        `Product ${product.id ?? `at index ${index}`} has an empty ${field}.`,
        { productId: product.id, field },
      );
    }
  }
  if (
    typeof product.categoryId === "string" &&
    !patterns.stableId.test(product.categoryId)
  ) {
    addError(
      errors,
      "product.invalid_category_id",
      `Product ${product.id} has invalid category ID ${product.categoryId}.`,
      { productId: product.id, categoryId: product.categoryId },
    );
  }
  if (
    product.subcategoryId !== null &&
    (typeof product.subcategoryId !== "string" ||
      !patterns.subcategoryId.test(product.subcategoryId))
  ) {
    addError(
      errors,
      "product.invalid_subcategory_id",
      `Product ${product.id} has invalid subcategory ID ${JSON.stringify(product.subcategoryId)}.`,
      { productId: product.id, subcategoryId: product.subcategoryId },
    );
  }

  for (const field of [
    "aliases",
    "keywords",
    "brandTerms",
    ...(Object.hasOwn(product, "variantDescriptors")
      ? ["variantDescriptors"]
      : []),
    ...(Object.hasOwn(product, "barcodes") ? ["barcodes"] : []),
    ...(Object.hasOwn(product, "legacyNames") ? ["legacyNames"] : []),
  ]) {
    validateTextArray({
      product,
      field,
      errors,
      productIndex: index,
    });
  }

  const popularity =
    schema?.$defs?.product?.properties?.popularityScore ?? {};
  if (
    !Number.isInteger(product.popularityScore) ||
    product.popularityScore < (popularity.minimum ?? 0) ||
    product.popularityScore > (popularity.maximum ?? 100)
  ) {
    addError(
      errors,
      "product.invalid_popularity",
      `Product ${product.id} popularityScore must be an integer from ${popularity.minimum ?? 0} through ${popularity.maximum ?? 100}.`,
      { productId: product.id, popularityScore: product.popularityScore },
    );
  }
  if (typeof product.isActive !== "boolean") {
    addError(
      errors,
      "schema.invalid_type",
      `Product ${product.id} isActive must be a boolean.`,
      { productId: product.id, field: "isActive" },
    );
  }
  for (const field of [
    "semanticKey",
    "brand",
    "packageDescriptor",
    "unit",
    "provenance",
  ]) {
    if (
      Object.hasOwn(product, field) &&
      product[field] !== null &&
      !nonEmptyText(product[field])
    ) {
      addError(
        errors,
        "product.invalid_optional_text",
        `Product ${product.id} field ${field} must be null or nonempty text.`,
        { productId: product.id, field },
      );
    }
  }
  for (const barcode of Array.isArray(product.barcodes)
    ? product.barcodes
    : []) {
    if (!hasValidGTINCheckDigit(barcode)) {
      addError(
        errors,
        "product.malformed_barcode",
        `Product ${product.id} has malformed GTIN/barcode ${JSON.stringify(barcode)}.`,
        { productId: product.id, barcode },
      );
    }
  }
  if (
    Object.hasOwn(product, "replacementProductId") &&
    product.replacementProductId !== null &&
    (typeof product.replacementProductId !== "string" ||
      !patterns.stableId.test(product.replacementProductId))
  ) {
    addError(
      errors,
      "product.invalid_replacement_id",
      `Product ${product.id} has invalid replacementProductId.`,
      { productId: product.id },
    );
  }
  if (
    Object.hasOwn(product, "deprecatedSinceCatalogVersion") &&
    product.deprecatedSinceCatalogVersion !== null &&
    (!Number.isInteger(product.deprecatedSinceCatalogVersion) ||
      product.deprecatedSinceCatalogVersion < 1)
  ) {
    addError(
      errors,
      "product.invalid_deprecation_version",
      `Product ${product.id} has invalid deprecatedSinceCatalogVersion.`,
      { productId: product.id },
    );
  }
  if (
    Object.hasOwn(product, "metadata") &&
    !isObject(product.metadata)
  ) {
    addError(
      errors,
      "schema.invalid_type",
      `Product ${product.id} metadata must be an object.`,
      { productId: product.id, field: "metadata" },
    );
  }
}

function validateDocumentShape(catalog, schema, patterns, errors) {
  if (!isObject(catalog)) {
    addError(
      errors,
      "schema.invalid_document",
      "Catalog document must be a JSON object.",
    );
    return;
  }

  const required = schema?.required ?? [
    "schemaVersion",
    "catalogVersion",
    "taxonomyVersion",
    "locale",
    "products",
  ];
  const allowed = new Set(Object.keys(schema?.properties ?? {}));
  for (const field of required) {
    if (!Object.hasOwn(catalog, field)) {
      addError(
        errors,
        "schema.missing_top_level_field",
        `Catalog is missing required top-level field ${field}.`,
        { field },
      );
    }
  }
  for (const field of Object.keys(catalog)) {
    if (allowed.size > 0 && !allowed.has(field)) {
      addError(
        errors,
        "schema.unknown_top_level_field",
        `Catalog contains unsupported top-level field ${field}.`,
        { field },
      );
    }
  }

  const requiredSchemaVersion =
    schema?.properties?.schemaVersion?.const ?? 1;
  if (catalog.schemaVersion !== requiredSchemaVersion) {
    addError(
      errors,
      "catalog.unsupported_schema_version",
      `schemaVersion must be ${requiredSchemaVersion}; found ${JSON.stringify(catalog.schemaVersion)}.`,
      { schemaVersion: catalog.schemaVersion },
    );
  }
  for (const field of ["catalogVersion", "taxonomyVersion"]) {
    if (!Number.isInteger(catalog[field]) || catalog[field] < 1) {
      addError(
        errors,
        "schema.invalid_version",
        `${field} must be a positive integer.`,
        { field, value: catalog[field] },
      );
    }
  }
  if (
    typeof catalog.locale !== "string" ||
    !patterns.locale.test(catalog.locale)
  ) {
    addError(
      errors,
      "schema.invalid_locale",
      `Catalog locale is invalid: ${JSON.stringify(catalog.locale)}.`,
      { locale: catalog.locale },
    );
  }
  if (!Array.isArray(catalog.products)) {
    addError(
      errors,
      "schema.invalid_products",
      "Catalog products must be an array.",
    );
    return;
  }
  catalog.products.forEach((product, index) =>
    validateProductShape(product, index, schema, patterns, errors),
  );
}

function validateTaxonomy(taxonomy, patterns, errors) {
  const categoryById = new Map();
  const subcategoryById = new Map();

  if (!isObject(taxonomy)) {
    addError(
      errors,
      "taxonomy.invalid_document",
      "Taxonomy must be a JSON object.",
    );
    return { categoryById, subcategoryById };
  }
  if (!Number.isInteger(taxonomy.taxonomyVersion) ||
      taxonomy.taxonomyVersion < 1) {
    addError(
      errors,
      "taxonomy.invalid_version",
      "taxonomyVersion must be a positive integer.",
    );
  }
  if (!nonEmptyText(taxonomy.locale)) {
    addError(errors, "taxonomy.invalid_locale", "Taxonomy locale is empty.");
  }
  if (!Array.isArray(taxonomy.categories)) {
    addError(
      errors,
      "taxonomy.invalid_categories",
      "Taxonomy categories must be an array.",
    );
    return { categoryById, subcategoryById };
  }

  for (const category of taxonomy.categories) {
    if (
      !isObject(category) ||
      !patterns.stableId.test(category.id ?? "")
    ) {
      addError(
        errors,
        "taxonomy.invalid_category_id",
        `Taxonomy category has invalid ID ${JSON.stringify(category?.id)}.`,
      );
      continue;
    }
    if (categoryById.has(category.id)) {
      addError(
        errors,
        "taxonomy.duplicate_category_id",
        `Taxonomy category ID ${category.id} is duplicated.`,
        { categoryId: category.id },
      );
    }
    categoryById.set(category.id, category);
    if (
      !nonEmptyText(category.canonicalName) ||
      !nonEmptyText(category.localizedNames?.[taxonomy.locale])
    ) {
      addError(
        errors,
        "taxonomy.empty_category_name",
        `Taxonomy category ${category.id} lacks a canonical or ${taxonomy.locale} name.`,
        { categoryId: category.id },
      );
    }
    if (!Array.isArray(category.subcategories)) {
      addError(
        errors,
        "taxonomy.invalid_subcategories",
        `Taxonomy category ${category.id} subcategories must be an array.`,
        { categoryId: category.id },
      );
      continue;
    }

    for (const subcategory of category.subcategories) {
      if (
        !isObject(subcategory) ||
        !patterns.subcategoryId.test(subcategory.id ?? "")
      ) {
        addError(
          errors,
          "taxonomy.invalid_subcategory_id",
          `Taxonomy subcategory has invalid ID ${JSON.stringify(subcategory?.id)}.`,
          { categoryId: category.id },
        );
        continue;
      }
      if (subcategoryById.has(subcategory.id)) {
        addError(
          errors,
          "taxonomy.duplicate_subcategory_id",
          `Taxonomy subcategory ID ${subcategory.id} is duplicated.`,
          { subcategoryId: subcategory.id },
        );
      }
      subcategoryById.set(subcategory.id, subcategory);
      if (subcategory.parentCategoryId !== category.id) {
        addError(
          errors,
          "taxonomy.subcategory_parent_mismatch",
          `Subcategory ${subcategory.id} declares parent ${subcategory.parentCategoryId}, but is contained by ${category.id}.`,
          { subcategoryId: subcategory.id, categoryId: category.id },
        );
      }
      if (
        !nonEmptyText(subcategory.canonicalName) ||
        !nonEmptyText(subcategory.localizedNames?.[taxonomy.locale])
      ) {
        addError(
          errors,
          "taxonomy.empty_subcategory_name",
          `Taxonomy subcategory ${subcategory.id} lacks a canonical or ${taxonomy.locale} name.`,
          { subcategoryId: subcategory.id },
        );
      }
    }
  }

  if (Array.isArray(taxonomy.compatibilityMappings)) {
    const legacyIds = new Set();
    for (const mapping of taxonomy.compatibilityMappings) {
      if (
        !patterns.stableId.test(mapping.legacyCategoryId ?? "") ||
        legacyIds.has(mapping.legacyCategoryId)
      ) {
        addError(
          errors,
          "taxonomy.invalid_compatibility_mapping",
          `Invalid or duplicate legacy category mapping ${JSON.stringify(mapping.legacyCategoryId)}.`,
        );
      }
      legacyIds.add(mapping.legacyCategoryId);
      if (!categoryById.has(mapping.canonicalCategoryId)) {
        addError(
          errors,
          "taxonomy.orphan_compatibility_category",
          `Legacy mapping ${mapping.legacyCategoryId} references missing category ${mapping.canonicalCategoryId}.`,
        );
      }
      if (mapping.canonicalSubcategoryId !== null) {
        const subcategory = subcategoryById.get(
          mapping.canonicalSubcategoryId,
        );
        if (!subcategory) {
          addError(
            errors,
            "taxonomy.orphan_compatibility_subcategory",
            `Legacy mapping ${mapping.legacyCategoryId} references missing subcategory ${mapping.canonicalSubcategoryId}.`,
          );
        } else if (
          subcategory.parentCategoryId !== mapping.canonicalCategoryId
        ) {
          addError(
            errors,
            "taxonomy.compatibility_parent_mismatch",
            `Legacy mapping ${mapping.legacyCategoryId} has mismatched category and subcategory targets.`,
          );
        }
      }
    }
  }
  return { categoryById, subcategoryById };
}

function validateProductRelationships(
  catalog,
  taxonomyIndex,
  errors,
  warnings,
) {
  if (!Array.isArray(catalog.products)) {
    return;
  }
  const productsById = new Map();
  const canonicalNames = new Map();
  const barcodeOwners = new Map();

  for (const product of catalog.products) {
    if (!isObject(product) || typeof product.id !== "string") {
      continue;
    }
    if (productsById.has(product.id)) {
      addError(
        errors,
        "product.duplicate_id",
        `Product ID ${product.id} is duplicated.`,
        { productId: product.id },
      );
    }
    productsById.set(product.id, product);

    if (nonEmptyText(product.canonicalName)) {
      const key = normalizedValue(product.canonicalName);
      const owner = canonicalNames.get(key);
      if (owner && owner !== product.id) {
        addError(
          errors,
          "product.duplicate_canonical_name",
          `Products ${owner} and ${product.id} share normalized canonical name ${JSON.stringify(key)}.`,
          {
            productId: product.id,
            relatedProductId: owner,
            normalizedValue: key,
          },
        );
      } else {
        canonicalNames.set(key, product.id);
      }
    }

    const category = taxonomyIndex.categoryById.get(product.categoryId);
    if (!category) {
      addError(
        errors,
        "product.orphan_category",
        `Product ${product.id} references missing category ${product.categoryId}.`,
        { productId: product.id, categoryId: product.categoryId },
      );
    }
    if (product.subcategoryId !== null) {
      const subcategory = taxonomyIndex.subcategoryById.get(
        product.subcategoryId,
      );
      if (!subcategory) {
        addError(
          errors,
          "product.orphan_subcategory",
          `Product ${product.id} references missing subcategory ${product.subcategoryId}.`,
          { productId: product.id, subcategoryId: product.subcategoryId },
        );
      } else if (subcategory.parentCategoryId !== product.categoryId) {
        addError(
          errors,
          "product.subcategory_parent_mismatch",
          `Product ${product.id} assigns ${product.subcategoryId} under category ${product.categoryId}; expected ${subcategory.parentCategoryId}.`,
          {
            productId: product.id,
            categoryId: product.categoryId,
            subcategoryId: product.subcategoryId,
          },
        );
      }
    }
    if (product.isActive && product.categoryId === "uncategorized") {
      warnings.push(
        issue(
          "product.uncategorized",
          `Active product ${product.id} is assigned to uncategorized.`,
          { productId: product.id },
        ),
      );
    }
    for (const barcode of Array.isArray(product.barcodes)
      ? product.barcodes
      : []) {
      const key = normalizedBarcode(barcode);
      if (key === null) {
        continue;
      }
      const owner = barcodeOwners.get(key);
      if (owner && owner !== product.id) {
        addError(
          errors,
          "product.conflicting_barcode",
          `Products ${owner} and ${product.id} share normalized barcode ${key}.`,
          {
            productId: product.id,
            relatedProductId: owner,
            barcode: key,
          },
        );
      } else {
        barcodeOwners.set(key, product.id);
      }
    }
  }

  const activeCanonicalNames = new Map(
    [...canonicalNames].filter(
      ([, productId]) => productsById.get(productId)?.isActive === true,
    ),
  );
  const activeAliases = new Map();
  for (const product of catalog.products.filter(
    (entry) => isObject(entry) && entry.isActive === true,
  )) {
    const ownName = normalizedValue(product.canonicalName);
    for (const alias of Array.isArray(product.aliases)
      ? product.aliases
      : []) {
      if (!nonEmptyText(alias)) {
        continue;
      }
      const key = normalizedValue(alias);
      if (key === ownName) {
        addError(
          errors,
          "product.alias_matches_own_name",
          `Alias ${JSON.stringify(alias)} on ${product.id} repeats its canonical name after normalization.`,
          { productId: product.id, alias },
        );
      }
      const canonicalOwner = activeCanonicalNames.get(key);
      if (canonicalOwner && canonicalOwner !== product.id) {
        addError(
          errors,
          "product.alias_matches_canonical_name",
          `Alias ${JSON.stringify(alias)} on ${product.id} matches canonical name of ${canonicalOwner}.`,
          {
            productId: product.id,
            relatedProductId: canonicalOwner,
            alias,
          },
        );
      }
      const aliasOwner = activeAliases.get(key);
      if (aliasOwner && aliasOwner.productId !== product.id) {
        addError(
          errors,
          "product.alias_collision",
          `Alias ${JSON.stringify(alias)} on ${product.id} collides with ${JSON.stringify(aliasOwner.alias)} on ${aliasOwner.productId}.`,
          {
            productId: product.id,
            relatedProductId: aliasOwner.productId,
            alias,
          },
        );
      } else {
        activeAliases.set(key, { productId: product.id, alias });
      }
    }
  }

  for (const product of catalog.products.filter(
    (entry) => isObject(entry) && entry.isActive === true,
  )) {
    for (const brandTerm of Array.isArray(product.brandTerms)
      ? product.brandTerms
      : []) {
      if (!nonEmptyText(brandTerm)) {
        continue;
      }
      const key = normalizedValue(brandTerm);
      const canonicalOwner = activeCanonicalNames.get(key);
      if (canonicalOwner) {
        addError(
          errors,
          "product.brand_term_matches_canonical_name",
          `Brand term ${JSON.stringify(brandTerm)} on ${product.id} matches canonical name of ${canonicalOwner}.`,
          {
            productId: product.id,
            relatedProductId: canonicalOwner,
            brandTerm,
          },
        );
      }
      const aliasOwner = activeAliases.get(key);
      if (aliasOwner) {
        addError(
          errors,
          "product.brand_term_matches_alias",
          `Brand term ${JSON.stringify(brandTerm)} on ${product.id} matches alias on ${aliasOwner.productId}.`,
          {
            productId: product.id,
            relatedProductId: aliasOwner.productId,
            brandTerm,
          },
        );
      }
    }
  }

  for (const product of catalog.products.filter(isObject)) {
    const replacementId = product.replacementProductId;
    const deprecatedVersion = product.deprecatedSinceCatalogVersion;
    if (product.isActive && replacementId != null) {
      addError(
        errors,
        "replacement.active_product_has_replacement",
        `Active product ${product.id} cannot have replacementProductId.`,
        { productId: product.id },
      );
    }
    if (product.isActive && deprecatedVersion != null) {
      addError(
        errors,
        "replacement.active_product_is_deprecated",
        `Active product ${product.id} cannot have deprecation metadata.`,
        { productId: product.id },
      );
    }
    if (
      deprecatedVersion != null &&
      (!Number.isInteger(deprecatedVersion) ||
        deprecatedVersion < 1 ||
        deprecatedVersion > catalog.catalogVersion)
    ) {
      addError(
        errors,
        "replacement.invalid_deprecation_version",
        `Product ${product.id} deprecation version must be within this catalog history.`,
        { productId: product.id },
      );
    }
    if (replacementId != null) {
      if (replacementId === product.id) {
        addError(
          errors,
          "replacement.self_loop",
          `Product ${product.id} cannot replace itself.`,
          { productId: product.id },
        );
      }
      const target = productsById.get(replacementId);
      if (!target) {
        addError(
          errors,
          "replacement.missing_target",
          `Product ${product.id} references missing replacement ${replacementId}.`,
          { productId: product.id, replacementProductId: replacementId },
        );
      } else if (!target.isActive) {
        addError(
          errors,
          "replacement.inactive_target",
          `Product ${product.id} replacement ${replacementId} is inactive.`,
          { productId: product.id, replacementProductId: replacementId },
        );
      }
    }
  }

  const emittedCycles = new Set();
  for (const product of catalog.products.filter(isObject)) {
    const path = [];
    const visited = new Map();
    let currentId = product.id;
    while (currentId && productsById.has(currentId)) {
      if (visited.has(currentId)) {
        const cycle = [...path.slice(visited.get(currentId)), currentId];
        const key = [...new Set(cycle)].sort().join("|");
        if (!emittedCycles.has(key)) {
          emittedCycles.add(key);
          addError(
            errors,
            "replacement.loop",
            `Replacement loop detected: ${cycle.join(" -> ")}.`,
            { productId: product.id, cycle },
          );
        }
        break;
      }
      visited.set(currentId, path.length);
      path.push(currentId);
      currentId = productsById.get(currentId).replacementProductId;
    }
  }
}

function validateReviewManifest(catalog, review, errors) {
  if (review == null) {
    return;
  }
  if (!isObject(review) || !Array.isArray(review.products)) {
    addError(
      errors,
      "review.invalid_document",
      "Taxonomy review manifest must contain a products array.",
    );
    return;
  }
  for (const field of ["catalogVersion", "taxonomyVersion", "locale"]) {
    if (review[field] !== catalog[field]) {
      addError(
        errors,
        "review.metadata_mismatch",
        `Review manifest ${field} ${JSON.stringify(review[field])} does not match catalog ${JSON.stringify(catalog[field])}.`,
        { field },
      );
    }
  }
  if (review.productCount !== catalog.products.length) {
    addError(
      errors,
      "review.product_count_mismatch",
      `Review manifest productCount ${review.productCount} does not match catalog count ${catalog.products.length}.`,
    );
  }

  const catalogById = new Map(
    catalog.products
      .filter((product) => isObject(product))
      .map((product) => [product.id, product]),
  );
  const reviewIds = new Set();
  for (const entry of review.products) {
    if (!isObject(entry) || !nonEmptyText(entry.productId)) {
      addError(
        errors,
        "review.invalid_entry",
        "Review manifest contains an entry without productId.",
      );
      continue;
    }
    if (reviewIds.has(entry.productId)) {
      addError(
        errors,
        "review.duplicate_product",
        `Review manifest repeats product ${entry.productId}.`,
        { productId: entry.productId },
      );
    }
    reviewIds.add(entry.productId);
    const product = catalogById.get(entry.productId);
    if (!product) {
      addError(
        errors,
        "review.orphan_product",
        `Review manifest references missing product ${entry.productId}.`,
        { productId: entry.productId },
      );
      continue;
    }
    if (!REVIEW_STATUSES.has(entry.reviewStatus)) {
      addError(
        errors,
        "review.invalid_status",
        `Review entry ${entry.productId} has unsupported status ${JSON.stringify(entry.reviewStatus)}.`,
        { productId: entry.productId },
      );
    }
    if (
      entry.canonicalCategoryId !== product.categoryId ||
      entry.canonicalSubcategoryId !== product.subcategoryId
    ) {
      addError(
        errors,
        "review.taxonomy_mismatch",
        `Review entry ${entry.productId} does not match its catalog taxonomy assignment.`,
        { productId: entry.productId },
      );
    }
    if (
      entry.previousLegacyCategoryId !== null &&
      !nonEmptyText(entry.previousLegacyCategoryId)
    ) {
      addError(
        errors,
        "review.invalid_legacy_category",
        `Review entry ${entry.productId} has invalid previousLegacyCategoryId.`,
        { productId: entry.productId },
      );
    }
  }
  for (const productId of catalogById.keys()) {
    if (!reviewIds.has(productId)) {
      addError(
        errors,
        "review.missing_product",
        `Review manifest is missing product ${productId}.`,
        { productId },
      );
    }
  }
}

function validateCatalog({ catalog, schema, taxonomy, review = null }) {
  const errors = [];
  const warnings = [];
  const patterns = schemaPatterns(schema);

  validateDocumentShape(catalog, schema, patterns, errors);
  const taxonomyIndex = validateTaxonomy(taxonomy, patterns, errors);
  if (isObject(catalog) && isObject(taxonomy)) {
    if (catalog.taxonomyVersion !== taxonomy.taxonomyVersion) {
      addError(
        errors,
        "catalog.taxonomy_version_mismatch",
        `Catalog taxonomyVersion ${catalog.taxonomyVersion} does not match registry ${taxonomy.taxonomyVersion}.`,
      );
    }
    if (catalog.locale !== taxonomy.locale) {
      addError(
        errors,
        "catalog.taxonomy_locale_mismatch",
        `Catalog locale ${catalog.locale} does not match taxonomy locale ${taxonomy.locale}.`,
      );
    }
  }
  if (isObject(catalog)) {
    validateProductRelationships(
      catalog,
      taxonomyIndex,
      errors,
      warnings,
    );
    if (Array.isArray(catalog.products)) {
      validateReviewManifest(catalog, review, errors);
    }
  }

  errors.sort((left, right) =>
    `${left.productId ?? ""}:${left.code}:${left.message}`.localeCompare(
      `${right.productId ?? ""}:${right.code}:${right.message}`,
      "en",
    ),
  );
  warnings.sort((left, right) => left.message.localeCompare(right.message));

  const products = Array.isArray(catalog?.products) ? catalog.products : [];
  return {
    valid: errors.length === 0,
    errors,
    warnings,
    stats: {
      products: products.length,
      active: products.filter((product) => product?.isActive === true).length,
      inactive: products.filter((product) => product?.isActive === false)
        .length,
      categories: taxonomyIndex.categoryById.size,
      subcategories: taxonomyIndex.subcategoryById.size,
    },
  };
}

module.exports = {
  REVIEW_STATUSES,
  hasValidGTINCheckDigit,
  normalizedBarcode,
  validateCatalog,
};
