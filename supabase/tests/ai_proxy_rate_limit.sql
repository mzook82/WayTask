\set ON_ERROR_STOP on
\set QUIET on

begin;

create schema waytask_test;
create table waytask_test.results (name text primary key);

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
        raise exception 'secure AI assertion failed: %', test_name;
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
    raise exception 'expected secure AI failure: %', test_name;
end;
$$;

grant usage on schema waytask_test to anon, authenticated;
grant execute on all functions in schema waytask_test to anon, authenticated;

\set user_a '11111111-1111-4111-8111-111111111111'
\set user_b '22222222-2222-4222-8222-222222222222'
\set ip_hash 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, created_at, updated_at
) values
    (gen_random_uuid(), :'user_a', 'authenticated', 'authenticated',
     'ai-a@local.invalid', '', now(), now()),
    (gen_random_uuid(), :'user_b', 'authenticated', 'authenticated',
     'ai-b@local.invalid', '', now(), now());

insert into waytask_private.ai_recognition_requests (
    owner_user_id, request_id, ip_hash, created_at
) values (
    :'user_b',
    '20000000-0000-4000-8000-000000009999',
    :'ip_hash',
    now() - interval '3 days'
);

set local role anon;
select waytask_test.expect_failure(
    format(
        'select * from public.consume_ai_recognition_quota(%L, %L)',
        '10000000-0000-4000-8000-000000000001', :'ip_hash'
    ),
    '01 anonymous quota use is denied'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'user_a', true);

select waytask_test.assert_true(
    (select allowed and not duplicate_request
     from public.consume_ai_recognition_quota(
         '10000000-0000-4000-8000-000000000001', :'ip_hash'
     )),
    '02 first authenticated request is allowed'
);
select waytask_test.assert_true(
    (select not allowed and duplicate_request
     from public.consume_ai_recognition_quota(
         '10000000-0000-4000-8000-000000000001', :'ip_hash'
     )),
    '03 replayed request ID is rejected without another provider call'
);

select public.consume_ai_recognition_quota(
    ('10000000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
    :'ip_hash'
) from generate_series(2, 6) value;
select waytask_test.assert_true(
    (select not allowed and not duplicate_request and retry_after_seconds > 0
     from public.consume_ai_recognition_quota(
         '10000000-0000-4000-8000-000000000007', :'ip_hash'
     )),
    '04 seventh request in one minute is rate limited'
);
select waytask_test.expect_failure(
    format(
        'select * from public.consume_ai_recognition_quota(%L, %L)',
        '10000000-0000-4000-8000-000000000008', 'raw-ip-address'
    ),
    '05 raw or malformed IP values are rejected'
);
select waytask_test.expect_failure(
    'select * from waytask_private.ai_recognition_requests',
    '06 authenticated clients cannot inspect quota records'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'user_b', true);
select waytask_test.assert_true(
    (select allowed and not duplicate_request
     from public.consume_ai_recognition_quota(
         '20000000-0000-4000-8000-000000000001', :'ip_hash'
     )),
    '07 user quota is owner scoped while the IP limit remains shared'
);

reset role;

select waytask_test.assert_true(
    not exists (
        select 1
        from waytask_private.ai_recognition_requests
        where request_id = '20000000-0000-4000-8000-000000009999'
    ),
    '08 stale quota records are removed globally without content retention'
);

do $$
declare
    passed integer;
begin
    select count(*) into passed from waytask_test.results;
    if passed <> 8 then
        raise exception 'expected 8 secure AI tests, got %', passed;
    end if;
    raise notice 'WT-032A.1 SECURE AI QUOTA TESTS PASSED: %', passed;
end;
$$;

rollback;
