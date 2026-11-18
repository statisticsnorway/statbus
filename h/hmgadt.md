---
id: "hmgadt"
title: Records added to a unit can be removed from the edit form
state: "doing"
assignee: ["rabbit"]
updated_date: '2026-11-13T12:12:00Z'
labels:
  - ui
  - edit
  - temporal
group: ""
rank: "00000000058c"
dependencies: []
priority: high
type: "feature"
origin: "backlog:STATBUS-611"
aliases: ["STATBUS-611"]
backlog_type: "feature"
created: "2026-11-10T21:29:00Z"
updated: "2026-11-13T12:12:00Z"
model: "claude-opus-5-5"
branch: "statbus-628-all-forms"
worktree: "/Users/jhf/ssb/statbus_test"
stage: "waiting"
waiting_on: "owner: check 4 on Norway rc.02 (remove a test record through the form)"
waiting_since: "2026-11-18T12:28"
waiting_asked_by: "rabbit"
---

## Goal
Anything a user can add to a unit in the edit form, the user can also remove there, for a chosen period or entirely.

## Purpose
On Norway the owner added a test location to 0404 GRUE TRAVKLUBB and the form offered no way to remove it (2026-11-10); every record the forms can add had the same gap, and the edit forms only update or insert.

## Principle
A removal is an edit like any other: it goes through the for_portion_of view, carries only identity and period, and the rows it cuts keep their own writer and time.

## Acceptance
- [x] #1 [Owner] Decides how removal works in the UI (remove for a period versus entirely, where the action sits, what history shows) after a walk-through. The answer is recorded in this ticket's notes and becomes the build plan.
- [x] #2 A location, contact, activity and statistic can each be removed for a chosen period through the API; a test removes a middle portion and asserts the split rows and that other units are unchanged
- [x] #3 The edit form offers the agreed remove action for each kind of record it can add; a headless test removes a location, a contact, an activity and a statistic through the form and asserts each one's stored rows (the period gone, the rest kept, other units unchanged) and that the removal carries no comment or other values
- [ ] #4 [Owner] On Norway, after the release carrying this, removes a test record he adds for the purpose (e.g. a physical location on 0404 GRUE TRAVKLUBB, 933130436) through the form; the earlier test location 2312602 was deleted by hand on 2026-11-10. The answer is recorded in this ticket's notes: yes closes the ticket; no gives the error to investigate.
- [x] #5 [Owner] Decides whether a removal records who and when; answer recorded in this ticket's notes (2026-11-17 19:09: no, tracking changes is its own task k5q120; Zoom in and #3 amended)

## North Star
Anything a user can add to a unit in the edit form, the user can also remove there, for a chosen period or entirely, and the removal is recorded like any other edit.

## Zoom out
Owner testing on Norway (v2026.11.4-rc.01, 2026-11-10 21:29): after adding a test physical location (region 03, country AX, from 2026-11-07; location 2312602) to establishment 0404 GRUE TRAVKLUBB (org no. 933130436), the form offers no way to remove it. The same holds for every record the forms can add to a unit: postal and physical locations, contact details, secondary activities, statistics, tags and other linked rows.
- The edit forms only update or insert (upsertTemporalRecord); nothing deletes.
- The for-portion-of views do not support DELETE (sql_saga: standard SQL cannot pass the [from, until) portion to a DELETE trigger). sql_saga.temporal_merge offers mode 'DELETE_FOR_PORTION_OF' (a mode, not a delete_mode), which removes a time portion and splits a row when the portion is in the middle.
- Removing a record for a period differs from ending a unit (closing it with a death date, STATBUS-600): the unit stays, only the linked record goes for that period.

## Zoom in (settled with the owner 2026-11-12/13 and 2026-11-16, see notes)
- What the user does: Change | Remove on the Time frame panel's heading, in the Frame view (the chosen frame or specific dates) and the Timeline view (ticked pieces per frame, Tick all); the parts removed shown struck through; the red Remove takes Save's place and asks first, naming the past frames it reaches.
- What is recorded: a removal carries only identity and period (no data source, comment or remover); the rows it cuts keep their own writer and time; removed history stays visible in the unit's history. Who removed what and when is not recorded: owner 2026-11-17 19:09, tracking changes is its own task (k5q120), since it touches every import and edit path.
- How the database does it: the for_portion_of view, UPDATE x__for_portion_of_valid SET id = NULL, valid_from = START, valid_until = STOP WHERE id = N (sql_saga 1.5, on master), which removes [START, STOP) and splits rows at the edges. Any record the forms can add may be removed, the primary activity included (owner 2026-11-16).
- Then: the owner removes a record on Norway through the form after the release carrying this (check #4).

## Implementation Notes

Owner 2026-11-10 21:30: other single-value fields already turn Save into a delete when the value is erased (external identifiers: update-external-ident-server-action.ts deletes the row when the ident is emptied, refusing the last one; the image: clearing it clears image_id and deletes the image). A form with several fields (a location: address parts, post code, region, country, coordinates) needs an explicit UI interaction for removal, not erase-to-delete. The test physical location 2312602 on Norway was removed by hand (SQL, exactly one row, 21:30) at the owner's request; the postal address 1889376 remains.

2026-11-12 15:38 database findings (Rabbit, rolled back, tmp/611-delete-portion-probe.log, tmp/611-delete-probe.log): (1) DELETE through location__for_portion_of_valid is refused: 'The for_portion_of view only supports UPDATE operations' (sql_saga.for_portion_of_trigger). (2) DELETE_FOR_PORTION_OF is a temporal_merge MODE (sql_saga.temporal_merge_mode), not a delete_mode; the delete_mode enum is NONE / DELETE_MISSING_TIMELINE / DELETE_MISSING_ENTITIES / DELETE_MISSING_TIMELINE_AND_ENTITIES. (3) CALL sql_saga.temporal_merge(target_table=>'public.location', source_table=>src(row_id,id,valid_from,valid_until), primary_identity_columns=>ARRAY['id'], mode=>'DELETE_FOR_PORTION_OF') with 2024-01-01..2025-01-01 removed exactly 2024 from unit 28's physical location (9 rows -> 8, 2023 and 2025.. kept), 35 ms. So a removal function per table (or one generic) can call temporal_merge with that mode. (4) What may be removed follows the constraints: contact needs at least one value (CHECK), so emptying all its fields = removing it; activity.category_id and location.country_id are NOT NULL, so clearing them = removing the record.

2026-11-12 21:25 owner design: Remove goes through the for_portion_of view as UPDATE x__for_portion_of_valid SET id = NULL, valid_from = START, valid_until = STOP WHERE id = N (PostgREST PATCH body {"id": null, "valid_from", "valid_until"}): removes the record over [START, STOP), splitting rows at the edges (temporal_merge DELETE_FOR_PORTION_OF). Rejected: a view-only marker column (must be real columns); all values NULL (a legitimate update, and contact's CHECK refuses it). Specified for the sql_saga agent in ../sql_saga/todo.md ('Next - for_portion_of view: remove a portion with SET id = NULL'), with 8 tests. Today on 1.4 SET id = NULL reports UPDATE 1 and changes nothing (tmp/611-null-id-probe2.log). StatBus pins the new sql_saga, then builds the Remove button on it; the prototype function public.remove_for_portion_of (local dev DB only) is dropped then.

2026-11-12 22:10 UI prototype for the owner's morning review (branch statbus-628-all-forms, NOT pushed: cf4aa4967 emptied contact refused pointing to Remove; 5334201cd Remove beside Save). Remove names the panel's stretch, always asks (dialog: Removed / Kept / past frames), calls one server action removeTemporalRecord. Backend tonight: local-only public.remove_for_portion_of (tmp/611-remove-prototype.sql); swaps to the for_portion_of view's SET id = NULL protocol when sql_saga ships it. Evidence: jest removal RED/GREEN tmp/611-removal-{red,green}.log, contact tmp/611-contact-empty-{red,green}.log, jest 348 / tsc 0 / lint 0; real app tmp/611-remove-check.log (LU 29 postal 2025 removed, 2024 and 2026- kept, restored after) and tmp/611-remove-check2.log (Timeline ticks, nothing-to-remove disabled, establishment). Review note tmp/611-remove-prototype.md. Open: Remove on statistical variables (owner thinking).

2026-11-13 Remove design settled with the owner and sql_saga 1.5 adopted (Rabbit).
- Owner design 10:55-11:32: Change | Remove on the Time frame panel's heading, working in both views. Simple/Advanced replaced by Frame | Timeline (the Frame menu ends with Specific dates). Frame view: Remove takes out the chosen frame (its own period) or the specific dates; the parts removed are shown struck through in red with what stays. Timeline view: the timeline splits into one piece per frame; ticked pieces turn red; gaps allowed, each unbroken run is one removal; Tick all / Remove all. Fields are locked, Data source and Comment hidden (a removal carries only identity and period), the red Remove takes Save's place and asks first, naming the past frames it reaches. Owner tried it 11:13 ('works very well') and removed all of LU 29's postal rows.
- On master: test 405 (245ae853d, RED on 1.4 tmp/611-405-red-result.out), sql_saga v1.5 pin (e99e09295; the migrate runner's extension step updates 1.4 databases directly, no migration), 405 expected from 1.5 (936098260; generated on a seed copy updated 1.4->1.5 with ALTER EXTENSION + check_integrity, tmp/test-611-405-green-saga15-regress.out), restore pin row for 1.5 (ab4f4e845; Go Test caught the missing row). CI on 936098260: Fast Tests success (incl. 405), Images success.
- On branch statbus-628-all-forms (not pushed; owner reviews every edit form first, plan tmp/edit-forms-review-plan.md): Remove mode UI, removeTemporalRecord as PATCH of x__for_portion_of_valid {id: null, valid_from, valid_until} per run (removalPatch, jest RED/GREEN tmp/611-patch-{red,green}.log), Frame | Timeline (tmp/frame-view-check.log), Remove on statistics and activities (tmp/remove-single-check.log).
- Q2 (may the primary activity be removed?) answered 2026-11-16 17:26: yes (note below). The local dev database still runs sql_saga 1.4, so 3007 still removes through the local-only prototype function until it moves to the 1.5 image.


## Notes
2026-11-16 17:26 owner decision Q2: the primary activity may be removed like any other record. Basis: the import accepts a unit without one: import_analyse_activity sets primary_activity_category_id NULL when the code is missing and only warns ('Not found') when the code is unknown, never an error. Norway data (local restore 2026-11-16): 161,571 of 1,958,242 current legal units and establishments have no primary activity.

2026-11-17 11:20 task review open, Rabbit fixes after the owner walkthrough: (1) Zoom in is dated 2026-11-12/13 but includes the 2026-11-16 primary-activity decision, so update the date; (2) #3 claims every record but its test removes one, so test removing one of each kind and assert rows and comment.

2026-11-17 11:26 check #3 run (Rabbit), tmp/611-ac3-remove-each.mjs + .log, real app on branch 168a913ad (sql_saga 1.6): on EST 51, through each edit form, Frame view, Previous frame (2025), Remove, confirm. Physical location 2024|2025|2026- -> 2024|2026- ; contact 2024|2025- -> 2024|2026- ; primary activity 2024- -> 2024|2026- (split) ; Employees 2024-2025|2026- -> 2024|2026-. Each lost exactly 2025, kept the rest; other units' rows unchanged (114/8/117/165 before and after). Restored exactly from a snapshot (tmp/611-ac3-restore.sql, diff empty). Open: no row records who removed or when. The kept pieces keep their own edit_by/edit_at, and base_change_log holds only unit ids and ranges. That matches the owner's 2026-11-13 08:52 decision (no metadata with a removal) but not this ticket's Zoom in ('who removed it and when, as for other edits') or #3. Owner to decide which holds before #3 is checked.

2026-11-17 19:26 owner decision 19:09 (Rabbit): the implementation is the for_portion_of view's PATCH {id: null, valid_from, valid_until} (sql_saga); who removed what and when is a bigger question touching every import and edit path, so it moves to its own spike k5q120. Zoom in and #3 corrected. #2: test 405 extended (commit b9f0b6111 on branch statbus-628-all-forms): as a regular user under pg_safeupdate, removes 2025 of a postal location, a middle portion of an open-ended location row (split), 2025 of a primary activity and of the employees statistic (each split into 2024 and 2026-), the whole contact; a bystander legal unit with the same four kinds keeps all 4 rows (0 changed, 0 lost). RED (new expectations not yet blessed) tmp/test-611-405-each-red.log, GREEN tmp/test-611-405-each-green.log. #3: tmp/611-ac3-remove-each.log (11:26): EST 51 through each form, Frame view, Previous frame (2025), Remove: location, contact, primary activity, Employees each lost exactly 2025 and kept the rest, other units unchanged (114/8/117/165 rows), no comment or data source on the removal, restored exactly. Found while extending 405: a regular user cannot change or remove part of a period on a row another user wrote (RLS on the kept piece): bug task febdra; not caused by removal, ordinary partial edits fail the same way.


2026-11-18 03:40 (Rabbit): shipped in v2026.11.5-rc.01 (82c2da035); ladder rungs 1-8 green (orchestrator 44224042839). Remaining owner check waits for rc.01 on Norway.
2026-11-18 05:52 (Rabbit): the North Star's 'the removal is recorded like any other edit' predates check 5 (owner 2026-11-17 19:09: a removal records no who/when; change tracking is k5q120). What holds: the removed period stays visible in the unit's history. Goal/Purpose/Principle filled from the task's own text. 'hug upgrade --apply' (old waiting_for layout) left to Hibiscus, since it rewrites the whole shared board.
2026-11-18 06:54 (Rabbit): v2026.11.5-rc.02 (691e26810) carries this; ladder rungs 1-8 green (orchestrator 44247167926). Test on Norway with rc.02.
2026-11-18 11:27 (Rabbit): owner reports Norway (rune) upgraded to v2026.11.5-rc.02. The owner check on Norway is now possible.
2026-11-18 15:54 owner on Norway (no.statbus.org, v2026.11.5), establishment 479720 0404 GRUE TRAVKLUBB: physical location 'Neither here nor there' (2026-11-07 – Present, added for the purpose, mtw92d #3). Edit → Remove in the Time frame panel: the piece shown struck through in red, 'Remove physical location entirely' in Save's place beside the primary-unit notice; the dialog listed '2026-11-07 – Present: Neither here nor there, Norway'; Remove → Removing… → the field's timeline says 'No values recorded' and the fields are empty. Check 4: yes.
## History
- 2026-11-18T01:04 doing -> doing/waiting (wait)
- 2026-11-18T11:39 doing/waiting -> doing/asked (hug upgrade, 41hhgn: a question to a person is its own stage)
- 2026-11-18T12:28 doing/asked -> doing/waiting (wait); was asked_by: rabbit; asked_check: 4; asked_for: jorgen; asked_since: 2026-11-18T01:04; asked_what: owner removes a test record on Norway after the release carrying this
