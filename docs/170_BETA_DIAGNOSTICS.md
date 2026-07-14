# WayTask Beta Diagnostics Center

**Sprint:** 27B.5B  
**Date:** July 12, 2026  
**Status:** Implemented

## Purpose

The Beta Diagnostics Center is an optional internal runtime-observability surface for External TestFlight. It explains existing decisions; it does not make planner, recognition, store, ranking, notification, geofence, or Map decisions.

## Activation

Developer Mode is disabled by default. The normal Settings placeholder remains unchanged.

1. Open Settings.
2. Tap the Settings surface seven times.
3. Settings switches to the existing settings view.
4. Open Developer -> Beta Diagnostics.

Developer Mode can be disabled from the bottom of Beta Diagnostics. The Developer section is absent during normal consumer use.

## Runtime Coverage

### Planner

Records current list/counts, shared `ShoppingPlanGenerationState`, stage, start/end timing, last failure, coverage, matched/missing products, content-signature cache result, best store, scores, and ranking reasons. Repeated non-generation plan publications cannot reuse an earlier generation start time.

### Store Discovery

Records saved/MapKit/merged/deduplicated counts, accepted and rejected MapKit query results, rejection reasons, 3 km search radius, coordinate, cache hit/miss/in-flight/throttle reason, duration, and source labels. Each resolution receives a diagnostic session ID; task-local context keeps simultaneous Map, Nearby, Planner, and Geofence searches from mixing query counters.

Source labels are:

- Saved
- MapKit / Transient
- Transient
- Future Community
- Future Merchant

### Notifications And Geofence

Records notification fired/suppressed outcome and reason, type, time, store, coordinate, list, matched products, tap/deep-link result, and bottom-sheet completion. Geofence diagnostics distinguish resolved candidates from Core Location's actual `monitoredRegions` and record monitoring failures, region-limit suppression, entry, exit, trigger time, store, and distance.

### Map

Records user coordinate, camera center, region/span, approximate zoom, focused/selected store, visible runtime stores, visible circles, and store appearance/disappearance reasons.

### Gemini And Recognition

Records locally observed Gemini requests/success/failure, barcode fallbacks, barcode and OpenFoodFacts lookups, manual products, last/average recognition duration, Product Knowledge cache hits, provider misses, and an estimated 30-day Gemini request count. The estimate is projected only from local requests observed after Developer Mode is enabled.

## Beta Snapshot

`Capture Beta Snapshot` creates one in-memory value containing:

- Current diagnostics screen image.
- Current planner and ShoppingPlan state.
- Current discovery, notification, geofence, Map, recognition, performance, build, timestamp, and device state.
- Point-in-time Markdown and JSON reports.

The screen image is previewable inside diagnostics but is never added to report/share/save output. It is released when the process or snapshot value is replaced.

## Export

The export section supports Markdown or JSON and provides:

- Share Report: system Share Sheet.
- Copy Report: text to clipboard.
- Save Report: Files document exporter.

Reports include App, Planner, Store Discovery, Notifications, Geofence, Map, Gemini, Performance, Recent Errors, Recent Decisions, and Privacy sections.

## Privacy Review

Exports include diagnostic product names and the current diagnostic coordinate because those are required to explain matching and location decisions. They do not include:

- Product photos or image data.
- Snapshot screenshots.
- User email or authentication state.
- API keys, request authorization headers, or secrets.
- Precise route history; only current decision coordinates are included.
- Private account data.

The JSON privacy object explicitly records that images, credentials, and route history were not exported.

## Performance Safeguards

- Every telemetry entry point checks the Developer Mode flag before mutation.
- Maximum 200 in-memory events.
- Maximum 40 recent MapKit rejection reasons.
- Snapshots are created only by explicit action.
- Screenshots stay in memory and are not written automatically.
- Only aggregate timing and recognition counters persist in `UserDefaults`.
- No location callback triggers planner generation or report generation.
- No diagnostic publisher feeds back into runtime planning or store resolution.
- Disabled diagnostics return before monitored-region rows or rejected-store details are materialized.

### DEBUG Map Performance Counters

Sprint 27B.5E adds console-only DEBUG counters for native Map validation:

- `updateUIView` calls.
- Native annotation/overlay rebuilds.
- Identical native updates skipped by the stable signature.
- `MapViewModel.applyShoppingPlan` calls.

The counters are compile-time DEBUG state owned by the Map coordinator/view model. They are not `@Published`, do not append Beta Diagnostics events, do not capture snapshots, and are not visible in normal-user UI.

## Known Limitations

- Telemetry begins when Developer Mode is enabled; earlier runtime events are not reconstructed, although current planner/list/geofence state is synchronized when the center opens.
- Core Location entry/exit delivery remains device/OS controlled; monitored regions are exact at the time diagnostics reads `monitoredRegions`.
- MapKit rejection totals describe accepted/rejected query results and may exceed unique merged branch counts.
- A screenshot captures the Beta Diagnostics screen because the capture action is located there; screenshots are intentionally excluded from export.
- Device model is the local hardware identifier, not a marketing-name lookup.
- No server upload or remote telemetry exists.

## Field-Test Checklist

1. Fresh install or cleared defaults: confirm Settings shows no Developer section and normal Settings placeholder remains unchanged.
2. Tap Settings seven times: confirm Developer Mode activates and Developer -> Beta Diagnostics appears.
3. Disable Developer Mode inside diagnostics: confirm the Developer section disappears.
4. Generate a successful plan: confirm list counts, state, stages, duration, coverage, matched/missing products, best store, and ranking reasons match Shopping.
5. Force planner failures for no products, no location/stores, no matches, and timeout where practical; confirm exact failure reason and stage.
6. Repeat an identical plan publication: confirm Content Signature Hit and no duplicate timing sample.
7. Run saved-only, mixed, and MapKit-only discovery; confirm counts, sources, coordinate, duration, cache status, accepted/rejected queries, and rejection reasons.
8. Trigger simultaneous Map/Nearby/Geofence refreshes; confirm the displayed discovery session has internally consistent counts.
9. Add/remove or move between store contexts; confirm appeared/disappeared decision events identify the reason.
10. Trigger notification success, no matched products, cooldown suppression, and invalid payload; confirm fired/suppressed reason and recent errors where applicable.
11. Tap a saved and transient notification; confirm tap result, deep-link status, selected store, and bottom-sheet opened state.
12. Compare Geofence region rows with Core Location logs; confirm count, title, coordinate, source, and radius match actual monitored regions.
13. Enter a monitored region on device; confirm entered region, trigger time, current store, and distance update. Confirm exit remains absent when `notifyOnExit` is disabled.
14. Open and move Map; confirm user coordinate, camera, focused/selected store, visible stores/circles, zoom, and region update.
15. Run Gemini success/failure and barcode/OpenFoodFacts/manual flows; confirm counters and durations increment once per local request.
16. Confirm the estimated monthly Gemini count is zero before requests and uses only locally recorded requests afterward.
17. Capture a Beta Snapshot; confirm timestamp, build, device, runtime report, and in-memory screen preview are present.
18. Export Markdown and JSON; verify both are readable and contain all required sections.
19. Test Share, Copy, and Save for both formats.
20. Search exports for image data, email, auth, API keys, secrets, screenshots, and route history; confirm none are present.
