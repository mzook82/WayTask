# WT-032B — Supabase Staging + Sign in with Apple Foundation

Status: implemented and locally proven; remote staging and physical-device
Apple authorization remain external gates. Production accounts, sync,
migration, and Secure AI remain disabled.

## Baseline audit

- Branch was `main` at `aacced0` (`WT-MAP-R1`) with a clean working tree.
- WT-032A account/configuration/error/state foundations and its ordered
  migrations were present. Guest was the default and the disabled sync provider
  made zero network requests.
- ProductState V4 remained the local runtime and write authority. Account code
  had no ProductState repository, `ModelContext`, Shopping, Map, Camera, Scanner,
  catalog, or Product Knowledge write access.
- The WT-032A ownership state rejected retargeting linked or pending data to a
  second user, but its dataset binding was process-local. WT-032B persists the
  binding in a protected Application Support sidecar without storing ProductState
  content or activating migration.
- Ten public Data API tables had RLS and FORCE RLS. Policies derived private
  ownership from `auth.uid()`, denied client deletion/status forgery, protected
  parent-child ownership, hid the administrative schema, and exposed only
  published catalog release metadata to anonymous readers.
- Debug and Release had blank Supabase configuration and every cloud flag OFF.
  The iOS environment enum still included `development`; WT-032B reduced this
  to the strict `local`, `staging`, and `production` set.
- Production bundle identifier remains `h.WayTask`; Staging is isolated as
  `h.WayTask.staging`. No Apple entitlement existed before this sprint.
  `WayTask.entitlements` is assigned only to Staging and declares the Sign in
  with Apple capability; its matching App ID/provisioning capability still
  requires Apple Developer portal confirmation.
- No auth token storage existed. Sessions now use a ThisDeviceOnly Keychain item;
  ownership metadata uses an atomic complete-file-protection sidecar. Tokens
  never enter ProductState, `UserDefaults`, plist configuration, diagnostics, or
  UI state.
- WT-032A.1 had already removed the bundled `Secrets.plist`, direct Gemini
  endpoint, and client credential path. Secure AI required an access-token
  provider and was OFF. WT-032B supplies a token only for an authenticated,
  unexpired staging session and only when the independent Secure-AI flag is ON.
- `WT-MAP-R1` is the audited parent commit. Authentication changes do not touch
  map-model freshness, store compatibility, notification/geofence authority, or
  their services. Their regression suites remain release gates.

## Environment and feature boundary

| Build/configuration | Accounts | Sync | Migration | Secure AI | Credentials |
|---|---:|---:|---:|---:|---|
| Debug | OFF | OFF | OFF | OFF | absent by default |
| Staging | ON only after valid config | OFF | OFF | OFF | dedicated staging URL + client publishable key only |
| Release/Production | OFF | OFF | OFF | OFF | absent |

`WayTask-Staging` uses `Staging.xcconfig` and the `STAGING` compilation
condition. It has no Production fallback. A missing, placeholder, partial,
non-TLS remote, privileged-key, wrong-environment, or unsupported configuration
fails closed before an auth client is created. Guest startup then performs no
cloud request and continues normally.

Only the ignored `Secrets-Staging.xcconfig` may supply the staging project URL
and client publishable key. A service-role/secret key, access/refresh token,
database password, Apple `.p8` key/client secret, Gemini key, or Production value
is prohibited in every client configuration and artifact.

## Authentication architecture

1. The internal account view invokes Apple's native
   `ASAuthorizationController` and official Apple button.
2. The app creates independent 32-byte random nonce and state values with
   `SecRandomCopyBytes`, sends SHA-256(nonce) to Apple, and compares returned
   state without early exit.
3. Only Apple's identity token and the original raw nonce are submitted as data
   to the fixed staging Supabase Auth `id_token` exchange. Authorization code,
   email, name, nonce, state, and tokens are never logged.
4. The authoritative account identity is the UUID returned by Supabase Auth.
   Apple name/email claims and editable fields never authorize a row.
5. Access and refresh tokens are stored as a versioned, environment/project-
   bound Keychain session. Restoration refreshes near-expiry sessions and calls
   Supabase `/auth/v1/user`; a revoked, stale, malformed, cross-environment, or
   mismatched session fails closed.
6. Sign-out asks Supabase Auth to revoke the local refresh-token family, then
   clears Keychain material even if the network request fails. Local data and
   its ownership binding remain.

Apple may return a name only on first authorization. WayTask holds that value
only as an ephemeral suggestion and saves it only after the user taps **Save
display name**. Email—including Apple Private Relay—is left to Supabase Auth and
is not displayed, copied into ProductState, validated by domain, or logged. This
also avoids breaking current or future relay domains.

## Account state machine and migration boundary

```text
Guest
  -> signing in
  -> authenticated / local data not backed up
  -> migration pending (prepared state only)
  -> sign out or session expired / local access preserved
```

Sign-in changes authenticated account state and persists only the pending target
binding. It does not read, serialize, upload, relink, delete, or edit any Product,
Shopping List, entry, store, session, history, Product Knowledge, or image. It
does not call the disabled sync provider. Migration and sync flags remain OFF.

The pending dataset UUID/target UUID survives relaunch. If User A is pending or
linked, User B may authenticate but receives a recoverable ownership-conflict
state; the local dataset remains bound to A and cannot be activated, retargeted,
or uploaded. A persistence failure disables authentication and preserves Guest
Mode rather than losing the guard.

## Session and recovery behavior

- Valid stored session: refresh if within 60 seconds of expiry, verify against
  the configured Supabase project, then restore signed-in state.
- Offline restore: expose **Offline**, withhold server authorization and Secure
  AI access, preserve the stored retry material and all local data.
- Revoked/expired/malformed session: clear unusable session material, show
  **Session expired**, preserve local data and ownership, and offer retry/sign-in.
- Apple cancellation: return to the prior Guest/expired state, record a
  cancellation diagnostic, and do not contact Supabase.
- Provider/service failure: show curated recovery copy; never expose raw Apple,
  Supabase, HTTP, JWT, SQLSTATE, response body, or stack text.

## Identity input security contract

There is no username/handle in WT-032B. If a public unique handle is later
needed it must be a separate field with an ASCII allowlist, canonical lowercase,
length/reserved-name policy, and database uniqueness; display name must never be
repurposed as a unique identifier.

Display name is optional at the account level, but a submitted value must:

- be NFC-normalized;
- trim surrounding whitespace and collapse internal whitespace runs to one
  ordinary space;
- contain 1–80 Unicode scalar/code-point characters after normalization, aligned
  with PostgreSQL `char_length`;
- contain no null, newline, tab, or other control character;
- reject zero-width space, word joiner, BOM, and Unicode bidi embedding,
  override, isolate, and mark controls;
- allow natural Hebrew/Arabic directionality, accented Latin, CJK, punctuation,
  apostrophes, and emoji;
- allow ZWJ for composed emoji and ZWNJ because it has legitimate meaning in
  Persian and other Arabic-script orthographies.

SwiftUI renders the value as `Text`; SQL-like and markup-like strings are not
special-cased or banned. The Data API receives JSON encoded by `JSONEncoder`,
never concatenated SQL. A database trigger independently performs NFC/space
normalization and an authoritative CHECK rejects bypasses. A future HTML,
email, log, shell, URL, filename, or admin surface must contextually escape the
stored value at output.

## Authorization and adversarial test matrix

Locally executed PostgreSQL proof:

- 50 authorization assertions: anonymous private denial, User A/User B
  isolation for read/update/delete, exact UUID guessing, broad/filter query
  manipulation, parent-child bypass, immutable owner, duplicate idempotency,
  client status forgery, private/admin schema denial, published catalog
  separation, and RLS/FORCE-RLS/policy coverage for all ten Data API tables.
- 30 original constraint assertions.
- 26 identity assertions: SQL and markup payloads stored/retrieved literally;
  tables/rows remain intact; international names and emoji accepted; combining
  text and spaces normalized; invisible/bidi/control/null/empty/overlong input
  rejected.
- 8 Secure-AI quota/idempotency assertions.
- Two clean rebuilds produced schema-identical output.

iOS contract proof covers secure challenge generation/hash, state mismatch,
Apple cancellation, zero-request Guest configuration, sign-in without sync,
restoration, expiration/offline, sign-out, relaunch/account switch, independent
Secure-AI gating, typed validation, fixed Supabase endpoints, JSON profile writes,
wrong-environment token rejection, 401/revocation behavior, and provider-error
redaction.

Real JWT signature, issuer/audience, stale/revoked token enforcement at the Auth
gateway and PostgREST ingress must be rerun against the actual staging project;
local unit/SQL tests do not claim remote-provider proof.

## Observability and privacy

Only these fixed events are logged: `auth_started`, `auth_succeeded`,
`auth_cancelled`, `auth_failed` plus typed category, `session_restored`,
`session_expired`, `signed_out`, and `migration_pending`.

Logs never contain identity/authorization code, access/refresh token, nonce,
state, email, name, user-entered profile text, database credentials, or Gemini
credentials. No raw provider/database response becomes user-facing copy.

## Sign-out and account switching

- Clear account-only ephemeral name/profile state and local Keychain session.
- Ask Supabase to revoke the current local refresh session when reachable.
- Preserve ProductState V4 and the guest/pending/linked ownership sidecar.
- Never relabel local records on sign-out or subsequent sign-in.
- Require the later reviewed recovery/migration flow when the next account does
  not match the pending/linked owner.
- Account deletion is intentionally not implemented in this sprint.

## Secure AI

Authentication makes a verified staging access token available to the existing
server quota authority only when all of these are true: internal Staging build,
staging environment, valid unexpired signed-in session, and independent client
Secure-AI flag ON. The flag remains OFF, the Function's server kill switch
remains OFF, anonymous use is impossible, Production is rejected, and no Gemini
credential enters iOS.

## Rollback and kill switches

Immediate rollback is to set `WAYTASK_CLOUD_ACCOUNTS_ENABLED=NO` or ship Debug/
Release. That prevents auth client construction and leaves Guest Mode intact.
Sync, migration, and Secure AI have independent OFF flags. Database changes are
rolled forward with a new migration; never edit or delete an applied migration.
Do not remove the local ownership sidecar during rollback because it prevents
cross-account retargeting.

## Remaining risks

- A real staging project, Auth configuration, Apple App ID capability,
  provisioning profile, and physical-device authorization are not repository
  operations and remain unproven.
- Remote Auth/JWT/audience/revocation and hosted RLS tests remain unexecuted.
- The ownership sidecar is a WT-032B guard, not the approved future sync ledger;
  the migration sprint must bind it transactionally to ProductState backup and
  canonical manifest evidence.
- Apple account-change server notifications and destructive account deletion
  need a separate compliance/backend design before Production accounts.
- Private Relay outbound email requires approved sending domains and SPF/DKIM;
  WT-032B sends no account email.
- Existing historical Gemini credential rotation remains an authorized Google
  Cloud owner action described by WT-032A.1.

See [staging setup](STAGING_SETUP.md) and [physical-device QA](PHYSICAL_DEVICE_QA.md).
