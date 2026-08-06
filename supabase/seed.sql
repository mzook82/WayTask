-- Intentionally contains no Auth users and no private user data.
-- Local database tests create isolated identities inside rollback transactions.

insert into public.catalog_releases (
    id,
    release_name,
    schema_version,
    content_sha256,
    published_at
) values (
    '00000000-0000-0000-0000-000000000001',
    'local-empty-fixture',
    1,
    repeat('0', 64),
    now()
) on conflict (id) do nothing;
