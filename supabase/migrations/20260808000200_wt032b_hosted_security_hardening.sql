-- WT-032B hosted Supabase hardening.
-- Supabase may install this event-trigger helper in public with PostgreSQL's
-- default PUBLIC EXECUTE grant. Client execution is unnecessary: the database
-- event trigger invokes it internally. Bare/local PostgreSQL does not install
-- the helper, so this migration intentionally becomes a no-op there.

do $$
begin
    if to_regprocedure('public.rls_auto_enable()') is not null then
        execute
            'revoke execute on function public.rls_auto_enable() '
            'from public, anon, authenticated';
    end if;
end;
$$;
