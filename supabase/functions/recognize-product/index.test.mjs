import assert from "node:assert/strict";
import test from "node:test";

const environment = {
  WAYTASK_ENVIRONMENT: "local",
  AI_RECOGNITION_ENABLED: "false",
  GEMINI_API_KEY: "server-test-key-value-123456",
  SUPABASE_URL: "http://127.0.0.1:54321",
  SUPABASE_ANON_KEY: "local-publishable-test-value",
  AI_RATE_LIMIT_HASH_SALT: "staging-test-salt-with-at-least-32-characters",
  AI_TRUSTED_IP_HEADER: "x-forwarded-for",
};

let handler;
globalThis.Deno = {
  env: { get: (name) => environment[name] },
  serve: (value) => { handler = value; },
};

await import("./index.ts");
assert.equal(typeof handler, "function");

const requestId = "123e4567-e89b-42d3-a456-426614174000";
const syntheticJPEG = Buffer.from([
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46,
  0x49, 0x46, 0x00, 0x01, 0xff, 0xd9,
]).toString("base64");

function validPayload() {
  return {
    schemaVersion: 1,
    requestId,
    image: { mimeType: "image/jpeg", imageBase64: syntheticJPEG },
    barcode: { value: "7290000000000", type: "ean13" },
  };
}

function makeRequest(body, { includeIP = true } = {}) {
  const headers = {
    Authorization: "Bearer signed-in-test-token-value",
    "Content-Type": "application/json",
  };
  if (includeIP) headers["X-Forwarded-For"] = "127.0.0.1";
  return new Request("http://127.0.0.1/functions/v1/recognize-product", {
    method: "POST",
    headers,
    body,
  });
}

function installFetch(mode, calls) {
  globalThis.fetch = async (input, init = {}) => {
    const url = input instanceof URL
      ? input
      : new URL(typeof input === "string" ? input : input.url);
    calls.push({ url, init });

    if (url.pathname === "/auth/v1/user") {
      return Response.json({ id: "11111111-1111-4111-8111-111111111111" });
    }
    if (url.pathname.endsWith("/consume_ai_recognition_quota")) {
      if (mode === "rate-limited") {
        return Response.json({
          allowed: false,
          duplicate_request: false,
          retry_after_seconds: 17,
        });
      }
      return Response.json({
        allowed: true,
        duplicate_request: false,
        retry_after_seconds: 0,
      });
    }
    if (url.hostname === "generativelanguage.googleapis.com") {
      if (mode === "oversized-provider") {
        return new Response(
          new Uint8Array((64 * 1_024) + 1),
          { status: 200 },
        );
      }
      return Response.json({
        candidates: [{
          content: {
            parts: [{
              text: JSON.stringify({
                productName: "Runtime Test Product",
                brand: "Test Brand",
                category: "Test Category",
                confidence: 0.9,
                searchKeywords: ["runtime", "test"],
              }),
            }],
          },
        }],
      });
    }
    throw new Error(`Unexpected fetch destination: ${url.origin}${url.pathname}`);
  };
}

test("Edge runtime fails closed and enforces the complete secure boundary", async () => {
  const originalFetch = globalThis.fetch;
  const originalLog = console.log;
  const logs = [];
  console.log = (value) => logs.push(value);

  try {
    let calls = [];
    installFetch("success", calls);
    environment.AI_RECOGNITION_ENABLED = "false";
    let response = await handler(makeRequest(JSON.stringify(validPayload())));
    assert.equal(response.status, 503);
    assert.equal(calls.length, 0);
    assert.equal((await response.json()).error.code, "not_configured");

    environment.AI_RECOGNITION_ENABLED = "true";
    calls = [];
    installFetch("success", calls);
    const withForbiddenControl = validPayload();
    withForbiddenControl.model = "client-selected-model";
    response = await handler(makeRequest(JSON.stringify(withForbiddenControl)));
    assert.equal(response.status, 400);
    assert.equal(calls.length, 1, "only Auth may run before schema rejection");

    calls = [];
    installFetch("success", calls);
    response = await handler(makeRequest("x".repeat(2_850_001)));
    assert.equal(response.status, 413);
    assert.equal(calls.length, 1, "oversized bodies stop before quota/provider");

    calls = [];
    installFetch("success", calls);
    response = await handler(makeRequest(
      JSON.stringify(validPayload()),
      { includeIP: false },
    ));
    assert.equal(response.status, 503);
    assert.equal(calls.length, 1, "missing trusted IP data fails before quota");

    calls = [];
    installFetch("rate-limited", calls);
    response = await handler(makeRequest(JSON.stringify(validPayload())));
    assert.equal(response.status, 429);
    assert.equal(response.headers.get("Retry-After"), "17");
    assert.equal(calls.length, 2, "rate limits stop before the provider");

    calls = [];
    installFetch("oversized-provider", calls);
    response = await handler(makeRequest(JSON.stringify(validPayload())));
    assert.equal(response.status, 502);
    assert.equal((await response.json()).error.code, "invalid_result");

    calls = [];
    installFetch("success", calls);
    response = await handler(makeRequest(JSON.stringify(validPayload())));
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.status, "recognized");
    assert.equal(body.product.productName, "Runtime Test Product");

    const providerCall = calls.at(-1);
    assert.equal(providerCall.url.hostname, "generativelanguage.googleapis.com");
    assert.equal(
      providerCall.url.pathname,
      "/v1beta/models/gemini-2.5-flash:generateContent",
    );
    assert.equal(providerCall.url.search, "");
    assert.equal(
      providerCall.init.headers["x-goog-api-key"],
      environment.GEMINI_API_KEY,
    );
    const providerBody = JSON.parse(providerCall.init.body);
    assert.equal(providerBody.model, undefined);
    assert.equal(providerBody.endpoint, undefined);

    const logObjects = logs.map((value) => JSON.parse(value));
    assert.ok(logObjects.length >= 2);
    for (const entry of logObjects) {
      assert.deepEqual(
        Object.keys(entry).sort(),
        ["durationMs", "event", "outcome", "providerResponseBytes"],
      );
    }
  } finally {
    environment.AI_RECOGNITION_ENABLED = "false";
    globalThis.fetch = originalFetch;
    console.log = originalLog;
  }
});
