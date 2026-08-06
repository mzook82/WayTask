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
    raise exception 'expected constraint failure: %', test_name;
end;
$$;

grant usage on schema waytask_test to service_role;
grant execute on all functions in schema waytask_test to service_role;

\set owner_id 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
\set list_id 'e1000000-0000-4000-8000-000000000001'
\set product_id 'e2000000-0000-4000-8000-000000000002'
\set device_id 'e3000000-0000-4000-8000-000000000003'

insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, created_at, updated_at
) values (
    gen_random_uuid(), :'owner_id', 'authenticated', 'authenticated',
    'constraints@local.invalid', '', now(), now()
);

set local role service_role;

insert into public.profiles (id, owner_user_id, display_name)
values (:'owner_id', :'owner_id', 'בדיקת משתמש');
select waytask_test.pass('01 valid Unicode profile is accepted');
insert into public.shopping_lists (id, owner_user_id, title)
values (:'list_id', :'owner_id', 'קניות ליום ו׳ 🛒');
select waytask_test.pass('02 valid Unicode list name is accepted');
insert into public.personal_products (
    id, owner_user_id, display_name, barcode, source
) values (:'product_id', :'owner_id', 'O''Brien חלב 😊', '7290000000000', 'barcode');
select waytask_test.pass('03 valid product and barcode are accepted');
insert into public.device_installations (
    id, owner_user_id, app_version, device_locale
) values (:'device_id', :'owner_id', '1.1.0', 'he-IL');
select waytask_test.pass('04 valid device installation is accepted');

select waytask_test.expect_failure(
    format('insert into public.shopping_lists (id, owner_user_id, title) '
           'values (gen_random_uuid(), %L, %L)', :'owner_id', '   '),
    '05 blank list name is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.shopping_lists (id, owner_user_id, title) '
           'values (gen_random_uuid(), %L, %L)', :'owner_id', repeat('a', 121)),
    '06 excessive list name is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.shopping_lists (id, owner_user_id, title) '
           'values (gen_random_uuid(), %L, %L)',
           :'owner_id', 'ok' || chr(7)),
    '07 list control characters are rejected'
);
select waytask_test.expect_failure(
    format('insert into public.personal_products '
           '(id, owner_user_id, display_name, source) '
           'values (gen_random_uuid(), %L, %L, %L)',
           :'owner_id', repeat('א', 201), 'manual'),
    '08 excessive product display name is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.personal_products '
           '(id, owner_user_id, display_name, barcode, source) '
           'values (gen_random_uuid(), %L, %L, %L, %L)',
           :'owner_id', 'bad barcode', 'ABC-123', 'barcode'),
    '09 malformed barcode is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.personal_products '
           '(id, owner_user_id, display_name, source) '
           'values (gen_random_uuid(), %L, %L, %L)',
           :'owner_id', 'bad source', 'shell'),
    '10 unknown product source is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.personal_products '
           '(id, owner_user_id, display_name, source, library_lifecycle) '
           'values (gen_random_uuid(), %L, %L, %L, %L)',
           :'owner_id', 'removed without date', 'manual', 'removed'),
    '11 inconsistent removal state is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.personal_products '
           '(id, owner_user_id, display_name, source, image_object_path, '
           'image_mime_type, image_byte_count, image_pixel_width, image_pixel_height) '
           'values (gen_random_uuid(), %L, %L, %L, %L, %L, 100, 10, 10)',
           :'owner_id', 'bad image', 'manual',
           :'owner_id' || '/item.svg', 'image/svg+xml'),
    '12 disallowed image MIME type is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.personal_products '
           '(id, owner_user_id, display_name, source, image_object_path, '
           'image_mime_type, image_byte_count, image_pixel_width, image_pixel_height) '
           'values (gen_random_uuid(), %L, %L, %L, %L, %L, 100, 10, 10)',
           :'owner_id', 'bad image path', 'manual',
           'another-owner/item.jpg', 'image/jpeg'),
    '13 image object path must be owner-prefixed'
);
select waytask_test.expect_failure(
    format('insert into public.shopping_list_entries '
           '(id, owner_user_id, shopping_list_id, personal_product_id, quantity) '
           'values (gen_random_uuid(), %L, %L, %L, 0)',
           :'owner_id', :'list_id', :'product_id'),
    '14 zero quantity is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.shopping_list_entries '
           '(id, owner_user_id, shopping_list_id, personal_product_id, quantity) '
           'values (gen_random_uuid(), %L, %L, %L, 1000000)',
           :'owner_id', :'list_id', :'product_id'),
    '15 excessive quantity is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.shopping_list_entries '
           '(id, owner_user_id, shopping_list_id, personal_product_id, quantity, unit) '
           'values (gen_random_uuid(), %L, %L, %L, 1, %L)',
           :'owner_id', :'list_id', :'product_id', 'bucket'),
    '16 unknown quantity unit is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.shopping_list_entries '
           '(id, owner_user_id, shopping_list_id, personal_product_id, quantity, note) '
           'values (gen_random_uuid(), %L, %L, %L, 1, %L)',
           :'owner_id', :'list_id', :'product_id', repeat('n', 2001)),
    '17 excessive entry note is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.shopping_list_entries '
           '(id, owner_user_id, shopping_list_id, personal_product_id, quantity, '
           'lifecycle) values (gen_random_uuid(), %L, %L, %L, 1, %L)',
           :'owner_id', :'list_id', :'product_id', 'resolved'),
    '18 resolved entry without resolution metadata is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.saved_stores '
           '(id, owner_user_id, display_name, latitude, longitude) '
           'values (gen_random_uuid(), %L, %L, 91, 35)',
           :'owner_id', 'outside earth'),
    '19 invalid latitude is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.saved_stores '
           '(id, owner_user_id, display_name, latitude, longitude, website_url) '
           'values (gen_random_uuid(), %L, %L, 31.8, 35.2, %L)',
           :'owner_id', 'unsafe URL', 'javascript:alert(1)'),
    '20 non-HTTP store URL is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.saved_stores '
           '(id, owner_user_id, display_name, latitude, longitude, radius_meters) '
           'values (gen_random_uuid(), %L, %L, 31.8, 35.2, 5001)',
           :'owner_id', 'huge radius'),
    '21 excessive store radius is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.user_preferences '
           '(owner_user_id, preferred_locale) values (%L, %L)',
           :'owner_id', 'xx-INVALID'),
    '22 unsupported locale is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.user_preferences '
           '(owner_user_id, time_zone) values (%L, %L)',
           :'owner_id', 'not a timezone'),
    '23 malformed timezone is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.notification_preferences '
           '(owner_user_id, quiet_hours_enabled) values (%L, true)',
           :'owner_id'),
    '24 incomplete quiet hours are rejected'
);
select waytask_test.expect_failure(
    format('insert into public.notification_preferences '
           '(owner_user_id, default_radius_meters) values (%L, 99)',
           :'owner_id'),
    '25 unsafe notification radius is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.device_installations '
           '(id, owner_user_id, app_version, device_locale) '
           'values (gen_random_uuid(), %L, %L, %L)',
           :'owner_id', 'version-latest', 'he-IL'),
    '26 malformed app version is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.device_installations '
           '(id, owner_user_id, app_version, device_locale, push_token_sha256) '
           'values (gen_random_uuid(), %L, %L, %L, %L)',
           :'owner_id', '1.1.0', 'he-IL', 'raw-push-token'),
    '27 raw push token shape is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.sync_mutations '
           '(id, owner_user_id, device_installation_id, idempotency_key, '
           'mutation_type, payload_sha256, record_count, payload_bytes) '
           'values (gen_random_uuid(), %L, %L, %L, %L, %L, 501, 10)',
           :'owner_id', :'device_id', 'batch-0000000000001', 'upsert', repeat('a', 64)),
    '28 batch larger than 500 records is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.sync_mutations '
           '(id, owner_user_id, device_installation_id, idempotency_key, '
           'mutation_type, payload_sha256, record_count, payload_bytes) '
           'values (gen_random_uuid(), %L, %L, %L, %L, %L, 1, 1048577)',
           :'owner_id', :'device_id', 'batch-0000000000002', 'upsert', repeat('b', 64)),
    '29 payload larger than one MiB is rejected'
);
select waytask_test.expect_failure(
    format('insert into public.sync_mutations '
           '(id, owner_user_id, device_installation_id, idempotency_key, '
           'mutation_type, payload_sha256, record_count, payload_bytes) '
           'values (gen_random_uuid(), %L, %L, %L, %L, %L, 1, 10)',
           :'owner_id', :'device_id', 'short', 'upsert', 'not-a-hash'),
    '30 malformed mutation identity and hash are rejected'
);

reset role;

do $$
declare
    passed integer;
begin
    select count(*) into passed from waytask_test.results;
    if passed <> 30 then
        raise exception 'expected 30 constraint tests, got %', passed;
    end if;
    raise notice 'WT-032A CONSTRAINT TESTS PASSED: %', passed;
end;
$$;

rollback;
