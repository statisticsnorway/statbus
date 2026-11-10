---
id: STATBUS-604
title: >-
  Editing a unit applies the change for the portion it exists in, and every
  statement an edit causes is targeted
status: In Progress
assignee: []
created_date: '2026-11-10T10:25:00Z'
updated_date: '2026-11-10T13:59:00Z'
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

### Closing review

- Memory: recorded. Owner's small loop (first stop, fix the principle everywhere, commit per principle) and consistency over smallest change.
- Documentation: `.claude/rules/sql.md` states that every UPDATE and DELETE names its rows, with `WHERE true` and a comment for deliberate whole-table changes, and that every session runs under pg_safeupdate. doc/db regenerated with the migrations.
- Cleanup: scratch databases statbus_604_repro and statbus_604_full; tmp/venv-pglast.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With safeupdate loaded, an edit through legal_unit__for_portion_of_valid, establishment__for_portion_of_valid and location__for_portion_of_valid succeeds for a portion equal to the row and for one starting before the unit exists; the test asserts the resulting rows, no rows before the unit's first valid_from, and other units unchanged (RED before, GREEN after)
- [x] #2 The untargeted UPDATE on the edit path is named (statement and function) and bounded to the rows it is meant to change, not WHERE true
- [ ] #3 The app sends the edit with the form's portion and lets the database clip it: the legal unit rename with portion 2026-01-01..infinity on a unit from 2026-11-07 succeeds and changes the name from 2026-11-07
- [ ] #4 Adding a physical location to an establishment that has only a postal one succeeds; the 409 cause is named and fixed
- [ ] #5 [Owner] Confirms on Norway, after the release candidate carrying the fix, that renaming 314286 and editing 479720 succeed. The answer is recorded in this ticket's notes: yes closes the ticket; no reopens the investigation with the new error from rune's logs.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Investigation 2026-11-10 (local repro, tmp/604-repro*.sql/.log on a copy of a rune-shaped DB with safeupdate loaded):
- Problem 2 root cause: worker.publish_base_change_wakeup() runs `UPDATE worker.base_change_log_has_pending SET has_pending = TRUE` with no WHERE. Path: for_portion_of_trigger -> temporal_merge_execute -> UPDATE establishment -> trigger worker.log_base_change -> publish_base_change_wakeup. Introduced by f09301614 (STATBUS-591, released in v2026.11.3); before it the statement had WHERE has_pending = FALSE. Every API write that logs a change on the 14 logged tables (activity, contact, enterprise, establishment, external_ident, legal_relationship, legal_unit, location, person_for_unit, power_group, power_root, region, stat_for_unit, tag_for_unit) passes through it, so all edits from the UI fail on stable. Imports run in the worker, without safeupdate, so they are unaffected.
- 409 on adding a location: an empty Country field is coerced from "" to 0 by z.coerce.number() and violates location_country_id_fkey (23503, PostgREST 409). An empty Region gives 0 and violates location_region_version_consistency (23514, 400). Rune's DB log does not record errors, so this matches the request shape but is not read from the request body.

Decisions 2026-11-10 (owner):
- Tests run as close to production as possible: safeupdate is on while a test acts as an API user, off for worker work (option 1b).
- Flag fix (i): a producer locks the single flag row (SELECT ... FOR UPDATE), then sets it with UPDATE ... WHERE NOT has_pending; the collector clears it with WHERE has_pending. The table's comment states it holds exactly one row. Keeps the STATBUS-591 race fix.
- Edit range default: the stretch where the value shown is valid, bounded by the selected time context (intersection). A later ticket covers a timeline editor for fragmented periods, plus the owner's other editing fixes.
- Correctness before speed.

Decision 2026-11-10 11:23 (owner): safeupdate is loaded for every session through postgresql.conf (session_preload_libraries), including debug mode. The one stated exemption is the migration runner: its sessions start with -c safeupdate.enabled=off, alongside the existing read-only-window exemption (migrateReadOnlyExemptOptions), so released migrations stay byte-identical and the seed build, which replays every migration through sb migrate, keeps working. All code that runs outside migrations names its target: the 15 live function statements (including the flag fix (i)) and our scripts; deliberate whole-table clears use WHERE true with a comment. Tests get the guard because the server loads it, the same as production.

Decision 2026-11-10 11:27 (owner), replaces the 11:23 runner exemption: safeupdate applies to every session with no exemption, the migration runner included. Reason: consistency going forward. With one rule, SQL written in a migration and SQL written in a function follow the same convention, and an agent cannot learn two. Released migrations that touch every row get an explicit WHERE (WHERE true with a comment where the whole table is meant), shipped through the existing STATBUS_INTENTIONALLY_FIX_BROKEN_IMMUTABLE_MIGRATION mechanism, which re-stamps the content hash on boxes and is declared at the release cut. The full set of statements is found by replaying all migrations (seed build) and the test suite under the guard, not by text scan alone: DO blocks and functions called during migrations are only visible at run time.

Progress 2026-11-10 13:07, local branch statbus-604-safeupdate (not pushed), one commit per principle:
- b809c285e (master, local): extension install/update scripts run with safeupdate lifted for that statement, every extension.
- All migrations replay from empty under the guard: timesegments and *_used full refreshes, settings (WHERE only_one_setting), partition-key recomputes, column backfills, derived-data clears, deliberate whole-table deletes, each named.
- 3743bf94b: flag fix (i), collector and crash recovery name their rows.
- 93a204b57: import batch numbering names its all-row update.
- 9eb3f50bc: postgresql.conf loads safeupdate for every session; test 397 edits as a user through the for-portion views.
- RED: test 397 against v2026.11.3's publish_base_change_wakeup fails with 'UPDATE requires a WHERE clause' (tmp/604-red-397.log). GREEN: test 397 passes.
Next: down-all and up again under the guard; then the test suite one test at a time; doc/db regen; declare the edited released migrations.

AC1 and AC2 verified 13:07: test 397 (9eb3f50bc) edits as a user through the three views under the guard, asserting rows, no pre-birth rows, other units unchanged; RED against v2026.11.3's flag function (tmp/604-red-397.log), GREEN on the branch. The untargeted statement was worker.publish_base_change_wakeup's flag UPDATE; it now locks the row FOR UPDATE and sets it WHERE NOT has_pending (3743bf94b).

Progress 2026-11-10 13:59 (branch statbus-604-safeupdate, local):
- 139/139 fast SQL tests pass under pg_safeupdate (every session). Principles committed one each; doc/db regenerated (040e0092d); rule in .claude/rules/sql.md (4c137bb98).
- App: defaultEditRange (6b4dc91c3), app date check removed (34893f347), empty location fields are null and country is required (fc47499fc), each with jest tests RED then GREEN.
- Owner decisions 13:57-13:58: the down file 20260317114643 (drops columns before the view that reads them) is fixed here in its own commit (delegated); the edit range is wired with option 1, a small hook doing one standard read per edit start, bounded by the selected time context.
- Open with owner: how the default range relates to the selected period (end at period end or value end; telling the user why the start is not the period start).
<!-- SECTION:NOTES:END -->
