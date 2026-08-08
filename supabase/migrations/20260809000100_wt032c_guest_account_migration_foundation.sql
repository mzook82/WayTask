-- WT-032C: fail-closed Guest -> Account migration foundation.
-- This migration only creates inert server authority. Activation requires a
-- later, explicit Staging-only control change after the real signed A/B gate.

create table waytask_private.initial_migration_control (
    singleton boolean primary key default true check (singleton),
    environment text not null default 'staging'
        check (environment = 'staging'),
    deployment_approved boolean not null default false,
    enabled boolean not null default false,
    endpoint_ready boolean not null default false,
    signed_session_ab_gate_passed boolean not null default false,
    session_recovery_gate_passed boolean not null default false,
    security_blockers_clear boolean not null default false,
    approved_format_version integer not null default 1
        check (approved_format_version = 1),
    updated_at timestamptz not null default now()
);

insert into waytask_private.initial_migration_control(singleton)
values (true)
on conflict (singleton) do nothing;

revoke all on table waytask_private.initial_migration_control
from public, anon, authenticated;

create or replace function waytask_private.sha256_hex(value bytea)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    extension_schema text;
    result text;
begin
    select namespace.nspname into strict extension_schema
    from pg_catalog.pg_extension extension
    join pg_catalog.pg_namespace namespace
      on namespace.oid = extension.extnamespace
    where extension.extname = 'pgcrypto';
    execute pg_catalog.format(
        'select encode(%I.digest($1, ''sha256''), ''hex'')',
        extension_schema
    ) using value into result;
    return result;
end;
$$;

revoke all on function waytask_private.sha256_hex(bytea) from public;

create table public.initial_migration_attempts (
    id uuid primary key,
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    local_dataset_id uuid not null,
    dataset_fingerprint text not null,
    format_version integer not null,
    expected_personal_products integer not null,
    expected_shopping_lists integer not null,
    expected_shopping_list_entries integer not null,
    state text not null default 'preparing',
    next_sequence integer not null default 0,
    highest_dependency_rank integer not null default -1,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    completed_at timestamptz,
    constraint initial_migration_attempt_owner_identity
        unique (id, owner_user_id),
    constraint initial_migration_attempt_single_owner
        unique (owner_user_id),
    constraint initial_migration_attempt_dataset_identity
        unique (local_dataset_id),
    constraint initial_migration_attempt_fingerprint_valid check (
        dataset_fingerprint ~ '^[0-9a-f]{64}$'
    ),
    constraint initial_migration_attempt_format_valid check (
        format_version = 1
    ),
    constraint initial_migration_attempt_counts_valid check (
        expected_personal_products between 0 and 100000
        and expected_shopping_lists between 0 and 10000
        and expected_shopping_list_entries between 0 and 500000
        and expected_personal_products + expected_shopping_lists
            + expected_shopping_list_entries <= 510000
    ),
    constraint initial_migration_attempt_state_valid check (
        state in ('preparing', 'uploading', 'verifying', 'completed',
                  'interrupted', 'rollback_required')
    ),
    constraint initial_migration_attempt_sequence_valid check (
        next_sequence >= 0
        and highest_dependency_rank between -1 and 2
    ),
    constraint initial_migration_attempt_completion_valid check (
        (state = 'completed' and completed_at is not null)
        or (state <> 'completed' and completed_at is null)
    )
);

create table public.initial_migration_receipts (
    attempt_id uuid not null,
    owner_user_id uuid not null,
    batch_id text not null,
    sequence integer not null,
    entity_kind text not null,
    client_payload_sha256 text not null,
    server_payload_sha256 text not null,
    stored_rows_sha256 text not null,
    record_ids uuid[] not null,
    record_count integer not null,
    acknowledged_at timestamptz not null default now(),
    primary key (attempt_id, batch_id),
    constraint initial_migration_receipt_attempt_owner_fk foreign key (
        attempt_id, owner_user_id
    ) references public.initial_migration_attempts(id, owner_user_id)
        on delete cascade,
    constraint initial_migration_receipt_sequence_unique
        unique (attempt_id, sequence),
    constraint initial_migration_receipt_batch_id_valid check (
        batch_id ~ '^[0-9a-f]{64}$'
    ),
    constraint initial_migration_receipt_sequence_valid check (sequence >= 0),
    constraint initial_migration_receipt_entity_valid check (
        entity_kind in (
            'personal_products', 'shopping_lists', 'shopping_list_entries'
        )
    ),
    constraint initial_migration_receipt_hashes_valid check (
        client_payload_sha256 ~ '^[0-9a-f]{64}$'
        and server_payload_sha256 ~ '^[0-9a-f]{64}$'
        and stored_rows_sha256 ~ '^[0-9a-f]{64}$'
    ),
    constraint initial_migration_receipt_count_valid check (
        record_count between 1 and 500
        and cardinality(record_ids) = record_count
    )
);

alter table public.personal_products
    add column initial_migration_attempt_id uuid;
alter table public.shopping_lists
    add column initial_migration_attempt_id uuid;
alter table public.shopping_list_entries
    add column initial_migration_attempt_id uuid;

alter table public.personal_products
    add constraint personal_products_initial_migration_owner_fk foreign key (
        initial_migration_attempt_id, owner_user_id
    ) references public.initial_migration_attempts(id, owner_user_id)
        on delete restrict;
alter table public.shopping_lists
    add constraint shopping_lists_initial_migration_owner_fk foreign key (
        initial_migration_attempt_id, owner_user_id
    ) references public.initial_migration_attempts(id, owner_user_id)
        on delete restrict;
alter table public.shopping_list_entries
    add constraint shopping_list_entries_initial_migration_owner_fk foreign key (
        initial_migration_attempt_id, owner_user_id
    ) references public.initial_migration_attempts(id, owner_user_id)
        on delete restrict;

create index personal_products_initial_migration_idx
    on public.personal_products(initial_migration_attempt_id)
    where initial_migration_attempt_id is not null;
create index shopping_lists_initial_migration_idx
    on public.shopping_lists(initial_migration_attempt_id)
    where initial_migration_attempt_id is not null;
create index shopping_list_entries_initial_migration_idx
    on public.shopping_list_entries(initial_migration_attempt_id)
    where initial_migration_attempt_id is not null;

alter table public.initial_migration_attempts enable row level security;
alter table public.initial_migration_attempts force row level security;
alter table public.initial_migration_receipts enable row level security;
alter table public.initial_migration_receipts force row level security;

grant select on table public.initial_migration_attempts,
    public.initial_migration_receipts to authenticated;
revoke insert, update, delete on table public.initial_migration_attempts,
    public.initial_migration_receipts from anon, authenticated;
revoke all on table public.initial_migration_attempts,
    public.initial_migration_receipts from anon;

create policy initial_migration_attempt_owner_select
on public.initial_migration_attempts for select to authenticated
using (owner_user_id = (select auth.uid()));

create policy initial_migration_receipt_owner_select
on public.initial_migration_receipts for select to authenticated
using (owner_user_id = (select auth.uid()));

create or replace function waytask_private.require_initial_migration_deployment()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller uuid := auth.uid();
    control waytask_private.initial_migration_control%rowtype;
begin
    if caller is null then
        raise exception 'migration_authentication_required'
            using errcode = '42501';
    end if;
    select * into strict control
    from waytask_private.initial_migration_control
    where singleton;
    if control.environment <> 'staging'
       or not control.deployment_approved then
        raise exception 'migration_deployment_not_approved'
            using errcode = '42501';
    end if;
    return caller;
end;
$$;

revoke all on function
    waytask_private.require_initial_migration_deployment() from public;

create or replace function waytask_private.initial_migration_rows_sha256(
    p_owner_user_id uuid,
    p_attempt_id uuid,
    p_entity_kind text,
    p_record_ids uuid[]
) returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    canonical_rows jsonb;
begin
    if p_entity_kind = 'personal_products' then
        select coalesce(
            jsonb_agg(to_jsonb(row_value) order by row_value.id),
            '[]'::jsonb
        ) into canonical_rows
        from public.personal_products row_value
        where row_value.owner_user_id = p_owner_user_id
          and row_value.initial_migration_attempt_id = p_attempt_id
          and row_value.id = any(p_record_ids);
    elsif p_entity_kind = 'shopping_lists' then
        select coalesce(
            jsonb_agg(to_jsonb(row_value) order by row_value.id),
            '[]'::jsonb
        ) into canonical_rows
        from public.shopping_lists row_value
        where row_value.owner_user_id = p_owner_user_id
          and row_value.initial_migration_attempt_id = p_attempt_id
          and row_value.id = any(p_record_ids);
    elsif p_entity_kind = 'shopping_list_entries' then
        select coalesce(
            jsonb_agg(to_jsonb(row_value) order by row_value.id),
            '[]'::jsonb
        ) into canonical_rows
        from public.shopping_list_entries row_value
        where row_value.owner_user_id = p_owner_user_id
          and row_value.initial_migration_attempt_id = p_attempt_id
          and row_value.id = any(p_record_ids);
    else
        raise exception 'migration_batch_invalid' using errcode = '22023';
    end if;
    return waytask_private.sha256_hex(
        pg_catalog.convert_to(canonical_rows::text, 'UTF8')
    );
end;
$$;

revoke all on function waytask_private.initial_migration_rows_sha256(
    uuid, uuid, text, uuid[]
) from public;

create or replace function waytask_private.require_initial_migration_active()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller uuid := waytask_private.require_initial_migration_deployment();
    control waytask_private.initial_migration_control%rowtype;
begin
    select * into strict control
    from waytask_private.initial_migration_control
    where singleton;
    if not control.enabled
       or not control.endpoint_ready
       or not control.signed_session_ab_gate_passed
       or not control.session_recovery_gate_passed
       or not control.security_blockers_clear
       or control.approved_format_version <> 1 then
        raise exception 'migration_security_gate_blocked'
            using errcode = '42501';
    end if;
    return caller;
end;
$$;

revoke all on function
    waytask_private.require_initial_migration_active() from public;

create or replace function public.initial_migration_begin(
    p_attempt_id uuid,
    p_local_dataset_id uuid,
    p_dataset_fingerprint text,
    p_format_version integer,
    p_counts jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller uuid := waytask_private.require_initial_migration_active();
    existing public.initial_migration_attempts%rowtype;
    product_count integer;
    list_count integer;
    entry_count integer;
begin
    if p_attempt_id is null or p_local_dataset_id is null
       or p_dataset_fingerprint !~ '^[0-9a-f]{64}$'
       or p_format_version <> 1
       or jsonb_typeof(p_counts) <> 'object'
       or p_counts <> jsonb_build_object(
            'personal_products', p_counts -> 'personal_products',
            'shopping_lists', p_counts -> 'shopping_lists',
            'shopping_list_entries', p_counts -> 'shopping_list_entries'
       ) then
        raise exception 'migration_manifest_invalid' using errcode = '22023';
    end if;
    begin
        product_count := (p_counts ->> 'personal_products')::integer;
        list_count := (p_counts ->> 'shopping_lists')::integer;
        entry_count := (p_counts ->> 'shopping_list_entries')::integer;
    exception when others then
        raise exception 'migration_manifest_invalid' using errcode = '22023';
    end;
    if product_count not between 0 and 100000
       or list_count not between 0 and 10000
       or entry_count not between 0 and 500000
       or product_count + list_count + entry_count > 510000 then
        raise exception 'migration_manifest_oversized' using errcode = '22023';
    end if;

    select * into existing from public.initial_migration_attempts
    where id = p_attempt_id;
    if found then
        if existing.owner_user_id <> caller
           or existing.local_dataset_id <> p_local_dataset_id
           or existing.dataset_fingerprint <> p_dataset_fingerprint
           or existing.format_version <> p_format_version
           or existing.expected_personal_products <> product_count
           or existing.expected_shopping_lists <> list_count
           or existing.expected_shopping_list_entries <> entry_count then
            raise exception 'migration_attempt_conflict' using errcode = '42501';
        end if;
        return jsonb_build_object(
            'attempt_id', existing.id,
            'state', existing.state,
            'idempotent', true
        );
    end if;

    if exists(select 1 from public.personal_products where owner_user_id = caller)
       or exists(select 1 from public.shopping_lists where owner_user_id = caller)
       or exists(select 1 from public.shopping_list_entries
                 where owner_user_id = caller)
       or exists(select 1 from public.user_preferences
                 where owner_user_id = caller)
       or exists(select 1 from public.saved_stores where owner_user_id = caller)
       or exists(select 1 from public.notification_preferences
                 where owner_user_id = caller)
       or exists(select 1 from public.device_installations
                 where owner_user_id = caller)
       or exists(select 1 from public.sync_mutations
                 where owner_user_id = caller)
       or exists(select 1 from public.initial_migration_attempts
                 where owner_user_id = caller) then
        raise exception 'migration_remote_not_empty' using errcode = '23505';
    end if;

    insert into public.initial_migration_attempts(
        id, owner_user_id, local_dataset_id, dataset_fingerprint,
        format_version, expected_personal_products,
        expected_shopping_lists, expected_shopping_list_entries
    ) values (
        p_attempt_id, caller, p_local_dataset_id, p_dataset_fingerprint,
        p_format_version, product_count, list_count, entry_count
    );
    return jsonb_build_object(
        'attempt_id', p_attempt_id,
        'state', 'preparing',
        'idempotent', false
    );
end;
$$;

create or replace function public.initial_migration_apply_batch(
    p_attempt_id uuid,
    p_batch_id text,
    p_sequence integer,
    p_entity_kind text,
    p_client_payload_sha256 text,
    p_records jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller uuid := waytask_private.require_initial_migration_active();
    attempt public.initial_migration_attempts%rowtype;
    receipt public.initial_migration_receipts%rowtype;
    record_count integer;
    dependency_rank integer;
    server_hash text;
    stored_rows_hash text;
    expected_batch_id text;
    record_ids uuid[];
    expected_entity_count integer;
    applied_entity_count integer;
begin
    if jsonb_typeof(p_records) <> 'array'
       or p_client_payload_sha256 !~ '^[0-9a-f]{64}$'
       or p_batch_id !~ '^[0-9a-f]{64}$'
       or p_sequence < 0 or p_sequence >= 5100
       or p_entity_kind not in (
            'personal_products', 'shopping_lists', 'shopping_list_entries'
       ) then
        raise exception 'migration_batch_invalid' using errcode = '22023';
    end if;
    record_count := jsonb_array_length(p_records);
    if record_count not between 1 and 100
       or octet_length(p_records::text) > 1048576 then
        raise exception 'migration_batch_oversized' using errcode = '22023';
    end if;
    if exists(
        select 1 from jsonb_array_elements(p_records) as record
        where record ?| array[
            'owner_user_id', 'ownerUserID', 'target_user_id', 'targetUserID'
        ]
    ) then
        raise exception 'migration_owner_field_forbidden' using errcode = '42501';
    end if;
    begin
        select pg_catalog.array_agg(record_id order by record_id)
        into record_ids
        from (
            select (record ->> 'id')::uuid as record_id
            from jsonb_array_elements(p_records) as record
        ) identifiers;
    exception when others then
        raise exception 'migration_batch_invalid' using errcode = '22023';
    end;
    if cardinality(record_ids) <> record_count
       or (select count(distinct value) from unnest(record_ids) value)
            <> record_count then
        raise exception 'migration_batch_invalid' using errcode = '22023';
    end if;

    dependency_rank := case p_entity_kind
        when 'personal_products' then 0
        when 'shopping_lists' then 1
        else 2
    end;
    server_hash := waytask_private.sha256_hex(
        convert_to(p_records::text, 'UTF8')
    );
    expected_batch_id := waytask_private.sha256_hex(
        convert_to(
            lower(p_attempt_id::text) || '|' || p_sequence::text || '|'
            || p_entity_kind || '|' || p_client_payload_sha256,
            'UTF8'
        )
    );
    if expected_batch_id <> p_batch_id then
        raise exception 'migration_batch_identity_invalid' using errcode = '22023';
    end if;

    select * into receipt from public.initial_migration_receipts
    where attempt_id = p_attempt_id and batch_id = p_batch_id;
    if found then
        if receipt.owner_user_id <> caller
           or receipt.sequence <> p_sequence
           or receipt.entity_kind <> p_entity_kind
           or receipt.client_payload_sha256 <> p_client_payload_sha256
           or receipt.server_payload_sha256 <> server_hash
           or receipt.record_ids <> record_ids
           or receipt.stored_rows_sha256 <>
                waytask_private.initial_migration_rows_sha256(
                    caller, p_attempt_id, p_entity_kind, record_ids
                )
           or receipt.record_count <> record_count then
            raise exception 'migration_receipt_conflict' using errcode = '42501';
        end if;
        return jsonb_build_object(
            'batch_id', receipt.batch_id,
            'sequence', receipt.sequence,
            'payload_sha256', receipt.client_payload_sha256,
            'record_count', receipt.record_count,
            'idempotent', true
        );
    end if;

    select * into strict attempt from public.initial_migration_attempts
    where id = p_attempt_id for update;
    if attempt.owner_user_id <> caller then
        raise exception 'migration_attempt_owner_mismatch' using errcode = '42501';
    end if;
    if attempt.state = 'completed' then
        raise exception 'migration_already_completed' using errcode = '23514';
    end if;
    if attempt.next_sequence <> p_sequence
       or dependency_rank < attempt.highest_dependency_rank then
        raise exception 'migration_batch_order_invalid' using errcode = '23514';
    end if;
    expected_entity_count := case p_entity_kind
        when 'personal_products' then attempt.expected_personal_products
        when 'shopping_lists' then attempt.expected_shopping_lists
        else attempt.expected_shopping_list_entries
    end;
    select coalesce(sum(existing_receipt.record_count), 0)
    into applied_entity_count
    from public.initial_migration_receipts existing_receipt
    where existing_receipt.attempt_id = p_attempt_id
      and existing_receipt.owner_user_id = caller
      and existing_receipt.entity_kind = p_entity_kind;
    if applied_entity_count + record_count > expected_entity_count
       or record_count <> least(
            100, expected_entity_count - applied_entity_count
       ) then
        raise exception 'migration_manifest_count_exceeded'
            using errcode = '23514';
    end if;

    if p_entity_kind = 'personal_products' then
        insert into public.personal_products(
            id, owner_user_id, display_name, brand, category, barcode, source,
            catalog_product_id, library_lifecycle, removed_at, revision,
            created_at, updated_at, initial_migration_attempt_id
        )
        select
            (record ->> 'id')::uuid, caller,
            record ->> 'display_name', record ->> 'brand',
            record ->> 'category', record ->> 'barcode',
            record ->> 'source', record ->> 'catalog_product_id',
            record ->> 'library_lifecycle',
            case when record ->> 'removed_at_milliseconds' is null then null
                 else to_timestamp(
                    (record ->> 'removed_at_milliseconds')::numeric / 1000
                 ) end,
            1,
            to_timestamp((record ->> 'created_at_milliseconds')::numeric / 1000),
            to_timestamp((record ->> 'updated_at_milliseconds')::numeric / 1000),
            p_attempt_id
        from jsonb_array_elements(p_records) as record;
    elsif p_entity_kind = 'shopping_lists' then
        insert into public.shopping_lists(
            id, owner_user_id, title, purpose, revision, created_at, updated_at,
            initial_migration_attempt_id
        )
        select
            (record ->> 'id')::uuid, caller, record ->> 'title',
            record ->> 'purpose', 1,
            to_timestamp((record ->> 'created_at_milliseconds')::numeric / 1000),
            to_timestamp((record ->> 'updated_at_milliseconds')::numeric / 1000),
            p_attempt_id
        from jsonb_array_elements(p_records) as record;
    else
        insert into public.shopping_list_entries(
            id, owner_user_id, shopping_list_id, personal_product_id,
            quantity, unit, note, lifecycle, resolution_reason,
            resolution_effective_at, resolution_provenance,
            resolution_command_id, sort_order, revision, created_at,
            updated_at, initial_migration_attempt_id
        )
        select
            (record ->> 'id')::uuid, caller,
            (record ->> 'shopping_list_id')::uuid,
            (record ->> 'personal_product_id')::uuid,
            (record ->> 'quantity')::numeric,
            record ->> 'unit', record ->> 'note', record ->> 'lifecycle',
            record ->> 'resolution_reason',
            case when record ->> 'resolution_effective_at_milliseconds' is null
                 then null else to_timestamp(
                    (record ->> 'resolution_effective_at_milliseconds')::numeric
                        / 1000
                 ) end,
            record ->> 'resolution_provenance',
            case when record ->> 'resolution_command_id' is null then null
                 else (record ->> 'resolution_command_id')::uuid end,
            (record ->> 'sort_order')::numeric,
            1,
            to_timestamp((record ->> 'created_at_milliseconds')::numeric / 1000),
            to_timestamp((record ->> 'updated_at_milliseconds')::numeric / 1000),
            p_attempt_id
        from jsonb_array_elements(p_records) as record;
    end if;

    stored_rows_hash := waytask_private.initial_migration_rows_sha256(
        caller, p_attempt_id, p_entity_kind, record_ids
    );
    if (case p_entity_kind
            when 'personal_products' then (
                select count(*) from public.personal_products
                where owner_user_id = caller
                  and initial_migration_attempt_id = p_attempt_id
                  and id = any(record_ids)
            )
            when 'shopping_lists' then (
                select count(*) from public.shopping_lists
                where owner_user_id = caller
                  and initial_migration_attempt_id = p_attempt_id
                  and id = any(record_ids)
            )
            else (
                select count(*) from public.shopping_list_entries
                where owner_user_id = caller
                  and initial_migration_attempt_id = p_attempt_id
                  and id = any(record_ids)
            )
        end) <> record_count then
        raise exception 'migration_batch_persistence_mismatch'
            using errcode = '23514';
    end if;

    insert into public.initial_migration_receipts(
        attempt_id, owner_user_id, batch_id, sequence, entity_kind,
        client_payload_sha256, server_payload_sha256, stored_rows_sha256,
        record_ids, record_count
    ) values (
        p_attempt_id, caller, p_batch_id, p_sequence, p_entity_kind,
        p_client_payload_sha256, server_hash, stored_rows_hash,
        record_ids, record_count
    );
    update public.initial_migration_attempts
    set state = 'uploading', next_sequence = p_sequence + 1,
        highest_dependency_rank = greatest(highest_dependency_rank,
                                           dependency_rank),
        updated_at = clock_timestamp()
    where id = p_attempt_id and owner_user_id = caller;

    return jsonb_build_object(
        'batch_id', p_batch_id,
        'sequence', p_sequence,
        'payload_sha256', p_client_payload_sha256,
        'record_count', record_count,
        'idempotent', false
    );
exception
    when unique_violation then
        raise exception 'migration_identity_conflict' using errcode = '23505';
    when foreign_key_violation then
        raise exception 'migration_parent_missing' using errcode = '23503';
end;
$$;

create or replace function public.initial_migration_verify(
    p_attempt_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller uuid := waytask_private.require_initial_migration_active();
    attempt public.initial_migration_attempts%rowtype;
    product_count integer;
    list_count integer;
    entry_count integer;
    receipt_count integer;
begin
    select * into strict attempt from public.initial_migration_attempts
    where id = p_attempt_id for update;
    if attempt.owner_user_id <> caller then
        raise exception 'migration_attempt_owner_mismatch' using errcode = '42501';
    end if;
    select count(*) into product_count from public.personal_products
    where owner_user_id = caller and initial_migration_attempt_id = p_attempt_id;
    select count(*) into list_count from public.shopping_lists
    where owner_user_id = caller and initial_migration_attempt_id = p_attempt_id;
    select count(*) into entry_count from public.shopping_list_entries
    where owner_user_id = caller and initial_migration_attempt_id = p_attempt_id;
    select coalesce(sum(record_count), 0) into receipt_count
    from public.initial_migration_receipts
    where owner_user_id = caller and attempt_id = p_attempt_id;

    if product_count <> attempt.expected_personal_products
       or list_count <> attempt.expected_shopping_lists
       or entry_count <> attempt.expected_shopping_list_entries
       or receipt_count <> product_count + list_count + entry_count
       or product_count <> (
            select count(*) from public.personal_products
            where owner_user_id = caller
       )
       or list_count <> (
            select count(*) from public.shopping_lists
            where owner_user_id = caller
       )
       or entry_count <> (
            select count(*) from public.shopping_list_entries
            where owner_user_id = caller
       )
       or exists(select 1 from public.user_preferences
                 where owner_user_id = caller)
       or exists(select 1 from public.saved_stores
                 where owner_user_id = caller)
       or exists(select 1 from public.notification_preferences
                 where owner_user_id = caller)
       or exists(select 1 from public.device_installations
                 where owner_user_id = caller)
       or exists(select 1 from public.sync_mutations
                 where owner_user_id = caller)
       or exists(
            select 1 from public.initial_migration_receipts receipt
            where receipt.attempt_id = p_attempt_id
              and receipt.owner_user_id = caller
              and receipt.stored_rows_sha256 <>
                  waytask_private.initial_migration_rows_sha256(
                      caller, p_attempt_id, receipt.entity_kind,
                      receipt.record_ids
                  )
       )
       or exists(
            select 1 from public.shopping_list_entries entry
            left join public.shopping_lists list
              on list.id = entry.shopping_list_id
             and list.owner_user_id = entry.owner_user_id
            left join public.personal_products product
              on product.id = entry.personal_product_id
             and product.owner_user_id = entry.owner_user_id
            where entry.initial_migration_attempt_id = p_attempt_id
              and (list.initial_migration_attempt_id <> p_attempt_id
                   or product.initial_migration_attempt_id <> p_attempt_id)
       )
       or exists(
            select 1 from public.personal_products
            where initial_migration_attempt_id = p_attempt_id
              and (image_object_path is not null
                   or image_mime_type is not null
                   or image_byte_count is not null
                   or image_pixel_width is not null
                   or image_pixel_height is not null)
       ) then
        update public.initial_migration_attempts
        set state = 'rollback_required', updated_at = clock_timestamp()
        where id = p_attempt_id;
        raise exception 'migration_verification_failed' using errcode = '23514';
    end if;

    update public.initial_migration_attempts
    set state = 'completed', completed_at = clock_timestamp(),
        updated_at = clock_timestamp()
    where id = p_attempt_id;

    return jsonb_build_object(
        'target_user_id', caller,
        'dataset_fingerprint', attempt.dataset_fingerprint,
        'counts', jsonb_build_object(
            'personal_products', product_count,
            'shopping_lists', list_count,
            'shopping_list_entries', entry_count
        ),
        'acknowledged_batch_ids', coalesce((
            select jsonb_agg(batch_id order by sequence)
            from public.initial_migration_receipts
            where attempt_id = p_attempt_id and owner_user_id = caller
        ), '[]'::jsonb),
        'parent_child_integrity_verified', true,
        'excluded_data_absent', true
    );
end;
$$;

create or replace function public.initial_migration_rollback(
    p_attempt_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller uuid := waytask_private.require_initial_migration_deployment();
    attempt public.initial_migration_attempts%rowtype;
begin
    select * into strict attempt from public.initial_migration_attempts
    where id = p_attempt_id for update;
    if attempt.owner_user_id <> caller then
        raise exception 'migration_attempt_owner_mismatch' using errcode = '42501';
    end if;
    if attempt.state = 'completed' then
        raise exception 'migration_completed_not_rollbackable'
            using errcode = '23514';
    end if;
    delete from public.shopping_list_entries
    where initial_migration_attempt_id = p_attempt_id and owner_user_id = caller;
    delete from public.shopping_lists
    where initial_migration_attempt_id = p_attempt_id and owner_user_id = caller;
    delete from public.personal_products
    where initial_migration_attempt_id = p_attempt_id and owner_user_id = caller;
    delete from public.initial_migration_receipts
    where attempt_id = p_attempt_id and owner_user_id = caller;
    delete from public.initial_migration_attempts
    where id = p_attempt_id and owner_user_id = caller;
end;
$$;

revoke all on function public.initial_migration_begin(
    uuid, uuid, text, integer, jsonb
) from public, anon;
revoke all on function public.initial_migration_apply_batch(
    uuid, text, integer, text, text, jsonb
) from public, anon;
revoke all on function public.initial_migration_verify(uuid)
from public, anon;
revoke all on function public.initial_migration_rollback(uuid)
from public, anon;

grant execute on function public.initial_migration_begin(
    uuid, uuid, text, integer, jsonb
) to authenticated;
grant execute on function public.initial_migration_apply_batch(
    uuid, text, integer, text, text, jsonb
) to authenticated;
grant execute on function public.initial_migration_verify(uuid)
to authenticated;
grant execute on function public.initial_migration_rollback(uuid)
to authenticated;

comment on table public.initial_migration_attempts is
    'WT-032C staging migration ledger. Direct client mutation is denied.';
comment on table public.initial_migration_receipts is
    'Owner-scoped idempotency receipts for bounded initial migration batches.';
