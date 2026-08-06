#!/usr/bin/env bash
set -euo pipefail

test_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
supabase_root="$(cd "${test_root}/.." && pwd)"
first_database="waytask_wt032a_rebuild_a"
second_database="waytask_wt032a_rebuild_b"
first_dump="$(mktemp /tmp/waytask-wt032a-a.XXXXXX)"
second_dump="$(mktemp /tmp/waytask-wt032a-b.XXXXXX)"

cleanup() {
    dropdb --if-exists "${first_database}" >/dev/null 2>&1 || true
    dropdb --if-exists "${second_database}" >/dev/null 2>&1 || true
    rm -f "${first_dump}" "${second_dump}"
}
trap cleanup EXIT

for database_name in "${first_database}" "${second_database}"; do
    dropdb --if-exists "${database_name}"
    createdb "${database_name}"
    psql --set ON_ERROR_STOP=on --dbname "${database_name}" \
        --file "${test_root}/bootstrap_bare_postgres.sql" >/dev/null
    for migration in "${supabase_root}"/migrations/*.sql; do
        psql --set ON_ERROR_STOP=on --dbname "${database_name}" \
            --file "${migration}" >/dev/null
    done
done

pg_dump --schema-only --no-owner --no-privileges "${first_database}" \
    | sed -E '/^\\(un)?restrict /d' \
    | sed "s/${first_database}/${second_database}/g" > "${first_dump}"
pg_dump --schema-only --no-owner --no-privileges "${second_database}" \
    | sed -E '/^\\(un)?restrict /d' > "${second_dump}"

diff -u "${first_dump}" "${second_dump}"
echo "WT-032A clean rebuilds are schema-identical."
