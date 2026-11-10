---
id: STATBUS-609
title: Adding a record to a unit opens and saves on the period where the unit exists
status: To Do
assignee: []
created_date: '2026-11-10T21:27:00Z'
labels:
  - ui
  - edit
  - temporal
dependencies: []
priority: high
type: bug
ordinal: 523204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
Adding a record to a unit (a location, contact, activity or statistic it does not have yet) opens on the period where the unit exists, and saving it stores it there, the same way an edit of an existing value does (STATBUS-604).

## Zoom out
Owner testing on Norway (v2026.11.4-rc.01, 2026-11-10 21:21), adding a physical location to establishment 0404 GRUE TRAVKLUBB (org no. 933130436), which exists from 2026-11-07:
1. Valid From opened on 2026-01-01, the selected time frame's start. readEditRange (app/src/components/form/read-edit-range.ts) reads the field's rows; a new record has none, so it falls back to the context instead of to where the unit exists.
2. Saving with 2026-01-01 refused: "Cannot add location for the period 2026-01-01 to infinity. The establishment does not exist for this period. The establishment exists for: 2026-11-07 to infinity." upsertTemporalRecord's insert path (app/src/app/legal-units/[id]/update-legal-unit-server-actions.ts) still has the app-side date check that STATBUS-604 removed from the update path (34893f347).
3. With Valid From set by hand to 2026-11-07 the save went through.

## Zoom in
- With no rows for the field, the edit opens on the unit's own stretch within the selected time frame (its first valid_from inside the frame, to the frame's end).
- The insert path clips the period to where the unit exists, as the for-portion-of update does (the definition of an update for portion of), instead of refusing. One rule for new and existing records.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Adding a location, contact, activity or statistic to a unit that starts inside the selected time frame opens Valid From on the unit's first day; a test of readEditRange with no rows for the field asserts it
- [ ] #2 Saving a new record whose period starts before the unit exists stores it from the unit's first day and no earlier, without an error; a test asserts the stored rows for a portion starting before the unit
- [ ] #3 [Owner] On Norway after the release carrying this, adds a physical location to 0404 GRUE TRAVKLUBB (933130436) without changing Valid From. The answer is recorded in this ticket's notes: yes closes the ticket; no gives the error to investigate.
<!-- AC:END -->
