#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 /path/to/WayTask.app" >&2
    exit 2
fi

bundle="$1"
if [[ ! -d "${bundle}" ]]; then
    echo "Built app bundle not found: ${bundle}" >&2
    exit 2
fi

failures=0
encoded_service_role='c2VydmljZV9y''b2xl'

while IFS= read -r -d '' file; do
    relative="${file#"${bundle}"/}"
    base_name="$(basename "${file}")"
    lower_name="$(printf '%s' "${base_name}" | tr '[:upper:]' '[:lower:]')"
    case "${lower_name}" in
        secrets.plist|secret.plist|.env|.env.*|*service-account*.json|*.p8|*.p12|*.pem)
            echo "FORBIDDEN_BUNDLED_SECRET_FILE: ${relative}" >&2
            failures=$((failures + 1))
            ;;
    esac

    if LC_ALL=C grep -aEql \
        '(AIza[0-9A-Za-z_-]{30,}|AQ\.[0-9A-Za-z_-]{35,}|sb_secret_[0-9A-Za-z_-]{20,}|sntrys_[0-9A-Za-z_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)' \
        "${file}"; then
        echo "FORBIDDEN_PRIVILEGED_CREDENTIAL_VALUE: ${relative}" >&2
        failures=$((failures + 1))
    fi
    if LC_ALL=C grep -aFql "${encoded_service_role}" "${file}"; then
        echo "FORBIDDEN_ENCODED_SERVICE_ROLE_VALUE: ${relative}" >&2
        failures=$((failures + 1))
    fi

    if LC_ALL=C grep -aEql \
        '(GEMINI_API_KEY|SENTRY_AUTH_TOKEN|SUPABASE_SERVICE_ROLE|generativelanguage\.googleapis\.com)' \
        "${file}"; then
        echo "FORBIDDEN_CLIENT_CREDENTIAL_OR_DIRECT_ENDPOINT_MARKER: ${relative}" >&2
        failures=$((failures + 1))
    fi
done < <(find "${bundle}" -type f -print0)

# During key-removal incidents, point this optional variable at the ignored
# developer plist. Its value is compared byte-for-byte but is never printed.
if [[ -n "${WAYTASK_FORBIDDEN_SECRET_PLIST:-}" && \
      -f "${WAYTASK_FORBIDDEN_SECRET_PLIST}" ]]; then
    forbidden_value="$(plutil -extract GEMINI_API_KEY raw -o - \
        "${WAYTASK_FORBIDDEN_SECRET_PLIST}" 2>/dev/null || true)"
    if [[ -n "${forbidden_value}" ]]; then
        while IFS= read -r -d '' file; do
            if LC_ALL=C grep -aFql -- "${forbidden_value}" "${file}"; then
                relative="${file#"${bundle}"/}"
                echo "FORBIDDEN_EXACT_ROTATION_VALUE: ${relative}" >&2
                failures=$((failures + 1))
            fi
        done < <(find "${bundle}" -type f -print0)
    fi
fi

if [[ ${failures} -ne 0 ]]; then
    echo "Built-app security scan failed with ${failures} finding(s)." >&2
    exit 1
fi

echo "Built-app security scan passed: no bundled secret file, privileged credential, or direct Gemini endpoint."
