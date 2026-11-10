---
id: STATBUS-610
title: Optional selects in the edit forms can be emptied
status: To Do
assignee: []
created_date: '2026-11-10T21:27:00Z'
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
## North Star
A field that may be empty can be emptied again in the form.

## Zoom out
Owner testing on Norway (2026-11-10 21:23-21:26): once Region or Country is chosen in the physical location edit, it cannot be removed. SelectFormField (app/src/components/form/select-form-field.tsx) only sets a value: choosing an option sets it, and choosing the selected option again sets it again. It is used in the general info, contact and demographic forms of legal units and establishments, so every optional select there has the same gap.

## Zoom in
An optional select offers a way to empty it (a "None" entry at the top of the list or a clear button beside the value); a required one does not. Whether a field is optional comes from the same rules as STATBUS-608, not from a separate list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every optional select built on SelectFormField can be emptied, and saving stores NULL; a test empties one and asserts the saved value
- [ ] #2 A required select offers no way to empty it; a test asserts the clear control is absent
<!-- AC:END -->
