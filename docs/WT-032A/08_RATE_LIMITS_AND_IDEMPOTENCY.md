# Rate Limits and Idempotency

Numbers below are provisional development/staging starting points, not asserted
Production truth. Before Production, observe legitimate beta behavior, choose
provider-tier capacity, test accessibility/retry flows, and approve final values.
All `429` responses include integer `Retry-After` seconds and a safe typed
`rateLimited` error; clients use jittered exponential backoff and do not spin.

| Class | Key | Burst | Sustained | Enforcement | Response and user copy | Alert threshold |
|---|---|---:|---:|---|---|---|
| Authentication | normalized account target + IP/device | provider default; dev target 10/10 min | provider default | Supabase Auth plus future gateway | `429`; “Too many attempts…wait…” | >2% limited or distributed target attack |
| Profile updates | user ID | 10/min | 60/hour | future Edge/gateway; DB revision prevents stale writes | retry after delay; local draft retained | >30/hour/user population outliers |
| List creation | user ID + device | 10/min | 100/day provisional | Edge/gateway or quota trigger before Production | preserve local list pending sync | >50/day/user review |
| List-entry writes | user + device | 120/min | 2,000/day provisional | gateway/Edge for batches; direct writes observed | queue locally, coalesce safe updates | >1% throttled or >1,000/hour |
| Personal-product creation | user + device | 20/min | 300/day | gateway/Edge for imports | preserve local product | >100/day/user review |
| Large sync batches | user + device + operation | 4 concurrent, 10/min | 2,000 records/hour initially | Edge Function mandatory | return receipt/partial progress and `Retry-After` | backlog age >30 min or high rejection |
| Image uploads | user + IP + device | 5/min | provisional 100 MiB/day | future Storage quota + Edge finalization | keep local image; explain upload pending | malware/type failures or 80% quota |
| Store reports | user + IP + device | 3/10 min | 10/day | Edge/moderation mandatory | queue or reject; no direct catalog write | 5/day/user or coordinated target |
| Notification registration | user + installation | 10/min | 30/day | Edge/provider integration | keep local notifications; retry later | token churn >10/day |
| Export/deletion/security operations | user + recent reauth + IP | 2/hour | 5/day export; deletion one active job | Edge/job mandatory | explicit status; never duplicate job | any repeated deletion request or job >SLO |
| Secure AI recognition (implemented staging start) | authenticated user + salted IP hash + request UUID | 6/user/min; 30/IP/min | 60/user/day; 300/IP/day | transactional quota RPC before Gemini; Function/client kill switches | `429` + bounded `Retry-After`; retry or manual entry | provider cost/latency, >2% limited, repeated old-key use |

## Idempotency contract

- Client generates a stable mutation UUID and 16–128 character idempotency key
  before its first attempt. Retries reuse both.
- Scope is `(owner_user_id, device_installation_id, idempotency_key)`; a DB unique
  constraint rejects duplicates. Existing ProductState UUIDs become cloud PKs.
- The request includes a SHA-256 of canonical payload bytes. Reusing a key with
  a different hash is a security/conflict error, never “last write wins.”
- `sync_mutations` contains hashes, counts and status—not raw payloads.
- Direct duplicate insert returns conflict; client fetches its owner-scoped
  receipt. A future Edge endpoint returns the original response for an exact
  key/hash retry.
- Multi-table batches are divided into deterministic chunks of at most 500
  records and 1 MiB; each chunk has its own derived key and ordered manifest.
- Applied status is server-owned. The authorization suite proves an iOS client
  cannot forge it and a duplicate retry leaves exactly one receipt.
- Safe coalescing is limited to superseded unsent updates for the same record;
  deletes, history events, conflict copies, and user choices are never dropped.

Secure AI uses a narrower idempotency contract because recognition is not a
state mutation: `(auth.uid(), request_id)` is unique, a duplicate is rejected,
and the two-day quota ledger contains only the user UUID, request UUID, salted
IP hash, and timestamp. It stores no image, barcode, prompt, or response. The
limits are staging values and require cost/abuse tuning before Production. The
IP component is enabled only with an explicitly configured allowlisted ingress
header, and staging must prove the gateway overwrites it rather than trusting a
client-supplied value.
