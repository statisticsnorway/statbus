---
id: STATBUS-610
title: Optional selects in the edit forms can be emptied
status: In Progress
assignee: []
created_date: '2026-11-10T21:27:00Z'
updated_date: '2026-11-13T13:54:00Z'
labels:
  - ui
  - edit
dependencies: []
priority: medium
type: bug
ordinal: 524204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A field that may be empty can be emptied again in the form.

Owner testing on Norway (2026-11-10 21:23-21:26): once Region or Country was chosen in the physical location edit, it could not be removed, as SelectFormField only sets a value. Owner 2026-11-13: unit size should be clearable ("set to nothing").

An optional select starts with None, storing no value (NULL), the same as an empty cell in an import. A required select (status, country, activity category) has no None. Which fields are optional follows the database: legal_unit legal_form_id, sector_id, unit_size_id; establishment unit_size_id; location region_id are nullable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every optional select built on SelectFormField can be emptied, and saving stores NULL; a test empties one and asserts the saved value
- [x] #2 A required select offers no way to empty it; a test asserts the clear control is absent
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-13 (Rabbit, branch statbus-628-all-forms, not pushed yet): optional selects start with None, storing no value: unit size (legal unit, establishment), region (physical location), legal form and sector (legal unit). An emptied sector or legal form stored a reference to row 0 (z.coerce of ""): now optionalId, 3360900f8 (RED/GREEN tmp/610-none-{red,green}.log). codeListOptions ac781d7d7: a code list row without a code (a sector heading such as DOMESTIC) shows without 'null' and can't be chosen, as the import also looks sectors up by code. Real app tmp/610-none-check.log: LU 29 sector set to None stored NULL for 2026, restored through the form. Required: status, country, activity category (removing an activity is STATBUS-611).
<!-- SECTION:NOTES:END -->
