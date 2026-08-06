# WT-032A — Supabase Account, Security & Sync Foundation

Status: local/staging foundation only. Cloud accounts, first migration, and
synchronization remain OFF. No production project is linked and no local user
data is uploaded.

Documents:

1. [Account architecture](01_ACCOUNT_ARCHITECTURE.md)
2. [Cloud data inventory](02_CLOUD_DATA_INVENTORY.md)
3. [Database schema](03_DATABASE_SCHEMA.md)
4. [RLS policy matrix](04_RLS_POLICY_MATRIX.md)
5. [Validation matrix](05_VALIDATION_MATRIX.md)
6. [Threat model](06_THREAT_MODEL.md)
7. [Data API versus Edge Functions](07_DATA_API_VS_EDGE_FUNCTIONS.md)
8. [Rate limits and idempotency](08_RATE_LIMITS_AND_IDEMPOTENCY.md)
9. [Guest migration](09_GUEST_MIGRATION.md)
10. [Sync and conflict resolution](10_SYNC_AND_CONFLICT_RESOLUTION.md)
11. [User-facing error contract](11_ERROR_CONTRACT.md)
12. [Privacy and data minimization](12_PRIVACY_AND_DATA_MINIMIZATION.md)
13. [Backup, restore, and rollback](13_BACKUP_RESTORE_ROLLBACK.md)
14. [Environments and secrets](14_ENVIRONMENTS_AND_SECRETS.md)
15. [Account deletion and export](15_ACCOUNT_DELETION_AND_EXPORT.md)
16. [WT-032B prerequisites](16_WT032B_PREREQUISITES.md)
17. [Gemini credential remediation](17_GEMINI_CREDENTIAL_REMEDIATION.md)

Executable evidence lives under `supabase/tests/` and iOS contract tests live
under `WayTaskTests/AccountSync/` and `WayTaskTests/AIRecognition/`.
