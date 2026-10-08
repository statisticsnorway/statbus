---
id: STATBUS-478
title: >-
  status_custom and status_system views omit NOT NULL columns, so every insert
  through them errors
status: Done
assignee: []
created_date: '2026-10-08 16:43'
updated_date: '2026-10-08 17:56'
labels:
  - sql
dependencies: []
priority: medium
ordinal: 404204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: an operator can upload custom statuses (and a migration can reload system statuses) through the status_custom / status_system views.

FOUND during STATBUS-477 (observed on statbus_seed at master, rolled-back transaction, 2026-10-08). public.status has assigned_by_default and used_for_counting NOT NULL with no default, but the views status_custom and status_system expose only (code, name, priority), and admin.upsert_status_custom / admin.upsert_status_system insert only (code, name, enabled, custom, updated_at). Observed: INSERT INTO public.status_custom(code, name, priority) VALUES ('q77', 'first', 99) and INSERT INTO public.status_system(code, name, priority) VALUES ('active', 'Active (renamed)', 1) both fail with: null value in column "assigned_by_default" of relation "status" violates not-null constraint. priority is accepted by the view and silently dropped by the upsert. Unlike the silent no-op of STATBUS-477, this path is broken loudly. Nothing in app/, samples/ or test/ writes through these views today.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Inserting through status_custom and status_system stores code, name, priority, assigned_by_default and used_for_counting, or the views are made honestly read-only
- [x] #2 pg_regress test covers an insert and a corrected re-upload through each view
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Fast Tests with pg_regress actually run, green on a commit containing c4203d184; blocked by STATBUS-481
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
LANDED as c4203d184 (migration 20261008175137_statbus_478_generated_views_carry_required_columns, test 140). The views now WORK rather than being made read-only (rabbit agreed: the columns can be carried).

DERIVED EXPOSURE RULE (re-runnable, not a list): admin.batch_api_required_columns(table_properties) returns the columns an insert through a generated system/custom view must supply and that the generated upsert does not manage itself: attnotnull AND NOT atthasdef AND attidentity = '' AND attgenerated = '', minus id, code, path, parent_id, name, description, priority, enabled, custom, created_at, updated_at (name, description and priority are handled by their own table properties). To re-check every generated table:
  SELECT t, admin.batch_api_required_columns(admin.detect_batch_api_table_properties(format('public.%I', t)::regclass)) FROM unnest(ARRAY['legal_form','data_source','foreign_participation','unit_size','status','legal_rel_type','legal_reorg_type','person_role','power_group_type','region_version','sector','tag']) AS t;
Result on master: status -> {assigned_by_default, used_for_counting}; the other 11 -> {}. So only status's two views change. Verified before writing with an equivalent pg_attribute query (data_source, foreign_participation, legal_form, person_role, power_group_type and unit_size accept name; legal_rel_type, legal_reorg_type, region_version, sector and tag accept name and description; unchanged).
admin.generate_view exposes them; admin.generate_code_upsert_function and admin.generate_path_upsert_function write priority (has_priority) and them on insert and update. status_custom/status_system are regenerated through the generator, along with their upserts and triggers.

ACL INVARIANT (rabbit's conditions, as corrected): the batch-API views are NOT sql_saga views and do not mirror their table's ACL. All generated batch views share one explicit ACL {postgres=arwdDxtm, authenticated=ar, regular_user=ar, admin_user=ar}, granted by admin.grant_permissions_on_views; the INSTEAD OF upserts run as invoker, so table privileges and RLS still decide writes. The migration snapshots relacl of all 48 generated batch views (12 tables x ordered/enabled/system/custom) BEFORE the recreate, re-grants the two recreated views with the same explicit GRANT SELECT/INSERT (no inheritance-aware has_table_privilege propagation), and asserts AFTER, as exact entries: no view's ACL changed or went missing (including the two recreated ones) and all 48 share one ACL. Observed NOTICE: '48 batch views unchanged, all with ACL {...}'. Proof the check fires: a probe copy of the migration that adds GRANT UPDATE ON sector_custom before the recreate aborts with 'STATBUS-478: batch view ACL changed or view missing: sector_custom'.
NO INTERACTION WITH STATBUS-481: 478 touches no sql_saga for_portion_of_valid view and no table ACL; the two repairs are independent.

Test 140, on my own clones of statbus_seed:
- statbus_478_prefix (pre-fix), RED: INSERT INTO status_custom(code, name, priority, assigned_by_default, used_for_counting) fails with 'column assigned_by_default of relation status_custom does not exist'. (With only the old columns it fails on the NOT NULL constraint, as observed when this ticket was filed.)
- statbus_478_fixed, GREEN: upload, correct, re-upload (INSERT and COPY) stores all five fields on the same row (same_row_as_first_upload = t, final priority 30, used_for_counting f); the status_system reload of 'passive' corrects all its fields in place; a second enabled default is refused with 'status code "q141" cannot be stored: another entry already has a value that must be unique (Key (assigned_by_default)=(t) already exists.)' plus a HINT (477's second-key handler); the generator proof: fresh table probe_478_code with required column weight gets code, name, weight in both views, and upload/re-upload writes it.
- pg_regress on master + 478: 140, 138, 137, 136, 134, 108, 015, 306 ok. Down/up round trip clean.
Expected-output changes: only the new test 140 (its one deliberate ERROR is justified in the commit message).
doc/db: once, 1 added (admin_batch_api_required_columns, created by this migration), 0 deleted, 7 modified (3 generators, 2 upserts, 2 views). database.types.ts: +12 lines (the two columns on status_custom/status_system Row/Insert/Update); the types stamp is withheld while migrations/ was dirty, as expected.
CLOSES 477's recorded AC#2 exception: status_custom now has its upload/correct/re-upload test (140.1).
CI: none claimed while STATBUS-481 blocks Images.
<!-- SECTION:NOTES:END -->
