#!/usr/bin/env bash
set -euo pipefail

test_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
supabase_root="$(cd "${test_root}/.." && pwd)"
database_name="waytask_wt032a_test"

for command_name in createdb dropdb psql pg_dump; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Missing PostgreSQL command: ${command_name}" >&2
        exit 2
    fi
done

dropdb --if-exists "${database_name}"
createdb "${database_name}"

cleanup() {
    dropdb --if-exists "${database_name}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

psql --set ON_ERROR_STOP=on --dbname "${database_name}" \
    --file "${test_root}/bootstrap_bare_postgres.sql"
for migration in "${supabase_root}"/migrations/*.sql; do
    psql --set ON_ERROR_STOP=on --dbname "${database_name}" \
        --file "${migration}"
done
psql --set ON_ERROR_STOP=on --dbname "${database_name}" \
    --file "${test_root}/authorization.sql"
psql --set ON_ERROR_STOP=on --dbname "${database_name}" \
    --file "${test_root}/constraints.sql"
psql --set ON_ERROR_STOP=on --dbname "${database_name}" \
    --file "${test_root}/identity_inputs.sql"
psql --set ON_ERROR_STOP=on --dbname "${database_name}" \
    --file "${test_root}/ai_proxy_rate_limit.sql"

echo "WT-032A/WT-032B PostgreSQL policy suite completed."
