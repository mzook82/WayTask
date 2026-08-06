# Validation Matrix

Authority legend: **DB** is authoritative for persisted rows; **server** is
authoritative for privileged/complex operations; iOS presentation/domain checks
provide early feedback but never replace DB/server validation.

| Field | Contract | Presentation | Domain | DB | Edge/server |
|---|---|---|---|---|---|
| UUID identities | Native UUID, never name-based | generated/parsed | strongly typed UUID | UUID type, PK/FK | revalidate request IDs |
| owner ID | Never user-selectable | absent from editable UI | derived from verified session | `auth.uid()`, RLS, immutable trigger | derive from JWT, never body |
| list name | trimmed content 1–120; Unicode allowed; no controls/newlines | live count/message | `validateListName` | authoritative CHECK | same contract for batches |
| product display name | trimmed content 1–200; Unicode/emoji/apostrophes allowed | live count/message | `validateProductDisplayName` | authoritative CHECK | same contract for import |
| brand/category | optional, max 160, no control chars | counter if edited | shared text validator | authoritative CHECK | import validation |
| note | optional, max 2,000; tab/newline allowed; other controls denied | counter | `validateNote` | authoritative CHECK | batch validation |
| description/future export labels | optional, max 4,000 | counter | `validateDescription` | add CHECK with field | request validation |
| quantity | finite decimal 0.001–999,999.999, three stored decimals | numeric control | `validateQuantity` | `numeric(12,3)` CHECK | batch validation |
| unit | null or count/kg/g/l/ml/package | picker | enum | allowlist CHECK | batch validation |
| locale | he, he-IL, en, en-US, ar, ar-IL | picker/system match | `validateLocale` | allowlist CHECK | same allowlist |
| timezone | UTC or bounded IANA-shaped identifier | system picker | Foundation availability check | max 64 and syntax CHECK | validate against server tz database |
| timestamps | UTC/RFC 3339 on wire; not >5 min future from iOS; server time orders sync | none | `validateTimestamp` | `timestamptz`, consistency CHECKs, server `updated_at` | server receipt time authoritative |
| lifecycle/status | documented finite allowlist | picker/action | enum | CHECK | explicit decoder |
| web URL | HTTP(S), max 2,048, host required, no embedded credentials | URL feedback | `validateWebURL` | authoritative scheme/shape CHECK | reparse and deny redirects for fetches |
| barcode | optional 6–32 ASCII digits | scan/manual feedback | `validateBarcode` | regex CHECK | import validation |
| catalog ID | 1–128 safe identifier characters | not free-form | catalog adapter | regex CHECK | catalog lookup |
| saved coordinates | latitude ±90, longitude ±180; explicit save/consent | map confirmation | Core Location validity | numeric bounds | do not accept implicit history |
| store radius | cloud 50–5,000; notification default 100–1,000 | bounded slider | numeric bounds | CHECK | report workflow validation |
| image metadata | JPEG/PNG/HEIC/WebP; 1–10 MiB; 1–12,000 px; owner-prefixed path | preflight | `validateImageMetadata` | CHECK | mandatory content sniff/scan before future upload |
| idempotency key | 16–128 safe chars; unique per owner/device/operation | hidden | generated mutation UUID/key | unique constraint | required for privileged/batch calls |
| mutation hash | lower-case SHA-256 | hidden | computed over canonical bytes | 64-hex CHECK | recompute before applying |
| batch count | 1–500 | progress/preflight | `validateBatch` | receipt CHECK | reject before parsing/applying |
| payload size | 1–1,048,576 bytes for custom operations | preflight | `validateBatch` | receipt CHECK | request body limit is authoritative |
| secure-AI image | JPEG only; re-rendered metadata-free; local input ≤12 MiB; upload ≤2 MiB and longest side ≤1,280 px | explicit review/consent and preflight | fixed encoder | never stored | body ≤2,850,000; JPEG signature/MIME/decoded size checked |
| secure-AI request | schema v1; UUID; only image and optional numeric allowlisted barcode; no QR/model/prompt/endpoint/user/location | hidden generated UUID | fixed Codable type | quota ledger stores identifiers/hash/time only | reject unknown/malformed fields; derive user from JWT |
| secure-AI response | ≤64 KiB client/provider; normalized body ≤32 KiB; bounded fields; one candidate or no-match | reviewed, never auto-added | strict decoder and safe message codes | no response persistence by proxy | fixed model/prompt; validate and normalize provider JSON |

The presentation layer must show typed field errors and must submit the original
Unicode value as data. It may trim surrounding whitespace only as an explicit
user-visible normalization. It must not delete Hebrew, apostrophes, emoji, or
punctuation.

Queries use parameterized SDK requests or static SQL. Raw user text is never
concatenated into SQL, shell, HTML, or code. Stored content must be escaped for
the later rendering context. Raw Postgres/PostgREST/JWT/HTTP/Supabase errors are
mapped to `WayTaskAccountSyncError` and are not user-facing or persisted as UI
copy.

The database constraint suite contains 30 executed assertions, including
malformed Unicode controls, bounds, enum values, URLs, barcodes, image metadata,
location, quiet hours, batch count, and payload size.

The secure-AI Function contract suite additionally covers valid requests,
unknown client controls, malformed/oversized payloads, JPEG signature/MIME, and
bounded response normalization. Its PostgreSQL quota suite executes eight
authorization, duplicate, user-limit, IP-limit, and no-content-storage
assertions.
