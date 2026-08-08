# WT-032A.1 — Gemini Credential Remediation

Date: 2026-08-06

Scope: local/staging implementation only. Accounts, synchronization, first
migration, secure AI, and every Production path remain OFF.

## Decision summary

The old iOS-to-Gemini path was active when a key was available and the user
explicitly submitted a camera or imported photo. The ignored root
`Secrets.plist` was an unconditional member of the WayTask target's **Copy
Bundle Resources** phase, so its non-empty reusable Gemini key shipped in both
Debug and Release products. The same value was also expanded into the built
`Info.plist` through the optional ignored `Secrets.xcconfig` include. The key
was therefore extractable from an app/IPA and must be treated as compromised.

The direct provider and every client key lookup have now been removed. New
Debug and Release/generic artifacts contain neither `Secrets.plist`, the exact
incident value, a Gemini key marker, nor the Google Generative Language endpoint.
The developer's ignored local files were not deleted. Secure recognition now
has a protocol-backed, authenticated staging proxy contract and fails closed
until staging Auth supplies a real user access token and both client/server kill
switches are deliberately enabled. It cannot select Production and it never
returns an invented product while unavailable.

## Exact pre-remediation runtime path

1. `SecretsManager.swift` loaded `Bundle.main/Secrets.plist` and returned its
   `GEMINI_API_KEY` value after whitespace/placeholder normalization.
2. `GeminiAPIKeyProvider` in `GeminiProductRecognitionService.swift` tried, in
   order: `SecretsManager.geminiAPIKey`, built `Info.plist` key
   `GEMINI_API_KEY`, then process environment `GEMINI_API_KEY`.
3. `CameraViewModel.init()` constructed `GeminiProductRecognitionService`
   directly. This proved that the provider was the runtime default, not dead
   code or an unused SDK.
4. AI Vision accepted a camera capture or imported photo, displayed a review,
   and called the provider only after the user chose **Use Photo**. Barcode mode
   queried Open Food Facts first; a miss/incomplete result offered **Improve
   with AI**, then used an explicitly captured/imported package photo.
5. The provider posted JSON directly from iOS to the fixed
   `generativelanguage.googleapis.com` `generateContent` operation for a fixed
   Gemini model. The reusable key was a URL query parameter.

No `GoogleGenerativeAI` SDK was linked. The implementation used Foundation
`URLSession` directly. Product Knowledge/catalog lookup did not call Gemini;
it only consumed a reviewed recognition candidate after the recognition step.

### Build configuration proof

The pre-remediation `WayTask.xcodeproj/project.pbxproj` contained
`Secrets.plist in Resources` in the WayTask target's `PBXResourcesBuildPhase`
(Xcode UI: **WayTask target → Build Phases → Copy Bundle Resources**). That
phase had no configuration condition, so it ran for Debug and Release. Both
`Debug.xcconfig` and `Release.xcconfig` optionally included the ignored
`Secrets.xcconfig`; `Info.plist` expanded `$(GEMINI_API_KEY)`. There was no
Release/TestFlight exclusion and no AI feature flag.

Baseline generic-device builds proved:

| Artifact | `Secrets.plist` | Exact incident key | Direct Gemini endpoint | Other privileged credentials |
|---|---|---|---|---|
| Debug `.app` | Present, app root | Present in resource and built `Info.plist` | Present in executable | Supabase service-role/secret and Sentry auth token absent |
| Release `.app` (TestFlight-equivalent resources/code path) | Present, app root | Present in resource and built `Info.plist` | Present in executable | Supabase service-role/secret and Sentry auth token absent |

The configured Sentry DSN is a public client ingest identifier, not the Sentry
upload/auth token; the latter was absent. Supabase publishable/legacy anon
client values are public client credentials protected by authorization/RLS;
no Supabase privileged server key was found. No secret values were recorded in
this report.

### Data and privacy of the former request

The direct request contained a recompressed JPEG (longest side at most 1,280
pixels), a fixed product-recognition prompt, and—when present—the raw barcode
value and symbology. Re-rendering normally removed EXIF metadata, but there was
no authoritative upload-byte cap or MIME/content contract. A package image can
contain faces, home/work background, addresses, labels, reflections, readable
private text, or other user-owned content. The old implementation also forwarded
any barcode type, so a QR payload could have contained arbitrary sensitive text.

The request did not explicitly send an account/user ID, ProductState identity,
device/installation ID, location, locale field, saved product names, inventory,
shopping lists, or app logs. The fixed prompt preferred visible Hebrew names.
Google still received network metadata such as source IP. Debug logging included
configuration as a boolean, dimensions, byte count, elapsed time, confidence,
and generic failures—not the key—but the key's URL-query placement increased
proxy/network-log exposure risk. Diagnostics could retain/export the model's
result message; that path now records only a generic outcome.

### Former reliability behavior and removal impact

The direct request timeout was 20 seconds. There was no retry, idempotency,
user-level authorization, client/server rate limit, response-size limit, or cost
budget. HTTP/provider errors were reduced to manual-fallback messages, while
some debug/Sentry paths recorded generic provider failures.

Removing the file alone would not have crashed the app: the key provider
returned `nil`, recognition returned `unavailable`, and manual entry remained.
It would, however, have silently disabled AI Vision and barcode AI enrichment.
The remediation preserves that honest unavailable/manual path and adds explicit
secure-service configuration/authentication errors. Camera/barcode scanning,
Open Food Facts, imported/captured-photo review, manual product entry,
ProductState, Shopping, Products, Map, catalog, Product Knowledge, and Guest
Mode remain local and usable.

## Threat and cost assessment

- An IPA or installed `.app` can be copied and inspected; plist/binary
  obfuscation, renaming, Keychain, or app-side encryption cannot make a reusable
  provider secret confidential.
- An extractor could invoke the provider with arbitrary prompts or payloads,
  consume quota, create unexpected billing, trigger provider suspension, and
  disrupt legitimate users.
- The provider could not distinguish an authorized WayTask user from an
  attacker holding the key. There was no per-user quota, IP defense,
  idempotency, request allowlist, or server kill switch.
- Rotation required shipping and adopting a new app build; already distributed
  builds kept the old credential.
- User-selected images and text/barcodes crossed directly into a third-party AI
  privacy boundary without a WayTask server validation/normalization layer.
- URL-query credentials and raw provider errors/responses have elevated logging
  and telemetry exposure risk.

Credential classes are deliberately distinct:

- Public/publishable identifiers: bundle ID, Supabase project URL and
  publishable/legacy anon key, and Sentry DSN. They authorize no privileged
  operation by themselves and require server authorization/RLS/ingest controls.
- Restricted client API keys: extractable keys limited by API/application/quota
  restrictions. Restrictions reduce blast radius but do not provide secrecy.
- Privileged reusable server secrets: Gemini provider keys, Supabase
  service-role/secret keys, Sentry upload tokens, private keys, and database
  credentials. These never belong in iOS. WayTask treats the Gemini key as this
  class.

## Approved architecture and implemented boundary

```text
WayTask iOS (explicit Use Photo)
  → fixed staging Supabase Function URL + client publishable key + user JWT
  → JWT verification and environment/kill-switch checks
  → strict schema/MIME/size validation
  → transactional user + salted-IP quota and request UUID deduplication
  → fixed server-owned Gemini endpoint/model/prompt + server environment key
  → bounded, normalized response with allowlisted message code
  → reviewed candidate or honest unavailable/no-match state in iOS
```

The iOS authority is `AIProductRecognitionServicing` with
`SecureAIProductRecognitionService` as the runtime provider. Its endpoint is
derived only from the validated Supabase project URL plus the fixed
`/functions/v1/recognize-product` path. The client cannot provide a model,
Gemini endpoint, or prompt. `directClientFallbackAllowed` is permanently false.
Production cloud configuration is rejected even if flags are manually changed.

Request schema version 1 accepts only:

```json
{
  "schemaVersion": 1,
  "requestId": "UUID",
  "image": { "mimeType": "image/jpeg", "imageBase64": "..." },
  "barcode": { "value": "6-32 ASCII digits", "type": "allowlisted" }
}
```

Unknown fields are rejected, including `model`, `prompt`, endpoint, user ID,
location, and arbitrary metadata. QR data is not sent. iOS accepts at most 12
MiB of local input, re-renders to metadata-free JPEG, limits the longest side to
1,280 pixels and the upload to 2 MiB, limits the JSON body to 2,850,000 bytes,
times out at 20 seconds, and accepts at most 64 KiB from the proxy. The Function
allows JPEG only, verifies JPEG signatures and decoded/body limits, uses a 15
second Gemini timeout, caps the provider response at 64 KiB and the normalized
response at 32 KiB.

The staging quota RPC is callable only by an authenticated user. It derives the
owner from `auth.uid()`, serializes quota decisions, and starts at 6 requests per
user/minute, 60/user/day, 30/salted-IP/minute, and 300/salted-IP/day. A
user/request UUID primary key rejects duplicate requests. The two-day ledger
stores only user UUID, request UUID, salted IP hash, and timestamp—never image,
barcode, prompt, or response. These are provisional staging limits to tune from
cost/latency/rejection evidence. The Function fails closed unless one allowlisted
IP header is explicitly configured; staging must prove its ingress overwrites
that header and rejects client spoofing before the IP limit is trusted.

Both client `WAYTASK_SECURE_AI_ENABLED` and server
`AI_RECOGNITION_ENABLED` default OFF. The Function itself additionally accepts
only local/staging environments. Logs contain only a fixed event,
allowlisted outcome, duration, and provider response byte count. Raw images are
transient request memory and are not retained by WayTask by default. Provider
retention/training terms still require a staging legal/privacy review.

### Sign-in recommendation

Require a signed-in staging user and leave recognition disabled until WT-032B
provides a verified Supabase Auth session. Do not deploy an anonymous public
proxy and do not add an installation-token system merely to preserve the former
flow. A short-lived anonymous installation token would add a new issuer,
revocation, and abuse identity boundary that WT-032A does not currently have.
App Attest/DeviceCheck is useful later as defense in depth for a Production
pilot, but it does not replace user authorization, server validation, quotas,
or the kill switch.

## Error and privacy UX

The client maps failures to curated actions without displaying Gemini,
Supabase, HTTP, SQL, JWT, or stack errors:

| State | User behavior |
|---|---|
| Not configured / Production prohibited | Explain secure AI is unavailable in this build; add manually; no request |
| Offline | Explain photo stayed local; retry online or add manually |
| Authentication required / permission denied | Sign in/re-authenticate or add manually; no fallback provider |
| Rate limited | Honor bounded `Retry-After`; wait/retry or add manually |
| Payload too large / unsupported image | Choose a smaller/clear JPEG-compatible image or add manually |
| Service unavailable / recoverable server error | Retry later or add manually |
| Timeout | Retry or add manually |
| Invalid/empty result | Retake or add manually; no invented candidate |
| Duplicate request | Start a new capture/request; no duplicate provider call |
| Cancellation | Confirm cancellation and that the photo remained local |

The capture/import review now says that **Use Photo** sends a compressed,
metadata-free copy to the secure service. Cancel/retake keeps the image local.
The app does not automatically send camera frames or imported images.

## Secret removal and automated proof

`Secrets.plist` and `SecretsManager.swift` were removed from the Xcode project;
the key expansion was removed from `Info.plist`; both xcconfigs have only the
non-secret secure-AI flag defaulting OFF. The ignored local `Secrets.plist` and
`Secrets.xcconfig` were intentionally left on disk for the developer, but they
are no longer an app credential mechanism. The placeholder example explicitly
prohibits Gemini credentials.

`tools/security/scan-built-app-secrets.sh` inspects a built `.app`, not only
source. It fails on bundled secret-file names, Google/Gemini credential shapes,
Supabase server/secret keys, Sentry auth tokens, private keys, Gemini markers,
or the direct Google endpoint. During rotation it can compare the ignored
incident plist's value byte-for-byte without printing it. The baseline artifacts
failed this scanner; both remediated Debug and Release artifacts pass.
`tools/security/scan-tracked-source-secrets.sh` separately scans Git-tracked and
non-ignored working-tree files (never ignored developer secrets) and passes.

| Remediated artifact | Secret/resource result | Status |
|---|---|---|
| Debug generic `.app` | `Secrets.plist`, exact old value, key marker, endpoint, Supabase server secrets, Sentry auth token absent | Remediated |
| Release generic `.app` | same items absent | Remediated |

Already installed/distributed baseline builds remain extractable. Bundle removal
does not invalidate their key; rotation is still mandatory after the secure
staging path is deployed and verified.

## External staging prerequisites

1. Create/select a dedicated non-Production Supabase staging project with no
   Production users/data and deploy all reviewed migrations and the Function.
2. Complete WT-032B staging Sign in with Apple/Supabase Auth and inject the
   current access token through the iOS `AccessTokenProvider`; never commit a
   token.
3. Configure only server-side Function secrets: replacement `GEMINI_API_KEY`,
   a random 32+ character `AI_RATE_LIMIT_HASH_SALT`, `WAYTASK_ENVIRONMENT=staging`,
   and platform-provided Supabase values. Configure `AI_TRUSTED_IP_HEADER` only
   after proving the staging ingress overwrites the selected allowlisted header
   (`cf-connecting-ip`, `x-real-ip`, or `x-forwarded-for`). Start with
   `AI_RECOGNITION_ENABLED=false`.
4. Configure iOS with the staging Supabase URL and client-safe publishable key;
   keep account, sync, migration, and secure-AI flags OFF for normal builds.
5. Run the database/RLS/quota suites and Function schema tests in staging. With
   synthetic images only, exercise auth rejection, malformed/oversized input,
   timeout, quota, duplicate request, normalized success, no-match, and kill
   switch behavior. Review privacy-safe logs and actual Gemini cost/quota data.
6. Enable accounts and secure AI only in an explicitly approved internal staging
   configuration. Synchronization and first migration remain OFF.
7. Validate explicit consent, cancel/retry/manual flows on a physical device;
   no real user images are part of this sprint.

No Production URL, key, account, sync setting, or deployment is included.

## Google Cloud restriction and rotation checklist

No key was changed or revoked automatically. An authorized Google Cloud owner
must:

1. Locate the current key using its provider-side key ID/fingerprint and audit
   metadata; do not paste or print its value.
2. Immediately restrict it to only the required Generative Language/Gemini API
   and the strongest supported application controls, recognizing that an iOS
   bundle restriction is damage limitation, not secrecy.
3. Set conservative per-minute/day quotas, project budget alerts, anomaly alerts,
   and usage dashboards; investigate usage by time/API/key before rotation.
4. Create a distinct replacement key for server-side staging only, with minimum
   API scope and staging-specific quotas/alerts.
5. Store that value only in the staging Function's environment-secret manager;
   never in Git, Xcode, plist, xcconfig, app storage, logs, or CI artifacts.
6. Validate the authenticated proxy with synthetic images, kill switch, schema,
   timeout, rate, idempotency, response, privacy-log, and cost controls.
7. Confirm the old key is absent from all current source/configuration and new
   Debug/Release/TestFlight artifacts. Retire any superseded TestFlight build
   where operationally possible.
8. Revoke/delete the old key after the replacement staging path is verified and
   the new app build is the approved build.
9. Verify an authorized test using the old key is rejected, then review provider
   usage for continued attempts and handle them as incident indicators.
10. Repeat with a separate Production project/key only after explicit Production
    approval, privacy review, physical-device validation, tuned quotas, and a
    go/no-go review.

## Validation evidence

Implemented and automatically proven in this sprint:

- Debug and Release generic iOS builds succeeded.
- Baseline built products proved the exposure; remediated built-product scans
  proved bundle/key/endpoint removal.
- Secure-AI iOS tests prove disabled/missing-auth zero-network behavior,
  Production rejection, permanent direct-client prohibition, fixed request
  authority, size/MIME limits, safe error mapping, and no fake candidate.
- Existing account/configuration/Guest zero-network and scanner/ProductState
  integration tests pass in the focused simulator run.
- The repository-wide serial non-performance suite passes 852/852 with zero
  failures or skips, covering ProductState, Shopping, Products, Camera/Scanner,
  Map, catalog, Product Knowledge, account/configuration, and secure AI.
- Six Node contract/runtime tests pass for valid, unknown-field,
  malformed/oversized, unsupported-image, rate/kill-switch, fixed-provider,
  bounded-stream, privacy-log, and response-normalization behavior.
- PostgreSQL authorization (50), constraint (30), and secure-AI quota (8)
  assertions pass; two clean rebuilds are schema-identical.
- Tracked-source secret scan, plist lint, and `git diff --check` pass.

The local Supabase Edge container could not be booted because this machine has
neither Docker nor Podman; the handler was instead executed under a no-network
runtime shim and its TypeScript syntax check passed. Requires staging
configuration: deployed Function runtime, real JWT wiring, provider integration,
cost/abuse monitoring, and remote migration/RLS proof.
Requires Google Cloud Console: restriction, replacement-key creation, quota and
billing alert configuration, usage review, and eventual revocation. Requires a
physical device: camera/photo consent wording, offline/timeout/cancel/retry,
Auth session, and internal staging request validation. Requires post-deployment
rotation: rejection and monitoring of the old key.

## Files changed and compatibility

- iOS authority/configuration/UI: `GeminiProductRecognitionService.swift`
  (legacy filename, secure provider only), `CameraViewModel.swift`,
  `CameraView.swift`, `SettingsView.swift`, `WayTaskCloudConfiguration.swift`,
  `WayTaskApp.swift`, `BetaDiagnostics.swift`, and `BetaDiagnosticsView.swift`.
- secret/build configuration: `WayTask.xcodeproj/project.pbxproj`,
  `WayTask/Info.plist`, `Debug.xcconfig`, `Release.xcconfig`, and
  `Secrets.xcconfig.example`; tracked `SecretsManager.swift` removed.
- server boundary: Function contract/runtime, migration, environment/config,
  SQL/Node tests, and Supabase test/rebuild runners under `supabase/`.
- assurance: secure-AI/account tests and both scanners under `WayTaskTests/` and
  `tools/security/`.
- documentation: this report and WT-032A environment, threat, validation, rate,
  error, privacy, and WT-032B prerequisite documents.

No ProductState schema or local record is migrated/deleted. Historical local
diagnostics JSON/UserDefaults keys retain their old names for compatibility,
while presentation labels use “Secure AI.” Guest Mode creates no secure-AI
request. The only user-visible regression is intentional: AI recognition is
honestly unavailable until approved staging Auth/proxy configuration exists;
manual entry and non-AI recognition continue.

## WT-032B sequencing and remaining risks

This remediation removes the bundled-secret blocker but does not enable WT-032B
accounts or sync. WT-032B staging authentication must come first so the secure
AI token provider can use a verified signed-in session. The quota migration and
Function may be deployed disabled during that staging work; secure AI is enabled
only after Auth, server secrets, synthetic integration tests, monitoring, and
approval. Sync and first migration remain independently OFF.

Remaining risks are: the old key remains usable until an authorized rotation;
old distributed builds retain it; the Function has not run against a remote
staging Gemini project; provider data terms and App Store privacy disclosures
need review; IP/user quotas need staging tuning and can still face distributed
abuse; App Attest/DeviceCheck is not implemented; physical-device UX/network
behavior is unverified; and a future authenticated token provider must preserve
the current fail-closed policy.
