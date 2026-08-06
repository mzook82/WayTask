# Account Architecture

## Current production authority audit

`WayTaskApp` starts `WayTaskProductStateRuntimeBootstrap`, which either opens or
non-destructively creates/promotes the separate ProductState V4 store at
`WayTaskProductStateRuntime/product-state-v4.store`. The app renders
`WayTaskProductionRuntimeView`. The shipped V3 store and
`WayTaskModelContainer.currentSchema` remain compatibility/migration inputs;
they are not the active runtime write authority after cutover.

The active ProductState V4 write graph is:

- `WayTaskSchemaV4.Product`: personal product library, UUID, UInt64 revision,
  active/removed lifecycle, optional removal timestamp, names/classification,
  source, catalog link/snapshot, optional inline image data or URL, created and
  updated timestamps.
- `WayTaskSchemaV4.ShoppingList`: named list UUID, UInt64 revision, title,
  purpose, created/updated timestamps, cascade-owned entries. Logical deletion
  writes purpose `deleted`; it does not hard-delete the row.
- `WayTaskSchemaV4.ShoppingListEntry`: stable entry/list/product UUIDs,
  needed/resolved lifecycle, reason/effective time/provenance and command or
  session IDs, Double quantity, unit, note, sort order, timestamps.
- `WayTaskSchemaV4.ShoppingSession`, `ShoppingSessionLine`, and
  `ShoppingSessionStop`: revisioned durable execution plus immutable product,
  quantity, note and store snapshots.
- `WayTaskSchemaV4.ProductHistoryEvent`: immutable UUID-keyed history with
  meaning, provenance, source list/entry/session/command IDs, and occurrence
  time.
- `ProductStateMigrationException`: privacy-safe digests used for local
  compatibility recovery, not user content.

The runtime repository and transaction coordinators are the only active
ProductState writers. Queries return projections; presentation state is not
authority. Commands carry UUID mutation IDs and expected revisions, but there
is no durable cloud sync ledger yet.

Application lifecycle findings:

- ProductState bootstrap fails closed if protected cutover evidence is invalid.
- Guest use has no network/account prerequisite.
- `selectedListID`, map store selection, camera region, store search results,
  plan projections, notification plans and monitoring plans are in-memory.
- The production map uses current coarse location and transient store results;
  its ProductState path currently passes empty saved-location evidence.
- `SettingsView`, `GeoLocation`, legacy `ShoppingItem`, learned
  `ProductKnowledge`, and old preference UI remain in the source/schema for
  compatibility, but the active production tab set has no Settings tab.
- Bundled Product Knowledge/catalog JSON is loaded into an immutable in-memory
  repository and is the production search/catalog authority.
- OS notification authorization, pending/delivered requests, region monitoring,
  current location, Photos picker items, and camera frames are owned by iOS or
  transient services.
- Onboarding, feature-tour completion, beta diagnostics, debug seed controls,
  notification cooldowns, and old shopping prompts are in `UserDefaults`.

## Separation of concerns

| Concern | Authority | Rule |
|---|---|---|
| Authentication | Future Supabase Auth adapter | Establishes a verified `UserIdentity`; never establishes ownership by itself. |
| Authorization | Database constraints and RLS | Derives owner scope from `auth.uid()`; never trusts UI filters or a submitted owner alone. |
| Synchronization | Future `CloudSyncProviding` implementation | Moves versioned mutations; never makes local data contingent on cloud availability. |
| Local data | ProductState/SwiftData | Remains usable in Guest Mode, on sign-out, on expiration, and during outages. |

Implemented types are `UserIdentity`, `AccountAuthenticationState`,
`AccountAuthorizationState`, `LocalDataOwnershipState`, `SyncLifecycleState`,
`AccountSessionSnapshot`, `AccountSessionProviding`,
`AccountSessionAuthorizing`, `CloudSyncProviding`, and `SyncConfiguration`.

## Supported state contract

| Product state | Authentication | Authorization | Synchronization | Local access |
|---|---|---|---|---|
| Guest/local only | Guest | Device only | Local only | Full |
| Signed in/local not backed up | Verified identity | Owner-scoped cloud plus local | Not backed up | Full |
| Initial migration pending | Verified identity | Owner scoped | Preview/commit pending | Full |
| Sync active | Verified identity | Owner scoped | Active | Full |
| Paused/offline | Verified identity | Owner scoped when token valid | Paused | Full |
| Session expired | Last known identity only | Device only | Authentication required | Full |
| Recoverable error | Verified identity where available | No expansion | Retryable error | Full unless local persistence failed |
| Deletion pending | Reauthenticated identity | Restricted owner scope | Orchestration pending | Explicit policy; never implicit deletion |

`LocalAccountSessionAuthority.acceptVerifiedSession` accepts only an identity
already verified by a future auth adapter. It does not perform or fake login.
It marks guest data as migration-pending; it never silently links or uploads it.
Session expiration and sign-out preserve the local dataset identity. A dataset
already linked or pending migration for one owner is never retargeted when a
different user signs in: the authority enters a recoverable permission error
and retains the original ownership binding.

## Startup invariant

`WayTaskAccountSyncFoundation.startup()` resolves the environment, forces flags
off if configuration is absent or invalid, creates the Guest account authority,
and installs `DisabledCloudSyncProvider`. The disabled provider records zero
network requests and fails with the typed account-unavailable error. WT-032A
adds no account UI and no Supabase client dependency.
