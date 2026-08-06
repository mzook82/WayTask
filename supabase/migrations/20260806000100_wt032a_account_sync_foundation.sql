-- WT-032A: local/staging account and synchronization foundation.
-- Production rollout is intentionally a separate, explicit operation.

create extension if not exists pgcrypto;

create schema if not exists waytask_private;
create schema if not exists waytask_admin;

revoke all on schema waytask_private from public, anon, authenticated;
revoke all on schema waytask_admin from public, anon, authenticated;

create or replace function waytask_private.valid_user_text(
    value text,
    minimum_length integer,
    maximum_length integer,
    allows_multiline boolean default false
) returns boolean
language sql
immutable
set search_path = ''
as $$
    select value is not null
       and char_length(btrim(value)) between minimum_length and maximum_length
       and case
            when allows_multiline then
                regexp_replace(value, E'[\t\n\r]', '', 'g') !~ '[[:cntrl:]]'
            else value !~ '[[:cntrl:]]'
           end;
$$;

create or replace function waytask_private.valid_optional_user_text(
    value text,
    maximum_length integer,
    allows_multiline boolean default false
) returns boolean
language sql
immutable
set search_path = ''
as $$
    select value is null or (
        char_length(value) <= maximum_length
        and case
             when allows_multiline then
                 regexp_replace(value, E'[\t\n\r]', '', 'g') !~ '[[:cntrl:]]'
             else value !~ '[[:cntrl:]]'
            end
    );
$$;

create or replace function waytask_private.valid_http_url(value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
    select value is null or (
        octet_length(value) <= 2048
        and value ~* '^https?://[^[:space:]]+$'
        and value !~* '^https?://[^/]+@'
        and value !~ '[[:cntrl:]]'
    );
$$;

create or replace function waytask_private.prepare_private_row()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        new.revision := 1;
        new.created_at := coalesce(new.created_at, clock_timestamp());
        new.updated_at := coalesce(new.updated_at, new.created_at);
        return new;
    end if;

    if new.id is distinct from old.id then
        raise exception 'immutable row identity' using errcode = '23514';
    end if;
    if new.owner_user_id is distinct from old.owner_user_id then
        raise exception 'immutable row ownership' using errcode = '42501';
    end if;
    if new.created_at is distinct from old.created_at then
        raise exception 'immutable creation timestamp' using errcode = '23514';
    end if;
    new.revision := old.revision + 1;
    new.updated_at := clock_timestamp();
    return new;
end;
$$;

create or replace function waytask_private.prepare_shared_row()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
    if tg_op = 'INSERT' then
        new.revision := 1;
        new.created_at := coalesce(new.created_at, clock_timestamp());
        new.updated_at := coalesce(new.updated_at, new.created_at);
        return new;
    end if;
    if new.id is distinct from old.id or
       new.created_at is distinct from old.created_at then
        raise exception 'immutable shared identity' using errcode = '23514';
    end if;
    new.revision := old.revision + 1;
    new.updated_at := clock_timestamp();
    return new;
end;
$$;

create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    owner_user_id uuid not null unique references auth.users(id) on delete cascade,
    display_name text,
    locale text not null default 'he-IL',
    revision bigint not null default 1 check (revision > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint profiles_identity_is_owner check (id = owner_user_id),
    constraint profiles_display_name_valid check (
        display_name is null or waytask_private.valid_user_text(
            display_name, 1, 120, false
        )
    ),
    constraint profiles_locale_allowed check (
        locale in ('he', 'he-IL', 'en', 'en-US', 'ar', 'ar-IL')
    ),
    constraint profiles_deleted_time_valid check (
        deleted_at is null or deleted_at >= created_at
    ),
    constraint profiles_updated_time_valid check (updated_at >= created_at)
);

create table public.user_preferences (
    id uuid primary key default gen_random_uuid(),
    owner_user_id uuid not null unique references auth.users(id) on delete cascade,
    preferred_locale text not null default 'he-IL',
    measurement_system text not null default 'metric',
    preferred_currency text,
    time_zone text not null default 'UTC',
    location_features_opt_in boolean not null default false,
    revision bigint not null default 1 check (revision > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint user_preferences_locale_allowed check (
        preferred_locale in ('he', 'he-IL', 'en', 'en-US', 'ar', 'ar-IL')
    ),
    constraint user_preferences_measurement_allowed check (
        measurement_system in ('metric', 'imperial')
    ),
    constraint user_preferences_currency_valid check (
        preferred_currency is null or preferred_currency ~ '^[A-Z]{3}$'
    ),
    constraint user_preferences_time_zone_valid check (
        char_length(time_zone) between 1 and 64
        and time_zone ~ '^(UTC|[A-Za-z_+-]+(/[A-Za-z0-9_+-]+)+)$'
    ),
    constraint user_preferences_deleted_time_valid check (
        deleted_at is null or deleted_at >= created_at
    ),
    constraint user_preferences_updated_time_valid check (updated_at >= created_at)
);

create table public.shopping_lists (
    id uuid primary key,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    title text not null,
    purpose text not null default 'shopping',
    revision bigint not null default 1 check (revision > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint shopping_lists_owner_identity unique (id, owner_user_id),
    constraint shopping_lists_title_valid check (
        waytask_private.valid_user_text(title, 1, 120, false)
    ),
    constraint shopping_lists_purpose_allowed check (
        purpose in ('shopping', 'weekly', 'recent', 'completed', 'custom')
    ),
    constraint shopping_lists_deleted_time_valid check (
        deleted_at is null or deleted_at >= created_at
    ),
    constraint shopping_lists_updated_time_valid check (updated_at >= created_at)
);

create table public.personal_products (
    id uuid primary key,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    display_name text not null,
    brand text,
    category text,
    barcode text,
    source text not null,
    catalog_product_id text,
    library_lifecycle text not null default 'active',
    removed_at timestamptz,
    image_object_path text,
    image_mime_type text,
    image_byte_count integer,
    image_pixel_width integer,
    image_pixel_height integer,
    revision bigint not null default 1 check (revision > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint personal_products_owner_identity unique (id, owner_user_id),
    constraint personal_products_name_valid check (
        waytask_private.valid_user_text(display_name, 1, 200, false)
    ),
    constraint personal_products_brand_valid check (
        waytask_private.valid_optional_user_text(brand, 160, false)
    ),
    constraint personal_products_category_valid check (
        waytask_private.valid_optional_user_text(category, 160, false)
    ),
    constraint personal_products_barcode_valid check (
        barcode is null or barcode ~ '^[0-9]{6,32}$'
    ),
    constraint personal_products_source_allowed check (
        source in (
            'manual', 'barcode', 'camera', 'ai', 'discover', 'catalog',
            'imported', 'camera_reviewed', 'ai_reviewed'
        )
    ),
    constraint personal_products_catalog_id_valid check (
        catalog_product_id is null or (
            char_length(catalog_product_id) between 1 and 128
            and catalog_product_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]*$'
        )
    ),
    constraint personal_products_lifecycle_allowed check (
        library_lifecycle in ('active', 'removed')
    ),
    constraint personal_products_removal_consistent check (
        (library_lifecycle = 'active' and removed_at is null)
        or (library_lifecycle = 'removed' and removed_at is not null)
    ),
    constraint personal_products_image_path_valid check (
        image_object_path is null or (
            char_length(image_object_path) between 1 and 512
            and image_object_path like owner_user_id::text || '/%'
            and image_object_path ~ '^[A-Za-z0-9][A-Za-z0-9/_.-]*$'
            and position('..' in image_object_path) = 0
        )
    ),
    constraint personal_products_image_metadata_consistent check (
        (image_object_path is null and image_mime_type is null
            and image_byte_count is null and image_pixel_width is null
            and image_pixel_height is null)
        or (
            image_object_path is not null
            and image_mime_type in (
                'image/jpeg', 'image/png', 'image/heic', 'image/webp'
            )
            and image_byte_count between 1 and 10485760
            and image_pixel_width between 1 and 12000
            and image_pixel_height between 1 and 12000
        )
    ),
    constraint personal_products_deleted_time_valid check (
        deleted_at is null or deleted_at >= created_at
    ),
    constraint personal_products_updated_time_valid check (updated_at >= created_at)
);

create table public.shopping_list_entries (
    id uuid primary key,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    shopping_list_id uuid not null,
    personal_product_id uuid not null,
    quantity numeric(12, 3) not null default 1,
    unit text,
    note text,
    lifecycle text not null default 'needed',
    resolution_reason text,
    resolution_effective_at timestamptz,
    resolution_provenance text,
    resolution_command_id uuid,
    resolution_session_id uuid,
    resolution_session_line_id uuid,
    sort_order numeric(18, 6) not null default 0,
    revision bigint not null default 1 check (revision > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint shopping_list_entries_owner_identity unique (id, owner_user_id),
    constraint shopping_list_entries_list_owner_fk foreign key (
        shopping_list_id, owner_user_id
    ) references public.shopping_lists(id, owner_user_id) on delete restrict,
    constraint shopping_list_entries_product_owner_fk foreign key (
        personal_product_id, owner_user_id
    ) references public.personal_products(id, owner_user_id) on delete restrict,
    constraint shopping_list_entries_quantity_valid check (
        quantity between 0.001 and 999999.999
    ),
    constraint shopping_list_entries_unit_allowed check (
        unit is null or unit in ('count', 'kg', 'g', 'l', 'ml', 'package')
    ),
    constraint shopping_list_entries_note_valid check (
        waytask_private.valid_optional_user_text(note, 2000, true)
    ),
    constraint shopping_list_entries_lifecycle_allowed check (
        lifecycle in ('needed', 'resolved')
    ),
    constraint shopping_list_entries_resolution_allowed check (
        resolution_reason is null or resolution_reason in (
            'purchased', 'already_have', 'no_longer_needed', 'legacy_unknown'
        )
    ),
    constraint shopping_list_entries_provenance_allowed check (
        resolution_provenance is null or resolution_provenance in (
            'user_command', 'session_finish', 'legacy_migration'
        )
    ),
    constraint shopping_list_entries_resolution_consistent check (
        (lifecycle = 'needed' and resolution_reason is null
            and resolution_effective_at is null
            and resolution_provenance is null
            and resolution_command_id is null
            and resolution_session_id is null
            and resolution_session_line_id is null)
        or (
            lifecycle = 'resolved'
            and resolution_reason is not null
            and resolution_effective_at is not null
            and resolution_provenance is not null
        )
    ),
    constraint shopping_list_entries_sort_order_valid check (
        sort_order between -1000000000 and 1000000000
    ),
    constraint shopping_list_entries_deleted_time_valid check (
        deleted_at is null or deleted_at >= created_at
    ),
    constraint shopping_list_entries_updated_time_valid check (
        updated_at >= created_at
    )
);

create table public.saved_stores (
    id uuid primary key,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    display_name text not null,
    latitude numeric(9, 6) not null,
    longitude numeric(9, 6) not null,
    radius_meters integer not null default 200,
    store_category text,
    address_text text,
    notes text,
    source text not null default 'user_generated',
    external_store_reference text,
    website_url text,
    precise_location_opt_in boolean not null default true,
    revision bigint not null default 1 check (revision > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint saved_stores_owner_identity unique (id, owner_user_id),
    constraint saved_stores_name_valid check (
        waytask_private.valid_user_text(display_name, 1, 200, false)
    ),
    constraint saved_stores_coordinates_valid check (
        latitude between -90 and 90 and longitude between -180 and 180
    ),
    constraint saved_stores_radius_valid check (
        radius_meters between 50 and 5000
    ),
    constraint saved_stores_category_valid check (
        waytask_private.valid_optional_user_text(store_category, 80, false)
    ),
    constraint saved_stores_address_valid check (
        waytask_private.valid_optional_user_text(address_text, 500, true)
    ),
    constraint saved_stores_notes_valid check (
        waytask_private.valid_optional_user_text(notes, 2000, true)
    ),
    constraint saved_stores_source_allowed check (
        source in ('user_generated', 'apple_maps', 'imported')
    ),
    constraint saved_stores_external_reference_valid check (
        waytask_private.valid_optional_user_text(
            external_store_reference, 256, false
        )
    ),
    constraint saved_stores_website_valid check (
        waytask_private.valid_http_url(website_url)
    ),
    constraint saved_stores_deleted_time_valid check (
        deleted_at is null or deleted_at >= created_at
    ),
    constraint saved_stores_updated_time_valid check (updated_at >= created_at)
);

create table public.notification_preferences (
    id uuid primary key default gen_random_uuid(),
    owner_user_id uuid not null unique references auth.users(id) on delete cascade,
    nearby_shopping_enabled boolean not null default false,
    quiet_hours_enabled boolean not null default false,
    quiet_hours_start time,
    quiet_hours_end time,
    time_zone text not null default 'UTC',
    default_radius_meters integer not null default 200,
    revision bigint not null default 1 check (revision > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint notification_preferences_quiet_hours_consistent check (
        (quiet_hours_enabled and quiet_hours_start is not null
            and quiet_hours_end is not null)
        or (not quiet_hours_enabled and quiet_hours_start is null
            and quiet_hours_end is null)
    ),
    constraint notification_preferences_time_zone_valid check (
        char_length(time_zone) between 1 and 64
        and time_zone ~ '^(UTC|[A-Za-z_+-]+(/[A-Za-z0-9_+-]+)+)$'
    ),
    constraint notification_preferences_radius_valid check (
        default_radius_meters between 100 and 1000
    ),
    constraint notification_preferences_deleted_time_valid check (
        deleted_at is null or deleted_at >= created_at
    ),
    constraint notification_preferences_updated_time_valid check (
        updated_at >= created_at
    )
);

create table public.device_installations (
    id uuid primary key,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    platform text not null default 'ios',
    app_version text not null,
    device_locale text not null,
    push_token_sha256 text,
    last_seen_at timestamptz not null default now(),
    revoked_at timestamptz,
    revision bigint not null default 1 check (revision > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint device_installations_owner_identity unique (id, owner_user_id),
    constraint device_installations_platform_allowed check (platform = 'ios'),
    constraint device_installations_app_version_valid check (
        app_version ~ '^[0-9]+\.[0-9]+\.[0-9]+([+-][A-Za-z0-9.-]+)?$'
        and char_length(app_version) <= 64
    ),
    constraint device_installations_locale_allowed check (
        device_locale in ('he', 'he-IL', 'en', 'en-US', 'ar', 'ar-IL')
    ),
    constraint device_installations_push_hash_valid check (
        push_token_sha256 is null or push_token_sha256 ~ '^[0-9a-f]{64}$'
    ),
    constraint device_installations_revocation_valid check (
        revoked_at is null or revoked_at >= created_at
    ),
    constraint device_installations_deleted_time_valid check (
        deleted_at is null or deleted_at >= created_at
    ),
    constraint device_installations_updated_time_valid check (
        updated_at >= created_at
    )
);

create table public.sync_mutations (
    id uuid primary key,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    device_installation_id uuid not null,
    idempotency_key text not null,
    mutation_type text not null,
    payload_sha256 text not null,
    record_count integer not null,
    payload_bytes integer not null,
    status text not null default 'accepted',
    applied_at timestamptz,
    failure_code text,
    revision bigint not null default 1 check (revision > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint sync_mutations_owner_identity unique (id, owner_user_id),
    constraint sync_mutations_installation_owner_fk foreign key (
        device_installation_id, owner_user_id
    ) references public.device_installations(id, owner_user_id) on delete restrict,
    constraint sync_mutations_idempotency_unique unique (
        owner_user_id, device_installation_id, idempotency_key
    ),
    constraint sync_mutations_idempotency_key_valid check (
        char_length(idempotency_key) between 16 and 128
        and idempotency_key ~ '^[A-Za-z0-9._:-]+$'
    ),
    constraint sync_mutations_type_allowed check (
        mutation_type in (
            'initial_migration', 'upsert', 'tombstone',
            'preference_update', 'device_registration',
            'account_deletion_request', 'export_request'
        )
    ),
    constraint sync_mutations_payload_hash_valid check (
        payload_sha256 ~ '^[0-9a-f]{64}$'
    ),
    constraint sync_mutations_batch_valid check (
        record_count between 1 and 500
        and payload_bytes between 1 and 1048576
    ),
    constraint sync_mutations_status_allowed check (
        status in ('accepted', 'applied', 'rejected')
    ),
    constraint sync_mutations_status_consistent check (
        (status = 'accepted' and applied_at is null and failure_code is null)
        or (status = 'applied' and applied_at is not null and failure_code is null)
        or (status = 'rejected' and applied_at is null and failure_code is not null)
    ),
    constraint sync_mutations_failure_code_valid check (
        failure_code is null or (
            char_length(failure_code) between 1 and 64
            and failure_code ~ '^[A-Z0-9_-]+$'
        )
    ),
    constraint sync_mutations_deleted_time_valid check (
        deleted_at is null or deleted_at >= created_at
    ),
    constraint sync_mutations_updated_time_valid check (updated_at >= created_at)
);

create table public.catalog_releases (
    id uuid primary key,
    release_name text not null unique,
    schema_version integer not null check (schema_version > 0),
    content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
    published_at timestamptz not null,
    withdrawn_at timestamptz,
    revision bigint not null default 1 check (revision > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint catalog_releases_name_valid check (
        release_name ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'
    ),
    constraint catalog_releases_withdrawal_valid check (
        withdrawn_at is null or withdrawn_at >= published_at
    ),
    constraint catalog_releases_updated_time_valid check (updated_at >= created_at)
);

create table waytask_admin.migration_audit (
    id uuid primary key default gen_random_uuid(),
    migration_name text not null,
    applied_at timestamptz not null default now(),
    schema_digest text not null
);

revoke all on table waytask_admin.migration_audit from public, anon, authenticated;

create index profiles_owner_updated_idx
    on public.profiles (owner_user_id, updated_at, id);
create index user_preferences_owner_updated_idx
    on public.user_preferences (owner_user_id, updated_at, id);
create index shopping_lists_owner_sync_idx
    on public.shopping_lists (owner_user_id, updated_at, id);
create index shopping_lists_owner_deleted_idx
    on public.shopping_lists (owner_user_id, deleted_at) where deleted_at is not null;
create index personal_products_owner_sync_idx
    on public.personal_products (owner_user_id, updated_at, id);
create index personal_products_owner_catalog_idx
    on public.personal_products (owner_user_id, catalog_product_id)
    where catalog_product_id is not null;
create index personal_products_owner_barcode_idx
    on public.personal_products (owner_user_id, barcode) where barcode is not null;
create index shopping_list_entries_owner_sync_idx
    on public.shopping_list_entries (owner_user_id, updated_at, id);
create index shopping_list_entries_list_idx
    on public.shopping_list_entries (owner_user_id, shopping_list_id, sort_order);
create index saved_stores_owner_sync_idx
    on public.saved_stores (owner_user_id, updated_at, id);
create index notification_preferences_owner_updated_idx
    on public.notification_preferences (owner_user_id, updated_at, id);
create index device_installations_owner_seen_idx
    on public.device_installations (owner_user_id, last_seen_at desc);
create index sync_mutations_owner_created_idx
    on public.sync_mutations (owner_user_id, created_at, id);

create trigger profiles_prepare_row
before insert or update on public.profiles
for each row execute function waytask_private.prepare_private_row();
create trigger user_preferences_prepare_row
before insert or update on public.user_preferences
for each row execute function waytask_private.prepare_private_row();
create trigger shopping_lists_prepare_row
before insert or update on public.shopping_lists
for each row execute function waytask_private.prepare_private_row();
create trigger personal_products_prepare_row
before insert or update on public.personal_products
for each row execute function waytask_private.prepare_private_row();
create trigger shopping_list_entries_prepare_row
before insert or update on public.shopping_list_entries
for each row execute function waytask_private.prepare_private_row();
create trigger saved_stores_prepare_row
before insert or update on public.saved_stores
for each row execute function waytask_private.prepare_private_row();
create trigger notification_preferences_prepare_row
before insert or update on public.notification_preferences
for each row execute function waytask_private.prepare_private_row();
create trigger device_installations_prepare_row
before insert or update on public.device_installations
for each row execute function waytask_private.prepare_private_row();
create trigger sync_mutations_prepare_row
before insert or update on public.sync_mutations
for each row execute function waytask_private.prepare_private_row();
create trigger catalog_releases_prepare_row
before insert or update on public.catalog_releases
for each row execute function waytask_private.prepare_shared_row();

alter table public.profiles enable row level security;
alter table public.profiles force row level security;
alter table public.user_preferences enable row level security;
alter table public.user_preferences force row level security;
alter table public.shopping_lists enable row level security;
alter table public.shopping_lists force row level security;
alter table public.personal_products enable row level security;
alter table public.personal_products force row level security;
alter table public.shopping_list_entries enable row level security;
alter table public.shopping_list_entries force row level security;
alter table public.saved_stores enable row level security;
alter table public.saved_stores force row level security;
alter table public.notification_preferences enable row level security;
alter table public.notification_preferences force row level security;
alter table public.device_installations enable row level security;
alter table public.device_installations force row level security;
alter table public.sync_mutations enable row level security;
alter table public.sync_mutations force row level security;
alter table public.catalog_releases enable row level security;
alter table public.catalog_releases force row level security;

grant select, insert, update, delete on table
    public.profiles,
    public.user_preferences,
    public.shopping_lists,
    public.personal_products,
    public.shopping_list_entries,
    public.saved_stores,
    public.notification_preferences,
    public.device_installations,
    public.sync_mutations
to anon, authenticated;

grant select, insert, update, delete on table public.catalog_releases
to anon, authenticated;

grant all on table
    public.profiles,
    public.user_preferences,
    public.shopping_lists,
    public.personal_products,
    public.shopping_list_entries,
    public.saved_stores,
    public.notification_preferences,
    public.device_installations,
    public.sync_mutations,
    public.catalog_releases
to service_role;

-- Profiles: owner select/insert/update; hard delete is server-orchestrated only.
create policy profiles_owner_select on public.profiles
for select to authenticated using (auth.uid() = owner_user_id);
create policy profiles_owner_insert on public.profiles
for insert to authenticated with check (
    auth.uid() = owner_user_id and id = auth.uid()
);
create policy profiles_owner_update on public.profiles
for update to authenticated using (auth.uid() = owner_user_id)
with check (auth.uid() = owner_user_id and id = auth.uid());
create policy profiles_client_delete_denied on public.profiles
for delete to anon, authenticated using (false);

-- Preferences: owner select/insert/update; hard delete is denied.
create policy user_preferences_owner_select on public.user_preferences
for select to authenticated using (auth.uid() = owner_user_id);
create policy user_preferences_owner_insert on public.user_preferences
for insert to authenticated with check (auth.uid() = owner_user_id);
create policy user_preferences_owner_update on public.user_preferences
for update to authenticated using (auth.uid() = owner_user_id)
with check (auth.uid() = owner_user_id);
create policy user_preferences_client_delete_denied on public.user_preferences
for delete to anon, authenticated using (false);

-- Lists: owner select/insert/update; tombstones replace client hard deletion.
create policy shopping_lists_owner_select on public.shopping_lists
for select to authenticated using (auth.uid() = owner_user_id);
create policy shopping_lists_owner_insert on public.shopping_lists
for insert to authenticated with check (auth.uid() = owner_user_id);
create policy shopping_lists_owner_update on public.shopping_lists
for update to authenticated using (auth.uid() = owner_user_id)
with check (auth.uid() = owner_user_id);
create policy shopping_lists_client_delete_denied on public.shopping_lists
for delete to anon, authenticated using (false);

-- Personal products: owner select/insert/update; tombstones replace hard delete.
create policy personal_products_owner_select on public.personal_products
for select to authenticated using (auth.uid() = owner_user_id);
create policy personal_products_owner_insert on public.personal_products
for insert to authenticated with check (auth.uid() = owner_user_id);
create policy personal_products_owner_update on public.personal_products
for update to authenticated using (auth.uid() = owner_user_id)
with check (auth.uid() = owner_user_id);
create policy personal_products_client_delete_denied on public.personal_products
for delete to anon, authenticated using (false);

-- Entries require both row ownership and an owner-scoped parent list.
create policy shopping_list_entries_owner_select on public.shopping_list_entries
for select to authenticated using (
    auth.uid() = owner_user_id
    and exists (
        select 1 from public.shopping_lists parent
        where parent.id = shopping_list_id
          and parent.owner_user_id = auth.uid()
    )
);
create policy shopping_list_entries_owner_insert on public.shopping_list_entries
for insert to authenticated with check (
    auth.uid() = owner_user_id
    and exists (
        select 1 from public.shopping_lists parent
        where parent.id = shopping_list_id
          and parent.owner_user_id = auth.uid()
    )
    and exists (
        select 1 from public.personal_products product
        where product.id = personal_product_id
          and product.owner_user_id = auth.uid()
    )
);
create policy shopping_list_entries_owner_update on public.shopping_list_entries
for update to authenticated using (
    auth.uid() = owner_user_id
    and exists (
        select 1 from public.shopping_lists parent
        where parent.id = shopping_list_id
          and parent.owner_user_id = auth.uid()
    )
) with check (
    auth.uid() = owner_user_id
    and exists (
        select 1 from public.shopping_lists parent
        where parent.id = shopping_list_id
          and parent.owner_user_id = auth.uid()
    )
    and exists (
        select 1 from public.personal_products product
        where product.id = personal_product_id
          and product.owner_user_id = auth.uid()
    )
);
create policy shopping_list_entries_client_delete_denied
on public.shopping_list_entries
for delete to anon, authenticated using (false);

-- Saved stores include sensitive coordinates and are private owner-only rows.
create policy saved_stores_owner_select on public.saved_stores
for select to authenticated using (auth.uid() = owner_user_id);
create policy saved_stores_owner_insert on public.saved_stores
for insert to authenticated with check (auth.uid() = owner_user_id);
create policy saved_stores_owner_update on public.saved_stores
for update to authenticated using (auth.uid() = owner_user_id)
with check (auth.uid() = owner_user_id);
create policy saved_stores_client_delete_denied on public.saved_stores
for delete to anon, authenticated using (false);

create policy notification_preferences_owner_select
on public.notification_preferences
for select to authenticated using (auth.uid() = owner_user_id);
create policy notification_preferences_owner_insert
on public.notification_preferences
for insert to authenticated with check (auth.uid() = owner_user_id);
create policy notification_preferences_owner_update
on public.notification_preferences
for update to authenticated using (auth.uid() = owner_user_id)
with check (auth.uid() = owner_user_id);
create policy notification_preferences_client_delete_denied
on public.notification_preferences
for delete to anon, authenticated using (false);

create policy device_installations_owner_select on public.device_installations
for select to authenticated using (auth.uid() = owner_user_id);
create policy device_installations_owner_insert on public.device_installations
for insert to authenticated with check (auth.uid() = owner_user_id);
create policy device_installations_owner_update on public.device_installations
for update to authenticated using (auth.uid() = owner_user_id)
with check (auth.uid() = owner_user_id);
create policy device_installations_client_delete_denied
on public.device_installations
for delete to anon, authenticated using (false);

-- Mutation inserts are immutable receipts. The owner and device must agree.
create policy sync_mutations_owner_select on public.sync_mutations
for select to authenticated using (auth.uid() = owner_user_id);
create policy sync_mutations_owner_insert on public.sync_mutations
for insert to authenticated with check (
    auth.uid() = owner_user_id
    and status = 'accepted'
    and applied_at is null
    and failure_code is null
    and exists (
        select 1 from public.device_installations device
        where device.id = device_installation_id
          and device.owner_user_id = auth.uid()
          and device.revoked_at is null
    )
);
create policy sync_mutations_client_update_denied on public.sync_mutations
for update to anon, authenticated using (false) with check (false);
create policy sync_mutations_client_delete_denied on public.sync_mutations
for delete to anon, authenticated using (false);

-- Shared release metadata is read-only to clients; catalog records remain bundled.
create policy catalog_releases_public_select on public.catalog_releases
for select to anon, authenticated using (
    published_at <= now() and withdrawn_at is null
);
create policy catalog_releases_client_insert_denied on public.catalog_releases
for insert to anon, authenticated with check (false);
create policy catalog_releases_client_update_denied on public.catalog_releases
for update to anon, authenticated using (false) with check (false);
create policy catalog_releases_client_delete_denied on public.catalog_releases
for delete to anon, authenticated using (false);

comment on schema waytask_admin is
    'Not exposed through the Data API; trusted operations only.';
comment on table public.catalog_releases is
    'Read-only release metadata; the product catalog itself is not user-owned.';
comment on column public.saved_stores.latitude is
    'Sensitive precise location; sync only after explicit account migration consent.';
comment on column public.saved_stores.longitude is
    'Sensitive precise location; sync only after explicit account migration consent.';
