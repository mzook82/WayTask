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
- The initial WT-032B live HTTPS/Auth suite passed 15 publishable-key-only
  assertions; the WT-032B.1 extension below subsequently passed 18/18:
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

At WT-032B closure, the advisor reported one deliberate warning:
`public.consume_ai_recognition_quota(uuid, text)` is an authenticated-callable
SECURITY DEFINER RPC. This is the reviewed server quota boundary: it derives the
user from `auth.uid()`, does not accept an owner UUID, and has its own constraint
and idempotency suite. It does not invoke Gemini. Secure AI's independent client
and server switches remain OFF, so this warning is accepted for WT-032B rather
than weakening the quota authority or enabling AI.

The WT-032B.1 re-audit additionally reports leaked-password protection disabled.
Email Auth is now disabled, so that advisor item documents an inactive password
feature rather than authorizing password authentication.

## Subsequent real-device authentication proof

On 2026-08-08, a signed `h.WayTask.staging` build completed native Sign in with
Apple on a physical iPhone against **WayTask Staging**. The test used Hide My
Email/Private Relay. Supabase created exactly one social user. The app restored
the valid session after force-close/reopen, remained Guest after sign-out and a
second relaunch, then re-signed in with the same Apple account without creating
a duplicate user. Sync, migration, and Secure AI stayed OFF and no user dataset
was uploaded or migrated.

This proves the real Apple → Supabase happy path and a valid signed Staging
session. It does not convert the database-role A/B assertions below into a live
two-user signed-token gateway test.

## Signed-session validation still deferred

The 56 database assertions exercise the deployed schema as PostgreSQL's
`authenticated` role with controlled JWT claim context. They do not mint or
verify a real Supabase access token. The HTTPS suite exercises the live gateway
as anonymous and with a malformed token. One real happy-path session is now
proven, but the combined evidence does not claim the following:

- real User A/User B HTTPS isolation using signed staging sessions;
- adversarial issuer, audience, project, subject, or UUID claim rejection for a
  deliberately altered otherwise-valid token;
- near-expiry refresh, natural expiration, or administratively revoked session
  recovery;
- a wrong-project signed token rejection.

Local sign-out persistence is real-device proven, but it does not independently
prove that the server rejected a previously issued refresh session after an
administrative revocation.

## WT-032B.1 hosted extension

On 2026-08-08, the publishable-key HTTPS/Auth gate was extended without using a
real user token or privileged credential. Two additional assertions passed:

- an unsigned `alg=none` JWT carrying fabricated authenticated claims was
  rejected;
- a structurally valid signed-shape JWT with an unknown key/signature was
  rejected.

The extension passes 18/18 negative/discovery/Data API/Auth assertions after
Email was disabled. Apple is the only enabled Staging provider. The successful
rerun created or modified no user or session.

The extension also adds local client proof for bounded refresh, offline retry,
denied refresh, protected-request revocation recovery, project-origin mismatch,
and server-verified subject mismatch. It still does not claim live signed A/B,
a valid foreign-project token, natural hosted expiration, or administrative
revocation. See [WT-032B.1](../WT-032B.1/README.md).

## Completed external setup

- Apple is enabled in **WayTask Staging** with native client ID
  `h.WayTask.staging`; no web OAuth secret is configured.
- The Apple App ID capability, development provisioning profile, signed Staging
  bundle, and Apple entitlement are verified on a physical iPhone.
- The ignored client configuration contains only the Staging HTTPS URL and
  client-safe publishable key and has mode `0600`.
- Staging Accounts is ON. Sync, Migration, Secure AI, and all Production account
  configuration remain OFF.

## Deferred external actions

- Create a second disposable Staging-only identity only after separately
  approving the real Apple action; do not import ProductState data.
- Inject short-lived A/B access tokens only through an approved ephemeral secret
  runner, never Git, chat, logs, reports, plist, or command arguments. No
  service-role key belongs in iOS.
- Revoke a disposable Staging session administratively to prove server-side
  recovery. Use a separate non-Production issuer for wrong-project denial; never
  use or configure Production.

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

The HTTPS/Auth script retrieves exactly one client-safe publishable key into
process memory, suppresses credential output, and refuses to run unless the
linked project name is exactly `WayTask Staging`. It never requests or uses a
service-role/secret key.
