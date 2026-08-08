-- WT-032B hosted Staging gate.
-- Pure SQL for `supabase db query --linked --file ...`.
-- Every synthetic identity and row is contained in this transaction and rolled
-- back. This file must never be executed against Production.

begin;

create schema waytask_hosted_test;
create table waytask_hosted_test.results (name text primary key);

create or replace function waytask_hosted_test.pass(test_name text)
returns void language plpgsql security definer
set search_path = waytask_hosted_test, pg_catalog
as $$
begin
    insert into waytask_hosted_test.results(name) values (test_name);
end;
$$;

create or replace function waytask_hosted_test.assert_true(
    condition boolean,
    test_name text
) returns void language plpgsql security definer
set search_path = waytask_hosted_test, pg_catalog
as $$
begin
    if condition is not true then
        raise exception 'hosted staging assertion failed: %', test_name;
    end if;
    perform waytask_hosted_test.pass(test_name);
end;
$$;

create or replace function waytask_hosted_test.expect_failure(
    statement text,
    test_name text
) returns void language plpgsql security invoker
set search_path = waytask_hosted_test, public, auth, pg_catalog
as $$
begin
    begin
        execute statement;
    exception when others then
        perform waytask_hosted_test.pass(test_name);
        return;
    end;
    raise exception 'expected hosted staging failure: %', test_name;
end;
$$;

create or replace function waytask_hosted_test.expect_affected(
    statement text,
    expected_rows bigint,
    test_name text
) returns void language plpgsql security invoker
set search_path = waytask_hosted_test, public, auth, pg_catalog
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
    perform waytask_hosted_test.pass(test_name);
end;
$$;

grant usage on schema waytask_hosted_test
to anon, authenticated, service_role;
grant execute on all functions in schema waytask_hosted_test
to anon, authenticated, service_role;

select waytask_hosted_test.assert_true(
    (
        select string_agg(version, ',' order by version) =
            '20260806000100,20260806000200,20260808000100,20260808000200'
        from supabase_migrations.schema_migrations
    ),
    '01 hosted migration history exactly matches the repository'
);
select waytask_hosted_test.assert_true(
    (
        select count(*) = 10
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relkind in ('r', 'p')
          and c.relname in (
              'profiles', 'user_preferences', 'shopping_lists',
              'personal_products', 'shopping_list_entries', 'saved_stores',
              'notification_preferences', 'device_installations',
              'sync_mutations', 'catalog_releases'
          )
    ),
    '02 all ten expected Data API tables are deployed'
);
select waytask_hosted_test.assert_true(
    (
        select count(*) = 10
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname in (
              'profiles', 'user_preferences', 'shopping_lists',
              'personal_products', 'shopping_list_entries', 'saved_stores',
              'notification_preferences', 'device_installations',
              'sync_mutations', 'catalog_releases'
          )
          and c.relrowsecurity
    ),
    '03 RLS is enabled on every Data API table'
);
select waytask_hosted_test.assert_true(
    (
        select count(*) = 10
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname in (
              'profiles', 'user_preferences', 'shopping_lists',
              'personal_products', 'shopping_list_entries', 'saved_stores',
              'notification_preferences', 'device_installations',
              'sync_mutations', 'catalog_releases'
          )
          and c.relforcerowsecurity
    ),
    '04 FORCE RLS is enabled on every Data API table'
);
select waytask_hosted_test.assert_true(
    (
        select count(*) >= 40
        from pg_policies
        where schemaname = 'public'
          and tablename in (
              'profiles', 'user_preferences', 'shopping_lists',
              'personal_products', 'shopping_list_entries', 'saved_stores',
              'notification_preferences', 'device_installations',
              'sync_mutations', 'catalog_releases'
          )
    ),
    '05 operation-complete RLS policy coverage is deployed'
);
select waytask_hosted_test.assert_true(
    has_schema_privilege('anon', 'public', 'USAGE'),
    '06 anonymous Data API role can resolve public schema'
);
select waytask_hosted_test.assert_true(
    has_table_privilege('anon', 'public.profiles', 'SELECT'),
    '07 anonymous private-table access is mediated by RLS'
);
select waytask_hosted_test.assert_true(
    has_table_privilege(
        'authenticated', 'public.profiles', 'SELECT, INSERT, UPDATE'
    ),
    '08 authenticated profile operations are exposed through RLS'
);
select waytask_hosted_test.assert_true(
    not has_schema_privilege('anon', 'waytask_private', 'USAGE'),
    '09 anonymous role cannot resolve private schema'
);
select waytask_hosted_test.assert_true(
    not has_schema_privilege('authenticated', 'waytask_admin', 'USAGE'),
    '10 authenticated role cannot resolve administrative schema'
);
select waytask_hosted_test.assert_true(
    (
        select count(*) = 1
        from pg_constraint
        where conname = 'profiles_display_name_valid'
          and conrelid = 'public.profiles'::regclass
    ),
    '11 authoritative profile display-name constraint is deployed'
);
select waytask_hosted_test.assert_true(
    (
        select count(*) = 1
        from pg_trigger
        where tgname = 'profiles_display_name_normalize'
          and tgrelid = 'public.profiles'::regclass
          and not tgisinternal
    ),
    '12 profile normalization trigger is deployed'
);
select waytask_hosted_test.assert_true(
    not has_function_privilege(
        'anon',
        'waytask_private.normalize_profile_display_name(text)',
        'EXECUTE'
    ),
    '13 anonymous cannot execute profile normalization internals'
);
select waytask_hosted_test.assert_true(
    to_regprocedure('public.rls_auto_enable()') is null or (
        not has_function_privilege(
            'anon', 'public.rls_auto_enable()', 'EXECUTE'
        )
        and not has_function_privilege(
            'authenticated', 'public.rls_auto_enable()', 'EXECUTE'
        )
    ),
    '14 client roles cannot execute the RLS event-trigger helper'
);

insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, created_at, updated_at
) values
    (
        gen_random_uuid(), 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'authenticated', 'authenticated',
        'wt032b-hosted-a@invalid.example', '', now(), now()
    ),
    (
        gen_random_uuid(), 'ebbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        'authenticated', 'authenticated',
        'wt032b-hosted-b@invalid.example', '', now(), now()
    );

set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    true
);
insert into public.profiles (id, owner_user_id, display_name)
values (
    'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'User A'
);
select waytask_hosted_test.pass('15 user A creates own profile');
select waytask_hosted_test.assert_true(
    (
        select count(*) = 1 from public.profiles
        where id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    '16 user A reads own profile by exact UUID'
);
update public.profiles set display_name = 'DROP TABLE shopping_lists;'
where id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select waytask_hosted_test.assert_true(
    (
        select display_name = 'DROP TABLE shopping_lists;'
        from public.profiles
        where id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    '17 SQL-like profile input is stored as literal data'
);
select waytask_hosted_test.assert_true(
    to_regclass('public.shopping_lists') is not null,
    '18 SQL-like profile input never executes'
);
update public.profiles set display_name = '<script>alert(1)</script>'
where id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select waytask_hosted_test.assert_true(
    (
        select display_name = '<script>alert(1)</script>'
        from public.profiles
        where id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    '19 markup-like profile input is stored as literal data'
);
update public.profiles set display_name = '   Ada    Lovelace   '
where id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select waytask_hosted_test.assert_true(
    (
        select display_name = 'Ada Lovelace' from public.profiles
        where id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    '20 profile whitespace is normalized server-side'
);
update public.profiles set display_name = U&'Jose\0301'
where id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select waytask_hosted_test.assert_true(
    (
        select display_name = 'José' from public.profiles
        where id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    '21 combining profile input is normalized to NFC'
);
update public.profiles set display_name = 'נועה לוי'
where id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select waytask_hosted_test.pass('22 Hebrew profile input is accepted');
update public.profiles set display_name = 'ليان أحمد'
where id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select waytask_hosted_test.pass('23 Arabic profile input is accepted');
update public.profiles set display_name = '👨‍👩‍👧‍👦'
where id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
select waytask_hosted_test.pass('24 ZWJ emoji profile input is accepted');
select waytask_hosted_test.expect_failure(
    format(
        'update public.profiles set display_name = %L where id = %L',
        U&'A\200BB', 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    '25 zero-width profile input is rejected server-side'
);
select waytask_hosted_test.expect_failure(
    format(
        'update public.profiles set display_name = %L where id = %L',
        U&'A\202EB', 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    '26 bidi-override profile input is rejected server-side'
);
select waytask_hosted_test.expect_failure(
    format(
        'update public.profiles set display_name = %L where id = %L',
        E'A\nB', 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    '27 newline profile input is rejected server-side'
);
select waytask_hosted_test.expect_failure(
    format(
        'update public.profiles set display_name = %L where id = %L',
        repeat('a', 81), 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    '28 overlong profile input is rejected server-side'
);
select waytask_hosted_test.expect_failure(
    format(
        'update public.profiles set display_name = %L where id = %L',
        '', 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    '29 empty profile input is rejected server-side'
);
select waytask_hosted_test.expect_failure(
    'select convert_from(decode(''00'', ''hex''), ''UTF8'')',
    '30 null byte is rejected by hosted PostgreSQL text boundary'
);

insert into public.shopping_lists (id, owner_user_id, title)
values (
    'ea100000-0000-4000-8000-000000000001',
    'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'A List'
);
insert into public.personal_products (
    id, owner_user_id, display_name, source
) values (
    'ea200000-0000-4000-8000-000000000002',
    'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Milk', 'manual'
);
insert into public.shopping_list_entries (
    id, owner_user_id, shopping_list_id, personal_product_id, quantity
) values (
    'ea300000-0000-4000-8000-000000000003',
    'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'ea100000-0000-4000-8000-000000000001',
    'ea200000-0000-4000-8000-000000000002', 1
);
select waytask_hosted_test.pass('31 user A creates own parent-child fixture');
select waytask_hosted_test.assert_true(
    (
        select count(*) = 1 from public.shopping_list_entries
        where id = 'ea300000-0000-4000-8000-000000000003'
    ),
    '32 user A reads own child by exact UUID'
);

reset role;
set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    'ebbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    true
);
select waytask_hosted_test.assert_true(
    (
        select count(*) = 0 from public.profiles
        where id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    ),
    '33 user B cannot read A profile by exact UUID'
);
select waytask_hosted_test.assert_true(
    (
        select count(*) = 0 from public.shopping_lists
        where id = 'ea100000-0000-4000-8000-000000000001'
    ),
    '34 user B cannot read A list by exact UUID'
);
select waytask_hosted_test.assert_true(
    (
        select count(*) = 0 from public.shopping_list_entries
        where id = 'ea300000-0000-4000-8000-000000000003'
    ),
    '35 user B cannot read A child by exact UUID'
);
select waytask_hosted_test.assert_true(
    (
        select count(*) = 0 from public.profiles
        where owner_user_id <> 'ebbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
           or true
    ),
    '36 broad OR profile filter cannot bypass RLS'
);
select waytask_hosted_test.assert_true(
    (
        select count(*) = 0 from public.shopping_lists
        where owner_user_id = 'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
           or title like '%'
    ),
    '37 manipulated list filter cannot bypass RLS'
);
select waytask_hosted_test.expect_affected(
    'update public.profiles set display_name = ''stolen'' '
        'where id = ''eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa''',
    0,
    '38 user B cannot update A profile'
);
select waytask_hosted_test.expect_affected(
    'delete from public.profiles '
        'where id = ''eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa''',
    0,
    '39 user B cannot delete A profile'
);
select waytask_hosted_test.expect_failure(
    'insert into public.shopping_list_entries '
        '(id, owner_user_id, shopping_list_id, personal_product_id, quantity) '
        'values (''eb300000-0000-4000-8000-000000000099'', '
        '''ebbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'', '
        '''ea100000-0000-4000-8000-000000000001'', '
        '''ea200000-0000-4000-8000-000000000002'', 1)',
    '40 user B cannot insert a child into A parents'
);

insert into public.profiles (id, owner_user_id, display_name)
values (
    'ebbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'ebbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'User B'
);
insert into public.shopping_lists (id, owner_user_id, title)
values (
    'eb100000-0000-4000-8000-000000000001',
    'ebbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'B List'
);
insert into public.personal_products (
    id, owner_user_id, display_name, source
) values (
    'eb200000-0000-4000-8000-000000000002',
    'ebbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Bread', 'manual'
);
insert into public.shopping_list_entries (
    id, owner_user_id, shopping_list_id, personal_product_id, quantity
) values (
    'eb300000-0000-4000-8000-000000000003',
    'ebbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'eb100000-0000-4000-8000-000000000001',
    'eb200000-0000-4000-8000-000000000002', 1
);
select waytask_hosted_test.pass('41 user B creates own parent-child fixture');
select waytask_hosted_test.expect_failure(
    'update public.shopping_list_entries '
        'set shopping_list_id = ''ea100000-0000-4000-8000-000000000001'' '
        'where id = ''eb300000-0000-4000-8000-000000000003''',
    '42 user B cannot move own child into A parent'
);

reset role;
set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    true
);
select waytask_hosted_test.expect_failure(
    'update public.shopping_lists '
        'set owner_user_id = ''ebbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'' '
        'where id = ''ea100000-0000-4000-8000-000000000001''',
    '43 user A cannot mutate list owner'
);
select waytask_hosted_test.expect_failure(
    'update public.shopping_list_entries '
        'set owner_user_id = ''ebbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'' '
        'where id = ''ea300000-0000-4000-8000-000000000003''',
    '44 user A cannot mutate child owner'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select waytask_hosted_test.assert_true(
    (select count(*) = 0 from public.profiles),
    '45 anonymous cannot read private profiles'
);
select waytask_hosted_test.assert_true(
    (select count(*) = 0 from public.shopping_lists),
    '46 anonymous cannot read private lists'
);
select waytask_hosted_test.expect_failure(
    'insert into public.shopping_lists (id, owner_user_id, title) values '
        '(''eddddddd-dddd-4ddd-8ddd-dddddddddddd'', '
        '''eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'', ''forged'')',
    '47 anonymous cannot insert a private list'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select waytask_hosted_test.assert_true(
    (select count(*) = 0 from public.profiles),
    '48 missing JWT subject has no private access'
);
select set_config('request.jwt.claim.sub', 'not-a-uuid', true);
select waytask_hosted_test.expect_failure(
    'select count(*) from public.profiles',
    '49 malformed JWT subject fails closed'
);

reset role;
set local role service_role;
insert into public.catalog_releases (
    id, release_name, schema_version, content_sha256, published_at
) values
    (
        'ec100000-0000-4000-8000-000000000001',
        'wt032b-hosted-published', 1, repeat('c', 64), now()
    ),
    (
        'ec200000-0000-4000-8000-000000000002',
        'wt032b-hosted-future', 1, repeat('d', 64),
        now() + interval '1 day'
    );
select waytask_hosted_test.pass('50 trusted role creates catalog fixtures');

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select waytask_hosted_test.assert_true(
    (
        select count(*) = 1 from public.catalog_releases
        where id = 'ec100000-0000-4000-8000-000000000001'
    ),
    '51 anonymous can read published catalog metadata'
);
select waytask_hosted_test.assert_true(
    (
        select count(*) = 0 from public.catalog_releases
        where id = 'ec200000-0000-4000-8000-000000000002'
    ),
    '52 anonymous cannot read unpublished catalog metadata'
);
select waytask_hosted_test.expect_failure(
    'insert into public.catalog_releases '
        '(id, release_name, schema_version, content_sha256, published_at) '
        'values (''ec300000-0000-4000-8000-000000000003'', '
        '''wt032b-hosted-forged'', 1, ''' || repeat('e', 64) || ''', now())',
    '53 anonymous cannot insert catalog metadata'
);

reset role;
set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    'eaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    true
);
select waytask_hosted_test.expect_affected(
    'update public.catalog_releases set release_name = ''changed'' '
        'where id = ''ec100000-0000-4000-8000-000000000001''',
    0,
    '54 authenticated client cannot update catalog metadata'
);
select waytask_hosted_test.expect_affected(
    'delete from public.catalog_releases '
        'where id = ''ec100000-0000-4000-8000-000000000001''',
    0,
    '55 authenticated client cannot delete catalog metadata'
);
select waytask_hosted_test.assert_true(
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
    '56 authenticated client cannot read administrative table'
);

reset role;

do $$
declare
    passed integer;
begin
    select count(*) into passed from waytask_hosted_test.results;
    if passed <> 56 then
        raise exception 'expected 56 hosted staging assertions, got %', passed;
    end if;
end;
$$;

select
    count(*) as passed_assertions,
    min(name) as first_assertion,
    max(name) as last_assertion
from waytask_hosted_test.results;

rollback;
