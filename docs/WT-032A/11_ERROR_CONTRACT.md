# User-Facing Account and Sync Error Contract

The implemented `WayTaskAccountSyncError` stores a category and bounded optional
retry delay. UI receives curated copy and diagnostic code only; raw provider,
PostgREST, Postgres, HTTP, JWT, SQLSTATE, or stack messages are internal and
must not be forwarded.

| Category / code | Safe title and explanation | Action / retry | Local work | Log privacy |
|---|---|---|---|---|
| Offline / WTAS-001 | You’re offline — changes are saved on this device and sync resumes online. | continue; when online | yes | public metadata |
| Authentication required / WTAS-002 | Sign in required — cloud backup needs a session; local data remains. | sign in; after reauth | yes | security event, no token |
| Session expired / WTAS-003 | Your session expired — sign in again; local data remains. | sign in; after reauth | yes | security event, no token |
| Permission denied / WTAS-004 | Information unavailable — sign in again or contact support. | reauth; after reauth | yes | security event, no token |
| Invalid input / WTAS-005 | Check this information — review highlighted values. | correct; after user choice | yes | public metadata |
| Rate limited / WTAS-006 | Please wait — too many attempts were made. | honor `Retry-After` | yes | public metadata |
| Conflict / WTAS-007 | Changes need review — versions were preserved. | review; after user choice | yes | private metadata, no content |
| Service unavailable / WTAS-008 | Sync temporarily unavailable — local information is not lost. | retry/backoff | yes | public metadata |
| Partial sync / WTAS-009 | Some changes are pending — completed and local work are preserved. | resume | yes | private metadata, no content |
| Migration interrupted / WTAS-010 | Backup interrupted — it can resume without duplication. | resume | yes | private metadata, no content |
| Local persistence failure / WTAS-011 | Could not save on this device — durability is unconfirmed. | keep app open/contact support; no blind retry | no for affected change | private metadata, no content |
| Cloud persistence failure / WTAS-012 | Could not save to cloud — change remains local and unsynced. | retry later | yes | private metadata, no content |
| Account unavailable / WTAS-013 | Accounts unavailable — Guest Mode still works. | continue Guest | yes | public metadata |
| Unknown recoverable / WTAS-014 | Sync did not finish — local data is safe. | retry/continue offline | yes | public metadata |
| Unknown non-recoverable / WTAS-015 | WayTask needs attention — account operation stopped safely. | contact support with code | where possible, not affected operation | public metadata |

Logs may contain diagnostic code, environment, app/schema version, operation
class, retry count, duration, row counts, and a random correlation ID. Never log
access/refresh tokens, client or server secrets, email, complete private rows,
shopping text, notes, barcodes, coordinates, image bytes/paths, raw requests, or
raw database/provider errors. If a provider error is needed for diagnosis, map
it to an allowlisted internal reason and discard the payload.

Tests enumerate all 15 categories, require complete safe metadata, verify the
approved Offline/Permission/Rate/Server copy, and reject database/JWT vocabulary
from explanations.
