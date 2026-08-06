import {
  jsonError,
  normalizeGeminiResponse,
  recognitionContract,
  validateRecognitionRequest,
} from "./contract.mjs";

const geminiEndpoint =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";
const jsonHeaders = Object.freeze({
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
});

Deno.serve(async (request: Request): Promise<Response> => {
  const startedAt = Date.now();
  if (request.method !== "POST") {
    return errorResponse(405, "method_not_allowed");
  }

  const environment = Deno.env.get("WAYTASK_ENVIRONMENT") ?? "";
  const enabled = Deno.env.get("AI_RECOGNITION_ENABLED") === "true";
  const geminiKey = Deno.env.get("GEMINI_API_KEY") ?? "";
  const supabaseURL = Deno.env.get("SUPABASE_URL") ?? "";
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const rateLimitSalt = Deno.env.get("AI_RATE_LIMIT_HASH_SALT") ?? "";
  const trustedIPHeader = Deno.env.get("AI_TRUSTED_IP_HEADER") ?? "";
  if (
    !enabled ||
    !["local", "development", "staging"].includes(environment) ||
    geminiKey.length < 16 ||
    publishableKey.length < 16 ||
    rateLimitSalt.length < 32 ||
    !["cf-connecting-ip", "x-real-ip", "x-forwarded-for"].includes(
      trustedIPHeader,
    ) ||
    !isAllowedSupabaseURL(supabaseURL, environment)
  ) {
    return errorResponse(503, "not_configured");
  }

  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (declaredLength > recognitionContract.maximumRequestBytes) {
    return errorResponse(413, "payload_too_large");
  }

  const authorization = request.headers.get("authorization") ?? "";
  if (!/^Bearer [^\s]{16,8192}$/.test(authorization)) {
    return errorResponse(401, "authentication_required");
  }
  if (!await hasVerifiedUser(supabaseURL, publishableKey, authorization)) {
    return errorResponse(401, "authentication_required");
  }

  let bodyText: string;
  try {
    const requestBytes = await readBoundedBytes(
      request.body,
      recognitionContract.maximumRequestBytes,
    );
    if (requestBytes === null) {
      return errorResponse(413, "payload_too_large");
    }
    bodyText = new TextDecoder("utf-8", { fatal: true }).decode(requestBytes);
  } catch {
    return errorResponse(400, "invalid_request");
  }

  let untrustedBody: unknown;
  try {
    untrustedBody = JSON.parse(bodyText);
  } catch {
    return errorResponse(400, "invalid_request");
  }
  const validated = validateRecognitionRequest(untrustedBody);
  if (!validated.ok) {
    const status = validated.error === "payload_too_large"
      ? 413
      : validated.error === "unsupported_image"
      ? 415
      : 400;
    return errorResponse(status, validated.error);
  }

  const ipHash = await privacySafeIPHash(
    request,
    rateLimitSalt,
    trustedIPHeader,
  );
  if (ipHash === null) return errorResponse(503, "service_unavailable");
  const quota = await consumeQuota(
    supabaseURL,
    publishableKey,
    authorization,
    validated.value.requestId,
    ipHash,
  );
  if (!quota.ok) return errorResponse(503, "service_unavailable");
  if (quota.duplicate) return errorResponse(409, "duplicate_request");
  if (!quota.allowed) {
    return errorResponse(
      429,
      "rate_limited",
      Math.max(1, quota.retryAfterSeconds),
    );
  }

  const barcodeContext = validated.value.barcode
    ? `A GS1-style barcode was scanned: ${validated.value.barcode.value} (${validated.value.barcode.type}).`
    : "No supported retail barcode was supplied.";
  const providerRequest = {
    contents: [{
      parts: [
        { text: productRecognitionPrompt(barcodeContext) },
        {
          inline_data: {
            mime_type: validated.value.image.mimeType,
            data: validated.value.image.imageBase64,
          },
        },
      ],
    }],
    generation_config: { response_mime_type: "application/json" },
  };

  let providerResponse: Response;
  try {
    providerResponse = await fetch(geminiEndpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "x-goog-api-key": geminiKey,
      },
      body: JSON.stringify(providerRequest),
      signal: AbortSignal.timeout(15_000),
    });
  } catch (error) {
    const code = error instanceof DOMException && error.name === "TimeoutError"
      ? "timeout"
      : "service_unavailable";
    privacySafeLog(code, startedAt, 0);
    return errorResponse(code === "timeout" ? 504 : 503, code);
  }
  if (!providerResponse.ok) {
    privacySafeLog("provider_rejected", startedAt, 0);
    return errorResponse(503, "service_unavailable");
  }

  const providerBytes = await readBoundedBytes(
    providerResponse.body,
    recognitionContract.maximumProviderResponseBytes,
  );
  if (providerBytes === null) {
    privacySafeLog("provider_response_too_large", startedAt, 0);
    return errorResponse(502, "invalid_result");
  }
  let providerJSON: unknown;
  try {
    providerJSON = JSON.parse(new TextDecoder().decode(providerBytes));
  } catch {
    return errorResponse(502, "invalid_result");
  }
  const normalized = normalizeGeminiResponse(
    providerJSON,
    validated.value.requestId,
  );
  if (!normalized.ok) {
    privacySafeLog(normalized.error, startedAt, providerBytes.byteLength);
    return errorResponse(422, normalized.error);
  }

  const responseBody = JSON.stringify(normalized.value);
  if (new TextEncoder().encode(responseBody).byteLength > 32_768) {
    return errorResponse(502, "invalid_result");
  }
  privacySafeLog(normalized.value.status, startedAt, providerBytes.byteLength);
  return new Response(responseBody, { status: 200, headers: jsonHeaders });
});

async function hasVerifiedUser(
  supabaseURL: string,
  publishableKey: string,
  authorization: string,
): Promise<boolean> {
  try {
    const response = await fetch(new URL("/auth/v1/user", supabaseURL), {
      headers: { apikey: publishableKey, Authorization: authorization },
      signal: AbortSignal.timeout(5_000),
    });
    if (!response.ok) return false;
    const body = await response.json();
    return typeof body?.id === "string" &&
      /^[0-9a-f-]{36}$/i.test(body.id);
  } catch {
    return false;
  }
}

async function consumeQuota(
  supabaseURL: string,
  publishableKey: string,
  authorization: string,
  requestId: string,
  ipHash: string,
): Promise<{
  ok: boolean;
  allowed: boolean;
  duplicate: boolean;
  retryAfterSeconds: number;
}> {
  try {
    const response = await fetch(
      new URL("/rest/v1/rpc/consume_ai_recognition_quota", supabaseURL),
      {
        method: "POST",
        headers: {
          apikey: publishableKey,
          Authorization: authorization,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        body: JSON.stringify({
          p_request_id: requestId,
          p_ip_hash: ipHash,
        }),
        signal: AbortSignal.timeout(3_000),
      },
    );
    if (!response.ok) return {
      ok: false,
      allowed: false,
      duplicate: false,
      retryAfterSeconds: 0,
    };
    const rows = await response.json();
    const row = Array.isArray(rows) ? rows[0] : rows;
    return {
      ok: typeof row?.allowed === "boolean",
      allowed: row?.allowed === true,
      duplicate: row?.duplicate_request === true,
      retryAfterSeconds: Number(row?.retry_after_seconds ?? 0),
    };
  } catch {
    return {
      ok: false,
      allowed: false,
      duplicate: false,
      retryAfterSeconds: 0,
    };
  }
}

async function privacySafeIPHash(
  request: Request,
  salt: string,
  trustedHeader: string,
): Promise<string | null> {
  const source = request.headers.get(trustedHeader)?.split(",")[0]?.trim() ?? "";
  if (!/^[0-9a-fA-F:.]{3,64}$/.test(source)) return null;
  const bytes = new TextEncoder().encode(`${salt}:${source}`);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return Array.from(digest).map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function isAllowedSupabaseURL(value: string, environment: string): boolean {
  try {
    const url = new URL(value);
    if (url.username || url.password || url.search || url.hash) return false;
    if (environment === "local") {
      return ["http:", "https:"].includes(url.protocol) &&
        ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname);
    }
    return url.protocol === "https:";
  } catch {
    return false;
  }
}

function productRecognitionPrompt(barcodeContext: string): string {
  return `You are a retail package recognition service. ${barcodeContext}
Use only the visible front-package image and supplied retail barcode. Do not
infer user identity, location, intent, inventory, price, or private data. Avoid
guessing. Return JSON only with productName, brand, category, productType,
flavor, packageSize, packageType, visibleText, confidence from 0 to 1,
description, and 3 to 8 searchKeywords. Use an empty string for a field that is
not visible. If the image is unclear, contains multiple products, or has no
identifiable retail package, leave productName empty and explain only the image
quality issue in description.`;
}

function errorResponse(
  status: number,
  code: string,
  retryAfterSeconds?: number,
): Response {
  const headers: Record<string, string> = { ...jsonHeaders };
  if (retryAfterSeconds !== undefined) {
    headers["Retry-After"] = String(retryAfterSeconds);
  }
  return new Response(jsonError(code), { status, headers });
}

function privacySafeLog(
  outcome: string,
  startedAt: number,
  providerResponseBytes: number,
): void {
  console.log(JSON.stringify({
    event: "secure_ai_recognition",
    outcome,
    durationMs: Date.now() - startedAt,
    providerResponseBytes,
  }));
}

async function readBoundedBytes(
  stream: ReadableStream<Uint8Array> | null,
  maximumBytes: number,
): Promise<Uint8Array | null> {
  if (stream === null) return new Uint8Array();

  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maximumBytes) {
        await reader.cancel("payload_too_large");
        return null;
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const output = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return output;
}
