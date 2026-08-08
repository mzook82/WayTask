-- WT-032B: staging authentication profile-input boundary.
-- This migration contains no sync, ProductState, or Production activation.

create or replace function waytask_private.normalize_profile_display_name(
    value text
) returns text
language sql
immutable
set search_path = ''
as $$
    select case
        when value is null then null
        else btrim(regexp_replace(normalize(value, NFC), ' +', ' ', 'g'))
    end;
$$;

create or replace function waytask_private.valid_profile_display_name(
    value text
) returns boolean
language sql
immutable
set search_path = ''
as $$
    select value is null or (
        char_length(value) between 1 and 80
        and value = normalize(value, NFC)
        and value = btrim(value)
        and value !~ '  +'
        and value !~ '[[:cntrl:]]'
        -- Preserve ZWJ emoji sequences and meaningful Arabic-script ZWNJ.
        and strpos(value, U&'\200B') = 0
        and strpos(value, U&'\2060') = 0
        and strpos(value, U&'\FEFF') = 0
        -- Reject direction-changing controls; natural Hebrew/Arabic is valid.
        and strpos(value, U&'\061C') = 0
        and strpos(value, U&'\200E') = 0
        and strpos(value, U&'\200F') = 0
        and strpos(value, U&'\202A') = 0
        and strpos(value, U&'\202B') = 0
        and strpos(value, U&'\202C') = 0
        and strpos(value, U&'\202D') = 0
        and strpos(value, U&'\202E') = 0
        and strpos(value, U&'\2066') = 0
        and strpos(value, U&'\2067') = 0
        and strpos(value, U&'\2068') = 0
        and strpos(value, U&'\2069') = 0
    );
$$;

create or replace function waytask_private.normalize_profile_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    new.display_name := waytask_private.normalize_profile_display_name(
        new.display_name
    );
    return new;
end;
$$;

drop trigger if exists profiles_display_name_normalize on public.profiles;
create trigger profiles_display_name_normalize
before insert or update of display_name on public.profiles
for each row execute function waytask_private.normalize_profile_row();

alter table public.profiles
    drop constraint profiles_display_name_valid;
alter table public.profiles
    add constraint profiles_display_name_valid check (
        waytask_private.valid_profile_display_name(display_name)
    );

revoke all on function waytask_private.normalize_profile_display_name(text)
from public, anon, authenticated;
revoke all on function waytask_private.valid_profile_display_name(text)
from public, anon, authenticated;
grant execute on function waytask_private.valid_profile_display_name(text)
to anon, authenticated, service_role;
revoke all on function waytask_private.normalize_profile_row()
from public, anon, authenticated;
