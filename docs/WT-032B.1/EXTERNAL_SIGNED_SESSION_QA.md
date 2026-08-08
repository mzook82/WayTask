# WT-032B.1 External Signed-Session QA

This checklist begins only after explicit approval for each real identity or
administrative action. Use **WayTask Staging** and `h.WayTask.staging` only.
Never paste a JWT, refresh token, Apple token/code, service/secret key, database
password, email, or display name into chat, a command argument, Git, logs, or a
test report.

## Gate 0 — hosted provider policy — PASSED

Email Auth was disabled in **WayTask Staging** without changing Apple, JWT
settings, Production, or an iOS feature flag. The publishable-key-only hosted
Data API/Auth rerun passed 18/18, including Apple as the only enabled provider.
It created or modified no user or session.

## Gate 1 — obtain two genuine Staging identities

1. Make a second Apple account available on a second device or through an
   Apple-supported manual sign-in context. It must be genuinely different from
   User A and must authorize `h.WayTask.staging`.
2. Before creating User B, approve the additional real Apple identity action.
   Do not automate Apple's UI.
3. Confirm Supabase Authentication shows two different Apple/social Staging
   user UUIDs. Record only sanitized labels A/B and pass/fail; do not record
   email, Apple subject, name, or token.
4. Keep each short-lived session in its device Keychain or an approved
   no-echo ephemeral runner. Do not export either session through chat or shell
   command arguments.

## Gate 2 — live signed A/B Data API matrix

An approved ephemeral runner must use the client publishable key and each user's
real signed access token. It must first call `/auth/v1/user`, derive A/B UUIDs
from server-verified responses, and reject equal/zero UUIDs. It must not decode a
JWT to choose an owner.

For A and symmetrically for B, prove:

- create/read/update own disposable profile/list/product fixture;
- exact-UUID read/update/delete of the other user is denied or affects zero;
- broad `or`, range, and filter manipulation reveals no other-user row;
- `owner_user_id` mutation is denied;
- child creation under the other user's parent is denied;
- private/admin schemas remain unavailable;
- published catalog metadata remains readable and immutable.

Use UUIDs generated only for this test. Clean fixtures through a trusted
Staging-only administrative cleanup step after the assertions. Never add a
cleanup policy/RPC that weakens client RLS, and never upload ProductState.

## Gate 3 — valid foreign-project token

1. Select an existing disposable Supabase project that is neither WayTask
   Staging nor Production, or explicitly approve creation of one.
2. Create one disposable Auth session there without copying any WayTask data or
   configuration.
3. Give the ephemeral runner the foreign project URL/publishable key and token
   only through approved secret storage/no-echo input. Do not send values in
   chat or commit them.
4. Present that valid foreign signed token to WayTask Staging `/auth/v1/user`
   and a private Data API endpoint using the WayTask Staging publishable key.
   Both must reject it, and no row may be created/read/changed.
5. Destroy the disposable foreign session and remove temporary configuration.

This cannot be replaced by editing an `iss` claim: editing breaks the signature
and proves tamper denial, not valid foreign-issuer denial.

## Gate 4 — hosted refresh and natural expiry

Prefer the existing Staging JWT lifetime. If shortening is necessary, obtain
separate approval, snapshot the current value, use no value below Supabase's
recommended five-minute minimum, and restore the original setting afterward.
Do not change the iPhone clock.

1. Sign in User A manually and confirm local data remains available.
2. Relaunch within the client's 60-second refresh window or remain active until
   its scheduled expiry check.
3. Confirm one hosted refresh occurs, the session stays User A, and Supabase
   Auth audit logs record `token_refreshed` without exposing token content.
4. Repeat with network unavailable at refresh: app shows Offline, retains local
   data, and does not retry rapidly.
5. Restore connectivity and retry once; session must recover without Apple UI
   when the refresh family is valid.

## Gate 5 — administrative revocation

This gate needs a trusted Staging administrative action. Never place a secret
key in iOS. The preferred action is the supported Supabase Auth admin sign-out
boundary executed in a trusted ephemeral/server environment against the exact
test session. If that environment is not available, stop rather than deleting
the Auth user or editing schema.

1. Leave User A signed in on the Staging device.
2. From the trusted admin boundary, revoke only the disposable User A Staging
   refresh session. Do not revoke/delete Production users and do not delete the
   Staging Auth user.
3. Because an issued access JWT remains valid until `exp`, wait for the next
   scheduled refresh or relaunch after access expiry.
4. Confirm refresh is denied once; the app shows Session expired, clears its
   Keychain session, retains local ProductState/ownership, starts no sync or
   migration, and offers Sign in with Apple.
5. Reauthenticate manually and confirm recovery to the same Staging user.
6. Verify Auth audit logs show only the expected revocation/refresh/login event
   categories. Do not export their identity/network metadata into the report.

## Gate 6 — real account switch

1. Sign in User A and verify A's pending ownership state.
2. Sign out through WayTask.
3. Sign in manually as genuinely different User B.
4. Confirm B cannot activate, relabel, or access A's binding and no cloud upload
   occurs.
5. Sign out B and return to A; only A may resume A's account context.
6. Confirm Sync Off, Migration Not performed, Secure AI Off, and Production
   untouched throughout.

## Evidence to record

Record project name, bundle ID, sanitized A/B labels, assertion counts, HTTP
status categories, timestamp, device/OS, and pass/fail only. Classify every item
as hosted, simulator, or physical-device proof. Do not record secrets or user
identity/profile content.
