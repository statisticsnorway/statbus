---
id: m6mnnw
title: "A unit edit form shows Saving… while its save runs"
state: "doing"
type: feature
priority: "high"
assignee: ["hibiscus"]
labels: []
group: ""
rank: "zzy"
created: 2026-11-18
updated: 2026-11-18
doing_since: "2026-11-19T16:26"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
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
- [x] Every unit edit form's Save shows a spinner and 'Saving…' with Save and Cancel disabled while the save runs; a jest test asserts the pending state for the field group and the single field
- [ ] On the local Norway data in Firefox, a save on a legal unit shows Saving… until the page shows the saved value; the owner sees it

## Notes


check 1: 203628fe0: FormSaveButton/FormCancelButton (app/src/components/form/form-save-buttons.tsx) follow the form's useFormStatus, used by every unit edit form (field group, single, hierarchical, metadata, select, image). Jest form-save-buttons.test.tsx asserts the field group and the single field: idle Save enabled; pending Saving… with Save and Cancel disabled. RED before (tmp/hug/m6mnnw-jest-red.log: 2 pending cases fail), GREEN after (m6mnnw-jest-green.log); full jest 465/465.
2026-11-19 Firefox 155 (driven) on the local Norway copy, VERIDIT AS (1030202) contact group, web address: Saving… with Save and Cancel disabled from 0.46 s, edit closed at 1.11 s, the page showed the saved value at 1.18 s (tmp/hug/m6mnnw-firefox.log, screenshot tmp/hug/m6mnnw-saving.png). The test save created a contact row; the script's restore did not complete, so I deleted that one row (id 174634, the unit had none before). Check 2 waits for the owner to see it in his Firefox.
## History
- 2026-11-19T16:26 todo -> doing/active (take)
