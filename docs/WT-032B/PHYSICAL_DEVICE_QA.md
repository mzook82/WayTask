# WT-032B Physical-Device QA

Use a registered device and the `WayTask-Staging` scheme connected only to the
dedicated staging Supabase project.

- [ ] Cold-launch as Guest; no account request occurs without a stored session.
- [ ] Existing ProductState V4 products/lists remain visible and editable.
- [ ] Open **Staging Account**; environment says Staging, Sync Off, Migration Not
      performed, Secure AI Off.
- [ ] Complete Sign in with Apple; observe **Signed in** and the exact warning
      that existing data remains on this device.
- [ ] Cancel Apple authorization; return to Guest/prior state with no error and
      no local mutation.
- [ ] Authorize with Hide My Email/Private Relay; sign-in succeeds without any
      client email-domain assumption.
- [ ] On first authorization, verify Apple name is offered only as an optional
      editable display-name suggestion. Reauthorize and verify missing name/email
      does not break the flow.
- [ ] Relaunch online; session restores through Supabase verification.
- [ ] Launch offline; local data remains usable and **Offline** recovery copy is
      shown without exposing a token/provider error.
- [ ] Revoke/expire the staging session; verify **Session expired**, local data
      preserved, Secure AI token unavailable, and reauthentication offered.
- [ ] Sign out online and offline; local data and pending ownership remain.
- [ ] Sign in again as the same Apple account; pending state remains and no upload
      occurs.
- [ ] User A sign-in → sign-out → User B sign-in; verify ownership-protected
      recovery state and no transfer/relabel of User A's local dataset.
- [ ] Inspect the staging database/network: no existing ProductState product,
      list, entry, store, history, session, image, catalog, or Product Knowledge
      row was uploaded automatically.
- [ ] Save accepted Hebrew, Arabic, accented Latin, CJK, and emoji display names;
      verify normalized retrieval as text.
- [ ] Verify invalid invisible/bidi/control/overlong display names show curated
      typed validation and no database/provider error.
- [ ] Exercise Map foreground/background return, fresh recentering, store/product
      compatibility, selection, navigation, geofence registration, cooldown, and
      notification deep link; compare with WT-MAP-R1 behavior.
- [ ] Exercise Products, Shopping, Camera/Scanner, catalog search, and Product
      Knowledge smoke flows.
- [ ] Confirm Secure AI remains disabled until its separate client/server kill
      switches receive later approval.
- [ ] Confirm Release/Production still shows no account UI and contains no
      Production Supabase configuration.

Capture only pass/fail, app version/build, device/OS, sanitized diagnostic code,
and staging project reference suffix. Do not capture identity tokens, codes,
session tokens, nonce/state, email, name, or user dataset content.
