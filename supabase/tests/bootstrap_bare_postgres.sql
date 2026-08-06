-- Compatibility bootstrap for running the policy suite against a clean local
-- PostgreSQL instance when the Supabase services are unavailable. The real
-- Supabase local stack already supplies these roles, auth.users, and auth.uid().

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role nologin bypassrls;
    end if;
end;
$$;

create schema if not exists auth;

create table if not exists auth.users (
    instance_id uuid,
    id uuid primary key,
    aud varchar(255),
    role varchar(255),
    email varchar(255),
    encrypted_password varchar(255),
    created_at timestamptz,
    updated_at timestamptz
);

create or replace function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
