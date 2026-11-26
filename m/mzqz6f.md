---
id: mzqz6f
title: "One Save click sends the edit twice and runs two derive cycles"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzy"
created: 2026-11-26
updated: 2026-11-26
---

## Goal
A Save on a unit's field sends one write, so one change runs one derive cycle.

## Purpose
Owner test 2026-11-26 on legal unit 146: one click on Save for the secondary activity gave two POSTs to /legal-units/146/classifications (dev log). The first inserted the activity row; the second PATCHed activity__for_portion_of_valid with the same value. The PATCH logged a base change, so a second collect_changes (116188) ran the whole pipeline again (about 3 minutes on Norway) and the navbar showed Starting... after the first cycle finished.

## Principle
Find the second submit's source and remove it; the save path stays one form submit. A test asserts one write per click.

## Details
Suspects: the capture submit listener in app/src/components/form/edit-metadata-controls.tsx (ask/confirmedRef/requestSubmit) together with the form's action in editable-field-with-select.tsx. Proxy log 22:49:20: POST /rest/activity 201, then 0.5 s later PATCH /rest/activity__for_portion_of_valid 204.

## Depends on

## Acceptance
- [ ] One Save click on a classification field sends one server action and one REST write (observed in the proxy log)
- [ ] A test fails before the fix and passes after it

## Notes
