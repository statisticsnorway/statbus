---
id: febdra
title: "A regular user cannot edit part of a period on a row another user wrote"
state: todo
type: bug
priority: ""
assignee: []
labels: ["db", "edit", "security"]
created: 2026-11-17
updated: 2026-11-17
---

## Goal
A regular user changes or removes part of a unit record's period (an activity, statistic, contact or location) that another user wrote, and the save succeeds; the rows the change does not cover keep their own writer.

## Purpose
Found 2026-11-17 while extending test 405 for hmgadt (Rabbit). Every partial edit or removal through a for_portion_of view splits rows; temporal_merge updates the kept piece with its original edit_by_user_id, and the *_regular_user_manage policies (WITH CHECK edit_by_user_id = auth.uid()) refuse it: 'new row violates row-level security policy for table "activity"'. So a regular user can only edit periods of rows they wrote themselves, or whole rows. Admins are not affected.

## Principle
The row's edit_by_user_id records who wrote that row's values; a kept piece's values were written by its original writer, so it keeps that name. Permission to edit a unit's data does not depend on who wrote it last.

## Relevant details
Reproduction (tmp/611-rls-probe4..6.sql, logs; clone of statbus_test_template; journal 2026-11-17 19:21): as test.regular, UPDATE activity__for_portion_of_valid SET category_id = X, edit_by_user_id = auth.uid(), edit_at = now(), valid_from = '2025-01-01', valid_until = '2026-01-01' (or 'infinity') on an admin-written row from 2024: RLS error. The same for SET id = NULL (removal), stat_for_unit and contact. Changing the whole row passes. location passes only through restricted_user's policy for region_id IS NULL (regular_user is a member of restricted_user). On the dev DB the same with rabbit-review (id 4). Locally 1 of 4 users is a regular_user; production share unknown. Fix options for the owner: (a) regular_user policies WITH CHECK true for the temporal tables, with the writer of new values set by the app/import (as today); (b) keep the check and let temporal_merge run kept-piece updates under a definer role; (c) other.

## Depends on

## Acceptance
- [ ] A pg_regress test, RED before the fix: as a regular user, change and remove 2025 of an activity, a statistic, a contact and a location (with a region) that the admin wrote from 2024; each succeeds, the changed or removed period is as asked, and the kept pieces still name the admin
- [ ] [Owner] Chooses the fix, recorded in this task's notes
- [ ] The edit form, as a regular user, saves a 2025-only change on a record another user wrote (headless, database restored after)

## Notes
