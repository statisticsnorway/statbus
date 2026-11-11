---
id: STATBUS-619
title: >-
  Saving a statistical variable or identifier type shows that it is working and
  finishes quickly on a full register
status: To Do
assignee: []
created_date: '2026-11-11T12:43:00Z'
labels:
  - app
  - db
  - admin
dependencies: []
priority: high
ordinal: 532204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
An administrator who changes a statistical variable or an identifier type sees at once that the change is being saved, and on a national register it is done in about a second.

## Zoom out
Erik (Slack 2026-11-11 13:38 local): on no.statbus.org, disabling a statistical variable (turnover) 'does not work'; on demo it does. Read-only findings on Norway (rune, v2026.11.4-rc.01, 3.1M statistical units) the same minute:
- The changes did land: stat_definition turnover enabled = false; external_ident_type stat_ident enabled = false.
- Each save took 8.6 to 13.3 s in the database (db log 12:35:09 to 12:36:28 GMT: 3 PATCH external_ident_type at 12.3 to 13.3 s, 4 PATCH stat_definition at 8.6 to 9.0 s). Erik pressed Save several times.
- The time is the statement trigger lifecycle_callbacks.cleanup_and_generate (AFTER INSERT/UPDATE/DELETE on stat_definition and external_ident_type), which runs every registered callback: statistical_unit_jsonb_indices (indices on statistical_unit), import external ident, link, stat var data columns, and default definition mappings.
- The form (app/src/app/admin/statistical-variables/statistical-variables-form.tsx) shows nothing while the server action runs: no pending state on Save, the dialog stays open until success. On demo the save is instant, so the gap does not show.
- Locally (tmp/statvar-disable-repro.sql, rolled back) the same UPDATE as admin_user succeeds.

## Zoom in (to agree before building)
- The form shows a pending state (Save disabled, 'Saving...') and closes on success; an error is shown in the dialog.
- The regeneration does only the work the change needs (e.g. an enabled flip on one variable adds or drops that variable's index and columns), or runs after the reply, so the save returns quickly on a full register. Measure on a Norway-sized database before and after.
- The same for the identifier types admin page, which shares the trigger.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Save shows a pending state until the server replies, and the dialog closes on success or shows the error; a test asserts it
- [ ] #2 Disabling one statistical variable on a database with 3M statistical units returns in under 2 s; the measurement before and after is recorded in this ticket
- [ ] #3 [Owner] Disables and re-enables a statistical variable on Norway after the release carrying this. The answer is recorded in this ticket's notes: yes closes the ticket; no gives the error to investigate.
<!-- AC:END -->
