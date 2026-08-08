\set ON_ERROR_STOP on
\set QUIET on

begin;

create schema waytask_identity_test;
create table waytask_identity_test.results (name text primary key);

create or replace function waytask_identity_test.pass(test_name text)
returns void language plpgsql security definer
set search_path = waytask_identity_test, pg_catalog
as $$
begin
    insert into waytask_identity_test.results(name) values (test_name);
end;
$$;

create or replace function waytask_identity_test.expect_failure(
    statement text,
    test_name text
) returns void language plpgsql security invoker
set search_path = waytask_identity_test, public, auth, pg_catalog
as $$
begin
    begin
        execute statement;
    exception when others then
        perform waytask_identity_test.pass(test_name);
        return;
    end;
    raise exception 'expected identity-input failure: %', test_name;
end;
$$;

grant usage on schema waytask_identity_test to service_role;
grant execute on all functions in schema waytask_identity_test to service_role;

\set owner_id 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'

insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, created_at, updated_at
) values (
    gen_random_uuid(), :'owner_id', 'authenticated', 'authenticated',
    'identity-input@local.invalid', '', now(), now()
);

set local role service_role;

insert into public.profiles (id, owner_user_id, display_name)
values (:'owner_id', :'owner_id', 'DROP TABLE shopping_lists;');
select waytask_identity_test.pass('01 SQL-like DROP text is accepted as data');
select waytask_identity_test.pass('02 SQL-like text did not execute')
where to_regclass('public.shopping_lists') is not null;

update public.profiles set display_name = ''' OR ''1''=''1'
where id = :'owner_id';
select waytask_identity_test.pass('03 quote injection text is accepted as data')
where (select display_name from public.profiles where id = :'owner_id') =
    ''' OR ''1''=''1';

update public.profiles set display_name = '"; DELETE FROM profiles; --'
where id = :'owner_id';
select waytask_identity_test.pass('04 DELETE-like text is stored literally')
where (select count(*) from public.profiles where id = :'owner_id') = 1;

update public.profiles set display_name = '<script>alert(1)</script>'
where id = :'owner_id';
select waytask_identity_test.pass('05 script-like text is stored literally')
where (select display_name from public.profiles where id = :'owner_id') =
    '<script>alert(1)</script>';

update public.profiles set display_name = '<img src=x onerror=alert(1)>'
where id = :'owner_id';
select waytask_identity_test.pass('06 image-markup-like text is stored literally')
where (select display_name from public.profiles where id = :'owner_id') =
    '<img src=x onerror=alert(1)>';

update public.profiles set display_name = '👻' where id = :'owner_id';
select waytask_identity_test.pass('07 single emoji is accepted');
update public.profiles set display_name = '👨‍👩‍👧‍👦' where id = :'owner_id';
select waytask_identity_test.pass('08 ZWJ family emoji is accepted');
update public.profiles set display_name = 'נועה לוי' where id = :'owner_id';
select waytask_identity_test.pass('09 Hebrew name is accepted');
update public.profiles set display_name = 'ليان أحمد' where id = :'owner_id';
select waytask_identity_test.pass('10 natural Arabic RTL name is accepted');
update public.profiles set display_name = 'José Álvarez' where id = :'owner_id';
select waytask_identity_test.pass('11 accented Latin is accepted');
update public.profiles set display_name = '王小明' where id = :'owner_id';
select waytask_identity_test.pass('12 CJK is accepted');

update public.profiles set display_name = U&'Jose\0301' where id = :'owner_id';
select waytask_identity_test.pass('13 combining sequence is normalized to NFC')
where (select display_name from public.profiles where id = :'owner_id') = 'José';
update public.profiles set display_name = '   Ada Lovelace   '
where id = :'owner_id';
select waytask_identity_test.pass('14 surrounding spaces are normalized')
where (select display_name from public.profiles where id = :'owner_id') =
    'Ada Lovelace';
update public.profiles set display_name = 'Ada    Lovelace'
where id = :'owner_id';
select waytask_identity_test.pass('15 repeated spaces are normalized')
where (select display_name from public.profiles where id = :'owner_id') =
    'Ada Lovelace';

select waytask_identity_test.expect_failure(
    format('update public.profiles set display_name = %L where id = %L',
           U&'A\200BB', :'owner_id'),
    '16 zero-width space is rejected'
);
select waytask_identity_test.expect_failure(
    format('update public.profiles set display_name = %L where id = %L',
           U&'A\202EB', :'owner_id'),
    '17 bidi override is rejected'
);
select waytask_identity_test.expect_failure(
    format('update public.profiles set display_name = %L where id = %L',
           E'A\nB', :'owner_id'),
    '18 newline is rejected'
);
select waytask_identity_test.expect_failure(
    format('update public.profiles set display_name = %L where id = %L',
           E'A\tB', :'owner_id'),
    '19 tab is rejected'
);
select waytask_identity_test.expect_failure(
    format('update public.profiles set display_name = %L where id = %L',
           'A' || chr(7) || 'B', :'owner_id'),
    '20 control character is rejected'
);
select waytask_identity_test.expect_failure(
    format('update public.profiles set display_name = %L where id = %L',
           repeat('a', 81), :'owner_id'),
    '21 extremely long display name is rejected'
);
update public.profiles set display_name = repeat('a', 80)
where id = :'owner_id';
select waytask_identity_test.pass('22 maximum-length display name is accepted');
select waytask_identity_test.expect_failure(
    format('update public.profiles set display_name = %L where id = %L',
           '', :'owner_id'),
    '23 empty input is rejected'
);
select waytask_identity_test.expect_failure(
    format('update public.profiles set display_name = %L where id = %L',
           '     ', :'owner_id'),
    '24 whitespace-only input is rejected'
);
select waytask_identity_test.expect_failure(
    $statement$select convert_from(decode('00', 'hex'), 'UTF8')$statement$,
    '25 null byte is rejected by PostgreSQL text boundary'
);
update public.profiles set display_name = null where id = :'owner_id';
select waytask_identity_test.pass('26 absent optional display name is accepted')
where (select display_name is null from public.profiles where id = :'owner_id');

reset role;

do $$
declare
    passed integer;
begin
    select count(*) into passed from waytask_identity_test.results;
    if passed <> 26 then
        raise exception 'expected 26 identity-input tests, got %', passed;
    end if;
    raise notice 'WT-032B IDENTITY INPUT TESTS PASSED: %', passed;
end;
$$;

rollback;
