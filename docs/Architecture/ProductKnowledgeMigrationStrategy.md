# WT-020 Product Knowledge Migration Strategy

**Version:** 1.0  
**Status:** Proposed  
**Scope:** Safe transition from current models to canonical Product Entity  
**Implementation:** Out of scope for WT-020 Phase 1

---

## 1. Migration Objective

Move from overlapping `Product`, `ShoppingItem`, `ProductKnowledge`, `ProductHistory`, and `ProductCandidate` representations to:

- One canonical `ProductEntity`.
- User library state keyed by Product ID.
- Shopping entries keyed by Product ID.
- Usage keyed by Product ID.
- Provider observations and provenance.
- A rebuildable local search index.

The migration must preserve current products, shopping membership, user-visible names, images, barcodes, usage history, and offline behavior.

---

## 2. Strategy Principles

1. **No big-bang replacement.** Introduce the new store and adapters alongside current reads.
2. **Preserve IDs where practical.** Existing `Product.id` should seed the initial Product Entity ID unless a verified merge dictates otherwise.
3. **Prefer false duplicates over false merges.** Ambiguous records remain separate and can be merged later.
4. **Idempotent steps.** Every migration phase can be restarted safely.
5. **Checkpointed transactions.** Record schema, seed, backfill, and index versions independently.
6. **Search is rebuildable.** Never treat the index as migrated source data.
7. **Keep rollback reads.** Do not remove legacy models until multiple releases prove the cutover.
8. **User-confirmed data wins.** Provider or AI fields cannot overwrite user values silently.
9. **Offline migration.** No migration step requires a network connection.

---

## 3. Current-to-Target Mapping

| Current source | Target use |
|---|---|
| `Product` | Primary source for an existing user’s initial Product Entity and UserProduct |
| `ShoppingItem` | Compatibility/enrichment source and temporary legacy-link map |
| `ShoppingListEntry` | Shopping entry retained and relinked to canonical Product ID |
| `ProductKnowledge` | Knowledge contribution, identifier, alias, image, and usage enrichment |
| `ProductHistory` | ProductUsage aggregate |
| `ProductCandidate` | Transient adapter input only; no data migration |
| `Product.sourceRawValue` | Initial origin/provenance contribution |
| Raw category strings | Taxonomy mapping; fallback to Uncategorized |
| Newline keyword strings | Normalized ProductSearchKeyword rows |
| Image `Data` | Local asset plus ProductMedia metadata |

---

## 4. Migration Ledger

Persist a local migration ledger independent of UI state:

| Field | Purpose |
|---|---|
| `migrationID` | Stable migration name |
| `targetSchemaVersion` | Target relational schema |
| `seedRevision` | Imported catalog/taxonomy revision |
| `normalizationVersion` | Search normalization version |
| `phase` | Last completed phase |
| `cursor` | Last processed stable legacy ID if batching |
| `startedAt` / `completedAt` | Diagnostics |
| `sourceCounts` | Pre-migration counts |
| `targetCounts` | Post-phase counts |
| `errorCode` | Privacy-safe failure reason |

Ledger writes occur in the same transaction as the relevant batch/checkpoint.

---

## 5. Phased Migration

### Phase 0 — Characterize and protect

Before schema changes:

- Add unit fixtures that represent current `Product`, `ShoppingItem`, Product Knowledge, history, and shopping-entry combinations.
- Capture privacy-safe aggregate counts and invariants.
- Define database backup/recovery behavior supported by the chosen persistence layer.
- Define a feature flag for new read and write paths.
- Establish performance baselines for current launch and Products tab.
- Freeze normalization version 1 and taxonomy revision 1.

Exit criteria:

- Fixtures cover manual, barcode, AI, duplicate, image, and legacy-link cases.
- Migration can be run against an isolated copy.
- Rollback path is documented and tested.

### Phase 1 — Add target schema and seed

Create target tables without switching product UI:

- Product Entity.
- Names/aliases.
- Taxonomy.
- Keywords.
- Identifiers.
- UserProduct.
- ProductUsage.
- Contributions.
- Media metadata.
- Redirects.
- Search-index metadata.

Import and validate:

- Taxonomy.
- Category aliases.
- Semantic icons.
- Curated seed products.

Validation rejects:

- Duplicate IDs.
- Broken category ancestry.
- Duplicate global external identifiers.
- Redirect cycles.
- Unsupported schema/normalization versions.

Exit criteria:

- Seed import is idempotent.
- Empty-install search index can be built offline.
- Legacy behavior remains unchanged.

### Phase 2 — Backfill existing Products

Process current `Product` rows in stable ID order.

For each row:

1. Reuse `Product.id` as Product Entity ID when no verified seed binding already exists.
2. Create a canonical name and normalized name.
3. Map category text to taxonomy.
4. Use Uncategorized when mapping is not safe.
5. Preserve the raw category as a contribution.
6. Convert barcode to a typed ProductIdentifier when valid.
7. Convert search keywords into rows.
8. Move/reference image bytes through ProductMedia/asset storage.
9. Record origin and source contribution.
10. Create active UserProduct.
11. Store legacy-to-canonical ID mapping.

If a current product strongly matches a seed entity:

- Barcode exact match may bind to the seed Product ID.
- Preserve the old Product UUID in a migration mapping or redirect.
- Preserve the user-visible name as a user override or alias when it differs.

Do not seed-bind on a name-only match.

Exit criteria:

- Every current Product maps to one resolvable Product ID.
- Active UserProduct count matches unique migrated library membership.
- All names and images are accounted for.

### Phase 3 — Enrich from Product Knowledge and ShoppingItem

For each `ProductKnowledge` row:

1. Resolve by exact normalized barcode when available.
2. Otherwise resolve by existing migration link or safe composite match.
3. If unresolved, create a provider/user knowledge entity only when the record is valid.
4. Add alternate preferred/product names as aliases where safe.
5. Add identifiers, keywords, image metadata, and product details as contributions.
6. Preserve AI confidence and recognition source as provenance.

For each `ShoppingItem`:

1. Resolve through `Product.legacyShoppingItemID` or `ShoppingListEntry.legacyShoppingItemID`.
2. Fall back to exact barcode.
3. Use composite matching only under the merge policy.
4. Preserve unmatched valid items as separate Product Entities rather than dropping them.

Authority:

- Existing Product/user-visible values take precedence.
- ProductKnowledge may fill missing fields.
- Lower-authority sources cannot replace stronger values automatically.

Exit criteria:

- Every referenced ShoppingItem resolves to a Product ID or appears in an explicit exception report.
- No unresolved ProductKnowledge row is silently discarded.

### Phase 4 — Migrate usage and shopping references

Product history:

- Resolve `ProductHistory` through barcode, Product/ShoppingItem links, then safe normalized composite.
- Create/merge ProductUsage aggregates.
- Preserve add count and relevant dates.
- Do not sum records that are only weak name matches.

Shopping:

- Add canonical Product ID to each shopping entry if not already present.
- Verify the canonical entity resolves and is active.
- Keep legacy IDs during the compatibility window.
- Preserve quantity, checked state, sort order, and list ID.

Exit criteria:

- Every shopping entry resolves to one canonical Product Entity.
- Entry counts per Shopping list are unchanged.
- Usage aggregate totals are reconciled or explicitly reported.

### Phase 5 — Build and validate search

Rebuild the index entirely from target authoritative rows:

- Names.
- Aliases.
- Keywords.
- Brand.
- Taxonomy text.
- Active status.

Run fixture queries:

- Exact name.
- Prefix.
- Token prefix.
- Alias.
- Partial/trigram.
- Hebrew/Arabic/English normalization.
- Redirected entity.

Run performance datasets at 500 and 50,000 entities.

Exit criteria:

- Search results contain only resolvable Product IDs.
- Ranking fixtures are stable.
- p95 latency meets the approved target on supported hardware.

### Phase 6 — Shadow reads and dual writes

Enable new product writes behind a feature flag:

- New Product Entity/UserProduct write.
- Temporary legacy Product mirror write if rollback requires it.
- Shopping entry continues to retain legacy compatibility fields.

For reads:

- Serve legacy UI initially.
- Run new search/resolution in shadow where safe.
- Compare privacy-safe counts and selected IDs, not raw user text.
- Report mismatches by reason code.

Dual-write rules must be centralized in one migration adapter. Views and provider adapters must not implement their own dual writes.

Exit criteria:

- No unexplained drift over the agreed beta period.
- New writes survive legacy and target read paths.
- Failed target writes do not report success.

### Phase 7 — Switch Product Creation and Library reads

Order:

1. Smart Product Creation suggestions.
2. Known-product selection/save.
3. Unknown-product save.
4. Product Library reads.
5. Product Library edit/remove.
6. Shopping selection.

Keep camera/barcode mapping through adapters into the new Product Draft pipeline.

Rollback:

- Disable new read flag.
- Continue reading legacy mirrors.
- Do not delete target data; it may be repaired and retried.

Exit criteria:

- Product Library and Shopping behavior pass regression tests.
- Existing IDs resolve through mapping/redirects.
- Save/delete semantics are consistent.

### Phase 8 — Switch downstream consumers

Migrate one consumer at a time:

- Shopping planner.
- Store/intent matching.
- Geofencing and locations.
- Shopping sessions.
- Product usage/recommendations.
- Camera local cache.
- Home/recent product views.

Each consumer receives a Product Entity/domain projection rather than database records or copied product strings.

Exit criteria:

- No production consumer requires product attributes from legacy ShoppingItem.
- Compatibility mapping metrics remain zero or understood.

### Phase 9 — Retire compatibility models

Only in a later, separately approved release:

- Stop legacy mirror writes.
- Keep a read-only recovery migration for at least the agreed support window.
- Remove `legacyShoppingItemID` dependencies.
- Remove duplicated product fields from ShoppingItem or replace the compatibility model.
- Remove old ProductKnowledge key-based cache.
- Remove obsolete migration flags after upgrade-floor analysis.

Do not retire legacy tables in the same release that first switches all reads.

---

## 6. Matching and Conflict Policy

### 6.1 Automatic match priority

| Priority | Match | Action |
|---:|---|---|
| 1 | Existing explicit migration link | Reuse |
| 2 | Exact valid global barcode | Reuse unless conflict report proves ambiguity |
| 3 | Exact provider-scoped identifier | Reuse within issuer |
| 4 | Exact normalized name + same normalized brand + compatible taxonomy/locale | Reuse when unique |
| 5 | Exact normalized alias + compatible brand/taxonomy | Reuse when unique |
| 6 | Name-only or partial similarity | Do not auto-merge |

### 6.2 Conflicting barcode

If one barcode maps to multiple current products:

- Choose no automatic winner unless an explicit legacy link proves it.
- Quarantine the identifier conflict.
- Keep both Product Entities.
- Exclude the conflicting identifier from automatic resolution until repaired.

### 6.3 Conflicting names

If the same normalized name represents multiple categories or variants:

- Keep separate Product IDs.
- Rank using category, brand, variant, locale, and usage.
- Require user selection where ambiguity remains.

### 6.4 Category mapping

Mapping order:

1. Exact current-to-taxonomy mapping table.
2. Locale-specific category alias.
3. Deterministic keyword rule with approved confidence.
4. Uncategorized.

The original text remains in a contribution for future remapping.

### 6.5 Field authority

Never replace a stronger existing value only because the new observation is newer.

Suggested default order:

1. Explicit user override/confirmation.
2. Curated seed.
3. Verified external identifier provider.
4. Accepted AI/camera observation.
5. Unconfirmed provider/community data.

---

## 7. Search Index Migration

The index is not migrated row-by-row from current `searchKeywordsRawValue`.

Process:

1. Migrate authoritative normalized rows.
2. Validate normalization version.
3. Drop or clear the target index.
4. Rebuild by Product ID batches.
5. Store build revision and row counts.
6. Run integrity queries.
7. Atomically mark the index active.

If build is interrupted, the repository can:

- Continue serving legacy/manual creation.
- Resume or restart index build.
- Never expose a partially marked-active index.

---

## 8. Image Migration

Image migration should be lazy or batched to avoid launch stalls:

1. Create ProductMedia metadata.
2. Copy bytes into managed asset storage.
3. Verify content hash and decodability.
4. Commit asset reference.
5. Retain legacy bytes during rollback window.
6. Remove duplicate legacy bytes only in the retirement phase.

Remote URLs remain optional and are never required for offline product display because semantic icons provide fallback.

---

## 9. Validation and Reconciliation

Required invariants after each applicable phase:

- Source Product count equals mapped Product count, accounting for explicit merges.
- Every active UserProduct resolves.
- Every ShoppingListEntry resolves.
- Shopping entry counts and ordering are unchanged.
- No image is removed before a verified target asset exists.
- Every barcode conflict appears in a report.
- Redirect graph is acyclic.
- Search result IDs resolve.
- No migration step requires network access.
- Re-running the migration produces no duplicate rows or count drift.

Privacy-safe reconciliation report:

```text
legacyProducts
migratedEntities
seedBindings
userProducts
shoppingEntries
resolvedShoppingEntries
unresolvedRecords
barcodeConflicts
categoryFallbacks
mediaCopied
mediaFailures
indexDocuments
indexBuildDuration
```

Do not log raw product names, barcodes, images, or user text.

---

## 10. Rollback Plan

Rollback is feature-flag and adapter based, not destructive:

- Keep legacy source rows during the compatibility window.
- Keep legacy-readable mirror writes while required.
- Switch reads back to legacy adapters.
- Retain target database for diagnostics and repair.
- Never downgrade the database by deleting target rows on rollback.
- If a target write succeeded but a mirror write failed, record a repair task and do not falsely report complete dual-write health.

Once legacy mirror writes stop, rollback requires an explicitly tested target-to-legacy export or a new forward fix. That is why legacy retirement is a separate release decision.

---

## 11. Release Gates

### Gate A — Schema and seed

- Validation passes.
- Import is idempotent.
- Empty install works offline.

### Gate B — Backfill

- All critical invariants pass.
- Ambiguities are reported, not merged.
- Interrupted migration resumes.

### Gate C — Search

- Functional fixtures pass.
- 500/50,000 performance passes.
- Index rebuild passes.

### Gate D — Product Creation

- Known, unknown, existing-library, and failure paths pass.
- No network dependency.

### Gate E — Consumer cutover

- Shopping/planning/location regressions pass.
- Legacy fallback remains available.

### Gate F — Retirement

- Agreed beta/release observation period completed.
- Compatibility usage is zero.
- Recovery strategy approved.

---

## 12. Explicit Non-Goals

This migration does not require:

- Cloud synchronization.
- Community data import.
- New Gemini behavior.
- Barcode-scanner improvements.
- Machine learning.
- Automatic cross-device entity merging.
- Deleting current compatibility models in Phase 1.

