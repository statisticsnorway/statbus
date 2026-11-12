---
id: STATBUS-611
title: Records added to a unit can be removed from the edit form
status: To Do
assignee: []
created_date: '2026-11-10T21:29:00Z'
updated_date: '2026-11-12T21:25:00Z'
labels:
  - ui
  - edit
  - temporal
dependencies: []
priority: high
type: feature
ordinal: 525204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
Anything a user can add to a unit in the edit form, the user can also remove there, for a chosen period or entirely, and the removal is recorded like any other edit.

## Zoom out
Owner testing on Norway (v2026.11.4-rc.01, 2026-11-10 21:29): after adding a test physical location (region 03, country AX, from 2026-11-07; location 2312602) to establishment 0404 GRUE TRAVKLUBB (org no. 933130436), the form offers no way to remove it. The same holds for every record the forms can add to a unit: postal and physical locations, contact details, secondary activities, statistics, tags and other linked rows.
- The edit forms only update or insert (upsertTemporalRecord); nothing deletes.
- The for-portion-of views do not support DELETE (sql_saga: standard SQL cannot pass the [from, until) portion to a DELETE trigger). sql_saga.temporal_merge offers mode 'DELETE_FOR_PORTION_OF' (a mode, not a delete_mode), which removes a time portion and splits a row when the portion is in the middle.
- Removing a record for a period differs from ending a unit (closing it with a death date, STATBUS-600): the unit stays, only the linked record goes for that period.

## Zoom in (to discuss with the owner before building)
- What the user does: a remove action on the record in the edit form, with the same period controls as an edit (the time frame by default, the edit icon for exact dates); "remove for this period" versus "remove entirely" (every period).
- What is recorded: the edit comment and who removed it, as for other edits; whether removed history stays visible in the unit's history.
- How the database does it: a removal function per table, or a generic one built on temporal_merge DELETE_FOR_PORTION_OF, called through the API like the for-portion-of views; the same rules as STATBUS-608 for what may be removed (a required record cannot be removed).
- Then: remove the owner's test row 2312602 on Norway through the new action, not by hand.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 [Owner] Decides how removal works in the UI (remove for a period versus entirely, where the action sits, what history shows) after a walk-through. The answer is recorded in this ticket's notes and becomes the build plan.
- [ ] #2 A location, contact, activity and statistic can each be removed for a chosen period through the API; a test removes a middle portion and asserts the split rows and that other units are unchanged
- [ ] #3 The edit form offers the agreed remove action for every record it can add; a test removes a record through the form and asserts the stored rows and the edit comment
- [ ] #4 [Owner] Removes the test physical location (region 03, Åland Islands) from 0404 GRUE TRAVKLUBB (933130436) on Norway through the form after the release carrying this. The answer is recorded in this ticket's notes: yes closes the ticket; no gives the error to investigate.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner 2026-11-10 21:30: other single-value fields already turn Save into a delete when the value is erased (external identifiers: update-external-ident-server-action.ts deletes the row when the ident is emptied, refusing the last one; the image: clearing it clears image_id and deletes the image). A form with several fields (a location: address parts, post code, region, country, coordinates) needs an explicit UI interaction for removal, not erase-to-delete. The test physical location 2312602 on Norway was removed by hand (SQL, exactly one row, 21:30) at the owner's request; the postal address 1889376 remains.

2026-11-12 15:38 database findings (Rabbit, rolled back, tmp/611-delete-portion-probe.log, tmp/611-delete-probe.log): (1) DELETE through location__for_portion_of_valid is refused: 'The for_portion_of view only supports UPDATE operations' (sql_saga.for_portion_of_trigger). (2) DELETE_FOR_PORTION_OF is a temporal_merge MODE (sql_saga.temporal_merge_mode), not a delete_mode; the delete_mode enum is NONE / DELETE_MISSING_TIMELINE / DELETE_MISSING_ENTITIES / DELETE_MISSING_TIMELINE_AND_ENTITIES. (3) CALL sql_saga.temporal_merge(target_table=>'public.location', source_table=>src(row_id,id,valid_from,valid_until), primary_identity_columns=>ARRAY['id'], mode=>'DELETE_FOR_PORTION_OF') with 2024-01-01..2025-01-01 removed exactly 2024 from unit 28's physical location (9 rows -> 8, 2023 and 2025.. kept), 35 ms. So a removal function per table (or one generic) can call temporal_merge with that mode. (4) What may be removed follows the constraints: contact needs at least one value (CHECK), so emptying all its fields = removing it; activity.category_id and location.country_id are NOT NULL, so clearing them = removing the record.

2026-11-12 21:25 owner design: Remove goes through the for_portion_of view as UPDATE x__for_portion_of_valid SET id = NULL, valid_from = START, valid_until = STOP WHERE id = N (PostgREST PATCH body {"id": null, "valid_from", "valid_until"}): removes the record over [START, STOP), splitting rows at the edges (temporal_merge DELETE_FOR_PORTION_OF). Rejected: a view-only marker column (must be real columns); all values NULL (a legitimate update, and contact's CHECK refuses it). Specified for the sql_saga agent in ../sql_saga/todo.md ('Next - for_portion_of view: remove a portion with SET id = NULL'), with 8 tests. Today on 1.4 SET id = NULL reports UPDATE 1 and changes nothing (tmp/611-null-id-probe2.log). StatBus pins the new sql_saga, then builds the Remove button on it; the prototype function public.remove_for_portion_of (local dev DB only) is dropped then.
<!-- SECTION:NOTES:END -->
