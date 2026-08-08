import {
  MAX_REQUEST_BYTES,
  publicError,
  requireBearer,
  rpcFor,
  validateRequest,
  verifyPayloadIntegrity,
} from "./contract.mjs";

const JSON_HEADERS = { "content-type": "application/json" };

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return response(405, "method_not_allowed");
  }
  try {
    if (Deno.env.get("WAYTASK_INITIAL_MIGRATION_ENABLED") !== "true") {
      return response(403, "migration_not_enabled");
    }
    const projectURL = requiredEnvironment("SUPABASE_URL");
    const publishableKey = requiredEnvironment("SUPABASE_ANON_KEY");
    const authorization = requireBearer(request.headers.get("authorization"));

    // Auth is verified by the hosted Staging Auth authority. The returned user
    // object is deliberately not accepted as a caller-supplied migration owner;
    // every database RPC derives ownership again from auth.uid().
    const authResponse = await fetch(`${projectURL}/auth/v1/user`, {
      headers: { authorization, apikey: publishableKey },
    });
    if (!authResponse.ok) return response(401, "authentication_required");

    const contentLength = Number(request.headers.get("content-length") ?? "0");
    if (contentLength > MAX_REQUEST_BYTES) {
      return response(413, "request_oversized");
    }
    const requestBytes = new Uint8Array(await request.arrayBuffer());
    if (requestBytes.byteLength > MAX_REQUEST_BYTES) {
      return response(413, "request_oversized");
    }
    let requestValue;
    try {
      requestValue = JSON.parse(new TextDecoder().decode(requestBytes));
    } catch {
      return response(400, "invalid_request");
    }
    const body = validateRequest(requestValue);
    await verifyPayloadIntegrity(body);
    const rpc = rpcFor(body);
    const rpcResponse = await fetch(
      `${projectURL}/rest/v1/rpc/${rpc.name}`,
      {
        method: "POST",
        headers: {
          authorization,
          apikey: publishableKey,
          "content-type": "application/json",
        },
        body: JSON.stringify(rpc.body),
      },
    );
    if (!rpcResponse.ok) {
      const providerError = await rpcResponse.json().catch(() => ({}));
      const safe = publicError(providerError);
      return response(safe.status, safe.code);
    }
    const value = await rpcResponse.json().catch(() => ({}));
    return new Response(JSON.stringify(value), {
      status: 200,
      headers: JSON_HEADERS,
    });
  } catch (error) {
    const safe = publicError(error);
    return response(safe.status, safe.code);
  }
});

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error("server_configuration_unavailable");
  return value;
}

function response(status: number, code: string): Response {
  return new Response(JSON.stringify({ error: code }), {
    status,
    headers: JSON_HEADERS,
  });
}
