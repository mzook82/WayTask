# WT-032B Hosted Staging Validation

Executed on 2026-08-08 against the linked project named **WayTask Staging**.
The project reference is intentionally omitted from this report. Production was
not linked, queried, migrated, or configured.

## Proven against hosted Staging

- Repository and remote migration history matched exactly at four versions:
  `20260806000100`, `20260806000200`, `20260808000100`, and
  `20260808000200`.
- `supabase db push --linked --dry-run` returned `upToDate: true` with no
  migrations, seeds, or roles pending.
- `hosted_staging_validation.sql` passed 56 assertions inside one transaction
  and rolled the transaction back. No synthetic auth identity or test row was
  retained.
- All ten expected public Data API tables had RLS and FORCE RLS enabled. The
  deployed policy/grant inventory, immutable ownership, parent/child ownership,
  and database constraints matched the repository contract.
- Database-role authenticated contexts for synthetic User A and User B proved
  exact-UUID isolation, broad/filter isolation, update/delete denial, owner
  mutation denial, parent/child bypass denial, and administrative-table denial.
- Anonymous database and HTTPS contexts could not read or write private rows.
  Exact UUID guesses and a broad `or` filter returned no private profile row.
- The live HTTPS/Auth suite passed 15 publishable-key-only assertions:
  missing API key, anonymous private access, exact UUID/filter manipulation,
  anonymous insert/update/delete, catalog exposure, private/admin schema
  exposure, malformed bearer JWT, private normalization RPC exposure, hosted
  issuer/JWKS discovery consistency, a non-empty verification key set, and
  missing-session denial at the Auth user endpoint.
- Published catalog release metadata remained anonymously readable while
  unpublished metadata and all client catalog writes remained denied.
- SQL-like and markup-like display names were stored/retrieved as data in the
  rollback transaction. Unicode normalization, international names, emoji and
  ZWJ behavior passed. Empty, overlong, zero-width, bidi-control, newline,
  control, and null-containing bypass attempts were rejected by the deployed
  database boundary.
- The hosted security advisor originally identified client execution grants on
  Supabase's `public.rls_auto_enable()` event-trigger helper. Migration
  `20260808000200` revoked that unnecessary access from `public`, `anon`, and
  `authenticated`; the hosted assertions prove those grants are now absent.

The advisor now reports one deliberate warning:
`public.consume_ai_recognition_quota(uuid, text)` is an authenticated-callable
SECURITY DEFINER RPC. This is the reviewed server quota boundary: it derives the
user from `auth.uid()`, does not accept an owner UUID, and has its own constraint
and idempotency suite. It does not invoke Gemini. Secure AI's independent client
and server switches remain OFF, so this warning is accepted for WT-032B rather
than weakening the quota authority or enabling AI.

## Not yet proven with real hosted Auth sessions

The 56 database assertions exercise the deployed schema as PostgreSQL's
`authenticated` role with controlled JWT claim context. They do not mint or
verify a real Supabase access token. The HTTPS suite exercises the live gateway
as anonymous and with a malformed token, but does not claim the following:

- real Apple-to-Supabase token exchange;
- real User A/User B HTTPS isolation using signed staging sessions;
- hosted issuer, audience, project, and UUID claim verification for a valid
  token;
- stale, expired, refreshed, or administratively revoked session behavior;
- a wrong-project signed token rejection.

The public Auth settings endpoint reported Apple disabled. The ignored client
configuration file `Secrets-Staging.xcconfig` is also absent. Creating users or
obtaining real session tokens would therefore cross the external configuration
boundary and was intentionally not attempted.

## Exact external actions required

1. In Apple Developer, enable **Sign in with Apple** for the staging App ID
   `h.WayTask.staging` and regenerate the internal-device provisioning profile.
2. In **WayTask Staging** Supabase Auth providers, enable Apple and configure the
   native client ID `h.WayTask.staging`. Keep any Apple private key or generated
   client secret outside Git and outside the iOS app. Do not configure a
   Production project.
3. Create the ignored `Secrets-Staging.xcconfig` from its example and insert
   only the Staging HTTPS project URL and client-safe publishable key. Keep sync,
   migration, and Secure AI OFF. Do not send these values in chat or commit them.
4. On registered devices, establish two disposable Staging-only Apple Auth
   identities/sessions (User A and User B). Do not import existing users or
   ProductState data.
5. For automated HTTPS A/B assertions, place the two short-lived access tokens
   in an approved ephemeral secret environment, never source control, command
   arguments, reports, or chat. No service-role key is needed by or permitted in
   iOS. If tokens cannot be supplied through a secret channel, execute these
   checks as physical-device QA instead.
6. Revoke one disposable Staging session from the Auth dashboard to exercise
   revocation/recovery. Test wrong-project rejection only with another
   non-Production disposable test project/token; never use a Production token.

## Re-run commands

Verify the CLI is linked to the project named **WayTask Staging** before running:

```sh
supabase migration list --linked
supabase db push --linked --dry-run
supabase db query --linked \
  --file supabase/tests/hosted_staging_validation.sql
bash supabase/tests/hosted_staging_data_api.sh
supabase db advisors --linked --type security --level warn \
  --fail-on none --output json
```

The HTTPS/Auth script retrieves exactly one client-safe publishable key into process
memory, suppresses credential output, and refuses to run unless the linked
project name is exactly `WayTask Staging`. It never requests or uses a
service-role/secret key.
