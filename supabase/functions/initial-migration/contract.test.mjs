import assert from "node:assert/strict";
import test from "node:test";
import {
  MigrationContractError,
  publicError,
  requireBearer,
  rpcFor,
  validateRequest,
  verifyPayloadIntegrity,
} from "./contract.mjs";

const attempt = "10000000-0000-4000-8000-000000000001";
const dataset = "20000000-0000-4000-8000-000000000002";
const hash = "a".repeat(64);

test("begin accepts exact versioned manifest and never forwards owner", () => {
  const value = validateRequest({
    operation: "begin",
    attempt_id: attempt,
    local_dataset_id: dataset,
    dataset_fingerprint: hash,
    format_version: 1,
    counts: {
      personal_products: 1,
      shopping_lists: 1,
      shopping_list_entries: 1,
    },
  });
  assert.deepEqual(rpcFor(value).body, {
    p_attempt_id: attempt,
    p_local_dataset_id: dataset,
    p_dataset_fingerprint: hash,
    p_format_version: 1,
    p_counts: value.counts,
  });
});

test("owner and target UUID authority fields are rejected recursively", () => {
  assert.throws(() => validateRequest({
    operation: "upload",
    attempt_id: attempt,
    batch_id: hash,
    sequence: 0,
    entity_kind: "personal_products",
    payload_sha256: hash,
    records: [{ id: dataset, owner_user_id: dataset }],
  }), (error) => error instanceof MigrationContractError &&
      error.code === "owner_field_forbidden");
});

test("malformed and oversized batches fail closed", () => {
  const base = {
    operation: "upload",
    attempt_id: attempt,
    batch_id: hash,
    sequence: 0,
    entity_kind: "personal_products",
    payload_sha256: hash,
  };
  assert.throws(() => validateRequest({ ...base, records: [] }));
  assert.throws(() => validateRequest({
    ...base,
    records: Array.from({ length: 501 }, (_, id) => ({ id })),
  }));
  assert.throws(() => validateRequest({ ...base, sequence: -1, records: [{}] }));
  assert.throws(() => validateRequest({
    ...base, sequence: 5_100, records: [{}],
  }));
});

test("unsupported versions and unknown fields are rejected", () => {
  assert.throws(() => validateRequest({
    operation: "begin",
    attempt_id: attempt,
    local_dataset_id: dataset,
    dataset_fingerprint: hash,
    format_version: 2,
    counts: {
      personal_products: 0,
      shopping_lists: 0,
      shopping_list_entries: 0,
    },
  }));
  assert.throws(() => validateRequest({
    operation: "verify",
    attempt_id: attempt,
    complete: true,
  }));
});

test("missing token and provider details are privacy-safe", () => {
  assert.throws(() => requireBearer(null));
  assert.deepEqual(publicError(new Error("raw database failure")), {
    status: 503,
    code: "migration_temporarily_unavailable",
  });
  assert.deepEqual(publicError(new Error("migration_verification_failed")), {
    status: 422,
    code: "migration_verification_failed",
  });
  assert.deepEqual(publicError(new Error("migration_manifest_count_exceeded")), {
    status: 400,
    code: "invalid_migration_request",
  });
});

test("upload content must match its declared canonical payload hash", async () => {
  const records = [{ display_name: "Synthetic", id: dataset }];
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify(records)),
  );
  const payloadHash = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  const request = validateRequest({
    operation: "upload",
    attempt_id: attempt,
    batch_id: hash,
    sequence: 0,
    entity_kind: "personal_products",
    payload_sha256: payloadHash,
    records,
  });
  await verifyPayloadIntegrity(request);
  await assert.rejects(
    verifyPayloadIntegrity({ ...request, payload_sha256: hash }),
    (error) => error instanceof MigrationContractError &&
      error.code === "payload_hash_mismatch",
  );
});
