---
id: m6mnnw
title: "A unit edit form shows Saving… while its save runs"
state: todo
type: feature
priority: "high"
assignee: []
labels: []
group: ""
rank: "zzy"
created: 2026-11-18
updated: 2026-11-18
---

## Goal
While a save on a unit's edit form runs, its Save button shows a spinner and 'Saving…', and Save and Cancel are disabled until the save finishes or fails.

## Purpose
On Norway a save can take seconds while the recalculation runs; with no sign that anything happens, a user clicks again or leaves (owner on no.statbus.org, 2026-11-18: the first save of Veridit AS took a while with no spinner).

## Principle
The same pending footer the admin dialogs already have (q8604t, app/src/app/admin/admin-dialog-footer.tsx): one shared way to show a running save, not a spinner per field. The save itself is not made faster here.

## Relevant details
Save buttons of the unit edit forms, none of which tracks a pending state today: app/src/components/form/editable-field-group.tsx (line ~167, disabled only by useSaveApproval's blocked), editable-field.tsx, editable-hierarchical-field.tsx, editable-image-field-with-metadata.tsx. Used by the legal unit, establishment and enterprise pages (general-info, contact, demographic forms). Whoever finishes their current task first takes this (owner 2026-11-18): hibiscus or Rabbit.

## Depends on

## Acceptance
- [ ] Every unit edit form's Save shows a spinner and 'Saving…' with Save and Cancel disabled while the save runs; a jest test asserts the pending state for the field group and the single field
- [ ] On the local Norway data in Firefox, a save on a legal unit shows Saving… until the page shows the saved value; the owner sees it

## Notes
