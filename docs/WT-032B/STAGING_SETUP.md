# WT-032B Staging Setup and Remote Verification

This checklist targets one dedicated non-Production Supabase project. Never use
a Production project reference, database, user export, or credentials.

## External configuration

Status on 2026-08-08: completed for **WayTask Staging**. Apple Auth is enabled
for native client ID `h.WayTask.staging`; the App ID capability, development
profile, signed physical-device bundle, and Apple entitlement are verified. The
ignored publishable client configuration is installed locally with mode `0600`.
No web OAuth secret or privileged client credential was created.

1. Create/select the isolated staging project. Confirm its organization, owner,
   region, plan, retention, backup policy, and that it contains no Production
   users or data.
2. In Apple Developer Certificates, Identifiers & Profiles, enable **Sign in
   with Apple** for App ID/bundle ID `h.WayTask.staging` as a primary App ID (or
   an explicitly reviewed group). Regenerate the internal provisioning profile.
3. In the staging Supabase dashboard, enable only the Apple provider and include
   native client ID `h.WayTask.staging`. Follow the current Supabase native
   Apple guide:
   <https://supabase.com/docs/guides/auth/social-login/auth-apple>.
4. This implementation is native-only. Do not add a web Services ID, redirect,
   `.p8` signing key, or Apple client secret unless a separately approved web
   OAuth flow actually requires it. If web OAuth is later enabled, keep `.p8`
   and generated secret outside Git/iOS and schedule required rotation.
5. If outbound mail to Apple relay addresses is later enabled, register and
   authenticate approved senders using Apple Private Relay guidance. Do not
   domain-reject `privaterelay.appleid.com`, `icloud.com`, or the newer
   `private.icloud.com` form. WT-032B sends no email.
6. Copy `Secrets-Staging.xcconfig.example` to the ignored
   `Secrets-Staging.xcconfig` and set only:

   ```xcconfig
   WAYTASK_SUPABASE_URL = https:/$()/STAGING_PROJECT_REF.supabase.co
   WAYTASK_SUPABASE_PUBLISHABLE_KEY = STAGING_CLIENT_PUBLISHABLE_KEY
   ```

   Leave sync, migration, and Secure AI OFF. Never put the database password,
   access token, refresh token, service-role/secret key, Apple private key,
   Apple client secret, or Gemini key in the file.

## Migration path

Authenticate the Supabase CLI outside the repository and verify the selected
project independently before linking. Keep the database password in the CLI's
native credential storage or an external `pg_service`/password file, not shell
history or repository files.

```sh
supabase projects list
supabase link --project-ref STAGING_PROJECT_REF
supabase migration list --linked
supabase db push --linked --dry-run
supabase db push --linked
supabase migration list --linked
supabase db push --linked --dry-run
```

The final dry run must say there is nothing to apply. Do not use dashboard SQL
editing as a substitute for migrations. Do not run `db push` with a Production
reference. Supabase documents that `db push` applies linked-project migrations
and records migration history:
<https://supabase.com/docs/reference/cli/supabase-projects-create#supabase-db-push>.

## Remote security verification

The approved linked-project gate is transactional and rolls back its synthetic
users/rows:

```sh
supabase db query --linked --file supabase/tests/hosted_staging_validation.sql
bash supabase/tests/hosted_staging_data_api.sh
supabase db advisors --linked --type security --level warn \
  --fail-on none --output json
```

The Data API script refuses any linked project whose name is not exactly
`WayTask Staging`, uses only the client-safe publishable key in process memory,
and never requests a service-role key. The current assertion totals are 56/56
hosted database assertions and 18/18 HTTPS/Auth assertions, including unsigned/
forged JWT denial and the Apple-only provider contract. Email Auth is disabled.

Confirm all expected public tables have both RLS and FORCE RLS, private/admin
schemas have no `anon`/`authenticated` access, anonymous private reads/writes
fail, A cannot access B by exact UUID or manipulated filter, owner mutation and
parent-child bypass fail, and only published catalog metadata is anonymous.

Then test through the hosted HTTPS gateways with synthetic staging accounts:

- missing, malformed, expired, revoked, wrong-project issuer/audience JWT;
- anonymous private-table GET/POST/PATCH/DELETE;
- A reads/updates/deletes B and guesses exact IDs;
- A changes `owner_user_id` or points a child to B's parent;
- broad `or`, filter, range, and query manipulation;
- duplicate request/idempotency behavior;
- client access to `waytask_private` and `waytask_admin`;
- published versus unpublished shared catalog metadata.

Record sanitized request IDs/statuses and assertion counts only. Never capture
JWTs, emails, names, or row contents in test reports.

The Supabase Dashboard for **WayTask Staging** now shows Apple as the only
enabled Auth provider. The exact remaining identity/session checklist is in
[WT-032B.1 external QA](../WT-032B.1/EXTERNAL_SIGNED_SESSION_QA.md).

See [the executed hosted validation report](REMOTE_STAGING_VALIDATION.md) for
the hosted proof, subsequent real-device auth proof, and deferred adversarial
signed-session matrix.

## Build and device gate

Completed on 2026-08-08: `WayTask-Staging` built, signed, installed, and launched
on a registered physical iPhone. The built configuration resolved Accounts ON,
Sync/Migration/Secure AI OFF, the bundle ID to `h.WayTask.staging`, and the
signed entitlement `com.apple.developer.applesignin` to `Default`. Native Apple
sign-in, Private Relay, session restoration, sign-out persistence, and
same-account re-sign-in passed.

Production remains explicitly disabled and unconfigured throughout this process.
