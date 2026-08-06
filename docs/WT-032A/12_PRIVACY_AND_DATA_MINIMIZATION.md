# Privacy and Data-Minimization Plan

| Data | Purpose | Storage | Retention assumption | Logs | Sync/delete/export | Required? |
|---|---|---|---|---|---|---|
| Auth user UUID | stable owner/authorization | Supabase Auth and owner columns | account life plus approved deletion completion | pseudonymous ID only if needed | not user-editable; deletion orchestrated; export may include ID | account only |
| Email/provider subject | account recovery/auth | Auth provider; do not duplicate in profile | provider/account policy | never raw | provider export/deletion | provider-dependent |
| Display name | optional account label | private profile | until changed/deleted | never | sync/delete/export | optional |
| Lists/entries/quantities/notes/state | backup/sync core | ProductState and private DB | while user retains plus tombstone window | never content | sync/delete/export | core only if user enables backup |
| Personal products/brand/category/barcode/catalog link | product library backup | ProductState and private DB | account/data retention | never content/barcode | sync/delete/export | product-dependent |
| Saved store/name/address/coordinates/notes | user store features | local; future private DB after explicit preview | until user removes/account deletes; tombstone window | never coordinate/content | opt-in sync/delete/export | optional/high-risk |
| Desired notification preferences | consistent user choice | local/future private DB | until change/delete | allowlisted booleans only if needed | sync/delete/export | optional/default off |
| OS notification permission/requests | device delivery | iOS | OS lifecycle | status category only | never cloud sync/export | device feature only |
| Current location | map/nearby operation | memory/Core Location | session/transient | never precise | never sync/export as history | optional and foreground feature-specific |
| Product/session history | user history | local V4 | local policy pending | never content | first sync deferred; future export/delete review | optional/deferred |
| Product images | product presentation | local SwiftData/Photos as chosen | user-controlled | never | cloud upload deferred and explicit | optional |
| Installation UUID/app version/locale | sync routing/compatibility | device and private DB | revoke plus bounded cleanup | pseudonymous metadata | sync/delete/export as technical metadata | account sync only |
| Push token | future push routing | Keychain/provider; cloud stores hash in current schema only | installation life | never | future deletion; raw value excluded from export | notification feature only |
| Mutation IDs/hash/count/status | idempotency/recovery | local sidecar/private DB | bounded operational window, proposed 90 days after convergence | counts/codes only | delete with account; export optional technical manifest | sync only |
| Diagnostics | reliability/security | Sentry/operational systems | separate approved short retention | allowlisted only | not private-content export; deletion per provider/legal contract | optional/operational |

Never collect continuous location history, full travel routes, raw tokens in
logs, extra email copies, camera frames/images unless explicitly saved, shopping
content in analytics, or precise location outside the requested feature. The
catalog remains shared/bundled and is excluded from user export.

Saved stores and notification preferences are private owner-owned resources.
Location-based smart shopping needs a separate opt-in, just-in-time explanation,
permission review, retention review, background behavior review, and App Store
privacy-label review before it can sync or notify intelligently.

Tombstones are necessary for convergence but must not become indefinite shadow
copies. Production approval must choose a recovery window and server compaction
job, document backup interaction, and preserve active deletion/export jobs.
