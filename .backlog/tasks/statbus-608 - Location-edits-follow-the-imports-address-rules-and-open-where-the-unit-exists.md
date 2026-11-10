---
id: STATBUS-608
title: >-
  Location edits follow the import's address rules and open where the unit
  exists
status: To Do
assignee: []
created_date: '2026-11-10T21:24:00Z'
labels:
  - ui
  - edit
  - location
dependencies: []
priority: high
type: bug
ordinal: 522204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## North Star
Adding or changing an address in the edit form follows the same rules as the import, opens on the period where the unit exists, and every problem is shown on its own field before anything is saved.

## Zoom out
Owner testing on Norway (v2026.11.4-rc.01, 2026-11-10 21:21-21:24), adding a physical location to establishment 0404 GRUE TRAVKLUBB (org no. 933130436), which exists from 2026-11-07 and has only a postal address:
1. Valid From opens on 2026-01-01, the selected period's start. A new record has no rows to read, so readEditRange falls back to the context instead of to where the unit exists.
2. Save with 2026-01-01 refuses: "Cannot add location for the period 2026-01-01 to infinity. The establishment does not exist for this period." upsertTemporalRecord's insert path kept the app-side date check that STATBUS-604 removed from the update path.
3. Address part 1 only, or with Region 03 Oslo and no country: "failed to parse form data for location". locationSchema requires country_id, and its field message never reaches the form; only the generic message is shown, and the Valid From problem is not shown at all.
4. Region and Country cannot be emptied once chosen: SelectFormField only sets a value. It is used in the general info, contact and demographic forms of legal units and establishments.

## Zoom in
The import's rules (migration 20260520141309, import.analyse_location) are the rule for the edit form too:
- Region given, no country: the country is the domestic country (regions exist only there). Region plus an address is enough for a domestic address (owner).
- Neither given: country defaults to the domestic country; a physical address without a region gets the missing-region warning.
- Region with a foreign country: refused, "Region can only be supplied for the domestic country."
- Postal addresses need no region.
A new record opens on the stretch where the unit exists within the selected time frame, and its period is clipped to where the unit exists, as an edit is.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Adding a location to a unit that starts inside the selected time frame opens Valid From on the unit's first day; a test of readEditRange with no rows asserts it
- [ ] #2 Saving a new location whose period starts before the unit exists stores it from the unit's first day, no earlier, and nothing is refused; a test asserts the stored rows
- [ ] #3 The edit form applies the import's region/country rules (domestic default, region implies domestic, region with a foreign country refused, postal needs no region); a test per rule asserts what is saved or the field message
- [ ] #4 Each validation problem is shown on its own field, all at once, before saving; the generic 'failed to parse form data' is not the only message; a test asserts the field messages
- [ ] #5 An optional select (region and the others using SelectFormField) can be emptied; a test empties one and asserts the saved value is null
- [ ] #6 [Owner] Adds a physical location with only Address part 1 and Region 03 Oslo to 0404 GRUE TRAVKLUBB (933130436) on Norway after the next release candidate. The answer is recorded in this ticket's notes: yes closes the ticket; no gives the error to investigate.
<!-- AC:END -->
