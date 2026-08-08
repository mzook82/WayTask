#!/usr/bin/env bash
set -euo pipefail

# WT-032B hosted Staging Data API gate. The client-safe publishable key remains
# in process memory and is never printed or persisted. Never run against
# Production; the linked project name is checked before any request.

for command_name in supabase curl jq; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Missing required command: ${command_name}" >&2
        exit 2
    fi
done

project_ref_file="supabase/.temp/project-ref"
if [[ ! -f "${project_ref_file}" ]]; then
    echo "No linked Supabase project." >&2
    exit 2
fi
project_ref="$(tr -d '\r\n' < "${project_ref_file}")"

projects_json="$(SUPABASE_TELEMETRY_DISABLED=true \
    supabase projects list --output json 2>/dev/null)"
project_name="$(printf '%s' "${projects_json}" | jq -r \
    --arg ref "${project_ref}" \
    '(if type == "object" and has("projects") then .projects else . end)[] |
     select((.ref // .id) == $ref) | .name')"
if [[ "${project_name}" != "WayTask Staging" ]]; then
    echo "Refusing Data API validation: linked project is not WayTask Staging." >&2
    exit 2
fi
unset projects_json project_name

keys_json="$(SUPABASE_TELEMETRY_DISABLED=true \
    supabase projects api-keys --project-ref "${project_ref}" \
    --output json 2>/dev/null)"
publishable_key="$(printf '%s' "${keys_json}" | jq -er \
    '[.[] | select(.type == "publishable") | .api_key] |
     if length == 1 then .[0] else error("expected one publishable key") end')"
unset keys_json

base_url="https://${project_ref}.supabase.co/rest/v1"
auth_url="https://${project_ref}.supabase.co/auth/v1"
passed=0

record_pass() {
    passed=$((passed + 1))
    printf 'PASS %02d %s\n' "${passed}" "$1"
}

split_response() {
    response_body="${1%$'\n__WAYTASK_STATUS__'*}"
    response_status="${1##*$'\n__WAYTASK_STATUS__'}"
}

assert_empty_array() {
    local label="$1"
    shift
    local response
    response="$(curl -sS -w $'\n__WAYTASK_STATUS__%{http_code}' "$@")"
    split_response "${response}"
    if [[ "${response_status}" != "200" ]] ||
        ! printf '%s' "${response_body}" |
            jq -e 'type == "array" and length == 0' >/dev/null; then
        echo "FAIL ${label}: expected HTTP 200 empty array, got ${response_status}" >&2
        exit 1
    fi
    unset response response_body response_status
    record_pass "${label}"
}

assert_status() {
    local label="$1"
    local expected="$2"
    shift 2
    local status
    status="$(curl -sS -o /dev/null -w '%{http_code}' "$@")"
    if [[ ! ",${expected}," =~ ,${status}, ]]; then
        echo "FAIL ${label}: expected ${expected}, got ${status}" >&2
        exit 1
    fi
    record_pass "${label}"
}

assert_json_array() {
    local label="$1"
    shift
    local response
    response="$(curl -sS -w $'\n__WAYTASK_STATUS__%{http_code}' "$@")"
    split_response "${response}"
    if [[ "${response_status}" != "200" ]] ||
        ! printf '%s' "${response_body}" |
            jq -e 'type == "array"' >/dev/null; then
        echo "FAIL ${label}: expected HTTP 200 JSON array, got ${response_status}" >&2
        exit 1
    fi
    unset response response_body response_status
    record_pass "${label}"
}

assert_oidc_discovery() {
    local label="$1"
    local response
    response="$(curl -sS -w $'\n__WAYTASK_STATUS__%{http_code}' \
        -H "apikey: ${publishable_key}" \
        "${auth_url}/.well-known/openid-configuration")"
    split_response "${response}"
    if [[ "${response_status}" != "200" ]] ||
        ! printf '%s' "${response_body}" | jq -e \
            --arg issuer "${auth_url}" \
            --arg jwks_uri "${auth_url}/.well-known/jwks.json" \
            'type == "object" and .issuer == $issuer and
             .jwks_uri == $jwks_uri' >/dev/null; then
        echo "FAIL ${label}: hosted discovery contract did not match linked Staging" >&2
        exit 1
    fi
    unset response response_body response_status
    record_pass "${label}"
}

assert_jwks() {
    local label="$1"
    local response
    response="$(curl -sS -w $'\n__WAYTASK_STATUS__%{http_code}' \
        -H "apikey: ${publishable_key}" \
        "${auth_url}/.well-known/jwks.json")"
    split_response "${response}"
    if [[ "${response_status}" != "200" ]] ||
        ! printf '%s' "${response_body}" |
            jq -e 'type == "object" and (.keys | type == "array") and
                   (.keys | length > 0)' >/dev/null; then
        echo "FAIL ${label}: hosted JWKS is unavailable or empty" >&2
        exit 1
    fi
    unset response response_body response_status
    record_pass "${label}"
}

assert_status \
    "gateway rejects a request without an API key" \
    "401" \
    "${base_url}/profiles?select=id&limit=1"

assert_empty_array \
    "anonymous role cannot list private profiles" \
    -H "apikey: ${publishable_key}" \
    "${base_url}/profiles?select=id&limit=1"

assert_empty_array \
    "anonymous exact-UUID profile guess returns no row" \
    -H "apikey: ${publishable_key}" \
    "${base_url}/profiles?id=eq.eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa&select=id"

assert_empty_array \
    "anonymous broad OR filter cannot bypass profile RLS" \
    -G -H "apikey: ${publishable_key}" \
    --data-urlencode \
    "or=(owner_user_id.neq.00000000-0000-0000-0000-000000000000,id.not.is.null)" \
    --data-urlencode "select=id" \
    "${base_url}/profiles"

assert_status \
    "anonymous profile insert is denied" \
    "401,403" \
    -X POST \
    -H "apikey: ${publishable_key}" \
    -H "Content-Type: application/json" \
    --data-binary \
    '{"id":"eddddddd-dddd-4ddd-8ddd-dddddddddddd","owner_user_id":"eddddddd-dddd-4ddd-8ddd-dddddddddddd","display_name":"forged"}' \
    "${base_url}/profiles"

assert_empty_array \
    "anonymous exact-UUID profile update affects no row" \
    -X PATCH \
    -H "apikey: ${publishable_key}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    --data-binary '{"display_name":"forged"}' \
    "${base_url}/profiles?id=eq.eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa&select=id"

assert_empty_array \
    "anonymous exact-UUID profile delete affects no row" \
    -X DELETE \
    -H "apikey: ${publishable_key}" \
    -H "Prefer: return=representation" \
    "${base_url}/profiles?id=eq.eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa&select=id"

assert_json_array \
    "published catalog metadata endpoint is exposed read-only" \
    -H "apikey: ${publishable_key}" \
    "${base_url}/catalog_releases?select=id,release_name&limit=1"

assert_status \
    "private schema is not exposed through Data API" \
    "404,406" \
    -H "apikey: ${publishable_key}" \
    -H "Accept-Profile: waytask_private" \
    "${base_url}/profiles?select=id&limit=1"

assert_status \
    "administrative schema is not exposed through Data API" \
    "404,406" \
    -H "apikey: ${publishable_key}" \
    -H "Accept-Profile: waytask_admin" \
    "${base_url}/migration_audit?select=id&limit=1"

assert_status \
    "malformed bearer JWT is rejected by hosted gateway" \
    "401" \
    -H "apikey: ${publishable_key}" \
    -H "Authorization: Bearer malformed.jwt.value" \
    "${base_url}/profiles?select=id&limit=1"

assert_status \
    "private normalization RPC is absent from public API" \
    "404" \
    -X POST \
    -H "apikey: ${publishable_key}" \
    -H "Content-Type: application/json" \
    --data-binary '{"value":"test"}' \
    "${base_url}/rpc/normalize_profile_display_name"

assert_oidc_discovery \
    "hosted Auth issuer and JWKS URI match linked Staging"

assert_jwks \
    "hosted Auth publishes a non-empty verification key set"

assert_status \
    "hosted Auth user endpoint rejects a missing session" \
    "401" \
    -H "apikey: ${publishable_key}" \
    "${auth_url}/user"

unset publishable_key project_ref base_url auth_url
printf 'WT-032B hosted Staging Data API validation passed: %d assertions.\n' \
    "${passed}"
