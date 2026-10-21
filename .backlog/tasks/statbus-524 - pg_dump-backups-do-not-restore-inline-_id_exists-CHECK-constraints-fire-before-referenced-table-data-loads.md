---
id: STATBUS-524
title: >-
  Unit addenda reference their unit through foreign keys, so pg_dump backups
  restore
status: In Progress
assignee: []
created_date: '2026-10-21 13:38'
updated_date: '2026-10-21 14:12'
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

**Decision (owner, 2026-10-21):** replace our hand-written checks with the mechanism sql_saga has proven robust, not a workaround.
- A plain `FOREIGN KEY` cannot point at a temporal parent, because `legal_unit.id` and `establishment.id` are unique only together with the validity period. sql_saga's regular-to-temporal foreign key exists for exactly this, and checks existence fast through its temporal key index.
- **Rule for deletes:** a child that is an addendum to a unit, with no meaning without it, goes with the unit (`ON DELETE CASCADE`). A child that is a thing in its own right would block the delete instead. `external_ident` (the unit's identifiers), `tag_for_unit` (tags on a unit) and `unit_notes` (notes about a unit) are addenda, so all their parent references cascade, as `enterprise_id` on these tables already does.

### Zoom in
The ten references and their replacements, all `ON DELETE CASCADE`:

| Child table | Column | Parent | Replacement |
|---|---|---|---|
| external_ident | legal_unit_id | legal_unit (temporal) | sql_saga regular foreign key |
| external_ident | establishment_id | establishment (temporal) | sql_saga regular foreign key |
| external_ident | person_id | person | plain FOREIGN KEY |
| external_ident | power_group_id | power_group | plain FOREIGN KEY |
| tag_for_unit | legal_unit_id | legal_unit (temporal) | sql_saga regular foreign key |
| tag_for_unit | establishment_id | establishment (temporal) | sql_saga regular foreign key |
| tag_for_unit | power_group_id | power_group | plain FOREIGN KEY |
| unit_notes | legal_unit_id | legal_unit (temporal) | sql_saga regular foreign key |
| unit_notes | establishment_id | establishment (temporal) | sql_saga regular foreign key |
| unit_notes | power_group_id | power_group | plain FOREIGN KEY |

- **sql_saga foreign keys:** `sql_saga.add_foreign_key(fk_table_oid => ..., fk_column_names => ARRAY[...], pk_table_oid => ..., pk_column_names => ARRAY['id'], delete_action => 'CASCADE')`, against the parent's `id` primary unique key (`legal_unit_id_valid`, `establishment_id_valid`). On 1.3 the child side is a constraint trigger, dumped after data.
- **The migration** drops the ten CHECKs and the four `admin.*_id_exists` functions. It adds the replacements and fails clearly if any existing row references a missing parent. It needs sql_saga 1.3, so it lands with STATBUS-519.
- **Parent-side behaviour:** a parent delete cascades to these children. `public.reset` removes units with one TRUNCATE listing parents and children together. Imports reshape timelines through `temporal_merge`, which 1.3 lets through while another row of the unit still holds the key.
- **Found by:** the STATBUS-519 proof, step 7 (`tmp/519-proof-1.3.log`).
- **Tried and not working:** moving the CHECKs to ALTER TABLE ADD CONSTRAINT (pg_dump still inlines them), and a SQL-standard function body (pg_dump does not order table data by that edge).

### Closing review
- **Memory:** none needed.
- **Documentation:** `COMMENT ON` each new foreign key states that it is an addendum reference that cascades with the unit. Regenerate `doc/db/`.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The ten admin.*_id_exists CHECKs and the four helper functions are gone; external_ident, tag_for_unit and unit_notes reference legal_unit and establishment through sql_saga regular foreign keys and person and power_group through plain FOREIGN KEYs, all ON DELETE CASCADE, each with a COMMENT ON naming it an addendum reference
- [ ] #2 Deleting a legal unit, establishment, person or power group deletes its rows in these three tables, and inserting a row that references a missing parent is refused (pg_regress test)
- [ ] #3 A pg_dump -Fc of a database with rows in all three tables restores with pg_restore --single-transaction --exit-on-error, and sql_saga.check_integrity() passes on the restored database (regression test)
- [ ] #4 Fast tests, doc/db regeneration and CI pass, together with STATBUS-519
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Owner decision 2026-10-21
Replace the 2024 hand-written CHECKs with the mechanism sql_saga proved robust (regular-to-temporal foreign keys, constraint triggers in 1.3), not a workaround. external_ident, tag_for_unit and unit_notes are addenda to a unit, so every parent reference cascades on delete. Built by duck as part of STATBUS-519.
<!-- SECTION:NOTES:END -->
