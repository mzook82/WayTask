-- WT-032A.1: staging-only secure AI quota and idempotency boundary.
-- The Edge Function remains disabled unless its server environment kill switch
-- is explicitly enabled. No image, barcode, prompt, or recognition response is
-- stored by this migration.

create table waytask_private.ai_recognition_requests (
    owner_user_id uuid not null references auth.users(id) on delete cascade,
    request_id uuid not null,
    ip_hash text not null,
    created_at timestamptz not null default clock_timestamp(),
    primary key (owner_user_id, request_id),
    constraint ai_recognition_ip_hash_valid check (
        ip_hash ~ '^[0-9a-f]{64}$'
    )
);

revoke all on table waytask_private.ai_recognition_requests
from public, anon, authenticated;
grant all on table waytask_private.ai_recognition_requests to service_role;

create index ai_recognition_user_created_idx
    on waytask_private.ai_recognition_requests
    (owner_user_id, created_at desc);
create index ai_recognition_ip_created_idx
    on waytask_private.ai_recognition_requests
    (ip_hash, created_at desc);

create or replace function public.consume_ai_recognition_quota(
    p_request_id uuid,
    p_ip_hash text
) returns table (
    allowed boolean,
    duplicate_request boolean,
    retry_after_seconds integer,
    user_minute_remaining integer,
    user_day_remaining integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_user_id uuid := auth.uid();
    quota_now timestamptz := clock_timestamp();
    user_minute_count integer;
    user_day_count integer;
    ip_minute_count integer;
    ip_day_count integer;
    retry_seconds integer := 60;
begin
    if current_user_id is null then
        raise exception 'authentication required' using errcode = '42501';
    end if;
    if p_request_id is null or p_ip_hash is null or
       p_ip_hash !~ '^[0-9a-f]{64}$' then
        raise exception 'invalid quota input' using errcode = '22023';
    end if;

    -- Serialize the authenticated user and the privacy-preserving network key.
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(current_user_id::text, 0)
    );
    perform pg_catalog.pg_advisory_xact_lock(
        pg_catalog.hashtextextended(p_ip_hash, 1)
    );

    if exists (
        select 1
        from waytask_private.ai_recognition_requests request
        where request.owner_user_id = current_user_id
          and request.request_id = p_request_id
    ) then
        return query select false, true, 0, 0, 0;
        return;
    end if;

    delete from waytask_private.ai_recognition_requests request
    where request.created_at < quota_now - interval '2 days';

    select count(*) filter (
               where request.created_at >= quota_now - interval '1 minute'
           ),
           count(*) filter (
               where request.created_at >= quota_now - interval '1 day'
           )
    into user_minute_count, user_day_count
    from waytask_private.ai_recognition_requests request
    where request.owner_user_id = current_user_id;

    select count(*) filter (
               where request.created_at >= quota_now - interval '1 minute'
           ),
           count(*) filter (
               where request.created_at >= quota_now - interval '1 day'
           )
    into ip_minute_count, ip_day_count
    from waytask_private.ai_recognition_requests request
    where request.ip_hash = p_ip_hash;

    if user_minute_count >= 6 or ip_minute_count >= 30 then
        select greatest(
            1,
            ceil(extract(epoch from (
                min(request.created_at) + interval '1 minute' - quota_now
            )))::integer
        )
        into retry_seconds
        from waytask_private.ai_recognition_requests request
        where request.created_at >= quota_now - interval '1 minute'
          and (
              request.owner_user_id = current_user_id
              or request.ip_hash = p_ip_hash
          );
        return query select
            false,
            false,
            coalesce(retry_seconds, 60),
            greatest(0, 6 - user_minute_count),
            greatest(0, 60 - user_day_count);
        return;
    end if;

    if user_day_count >= 60 or ip_day_count >= 300 then
        return query select
            false,
            false,
            3600,
            greatest(0, 6 - user_minute_count),
            greatest(0, 60 - user_day_count);
        return;
    end if;

    insert into waytask_private.ai_recognition_requests (
        owner_user_id,
        request_id,
        ip_hash,
        created_at
    ) values (
        current_user_id,
        p_request_id,
        p_ip_hash,
        quota_now
    );

    return query select
        true,
        false,
        0,
        greatest(0, 5 - user_minute_count),
        greatest(0, 59 - user_day_count);
end;
$$;

revoke all on function public.consume_ai_recognition_quota(uuid, text)
from public, anon;
grant execute on function public.consume_ai_recognition_quota(uuid, text)
to authenticated, service_role;

comment on function public.consume_ai_recognition_quota(uuid, text) is
'Consumes signed-in secure-AI quota by user and salted IP hash. Stores no request payload or recognition content.';
