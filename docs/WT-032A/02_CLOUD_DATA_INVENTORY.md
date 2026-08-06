# Cloud Data Inventory

Classification: **1** private sync candidate; **2** device-local; **3** shared
read-only; **4** derived/cache; **5** sensitive/high-risk; **6** first-release
out of scope. A row may have more than one classification.

| Existing type/field | Active ownership and persistence | Class | First cloud action |
|---|---|---:|---|
| V4 shopping list UUID/title/purpose/revision/timestamps | ProductState V4 SwiftData | 1 | `shopping_lists`; preserve UUID, normalize logical delete to tombstone. |
| V4 entry UUID, list/product UUID, quantity/unit/note/order | ProductState V4 SwiftData | 1 | `shopping_list_entries`; validate quantities and parent/product ownership. |
| Needed/resolved state, reason, effective time, command/session provenance | ProductState V4 SwiftData | 1 | Sync; map camel-case local values to documented cloud enums. |
| V4 personal product identity/name/brand/category/barcode/source/catalog link | ProductState V4 SwiftData | 1 | `personal_products`; catalog link is a reference, not a copied catalog row. |
| Manual/custom products | V4 product source `manual` | 1 | Include after migration preview. |
| Scanned/barcode products | V4 product source `barcode` | 1,5 | Include barcode only after format validation; no scan frame. |
| Camera/AI reviewed products | V4 sources `camera`/`ai`; command requires reviewed input | 1,5 | Include reviewed product record; exclude transient recognition payload. |
| Catalog/discover products | V4 source plus catalog snapshot | 1,3 | Sync personal link and compatibility snapshot only. |
| Imported source | Not an active V4 source today | 6 | Schema reserves `imported`; do not fabricate during migration. |
| Product inline `imageData` | V4 SwiftData | 5,6 | Do not upload in first sync. Future explicit image consent/storage migration. |
| Product `imageURLString` | V4 SwiftData, may be remote metadata | 5,6 | Preview and validate HTTP(S); no automatic remote fetch or copy. |
| Catalog display snapshots/icon key | V4 compatibility fields | 1,4 | Sync only the minimum snapshot required to survive catalog release changes; rebuild current display from catalog. |
| Product library removed state/time | V4 ProductState | 1 | Sync as lifecycle/tombstone metadata; never hard-delete on first upload. |
| V4 saved/custom `GeoLocation` records | SwiftData model remains in V4 schema; active production runtime currently does not consume them | 1,5,6 | `saved_stores` schema exists; first migration requires explicit location consent and runtime re-authorization. |
| Current map selected store/list/camera/visible region | In-memory `@Published`/`@State` | 2 | Never sync. |
| Current/coarse user location and location updates | Core Location transient | 2,5 | Never sync; do not create location history. |
| Map store search results, coverage, decisions, recommendations | Transient provider/projections | 4 | Rebuild; never sync. |
| Shopping plan/status/input fingerprint | ProductState projections, not durable cloud authority | 4,6 | Recompute from authoritative list/product data. |
| V4 shopping session and lines | ProductState V4 SwiftData | 1,5,6 | Preserve locally; defer first cloud release pending retention and conflict design. |
| Session stop store/name/coordinate snapshots | ProductState V4 SwiftData | 5,6 | Preserve locally; do not sync in first release. |
| V4 immutable product history events | ProductState V4 SwiftData | 1,5,6 | Preserve locally; defer until history retention/export policy is approved. |
| Legacy `ProductHistory` aggregates | Compatibility model | 4,6 | Rebuild from immutable events; never synchronize alongside events. |
| `ProductStateMigrationException` digests | Local recovery ledger | 2,5 | Never sync; counts may be privacy-safe operational telemetry only with approval. |
| Bundled product catalog/taxonomy/releases | Signed app resources/shared JSON | 3 | Keep shared and read-only. `catalog_releases` is metadata only. |
| Bundled Product Knowledge/localizations/search index | In-memory repository built from bundle | 3,4 | Do not copy per user; rebuild index. |
| Legacy learned `ProductKnowledge` rows/thumbnails/confidence/usage | Compatibility SwiftData model, not production search authority | 4,5,6 | Do not sync in first release; review whether any user-confirmed knowledge should become personal product data. |
| Notification desired preference | No active durable production preference model | 1 | Future `notification_preferences`; default opt-out. |
| OS notification authorization and delivered/pending requests | iOS | 2,5 | Never sync. |
| Geofence registrations, opaque reminder tokens, cooldown timestamps | iOS/UserDefaults/derived ProductState plans | 2,4,5 | Rebuild locally; never sync. |
| Onboarding/feature-tour completion | UserDefaults | 2 | Keep device-local in first release. |
| Legacy shopping prompt selections/review completion | UserDefaults | 2,6 | Keep local; obsolete after active UI cutover. |
| Beta diagnostics/developer/debug seed settings | UserDefaults | 2,4 | Never sync. |
| Sentry diagnostics | External operational service | 5,6 | No private records/tokens; separate consent and retention contract. |
| Supabase session tokens | Future Keychain/Auth SDK | 2,5 | Never ProductState/cloud-row sync and never logs. |
| Device installation UUID/app version/locale/hash-only push token | Future local identity plus cloud row | 1,5 | `device_installations`; minimize, per-user, revocable. |
| Sync mutation IDs/idempotency/hash/count/status | Future sync engine/cloud | 1,4,5 | Receipt metadata only; never raw payload or token. |
| User locale/measurement/currency/time zone/location opt-in | Existing values are mostly absent or OS-derived | 1 | `user_preferences`; explicit defaults and consent. |
| Precise saved-store coordinates | User-created `GeoLocation` | 1,5,6 | Private owner row; opt-in preview required before first upload. |

## Compatibility and identity conclusions

- Product/list/entry/session/history UUIDs are stable and safe to reuse after
  validation. They make first upload idempotent.
- V4 list, product, and session UInt64 revisions are local concurrency tokens;
  future cloud revisions are server-managed signed bigint values. An adapter,
  not a destructive local migration, maps them.
- Product removal and V4 logical list deletion already avoid destructive
  deletion. Cloud rows add explicit `deleted_at` tombstones.
- Entries have timestamps but no independent local revision. WT-032B must add a
  sidecar sync manifest or safe local schema version; it must not overload list
  revision as an entry cloud revision.
- There are no current cloud IDs, owner IDs, sync timestamps, or durable
  idempotency receipts in ProductState. WT-032A intentionally does not mutate
  the V4 production graph to add them.
