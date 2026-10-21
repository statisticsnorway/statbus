---
id: STATBUS-524
title: >-
  Unit addenda reference their unit through foreign keys, so pg_dump backups
  restore
status: In Progress
assignee: []
created_date: '2026-10-21 13:38'
updated_date: '2026-10-21 23:36'
labels:
  - bug
  - db
dependencies:
  - STATBUS-519
priority: high
type: bug
ordinal: 450204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A `pg_dump -Fc` backup of a StatBus database with data restores cleanly with `pg_restore --single-transaction`, and a unit's addenda can never point at a missing unit.

### Zoom out
**What breaks:** `external_ident`, `tag_for_unit` and `unit_notes` check their parent references with ten hand-written `CHECK` constraints, written in 2024 before sql_saga existed. They call `admin.legal_unit_id_exists`, `admin.establishment_id_exists`, `admin.person_id_exists` and `admin.power_group_id_exists`, which read the parent table. PostgreSQL treats a CHECK as row-local, so pg_dump has no edge to order by: it emits the CHECKs inside CREATE TABLE and loads `external_ident` before `legal_unit`. The restore fails with `violates check constraint external_ident_legal_unit_id_check`. So `./sb db dump` backups of a database with units do not restore. The upgrade snapshot is a file copy and is not affected.

**Not a sql_saga defect:** a minimal repro with two plain tables and no sql_saga fails the same way. sql_saga up to 1.2 had the same pattern for its own regular foreign keys and fixed it in 1.3 by making the child side a deferrable constraint trigger, which pg_dump emits after all data.

**Decision (owner, 2026-10-21, option B):** replace our hand-written checks with the mechanism sql_saga has proven robust, not a workaround.
- A plain `FOREIGN KEY` cannot point at a temporal parent, because `legal_unit.id` and `establishment.id` are unique only together with the validity period. sql_saga's regular-to-temporal foreign key exists for exactly this, and checks existence fast through its temporal key index.
- **Rule for deletes:** `external_ident` (the unit's identifiers), `tag_for_unit` (tags on a unit) and `unit_notes` (notes about a unit) are addenda, so a person or power group delete cascades (`ON DELETE CASCADE`), as `enterprise_id` on these tables already does. sql_saga 1.3 supports only NO ACTION/RESTRICT for its foreign keys, so the legal_unit/establishment references use NO ACTION: deleting a legal unit or establishment that still has addenda is refused. Cascade for the temporal ones is requested upstream (sql_saga todo.md) and is NOT in this release.

### Zoom in
The ten references and their replacements:

| Child table | Column | Parent | Replacement | Delete rule |
|---|---|---|---|---|
| external_ident | legal_unit_id | legal_unit (temporal) | sql_saga regular foreign key | NO ACTION (refused) |
| external_ident | establishment_id | establishment (temporal) | sql_saga regular foreign key | NO ACTION (refused) |
| external_ident | person_id | person | plain FOREIGN KEY | CASCADE |
| external_ident | power_group_id | power_group | plain FOREIGN KEY | CASCADE |
| tag_for_unit | legal_unit_id | legal_unit (temporal) | sql_saga regular foreign key | NO ACTION (refused) |
| tag_for_unit | establishment_id | establishment (temporal) | sql_saga regular foreign key | NO ACTION (refused) |
| tag_for_unit | power_group_id | power_group | plain FOREIGN KEY | CASCADE |
| unit_notes | legal_unit_id | legal_unit (temporal) | sql_saga regular foreign key | NO ACTION (refused) |
| unit_notes | establishment_id | establishment (temporal) | sql_saga regular foreign key | NO ACTION (refused) |
| unit_notes | power_group_id | power_group | plain FOREIGN KEY | CASCADE |

- **sql_saga foreign keys:** `sql_saga.add_foreign_key(fk_table_oid => ..., fk_column_names => ARRAY[...], pk_table_oid => ..., pk_column_names => ARRAY['id'])`, against the parent's `id` primary unique key (`legal_unit_id_valid`, `establishment_id_valid`). On 1.3 the child side is a constraint trigger, dumped after data. 1.3's catalog forbids CASCADE/SET NULL/SET DEFAULT here, hence NO ACTION.
- **The migration** drops the ten CHECKs and the four `admin.*_id_exists` functions. It adds the replacements and fails clearly if any existing row references a missing parent. It needs sql_saga 1.3, so it lands with STATBUS-519.
- **Parent-side behaviour:** a person/power_group delete cascades to these children; a legal_unit/establishment delete with addenda is refused. `public.reset` removes units with one TRUNCATE listing parents and children together. Imports reshape timelines through `temporal_merge`, which 1.3 lets through while another row of the unit still holds the key.
- **Found by:** the STATBUS-519 proof, step 7 (`tmp/519-proof-1.3.log`).
- **Tried and not working:** moving the CHECKs to ALTER TABLE ADD CONSTRAINT (pg_dump still inlines them), and a SQL-standard function body (pg_dump does not order table data by that edge).

### Closing review
- **Memory:** none needed.
- **Documentation:** `COMMENT ON` each new foreign key states that it is an addendum reference. Regenerate `doc/db/`.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The ten admin.*_id_exists CHECKs and the four helper functions are gone; external_ident, tag_for_unit and unit_notes reference legal_unit and establishment through sql_saga regular foreign keys (NO ACTION: sql_saga 1.3 supports no cascading delete action) and person and power_group through plain FOREIGN KEYs ON DELETE CASCADE, each with a COMMENT ON naming it an addendum reference
- [x] #2 Deleting a person or power group cascades to its addenda; deleting a legal unit or establishment that still has addenda is refused with an error naming the foreign key; an insert referencing a missing parent is refused (pg_regress test 143)
- [x] #3 A pg_dump -Fc of a database with rows in all three tables restores with pg_restore --single-transaction --exit-on-error, and sql_saga.check_integrity() passes on the restored database (pg_regress test 143)
- [x] #4 Fast tests, doc/db regeneration and CI pass, together with STATBUS-519
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Owner decision 2026-10-21
Replace the 2024 hand-written CHECKs with the mechanism sql_saga proved robust (regular-to-temporal foreign keys, constraint triggers in 1.3), not a workaround. external_ident, tag_for_unit and unit_notes are addenda to a unit, so every parent reference cascades on delete. Built by duck as part of STATBUS-519.

### Implementation 2026-10-21 (duck)
Migration 20261021143000_addendum_foreign_keys.up/down.sql: drops the 10 CHECKs + 4 admin.*_id_exists helpers; adds 6 sql_saga regular FKs (legal_unit/establishment) with NO ACTION and 4 native FKs (person, power_group x3) ON DELETE CASCADE; COMMENT ON each.
DEVIATION from the ticket table: sql_saga 1.3 forbids CASCADE/SET NULL/SET DEFAULT on its foreign keys (catalog CHECK foreign_keys_delete_action_check; verified live). legal_unit/establishment therefore NO ACTION; cascade for those is with the owner (duck DM to rabbit 2026-10-21, options: A hybrid cascade trigger, B NO ACTION only, C upstream sql_saga feature ask).
Red before fix (test_524_red = template + down migration): 142 fails (person/power_group delete leaves 2 idents, 1 tag, 1 note; different error text); 143 fails (RESTORE_FAILED on pg_restore --single-transaction --exit-on-error) — tmp/524-red-142.out, tmp/524-red-143.out.
Green after fix: 142 asserts 4 refused orphan inserts naming their FK, refused unit deletes with addenda, person/power_group cascade to 0. 143: DUMP_OK, RESTORE_OK, INTEGRITY_OK, restored counts 4/3/3.

### Verification 2026-10-21 (frog)
- Tests redone per owner decision: test 142 (sql + expected) deleted; test 143 trimmed to ONE addendum row per table (external_ident on the legal unit, tag_for_unit on the establishment, unit_notes on the power group) and now asserts, in the original database after the restore block: (1) an insert referencing a missing legal unit is refused with ERROR naming external_ident_legal_unit_id_fkey; (2) deleting the legal unit while its addendum exists is refused naming the FK; (3) deleting the power group cascades its unit_notes row (count before 1, after 0).
- Red (clone of test template + down of 20261021143000, i.e. parent state with the old CHECKs): tmp/524-red-143-final.out — RESTORE_FAILED and INTEGRITY_FAILED on pg_restore --single-transaction, the legal unit delete succeeds silently (no refusal), and the power group delete leaves the note (notes_after = 1).
- Green (fresh clone at HEAD): tmp/524-green-143-final.out — DUMP_OK, RESTORE_OK, INTEGRITY_OK, restored counts 1/1/1, both refusals naming the FK, notes 1 -> 0. Note: in the direct-psql capture the LU-delete ERROR appears after a later \echo marker (stdout/stderr buffering artifact of docker exec); the pg_regress-recorded expected file is correctly ordered.
- Expected output for 143 re-recorded from the runner's results after reading them; `./dev.sh test-isolated 143` passes.
- `./dev.sh test fast`: all 117 shared tests + isolated 094 and 143 pass (tmp/test-fast-519-524.log).

### CI evidence 2026-10-21 (frog)
- Landed as a4fa1e04f (+ 59b2bbefe for the STATBUS-526 seed-build gate the 1.3 bump required).
- CI on 59b2bbefe: Fast Tests success (includes test 143 against the 1.3 image), Images success, Go Test success, app build & lint success.
- doc/db regenerated with only the four admin_*_id_exists docs deleted; re-run after landing reproduced the identical tree.
- Red/green: tmp/524-red-143-final.out (parent state: RESTORE_FAILED, legal unit delete silently allowed, power group delete orphans its note) vs tmp/524-green-143-final.out (DUMP_OK, RESTORE_OK, INTEGRITY_OK, counts 1/1/1, both refusals naming the FK, cascade 1 -> 0).
<!-- SECTION:NOTES:END -->
