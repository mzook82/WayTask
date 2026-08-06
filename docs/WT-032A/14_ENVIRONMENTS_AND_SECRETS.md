# Environments and Secret Strategy

## Isolation

| Environment | Purpose | Identity/data rule | Promotion |
|---|---|---|---|
| Local Supabase | migrations, constraints, RLS and app integration on developer machine/CI | synthetic users only; local ports from `config.toml` | reset from Git migrations |
| Remote development/staging | integration, Auth provider sandbox, TestFlight-internal proof, load/restore drills | dedicated Supabase project and provider test tenants; no Production users/data | explicit reviewed staging deploy/link |
| Production | later real accounts and sync | separate organization/project, Auth providers, domains, backups, alerts and keys | separate manual/CI approval after go/no-go |

No database or Auth data is cloned from Production into development. Test users
use reserved invalid/test domains and providers. Production deployment jobs do
not run seed/test-user SQL. Project references are linked locally or in scoped CI
and are not encoded in migrations.

## Repository contract

`supabase/config.toml`, ordered migrations, seed-without-users, fixtures and SQL
tests are committed. `.branches`, `.temp`, `.env*` (except examples), function
environment files, database dumps and CLI login state are ignored. Every schema
change is a new migration; an applied migration is immutable.

The iOS build contract uses these Info/xcconfig keys:

- `WAYTASK_SUPABASE_ENVIRONMENT`: local/development/staging/production;
- `WAYTASK_SUPABASE_URL`: loopback HTTP(S) for local, HTTPS for remote;
- `WAYTASK_SUPABASE_PUBLISHABLE_KEY`: client-safe publishable or legacy anon
  value only;
- account, sync, and first-migration flags, each OFF by default.

Missing/all-placeholder values resolve to **not configured**. Partial, malformed,
non-TLS remote, non-loopback local, privileged-prefix, or privileged-JWT-role
values resolve invalid. Both outcomes disable client creation and preserve Guest
Mode. Feature dependencies are ordered: sync requires accounts; first migration
requires both.

## Allowed in iOS

Only the environment-appropriate Supabase project URL and client-safe
publishable/anon key may eventually be bundled. These are identifiers/client
credentials protected by RLS, not server authorization.

Never place a privileged Supabase server key, secret API key, database password,
Sentry upload/auth credential, Apple private key, SMTP credential, function
secret, refresh/access token fixture, or production dump in the repository,
xcconfig, plist, app binary, test fixture, log, crash report, or analytics.

Runtime user access/refresh tokens belong to the Auth SDK/Keychain and are never
ProductState fields. CI secrets are environment-scoped, least-privilege,
masked, rotated, and unavailable to untrusted pull requests. Production requires
different approvers and secret variables from staging.

Audit exception outside the new Supabase path: the existing Xcode project still
bundles the ignored `WayTask/Secrets.plist`, and artifact inspection confirmed
that its `GEMINI_API_KEY` value is non-empty. WT-032A did not read, print, copy,
or change that value, and no Supabase credential was added there. A bundled iOS
value cannot be treated as secret; before a Production account/sync pilot it
must be removed/rotated and the Gemini operation moved behind an authenticated,
abuse-controlled server path, or the value must be formally reclassified as a
restricted client credential with accepted extraction/quota risk. This finding
does not relax the prohibition on Supabase server credentials in the app.

## Deployment gate

Before any remote link/deploy, print only environment and project reference
suffix (never key), verify expected project through an independent check, run
clean reset plus RLS suite, scan artifacts, require migration review, and obtain
environment approval. Production rollout is never an automatic consequence of
merging local/staging migrations.
