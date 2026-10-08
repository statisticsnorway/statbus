---
id: STATBUS-473
title: >-
  Activity category upserts never update an existing row: custom re-upload
  silently ignored, standard reload wipes the standard
status: In Progress
assignee: []
created_date: '2026-10-08 13:43'
updated_date: '2026-10-08 13:54'
labels:
  - sql
  - import
dependencies: []
priority: high
ordinal: 399204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NORTH STAR: uploading an activity category file twice, with corrected labels, updates the labels; reloading a standard keeps every code it still contains.

FOUND while doing STATBUS-472 (inventory of the upsert trigger functions behind the activity_category_* views), observed on statbus_seed at 20261008132050, all in rolled-back transactions.

1. admin.activity_category_enabled_custom_upsert_custom (the custom CSV upload target, activity_category_enabled_custom) and admin.upsert_activity_category (behind activity_category_isic_v4 / activity_category_nace_v2_1) end in ON CONFLICT ... DO UPDATE ... WHERE activity_category.id = EXCLUDED.id. id is GENERATED ALWAYS AS IDENTITY, so EXCLUDED.id is the freshly drawn id and never equals the existing row's id: the DO UPDATE never fires (INSERT 0 0). Observed: uploading path Q9 'first' then Q9 'second (corrected)' leaves name 'first'. An operator who re-uploads a custom file with corrected labels (exactly the STATBUS-472 situation: the field file was hand-trimmed to fit 256 and will be re-uploaded untrimmed) sees success and no change. The clause has been there since 3564061ee (2024-11-12).

2. Consequence for standards: admin.delete_stale_activity_category (AFTER INSERT FOR EACH STATEMENT) deletes every row of the standard whose updated_at < statement_timestamp(). Because the upsert never touches existing rows, a reload of a standard deletes every pre-existing code. Observed: INSERT INTO activity_category_nace_v2_1 VALUES ('A',...),('A.99','New division') took nace_v2.1 from 1047 rows to 1. activity.category_id references activity_category ON DELETE CASCADE, so on a box with data this would cascade-delete activities. Reachable only by a migration or seed that reloads a standard (users have SELECT only on those views), so no live path today, but the next standard refresh would hit it.

3. admin.activity_category_enabled_upsert_custom (INSTEAD OF INSERT on activity_category_enabled) reads SELECT standard_id FROM public.settings, a column that does not exist (it is activity_category_standard_id), and ends in ON CONFLICT (standard_id, path), which matches no unique constraint (the key is (standard_id, path, enabled)). Every insert through that view errors. Nothing in app/, cli/ or test/ inserts through it; either fix it or drop the trigger so the view is honestly read-only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Re-uploading a custom activity category with a changed name updates the stored name, and the upload reports it.
- [ ] #2 Reloading a standard through activity_category_isic_v4 / activity_category_nace_v2_1 keeps every code present in the reload and updates its name; only codes absent from the reload are removed.
- [ ] #3 Inserting through activity_category_enabled either works against the real settings column and constraint, or the view no longer accepts inserts.
- [ ] #4 pg_regress test covers re-upload, standard reload, and the activity_category_enabled insert path, including a box with activities referencing the categories.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
COORDINATOR TRIAGE DECISION (2026-10-08), so the fix does not have to be rediscovered. The three findings share one shape and are fixed in one migration plus one pg_regress test.

1. ON CONFLICT ... DO UPDATE ... WHERE activity_category.id = EXCLUDED.id can never fire, because activity_category.id is GENERATED ALWAYS AS IDENTITY, so EXCLUDED.id is the freshly drawn identity and never equals the stored row's id. The row is therefore always inserted and never updated (INSERT 0 0 on the update path). Fix: drop the bogus WHERE predicate and conflict on the real key of the target view (standard_id, path), which is what the custom upload target actually keys on; keep the update restricted to the columns the upload addresses (name, at least), and make the custom path report how many rows it updated so a silent no-op cannot recur.

2. admin.delete_stale_activity_category deletes every row of the standard whose updated_at is older than statement_timestamp(), which after fix 1 becomes genuinely destructive: a reload that does not touch existing codes would delete all of them, and activity.category_id references activity_category ON DELETE CASCADE. Fix: delete only rows of that standard that the current statement did NOT address, i.e. compute the stale set as the complement of the codes present in the statement, never by wall-clock comparison alone.

3. admin.activity_category_enabled_upsert_custom (INSTEAD OF INSERT on activity_category_enabled) reads settings.standard_id, which does not exist (the column is activity_category_standard_id), and conflicts on (standard_id, path), which matches no unique constraint (it is (standard_id, path, enabled)). Fix it against the real column and the real constraint (AC3 allows dropping the trigger instead, but a view that silently refuses inserts is a trap; fix it). While in the file, inventory every trigger function behind the activity_category_* views for the same id-in-the-WHERE pattern and fix any other instance in the same migration.

Test (AC4): pg_regress 133 covering a custom re-upload with a changed label, a standard reload that keeps the codes it still contains and removes only the absent ones, and an insert through activity_category_enabled, all against a database that has activities referencing the categories.
<!-- SECTION:NOTES:END -->
