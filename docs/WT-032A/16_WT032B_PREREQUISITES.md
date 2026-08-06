# WT-032B Prerequisites and Go/No-Go Checklist

WT-032B means implementing staging-only authentication integration, migration
preview/sidecar, and disabled-by-default sync slices—not Production activation.

## Required before coding the first remote flow

- [ ] Approve this cloud inventory, especially deferral of images,
  ProductKnowledge, sessions/history, and precise saved-store migration.
- [ ] Create a dedicated remote staging Supabase project with no Production
  users/data and record owners, region, plan and retention.
- [ ] Choose and configure staging Auth provider credentials/redirects; no final
  public login UI or Production Auth.
- [ ] Re-run migration from clean Supabase local stack and staging; run all 50
  authorization and 30 constraint tests against both.
- [ ] Add CI jobs for migration lint/reset, RLS suite, secret/bundle scan and iOS
  account contract tests.
- [ ] Approve the versioned local sync sidecar/schema migration, protected-store
  backup, entry revision strategy, migration manifest and rollback tests.
- [ ] Specify canonical JSON hashing and the first authenticated migration batch
  endpoint, including owner derivation, 500-row/1 MiB limits, receipts, exact
  retry response, rate limiter and monitoring.
- [ ] Implement staging observability using codes/counts only and prove tokens,
  shopping content, images and coordinates are absent from logs.
- [ ] Implement internal-only migration preview/cancel/resume/verification UI;
  account, sync and migration flags stay OFF in release/TestFlight config.
- [ ] Add network-failure, token-expiry, sign-out, app-termination, partial-batch,
  duplicate-retry, conflict and local-persistence tests.
- [ ] Define supported older app/schema compatibility and a cloud-write kill
  switch; local features must remain operational.
- [x] Remove the direct Gemini client/key loader and bundled `Secrets.plist`;
  add the authenticated staging proxy contract, disabled flags, quota boundary,
  artifact scanner, and safe unavailable UX.
- [ ] Wire secure AI to a real WT-032B staging Auth access token and validate the
  deployed Function with synthetic images before enabling its two kill switches.

## Required before any Production pilot (not WT-032B entry criteria)

- [ ] Separate Production project, environment approvals, secrets, Auth provider,
  domains, privacy labels/policy and support/deletion/export flows.
- [ ] Managed backup evidence, PITR decision, measured isolated restore drill,
  named operators, approved RPO/RTO and Storage backup plan.
- [ ] Provisional rate limits tuned from staging evidence and abuse alerts tested.
- [ ] Independent security review of migrations/RLS/Storage/Edge/auth redirects,
  dependency review and production artifact secret scan.
- [x] Remove the existing bundled Gemini key and direct Release request path;
  remediated Debug/Release artifacts prove the file/value/endpoint absent.
- [ ] Restrict and rotate the exposed historical Gemini key after the secure
  staging path is deployed and verified; prove old-key rejection. This requires
  authorized Google Cloud Console action and is not a Supabase-key operation.
- [ ] Explicit opt-in and privacy review for saved-store precision, images,
  notification/location behavior and analytics/monitoring.
- [ ] Small reversible pilot with flags, no automatic upload of existing
  TestFlight data, and signed release approval.

## Go/no-go evidence from WT-032A

- Guest-default account/config/sync/error foundation: implemented.
- Account, sync and migration flags: OFF in Debug and Release defaults.
- Secure-AI flag and server kill switch: OFF by default; Production is rejected.
- Supabase migration repository and default-deny policy matrix: implemented.
- Real PostgreSQL authorization suite: 50/50 passed.
- Real PostgreSQL constraint suite: 30/30 passed.
- Supabase CLI 2.111.0 applied migration and seed to a clean PostgreSQL 17
  database; a second migration dry run reported the database up to date.
- Two independent clean rebuilds: schema-identical.
- Generic Debug and Release iOS builds: passed; focused security/account/scanner
  tests and 852 repository-wide non-performance tests passed on iOS Simulator.
- Managed Supabase backup/restore, remote staging, interactive simulator account
  flows and physical-device account flows: intentionally not claimed.
- Gemini staging deployment/JWT wiring, Google key rotation, provider cost proof,
  and physical-device secure-recognition flow: intentionally not claimed.

## Recommended iOS authentication method order

1. **Sign in with Apple** — first and primary method for the iOS account
   foundation; use Supabase Auth OIDC/native Apple integration, nonce/state/PKCE
   protections as applicable, private email relay support, Keychain sessions,
   and account-deletion compliance.
2. **Passkey/WebAuthn**, when Supabase and the chosen native/browser UX are
   validated for WayTask’s deployment targets — preferred passwordless recovery
   expansion without inventing an app password store.
3. **Google Sign-In** only if user evidence justifies it and Sign in with Apple
   parity/policy requirements are met.
4. **Email magic link/OTP** as recovery/fallback after redirect, enumeration,
   abuse and deliverability controls are proven.
5. **Email/password** last, only if a documented requirement outweighs password
   reset, credential-stuffing and support risk.

WT-032B must implement only method 1 in an internal/staging slice unless a later
approved task changes scope. It must not add fake authentication or treat local
identity as a cloud session.
