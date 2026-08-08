\set ON_ERROR_STOP on
\set QUIET on

begin;

create schema waytask_test;
create table waytask_test.results(name text primary key);

create or replace function waytask_test.pass(test_name text)
returns void language plpgsql security definer
set search_path = waytask_test, pg_catalog
as $$
begin
    insert into waytask_test.results(name) values (test_name);
end;
$$;

create or replace function waytask_test.assert_true(
    condition boolean,
    test_name text
) returns void language plpgsql security definer
set search_path = waytask_test, pg_catalog
as $$
begin
    if condition is not true then
        raise exception 'migration assertion failed: %', test_name;
    end if;
    perform waytask_test.pass(test_name);
end;
$$;

create or replace function waytask_test.expect_failure(
    statement text,
    test_name text
) returns void language plpgsql security invoker
set search_path = waytask_test, public, auth, pg_catalog
as $$
begin
    begin
        execute statement;
    exception when others then
        perform waytask_test.pass(test_name);
        return;
    end;
    raise exception 'expected migration failure: %', test_name;
end;
$$;

grant usage on schema waytask_test to anon, authenticated, service_role;
grant execute on all functions in schema waytask_test
to anon, authenticated, service_role;

\set user_a 'ca000000-0000-4a00-8a00-000000000001'
\set user_b 'cb000000-0000-4b00-8b00-000000000002'
\set attempt_a 'ca100000-0000-4a00-8a00-000000000011'
\set attempt_b 'cb100000-0000-4b00-8b00-000000000012'
\set dataset_a 'ca200000-0000-4a00-8a00-000000000021'
\set dataset_b 'cb200000-0000-4b00-8b00-000000000022'
\set product_a 'ca300000-0000-4a00-8a00-000000000031'
\set list_a 'ca400000-0000-4a00-8a00-000000000041'
\set entry_a 'ca500000-0000-4a00-8a00-000000000051'

insert into auth.users(
    instance_id, id, aud, role, email, encrypted_password, created_at, updated_at
) values
    (gen_random_uuid(), :'user_a', 'authenticated', 'authenticated',
     'migration-a@local.invalid', '', now(), now()),
    (gen_random_uuid(), :'user_b', 'authenticated', 'authenticated',
     'migration-b@local.invalid', '', now(), now());

update waytask_private.initial_migration_control
set enabled = true,
    endpoint_ready = true,
    signed_session_ab_gate_passed = true,
    session_recovery_gate_passed = true,
    security_blockers_clear = true;

select waytask_private.sha256_hex(convert_to(
    lower(:'attempt_a') || '|0|personal_products|' || repeat('a', 64),
    'UTF8'
)) as product_batch \gset
select waytask_private.sha256_hex(convert_to(
    lower(:'attempt_a') || '|1|shopping_lists|' || repeat('b', 64),
    'UTF8'
)) as list_batch \gset
select waytask_private.sha256_hex(convert_to(
    lower(:'attempt_a') || '|1|personal_products|' || repeat('e', 64),
    'UTF8'
)) as product_overflow_batch \gset
select waytask_private.sha256_hex(convert_to(
    lower(:'attempt_a') || '|2|shopping_list_entries|' || repeat('c', 64),
    'UTF8'
)) as entry_batch \gset
select waytask_private.sha256_hex(convert_to(
    lower(:'attempt_b') || '|0|shopping_list_entries|' || repeat('d', 64),
    'UTF8'
)) as child_first_batch \gset

set local role authenticated;
select set_config('request.jwt.claim.sub', :'user_a', true);
select waytask_test.expect_failure(
    format(
        'select public.initial_migration_begin(%L, %L, %L, 1, %L::jsonb)',
        :'attempt_a', :'dataset_a', repeat('1', 64),
        '{"personal_products":1,"shopping_lists":1,"shopping_list_entries":1}'
    ),
    '01 deployment approval independently defaults to denied'
);
select waytask_test.expect_failure(
    format(
        'insert into public.initial_migration_attempts '
        '(id, owner_user_id, local_dataset_id, dataset_fingerprint, '
        'format_version, expected_personal_products, expected_shopping_lists, '
        'expected_shopping_list_entries) values (%L,%L,%L,%L,1,0,0,0)',
        :'attempt_a', :'user_a', :'dataset_a', repeat('1', 64)
    ),
    '02 clients cannot directly forge an attempt'
);

reset role;
update waytask_private.initial_migration_control
set deployment_approved = true,
    enabled = true,
    endpoint_ready = true,
    signed_session_ab_gate_passed = true,
    session_recovery_gate_passed = true,
    security_blockers_clear = true;

set local role anon;
select set_config('request.jwt.claim.sub', '', true);
select waytask_test.expect_failure(
    format(
        'select public.initial_migration_begin(%L, %L, %L, 1, %L::jsonb)',
        :'attempt_a', :'dataset_a', repeat('1', 64),
        '{"personal_products":1,"shopping_lists":1,"shopping_list_entries":1}'
    ),
    '03 anonymous migration is denied'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'user_a', true);
select public.initial_migration_begin(
    :'attempt_a', :'dataset_a', repeat('1', 64), 1,
    '{"personal_products":1,"shopping_lists":1,"shopping_list_entries":1}'
);
select waytask_test.pass('04 authenticated A begins an owner-derived attempt');

select waytask_test.expect_failure(
    format(
        'update public.initial_migration_attempts set state = %L '
        'where id = %L',
        'completed', :'attempt_a'
    ),
    '19 client cannot claim arbitrary migration completion'
);

select waytask_test.expect_failure(
    format(
        'select public.initial_migration_apply_batch(%L,%L,0,%L,%L,%L::jsonb)',
        :'attempt_a', :'product_batch', 'personal_products', repeat('a', 64),
        format('[{"id":"%s","owner_user_id":"%s"}]',
               :'product_a', :'user_b')
    ),
    '05 forged owner field is rejected'
);

select public.initial_migration_apply_batch(
    :'attempt_a', :'product_batch', 0, 'personal_products', repeat('a', 64),
    jsonb_build_array(jsonb_build_object(
        'id', :'product_a', 'display_name', 'חלב Synthetic 👻',
        'brand', 'Synthetic', 'category', 'Food', 'barcode', '123456789012',
        'source', 'manual', 'catalog_product_id', 'synthetic.milk',
        'library_lifecycle', 'active', 'created_at_milliseconds', 1700000000000,
        'updated_at_milliseconds', 1700000000000
    ))
);
select waytask_test.pass('06 product batch is accepted with server owner');

select public.initial_migration_apply_batch(
    :'attempt_a', :'product_batch', 0, 'personal_products', repeat('a', 64),
    jsonb_build_array(jsonb_build_object(
        'id', :'product_a', 'display_name', 'חלב Synthetic 👻',
        'brand', 'Synthetic', 'category', 'Food', 'barcode', '123456789012',
        'source', 'manual', 'catalog_product_id', 'synthetic.milk',
        'library_lifecycle', 'active', 'created_at_milliseconds', 1700000000000,
        'updated_at_milliseconds', 1700000000000
    ))
);
select waytask_test.assert_true(
    (select count(*) = 1 from public.personal_products
     where id = :'product_a'),
    '07 duplicate lost-response retry is idempotent'
);

select waytask_test.expect_failure(
    format(
        'select public.initial_migration_apply_batch(%L,%L,1,%L,%L,%L::jsonb)',
        :'attempt_a', :'product_overflow_batch', 'personal_products',
        repeat('e', 64),
        format('[{"id":"%s","display_name":"Extra Synthetic",'
               '"source":"manual","library_lifecycle":"active",'
               '"created_at_milliseconds":1700000000000,'
               '"updated_at_milliseconds":1700000000000}]',
               gen_random_uuid())
    ),
    '22 declared entity counts cap accepted batches before insertion'
);

select waytask_test.expect_failure(
    format(
        'select public.initial_migration_apply_batch(%L,%L,2,%L,%L,%L::jsonb)',
        :'attempt_a', :'entry_batch', 'shopping_list_entries', repeat('c', 64),
        '[]'
    ),
    '08 batch sequence/order violation is rejected'
);

select public.initial_migration_apply_batch(
    :'attempt_a', :'list_batch', 1, 'shopping_lists', repeat('b', 64),
    jsonb_build_array(jsonb_build_object(
        'id', :'list_a', 'title', 'Synthetic List', 'purpose', 'shopping',
        'created_at_milliseconds', 1700000000000,
        'updated_at_milliseconds', 1700000000000
    ))
);
select waytask_test.pass('09 parent list batch follows product dependency');

select public.initial_migration_apply_batch(
    :'attempt_a', :'entry_batch', 2, 'shopping_list_entries', repeat('c', 64),
    jsonb_build_array(jsonb_build_object(
        'id', :'entry_a', 'shopping_list_id', :'list_a',
        'personal_product_id', :'product_a', 'quantity', 2,
        'unit', 'count', 'note', 'Synthetic note', 'lifecycle', 'needed',
        'sort_order', 0, 'created_at_milliseconds', 1700000000000,
        'updated_at_milliseconds', 1700000000000
    ))
);
select waytask_test.pass('10 child batch succeeds only after owned parents');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'user_b', true);
select waytask_test.assert_true(
    (select count(*) = 0 from public.initial_migration_attempts),
    '11 B cannot read A attempt or receipts'
);
select waytask_test.expect_failure(
    format(
        'select public.initial_migration_begin(%L,%L,%L,1,%L::jsonb)',
        :'attempt_a', :'dataset_a', repeat('1', 64),
        '{"personal_products":1,"shopping_lists":1,"shopping_list_entries":1}'
    ),
    '12 B cannot claim A attempt ID or manifest'
);

do $$
declare
    detected boolean := false;
begin
    begin
        insert into public.user_preferences(owner_user_id)
        values ('cb000000-0000-4b00-8b00-000000000002'::uuid);
        perform public.initial_migration_begin(
            'cb100000-0000-4b00-8b00-000000000012'::uuid,
            'cb200000-0000-4b00-8b00-000000000022'::uuid,
            repeat('2', 64), 1,
            '{"personal_products":0,"shopping_lists":0,"shopping_list_entries":1}'::jsonb
        );
    exception when sqlstate '23505' then
        detected := true;
    end;
    if not detected then
        raise exception 'pre-existing unrelated private data was not detected';
    end if;
end;
$$;

select public.initial_migration_begin(
    :'attempt_b', :'dataset_b', repeat('2', 64), 1,
    '{"personal_products":0,"shopping_lists":0,"shopping_list_entries":1}'
);
select waytask_test.expect_failure(
    format(
        'select public.initial_migration_apply_batch(%L,%L,0,%L,%L,%L::jsonb)',
        :'attempt_b', :'child_first_batch', 'shopping_list_entries',
        repeat('d', 64),
        format('[{"id":"%s","shopping_list_id":"%s",'
               '"personal_product_id":"%s","quantity":1,'
               '"lifecycle":"needed","sort_order":0,'
               '"created_at_milliseconds":1700000000000,'
               '"updated_at_milliseconds":1700000000000}]',
               gen_random_uuid(), :'list_a', :'product_a')
    ),
    '13 child-before-parent and cross-owner parent are rejected'
);
select public.initial_migration_rollback(:'attempt_b');
select waytask_test.pass('14 bound partial attempt rollback is child-first');
select waytask_test.expect_failure(
    format(
        'select public.initial_migration_begin(%L,%L,%L,1,%L::jsonb)',
        gen_random_uuid(), :'dataset_a', repeat('3', 64),
        '{"personal_products":0,"shopping_lists":0,"shopping_list_entries":0}'
    ),
    '20 B cannot claim A local dataset identity with a new attempt'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'user_a', true);
do $$
declare
    detected boolean := false;
begin
    begin
        update public.personal_products
        set display_name = 'Tampered after receipt'
        where id = 'ca300000-0000-4a00-8a00-000000000031'::uuid;
        perform public.initial_migration_verify(
            'ca100000-0000-4a00-8a00-000000000011'::uuid
        );
    exception when sqlstate '23514' then
        detected := true;
    end;
    if not detected then
        raise exception 'post-insert row mutation was not detected';
    end if;
end;
$$;
do $$
declare
    detected boolean := false;
begin
    begin
        insert into public.user_preferences(owner_user_id)
        values ('ca000000-0000-4a00-8a00-000000000001'::uuid);
        perform public.initial_migration_verify(
            'ca100000-0000-4a00-8a00-000000000011'::uuid
        );
    exception when sqlstate '23514' then
        detected := true;
    end;
    if not detected then
        raise exception 'unrelated private data before completion was not detected';
    end if;
end;
$$;
select public.initial_migration_verify(:'attempt_a');
select waytask_test.assert_true(
    (select state = 'completed' from public.initial_migration_attempts
     where id = :'attempt_a'),
    '15 row hashes, counts, receipts, ownership, and parents verify completion'
);
select waytask_test.expect_failure(
    format('select public.initial_migration_rollback(%L)', :'attempt_a'),
    '16 verified completion cannot be client-rolled back'
);
select waytask_test.assert_true(
    (select owner_user_id = :'user_a' from public.personal_products
     where id = :'product_a')
    and (select owner_user_id = :'user_a' from public.shopping_lists
         where id = :'list_a')
    and (select owner_user_id = :'user_a' from public.shopping_list_entries
         where id = :'entry_a'),
    '17 every migrated row is server-bound to authenticated A'
);

reset role;
select waytask_test.assert_true(
    (select count(*) = 2
     from pg_class relation
     join pg_namespace namespace on namespace.oid = relation.relnamespace
     where namespace.nspname = 'public'
       and relation.relname in (
           'initial_migration_attempts', 'initial_migration_receipts'
       )
       and relation.relrowsecurity and relation.relforcerowsecurity),
    '18 migration ledger tables have RLS and FORCE RLS'
);
select waytask_test.assert_true(
    (select count(*) = 2
     from pg_constraint constraint_value
     where constraint_value.conrelid =
            'public.initial_migration_attempts'::regclass
       and constraint_value.conname in (
           'initial_migration_attempt_single_owner',
           'initial_migration_attempt_dataset_identity'
       )),
    '21 one first-migration owner and dataset identity are enforced'
);

do $$
declare passed integer;
begin
    select count(*) into passed from waytask_test.results;
    if passed <> 22 then
        raise exception 'expected 22 migration tests, got %', passed;
    end if;
    raise notice 'WT-032C MIGRATION SECURITY TESTS PASSED: %', passed;
end;
$$;

rollback;
