# RLS Policy Matrix

All ten `public` Data API tables use `ENABLE ROW LEVEL SECURITY` and
`FORCE ROW LEVEL SECURITY`. Client table privileges are deliberately granted so
the test suite proves RLS, not an accidental missing grant. `service_role`
bypasses RLS only in trusted server infrastructure and is never an iOS value.

Legend: **owner** requires `auth.uid() = owner_user_id`; **deny** is an explicit
false policy; **admin** is a trusted server role outside the client.

| Table | Operation | anon/guest | authenticated owner | authenticated non-owner | admin/server |
|---|---|---|---|---|---|
| profiles | SELECT | deny | owner | deny | allow |
| profiles | INSERT | deny | owner and `id = auth.uid()` | deny | allow |
| profiles | UPDATE | deny | existing owner and new owner/id still caller | deny | allow |
| profiles | DELETE | deny | deny; deletion orchestrated | deny | allow |
| user_preferences | SELECT | deny | owner | deny | allow |
| user_preferences | INSERT | deny | owner | deny | allow |
| user_preferences | UPDATE | deny | existing/new owner | deny | allow |
| user_preferences | DELETE | deny | deny; tombstone | deny | allow |
| shopping_lists | SELECT | deny | owner, including own tombstones | deny | allow |
| shopping_lists | INSERT | deny | owner | deny | allow |
| shopping_lists | UPDATE | deny | existing/new owner; trigger locks owner | deny | allow |
| shopping_lists | DELETE | deny | deny; tombstone | deny | allow |
| personal_products | SELECT | deny | owner, including own tombstones | deny | allow |
| personal_products | INSERT | deny | owner | deny | allow |
| personal_products | UPDATE | deny | existing/new owner; trigger locks owner | deny | allow |
| personal_products | DELETE | deny | deny; tombstone | deny | allow |
| shopping_list_entries | SELECT | deny | owner and owner-owned parent list | deny | allow |
| shopping_list_entries | INSERT | deny | owner plus owner-owned list and product | deny | allow |
| shopping_list_entries | UPDATE | deny | old row/parent owned and new row/list/product owned | deny | allow |
| shopping_list_entries | DELETE | deny | deny; tombstone | deny | allow |
| saved_stores | SELECT | deny | owner | deny | allow |
| saved_stores | INSERT | deny | owner | deny | allow |
| saved_stores | UPDATE | deny | existing/new owner | deny | allow |
| saved_stores | DELETE | deny | deny; tombstone | deny | allow |
| notification_preferences | SELECT | deny | owner | deny | allow |
| notification_preferences | INSERT | deny | owner | deny | allow |
| notification_preferences | UPDATE | deny | existing/new owner | deny | allow |
| notification_preferences | DELETE | deny | deny; tombstone | deny | allow |
| device_installations | SELECT | deny | owner | deny | allow |
| device_installations | INSERT | deny | owner | deny | allow |
| device_installations | UPDATE | deny | existing/new owner | deny | allow |
| device_installations | DELETE | deny | deny; revoke/tombstone | deny | allow |
| sync_mutations | SELECT | deny | owner | deny | allow |
| sync_mutations | INSERT | deny | owner, active owner device, `accepted`, no result fields | deny | allow |
| sync_mutations | UPDATE | deny | deny; receipt immutable | deny | allow |
| sync_mutations | DELETE | deny | deny | deny | allow |
| catalog_releases | SELECT | published and not withdrawn | same | same | allow |
| catalog_releases | INSERT | deny | deny | deny | allow |
| catalog_releases | UPDATE | deny | deny | deny | allow |
| catalog_releases | DELETE | deny | deny | deny | allow |

`waytask_admin.migration_audit` is outside the exposed schema, its schema usage
and table privileges are revoked from `anon` and `authenticated`, and it is not
an RLS-backed client table.

Tombstone policy: an owner can read their own deleted rows so every device can
converge; non-owners and anonymous callers cannot see them. Future retention
compaction is trusted-server work only.

The executable matrix is `supabase/tests/authorization.sql`: 50 assertions run
as anonymous, User A, User B, and trusted server. The suite also fails unless
all ten tables have RLS, FORCE RLS, and four-operation policy coverage.
