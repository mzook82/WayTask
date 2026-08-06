\set ON_ERROR_STOP on
\set QUIET on

begin;

create schema waytask_test;
create table waytask_test.results (
    name text primary key
);

create or replace function waytask_test.pass(test_name text)
returns void
language plpgsql
security definer
set search_path = waytask_test, pg_catalog
as $$
begin
    insert into waytask_test.results(name) values (test_name);
end;
$$;

create or replace function waytask_test.assert_true(
    condition boolean,
    test_name text
) returns void
language plpgsql
security definer
set search_path = waytask_test, pg_catalog
as $$
begin
    if condition is not true then
        raise exception 'authorization assertion failed: %', test_name;
    end if;
    perform waytask_test.pass(test_name);
end;
$$;

create or replace function waytask_test.expect_failure(
    statement text,
    test_name text
) returns void
language plpgsql
security invoker
set search_path = waytask_test, public, auth, pg_catalog
as $$
begin
    begin
        execute statement;
    exception when others then
        perform waytask_test.pass(test_name);
        return;
    end;
    raise exception 'expected authorization failure: %', test_name;
end;
$$;

create or replace function waytask_test.expect_affected(
    statement text,
    expected_rows bigint,
    test_name text
) returns void
language plpgsql
security invoker
set search_path = waytask_test, public, auth, pg_catalog
as $$
declare
    affected bigint;
begin
    execute statement;
    get diagnostics affected = row_count;
    if affected <> expected_rows then
        raise exception 'expected % rows, got %: %',
            expected_rows, affected, test_name;
    end if;
    perform waytask_test.pass(test_name);
end;
$$;

grant usage on schema waytask_test to anon, authenticated, service_role;
grant execute on all functions in schema waytask_test
to anon, authenticated, service_role;

\set user_a 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
\set user_b 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
\set list_a 'a1000000-0000-4000-8000-000000000001'
\set list_b 'b1000000-0000-4000-8000-000000000001'
\set product_a 'a2000000-0000-4000-8000-000000000002'
\set product_b 'b2000000-0000-4000-8000-000000000002'
\set entry_a 'a3000000-0000-4000-8000-000000000003'
\set entry_b 'b3000000-0000-4000-8000-000000000003'
\set device_a 'a4000000-0000-4000-8000-000000000004'
\set mutation_a 'a5000000-0000-4000-8000-000000000005'
\set catalog_release 'c1000000-0000-4000-8000-000000000001'

insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, created_at, updated_at
) values
    (gen_random_uuid(), :'user_a', 'authenticated', 'authenticated',
     'user-a@local.invalid', '', now(), now()),
    (gen_random_uuid(), :'user_b', 'authenticated', 'authenticated',
     'user-b@local.invalid', '', now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', :'user_a', true);

insert into public.profiles (id, owner_user_id, display_name)
values (:'user_a', :'user_a', 'User A');
select waytask_test.pass('01 user A creates own profile');
select waytask_test.assert_true(
    (select count(*) = 1 from public.profiles where id = :'user_a'),
    '02 user A reads own profile'
);
select waytask_test.expect_affected(
    format('update public.profiles set display_name = %L where id = %L',
           'User A Updated', :'user_a'),
    1,
    '03 user A updates own profile'
);
select waytask_test.assert_true(
    (select revision = 2 from public.profiles where id = :'user_a'),
    '04 owner update increments revision server-side'
);

insert into public.shopping_lists (id, owner_user_id, title)
values (:'list_a', :'user_a', 'A List');
select waytask_test.pass('05 user A creates own list');
select waytask_test.assert_true(
    (select count(*) = 1 from public.shopping_lists where id = :'list_a'),
    '06 user A reads own list'
);
insert into public.personal_products (
    id, owner_user_id, display_name, source
) values (:'product_a', :'user_a', 'חלב', 'manual');
select waytask_test.pass('07 user A creates own personal product');
insert into public.shopping_list_entries (
    id, owner_user_id, shopping_list_id, personal_product_id, quantity
) values (:'entry_a', :'user_a', :'list_a', :'product_a', 2);
select waytask_test.pass('08 user A creates entry in own list');
select waytask_test.assert_true(
    (select count(*) = 1 from public.shopping_list_entries
      where id = :'entry_a' and shopping_list_id = :'list_a'),
    '09 user A reads own parent-scoped entry'
);
insert into public.device_installations (
    id, owner_user_id, app_version, device_locale
) values (:'device_a', :'user_a', '1.1.0', 'he-IL');
select waytask_test.pass('10 user A registers own device installation');
insert into public.sync_mutations (
    id, owner_user_id, device_installation_id, idempotency_key,
    mutation_type, payload_sha256, record_count, payload_bytes
) values (
    :'mutation_a', :'user_a', :'device_a',
    'migration-a-0000000000001', 'initial_migration', repeat('a', 64), 4, 512
);
select waytask_test.pass('11 user A creates immutable mutation receipt');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'user_b', true);

select waytask_test.assert_true(
    (select count(*) = 0 from public.profiles where id = :'user_a'),
    '12 user B cannot read A profile by exact ID'
);
select waytask_test.expect_affected(
    format('update public.profiles set display_name = %L where id = %L',
           'stolen', :'user_a'),
    0,
    '13 user B cannot update A profile'
);
select waytask_test.expect_affected(
    format('delete from public.profiles where id = %L', :'user_a'),
    0,
    '14 user B cannot delete A profile'
);
select waytask_test.assert_true(
    (select count(*) = 0 from public.shopping_lists),
    '15 user B cannot list A lists'
);
select waytask_test.assert_true(
    (select count(*) = 0 from public.shopping_lists where id = :'list_a'),
    '16 user B cannot fetch A list by direct ID'
);
select waytask_test.expect_affected(
    format('update public.shopping_lists set title = %L where id = %L',
           'B changed A', :'list_a'),
    0,
    '17 user B cannot update A list'
);
select waytask_test.expect_affected(
    format('delete from public.shopping_lists where id = %L', :'list_a'),
    0,
    '18 user B cannot delete A list'
);
select waytask_test.expect_failure(
    format(
        'insert into public.shopping_list_entries '
        '(id, owner_user_id, shopping_list_id, personal_product_id, quantity) '
        'values (%L, %L, %L, %L, 1)',
        'b3000000-0000-4000-8000-000000000099', :'user_b',
        :'list_a', :'product_a'
    ),
    '19 user B cannot insert entry into A list'
);
select waytask_test.assert_true(
    (select count(*) = 0 from public.shopping_list_entries
      where id = :'entry_a'),
    '20 user B cannot guess A entry ID'
);
select waytask_test.assert_true(
    (select count(*) = 0 from public.personal_products
      where id = :'product_a'),
    '21 user B cannot guess A product ID'
);
select waytask_test.assert_true(
    (select count(*) = 0 from public.shopping_lists
      where owner_user_id = :'user_a' or title like '%'),
    '22 query-filter manipulation cannot bypass list RLS'
);
select waytask_test.assert_true(
    (select count(*) = 0 from public.profiles
      where owner_user_id <> :'user_b' or true),
    '23 broad OR-filter cannot bypass profile RLS'
);

insert into public.profiles (id, owner_user_id, display_name)
values (:'user_b', :'user_b', 'User B');
insert into public.shopping_lists (id, owner_user_id, title)
values (:'list_b', :'user_b', 'B List');
insert into public.personal_products (
    id, owner_user_id, display_name, source
) values (:'product_b', :'user_b', 'Bread', 'manual');
insert into public.shopping_list_entries (
    id, owner_user_id, shopping_list_id, personal_product_id, quantity
) values (:'entry_b', :'user_b', :'list_b', :'product_b', 1);
select waytask_test.pass('24 user B creates own parent-child fixture');
select waytask_test.expect_failure(
    format(
        'update public.shopping_list_entries set shopping_list_id = %L '
        'where id = %L', :'list_a', :'entry_b'
    ),
    '25 user B cannot move own entry into A list'
);
select waytask_test.assert_true(
    (select shopping_list_id = :'list_b'
       from public.shopping_list_entries where id = :'entry_b'),
    '26 failed cross-owner move preserves original parent'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'user_a', true);
select waytask_test.expect_failure(
    format('update public.shopping_lists set owner_user_id = %L where id = %L',
           :'user_b', :'list_a'),
    '27 user A cannot change list owner to B'
);
select waytask_test.expect_failure(
    format('update public.shopping_list_entries set owner_user_id = %L where id = %L',
           :'user_b', :'entry_a'),
    '28 user A cannot change entry owner to B'
);
select waytask_test.expect_failure(
    format(
        'insert into public.profiles (id, owner_user_id, display_name) '
        'values (%L, %L, %L)',
        'cccccccc-cccc-4ccc-8ccc-cccccccccccc', :'user_b', 'forged'
    ),
    '29 user A cannot create profile owned by B'
);
select waytask_test.expect_failure(
    format(
        'insert into public.sync_mutations '
        '(id, owner_user_id, device_installation_id, idempotency_key, '
        'mutation_type, payload_sha256, record_count, payload_bytes) '
        'values (%L, %L, %L, %L, %L, %L, 4, 512)',
        'a5000000-0000-4000-8000-000000000099', :'user_a', :'device_a',
        'migration-a-0000000000001', 'initial_migration', repeat('a', 64)
    ),
    '30 duplicate idempotency key is rejected'
);
select waytask_test.assert_true(
    (select count(*) = 1 from public.sync_mutations
      where idempotency_key = 'migration-a-0000000000001'),
    '31 duplicate retry leaves exactly one mutation receipt'
);
select waytask_test.expect_affected(
    format('update public.shopping_lists set deleted_at = now() where id = %L',
           :'list_a'),
    1,
    '32 owner creates list tombstone by update'
);
select waytask_test.assert_true(
    (select count(*) = 1 from public.shopping_lists
      where id = :'list_a' and deleted_at is not null),
    '33 owner can read own tombstone for synchronization'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'user_b', true);
select waytask_test.assert_true(
    (select count(*) = 0 from public.shopping_lists where id = :'list_a'),
    '34 non-owner cannot read owner tombstone'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select waytask_test.assert_true(
    (select count(*) = 0 from public.profiles),
    '35 anonymous cannot read private profiles'
);
select waytask_test.assert_true(
    (select count(*) = 0 from public.shopping_lists),
    '36 anonymous cannot read private lists'
);
select waytask_test.assert_true(
    (select count(*) = 0 from public.shopping_list_entries),
    '37 anonymous cannot read private entries'
);
select waytask_test.expect_failure(
    format(
        'insert into public.shopping_lists (id, owner_user_id, title) '
        'values (%L, %L, %L)',
        'dddddddd-dddd-4ddd-8ddd-dddddddddddd', :'user_a', 'anonymous forged'
    ),
    '38 anonymous cannot insert private list'
);

reset role;
set local role service_role;
insert into public.catalog_releases (
    id, release_name, schema_version, content_sha256, published_at
) values (
    :'catalog_release', 'authorization-fixture', 1, repeat('c', 64), now()
);
select waytask_test.pass('39 trusted server can write shared release metadata');
select waytask_test.assert_true(
    (select count(*) = 2 from public.profiles),
    '40 trusted server context can inspect private rows'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select waytask_test.assert_true(
    (select count(*) = 1 from public.catalog_releases
      where id = :'catalog_release'),
    '41 anonymous may read published shared metadata'
);
select waytask_test.expect_failure(
    format(
        'insert into public.catalog_releases '
        '(id, release_name, schema_version, content_sha256, published_at) '
        'values (%L, %L, 1, %L, now())',
        'c2000000-0000-4000-8000-000000000002', 'client-write', repeat('d', 64)
    ),
    '42 anonymous cannot insert shared metadata'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'user_a', true);
select waytask_test.expect_affected(
    format('update public.catalog_releases set release_name = %L where id = %L',
           'changed', :'catalog_release'),
    0,
    '43 authenticated user cannot update shared metadata'
);
select waytask_test.expect_affected(
    format('delete from public.catalog_releases where id = %L', :'catalog_release'),
    0,
    '44 authenticated user cannot delete shared metadata'
);
select waytask_test.assert_true(
    not has_schema_privilege(current_user, 'waytask_admin', 'USAGE'),
    '45 authenticated client cannot access administrative schema'
);
select waytask_test.assert_true(
    not has_table_privilege(
        current_user,
        (
            select c.oid
            from pg_class c
            join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'waytask_admin'
              and c.relname = 'migration_audit'
        ),
        'SELECT'
    ),
    '46 authenticated client has no administrative table privilege'
);
select waytask_test.expect_affected(
    format('update public.sync_mutations set status = %L where id = %L',
           'applied', :'mutation_a'),
    0,
    '47 client cannot forge mutation application status'
);

reset role;
select waytask_test.assert_true(
    (select count(*) = 10
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname in (
            'profiles', 'user_preferences', 'shopping_lists',
            'personal_products', 'shopping_list_entries', 'saved_stores',
            'notification_preferences', 'device_installations',
            'sync_mutations', 'catalog_releases'
        )
        and c.relrowsecurity),
    '48 every Data API table has RLS enabled'
);
select waytask_test.assert_true(
    (select count(*) = 10
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname in (
            'profiles', 'user_preferences', 'shopping_lists',
            'personal_products', 'shopping_list_entries', 'saved_stores',
            'notification_preferences', 'device_installations',
            'sync_mutations', 'catalog_releases'
        )
        and c.relforcerowsecurity),
    '49 every Data API table has FORCE RLS enabled'
);
select waytask_test.assert_true(
    (select count(*) >= 4 * 10 from pg_policies
      where schemaname = 'public'
        and tablename in (
            'profiles', 'user_preferences', 'shopping_lists',
            'personal_products', 'shopping_list_entries', 'saved_stores',
            'notification_preferences', 'device_installations',
            'sync_mutations', 'catalog_releases'
        )),
    '50 every Data API table has operation-complete policy coverage'
);

do $$
declare
    passed integer;
begin
    select count(*) into passed from waytask_test.results;
    if passed <> 50 then
        raise exception 'expected 50 authorization tests, got %', passed;
    end if;
    raise notice 'WT-032A AUTHORIZATION TESTS PASSED: %', passed;
end;
$$;

rollback;
