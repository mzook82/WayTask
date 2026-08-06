#!/usr/bin/env bash
set -euo pipefail

test_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
supabase_root="$(cd "${test_root}/.." && pwd)"
migration="${supabase_root}/migrations/20260806000100_wt032a_account_sync_foundation.sql"
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
psql --set ON_ERROR_STOP=on --dbname "${database_name}" --file "${migration}"
psql --set ON_ERROR_STOP=on --dbname "${database_name}" \
    --file "${test_root}/authorization.sql"
psql --set ON_ERROR_STOP=on --dbname "${database_name}" \
    --file "${test_root}/constraints.sql"

echo "WT-032A PostgreSQL policy suite completed."
