# Account and Sync Threat Model

Residual risk is the risk after listed controls; none is described as solved by
authentication alone.

| # | Asset | Attack/failure | Prevention | Detection | Recovery | Residual risk |
|---:|---|---|---|---|---|---|
| 1 | Private rows | Cross-user reads/writes | owner ID, RLS for every operation, composite owner FKs | RLS attack tests, permission-denied metrics | revoke session, audit, notify/repair if exposure | policy or platform regression |
| 2 | Record privacy | UUID enumeration/direct guessing | random UUID plus owner RLS | repeated forbidden/not-found pattern without logging IDs | rotate token; investigate policy | traffic inference remains |
| 3 | Ownership | Client rewrites `owner_user_id` | WITH CHECK, immutable trigger, composite FKs | failed-policy/security events | reject mutation; preserve local record | trusted server bug |
| 4 | Entire database | RLS missing/disabled | migration enables and FORCEs RLS; explicit policies | test queries `pg_class`; deployment gate | disable writes/API, restore policy migration | manual dashboard drift |
| 5 | Session/data | Stolen or expired token | short-lived access token, Keychain refresh token, expiration state | Auth anomaly/revocation signals | revoke sessions, reauthenticate; local data remains | valid stolen token until revocation/expiry |
| 6 | Project | Privileged secret leakage | secrets outside repo/iOS; CI secret scopes; prefix/JWT startup guard | repository/bundle scans, provider secret alerts | rotate immediately, audit access, redeploy | screenshots/operator handling |
| 7 | Mutation integrity | Replay mutation | owner/device/key scope, unique idempotency key, payload hash | duplicate-key and replay-rate metrics | return original receipt or reject; no duplicate apply | replay before receipt commit |
| 8 | Records | Duplicate network retries | stable local IDs, upserts with expected revision, unique receipt | duplicate receipt counters | reconcile counts and resume | poorly chosen operation key |
| 9 | Availability/cost | Oversized request | 500-row/1 MiB limits, image limits, server body cap | rejected-size metrics | backoff; split approved batches | distributed abuse |
| 10 | Text/UI | Malformed Unicode/control chars | scalar-aware validation and DB CHECKs; preserve legitimate Unicode | validation counters without content | reject field, preserve local draft | later renderer bugs |
| 11 | Database | SQL injection | parameterized Data API/static migrations; no dynamic raw input SQL | code review/SAST, DB error anomaly | block request, patch query, rotate if compromise | dependency defect |
| 12 | UI/users | Stored text rendered as executable HTML/URL | treat as data; context escape; URL allowlist | security UI tests | disable affected renderer, encode output | future web/export clients |
| 13 | Service/cost | Spam/abusive write volume | provisional operation limits, quotas, server path for abuse-sensitive work | per-user/IP/device rates and alerts | throttle/suspend; preserve read/local mode | botnets/shared IPs |
| 14 | Store/community data | Malicious store report | not direct CRUD; authenticated Edge workflow, validation/moderation | abuse queue/reputation | quarantine/rollback report | coordinated abuse |
| 15 | Images/privacy | Unauthorized or dangerous upload | Storage disabled now; future owner path policy, content sniff/scan, size/type limits | object/table mismatch and scan failures | quarantine/delete object; revoke uploader | polyglot/novel malware |
| 16 | Guest dataset | App deleted before first migration completes | preview warning; resumable verified batches; never mark complete early | migration checkpoint/verification status | restore from verified cloud subset or device backup | unsynced local-only data can be lost |
| 17 | First backup | Interrupted partial upload | stable IDs, batch receipts, checkpoints, cloud verification, no local delete | partial-sync status/count mismatch | resume at first unverified batch | server commit/client timeout ambiguity |
| 18 | User data | Two-device conflicting edits | server revisions/base revisions/mutation IDs; deterministic rules | conflict records/metrics | auto-merge or preserved conflict copy/user choice | semantic merge ambiguity |
| 19 | User intent | Accidental mass deletion | tombstones, batch/delete thresholds, write kill switch | deletion-rate alert | pause sync, restore tombstones/backup | delayed detection |
| 20 | Schema/data | Bad migration | Git migration, clean rebuild, staging, backup, expand/migrate/contract | migration smoke/constraint/RLS tests | roll forward or isolated restore | irreversible external side effects |
| 21 | Availability | Cloud outage | local-first writes; circuit breaker/backoff; flags | provider health and sync backlog | continue locally; resume idempotently | prolonged backlog/storage pressure |
| 22 | Authorization | Wrong project/environment config | explicit environment, HTTPS/loopback guard, flags off, separate project linking | startup classification, deploy checklist | fail to Guest Mode; unlink/rotate config | valid but mislabelled remote URL |
| 23 | Tokens/content | Sensitive logging | typed codes/privacy classes; never tokens/full rows/images | log scans and sampling review | purge where possible, rotate token, incident review | third-party SDK behavior |
| 24 | Account lifecycle | Incomplete deletion/retention | reauth, durable deletion job, ordered resources, minimized audit | job state/age and orphan scans | retry/resume, manual authorized repair, report final status | provider/legal retention lag |
| 25 | Gemini key/cost | Extracted client credential used for arbitrary calls, quota/cost exhaustion, or outage | no key/direct endpoint in iOS; authenticated fixed Function; server secret and kill switch | artifact/source scans; provider quota/cost/rejection alerts | disable Function, rotate key, investigate old-key attempts | old builds expose key until rotation; distributed abuse |
| 26 | Recognition image/text | Sensitive background/OCR/barcode sent or logged | explicit Use Photo; JPEG re-render; fixed schema/prompt; QR omitted; no WayTask retention | content-free logs and sampled schema audits | kill switch; purge provider data where contract permits; privacy incident process | provider/network metadata and user-framed content |

## Trust boundaries

- The iOS process is untrusted for ownership claims and administrative actions.
- Supabase Auth proves a session; RLS and constraints authorize each row.
- Service credentials exist only in controlled server/deployment systems.
- Secure AI treats iOS as untrusted: Auth, validation, user/salted-IP quota,
  idempotency, endpoint/model/prompt ownership, and normalization are server-side.
- Apple/Core Location/notification/photo services are separate privacy domains.
- Shared catalog releases are not private-user ownership domains.

Before Production, monitoring must use counts, latency, diagnostic codes,
environment, schema version and pseudonymous request IDs—not tokens, email,
shopping text, coordinates, barcodes, images, or complete records.
