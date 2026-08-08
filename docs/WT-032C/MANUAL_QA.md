# WT-032C Synthetic Staging Migration QA

This checklist is not authorized for execution by the foundation sprint. It
starts only after explicit approval to deploy the new migration and create/write
disposable Staging fixtures. Never use the developer's existing ProductState,
Production, a service key in iOS, real photos, addresses, location/history, or
private profile content.

## Prerequisites

- [ ] Real signed-session User A/User B isolation is recorded PASSED. This is a
  hard activation requirement, not replaceable by database-role tests.
- [ ] WayTask Staging is the linked project; Production is not linked or
  targeted.
- [ ] Migration `20260809000100` is reviewed and pushed through `supabase db
  push`; dry-run then reports up to date.
- [ ] The `initial-migration` Edge Function is reviewed/deployed with JWT
  verification ON.
- [ ] Only disposable synthetic Staging identities/data are approved.
- [ ] A/B, session recovery, schema, endpoint, and blockers-clear approvals are
  recorded in both client configuration and the private Staging control row.
- [ ] The private database deployment approval is set only after confirming the
  linked project is WayTask Staging; schema deployment alone leaves it false.
- [ ] Migration is enabled only in a dedicated ignored synthetic-QA Staging
  configuration. Sync and Secure AI remain OFF. Production remains OFF.

## Fixture matrix

- [ ] Empty dataset.
- [ ] One list / one item.
- [ ] Multiple lists, personal products, quantities, needed/resolved states.
- [ ] Hebrew, Arabic, accented Latin, CJK, emoji, and localized English names.
- [ ] Large but bounded multi-batch dataset.
- [ ] Synthetic image/location/history/recognition data that must be absent
  from Preview payload and remote tables.

## Flow

- [ ] Sign-in alone produces no attempt, receipt, or private data row.
- [ ] Preview counts and exclusions match the synthetic local fixture.
- [ ] Cancel Preview/consent before preparation: zero remote calls and no
  binding.
- [ ] Cancel after preparation but before remote begin: consent is revoked,
  zero remote rows exist, and the immutable account binding remains.
- [ ] Change local data after Preview: consent invalidates and regenerates.
- [ ] Confirm explicitly: binding persists to the currently authenticated UUID.
- [ ] Kill the app before begin, between every dependency kind, after an
  accepted/lost response, and during verify. Each relaunch resumes only missing
  batches without duplicates.
- [ ] Go offline and expire/refresh the session mid-flow. The app pauses safely,
  retains ProductState, and resumes only for the same UUID without retry storm.
- [ ] Verify exact remote counts/IDs/ownership/parents/receipts and forbidden
  field absence before local completion.
- [ ] Confirm local ProductState remains fully readable after completion and
  Sync remains OFF.

## Conflicts and adversarial cases

- [ ] A prepares, signs out, B signs in: B receives account conflict and makes
  no migration call.
- [ ] B submits A attempt/batch/receipt/exact UUID: denied.
- [ ] Owner/target fields, unsupported version, malformed/oversized manifest,
  changed batch content, duplicate sequence, and child-before-parent: denied.
- [ ] Pre-existing unrelated A remote rows: conflict, no overwrite.
- [ ] Same manifest from another attempt/device: conflict unless the exact
  approved recovery rule applies.
- [ ] Direct attempt/receipt mutation and direct completion claim: denied.

## Rollback and cleanup

- [ ] Cancel before remote begin leaves no remote data and retains A binding.
- [ ] Exact partial attempt rolls back child-first through the authenticated
  RPC and cannot delete unrelated rows.
- [ ] Verified completion cannot use client rollback.
- [ ] Cleanup of completed synthetic fixtures uses a separately approved,
  trusted Staging administrative boundary. Do not add a client delete policy.
- [ ] Restore all migration activation inputs and server switches to OFF after
  QA; verify Sync/Secure AI/Production remained OFF throughout.

Record only sanitized fixture labels, counts, attempt/batch opaque IDs, typed
status categories, and pass/fail. Do not record tokens, email, names, payloads,
coordinates, provider errors, or credentials.
