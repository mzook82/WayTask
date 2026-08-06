# Direct Data API Versus Edge Functions

Decision rule: use direct Data API only when one authenticated user's simple
CRUD can be completely protected by row policy, foreign keys, constraints, and
ordinary transactions. Use a trusted server path when secrets, cross-user
authority, moderation, rate limiting, multi-step destructive work, or elevated
access are required.

| Operation | Path | Reason/control |
|---|---|---|
| Read/update own profile | Data API/RLS | simple owner row; hard delete excluded |
| Read/update own preferences | Data API/RLS | simple owner row and CHECKs |
| CRUD via tombstones for own lists/products/entries/stores | Data API/RLS | owner-only rows; composite child ownership; expected revision required in application query |
| Register/revoke own installation | Data API/RLS initially | no raw push token; owner-only; rate monitor |
| Read own mutation receipts | Data API/RLS | immutable metadata only |
| Submit small ordinary owner mutation | Data API/RLS only if one-row constraints suffice | stable ID and unique key; no privileged apply status |
| Initial guest migration batch | Edge Function/trusted migration service | resumable multi-table verification, limits, canonical hash, idempotent receipt, server timestamps |
| Large sync batch | Edge Function | body/rate limits, atomic subset, validation report, receipt orchestration |
| Administrative catalog write/release | trusted admin pipeline | shared data, signing/review, no user owner rule |
| Shared/family/collaboration workflow | Edge Function | cross-user grants cannot rely on one owner check; out of scope |
| Store report/submission | Edge Function | abuse throttling, moderation, provenance |
| Hidden-secret operation | Edge Function | iOS must never possess secret |
| Push-provider registration using provider secret | Edge Function | validates token and owns provider credential |
| Image upload authorization/finalization | signed upload plus Edge Function | owner path, quota, content verification/scan |
| Account export | Edge Function/job | snapshot consistency, secure delivery, rate limit |
| Account deletion | Edge Function/job | reauth, DB/Storage/Auth ordering, retry and final status |
| Backup/restore/migration administration | controlled operator path | elevated database access and approvals |

No Edge Function is added in WT-032A because every enabled runtime cloud
operation is disabled. WT-032B must not create a ceremonial pass-through
function; its first justified function is the authenticated initial-migration
batch endpoint, with strict schema validation, idempotency, rate limits, and
local/staging tests before any production deployment.
