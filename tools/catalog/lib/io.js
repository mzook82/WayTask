"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

function readJson(filePath, label = "JSON file") {
  let source;
  try {
    source = fs.readFileSync(filePath, "utf8");
  } catch (error) {
    throw new Error(`Cannot read ${label} at ${filePath}: ${error.message}`);
  }

  try {
    return JSON.parse(source);
  } catch (error) {
    throw new Error(`Invalid JSON in ${label} at ${filePath}: ${error.message}`);
  }
}

function jsonText(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

function sha256(value) {
  const bytes = Buffer.isBuffer(value) ? value : Buffer.from(String(value));
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function fileSha256(filePath) {
  return sha256(fs.readFileSync(filePath));
}

function ensureParentDirectory(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function temporaryPath(filePath) {
  const token = crypto.randomBytes(6).toString("hex");
  return path.join(
    path.dirname(filePath),
    `.${path.basename(filePath)}.${process.pid}.${token}.tmp`,
  );
}

function writeTransaction(files) {
  const seen = new Set();
  const prepared = [];
  const replaced = [];

  try {
    for (const file of files) {
      if (seen.has(file.path)) {
        throw new Error(`Transaction contains duplicate path: ${file.path}`);
      }
      seen.add(file.path);
      ensureParentDirectory(file.path);
      const tempPath = temporaryPath(file.path);
      fs.writeFileSync(tempPath, file.content, {
        encoding: "utf8",
        flag: "wx",
      });
      prepared.push({
        ...file,
        tempPath,
        original: fs.existsSync(file.path)
          ? fs.readFileSync(file.path)
          : null,
      });
    }

    for (const file of prepared) {
      fs.renameSync(file.tempPath, file.path);
      replaced.push(file);
    }
  } catch (error) {
    for (const file of [...replaced].reverse()) {
      try {
        if (file.original === null) {
          fs.unlinkSync(file.path);
        } else {
          const restorePath = temporaryPath(file.path);
          fs.writeFileSync(restorePath, file.original, { flag: "wx" });
          fs.renameSync(restorePath, file.path);
        }
      } catch {
        // Preserve the original failure. A caller still receives a hard error.
      }
    }
    throw error;
  } finally {
    for (const file of prepared) {
      if (fs.existsSync(file.tempPath)) {
        fs.unlinkSync(file.tempPath);
      }
    }
  }
}

function auditEntriesText(auditPath, entries) {
  if (!Array.isArray(entries) || entries.length === 0) {
    throw new Error("Audit append requires at least one entry.");
  }
  let existing = "";
  if (fs.existsSync(auditPath)) {
    existing = fs.readFileSync(auditPath, "utf8");
    for (const [index, line] of existing.split("\n").entries()) {
      if (line.trim().length === 0) {
        continue;
      }
      try {
        JSON.parse(line);
      } catch (error) {
        throw new Error(
          `Invalid audit JSON on line ${index + 1} of ${auditPath}: ${error.message}`,
        );
      }
    }
    if (existing.length > 0 && !existing.endsWith("\n")) {
      existing += "\n";
    }
  }
  return `${existing}${entries.map((entry) => JSON.stringify(entry)).join("\n")}\n`;
}

function auditText(auditPath, entry) {
  return auditEntriesText(auditPath, [entry]);
}

module.exports = {
  auditEntriesText,
  auditText,
  fileSha256,
  jsonText,
  readJson,
  sha256,
  writeTransaction,
};
