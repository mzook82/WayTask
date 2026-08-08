# WT-032B Physical-Device QA

Executed on 2026-08-08 on a physical iPhone using the signed
`h.WayTask.staging` app connected only to **WayTask Staging**. This is real-device
evidence, not simulator, mock-provider, or unit-test evidence.

## Passed on the physical device

- [x] Signed bundle ID was `h.WayTask.staging`; the signed app and provisioning
      profile contained the Sign in with Apple entitlement.
- [x] App began in Guest and exposed the internal Staging account flow.
- [x] Account UI showed Cloud Staging, Sync Off, Migration Not performed, and
      Secure AI Off.
- [x] Native Sign in with Apple completed successfully.
- [x] Hide My Email/Apple Private Relay completed without a client-side domain
      assumption.
- [x] Supabase Auth created exactly one Apple/social user.
- [x] WayTask transitioned Guest → Signed in without starting sync or migration.
- [x] Apple supplied the optional display name on first authorization. It was
      absent after later restoration, matching Apple's one-time name behavior
      and WayTask's ephemeral suggestion contract.
- [x] Force-close/reopen restored the valid authenticated session without a
      second Apple interaction.
- [x] Sign-out returned to Continue as Guest.
- [x] Force-close/reopen after sign-out remained Guest; no signed-out Keychain
      session was restored.
- [x] Re-sign-in with the same Apple account succeeded and Supabase still showed
      exactly one user.
- [x] No ProductState, list, store, history, Product Knowledge, or other user
      dataset was uploaded, linked, or migrated.
- [x] Accounts remained Staging-only; Sync, Migration, and Secure AI remained
      OFF. Production `h.WayTask` remained untouched.

The Staging app has a separate local iOS container and displayed zero products
and zero shopping lists. This is expected isolation. It is not evidence of
Production data loss, and because the Staging dataset was empty it is not a
physical-device proof of preserving a non-empty Guest dataset.

## Not executed in this device run

- [ ] Cancel Apple authorization and verify cancellation returns to the prior
      state without mutation.
- [ ] Launch/restore offline and verify curated offline recovery.
- [ ] Allow a session to approach expiry and verify refresh/expiration recovery.
- [ ] Administratively revoke the server session and verify device recovery.
- [ ] Sign in as a different User B and verify no transfer/relabel of User A's
      pending or linked dataset.
- [ ] Exercise accepted/rejected display-name UI cases; these are proven at the
      local and hosted database boundaries, not on this device run.
- [ ] Exercise the full WT-MAP-R1, Products, Shopping, Camera/Scanner, catalog,
      and Product Knowledge physical-device smoke matrix; the 880-test local
      non-performance suite passed separately.

WT-032B.1 has not added new physical-device evidence. Its refresh/revocation and
project/subject hardening is locally tested, while real A/B switching, hosted
expiration, and administrative revocation still require the separately approved
[external signed-session checklist](../WT-032B.1/EXTERNAL_SIGNED_SESSION_QA.md).

Capture only pass/fail, app version/build, device/OS, sanitized diagnostic code,
and staging project reference suffix. Do not capture identity tokens, codes,
session tokens, nonce/state, email, name, or user dataset content.
