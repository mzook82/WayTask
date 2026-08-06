# Sync and Conflict-Resolution Contract

## Authority and ordering

Device wall-clock time never chooses a winner. Cloud rows use server-managed
monotonic revisions and server `updated_at`; each mutation has an immutable ID,
device ID, base revision, and idempotency key. Local ProductState revisions order
local commands. A future sync sidecar records the last verified cloud base.

No silent data loss: if one semantic value cannot be safely merged, preserve
both versions or create a conflict copy before asking the user.

| Scenario | Deterministic rule |
|---|---|
| Local-only creation | Upsert stable UUID only when absent; collision with different owner/content is a conflict/security error. |
| Cloud-only creation | Materialize locally with cloud revision and a new local command/sidecar revision; never overwrite an unrelated UUID. |
| Changed on one device | Apply if mutation base equals cloud revision; server increments revision. |
| Same record changed on two devices | First valid base commit advances revision; second becomes conflict and is merged or preserved. |
| List renamed on both | No text auto-merge; keep cloud title and a recoverable “conflicting rename” copy/user choice. |
| Quantity changed on both | If both changes are independently expressible deltas from the same base, merge deltas within bounds; otherwise preserve both values for choice. Never use wall time. |
| Needed/resolved changed on both | Resolution is a semantic event. Preserve resolution provenance; reopen versus resolve conflict requires explicit deterministic event ordering and usually user review. |
| Delete versus edit | Tombstone wins for visibility but the edit is preserved as a recoverable conflict payload/copy; never discard it. |
| Delete versus re-create | Same UUID remains tombstoned unless an explicit restore mutation cites the tombstone revision. A new concept uses a new UUID. |
| Product identity differs | Catalog IDs are references, not identity. Do not merge two ProductState UUIDs solely by name/barcode/catalog ID; suggest user review. |
| Ordering conflicts | Use fractional/order tokens plus mutation ID tie-break; periodically normalize in a server-authorized transaction without changing semantic content. |
| Duplicate list entries | Follow existing ProductState list-scoped duplicate policy. Exact same entry UUID is idempotent; distinct entries are not silently collapsed. |
| Offline edits after sign-out | Commit locally to the existing dataset, pause upload, and require the same owner reauth or explicit migration choice. |
| Clock skew | Ignore device timestamps for winner selection; validate only gross future skew and use revisions/server receipt order. |
| Same mutation retried | Return/fetch the original receipt when key and hash match; reject key reuse with a different hash. |
| Parent deleted while child edited | Preserve parent tombstone and child edit as a conflict; do not orphan or cascade silently. |

## Merge outcomes

- **Auto-merge:** disjoint fields with the same base; exact idempotent retry;
  independently proven numeric deltas; deterministic ordering tokens.
- **Choose one revision:** only when one side is unchanged from the common base
  or an explicit later restore cites the prior tombstone revision.
- **Preserve both/conflict copy:** concurrent names/notes/product identity,
  delete-versus-edit, unprovable quantity intent, malformed legacy mapping.
- **User choice:** semantic state changes, list rename, product merge, or any
  conflict where automation could discard intent.

Conflict records are private owner-scoped operational metadata with minimized
field snapshots, expiry/retention, and export/deletion behavior. They are not
added to the WT-032A database because the sync engine is disabled; WT-032B must
approve their exact schema before implementation.
