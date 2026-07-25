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
} = require("../lib/catalog");
const { fileSha256, readJson } = require("../lib/io");
const { normalizedValue } = require("../lib/normalization");
const { validateCatalog } = require("../lib/validator");

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
  fs.copyFileSync(path.join(FIXTURES, "valid-catalog.json"), catalog);
  fs.copyFileSync(path.join(FIXTURES, "valid-review.json"), review);
  return { directory, catalog, review, audit };
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
  ];
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

test("production catalog, taxonomy, and all 147 reviews validate", () => {
  const context = productionContext();
  const result = validateCatalog(context);
  assert.equal(result.valid, true, JSON.stringify(result.errors, null, 2));
  assert.deepEqual(result.stats, {
    products: 147,
    active: 147,
    inactive: 0,
    categories: 23,
    subcategories: 22,
  });
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
  assert.equal(parseStdout(validation).stats.products, 147);

  const report = runCli(["report", "--json"]);
  assert.equal(report.status, 0, report.stderr);
  assert.equal(parseStdout(report).metadata.catalogVersion, 3);

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
