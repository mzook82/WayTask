"use strict";

const path = require("node:path");
const {
  auditEntriesText,
  fileSha256,
  jsonText,
  readJson,
  sha256,
  writeTransaction,
} = require("./io");
const { normalize, normalizedValue } = require("./normalization");
const { validateCatalog } = require("./validator");

function clone(value) {
  return structuredClone(value);
}

function loadContext(paths) {
  return {
    paths,
    catalog: readJson(paths.catalog, "catalog"),
    schema: readJson(paths.schema, "catalog JSON Schema"),
    taxonomy: readJson(paths.taxonomy, "taxonomy registry"),
    review: readJson(paths.review, "taxonomy review manifest"),
    sourceHashes: {
      catalog: fileSha256(paths.catalog),
      review: fileSha256(paths.review),
    },
  };
}

function validateContext(context) {
  return validateCatalog(context);
}

function categoryIndexes(taxonomy) {
  const categories = new Map();
  const subcategories = new Map();
  for (const category of taxonomy.categories ?? []) {
    categories.set(category.id, category);
    for (const subcategory of category.subcategories ?? []) {
      subcategories.set(subcategory.id, subcategory);
    }
  }
  return { categories, subcategories };
}

function buildReport(context) {
  const validation = validateContext(context);
  const { catalog, taxonomy, review } = context;
  const indexes = categoryIndexes(taxonomy);
  const categoryCounts = new Map(
    (taxonomy.categories ?? []).map((category) => [
      category.id,
      { active: 0, inactive: 0 },
    ]),
  );
  const reviewStatuses = new Map();

  for (const product of catalog.products ?? []) {
    const counts = categoryCounts.get(product.categoryId) ?? {
      active: 0,
      inactive: 0,
    };
    counts[product.isActive ? "active" : "inactive"] += 1;
    categoryCounts.set(product.categoryId, counts);
  }
  for (const entry of review.products ?? []) {
    reviewStatuses.set(
      entry.reviewStatus,
      (reviewStatuses.get(entry.reviewStatus) ?? 0) + 1,
    );
  }

  return {
    valid: validation.valid,
    metadata: {
      schemaVersion: catalog.schemaVersion,
      catalogVersion: catalog.catalogVersion,
      taxonomyVersion: catalog.taxonomyVersion,
      locale: catalog.locale,
    },
    products: {
      total: catalog.products.length,
      active: catalog.products.filter((product) => product.isActive).length,
      inactive: catalog.products.filter((product) => !product.isActive).length,
      withSubcategory: catalog.products.filter(
        (product) => product.subcategoryId !== null,
      ).length,
      withoutSubcategory: catalog.products.filter(
        (product) => product.subcategoryId === null,
      ).length,
      withBrandTerms: catalog.products.filter(
        (product) => product.brandTerms.length > 0,
      ).length,
      aliasCount: catalog.products.reduce(
        (total, product) => total + product.aliases.length,
        0,
      ),
      keywordCount: catalog.products.reduce(
        (total, product) => total + product.keywords.length,
        0,
      ),
      brandTermCount: catalog.products.reduce(
        (total, product) => total + product.brandTerms.length,
        0,
      ),
    },
    taxonomy: {
      categories: indexes.categories.size,
      subcategories: indexes.subcategories.size,
      assignments: [...categoryCounts].map(([categoryId, counts]) => {
        const category = indexes.categories.get(categoryId);
        return {
          categoryId,
          displayName:
            category?.localizedNames?.[catalog.locale] ??
            category?.canonicalName ??
            categoryId,
          ...counts,
        };
      }),
    },
    review: {
      entries: review.products.length,
      statuses: [...reviewStatuses]
        .map(([status, count]) => ({ status, count }))
        .sort((left, right) => left.status.localeCompare(right.status)),
    },
    idFingerprint: sha256(
      `${catalog.products
        .map((product) => product.id)
        .sort()
        .join("\n")}\n`,
    ),
    validation: {
      errors: validation.errors.length,
      warnings: validation.warnings.length,
    },
  };
}

function textMatch(value, query, prefixTier, containsTier, exactTier = null) {
  if (value === query && exactTier !== null) {
    return exactTier;
  }
  if (value.startsWith(query)) {
    return prefixTier;
  }
  if (value.includes(query)) {
    return containsTier;
  }
  return null;
}

function productMatch(product, query) {
  const canonical = normalize(product.canonicalName);
  if (canonical.value === query) {
    return { tier: 0, source: "canonical_name", value: product.canonicalName };
  }
  if (canonical.value.startsWith(query)) {
    return { tier: 1, source: "canonical_name", value: product.canonicalName };
  }
  if (canonical.tokens.some((token) => token.startsWith(query))) {
    return { tier: 2, source: "canonical_name", value: product.canonicalName };
  }
  if (canonical.value.includes(query)) {
    return { tier: 3, source: "canonical_name", value: product.canonicalName };
  }

  const fields = [
    ["aliases", "alias", 4, 5, 6],
    ["brandTerms", "brand_term", 7, 8, 9],
    ["keywords", "keyword", 10, 11, 12],
    ["legacyNames", "legacy_name", 4, 5, 6],
  ];
  let best = null;
  for (const [field, source, exact, prefix, contains] of fields) {
    for (const rawValue of product[field] ?? []) {
      const tier = textMatch(
        normalizedValue(rawValue),
        query,
        prefix,
        contains,
        exact,
      );
      if (tier !== null && (best === null || tier < best.tier)) {
        best = { tier, source, value: rawValue };
      }
    }
  }
  return best;
}

function findProducts(context, rawQuery, { includeInactive = false } = {}) {
  const query = normalizedValue(rawQuery);
  if (query.length === 0) {
    throw new Error("find requires a query containing a letter or number.");
  }

  return context.catalog.products
    .filter((product) => includeInactive || product.isActive)
    .map((product) => ({
      product,
      match: productMatch(product, query),
    }))
    .filter((result) => result.match !== null)
    .sort(
      (left, right) =>
        left.match.tier - right.match.tier ||
        right.product.popularityScore - left.product.popularityScore ||
        left.product.canonicalName.length -
          right.product.canonicalName.length ||
        left.product.canonicalName.localeCompare(
          right.product.canonicalName,
          "he",
        ) ||
        left.product.id.localeCompare(right.product.id, "en"),
    )
    .map(({ product, match }) => ({
      id: product.id,
      canonicalName: product.canonicalName,
      categoryId: product.categoryId,
      subcategoryId: product.subcategoryId,
      isActive: product.isActive,
      popularityScore: product.popularityScore,
      matchSource: match.source,
      matchedValue: match.value,
      diagnosticTier: match.tier,
    }));
}

function inspectProduct(context, productId) {
  const product = context.catalog.products.find(
    (entry) => entry.id === productId,
  );
  if (!product) {
    throw new Error(`Unknown catalog product ID: ${productId}`);
  }
  const indexes = categoryIndexes(context.taxonomy);
  return {
    product,
    taxonomy: {
      category:
        indexes.categories.get(product.categoryId) ?? null,
      subcategory:
        product.subcategoryId === null
          ? null
          : indexes.subcategories.get(product.subcategoryId) ?? null,
    },
    review:
      context.review.products.find(
        (entry) => entry.productId === productId,
      ) ?? null,
  };
}

function reviewStatus(before, after) {
  if (!before) {
    return "confirmed";
  }
  if (before.canonicalName !== after.canonicalName) {
    return "canonical_name_updated";
  }
  if (JSON.stringify(before.aliases) !== JSON.stringify(after.aliases)) {
    return "alias_updated";
  }
  if (
    JSON.stringify(before.brandTerms) !== JSON.stringify(after.brandTerms)
  ) {
    return "brand_term_updated";
  }
  if (
    before.categoryId !== after.categoryId ||
    before.subcategoryId !== after.subcategoryId
  ) {
    return "reclassified";
  }
  return "confirmed";
}

function updateReviewManifest({
  review,
  catalog,
  operation,
  before,
  after,
}) {
  const result = clone(review);
  result.catalogVersion = catalog.catalogVersion;
  result.taxonomyVersion = catalog.taxonomyVersion;
  result.locale = catalog.locale;
  result.productCount = catalog.products.length;

  if (operation === "add") {
    result.products.push({
      productId: after.id,
      previousLegacyCategoryId: null,
      canonicalCategoryId: after.categoryId,
      canonicalSubcategoryId: after.subcategoryId,
      reviewStatus: "confirmed",
      note: "Canonical product added through the catalog authoring toolkit.",
    });
  } else if (operation === "update") {
    const entry = result.products.find(
      (candidate) => candidate.productId === after.id,
    );
    if (!entry) {
      throw new Error(`Review manifest is missing product ${after.id}.`);
    }
    entry.canonicalCategoryId = after.categoryId;
    entry.canonicalSubcategoryId = after.subcategoryId;
    entry.reviewStatus = reviewStatus(before, after);
  }

  const order = new Map(
    catalog.products.map((product, index) => [product.id, index]),
  );
  result.products.sort(
    (left, right) =>
      (order.get(left.productId) ?? Number.MAX_SAFE_INTEGER) -
      (order.get(right.productId) ?? Number.MAX_SAFE_INTEGER),
  );
  return result;
}

function changedFields(before, after) {
  if (!before) {
    return ["product"];
  }
  const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
  return [...keys]
    .filter(
      (key) =>
        JSON.stringify(before[key]) !== JSON.stringify(after[key]),
    )
    .sort();
}

function finalizePlan({
  context,
  operation,
  productId,
  before,
  after,
  catalog,
  review,
}) {
  const proposedContext = {
    ...context,
    catalog,
    review,
  };
  const validation = validateContext(proposedContext);
  return {
    operation,
    productId,
    before,
    after,
    catalogVersionFrom: context.catalog.catalogVersion,
    catalogVersionTo: catalog.catalogVersion,
    changedFields: changedFields(before, after),
    catalog,
    review,
    validation,
  };
}

function assertValidBaseline(context) {
  const validation = validateContext(context);
  if (!validation.valid) {
    throw new Error(
      `Current catalog is invalid; refusing mutation (${validation.errors.length} errors). Run validate for details.`,
    );
  }
}

function assertObject(value, message) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(message);
  }
}

function applyAdd(catalog, product) {
  if (!product || typeof product !== "object" || Array.isArray(product)) {
    throw new Error("Add input must be one canonical product JSON object.");
  }
  const after = clone(product);
  catalog.products.push(after);
  return {
    operation: "add",
    productId: after.id,
    before: null,
    after,
    changedFields: ["product"],
  };
}

function applyUpdate(catalog, productId, patch) {
  if (!patch || typeof patch !== "object" || Array.isArray(patch)) {
    throw new Error("Update input must be one JSON object containing fields to replace.");
  }
  if (Object.hasOwn(patch, "id") && patch.id !== productId) {
    throw new Error(
      `Update cannot rename stable ID ${productId} to ${patch.id}.`,
    );
  }
  const index = catalog.products.findIndex(
    (product) => product.id === productId,
  );
  if (index < 0) {
    throw new Error(`Unknown catalog product ID: ${productId}`);
  }
  const before = clone(catalog.products[index]);
  const after = { ...catalog.products[index], ...clone(patch), id: productId };
  const fields = changedFields(before, after);
  if (fields.length === 0) {
    throw new Error(`Update for ${productId} does not change any field.`);
  }
  catalog.products[index] = after;
  return {
    operation: "update",
    productId,
    before,
    after,
    changedFields: fields,
  };
}

function applyDeactivate(catalog, productId) {
  const index = catalog.products.findIndex(
    (product) => product.id === productId,
  );
  if (index < 0) {
    throw new Error(`Unknown catalog product ID: ${productId}`);
  }
  const before = clone(catalog.products[index]);
  if (!before.isActive) {
    throw new Error(`Product ${productId} is already inactive.`);
  }
  const after = {
    ...catalog.products[index],
    isActive: false,
    deprecatedSinceCatalogVersion: catalog.catalogVersion,
  };
  catalog.products[index] = after;
  return {
    operation: "deactivate",
    productId,
    before,
    after,
    changedFields: changedFields(before, after),
  };
}

function planSingleMutation(context, mutation) {
  assertValidBaseline(context);
  const catalog = clone(context.catalog);
  catalog.catalogVersion += 1;
  const applied = mutation(catalog);
  const review = updateReviewManifest({
    review: context.review,
    catalog,
    operation: applied.operation,
    before: applied.before,
    after: applied.after,
  });
  return finalizePlan({
    context,
    operation: applied.operation,
    productId: applied.productId,
    before: applied.before,
    after: applied.after,
    catalog,
    review,
  });
}

function planAdd(context, product) {
  return planSingleMutation(context, (catalog) => applyAdd(catalog, product));
}

function planUpdate(context, productId, patch) {
  return planSingleMutation(context, (catalog) =>
    applyUpdate(catalog, productId, patch),
  );
}

function planDeactivate(context, productId) {
  return planSingleMutation(context, (catalog) =>
    applyDeactivate(catalog, productId),
  );
}

function batchMutationTarget(operation, index) {
  assertObject(
    operation,
    `Batch operation ${index + 1} must be a JSON object.`,
  );
  switch (operation.operation) {
    case "add":
      assertObject(
        operation.product,
        `Batch add operation ${index + 1} requires a product object.`,
      );
      return operation.product.id;
    case "update":
    case "deactivate":
      return operation.id;
    default:
      throw new Error(
        `Batch operation ${index + 1} has unsupported operation "${operation.operation}".`,
      );
  }
}

function planBatch(context, release) {
  assertValidBaseline(context);
  assertObject(
    release,
    "Batch input must be a JSON object containing releaseId and operations.",
  );
  if (
    typeof release.releaseId !== "string" ||
    !/^[a-z0-9][a-z0-9._-]*$/.test(release.releaseId)
  ) {
    throw new Error(
      "Batch releaseId must use lowercase ASCII letters, digits, dots, underscores, or hyphens.",
    );
  }
  if (!Array.isArray(release.operations) || release.operations.length === 0) {
    throw new Error("Batch input requires at least one operation.");
  }

  const targets = release.operations.map(batchMutationTarget);
  const invalidTargetIndex = targets.findIndex(
    (target) => typeof target !== "string" || target.length === 0,
  );
  if (invalidTargetIndex >= 0) {
    throw new Error(
      `Batch operation ${invalidTargetIndex + 1} requires a product ID.`,
    );
  }
  const duplicateTarget = targets.find(
    (target, index) => targets.indexOf(target) !== index,
  );
  if (duplicateTarget) {
    throw new Error(
      `Batch release cannot mutate product ${duplicateTarget} more than once.`,
    );
  }

  const catalog = clone(context.catalog);
  catalog.catalogVersion += 1;
  let review = clone(context.review);
  const mutations = [];
  for (const operation of release.operations) {
    let mutation;
    switch (operation.operation) {
      case "add":
        mutation = applyAdd(catalog, operation.product);
        break;
      case "update":
        mutation = applyUpdate(catalog, operation.id, operation.patch);
        break;
      case "deactivate":
        mutation = applyDeactivate(catalog, operation.id);
        break;
      default:
        throw new Error(`Unsupported batch operation: ${operation.operation}`);
    }
    review = updateReviewManifest({
      review,
      catalog,
      operation: mutation.operation,
      before: mutation.before,
      after: mutation.after,
    });
    mutations.push(mutation);
  }

  const proposedContext = { ...context, catalog, review };
  const validation = validateContext(proposedContext);
  return {
    operation: "batch",
    releaseId: release.releaseId,
    productId: null,
    mutations,
    catalogVersionFrom: context.catalog.catalogVersion,
    catalogVersionTo: catalog.catalogVersion,
    changedFields: [
      ...new Set(mutations.flatMap((mutation) => mutation.changedFields)),
    ].sort(),
    catalog,
    review,
    validation,
  };
}

function checkCandidate(context, product) {
  const plan = planAdd(context, product);
  return {
    valid: plan.validation.valid,
    candidateId: product?.id ?? null,
    proposedCatalogVersion: plan.catalogVersionTo,
    errors: plan.validation.errors,
    warnings: plan.validation.warnings,
    stats: plan.validation.stats,
  };
}

function commitPlan(context, plan) {
  if (!plan.validation.valid) {
    throw new Error(
      `Proposed ${plan.operation} is invalid (${plan.validation.errors.length} errors); nothing was written.`,
    );
  }
  if (
    fileSha256(context.paths.catalog) !== context.sourceHashes.catalog ||
    fileSha256(context.paths.review) !== context.sourceHashes.review
  ) {
    throw new Error(
      "Catalog or review manifest changed after loading; refusing a stale write.",
    );
  }

  const catalogAfterText = jsonText(plan.catalog);
  const timestamp = new Date().toISOString();
  const catalogSha256After = sha256(catalogAfterText);
  const mutations =
    plan.operation === "batch"
      ? plan.mutations
      : [
          {
            operation: plan.operation,
            productId: plan.productId,
            changedFields: plan.changedFields,
          },
        ];
  const auditEntries = mutations.map((mutation, index) => ({
    auditVersion: 2,
    timestamp,
    operation: mutation.operation,
    productId: mutation.productId,
    releaseOperation: plan.operation === "batch" ? "batch" : "single",
    ...(plan.releaseId ? { releaseId: plan.releaseId } : {}),
    ...(plan.operation === "batch"
      ? {
          batchIndex: index + 1,
          batchSize: mutations.length,
        }
      : {}),
    catalogVersionFrom: plan.catalogVersionFrom,
    catalogVersionTo: plan.catalogVersionTo,
    changedFields: mutation.changedFields,
    catalogSha256Before: context.sourceHashes.catalog,
    catalogSha256After,
  }));
  const nextAuditText = auditEntriesText(
    context.paths.audit,
    auditEntries,
  );

  writeTransaction([
    { path: context.paths.catalog, content: catalogAfterText },
    { path: context.paths.review, content: jsonText(plan.review) },
    { path: context.paths.audit, content: nextAuditText },
  ]);

  const reloaded = loadContext(context.paths);
  const validation = validateContext(reloaded);
  if (!validation.valid) {
    throw new Error(
      `Post-write validation unexpectedly failed (${validation.errors.length} errors).`,
    );
  }
  return {
    auditEntry: auditEntries.length === 1 ? auditEntries[0] : null,
    auditEntries,
    validation,
  };
}

function relativePath(repoRoot, targetPath) {
  const relative = path.relative(repoRoot, targetPath);
  return relative.startsWith("..") ? targetPath : relative;
}

module.exports = {
  buildReport,
  checkCandidate,
  commitPlan,
  findProducts,
  inspectProduct,
  loadContext,
  planAdd,
  planBatch,
  planDeactivate,
  planUpdate,
  relativePath,
  validateContext,
};
