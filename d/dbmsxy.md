---
id: dbmsxy
title: "An import can update only the columns a file gives, on existing units"
state: todo
type: feature
priority: "high"
assignee: []
labels: []
group: ""
rank: "zzzzx"
created: 2026-11-21
updated: 2026-11-21
---

## Goal
A user can upload tax_ident plus a few columns (like lat+lon) and only those values change on existing units, from the chosen date onward.

## Purpose
Erik (Norway, Slack 2026-11-11 to 18) cannot add coordinates to units already in no.statbus: the file must repeat the name, a 'current' job adds a row before the unit existed, and establishment rows fail in processing with name or link not-null errors. Owner 2026-11-21: the advanced import must show the underlying machinery (patch or upsert, update versus upsert).

## Principle
The import definition's strategy picks the sql_saga merge mode; the user sees it in plain words under an Advanced switch and the simple path keeps today's defaults. A column the file does not carry is never written.

## Relevant details
Findings 2026-11-21 (Rabbit, rolled-back prototype on the test slot, tmp/slack-todos/modes*.log and tmp/journal.md):
- Strategy to merge mode today (import.process_*): insert_or_replace=MERGE_ENTITY_REPLACE, replace_only=REPLACE_FOR_PORTION_OF, insert_or_update=MERGE_ENTITY_PATCH, update_only=UPDATE_FOR_PORTION_OF. process_establishment differs: replace_only=MERGE_ENTITY_REPLACE, update_only=MERGE_ENTITY_UPSERT. insert_only has no mapping (falls to PATCH). No strategy uses PATCH_FOR_PORTION_OF.
- Every seeded definition is insert_or_update except generic_unit_stats_update (replace_only). The app offers no strategy choice; unit type and time frame pick the definition.
- Inside a unit's life with a column absent: PATCH modes keep the value; UPSERT, REPLACE and UPDATE_FOR_PORTION_OF write NULL over it.
- A period that starts before the unit existed: MERGE_ENTITY_* modes insert the uncovered stretch with only the file's columns and fail with 'null value in column name' (Erik's job 5). *_FOR_PORTION_OF modes clip to the unit's life and apply.
- So 'update these columns on units that exist' is PATCH_FOR_PORTION_OF, which no strategy reaches today.
- Erik also asked: put an update only on the record that runs to infinity (from a date forward), and analyse only the columns present (his 3-column file ran all 16 analysis steps, about 5 minutes).
Related: 6btpmz (unit notes, waits on this), qtx2xm (same rules for edits and imports), e334k3 (definition editor), r39dqb (Norway coordinates).

## Depends on

## Acceptance
- [ ] [Owner] Settles the strategies the Advanced switch offers, their plain names, and which merge mode each uses (including whether update_only becomes PATCH_FOR_PORTION_OF and process_establishment matches the others); the answer is recorded in this task's notes
- [ ] A file with only tax_ident, physical_latitude and physical_longitude, imported with the update strategy on units that exist from 2026-11-07, sets the coordinates from the chosen date and leaves name and every other value unchanged; a SQL test asserts the stored rows
- [ ] The same file with a date before a unit existed stores nothing outside the unit's life and reports no processing error; a test asserts it
- [ ] The upload page has an Advanced switch that shows the strategy in plain words; a Playwright test picks the update strategy and the job's definition has it
- [ ] Analysis runs only the steps whose columns the file carries; a test with a 3-column file asserts which steps ran
- [ ] The job records which analysis steps ran and why the others were skipped (no column in the file); the job page shows it and a test asserts the record for a 3-column file
- [ ] The job's data view shows only the columns of steps that ran for that job; a Playwright test on a 3-column job asserts the shown columns

## Notes

2026-11-21 21:50 (hibiscus) the map (z2qt08) needs this to put Erik's coordinates on Norway's existing units; it is phase 0 of doc/design/units-on-map.md on feat/units-on-map.
