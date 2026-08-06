"use strict";

const fs = require("node:fs");
const {
  auditEntriesText,
  fileSha256,
  jsonText,
  readJson,
  sha256,
  writeTransaction,
} = require("./io");
const { loadContext } = require("./catalog");
const { normalizedValue } = require("./normalization");
const {
  hasValidGTINCheckDigit,
  normalizedBarcode,
  validateCatalog,
} = require("./validator");

const EDITORIAL_SCHEMA_VERSION = 1;
const RELEASE_MANIFEST_SCHEMA_VERSION = 1;
const PRIMARY_LOCALE = "he-IL";
const LOCALE_PATTERN = /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/;
const STABLE_ID_PATTERN = /^[a-z][a-z0-9_]*$/;
const SUBCATEGORY_ID_PATTERN =
  /^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/;
const RELEASE_ID_PATTERN = /^[a-z0-9][a-z0-9._-]*$/;
const TERM_FIELDS = [
  "localizedDisplayNames",
  "aliases",
  "keywords",
  "brandTerms",
  "legacyNames",
];
const REQUIRED_TERM_FIELDS = TERM_FIELDS.filter(
  (field) => field !== "legacyNames",
);

function clone(value) {
  return structuredClone(value);
}

function issue(code, message, details = {}) {
  return { code, message, ...details };
}

function addError(errors, code, message, details = {}) {
  errors.push(issue(code, message, details));
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function nonEmptyText(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function isValidDate(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }
  const date = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(date.valueOf()) &&
    date.toISOString().slice(0, 10) === value;
}

function taxonomyIndexes(taxonomy) {
  const categories = new Map();
  const subcategories = new Map();
  for (const category of taxonomy?.categories ?? []) {
    categories.set(category.id, category);
    for (const subcategory of category.subcategories ?? []) {
      subcategories.set(subcategory.id, subcategory);
    }
  }
  return { categories, subcategories };
}

function validateLocalizedTerms(product, field, errors, locales) {
  const terms = product[field];
  if (!Array.isArray(terms)) {
    addError(
      errors,
      "editorial.invalid_localized_terms",
      `Product ${product.id ?? "<unknown>"} field ${field} must be an array.`,
      { productId: product.id, field },
    );
    return [];
  }

  const seen = new Map();
  const valid = [];
  for (const [index, term] of terms.entries()) {
    if (
      !isObject(term) ||
      Object.keys(term).some((key) => !["locale", "value"].includes(key)) ||
      !LOCALE_PATTERN.test(term.locale ?? "") ||
      !nonEmptyText(term.value)
    ) {
      addError(
        errors,
        field === "keywords"
          ? "editorial.invalid_keyword"
          : "editorial.invalid_localized_name",
        `Product ${product.id ?? "<unknown>"} has invalid ${field}[${index}].`,
        { productId: product.id, field, index },
      );
      continue;
    }
    const normalized = normalizedValue(term.value);
    if (normalized.length === 0 || term.value.length > 120) {
      addError(
        errors,
        field === "keywords"
          ? "editorial.invalid_keyword"
          : "editorial.invalid_localized_name",
        `Product ${product.id} ${field}[${index}] cannot be indexed safely.`,
        { productId: product.id, field, index, value: term.value },
      );
      continue;
    }
    if (field === "keywords" && normalized.split(" ").length > 10) {
      addError(
        errors,
        "editorial.invalid_keyword",
        `Product ${product.id} keyword ${JSON.stringify(term.value)} is too broad; limit keywords to ten normalized tokens.`,
        { productId: product.id, field, index, value: term.value },
      );
    }
    const key = `${term.locale}:${normalized}`;
    if (seen.has(key)) {
      addError(
        errors,
        "editorial.duplicate_locale_name",
        `Product ${product.id} repeats ${JSON.stringify(term.value)} in ${field} for ${term.locale}.`,
        { productId: product.id, field, locale: term.locale },
      );
    } else {
      seen.set(key, term.value);
    }
    locales.add(term.locale);
    valid.push(term);
  }
  return valid;
}

function validateEditorialProduct(product, errors, taxonomy, locales) {
  if (!isObject(product)) {
    addError(
      errors,
      "editorial.invalid_product",
      "Editorial product must be an object.",
    );
    return;
  }
  const required = new Set([
    "id",
    "canonicalNames",
    ...REQUIRED_TERM_FIELDS,
    "categoryId",
    "subcategoryId",
    "barcodes",
    "variantDescriptors",
    "popularityScore",
    "status",
  ]);
  const allowed = new Set([
    ...required,
    "legacyNames",
    "brand",
    "semanticKey",
    "packageDescriptor",
    "unit",
    "provenance",
    "metadata",
  ]);
  for (const field of required) {
    if (!Object.hasOwn(product, field)) {
      addError(
        errors,
        "editorial.missing_product_field",
        `Product ${product.id ?? "<unknown>"} is missing ${field}.`,
        { productId: product.id, field },
      );
    }
  }
  for (const field of Object.keys(product)) {
    if (!allowed.has(field)) {
      addError(
        errors,
        "editorial.unknown_product_field",
        `Product ${product.id ?? "<unknown>"} contains unsupported field ${field}.`,
        { productId: product.id, field },
      );
    }
  }
  if (!STABLE_ID_PATTERN.test(product.id ?? "")) {
    addError(
      errors,
      "editorial.invalid_product_id",
      `Product has invalid stable ID ${JSON.stringify(product.id)}.`,
      { productId: product.id },
    );
  }

  if (!isObject(product.canonicalNames)) {
    addError(
      errors,
      "editorial.invalid_canonical_names",
      `Product ${product.id ?? "<unknown>"} canonicalNames must be an object.`,
      { productId: product.id },
    );
  } else {
    if (!nonEmptyText(product.canonicalNames[PRIMARY_LOCALE])) {
      addError(
        errors,
        "editorial.missing_canonical_name",
        `Product ${product.id} requires a canonical ${PRIMARY_LOCALE} display name.`,
        { productId: product.id, locale: PRIMARY_LOCALE },
      );
    }
    for (const [locale, value] of Object.entries(product.canonicalNames)) {
      if (
        !LOCALE_PATTERN.test(locale) ||
        !nonEmptyText(value) ||
        normalizedValue(value).length === 0 ||
        value.length > 120
      ) {
        addError(
          errors,
          "editorial.invalid_localized_name",
          `Product ${product.id} has invalid canonical name for ${locale}.`,
          { productId: product.id, locale },
        );
      }
      locales.add(locale);
    }
  }

  const productTerms = new Map();
  for (const field of TERM_FIELDS) {
    if (!Object.hasOwn(product, field) && field === "legacyNames") {
      continue;
    }
    for (const term of validateLocalizedTerms(
      product,
      field,
      errors,
      locales,
    )) {
      const key = `${term.locale}:${normalizedValue(term.value)}`;
      const prior = productTerms.get(key);
      if (prior && prior !== field) {
        addError(
          errors,
          "editorial.duplicate_locale_name",
          `Product ${product.id} defines ${JSON.stringify(term.value)} as both ${prior} and ${field} for ${term.locale}.`,
          { productId: product.id, locale: term.locale, fields: [prior, field] },
        );
      } else {
        productTerms.set(key, field);
      }
    }
  }
  for (const [locale, value] of Object.entries(product.canonicalNames ?? {})) {
    const key = `${locale}:${normalizedValue(value)}`;
    if (productTerms.has(key)) {
      addError(
        errors,
        "editorial.duplicate_locale_name",
        `Product ${product.id} repeats canonical ${JSON.stringify(value)} in ${productTerms.get(key)} for ${locale}.`,
        { productId: product.id, locale },
      );
    }
  }

  if (!STABLE_ID_PATTERN.test(product.categoryId ?? "")) {
    addError(
      errors,
      "editorial.invalid_category",
      `Product ${product.id} has invalid category ${JSON.stringify(product.categoryId)}.`,
      { productId: product.id, categoryId: product.categoryId },
    );
  }
  const indexes = taxonomyIndexes(taxonomy);
  if (!indexes.categories.has(product.categoryId)) {
    addError(
      errors,
      "editorial.invalid_category",
      `Product ${product.id} references missing category ${product.categoryId}.`,
      { productId: product.id, categoryId: product.categoryId },
    );
  }
  if (
    product.subcategoryId !== null &&
    !SUBCATEGORY_ID_PATTERN.test(product.subcategoryId ?? "")
  ) {
    addError(
      errors,
      "editorial.orphan_subcategory",
      `Product ${product.id} has invalid subcategory ${JSON.stringify(product.subcategoryId)}.`,
      { productId: product.id, subcategoryId: product.subcategoryId },
    );
  } else if (product.subcategoryId !== null) {
    const subcategory = indexes.subcategories.get(product.subcategoryId);
    if (!subcategory) {
      addError(
        errors,
        "editorial.orphan_subcategory",
        `Product ${product.id} references missing subcategory ${product.subcategoryId}.`,
        { productId: product.id, subcategoryId: product.subcategoryId },
      );
    } else if (subcategory.parentCategoryId !== product.categoryId) {
      addError(
        errors,
        "editorial.broken_taxonomy",
        `Product ${product.id} assigns ${product.subcategoryId} below ${product.categoryId}; its parent is ${subcategory.parentCategoryId}.`,
        { productId: product.id, subcategoryId: product.subcategoryId },
      );
    }
  }

  for (const field of ["variantDescriptors", "barcodes"]) {
    if (!Array.isArray(product[field])) {
      addError(
        errors,
        "editorial.invalid_product_field",
        `Product ${product.id} field ${field} must be an array.`,
        { productId: product.id, field },
      );
    }
  }
  const variantKeys = new Set();
  for (const value of Array.isArray(product.variantDescriptors)
    ? product.variantDescriptors
    : []) {
    const key = normalizedValue(value ?? "");
    if (!nonEmptyText(value) || key.length === 0 || variantKeys.has(key)) {
      addError(
        errors,
        "editorial.invalid_variant",
        `Product ${product.id} has an invalid or duplicate variant descriptor.`,
        { productId: product.id, value },
      );
    }
    variantKeys.add(key);
  }
  const ownBarcodes = new Set();
  for (const barcode of Array.isArray(product.barcodes)
    ? product.barcodes
    : []) {
    const key = normalizedBarcode(barcode);
    if (!hasValidGTINCheckDigit(barcode)) {
      addError(
        errors,
        "editorial.malformed_barcode",
        `Product ${product.id} has malformed GTIN/barcode ${JSON.stringify(barcode)}.`,
        { productId: product.id, barcode },
      );
    } else if (ownBarcodes.has(key)) {
      addError(
        errors,
        "editorial.duplicate_barcode",
        `Product ${product.id} repeats normalized barcode ${key}.`,
        { productId: product.id, barcode: key },
      );
    }
    if (key !== null) {
      ownBarcodes.add(key);
    }
  }

  for (const field of [
    "brand",
    "semanticKey",
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
        "editorial.invalid_product_field",
        `Product ${product.id} field ${field} must be null or nonempty text.`,
        { productId: product.id, field },
      );
    }
  }
  if (
    !Number.isInteger(product.popularityScore) ||
    product.popularityScore < 0 ||
    product.popularityScore > 100
  ) {
    addError(
      errors,
      "editorial.invalid_popularity",
      `Product ${product.id} popularityScore must be an integer in 0...100.`,
      { productId: product.id },
    );
  }

  const status = product.status;
  if (!isObject(status) || !["active", "inactive"].includes(status.state)) {
    addError(
      errors,
      "editorial.invalid_status",
      `Product ${product.id} requires active or inactive status.`,
      { productId: product.id },
    );
  } else if (
    status.state === "active" &&
    (status.replacementProductId != null ||
      status.deprecatedSinceCatalogVersion != null)
  ) {
    addError(
      errors,
      "editorial.invalid_status",
      `Active product ${product.id} cannot declare replacement or deprecation metadata.`,
      { productId: product.id },
    );
  } else if (
    status.state === "inactive" &&
    (!Number.isInteger(status.deprecatedSinceCatalogVersion) ||
      status.deprecatedSinceCatalogVersion < 1)
  ) {
    addError(
      errors,
      "editorial.invalid_status",
      `Inactive product ${product.id} requires deprecatedSinceCatalogVersion.`,
      { productId: product.id },
    );
  }
  if (
    status?.replacementProductId != null &&
    !STABLE_ID_PATTERN.test(status.replacementProductId)
  ) {
    addError(
      errors,
      "editorial.invalid_status",
      `Product ${product.id} has invalid replacementProductId.`,
      { productId: product.id },
    );
  }
}

function productNameEvidence(product) {
  const displays = [];
  const aliases = [];
  for (const [locale, value] of Object.entries(product.canonicalNames ?? {})) {
    displays.push({ locale, value, field: "canonicalNames" });
  }
  for (const term of product.localizedDisplayNames ?? []) {
    displays.push({ ...term, field: "localizedDisplayNames" });
  }
  for (const term of product.aliases ?? []) {
    aliases.push({ ...term, field: "aliases" });
  }
  for (const term of product.legacyNames ?? []) {
    aliases.push({ ...term, field: "legacyNames" });
  }
  return { displays, aliases };
}

function validateEditorialRelationships(products, errors) {
  const productsById = new Map();
  const displayOwners = new Map();
  const globalDisplayOwners = new Map();
  const aliasOwners = new Map();
  const barcodeOwners = new Map();
  const exactIdentityOwners = new Map();

  for (const product of products) {
    if (!isObject(product) || !nonEmptyText(product.id)) {
      continue;
    }
    if (productsById.has(product.id)) {
      addError(
        errors,
        "editorial.duplicate_id",
        `Editorial product ID ${product.id} is duplicated.`,
        { productId: product.id },
      );
    }
    productsById.set(product.id, product);
    if (product.status?.state !== "active") {
      continue;
    }
    for (const display of productNameEvidence(product).displays) {
      const key = `${display.locale}:${normalizedValue(display.value)}`;
      const owner = displayOwners.get(key);
      if (owner && owner.productId !== product.id) {
        addError(
          errors,
          "editorial.conflicting_localized_name",
          `Products ${owner.productId} and ${product.id} share localized display name ${JSON.stringify(display.value)} for ${display.locale}.`,
          {
            productId: product.id,
            relatedProductId: owner.productId,
            locale: display.locale,
          },
        );
      } else {
        displayOwners.set(key, { productId: product.id, value: display.value });
      }
      const normalized = normalizedValue(display.value);
      const owners = globalDisplayOwners.get(normalized) ?? new Set();
      owners.add(product.id);
      globalDisplayOwners.set(normalized, owners);
    }
    for (const barcode of product.barcodes ?? []) {
      const key = normalizedBarcode(barcode);
      if (key === null) {
        continue;
      }
      const owner = barcodeOwners.get(key);
      if (owner && owner !== product.id) {
        addError(
          errors,
          "editorial.conflicting_barcode",
          `Products ${owner} and ${product.id} share normalized barcode ${key}.`,
          { productId: product.id, relatedProductId: owner, barcode: key },
        );
      } else {
        barcodeOwners.set(key, product.id);
      }
    }
    const identityKey = [
      product.semanticKey ?? product.id,
      product.brand ?? "",
      ...(product.variantDescriptors ?? []).slice().sort(),
      product.packageDescriptor ?? "",
      product.unit ?? "",
    ].map(normalizedValue).join("\u001f");
    const identityOwner = exactIdentityOwners.get(identityKey);
    if (identityOwner && identityOwner !== product.id) {
      addError(
        errors,
        "editorial.indistinguishable_identity",
        `Products ${identityOwner} and ${product.id} share exact semantic, brand, variant, package, and unit identity.`,
        { productId: product.id, relatedProductId: identityOwner },
      );
    } else {
      exactIdentityOwners.set(identityKey, product.id);
    }
  }

  for (const product of products) {
    if (!isObject(product) || product.status?.state !== "active") {
      continue;
    }
    for (const alias of productNameEvidence(product).aliases) {
      const key = normalizedValue(alias.value);
      const conflictingDisplays = [...(globalDisplayOwners.get(key) ?? [])]
        .filter((owner) => owner !== product.id);
      if (conflictingDisplays.length > 0) {
        addError(
          errors,
          "editorial.duplicate_alias",
          `Alias ${JSON.stringify(alias.value)} on ${product.id} conflicts with localized display name on ${conflictingDisplays[0]}.`,
          {
            productId: product.id,
            relatedProductId: conflictingDisplays[0],
            locale: alias.locale,
          },
        );
      }
      const aliasOwner = aliasOwners.get(key);
      if (aliasOwner && aliasOwner.productId !== product.id) {
        addError(
          errors,
          "editorial.duplicate_alias",
          `Alias ${JSON.stringify(alias.value)} on ${product.id} conflicts with alias on ${aliasOwner.productId}.`,
          {
            productId: product.id,
            relatedProductId: aliasOwner.productId,
            locale: alias.locale,
          },
        );
      } else {
        aliasOwners.set(key, { productId: product.id, value: alias.value });
      }
    }
  }

  for (const product of products) {
    const replacement = product?.status?.replacementProductId;
    if (replacement != null) {
      const target = productsById.get(replacement);
      if (!target || target.status?.state !== "active") {
        addError(
          errors,
          "editorial.invalid_replacement",
          `Product ${product.id} replacement ${replacement} must exist and be active.`,
          { productId: product.id, replacementProductId: replacement },
        );
      }
    }
  }
}

function runtimeProductToEditorial(product, catalog, localizationNames) {
  const canonicalNames = { [catalog.locale]: product.canonicalName };
  const localizedDisplayNames = [];
  const aliases = (product.aliases ?? []).map((value) => ({
    locale: catalog.locale,
    value,
  }));
  const keywords = (product.keywords ?? []).map((value) => ({
    locale: catalog.locale,
    value,
  }));
  const brandTerms = (product.brandTerms ?? []).map((value) => ({
    locale: catalog.locale,
    value,
  }));
  const legacyNames = (product.legacyNames ?? []).map((value) => ({
    locale: catalog.locale,
    value,
  }));

  for (const name of localizationNames) {
    switch (name.kind) {
      case "canonical":
        if (!Object.hasOwn(canonicalNames, name.locale)) {
          canonicalNames[name.locale] = name.value;
        } else if (canonicalNames[name.locale] !== name.value) {
          localizedDisplayNames.push({ locale: name.locale, value: name.value });
        }
        break;
      case "localizedDisplay":
        if (name.isPreferred && !Object.hasOwn(canonicalNames, name.locale)) {
          canonicalNames[name.locale] = name.value;
        } else {
          localizedDisplayNames.push({ locale: name.locale, value: name.value });
        }
        break;
      case "alias":
        aliases.push({ locale: name.locale, value: name.value });
        break;
      case "keyword":
        keywords.push({ locale: name.locale, value: name.value });
        break;
      default:
        break;
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
    status: {
      state: product.isActive ? "active" : "inactive",
      ...(product.replacementProductId != null
        ? { replacementProductId: product.replacementProductId }
        : {}),
      ...(product.deprecatedSinceCatalogVersion != null
        ? {
            deprecatedSinceCatalogVersion:
              product.deprecatedSinceCatalogVersion,
          }
        : {}),
    },
    ...(product.metadata != null ? { metadata: product.metadata } : {}),
  };
}

function currentEditorialProducts(context) {
  const namesByProduct = new Map();
  for (const name of context.localizations.names ?? []) {
    const names = namesByProduct.get(name.productID) ?? [];
    names.push(name);
    namesByProduct.set(name.productID, names);
  }
  return context.catalog.products.map((product) =>
    runtimeProductToEditorial(
      product,
      context.catalog,
      namesByProduct.get(product.id) ?? [],
    ),
  );
}

function validateReleaseMetadata(release, context, errors) {
  if (!isObject(release)) {
    addError(
      errors,
      "editorial.invalid_document",
      "Editorial release must be a JSON object.",
    );
    return;
  }
  const required = [
    "schemaVersion",
    "catalogVersion",
    "taxonomyVersion",
    "generationDate",
    "productCount",
    "releaseId",
    "supportedLocales",
    "operations",
  ];
  const allowed = new Set(required);
  for (const field of required) {
    if (!Object.hasOwn(release, field)) {
      addError(
        errors,
        "editorial.missing_release_field",
        `Editorial release is missing ${field}.`,
        { field },
      );
    }
  }
  for (const field of Object.keys(release)) {
    if (!allowed.has(field)) {
      addError(
        errors,
        "editorial.unknown_release_field",
        `Editorial release contains unsupported field ${field}.`,
        { field },
      );
    }
  }
  if (release.schemaVersion !== EDITORIAL_SCHEMA_VERSION) {
    addError(
      errors,
      "editorial.unsupported_schema_version",
      `Editorial schemaVersion must be ${EDITORIAL_SCHEMA_VERSION}.`,
    );
  }
  if (release.catalogVersion !== context.catalog.catalogVersion + 1) {
    addError(
      errors,
      "editorial.catalog_version_mismatch",
      `Editorial catalogVersion must advance exactly once from ${context.catalog.catalogVersion} to ${context.catalog.catalogVersion + 1}.`,
    );
  }
  if (release.taxonomyVersion !== context.taxonomy.taxonomyVersion) {
    addError(
      errors,
      "editorial.taxonomy_version_mismatch",
      `Editorial taxonomyVersion ${release.taxonomyVersion} does not match ${context.taxonomy.taxonomyVersion}.`,
    );
  }
  if (!isValidDate(release.generationDate)) {
    addError(
      errors,
      "editorial.invalid_generation_date",
      `Editorial generationDate must be a real YYYY-MM-DD date.`,
    );
  }
  if (!Number.isInteger(release.productCount) || release.productCount < 0) {
    addError(
      errors,
      "editorial.invalid_product_count",
      "Editorial productCount must be a nonnegative integer.",
    );
  }
  if (!RELEASE_ID_PATTERN.test(release.releaseId ?? "")) {
    addError(
      errors,
      "editorial.invalid_release_id",
      `Editorial releaseId is invalid: ${JSON.stringify(release.releaseId)}.`,
    );
  }
  if (
    !Array.isArray(release.supportedLocales) ||
    release.supportedLocales.length === 0 ||
    !release.supportedLocales.includes(PRIMARY_LOCALE) ||
    release.supportedLocales.some((locale) => !LOCALE_PATTERN.test(locale)) ||
    new Set(release.supportedLocales).size !== release.supportedLocales.length
  ) {
    addError(
      errors,
      "editorial.invalid_supported_locales",
      `Editorial supportedLocales must be unique, valid, and include ${PRIMARY_LOCALE}.`,
    );
  }
  if (!Array.isArray(release.operations) || release.operations.length === 0) {
    addError(
      errors,
      "editorial.invalid_operations",
      "Editorial release requires at least one operation.",
    );
  }
}

function validateEditorialRelease(release, context) {
  const errors = [];
  const warnings = [];
  validateReleaseMetadata(release, context, errors);
  const proposed = currentEditorialProducts(context);
  const indexById = new Map(
    proposed.map((product, index) => [product.id, index]),
  );
  const targets = new Set();
  const locales = new Set([context.catalog.locale]);

  for (const [index, operation] of (Array.isArray(release?.operations)
    ? release.operations
    : []).entries()) {
    if (
      !isObject(operation) ||
      !["add", "replace"].includes(operation.operation) ||
      !Object.hasOwn(operation, "product") ||
      Object.keys(operation).some(
        (field) => !["operation", "product"].includes(field),
      )
    ) {
      addError(
        errors,
        "editorial.invalid_operation",
        `Editorial operation ${index + 1} must be add or replace with one complete product.`,
        { operationIndex: index },
      );
      continue;
    }
    const product = operation.product;
    validateEditorialProduct(product, errors, context.taxonomy, locales);
    if (!isObject(product) || !nonEmptyText(product.id)) {
      continue;
    }
    if (targets.has(product.id)) {
      addError(
        errors,
        "editorial.duplicate_operation",
        `Editorial release mutates ${product.id} more than once.`,
        { productId: product.id },
      );
      continue;
    }
    targets.add(product.id);
    const existingIndex = indexById.get(product.id);
    if (operation.operation === "add" && existingIndex !== undefined) {
      addError(
        errors,
        "editorial.add_existing_product",
        `Editorial add cannot replace existing product ${product.id}.`,
        { productId: product.id },
      );
    } else if (operation.operation === "replace" && existingIndex === undefined) {
      addError(
        errors,
        "editorial.replace_missing_product",
        `Editorial replace requires existing product ${product.id}.`,
        { productId: product.id },
      );
    } else if (operation.operation === "add") {
      indexById.set(product.id, proposed.length);
      proposed.push(product);
    } else {
      proposed[existingIndex] = product;
    }
  }

  if (release?.productCount !== proposed.length) {
    addError(
      errors,
      "editorial.product_count_mismatch",
      `Editorial productCount ${release?.productCount} does not match proposed count ${proposed.length}.`,
    );
  }
  validateEditorialRelationships(proposed, errors);
  const declaredLocales = new Set(release?.supportedLocales ?? []);
  for (const locale of locales) {
    if (!declaredLocales.has(locale)) {
      addError(
        errors,
        "editorial.undeclared_locale",
        `Editorial content uses ${locale}, which is absent from supportedLocales.`,
        { locale },
      );
    }
  }

  errors.sort((left, right) =>
    `${left.productId ?? ""}:${left.code}:${left.message}`.localeCompare(
      `${right.productId ?? ""}:${right.code}:${right.message}`,
      "en",
    ),
  );
  return {
    valid: errors.length === 0,
    errors,
    warnings,
    proposedProducts: proposed,
    stats: {
      operations: Array.isArray(release?.operations)
        ? release.operations.length
        : 0,
      products: proposed.length,
      locales: [...locales].sort(),
    },
  };
}

function runtimeProduct(editorial) {
  const product = {
    id: editorial.id,
    canonicalName: editorial.canonicalNames[PRIMARY_LOCALE],
    categoryId: editorial.categoryId,
    subcategoryId: editorial.subcategoryId,
    aliases: editorial.aliases
      .filter((term) => term.locale === PRIMARY_LOCALE)
      .map((term) => term.value),
    keywords: editorial.keywords
      .filter((term) => term.locale === PRIMARY_LOCALE)
      .map((term) => term.value),
    brandTerms: editorial.brandTerms
      .filter((term) => term.locale === PRIMARY_LOCALE)
      .map((term) => term.value),
    popularityScore: editorial.popularityScore,
    isActive: editorial.status.state === "active",
  };
  const optional = {
    semanticKey: editorial.semanticKey,
    brand: editorial.brand,
    packageDescriptor: editorial.packageDescriptor,
    unit: editorial.unit,
    provenance: editorial.provenance,
    replacementProductId: editorial.status.replacementProductId,
    deprecatedSinceCatalogVersion:
      editorial.status.deprecatedSinceCatalogVersion,
    metadata: editorial.metadata,
  };
  for (const [field, value] of Object.entries(optional)) {
    if (value !== undefined && value !== null) {
      product[field] = clone(value);
    }
  }
  if (editorial.variantDescriptors.length > 0) {
    product.variantDescriptors = clone(editorial.variantDescriptors);
  }
  if (editorial.barcodes.length > 0) {
    product.barcodes = clone(editorial.barcodes);
  }
  const baseLegacyNames = (editorial.legacyNames ?? [])
    .filter((term) => term.locale === PRIMARY_LOCALE)
    .map((term) => term.value);
  if (baseLegacyNames.length > 0) {
    product.legacyNames = baseLegacyNames;
  }
  return product;
}

function safeIDSegment(value) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
}

function localizationRecords(editorial) {
  const records = [];
  const counters = new Map();
  function append(locale, kind, value, isPreferred) {
    const counterKey = `${locale}:${kind}`;
    const index = (counters.get(counterKey) ?? 0) + 1;
    counters.set(counterKey, index);
    records.push({
      id: `catalog_name_${editorial.id}_${safeIDSegment(locale)}_${safeIDSegment(kind)}_${index}`,
      productID: editorial.id,
      locale,
      kind,
      value,
      isPreferred,
    });
  }
  for (const [locale, value] of Object.entries(editorial.canonicalNames)) {
    if (locale !== PRIMARY_LOCALE) {
      append(locale, "localizedDisplay", value, true);
    }
  }
  for (const term of editorial.localizedDisplayNames) {
    append(term.locale, "localizedDisplay", term.value, false);
  }
  for (const term of editorial.aliases) {
    if (term.locale !== PRIMARY_LOCALE) {
      append(term.locale, "alias", term.value, false);
    }
  }
  for (const term of editorial.keywords) {
    if (term.locale !== PRIMARY_LOCALE) {
      append(term.locale, "keyword", term.value, false);
    }
  }
  for (const term of editorial.brandTerms) {
    if (term.locale !== PRIMARY_LOCALE) {
      append(term.locale, "keyword", term.value, false);
    }
  }
  for (const term of editorial.legacyNames ?? []) {
    if (term.locale !== PRIMARY_LOCALE) {
      append(term.locale, "alias", term.value, false);
    }
  }
  return records;
}

function validateProductionBundle(context) {
  const base = validateCatalog(context);
  const errors = [...base.errors];
  const warnings = [...base.warnings];
  const { catalog, localizations, manifest } = context;

  if (!isObject(manifest)) {
    addError(
      errors,
      "manifest.invalid_document",
      "Production catalog release manifest must be an object.",
    );
  } else {
    if (manifest.schemaVersion !== RELEASE_MANIFEST_SCHEMA_VERSION) {
      addError(
        errors,
        "manifest.unsupported_schema_version",
        `Release manifest schemaVersion must be ${RELEASE_MANIFEST_SCHEMA_VERSION}.`,
      );
    }
    if (manifest.catalogVersion !== catalog.catalogVersion) {
      addError(
        errors,
        "manifest.catalog_version_mismatch",
        `Release manifest catalogVersion ${manifest.catalogVersion} does not match catalog ${catalog.catalogVersion}.`,
      );
    }
    if (!isValidDate(manifest.generationDate)) {
      addError(
        errors,
        "manifest.invalid_generation_date",
        "Release manifest generationDate must be a real YYYY-MM-DD date.",
      );
    }
    if (manifest.productCount !== catalog.products.length) {
      addError(
        errors,
        "manifest.product_count_mismatch",
        `Release manifest productCount ${manifest.productCount} does not match catalog ${catalog.products.length}.`,
      );
    }
  }

  const productsById = new Map(
    catalog.products.map((product) => [product.id, product]),
  );
  if (
    !isObject(localizations) ||
    !Array.isArray(localizations.names) ||
    !Array.isArray(localizations.supportedLocales)
  ) {
    addError(
      errors,
      "localization.invalid_document",
      "Localization overlay must contain supportedLocales and names arrays.",
    );
  } else {
    if (localizations.schemaVersion !== 1) {
      addError(
        errors,
        "localization.unsupported_schema_version",
        "Localization schemaVersion must be 1.",
      );
    }
    if (localizations.catalogVersion !== catalog.catalogVersion) {
      addError(
        errors,
        "localization.catalog_version_mismatch",
        `Localization catalogVersion ${localizations.catalogVersion} does not match catalog ${catalog.catalogVersion}.`,
      );
    }
    const supportedLocales = new Set(localizations.supportedLocales);
    if (
      supportedLocales.size !== localizations.supportedLocales.length ||
      [...supportedLocales].some((locale) => !LOCALE_PATTERN.test(locale)) ||
      !supportedLocales.has(catalog.locale)
    ) {
      addError(
        errors,
        "localization.invalid_supported_locales",
        "Localization supportedLocales must be unique, valid, and include the catalog locale.",
      );
    }
    const ids = new Set();
    const definitions = new Map();
    const preferredDisplays = new Map();
    const localizedDisplayOwners = new Map();
    const globalDisplayOwners = new Map();
    const aliasOwners = new Map();

    for (const product of catalog.products.filter((entry) => entry.isActive)) {
      const normalizedDisplay = normalizedValue(product.canonicalName);
      localizedDisplayOwners.set(
        `${catalog.locale}:${normalizedDisplay}`,
        product.id,
      );
      globalDisplayOwners.set(normalizedDisplay, new Set([product.id]));
      for (const alias of [...(product.aliases ?? []), ...(product.legacyNames ?? [])]) {
        aliasOwners.set(normalizedValue(alias), product.id);
      }
    }

    for (const [index, name] of localizations.names.entries()) {
      if (
        !isObject(name) ||
        !nonEmptyText(name.id) ||
        !nonEmptyText(name.productID) ||
        !LOCALE_PATTERN.test(name.locale ?? "") ||
        !["canonical", "localizedDisplay", "alias", "keyword"].includes(
          name.kind,
        ) ||
        !nonEmptyText(name.value) ||
        normalizedValue(name.value).length === 0 ||
        typeof name.isPreferred !== "boolean"
      ) {
        addError(
          errors,
          "localization.invalid_name",
          `Localization name at index ${index} is malformed or cannot be indexed.`,
          { nameIndex: index, productId: name?.productID },
        );
        continue;
      }
      if (ids.has(name.id)) {
        addError(
          errors,
          "localization.duplicate_name_id",
          `Localization name ID ${name.id} is duplicated.`,
          { productId: name.productID },
        );
      }
      ids.add(name.id);
      const product = productsById.get(name.productID);
      if (!product) {
        addError(
          errors,
          "localization.orphan_product",
          `Localization ${name.id} references missing product ${name.productID}.`,
          { productId: name.productID },
        );
        continue;
      }
      if (!supportedLocales.has(name.locale)) {
        addError(
          errors,
          "localization.undeclared_locale",
          `Localization ${name.id} uses undeclared locale ${name.locale}.`,
          { productId: name.productID, locale: name.locale },
        );
      }
      if (name.isPreferred && !["canonical", "localizedDisplay"].includes(name.kind)) {
        addError(
          errors,
          "localization.invalid_preferred_name",
          `Localization ${name.id} marks non-display kind ${name.kind} preferred.`,
          { productId: name.productID },
        );
      }
      const key = `${name.productID}:${name.locale}:${normalizedValue(name.value)}`;
      if (definitions.has(key)) {
        addError(
          errors,
          "localization.duplicate_locale_name",
          `Product ${name.productID} repeats localized name ${JSON.stringify(name.value)} for ${name.locale}.`,
          { productId: name.productID, locale: name.locale },
        );
      }
      definitions.set(key, name.id);
      if (name.isPreferred && ["canonical", "localizedDisplay"].includes(name.kind)) {
        const preferredKey = `${name.productID}:${name.locale}`;
        if (preferredDisplays.has(preferredKey)) {
          addError(
            errors,
            "localization.conflicting_preferred_names",
            `Product ${name.productID} has multiple preferred display names for ${name.locale}.`,
            { productId: name.productID, locale: name.locale },
          );
        }
        preferredDisplays.set(preferredKey, name.id);
      }
      if (!product.isActive) {
        continue;
      }
      const globalKey = `${name.locale}:${normalizedValue(name.value)}`;
      if (["canonical", "localizedDisplay"].includes(name.kind)) {
        const owner = localizedDisplayOwners.get(globalKey);
        if (owner && owner !== name.productID) {
          addError(
            errors,
            "localization.conflicting_display_name",
            `Localized display ${JSON.stringify(name.value)} on ${name.productID} conflicts with ${owner}.`,
            { productId: name.productID, relatedProductId: owner },
          );
        }
        localizedDisplayOwners.set(globalKey, name.productID);
        const normalized = normalizedValue(name.value);
        const owners = globalDisplayOwners.get(normalized) ?? new Set();
        owners.add(name.productID);
        globalDisplayOwners.set(normalized, owners);
      } else if (name.kind === "alias") {
        const normalized = normalizedValue(name.value);
        const aliasOwner = aliasOwners.get(normalized);
        const displayOwner = [...(globalDisplayOwners.get(normalized) ?? [])]
          .find((owner) => owner !== name.productID);
        const owner = displayOwner ?? aliasOwner;
        if (owner && owner !== name.productID) {
          addError(
            errors,
            "localization.alias_collision",
            `Localized alias ${JSON.stringify(name.value)} on ${name.productID} conflicts with ${owner}.`,
            { productId: name.productID, relatedProductId: owner },
          );
        }
        aliasOwners.set(normalized, name.productID);
      }
    }
  }

  errors.sort((left, right) =>
    `${left.productId ?? ""}:${left.code}:${left.message}`.localeCompare(
      `${right.productId ?? ""}:${right.code}:${right.message}`,
      "en",
    ),
  );
  return {
    valid: errors.length === 0,
    errors,
    warnings,
    stats: {
      ...base.stats,
      localizedNames: Array.isArray(localizations?.names)
        ? localizations.names.length
        : 0,
      supportedLocales: Array.isArray(localizations?.supportedLocales)
        ? localizations.supportedLocales.length
        : 0,
    },
  };
}

function updateReview(review, catalog, operations) {
  const result = clone(review);
  result.catalogVersion = catalog.catalogVersion;
  result.taxonomyVersion = catalog.taxonomyVersion;
  result.locale = catalog.locale;
  result.productCount = catalog.products.length;
  for (const operation of operations) {
    const product = runtimeProduct(operation.product);
    let entry = result.products.find((item) => item.productId === product.id);
    if (!entry) {
      entry = {
        productId: product.id,
        previousLegacyCategoryId: null,
        canonicalCategoryId: product.categoryId,
        canonicalSubcategoryId: product.subcategoryId,
        reviewStatus: "confirmed",
        note: "Curated product accepted through the WT-031B editorial importer.",
      };
      result.products.push(entry);
    } else {
      const changedTaxonomy =
        entry.canonicalCategoryId !== product.categoryId ||
        entry.canonicalSubcategoryId !== product.subcategoryId;
      entry.canonicalCategoryId = product.categoryId;
      entry.canonicalSubcategoryId = product.subcategoryId;
      entry.reviewStatus = changedTaxonomy ? "reclassified" : "confirmed";
    }
  }
  const order = new Map(
    catalog.products.map((product, index) => [product.id, index]),
  );
  result.products.sort(
    (left, right) => order.get(left.productId) - order.get(right.productId),
  );
  return result;
}

function planEditorialImport(context, release) {
  const baseline = validateProductionBundle(context);
  if (!baseline.valid) {
    return {
      valid: false,
      releaseValidation: null,
      validation: baseline,
      error: "Current production bundle is invalid; refusing import.",
    };
  }
  const releaseValidation = validateEditorialRelease(release, context);
  if (!releaseValidation.valid) {
    return {
      valid: false,
      releaseValidation,
      validation: releaseValidation,
      error: "Editorial release is invalid; nothing can be imported.",
    };
  }

  const catalog = clone(context.catalog);
  catalog.catalogVersion = release.catalogVersion;
  const changedIDs = new Set();
  for (const operation of release.operations) {
    const product = runtimeProduct(operation.product);
    changedIDs.add(product.id);
    if (operation.operation === "add") {
      catalog.products.push(product);
    } else {
      const index = catalog.products.findIndex((item) => item.id === product.id);
      catalog.products[index] = product;
    }
  }

  const localizations = clone(context.localizations);
  localizations.catalogVersion = release.catalogVersion;
  localizations.supportedLocales = [...new Set([
    ...release.supportedLocales,
    catalog.locale,
  ])].sort();
  localizations.names = localizations.names.filter(
    (name) => !changedIDs.has(name.productID),
  );
  for (const operation of release.operations) {
    localizations.names.push(...localizationRecords(operation.product));
  }
  const manifest = {
    schemaVersion: RELEASE_MANIFEST_SCHEMA_VERSION,
    catalogVersion: release.catalogVersion,
    generationDate: release.generationDate,
    productCount: catalog.products.length,
  };
  const review = updateReview(context.review, catalog, release.operations);
  const proposedContext = {
    ...context,
    catalog,
    localizations,
    manifest,
    review,
  };
  const validation = validateProductionBundle(proposedContext);
  return {
    valid: validation.valid,
    release,
    releaseValidation,
    validation,
    catalog,
    localizations,
    manifest,
    review,
    changedProductIDs: [...changedIDs].sort(),
    catalogVersionFrom: context.catalog.catalogVersion,
    catalogVersionTo: release.catalogVersion,
  };
}

function existingHash(filePath) {
  return fs.existsSync(filePath) ? fileSha256(filePath) : null;
}

function loadEditorialContext(paths) {
  const context = loadContext(paths);
  return {
    ...context,
    editorialSchema: readJson(paths.editorialSchema, "editorial schema"),
    localizations: readJson(paths.localizations, "localization overlay"),
    manifest: readJson(paths.manifest, "release manifest"),
    sourceHashes: {
      ...context.sourceHashes,
      localizations: fileSha256(paths.localizations),
      manifest: fileSha256(paths.manifest),
      audit: existingHash(paths.audit),
    },
  };
}

function commitEditorialImport(context, plan) {
  if (!plan.valid) {
    throw new Error("Editorial import is invalid; nothing was written.");
  }
  const guarded = [
    [context.paths.catalog, context.sourceHashes.catalog],
    [context.paths.review, context.sourceHashes.review],
    [context.paths.localizations, context.sourceHashes.localizations],
    [context.paths.manifest, context.sourceHashes.manifest],
    [context.paths.audit, context.sourceHashes.audit],
  ];
  if (guarded.some(([filePath, hash]) => existingHash(filePath) !== hash)) {
    throw new Error(
      "Catalog bundle changed after loading; refusing a stale editorial import.",
    );
  }

  const catalogText = jsonText(plan.catalog);
  const localizationText = jsonText(plan.localizations);
  const manifestText = jsonText(plan.manifest);
  const reviewText = jsonText(plan.review);
  const auditEntry = {
    auditVersion: 3,
    timestamp: new Date().toISOString(),
    operation: "editorial_import",
    releaseOperation: "editorial_import",
    releaseId: plan.release.releaseId,
    catalogVersionFrom: plan.catalogVersionFrom,
    catalogVersionTo: plan.catalogVersionTo,
    generationDate: plan.release.generationDate,
    productCount: plan.catalog.products.length,
    changedProductIDs: plan.changedProductIDs,
    catalogSha256Before: context.sourceHashes.catalog,
    catalogSha256After: sha256(catalogText),
    localizationSha256After: sha256(localizationText),
    manifestSha256After: sha256(manifestText),
  };
  const auditText = auditEntriesText(context.paths.audit, [auditEntry]);

  writeTransaction([
    { path: context.paths.catalog, content: catalogText },
    { path: context.paths.localizations, content: localizationText },
    { path: context.paths.manifest, content: manifestText },
    { path: context.paths.review, content: reviewText },
    { path: context.paths.audit, content: auditText },
  ]);
  const reloaded = loadEditorialContext(context.paths);
  const validation = validateProductionBundle(reloaded);
  if (!validation.valid) {
    throw new Error(
      `Post-import validation unexpectedly failed (${validation.errors.length} errors).`,
    );
  }
  return { auditEntry, validation };
}

module.exports = {
  EDITORIAL_SCHEMA_VERSION,
  PRIMARY_LOCALE,
  RELEASE_MANIFEST_SCHEMA_VERSION,
  commitEditorialImport,
  currentEditorialProducts,
  loadEditorialContext,
  planEditorialImport,
  validateEditorialRelease,
  validateProductionBundle,
};
