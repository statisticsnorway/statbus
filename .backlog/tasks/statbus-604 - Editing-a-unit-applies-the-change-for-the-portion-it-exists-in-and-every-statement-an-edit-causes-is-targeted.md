---
id: STATBUS-604
title: >-
  Editing a unit applies the change for the portion it exists in, and every
  statement an edit causes is targeted
status: In Progress
assignee: []
created_date: '2026-11-10T10:25:00Z'
updated_date: '2026-11-10T10:26:00Z'
labels:
  - app
  - db
  - editing
dependencies: []
priority: high
type: bug
ordinal: 518204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star

1. An edit with any portion of time (the form defaults to the selected year) changes the unit exactly where it exists inside that portion, and nowhere else. The app does not refuse a portion the database's for-portion-of update handles.
2. A targeted edit (one unit, `id=eq.N`) causes only targeted statements: every UPDATE it triggers is bounded to that unit or the edit's own working rows. No step updates a whole table.

### Zoom out

Reported on Norway (no.statbus.org, v2026.11.3 b9d6661e0) 2026-11-10 and reproduced by the owner:
- Legal unit 314286 (one row from 2026-11-07): renaming with the default portion 2026-01-01..infinity fails in the app with "Cannot update legal unit: the provided valid from (2026-01-01) is before the earliest valid from (2026-11-07) for this record. Date range must be fully within or fully outside the existing range." No request reaches the database.
- Establishment 479720 (one row from 2026-11-07): with the portion equal to the row (2026-11-07..infinity) the app check passes, and `PATCH /rest/establishment__for_portion_of_valid?id=eq.479720` returns 400 "UPDATE requires a WHERE clause" (09:39:56 reporter, 10:21:33 owner). pg_safeupdate is preloaded for PostgREST sessions and checks every statement, including those run inside triggers, so an untargeted UPDATE exists somewhere on the path: the view's sql_saga.for_portion_of_trigger, sql_saga.temporal_merge, or StatBus triggers on the table.
- Same establishment: six attempts to add a physical location (09:36-09:38) went the insert path of upsertTemporalRecord and got 409 from POST /rest/location. Cause to be found in the same reproduction.
- Our tests and sql_saga's run without safeupdate, so they did not see problem 2.

### Zoom in

- Problem 1: checkValidityBounds (app/src/components/form/helper-functions.ts) guards updateLegalUnit, updateEstablishment and upsertTemporalRecord (location, contact, activity, stat_for_unit). The for-portion-of view already clips the portion to where the unit exists.
- Problem 2: reproduce locally with safeupdate loaded, as the authenticated role, through the view, verbose errors and debug logs; the error context names the untargeted statement and its function. Bound it to what it is meant to change, in sql_saga upstream or in StatBus, whichever owns it. Not `WHERE true`.
- RED first: SQL tests under safeupdate for legal unit, establishment and location edits through the views, with a portion equal to the row and a portion starting before the unit exists. Assert the edited rows, no history before the unit existed, and other units unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 With safeupdate loaded, an edit through legal_unit__for_portion_of_valid, establishment__for_portion_of_valid and location__for_portion_of_valid succeeds for a portion equal to the row and for one starting before the unit exists; the test asserts the resulting rows, no rows before the unit's first valid_from, and other units unchanged (RED before, GREEN after)
- [ ] #2 The untargeted UPDATE on the edit path is named (statement and function) and bounded to the rows it is meant to change, not WHERE true
- [ ] #3 The app sends the edit with the form's portion and lets the database clip it: the legal unit rename with portion 2026-01-01..infinity on a unit from 2026-11-07 succeeds and changes the name from 2026-11-07
- [ ] #4 Adding a physical location to an establishment that has only a postal one succeeds; the 409 cause is named and fixed
- [ ] #5 [Owner] On Norway, after the release carrying the fix, the reported edits on 314286 and 479720 succeed
<!-- AC:END -->
