# Account Deletion and Export Design

Neither workflow is enabled in WT-032A.

## Account deletion

1. Require a recent high-assurance reauthentication and show the account plus
   exact consequences. A normal access token alone is insufficient.
2. Offer an explicit choice approved by product/legal: immediate irreversible
   deletion or a documented grace period with cancellation. Do not imply a
   grace period unless the infrastructure enforces it.
3. Create one durable server deletion job keyed by user and idempotency key.
   Block duplicate jobs, record state/counts/codes only, and pause cloud writes.
4. Delete/revoke future Storage objects and provider tokens first where needed,
   then child mutation/device/entry resources, products/lists/stores/preferences,
   profile, and finally Auth identity. Actual order must be FK/Storage tested.
5. Minimize any retained security/audit record to job ID, irreversible user
   digest, timestamps, result code and legal basis. No shopping content, email,
   coordinates, token, or object body.
6. Retry/resume each idempotent phase. Partial failure remains “deletion
   pending,” alerts operators, and never falsely reports completion.
7. Verify zero live/tombstoned private rows, zero user Storage objects and absent
   Auth identity before final success. Account backups expire under documented
   backup retention; communicate that distinction.
8. Legal retention exceptions require named law/policy, data subset, owner,
   duration and access control. Default is no exception.

Local behavior must be an explicit confirmation separate from cloud deletion:
“keep this device’s local data” (default safest for recovery) or “delete local
data too” with a second destructive confirmation. Sign-out never performs either
account or local deletion. If local deletion is chosen, use existing protected
ProductState recovery/backup rules and do not destroy data before cloud job
status is clear.

## User data export

- Authenticated request with recent reauth, per-user/IP rate limit, one active
  idempotent job, expiration and audit-safe status.
- Produce versioned machine-readable UTF-8 JSON (optionally ZIP) with manifest,
  schema/version, generated time, lists, entries, personal products,
  preferences, notification preferences, saved stores and user-owned technical
  IDs/revisions/tombstones. Add history/sessions/images only if they later sync.
- Exclude shared catalog/Product Knowledge content, service diagnostics, server
  secrets, tokens, other users, internal abuse signals and irrelevant provider
  data. Catalog IDs may remain as references.
- Preserve Unicode and RFC 3339 UTC timestamps; document units and enum values.
- Generate in an isolated server job, encrypt at rest, use a short-lived
  authenticated download, bind access to the requesting user, and expire/delete
  the object. Do not attach or email a sensitive export without a separately
  approved encrypted delivery design.
- Export job failure is retryable and does not alter data. Export does not delay
  an already confirmed deletion unless the user explicitly requested export
  first and the product contract says so.
