"use strict";

const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  buildReport,
  checkCandidate,
  commitPlan,
  findProducts,
  inspectProduct,
  loadContext,
  planAdd,
  planBatch,
} = require("../lib/catalog");
const { fileSha256, readJson, sha256 } = require("../lib/io");
const { normalizedValue } = require("../lib/normalization");
const { validateCatalog } = require("../lib/validator");
const {
  commitEditorialImport,
  loadEditorialContext,
  planEditorialImport,
  validateProductionBundle,
} = require("../lib/editorial");

const REPO_ROOT = path.resolve(__dirname, "..", "..", "..");
const CLI = path.join(REPO_ROOT, "tools", "catalog", "catalog-tool.js");
const FIXTURES = path.join(__dirname, "fixtures");
const SHARED = path.join(REPO_ROOT, "shared", "catalog");
const PRODUCTION_CATALOG = path.join(
  REPO_ROOT,
  "WayTask",
  "Resources",
  "product_catalog_he.json",
);

function fixtureContext() {
  return {
    catalog: readJson(
      path.join(FIXTURES, "valid-catalog.json"),
      "test catalog",
    ),
    schema: readJson(
      path.join(SHARED, "product-catalog.schema.json"),
      "schema",
    ),
    taxonomy: readJson(path.join(SHARED, "taxonomy.json"), "taxonomy"),
    review: readJson(
      path.join(FIXTURES, "valid-review.json"),
      "test review",
    ),
  };
}

function productionContext() {
  return loadContext({
    catalog: PRODUCTION_CATALOG,
    schema: path.join(SHARED, "product-catalog.schema.json"),
    taxonomy: path.join(SHARED, "taxonomy.json"),
    review: path.join(SHARED, "product-taxonomy-review.json"),
    audit: path.join(SHARED, "catalog-authoring-audit.jsonl"),
  });
}

function clone(value) {
  return structuredClone(value);
}

function validationWith(change) {
  const context = fixtureContext();
  change(context);
  return validateCatalog(context);
}

function expectErrorCode(validation, code) {
  assert.equal(validation.valid, false);
  assert.ok(
    validation.errors.some((entry) => entry.code === code),
    `Expected ${code}; received ${validation.errors
      .map((entry) => entry.code)
      .join(", ")}`,
  );
}

function runCli(args) {
  return spawnSync(process.execPath, [CLI, ...args], {
    cwd: REPO_ROOT,
    encoding: "utf8",
  });
}

function parseStdout(result) {
  assert.notEqual(
    result.stdout.trim(),
    "",
    `Expected JSON stdout. stderr: ${result.stderr}`,
  );
  return JSON.parse(result.stdout);
}

function temporaryWorkspace() {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), "waytask-catalog-tool-"),
  );
  const catalog = path.join(directory, "catalog.json");
  const review = path.join(directory, "review.json");
  const audit = path.join(directory, "audit.jsonl");
  const localizations = path.join(directory, "localizations.json");
  const manifest = path.join(directory, "manifest.json");
  fs.copyFileSync(path.join(FIXTURES, "valid-catalog.json"), catalog);
  fs.copyFileSync(path.join(FIXTURES, "valid-review.json"), review);
  fs.copyFileSync(
    path.join(FIXTURES, "valid-localizations.json"),
    localizations,
  );
  fs.copyFileSync(path.join(FIXTURES, "valid-manifest.json"), manifest);
  return {
    directory,
    catalog,
    review,
    audit,
    localizations,
    manifest,
  };
}

function commonTemporaryArguments(workspace) {
  return [
    "--catalog",
    workspace.catalog,
    "--schema",
    path.join(SHARED, "product-catalog.schema.json"),
    "--taxonomy",
    path.join(SHARED, "taxonomy.json"),
    "--review",
    workspace.review,
    "--audit",
    workspace.audit,
    "--localizations",
    workspace.localizations,
    "--manifest",
    workspace.manifest,
    "--editorial-schema",
    path.join(SHARED, "product-editorial-release.schema.json"),
  ];
}

function editorialTemporaryContext(workspace) {
  return loadEditorialContext({
    catalog: workspace.catalog,
    schema: path.join(SHARED, "product-catalog.schema.json"),
    taxonomy: path.join(SHARED, "taxonomy.json"),
    review: workspace.review,
    audit: workspace.audit,
    editorialSchema: path.join(
      SHARED,
      "product-editorial-release.schema.json",
    ),
    localizations: workspace.localizations,
    manifest: workspace.manifest,
  });
}

test("shared Hebrew normalization fixtures execute in Node", () => {
  const fixtures = readJson(
    path.join(SHARED, "normalization-fixtures.json"),
    "normalization fixtures",
  );
  for (const fixture of fixtures.fixtures) {
    assert.equal(
      normalizedValue(fixture.input),
      fixture.expected,
      fixture.id,
    );
  }
});

test("Wave 2 production catalog, taxonomy, and all 647 reviews validate", () => {
  const context = productionContext();
  const result = validateCatalog(context);
  assert.equal(result.valid, true, JSON.stringify(result.errors, null, 2));
  assert.deepEqual(result.stats, {
    products: 647,
    active: 647,
    inactive: 0,
    categories: 23,
    subcategories: 22,
  });
  assert.equal(
    buildReport(context).idFingerprint,
    "31d11cc10d8aed1f7d27b210b8402f1883f87e1a334abe50ec2c2a3b8c0d53ff",
  );
});

test("WT-031B production bundle exposes release metadata and validates localized content", () => {
  const root = productionContext();
  const context = loadEditorialContext({
    ...root.paths,
    editorialSchema: path.join(
      SHARED,
      "product-editorial-release.schema.json",
    ),
    localizations: path.join(
      REPO_ROOT,
      "WayTask",
      "Resources",
      "ProductKnowledge",
      "product-knowledge-localizations-v1.json",
    ),
    manifest: path.join(
      REPO_ROOT,
      "WayTask",
      "Resources",
      "ProductKnowledge",
      "product-catalog-release-v1.json",
    ),
  });
  const result = validateProductionBundle(context);

  assert.equal(result.valid, true, JSON.stringify(result.errors, null, 2));
  assert.equal(context.manifest.schemaVersion, 1);
  assert.equal(context.manifest.catalogVersion, 5);
  assert.equal(context.manifest.generationDate, "2026-07-25");
  assert.equal(context.manifest.productCount, 647);
  assert.equal(result.stats.localizedNames, 11);
});

test("WT-031B importer produces a complete validated bundle without mutating on dry run", () => {
  const workspace = temporaryWorkspace();
  const context = editorialTemporaryContext(workspace);
  const release = readJson(
    path.join(FIXTURES, "valid-editorial-release.json"),
  );
  const hashes = {
    catalog: fileSha256(workspace.catalog),
    review: fileSha256(workspace.review),
    localizations: fileSha256(workspace.localizations),
    manifest: fileSha256(workspace.manifest),
  };
  const plan = planEditorialImport(context, release);

  assert.equal(plan.valid, true, JSON.stringify(plan.validation.errors, null, 2));
  assert.equal(plan.catalog.products.length, 4);
  assert.equal(plan.manifest.productCount, 4);
  assert.equal(plan.manifest.generationDate, "2026-08-06");
  assert.equal(plan.localizations.catalogVersion, 4);
  assert.ok(
    plan.localizations.names.some(
      (name) =>
        name.productID === "compost_bags" &&
        name.locale === "en" &&
        name.kind === "localizedDisplay" &&
        name.value === "Compost Bags",
    ),
  );
  assert.equal(fileSha256(workspace.catalog), hashes.catalog);
  assert.equal(fileSha256(workspace.review), hashes.review);
  assert.equal(fileSha256(workspace.localizations), hashes.localizations);
  assert.equal(fileSha256(workspace.manifest), hashes.manifest);
  assert.equal(fs.existsSync(workspace.audit), false);
});

test("WT-031B editorial validator reports every required unsafe content class", async (t) => {
  const cases = [
    {
      name: "duplicate stable ID",
      code: "editorial.add_existing_product",
      change(release) {
        release.operations[0].product.id = "trash_bags";
      },
    },
    {
      name: "duplicate localized alias",
      code: "editorial.duplicate_alias",
      change(release) {
        release.operations[0].product.aliases[0].value = "שקיות זבל";
      },
    },
    {
      name: "conflicting localized display name",
      code: "editorial.conflicting_localized_name",
      change(release) {
        release.operations[0].product.canonicalNames.en = "Toilet Paper";
      },
    },
    {
      name: "invalid category",
      code: "editorial.invalid_category",
      change(release) {
        release.operations[0].product.categoryId = "missing_category";
      },
    },
    {
      name: "orphan subcategory",
      code: "editorial.orphan_subcategory",
      change(release) {
        release.operations[0].product.subcategoryId = "household.missing";
      },
    },
    {
      name: "invalid localized name",
      code: "editorial.invalid_localized_name",
      change(release) {
        release.operations[0].product.localizedDisplayNames = [
          { locale: "bad_locale!", value: "Display" },
        ];
      },
    },
    {
      name: "invalid keyword",
      code: "editorial.invalid_keyword",
      change(release) {
        release.operations[0].product.keywords = [
          { locale: "he-IL", value: "   " },
        ];
      },
    },
    {
      name: "missing canonical Hebrew name",
      code: "editorial.missing_canonical_name",
      change(release) {
        delete release.operations[0].product.canonicalNames["he-IL"];
      },
    },
    {
      name: "malformed barcode",
      code: "editorial.malformed_barcode",
      change(release) {
        release.operations[0].product.barcodes = ["1234"];
      },
    },
  ];

  for (const entry of cases) {
    await t.test(entry.name, () => {
      const workspace = temporaryWorkspace();
      const release = readJson(
        path.join(FIXTURES, "valid-editorial-release.json"),
      );
      entry.change(release);
      const plan = planEditorialImport(
        editorialTemporaryContext(workspace),
        release,
      );
      expectErrorCode(plan.validation, entry.code);
      assert.equal(fs.existsSync(workspace.audit), false);
    });
  }
});

test("WT-031B importer commits catalog, localization, manifest, review, and audit atomically", () => {
  const workspace = temporaryWorkspace();
  const context = editorialTemporaryContext(workspace);
  const release = readJson(
    path.join(FIXTURES, "valid-editorial-release.json"),
  );
  const plan = planEditorialImport(context, release);
  const committed = commitEditorialImport(context, plan);

  assert.equal(committed.validation.valid, true);
  assert.equal(readJson(workspace.catalog).catalogVersion, 4);
  assert.equal(readJson(workspace.catalog).products.length, 4);
  assert.equal(readJson(workspace.localizations).catalogVersion, 4);
  assert.equal(readJson(workspace.manifest).productCount, 4);
  assert.equal(readJson(workspace.review).productCount, 4);
  const audit = fs
    .readFileSync(workspace.audit, "utf8")
    .trim()
    .split("\n")
    .map(JSON.parse);
  assert.equal(audit.length, 1);
  assert.equal(audit[0].auditVersion, 3);
  assert.equal(audit[0].operation, "editorial_import");
  assert.equal(audit[0].releaseId, "fixture_editorial_4");
});

test("WT-031B CLI validates and dry-runs an editorial release without writes", () => {
  const workspace = temporaryWorkspace();
  const common = commonTemporaryArguments(workspace);
  const release = path.join(FIXTURES, "valid-editorial-release.json");
  const before = fileSha256(workspace.catalog);

  const production = runCli(["validate-production", ...common, "--json"]);
  assert.equal(production.status, 0, production.stderr);
  assert.equal(parseStdout(production).valid, true);

  const validation = runCli([
    "validate-release",
    "--input",
    release,
    ...common,
    "--json",
  ]);
  assert.equal(validation.status, 0, validation.stderr);
  assert.equal(parseStdout(validation).valid, true);

  const dryRun = runCli([
    "import-release",
    "--input",
    release,
    ...common,
    "--json",
  ]);
  assert.equal(dryRun.status, 0, dryRun.stderr);
  assert.equal(parseStdout(dryRun).dryRun, true);
  assert.equal(fileSha256(workspace.catalog), before);
  assert.equal(fs.existsSync(workspace.audit), false);
});

test("Wave 1 shared search fixtures resolve production canonical products", () => {
  const context = productionContext();
  const fixtures = readJson(
    path.join(SHARED, "wave-1-search-fixtures.json"),
    "Wave 1 search fixtures",
  );

  assert.equal(fixtures.fixtureVersion, 1);
  assert.equal(fixtures.locale, "he-IL");
  assert.equal(fixtures.catalogVersion, 4);
  assert.ok(fixtures.catalogVersion < context.catalog.catalogVersion);
  assert.ok(fixtures.cases.length >= 30);

  for (const fixture of fixtures.cases) {
    const results = findProducts(context, fixture.query);
    if (fixture.expectedProductId === null) {
      assert.equal(results.length, 0, fixture.id);
      continue;
    }
    assert.equal(results[0]?.id, fixture.expectedProductId, fixture.id);
    assert.equal(
      results[0]?.canonicalName,
      fixture.expectedCanonicalName,
      fixture.id,
    );
    assert.equal(results[0]?.matchSource, fixture.matchSource, fixture.id);
  }
});

test("Wave 2 shared search fixtures resolve production canonical products", () => {
  const context = productionContext();
  const fixtures = readJson(
    path.join(SHARED, "wave-2-search-fixtures.json"),
    "Wave 2 search fixtures",
  );

  assert.equal(fixtures.fixtureVersion, 1);
  assert.equal(fixtures.locale, "he-IL");
  assert.equal(fixtures.catalogVersion, context.catalog.catalogVersion);
  assert.ok(fixtures.cases.length >= 40);

  for (const fixture of fixtures.cases) {
    const results = findProducts(context, fixture.query);
    if (fixture.expectedProductId === null) {
      assert.equal(results.length, 0, fixture.id);
      continue;
    }
    assert.equal(results[0]?.id, fixture.expectedProductId, fixture.id);
    assert.equal(
      results[0]?.canonicalName,
      fixture.expectedCanonicalName,
      fixture.id,
    );
    assert.equal(results[0]?.matchSource, fixture.matchSource, fixture.id);
  }
});

test("Wave 2 preserves all prior IDs and its transactional audit history", () => {
  const context = productionContext();
  const legacy = readJson(
    path.join(
      REPO_ROOT,
      "WayTaskTests",
      "ProductCatalog",
      "product_catalog_he_legacy_v2.json",
    ),
    "legacy v2 catalog fixture",
  );
  const productionIDs = context.catalog.products.map((product) => product.id);
  const legacyIDs = legacy.products.map((product) => product.id);
  assert.equal(legacyIDs.length, 147);
  assert.deepEqual(productionIDs.slice(0, 147), legacyIDs);
  assert.equal(
    sha256(`${productionIDs.slice(0, 467).sort().join("\n")}\n`),
    "87b0b24404119ccabf6fc56a596c0f5e8334d499bfeb05634f3ff1cc5247b325",
  );

  const auditSource = fs.readFileSync(
    path.join(SHARED, "catalog-authoring-audit.jsonl"),
    "utf8",
  );
  const auditLines = auditSource.trim().split("\n");
  const auditEntries = auditLines.map(JSON.parse);
  const historicalEntries = auditEntries.slice(0, 330);
  const normalization = auditEntries[330];
  const wave2Entries = auditEntries.slice(331);
  assert.equal(auditEntries.length, 511);
  assert.equal(
    sha256(`${auditLines.slice(0, 330).join("\n")}\n`),
    "6fdf64be6980f848d1549b1ee9ebd8b247d32016b11bd0ef22df94842f87412f",
  );
  assert.equal(
    sha256(`${auditLines.slice(0, 331).join("\n")}\n`),
    "b5b01012b3427ea92cd109e29267c3634c4a8478134cdf8dc58e4cac47c361d2",
  );
  assert.deepEqual(
    historicalEntries.slice(0, 320).map((entry) => entry.productId),
    productionIDs.slice(147, 467),
  );
  assert.ok(
    historicalEntries
      .slice(0, 320)
      .every((entry) => entry.operation === "add"),
  );
  assert.deepEqual(
    historicalEntries.slice(320).map((entry) => entry.operation),
    Array(10).fill("update"),
  );
  assert.deepEqual(
    historicalEntries.slice(320).map((entry) => entry.productId),
    [
      "baby_body_wash",
      "candles",
      "cleaning_sponges",
      "coconut_milk",
      "gummy_candy",
      "margarine",
      "mop",
      "pillow_cereal",
      "sour_cream",
      "tea_lights",
    ],
  );
  for (const [index, entry] of historicalEntries.entries()) {
    assert.equal(entry.catalogVersionFrom, index + 3);
    assert.equal(entry.catalogVersionTo, index + 4);
    if (index > 0) {
      assert.equal(
        historicalEntries[index - 1].catalogSha256After,
        entry.catalogSha256Before,
      );
    }
  }
  assert.equal(normalization.auditVersion, 2);
  assert.equal(normalization.operation, "release_version_normalization");
  assert.equal(normalization.releaseId, "wt-027a-wave-1");
  assert.equal(normalization.catalogVersionFrom, 333);
  assert.equal(normalization.catalogVersionTo, 4);
  assert.equal(
    normalization.catalogSha256Before,
    historicalEntries.at(-1).catalogSha256After,
  );
  assert.equal(
    normalization.catalogSha256After,
    wave2Entries[0].catalogSha256Before,
  );

  assert.equal(wave2Entries.length, 180);
  assert.deepEqual(
    wave2Entries.map((entry) => entry.productId),
    productionIDs.slice(467),
  );
  assert.ok(
    wave2Entries.every(
      (entry, index) =>
        entry.auditVersion === 2 &&
        entry.operation === "add" &&
        entry.releaseId === "wt-027b-wave-2" &&
        entry.releaseOperation === "batch" &&
        entry.catalogVersionFrom === 4 &&
        entry.catalogVersionTo === 5 &&
        entry.batchSize === 180 &&
        entry.batchIndex === index + 1 &&
        entry.catalogSha256Before ===
          wave2Entries[0].catalogSha256Before &&
        entry.catalogSha256After ===
          wave2Entries[0].catalogSha256After,
    ),
  );
  assert.equal(
    wave2Entries.at(-1).catalogSha256After,
    fileSha256(PRODUCTION_CATALOG),
  );
});

test("validator detects every required hard-error class", async (t) => {
  const cases = [
    {
      name: "duplicate IDs",
      code: "product.duplicate_id",
      change(context) {
        const duplicate = clone(context.catalog.products[0]);
        duplicate.canonicalName = "שם בדיקה ייחודי";
        duplicate.aliases = [];
        context.catalog.products.push(duplicate);
      },
    },
    {
      name: "duplicate canonical names",
      code: "product.duplicate_canonical_name",
      change(context) {
        context.catalog.products[1].canonicalName =
          context.catalog.products[0].canonicalName;
      },
    },
    {
      name: "alias collisions",
      code: "product.alias_collision",
      change(context) {
        context.catalog.products[1].aliases = ["שקיות זבל"];
      },
    },
    {
      name: "invalid category",
      code: "product.orphan_category",
      change(context) {
        context.catalog.products[0].categoryId = "missing_category";
      },
    },
    {
      name: "invalid subcategory parent",
      code: "product.subcategory_parent_mismatch",
      change(context) {
        context.catalog.products[0].categoryId = "cleaning";
      },
    },
    {
      name: "invalid popularity",
      code: "product.invalid_popularity",
      change(context) {
        context.catalog.products[0].popularityScore = 101;
      },
    },
    {
      name: "schema errors",
      code: "schema.missing_required_field",
      change(context) {
        delete context.catalog.products[0].canonicalName;
      },
    },
    {
      name: "replacement loops",
      code: "replacement.loop",
      change(context) {
        const trashBags = context.catalog.products[0];
        trashBags.isActive = false;
        trashBags.replacementProductId = "legacy_waste_bags";
        trashBags.deprecatedSinceCatalogVersion = 3;
      },
    },
    {
      name: "empty required fields",
      code: "product.empty_required_field",
      change(context) {
        context.catalog.products[0].canonicalName = "   ";
      },
    },
  ];

  for (const entry of cases) {
    await t.test(entry.name, () => {
      expectErrorCode(validationWith(entry.change), entry.code);
    });
  }
});

test("report, find, inspect, and candidate checks use canonical data", () => {
  const context = fixtureContext();
  const report = buildReport(context);
  assert.equal(report.valid, true);
  assert.equal(report.products.total, 3);
  assert.equal(report.products.active, 2);

  const results = findProducts(context, "שקיות זבל");
  assert.equal(results.length, 1);
  assert.equal(results[0].id, "trash_bags");
  assert.equal(results[0].matchSource, "alias");

  const inspection = inspectProduct(context, "trash_bags");
  assert.equal(
    inspection.taxonomy.subcategory.id,
    "household.waste_bags",
  );
  assert.equal(inspection.review.productId, "trash_bags");

  const validCandidate = readJson(
    path.join(FIXTURES, "candidate-new.json"),
  );
  assert.equal(checkCandidate(context, validCandidate).valid, true);

  const collision = readJson(
    path.join(FIXTURES, "candidate-collision.json"),
  );
  expectErrorCode(
    checkCandidate(context, collision),
    "product.duplicate_canonical_name",
  );
});

test("read-only CLI commands return actionable machine-readable results", () => {
  const before = fileSha256(PRODUCTION_CATALOG);

  const validation = runCli(["validate", "--json"]);
  assert.equal(validation.status, 0, validation.stderr);
  assert.equal(parseStdout(validation).stats.products, 647);

  const report = runCli(["report", "--json"]);
  assert.equal(report.status, 0, report.stderr);
  assert.equal(parseStdout(report).metadata.catalogVersion, 5);
  assert.equal(parseStdout(report).metadata.generationDate, "2026-07-25");
  assert.equal(parseStdout(report).metadata.productCount, 647);

  const find = runCli([
    "find",
    "--query",
    "שקיות זבל",
    "--json",
  ]);
  assert.equal(find.status, 0, find.stderr);
  assert.equal(parseStdout(find)[0].id, "trash_bags");

  const inspect = runCli(["inspect", "--id", "trash_bags"]);
  assert.equal(inspect.status, 0, inspect.stderr);
  assert.equal(parseStdout(inspect).product.id, "trash_bags");

  const candidate = runCli([
    "check-candidate",
    "--input",
    path.join(FIXTURES, "candidate-new.json"),
    "--json",
  ]);
  assert.equal(candidate.status, 0, candidate.stderr);
  assert.equal(parseStdout(candidate).valid, true);

  const collision = runCli([
    "check-candidate",
    "--input",
    path.join(FIXTURES, "candidate-collision.json"),
    "--json",
  ]);
  assert.equal(collision.status, 1);
  assert.equal(parseStdout(collision).valid, false);

  assert.equal(fileSha256(PRODUCTION_CATALOG), before);
});

test("add, update, and deactivate are dry-run by default and audited on write", () => {
  const workspace = temporaryWorkspace();
  const common = commonTemporaryArguments(workspace);
  const initialCatalogHash = fileSha256(workspace.catalog);
  const initialReviewHash = fileSha256(workspace.review);

  const addDryRun = runCli([
    "add",
    "--input",
    path.join(FIXTURES, "candidate-new.json"),
    ...common,
    "--json",
  ]);
  assert.equal(addDryRun.status, 0, addDryRun.stderr);
  assert.equal(parseStdout(addDryRun).dryRun, true);
  assert.equal(fileSha256(workspace.catalog), initialCatalogHash);
  assert.equal(fileSha256(workspace.review), initialReviewHash);
  assert.equal(fs.existsSync(workspace.audit), false);

  const addWrite = runCli([
    "add",
    "--input",
    path.join(FIXTURES, "candidate-new.json"),
    ...common,
    "--write",
    "--json",
  ]);
  assert.equal(addWrite.status, 0, addWrite.stderr);
  assert.equal(parseStdout(addWrite).catalogVersionTo, 4);
  assert.equal(readJson(workspace.catalog).products.length, 4);
  assert.equal(readJson(workspace.review).productCount, 4);

  const updateHash = fileSha256(workspace.catalog);
  const updateDryRun = runCli([
    "update",
    "--id",
    "trash_bags",
    "--input",
    path.join(FIXTURES, "update-trash-bags.json"),
    ...common,
    "--json",
  ]);
  assert.equal(updateDryRun.status, 0, updateDryRun.stderr);
  assert.equal(parseStdout(updateDryRun).catalogVersionTo, 5);
  assert.equal(fileSha256(workspace.catalog), updateHash);

  const updateWrite = runCli([
    "update",
    "--id",
    "trash_bags",
    "--input",
    path.join(FIXTURES, "update-trash-bags.json"),
    ...common,
    "--write",
    "--json",
  ]);
  assert.equal(updateWrite.status, 0, updateWrite.stderr);
  assert.equal(readJson(workspace.catalog).catalogVersion, 5);

  const deactivateHash = fileSha256(workspace.catalog);
  const deactivateDryRun = runCli([
    "deactivate",
    "--id",
    "toilet_paper",
    ...common,
    "--json",
  ]);
  assert.equal(deactivateDryRun.status, 0, deactivateDryRun.stderr);
  assert.equal(parseStdout(deactivateDryRun).catalogVersionTo, 6);
  assert.equal(fileSha256(workspace.catalog), deactivateHash);

  const deactivateWrite = runCli([
    "deactivate",
    "--id",
    "toilet_paper",
    ...common,
    "--write",
    "--json",
  ]);
  assert.equal(deactivateWrite.status, 0, deactivateWrite.stderr);
  const finalCatalog = readJson(workspace.catalog);
  assert.equal(finalCatalog.catalogVersion, 6);
  const toiletPaper = finalCatalog.products.find(
    (product) => product.id === "toilet_paper",
  );
  assert.equal(toiletPaper.isActive, false);
  assert.equal(toiletPaper.deprecatedSinceCatalogVersion, 6);

  const auditEntries = fs
    .readFileSync(workspace.audit, "utf8")
    .trim()
    .split("\n")
    .map(JSON.parse);
  assert.deepEqual(
    auditEntries.map((entry) => entry.operation),
    ["add", "update", "deactivate"],
  );
  assert.deepEqual(
    auditEntries.map((entry) => entry.catalogVersionTo),
    [4, 5, 6],
  );
  assert.ok(
    auditEntries.every(
      (entry) =>
        entry.auditVersion === 2 &&
        entry.releaseOperation === "single" &&
        entry.catalogSha256Before.length === 64 &&
        entry.catalogSha256After.length === 64,
    ),
  );

  const finalValidation = runCli([
    "validate",
    ...common,
    "--json",
  ]);
  assert.equal(finalValidation.status, 0, finalValidation.stderr);
  assert.equal(parseStdout(finalValidation).valid, true);
});

test("batch release is atomic, audited per mutation, and increments version once", () => {
  const workspace = temporaryWorkspace();
  const common = commonTemporaryArguments(workspace);
  const input = path.join(FIXTURES, "batch-release.json");
  const initialCatalogHash = fileSha256(workspace.catalog);
  const initialReviewHash = fileSha256(workspace.review);

  const dryRun = runCli([
    "batch",
    "--input",
    input,
    ...common,
    "--json",
  ]);
  assert.equal(dryRun.status, 0, dryRun.stderr);
  const dryRunSummary = parseStdout(dryRun);
  assert.equal(dryRunSummary.operation, "batch");
  assert.equal(dryRunSummary.releaseId, "fixture_release_4");
  assert.equal(dryRunSummary.mutationCount, 3);
  assert.equal(dryRunSummary.catalogVersionFrom, 3);
  assert.equal(dryRunSummary.catalogVersionTo, 4);
  assert.equal(fileSha256(workspace.catalog), initialCatalogHash);
  assert.equal(fileSha256(workspace.review), initialReviewHash);
  assert.equal(fs.existsSync(workspace.audit), false);

  const write = runCli([
    "batch",
    "--input",
    input,
    ...common,
    "--write",
    "--json",
  ]);
  assert.equal(write.status, 0, write.stderr);
  const summary = parseStdout(write);
  assert.equal(summary.catalogVersionTo, 4);
  assert.equal(summary.audits.length, 3);

  const catalog = readJson(workspace.catalog);
  const review = readJson(workspace.review);
  assert.equal(catalog.catalogVersion, 4);
  assert.equal(catalog.products.length, 4);
  assert.equal(review.catalogVersion, 4);
  assert.equal(review.productCount, 4);
  assert.equal(
    catalog.products.find((product) => product.id === "toilet_paper")
      .deprecatedSinceCatalogVersion,
    4,
  );

  const auditEntries = fs
    .readFileSync(workspace.audit, "utf8")
    .trim()
    .split("\n")
    .map(JSON.parse);
  assert.deepEqual(
    auditEntries.map((entry) => entry.operation),
    ["add", "update", "deactivate"],
  );
  assert.ok(
    auditEntries.every(
      (entry, index) =>
        entry.auditVersion === 2 &&
        entry.releaseOperation === "batch" &&
        entry.releaseId === "fixture_release_4" &&
        entry.batchIndex === index + 1 &&
        entry.batchSize === 3 &&
        entry.catalogVersionFrom === 3 &&
        entry.catalogVersionTo === 4 &&
        entry.catalogSha256Before === auditEntries[0].catalogSha256Before &&
        entry.catalogSha256After === auditEntries[0].catalogSha256After,
    ),
  );

  const validation = runCli(["validate", ...common, "--json"]);
  assert.equal(validation.status, 0, validation.stderr);
  assert.equal(parseStdout(validation).valid, true);
});

test("invalid batch release writes no catalog, review, or audit files", () => {
  const workspace = temporaryWorkspace();
  const paths = {
    catalog: workspace.catalog,
    schema: path.join(SHARED, "product-catalog.schema.json"),
    taxonomy: path.join(SHARED, "taxonomy.json"),
    review: workspace.review,
    audit: workspace.audit,
  };
  const context = loadContext(paths);
  const release = readJson(
    path.join(FIXTURES, "batch-release.json"),
    "batch release fixture",
  );
  release.operations[0].product.canonicalName = "נייר טואלט";
  const plan = planBatch(context, release);
  assert.equal(plan.validation.valid, false);
  const catalogHash = fileSha256(workspace.catalog);
  const reviewHash = fileSha256(workspace.review);

  assert.throws(() => commitPlan(context, plan), /invalid/);
  assert.equal(fileSha256(workspace.catalog), catalogHash);
  assert.equal(fileSha256(workspace.review), reviewHash);
  assert.equal(fs.existsSync(workspace.audit), false);
});

test("write transaction rejects a stale catalog snapshot", () => {
  const workspace = temporaryWorkspace();
  const paths = {
    catalog: workspace.catalog,
    schema: path.join(SHARED, "product-catalog.schema.json"),
    taxonomy: path.join(SHARED, "taxonomy.json"),
    review: workspace.review,
    audit: workspace.audit,
  };
  const context = loadContext(paths);
  const candidate = readJson(
    path.join(FIXTURES, "candidate-new.json"),
  );
  const plan = planAdd(context, candidate);

  fs.appendFileSync(workspace.catalog, "\n");
  assert.throws(
    () => commitPlan(context, plan),
    /changed after loading/,
  );
  assert.equal(fs.existsSync(workspace.audit), false);
  assert.equal(readJson(workspace.catalog).products.length, 3);
});
