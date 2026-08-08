export const MAX_RECORDS = 100;
export const MAX_BATCHES = 5_100;
export const MAX_PAYLOAD_BYTES = 1_048_576;
export const MAX_REQUEST_BYTES = 1_100_000;
export const FORMAT_VERSION = 1;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA256 = /^[0-9a-f]{64}$/;
const OPERATIONS = new Set(["begin", "upload", "verify", "rollback"]);
const KINDS = new Set([
  "personal_products",
  "shopping_lists",
  "shopping_list_entries",
]);

export class MigrationContractError extends Error {
  constructor(code, status = 400) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

export function requireBearer(value) {
  if (typeof value !== "string" || !/^Bearer [^\s]+$/.test(value)) {
    throw new MigrationContractError("authentication_required", 401);
  }
  return value;
}

export function validateRequest(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new MigrationContractError("invalid_request");
  }
  if (!OPERATIONS.has(value.operation) || !UUID.test(value.attempt_id ?? "")) {
    throw new MigrationContractError("invalid_request");
  }
  rejectOwnerAuthority(value);

  switch (value.operation) {
    case "begin":
      validateBegin(value);
      break;
    case "upload":
      validateUpload(value);
      break;
    case "verify":
    case "rollback":
      exactKeys(value, ["operation", "attempt_id"]);
      break;
  }
  return value;
}

export async function verifyPayloadIntegrity(value) {
  if (value.operation !== "upload") return;
  const payload = new TextEncoder().encode(JSON.stringify(value.records));
  const digest = await crypto.subtle.digest("SHA-256", payload);
  const actual = Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  if (actual !== value.payload_sha256) {
    throw new MigrationContractError("payload_hash_mismatch");
  }
}

function validateBegin(value) {
  exactKeys(value, [
    "operation",
    "attempt_id",
    "local_dataset_id",
    "dataset_fingerprint",
    "format_version",
    "counts",
  ]);
  if (!UUID.test(value.local_dataset_id ?? "") ||
      !SHA256.test(value.dataset_fingerprint ?? "") ||
      value.format_version !== FORMAT_VERSION ||
      !value.counts || typeof value.counts !== "object") {
    throw new MigrationContractError("invalid_manifest");
  }
  exactKeys(value.counts, [
    "personal_products",
    "shopping_lists",
    "shopping_list_entries",
  ]);
  const counts = Object.values(value.counts);
  if (!counts.every(Number.isSafeInteger) || counts.some((count) => count < 0) ||
      value.counts.personal_products > 100_000 ||
      value.counts.shopping_lists > 10_000 ||
      value.counts.shopping_list_entries > 500_000 ||
      counts.reduce((sum, count) => sum + count, 0) > 510_000) {
    throw new MigrationContractError("manifest_oversized", 413);
  }
}

function validateUpload(value) {
  exactKeys(value, [
    "operation",
    "attempt_id",
    "batch_id",
    "sequence",
    "entity_kind",
    "payload_sha256",
    "records",
  ]);
  if (!SHA256.test(value.batch_id ?? "") ||
      !SHA256.test(value.payload_sha256 ?? "") ||
      !Number.isSafeInteger(value.sequence) || value.sequence < 0 ||
      value.sequence >= MAX_BATCHES ||
      !KINDS.has(value.entity_kind) || !Array.isArray(value.records)) {
    throw new MigrationContractError("invalid_batch");
  }
  const payloadBytes = new TextEncoder().encode(
    JSON.stringify(value.records),
  ).byteLength;
  if (value.records.length < 1 || value.records.length > MAX_RECORDS ||
      payloadBytes > MAX_PAYLOAD_BYTES) {
    throw new MigrationContractError("batch_oversized", 413);
  }
  rejectOwnerAuthority(value.records);
}

function rejectOwnerAuthority(value) {
  if (Array.isArray(value)) {
    value.forEach(rejectOwnerAuthority);
    return;
  }
  if (!value || typeof value !== "object") return;
  for (const [key, child] of Object.entries(value)) {
    if (["owner_user_id", "ownerUserID", "target_user_id", "targetUserID"]
      .includes(key)) {
      throw new MigrationContractError("owner_field_forbidden", 403);
    }
    rejectOwnerAuthority(child);
  }
}

function exactKeys(value, allowed) {
  const actual = Object.keys(value).sort();
  const expected = [...allowed].sort();
  if (actual.length !== expected.length ||
      actual.some((key, index) => key !== expected[index])) {
    throw new MigrationContractError("invalid_request");
  }
}

export function rpcFor(request) {
  switch (request.operation) {
    case "begin":
      return {
        name: "initial_migration_begin",
        body: {
          p_attempt_id: request.attempt_id,
          p_local_dataset_id: request.local_dataset_id,
          p_dataset_fingerprint: request.dataset_fingerprint,
          p_format_version: request.format_version,
          p_counts: request.counts,
        },
      };
    case "upload":
      return {
        name: "initial_migration_apply_batch",
        body: {
          p_attempt_id: request.attempt_id,
          p_batch_id: request.batch_id,
          p_sequence: request.sequence,
          p_entity_kind: request.entity_kind,
          p_client_payload_sha256: request.payload_sha256,
          p_records: request.records,
        },
      };
    case "verify":
      return {
        name: "initial_migration_verify",
        body: { p_attempt_id: request.attempt_id },
      };
    case "rollback":
      return {
        name: "initial_migration_rollback",
        body: { p_attempt_id: request.attempt_id },
      };
  }
}

export function publicError(error) {
  if (error instanceof MigrationContractError) {
    return { status: error.status, code: error.code };
  }
  const message = String(error?.message ?? "");
  if (message.includes("authentication") || message.includes("owner")) {
    return { status: 403, code: "not_authorized" };
  }
  if (message.includes("security_gate")) {
    return { status: 403, code: "migration_not_enabled" };
  }
  if (message.includes("verification")) {
    return { status: 422, code: "migration_verification_failed" };
  }
  if (message.includes("oversized")) {
    return { status: 413, code: "migration_request_oversized" };
  }
  if (message.includes("invalid") || message.includes("count_exceeded")) {
    return { status: 400, code: "invalid_migration_request" };
  }
  if (message.includes("remote_not_empty") || message.includes("conflict")) {
    return { status: 409, code: "migration_conflict" };
  }
  if (message.includes("parent_missing") || message.includes("order") ||
      message.includes("already_completed")) {
    return { status: 409, code: "migration_order_invalid" };
  }
  return { status: 503, code: "migration_temporarily_unavailable" };
}
