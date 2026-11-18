---
id: febdra
title: "A regular user cannot edit part of a period on a row another user wrote"
state: "doing"
type: bug
priority: ""
assignee: ["rabbit"]
labels: ["db", "edit", "security"]
created: 2026-11-17
updated: 2026-11-17
doing_since: "2026-11-18T01:04"
stage: "active"
model: "claude-opus-5-5"
branch: "statbus-628-all-forms"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
A regular user changes or removes part of a unit record's period (an activity, statistic, contact or location) that another user wrote, and the save succeeds; the rows the change does not cover keep their own writer.

## Purpose
A regular user maintaining the register must be able to correct part of any unit's history, not only the rows they wrote themselves. Found 2026-11-17 while extending test 405 for hmgadt (Rabbit); the owner says the row-level security as it stands does not express the security model he intended.

## Principle
The row's edit_by_user_id records who wrote that row's values; a kept piece's values were written by its original writer, so it keeps that name. Permission to edit a unit's data does not depend on who wrote it last.

## Relevant details
Mechanism: every partial edit or removal through a for_portion_of view splits rows; temporal_merge updates the kept piece with its original edit_by_user_id, and the *_regular_user_manage policies (USING true, WITH CHECK edit_by_user_id = auth.uid()) refuse it: 'new row violates row-level security policy for table "activity"'. So a regular user can only edit periods of rows they wrote themselves, or whole rows. Admins are not affected. sql_saga inserts, updates and deletes rows itself during a merge, and passes edit_by_user_id/edit_at as ephemeral columns.

Reproduction (tmp/611-rls-probe4..6.sql, logs; clone of statbus_test_template; journal 2026-11-17 19:21): as test.regular, UPDATE activity__for_portion_of_valid SET category_id = X, edit_by_user_id = auth.uid(), edit_at = now(), valid_from = '2025-01-01', valid_until = '2026-01-01' (or 'infinity') on an admin-written row from 2024: RLS error. The same for SET id = NULL (removal), stat_for_unit and contact. Changing the whole row passes. location passes only through restricted_user's policy for region_id IS NULL (regular_user is a member of restricted_user). On the dev DB the same with rabbit-review (id 4). Locally 1 of 4 users is a regular_user; production share unknown. Fix ideas so far, none agreed: (a) regular_user policies WITH CHECK true for the temporal tables, with the writer of new values set by the app/import (as today) or by a trigger; (b) keep the check and let temporal_merge run kept-piece updates under a definer role; (c) other, from the owner's intended security model.

## Acceptance
- [ ] A pg_regress test, RED before the fix: as a regular user, change and remove 2025 of an activity, a statistic, a contact and a location (with a region) that the admin wrote from 2024; each succeeds, the changed or removed period is as asked, and the kept pieces still name the admin
- [ ] [Owner] States the intended security model for regular users and chooses the fix, recorded in this task's notes: (a) changes the regular_user policies, (b) changes how temporal_merge writes kept pieces, other is defined there; the test above then encodes it
- [ ] The edit form, as a regular user, saves a 2025-only change on a record another user wrote (headless, database restored after)

## Notes

2026-11-17 23:42 discussion with the owner, paused until tomorrow (Rabbit). Owner: (1) a regular user editing only rows they wrote makes no sense to him; the RLS as it stands does not express the security model he intended, so the model itself is to be discussed before any fix. (2) sql_saga inserts, updates and deletes rows itself during a merge (splits, kept pieces), and edit_by_user_id/edit_at are passed to temporal_merge as ephemeral columns, so any trigger or policy that stamps or checks the writer must be designed with that machinery in mind. Rabbit's proposal (WITH CHECK true plus a trigger stamping writer and time only when data columns change) is NOT agreed; parked. Related: notes (n9nyvd) use edit_at as the version for the save race; a database stamp of edit_at on unit_notes waits for this discussion. Nothing built yet.

2026-11-18 00:00 owner discussion (Rabbit). Origin: migration 20260312114525_edit_by_user_id_default_and_rls (2026-03-12/13, 'Migration F') changed every regular_user_manage policy from WITH CHECK (true) to WITH CHECK (edit_by_user_id = auth.uid()) on the 15 editable tables; the owner now thinks that migration may have been an overreach. Released since March; this branch only made partial-period writes common (Live-only edits, Remove), so regular users now meet it on ordinary edits. Semantics agreed in talk: edit_by_user_id/edit_at/edit_comment are last-writer provenance of a row's values, not locking; all 9 temporal eras already list them as sql_saga ephemeral columns (excluded from change comparison, still written). Design idea, owner's words: sql_saga is told a column's purpose (this column is the writer, this one the time) and the function that fills it (e.g. auth.uid(), statement_timestamp()), then stamps rows whose data changed and leaves trimmed pieces as they were. Not decided: (1) forward migration restoring WITH CHECK (true) for regular_user on those tables now; (2) the sql_saga stamping feature later.

2026-11-18 00:04 owner decision (Rabbit): the simple fix. A forward migration puts the regular_user_manage policies back to WITH CHECK (true) on the tables Migration F (20260312114525) changed, and admin.add_rls_regular_user_can_edit creates them that way for new tables. Access stays decided by login and role/grants; edit_by_user_id is last-writer provenance set by the app, imports and DEFAULT auth.uid(). Anti-forgery is only 'cannot sign as another user'; making it forgery-proof needs sql_saga to stamp writer/time itself (owner asks the sql_saga agent to research, e.g. writes under a definer role the stamping trigger recognises).


## History
- 2026-11-18T01:04 todo -> doing/active (take)
