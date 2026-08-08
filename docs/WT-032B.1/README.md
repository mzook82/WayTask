# WT-032B.1 — Staging Signed-Session Adversarial Closure

Status: **COMPLETE WITH EXPLICIT DEFERRED EXTERNAL QA** as of 2026-08-08.

The repository-side refresh, expiration, revocation-recovery, project-binding,
and fail-closed session work is implemented and locally tested. Hosted WayTask
Staging rejects missing, malformed, unsigned, and forged bearer tokens, exposes
Apple as its only enabled provider, and passes the complete 18/18 HTTPS/Auth
gate. Migration foundation implementation may proceed, but activation remains
blocked by the live two-user gate and the explicitly deferred hosted
session/foreign-project evidence.

Sync, Migration, Secure AI, and Production remain OFF. No ProductState content
was read, serialized, uploaded, migrated, relinked, or deleted.

## Baseline audit

- Sprint-start branch was `main` at `12e1a70` with a clean working tree.
- WT-032B's native `AuthenticationServices` flow, nonce/state validation,
  Supabase native Apple exchange, ThisDeviceOnly Keychain session, persistent
  ownership sidecar, Guest state machine, and Staging-only account UI were
  present.
- The signed bundle remains `h.WayTask.staging`; Production remains
  `h.WayTask` and has no account configuration or account entitlement change.
- The ignored `Secrets-Staging.xcconfig` remains Git-ignored with mode `0600`.
  It contains the client-safe Staging URL/publishable configuration and is not
  printed or copied into this report.
- A tracked-configuration drift was found: `Staging.xcconfig` also enabled
  Accounts. Its fallback is now OFF, so the ignored Staging configuration is
  the only source that can opt Accounts in. Debug and Release remain OFF.
- Sync, Migration, and Secure AI resolve OFF in Debug, Staging, and Release.
- ProductState V4 remains the local source of truth. Authentication code still
  has no ProductState, Shopping, Map, Camera, Scanner, catalog, or Product
  Knowledge writer.
- Ten public tables retain ENABLE RLS and FORCE RLS. Private ownership remains
  derived from `auth.uid()` and enforced again across parent/child policies.
- Four local and remote migration versions match; the linked-project dry run is
  up to date. The linked project name was verified as **WayTask Staging**.
- The current Security Advisor reports the reviewed authenticated Secure-AI
  quota RPC warning plus leaked-password protection disabled. Email Auth is now
  disabled, so the latter describes an inactive password capability rather than
  an enabled password entry point. Secure AI remains OFF and the quota RPC is
  not invoked.
- Existing device evidence remains valid: one real Apple identity completed
  native sign-in and Private Relay, restored after force-close, stayed signed
  out after force-close, and re-signed in to the same Supabase user without
  sync, migration, or duplicate account creation.
- No token/session injection hook exists in the production app. The only
  DEBUG-only expiration helper acts on in-memory test state and cannot inject
  or export a JWT; it is excluded from Release compilation.

## Signed-session trust model

The iOS client does not decode a JWT and treat its claims as authorization.

1. Build configuration selects one explicit environment and fixed HTTPS
   project origin. Stored sessions carry that environment/origin and fail closed
   before a request if either differs from current configuration.
2. Native Apple identity material is exchanged only with that project's
   `/auth/v1/token` endpoint. Supabase verifies Apple/OIDC material and returns
   the authenticated Supabase user UUID.
3. Restoration refreshes when required and calls the same project's
   `/auth/v1/user`. The returned authoritative UUID must equal the securely
   stored UUID. Zero or mismatched UUIDs are rejected and session material is
   cleared.
4. Data API requests go only to the fixed project origin. The hosted JWT
   verifier validates the signature and token claims; PostgreSQL RLS derives
   row ownership from the verified `auth.uid()`. Editable IDs, names, filters,
   or Apple profile fields never become authorization authority.
5. Access/refresh tokens remain in a non-synchronizable
   `AfterFirstUnlockThisDeviceOnly` Keychain item. They never enter ProductState,
   UserDefaults, plist, diagnostics, analytics, UI state, or documentation.

Supabase access-token claims include `iss`, `aud`, `exp`, `iat`, `sub`, `role`,
and `session_id`. The server must validate signature and required claims before
RLS may see a subject. The app deliberately verifies server output instead of
implementing a second client-side JWT authority. See Supabase's
[JWT claims reference](https://supabase.com/docs/guides/auth/jwt-fields).

## Repository-side hardening completed

- A token response with the all-zero user UUID is rejected. The previous random
  `UUID()` comparison could not enforce that contract.
- Corrupt, wrong-environment, or wrong-project stored sessions are deleted
  strictly; a Keychain deletion failure becomes a typed secure-storage failure.
- A 401 from an authenticated profile request clears stored session material,
  removes in-memory account-only state, transitions to **Session expired**, and
  preserves the local ownership binding and all local data.
- A 403 remains **permission denied** and does not falsely destroy an otherwise
  valid session.
- A restoration 401 triggers at most one refresh attempt. Storage is retained
  when that refresh is offline, but cleared when refresh is denied, malformed,
  wrong-subject, or still unauthorized. This avoids both token loss during a
  transient outage and an infinite refresh loop.
- Successful refresh requires the returned Supabase UUID to match the original
  session UUID and persists the rotated token pair before restoration succeeds.

## Evidence classification

### Proven locally / simulator

- Fresh stored session: one `/user` verification, no refresh.
- Within-60-seconds and already-expired access tokens: one refresh, rotated
  pair persistence, authoritative `/user` verification, and restoration.
- Stale access token: one `/user` denial, one refresh, one verification; no
  unbounded retry.
- Offline refresh: recoverable Offline state and retained Keychain retry
  material, including after an initial stale-token 401.
- Denied/revoked refresh: one attempt, cleared storage, Session expired, safe
  recovery copy, and no retry storm.
- Protected-request 401: cleared session and recoverable expiration state.
- Protected-request 403: permission denial without false expiration.
- Refresh or `/user` subject mismatch, zero UUID, wrong environment, and wrong
  project origin: fail closed.
- Guest zero-cloud-request, migration/sync non-activation, ProductState/local
  ownership preservation, and cross-account non-retargeting remain covered.

These timing/provider responses are controlled test doubles. They prove client
logic, not a real hosted token aging or revocation event.

### Proven on hosted WayTask Staging

- Migration parity and deployed RLS/FORCE-RLS remain proven by the prior 56/56
  transactional PostgreSQL assertions.
- The extended live publishable-key HTTPS/Auth gate passes 18/18 checks:
  anonymous private denial, exact-UUID/filter attacks, private/admin schema
  denial, published catalog behavior, missing API/session denial, malformed
  bearer denial, unsigned `alg=none` denial, forged-signature denial, fixed
  issuer/JWKS discovery, non-empty verification keys, and Apple as the only
  enabled provider.
- Database-role User A/User B isolation remains 56/56 proven, but it is not
  represented here as a live signed-session A/B result.

### Proven on a physical iPhone

- Signed `h.WayTask.staging` bundle and Apple entitlement.
- Native Apple sign-in, Private Relay, one Supabase social user, force-close
  restoration, local sign-out persistence, and same-account re-sign-in.
- Cloud Staging / Sync Off / Migration Not performed / Secure AI Off throughout.
- No upload or migration occurred.

No new WT-032B.1 physical-device action has been performed. In particular, the
prior single-user happy path does not prove A/B isolation or server revocation.

## Automated validation

- 45/45 focused iOS Simulator tests passed: Supabase session client, account
  controller/state transitions, Guest/ownership foundation, and configuration.
- 15/15 ProductState persistence characterization tests passed.
- Generic unsigned `WayTask-Staging` / Staging build passed with bundle
  `h.WayTask.staging`; Accounts resolved YES from the ignored override and Sync,
  Migration, and Secure AI resolved NO.
- Generic unsigned `WayTask` / Release build passed with bundle `h.WayTask`; all
  four cloud flags resolved NO.
- Tracked-source and both built-app secret scans passed. No privileged credential,
  bundled secret file, or direct Gemini endpoint was found.
- The hosted HTTPS/Auth extension passed 18/18 after Email Auth was disabled in
  WayTask Staging. No user or session was created or modified by that rerun.
- No migration was applied and no hosted row was written by this sprint's HTTP
  extension. The previous 56/56 transaction remains the deployed RLS baseline.
- The prior 880/880 full non-performance regression was not redundantly rerun:
  Production assumptions and ProductState/Shopping/Map/Camera/catalog code did
  not change. The affected auth/configuration suites, local persistence suite,
  generic Staging build, and Release boundary build were rerun instead.
- Map/location/geofence suites were not affected: no shared app state, Map model,
  location manager, notification authority, or geofence service changed.
- `git diff --check` and final repository consistency checks are release gates
  and are recorded at handoff.

### Still externally unproven

| Gate | Exact missing proof |
|---|---|
| Real A/B isolation | Two different real Apple/Supabase Staging identities and live signed Data API requests in both directions |
| Valid-token claims | `iss`/project, `aud`, `sub`, `exp`, `iat`/`nbf` behavior after a genuinely valid signature, not only malformed/forged input |
| Wrong project | A valid signed session from a separate disposable non-Production Supabase project denied by WayTask Staging |
| Hosted refresh/expiry | A real near-expiry refresh, natural access-token expiry, offline recovery, and invalid refresh-token recovery |
| Administrative revocation | A real Staging refresh session revoked from a trusted administrative boundary and detected by the client at refresh |
| Real A → B switch | User A sign-out followed by genuinely different User B, with A's ownership binding still inaccessible |
| Apple lifecycle | Credential-state and Apple server-to-server account-change/revocation behavior |

## Refresh, expiration, and revocation contract

| Scenario | Client outcome | Current proof |
|---|---|---|
| Fresh access token | Verify with `/auth/v1/user`; restore | Local + prior real valid restoration |
| Within 60 seconds of expiry | Refresh once, persist rotation, verify | Local clock-controlled |
| Expired access / valid refresh | Refresh once, verify, restore | Local clock-controlled |
| Refresh offline | Offline; retain retry material and local data | Local controlled network failure |
| Refresh denied/revoked | Clear unusable storage; Session expired | Local controlled 401 |
| Protected request 401 | Clear session; Session expired | Local controlled 401 |
| Protected request 403 | Permission denied; keep session | Local controlled 403 |
| Relaunch after hosted expiry | Refresh or recover to expired state | Not yet hosted/device proven |

Supabase documents that refresh tokens rotate and that terminating a refresh
session does not invalidate an already-issued access JWT before its `exp`.
Therefore, the administrative-revocation device test must observe the next
refresh/expiry boundary; it must not falsely expect immediate Data API denial.
See [Supabase user sessions](https://supabase.com/docs/guides/auth/sessions) and
[sign-out scopes](https://supabase.com/docs/guides/auth/signout).

## Account switching and ownership

The local dataset binding is independent of Keychain session material. Sign-out
clears account-only ephemeral state and the local refresh family but does not
clear or retarget the binding. A different authenticated UUID is accepted only
as account identity; if the local dataset is pending/linked to User A, the state
machine exposes an ownership conflict and never grants User B the dataset.

This is locally proven with two UUIDs and persistence across authority
reconstruction. The same scenario with two real signed Apple sessions remains a
required external gate. No Guest → Account migration code is active.

## Privacy-safe diagnostics

Only fixed event categories and typed failure categories are emitted. Source
and tests confirm no access/refresh token, Apple identity token, authorization
code, nonce/state, email/Private Relay address, display name, profile input,
database credential, service/secret key, or Gemini credential is logged.

The hosted shell gate keeps the publishable key in process memory, suppresses
its output, and uses only non-secret fabricated JWT strings for negative tests.
It never requests a service-role/secret key.

## Apple credential-state decision

WT-032B.1 intentionally does not add a client-only Apple revocation observer.
The current app does not persist Apple's provider subject; the Supabase UUID is
the account authority. A correct lifecycle implementation must jointly define:

- secure storage and account binding for the Apple provider subject;
- `getCredentialState(forUserID:)` handling for authorized, revoked,
  transferred, and not-found results;
- server-side verification of Apple's signed account-change events and
  `consent-revoked`/`account-deleted` handling;
- Supabase identity unlink/delete/recovery rules and ProductState retention;
- user-facing account deletion and reauthentication behavior.

Apple's current guidance says native apps should use credential-state checks for
account deletion and that server-to-server notifications carry the authoritative
account-change events. See [Apple account-change guidance](https://developer.apple.com/documentation/signinwithapple/processing-changes-for-sign-in-with-apple-accounts)
and [TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple).

This is a named pre-Production compliance/backend slice. It is not replaced by
Supabase refresh validation, and it is not implemented superficially merely to
turn this staging gate green.

## Gate for Guest → Account Migration

Migration activation remains blocked until all of the following are recorded:

1. hosted Auth exposes Apple only — **PASSED, 18/18 hosted gate**;
2. real signed User A/User B symmetric isolation passes and disposable rows are
   cleaned up;
3. valid foreign-project token denial passes;
4. at least one real hosted refresh/expiration cycle passes;
5. administrative refresh-session revocation is detected and reauthentication
   succeeds while local data remains available;
6. real A → B account switching preserves A's ownership binding;
7. all staging-only flags and Production isolation are reverified.

Follow [the external signed-session QA checklist](EXTERNAL_SIGNED_SESSION_QA.md).
Do not enable Sync, Migration, Secure AI, or Production to perform any gate.
