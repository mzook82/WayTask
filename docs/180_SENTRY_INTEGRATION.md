# Privacy-Safe Sentry Integration

**Sprint:** RC-1  
**Date:** July 14, 2026  
**Organization:** `waytask`  
**Project:** `waytask-ios`  
**SDK:** Sentry Cocoa 9.21.0 through Swift Package Manager  
**Linked product:** `Sentry` only

## Purpose

WayTask uses Sentry for sanitized crash and non-fatal operational diagnostics during the external beta. This integration does not add product analytics and does not change Planner, store resolution, Map, notification, geofence, recognition, persistence, or Shopping decisions.

If no valid DSN exists, `SentrySDK.start` is never called. The reporting service, context updates, breadcrumbs, and DEBUG test actions then no-op safely.

## Local DSN Setup

`Debug.xcconfig` and `Release.xcconfig` optionally include the ignored `Secrets.xcconfig`. Copy the relevant lines from `Secrets.xcconfig.example`; do not put a real DSN in the template, Info.plist, Swift source, documentation, or Git.

Because xcconfig treats `//` as a comment, preserve the two URL slashes with `/$()/`:

```xcconfig
SENTRY_DSN = https:/$()/PUBLIC_KEY@ORGANIZATION_INGEST_HOST/PROJECT_ID
```

The processed app Info.plist receives `SENTRY_DSN` through build-setting substitution. Runtime validation requires an HTTPS scheme, host, public-key user component, and project path. Blank, unresolved, or malformed values disable Sentry without a crash or console output containing the DSN.

To disable Sentry, remove/comment the local `SENTRY_DSN` setting or set it to an empty value, then clean/rebuild and relaunch.

## Initialization

`WayTaskApp.init()` calls `SentryReportingService.startIfConfigured()` before app state and UI workflows begin.

Configured values:

- Environment: `development` in DEBUG; `beta` in Release/TestFlight.
- Release: `<bundle identifier>@<marketing version>`.
- Dist: `CFBundleVersion` build number.
- SDK diagnostics: enabled only in DEBUG at warning level; disabled in Release.
- Error event sample rate: default 100% for intentionally reported errors/crashes.
- Trace sample rate: `0`; automatic performance tracing disabled.
- Profiling: not configured.
- Session Replay: session and error sample rates both `0`.
- Maximum breadcrumbs: 40.

The integration also disables automatic sessions, watchdog termination reports, app-hang tracking, automatic/network breadcrumbs, URL/network failure capture, swizzling, user-interaction tracing, UIViewController tracing, Core Data tracing, file I/O tracing, MetricKit, logs, screenshots, and view hierarchy capture.

## Event Privacy Rules

Every event passes through `beforeSend`. The filter:

- Removes user, request, server name, transaction name, extras, original Error object, module list, and custom fingerprint.
- Keeps only `area`, `operation`, and `category` tags.
- Keeps only WayTask workflow breadcrumbs and their enum-backed generic fields/aggregate counts.
- Replaces unapproved free-form messages and all exception values with generic text.
- Keeps only allowlisted `app`, `device`, `os`, and `waytask` context fields.
- Removes attachments from every capture scope.

Original `Error` values are accepted by the reporting API, but the transmitted NSError contains only a WayTask operation domain, numeric error code, and enum-backed safe message. Original localized descriptions and userInfo are not sent.

### Allowed

- App version, build number, beta/development environment, and bundle identifier.
- iOS name/version/build and Sentry-provided device family/model/model ID/architecture/simulator state.
- Generic area: Home, Products, Shopping, Map, Settings, or Camera.
- Generic operation: planner, store_discovery, notification, geofence, recognition, persistence, or diagnostics.
- Generic issue category: integration, operational, persistence, or test.
- Aggregate integers: `item_count`, `store_count`, `planning_duration_bucket`, and `discovery_result_count`.
- Symbolicated stack frames, binary images/debug metadata, error type, and numeric error code.

### Prohibited

- Product or shopping-list names, raw list contents, IDs, photos, image data, OCR, prompts, or recognition response bodies.
- Exact coordinates, route history, addresses, store names, or notification text/payloads.
- Email, person name, address, account/user/install identifier, advertising identifier, or exact device name.
- API keys, DSN, auth token, headers, query strings, request/response bodies, Gemini prompt, or authentication state.
- Screenshots, view hierarchy, Session Replay, logs, or arbitrary attachments/extras.

`sendDefaultPii` is false and `beforeSend` clears the event user, including any SDK-generated installation identifier or IP field. Because the ingest service can still observe a connection address, enable Sentry project-side **Prevent Storing of IP Addresses** before beta distribution.

## Reporting And Breadcrumb Coverage

`SentryReportingService` is the only source file that imports Sentry. It supports sanitized Error capture, enum-backed message capture, operation/category/area tags, allowlisted numeric context, generic breadcrumbs, and safe no-op behavior.

Non-fatal issue paths include:

- Planner timeout.
- MapKit store discovery error.
- Notification authorization/scheduling error and malformed deep link.
- Geofence monitoring failure, excluding user denial/authorization errors.
- Gemini transport/provider/decoding failure and OpenFoodFacts lookup failure.
- Existing SwiftData/session/store persistence errors.

Expected states such as no selected products, permission denial, no matching store, no product match, and cancellation do not create Sentry issues.

Breadcrumbs cover app launch, recognition start/complete/fail, plan start/ready/fail, Map open, notification deep-link handle/fail, and Shopping session start/complete. They contain generic state and aggregate counts only.

## DEBUG Test Procedure

The test UI and intentional crash method are compiled only in DEBUG.

1. Configure a local Debug DSN and rebuild.
2. Open Settings and activate Developer Mode with the existing seven-tap gesture.
3. Open Developer -> Beta Diagnostics -> Sentry Test (DEBUG Only).
4. Confirm Status is Enabled.
5. Tap Send Non-Fatal Test Event once.
6. In Sentry, confirm one event named `WayTask DEBUG non-fatal test`, environment `development`, correct release/dist, and only the allowed context above.
7. Tap Trigger Intentional Crash, read the warning, and explicitly choose Crash Now.
8. Launch the app again without a debugger attached. Wait for the previous-run crash envelope to upload, then confirm symbolication and privacy fields in Sentry.

The test action requests a two-second background flush. Sentry's flush API does not return delivery confirmation, so server receipt remains the authoritative check.

## dSYM Upload

Release already uses `DWARF with dSYM File`. The target has an `Upload Sentry Debug Symbols` build phase after Resources. Its upload operation is archive-only: the phase exits immediately unless both `CONFIGURATION=Release` and `ACTION=install` are true, so ordinary Debug and Release builds do not upload symbols. Xcode environment-variable logging is disabled for this phase so the DSN or inherited credentials are not echoed in its build log.

The script:

- Authenticates from a masked CI `SENTRY_AUTH_TOKEN` environment secret or a local `~/.sentryclirc`/ignored project `.sentryclirc`.
- Sets organization `waytask` and project `waytask-ios`.
- Calls `sentry-cli debug-files upload "$DWARF_DSYM_FOLDER_PATH"` without uploading source context.
- Emits a non-blocking generic warning and succeeds when authentication or the CLI is absent, or upload fails.
- Never prints the token.

### Local Auth Token

Install the official `sentry-cli`, create a minimally scoped token in Sentry, then run `sentry-cli login` so the credential is stored outside the repository in `~/.sentryclirc`. A project-local `.sentryclirc` is also ignored, but the home-directory configuration is preferred.

For CI, store `SENTRY_AUTH_TOKEN` in the CI secret manager as a masked value and inject it into the archive environment. Do not put the auth token in `Secrets.xcconfig`, an Xcode build setting, source, or a visible command argument; build-setting inspection can expose it.

### Verification

1. Archive the Release app.
2. In Organizer, Show in Finder -> Show Package Contents -> `dSYMs/WayTask.app.dSYM`.
3. Run `dwarfdump --uuid` on the archive dSYM and record the UUID.
4. Check the archive build log for the upload phase and no warning.
5. In Sentry -> Project Settings -> Debug Files, confirm the matching UUID exists.
6. Confirm a DEBUG/device validation crash is symbolicated before distributing the TestFlight candidate.

## Privacy Manifest And App Store Connect

Sentry Cocoa 9.21.0 contains `Sources/Resources/PrivacyInfo.xcprivacy`, embedded by its XCFramework. The SDK manifest declares, for App Functionality and not for tracking or linkage:

- Crash Data.
- Performance Data.
- Other Diagnostic Data.

It declares required-reason API use for UserDefaults (`CA92.1`), system boot time (`35F9.1`), and file timestamps (`C617.1`).

These are the SDK's manifest declarations, not a complete answer for the whole app's App Store privacy labels. The owner must review the built privacy report and WayTask's total data practices. For this Sentry configuration, the transmitted behavior is sanitized crash/non-fatal diagnostic data and the allowlisted technical context above; no tracking, product analytics, PII, exact location, product content, screenshots, view hierarchy, or replay is intentionally sent.

## TestFlight Validation Checklist

1. Build/launch DEBUG and Release with `SENTRY_DSN` empty; confirm normal behavior and no Sentry network/log activity.
2. Build/launch DEBUG with the local DSN; confirm Sentry reports Enabled in Beta Diagnostics without displaying the DSN.
3. Send one non-fatal test event and verify development environment, release, dist, app/OS/device context, generic tags, and no prohibited fields.
4. Perform the confirmed crash test on a physical DEBUG device without a debugger; relaunch and verify one symbolicated event.
5. Archive Release with the auth token and CLI; verify archive dSYM UUID upload.
6. Install the TestFlight build; confirm environment is beta and Debug-only Sentry Test UI is absent.
7. Exercise Planner success/expected empty/no-match states, store discovery, Map, notifications/deep links, geofence, Gemini/OpenFoodFacts, persistence, and Shopping sessions.
8. Confirm expected user states do not create issues and only generic breadcrumbs appear.
9. Inspect received events for product names, list content/IDs, photos, coordinates, addresses/store names, notification payload/text, email/name/address, keys/tokens/headers, Gemini prompt, and auth data; all must be absent.
10. Compare launch, scrolling, Map, plan generation, and Shopping responsiveness with the prior build. Traces/profiling/replay/hang tracking are disabled.

## Automated Validation Record

The July 14, 2026 unsigned generic-device Debug and Release builds resolved and compiled Sentry Cocoa 9.21.0. With the ignored local configuration containing no Sentry DSN, both processed app Info.plists contain an empty `SENTRY_DSN`; the app therefore takes the no-op startup path. Release generated a valid arm64 `WayTask.app.dSYM`, and the optimized app contains none of the DEBUG-only Sentry test/crash UI strings. The built app embeds `Sentry.framework/PrivacyInfo.xcprivacy`, and repository inspection confirms that `SentryReportingService.swift` is the only Swift file importing or calling the SDK directly.

A configured-DSN launch, server receipt/field inspection, prior-run crash delivery, symbol-server receipt, and TestFlight regression comparison require the owner's Sentry credentials and a physical-device/TestFlight run. They are intentionally not claimed by the automated build.

## Rollback

Immediate operational disablement: clear `SENTRY_DSN` locally/CI and rebuild. No source change is required.

Full code rollback:

1. Remove the `Sentry` package product and package reference from the target/project.
2. Remove the `Upload Sentry Debug Symbols` build phase and Release target script-sandbox override.
3. Remove `SENTRY_DSN` from Info.plist and xcconfig/template files.
4. Remove `SentryReportingService.swift` and its enum-backed calls/test UI.
5. Re-resolve Swift packages, build unsigned Debug, archive Release, and verify product behavior.

Do not delete local credentials as part of a Git rollback; rotate/revoke them in Sentry if exposure is suspected.
