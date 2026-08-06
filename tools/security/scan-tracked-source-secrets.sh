#!/usr/bin/env bash
set -euo pipefail

repository_root="$(git rev-parse --show-toplevel)"
cd "${repository_root}"

failures=0
encoded_service_role='c2VydmljZV9y''b2xl'
while IFS= read -r -d '' file; do
    [[ -f "${file}" ]] || continue
    base_name="$(basename "${file}")"
    lower_name="$(printf '%s' "${base_name}" | tr '[:upper:]' '[:lower:]')"
    case "${lower_name}" in
        secrets.plist|secret.plist|.env|*service-account*.json|*.p8|*.p12|*.pem)
            echo "FORBIDDEN_TRACKED_SECRET_FILE: ${file}" >&2
            failures=$((failures + 1))
            ;;
    esac

    if LC_ALL=C grep -aEql \
        '(AIza[0-9A-Za-z_-]{30,}|AQ\.[0-9A-Za-z_-]{35,}|sb_secret_[0-9A-Za-z_-]{20,}|sntrys_[0-9A-Za-z_-]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)' \
        "${file}"; then
        echo "FORBIDDEN_TRACKED_PRIVILEGED_CREDENTIAL: ${file}" >&2
        failures=$((failures + 1))
    fi
    if LC_ALL=C grep -aFql "${encoded_service_role}" "${file}"; then
        echo "FORBIDDEN_TRACKED_ENCODED_SERVICE_ROLE: ${file}" >&2
        failures=$((failures + 1))
    fi
done < <(git ls-files --cached --others --exclude-standard -z)

if [[ ${failures} -ne 0 ]]; then
    echo "Repository source security scan failed with ${failures} finding(s)." >&2
    exit 1
fi

echo "Repository source security scan passed: no privileged credential values or non-ignored secret files."
