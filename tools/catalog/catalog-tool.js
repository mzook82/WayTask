#!/usr/bin/env node
"use strict";

const path = require("node:path");
const {
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
} = require("./lib/catalog");
const { readJson } = require("./lib/io");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const DEFAULTS = {
  catalog: path.join(
    REPO_ROOT,
    "WayTask",
    "Resources",
    "product_catalog_he.json",
  ),
  schema: path.join(
    REPO_ROOT,
    "shared",
    "catalog",
    "product-catalog.schema.json",
  ),
  taxonomy: path.join(
    REPO_ROOT,
    "shared",
    "catalog",
    "taxonomy.json",
  ),
  review: path.join(
    REPO_ROOT,
    "shared",
    "catalog",
    "product-taxonomy-review.json",
  ),
  audit: path.join(
    REPO_ROOT,
    "shared",
    "catalog",
    "catalog-authoring-audit.jsonl",
  ),
};

const VALUE_OPTIONS = new Set([
  "audit",
  "catalog",
  "id",
  "input",
  "limit",
  "query",
  "review",
  "schema",
  "taxonomy",
]);
const BOOLEAN_OPTIONS = new Set([
  "help",
  "include-inactive",
  "json",
  "write",
]);

function usage() {
  return `WayTask canonical catalog authoring toolkit

Usage:
  node tools/catalog/catalog-tool.js validate [--json]
  node tools/catalog/catalog-tool.js report [--json]
  node tools/catalog/catalog-tool.js find --query "שקיות זבל" [--limit 10] [--json]
  node tools/catalog/catalog-tool.js inspect --id trash_bags [--json]
  node tools/catalog/catalog-tool.js check-candidate --input product.json [--json]
  node tools/catalog/catalog-tool.js add --input product.json [--write] [--json]
  node tools/catalog/catalog-tool.js update --id trash_bags --input patch.json [--write] [--json]
  node tools/catalog/catalog-tool.js deactivate --id product_id [--write] [--json]
  node tools/catalog/catalog-tool.js batch --input release.json [--write] [--json]

Mutation commands are dry runs unless --write is present. A committed write
represents one catalog release operation: it increments catalogVersion exactly
once, updates the taxonomy review manifest, validates the complete proposal, and
appends audit JSON lines for its mutations. A batch is one atomic release even
when it contains multiple product mutations.

Common path overrides:
  --catalog PATH   --schema PATH   --taxonomy PATH
  --review PATH    --audit PATH
`;
}

function parseArguments(argv) {
  const [command, ...rest] = argv;
  const options = {};
  for (let index = 0; index < rest.length; index += 1) {
    const argument = rest[index];
    if (!argument.startsWith("--")) {
      throw new Error(`Unexpected positional argument: ${argument}`);
    }
    const name = argument.slice(2);
    if (BOOLEAN_OPTIONS.has(name)) {
      options[name] = true;
      continue;
    }
    if (!VALUE_OPTIONS.has(name)) {
      throw new Error(`Unknown option: --${name}`);
    }
    const value = rest[index + 1];
    if (value === undefined || value.startsWith("--")) {
      throw new Error(`Option --${name} requires a value.`);
    }
    options[name] = value;
    index += 1;
  }
  return { command, options };
}

function resolvedPath(value, fallback) {
  return value ? path.resolve(process.cwd(), value) : fallback;
}

function contextPaths(options) {
  return {
    catalog: resolvedPath(options.catalog, DEFAULTS.catalog),
    schema: resolvedPath(options.schema, DEFAULTS.schema),
    taxonomy: resolvedPath(options.taxonomy, DEFAULTS.taxonomy),
    review: resolvedPath(options.review, DEFAULTS.review),
    audit: resolvedPath(options.audit, DEFAULTS.audit),
  };
}

function requireOption(options, name, command) {
  const value = options[name];
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${command} requires --${name}.`);
  }
  return value;
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function printValidation(validation) {
  if (validation.valid) {
    console.log(
      `VALID: ${validation.stats.products} products (${validation.stats.active} active, ${validation.stats.inactive} inactive), ${validation.warnings.length} warnings.`,
    );
  } else {
    console.error(
      `INVALID: ${validation.errors.length} errors, ${validation.warnings.length} warnings.`,
    );
  }
  for (const entry of validation.errors) {
    console.error(`ERROR [${entry.code}] ${entry.message}`);
  }
  for (const entry of validation.warnings) {
    console.error(`WARNING [${entry.code}] ${entry.message}`);
  }
}

function printReport(report) {
  console.log(
    `Catalog schema ${report.metadata.schemaVersion}, catalog ${report.metadata.catalogVersion}, taxonomy ${report.metadata.taxonomyVersion}, ${report.metadata.locale}`,
  );
  console.log(
    `Products: ${report.products.total} total, ${report.products.active} active, ${report.products.inactive} inactive`,
  );
  console.log(
    `Taxonomy: ${report.taxonomy.categories} categories, ${report.taxonomy.subcategories} subcategories`,
  );
  console.log(
    `Review: ${report.review.entries} entries; validation ${report.valid ? "valid" : "invalid"}`,
  );
  console.log(`ID fingerprint: ${report.idFingerprint}`);
  console.log("Category assignments:");
  for (const category of report.taxonomy.assignments) {
    console.log(
      `  ${category.categoryId}: ${category.active} active, ${category.inactive} inactive (${category.displayName})`,
    );
  }
}

function printFind(results) {
  if (results.length === 0) {
    console.log("No diagnostic catalog matches.");
    return;
  }
  for (const [index, result] of results.entries()) {
    console.log(
      `${index + 1}. ${result.id} — ${result.canonicalName} [${result.matchSource}: ${result.matchedValue}]`,
    );
  }
}

function planSummary(plan, written) {
  return {
    operation: plan.operation,
    productId: plan.productId,
    ...(plan.releaseId ? { releaseId: plan.releaseId } : {}),
    ...(plan.mutations
      ? {
          mutationCount: plan.mutations.length,
          mutations: plan.mutations.map((mutation) => ({
            operation: mutation.operation,
            productId: mutation.productId,
            changedFields: mutation.changedFields,
          })),
        }
      : {}),
    dryRun: !written,
    written,
    catalogVersionFrom: plan.catalogVersionFrom,
    catalogVersionTo: plan.catalogVersionTo,
    changedFields: plan.changedFields,
    valid: plan.validation.valid,
    errors: plan.validation.errors,
    warnings: plan.validation.warnings,
  };
}

function executeMutation(context, plan, options) {
  if (!plan.validation.valid) {
    if (options.json) {
      printJson(planSummary(plan, false));
    } else {
      printValidation(plan.validation);
      console.error("Nothing was written.");
    }
    process.exitCode = 1;
    return;
  }

  if (!options.write) {
    const summary = planSummary(plan, false);
    if (options.json) {
      printJson(summary);
    } else {
      const target =
        plan.operation === "batch"
          ? `${plan.releaseId} (${plan.mutations.length} mutations)`
          : plan.productId;
      console.log(
        `DRY RUN: ${plan.operation} ${target}; catalogVersion ${plan.catalogVersionFrom} -> ${plan.catalogVersionTo}.`,
      );
      console.log(`Changed fields: ${plan.changedFields.join(", ")}`);
      console.log("VALID. Nothing was written; re-run with --write to commit.");
    }
    return;
  }

  const committed = commitPlan(context, plan);
  const summary = {
    ...planSummary(plan, true),
    ...(committed.auditEntry
      ? { audit: committed.auditEntry }
      : { audits: committed.auditEntries }),
    auditPath: relativePath(REPO_ROOT, context.paths.audit),
  };
  if (options.json) {
    printJson(summary);
  } else {
    const target =
      plan.operation === "batch"
        ? `${plan.releaseId} (${plan.mutations.length} mutations)`
        : plan.productId;
    console.log(
      `WROTE: ${plan.operation} ${target}; catalogVersion ${plan.catalogVersionFrom} -> ${plan.catalogVersionTo}.`,
    );
    console.log(
      `Audit appended to ${relativePath(REPO_ROOT, context.paths.audit)}.`,
    );
    console.log("Post-write validation passed.");
  }
}

function main() {
  const { command, options } = parseArguments(process.argv.slice(2));
  if (!command || command === "help" || options.help) {
    console.log(usage());
    return;
  }

  const supported = new Set([
    "validate",
    "report",
    "find",
    "inspect",
    "check-candidate",
    "add",
    "update",
    "deactivate",
    "batch",
  ]);
  if (!supported.has(command)) {
    throw new Error(`Unknown command: ${command}\n\n${usage()}`);
  }

  const context = loadContext(contextPaths(options));
  switch (command) {
    case "validate": {
      const validation = validateContext(context);
      if (options.json) {
        printJson(validation);
      } else {
        printValidation(validation);
      }
      if (!validation.valid) {
        process.exitCode = 1;
      }
      break;
    }
    case "report": {
      const report = buildReport(context);
      if (options.json) {
        printJson(report);
      } else {
        printReport(report);
      }
      if (!report.valid) {
        process.exitCode = 1;
      }
      break;
    }
    case "find": {
      const query = requireOption(options, "query", command);
      let results = findProducts(context, query, {
        includeInactive: Boolean(options["include-inactive"]),
      });
      if (options.limit !== undefined) {
        const limit = Number(options.limit);
        if (!Number.isInteger(limit) || limit < 1) {
          throw new Error("--limit must be a positive integer.");
        }
        results = results.slice(0, limit);
      }
      options.json ? printJson(results) : printFind(results);
      break;
    }
    case "inspect": {
      const id = requireOption(options, "id", command);
      const inspection = inspectProduct(context, id);
      printJson(inspection);
      break;
    }
    case "check-candidate": {
      const input = requireOption(options, "input", command);
      const candidate = readJson(
        resolvedPath(input),
        "candidate product",
      );
      const result = checkCandidate(context, candidate);
      options.json ? printJson(result) : printValidation(result);
      if (!result.valid) {
        process.exitCode = 1;
      }
      break;
    }
    case "add": {
      const input = requireOption(options, "input", command);
      const product = readJson(resolvedPath(input), "product input");
      executeMutation(context, planAdd(context, product), options);
      break;
    }
    case "update": {
      const id = requireOption(options, "id", command);
      const input = requireOption(options, "input", command);
      const patch = readJson(resolvedPath(input), "product update");
      executeMutation(context, planUpdate(context, id, patch), options);
      break;
    }
    case "deactivate": {
      const id = requireOption(options, "id", command);
      executeMutation(context, planDeactivate(context, id), options);
      break;
    }
    case "batch": {
      const input = requireOption(options, "input", command);
      const release = readJson(resolvedPath(input), "batch release input");
      executeMutation(context, planBatch(context, release), options);
      break;
    }
    default:
      throw new Error(`Unhandled command: ${command}`);
  }
}

try {
  main();
} catch (error) {
  console.error(`catalog-tool: ${error.message}`);
  process.exitCode = 1;
}
