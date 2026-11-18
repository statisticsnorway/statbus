---
id: acdq9d
title: "Editing a primary legal unit warns inside the edit form, beside Save"
state: "done"
type: feature
priority: ""
assignee: ["rabbit"]
labels: ["app", "edit"]
created: 2026-11-17
updated: 2026-11-17
model: "claude-opus-5-5"
branch: "statbus-628-all-forms"
worktree: "/Users/jhf/ssb/statbus_test"
done_at: "2026-11-18T03:31"
---

## Goal
A user editing a field of the enterprise's primary legal unit sees, inside that edit form next to Save, that the change will also change the enterprise. The side box that says this on every page goes away.

## Purpose
Owner review 2026-11-17: the yellow 'This legal unit is the primary legal unit for the enterprise ... Changes you make ... will affect the enterprise' box sits under the side menu on every page, also where nothing is being edited. It matters only while editing a field the enterprise takes from its primary legal unit, so it belongs at that Save.

## Principle
Physical locality: the warning sits where the action it qualifies is taken. Shown only when it applies.

## Relevant details
Boxes: app/src/app/legal-units/[id]/@primaryUnitInfo/default.tsx and app/src/app/establishments/[id]/@primaryUnitInfo/default.tsx, shown in the side column of every legal unit and establishment page (Identification, Contact, Demographic, Classifications, Statistical variables, History, Links, Inspect). Every field the edit forms show reaches the enterprise through its primary legal unit (timeline_enterprise_def). Owner's choice, 2026-11-17 19:09: a yellow/orange notice beside Save, Save stays enabled (no tick box).

## Acceptance
- [x] On a primary legal unit, opening an edit of a field the enterprise takes from it shows the warning to the left of Cancel and Save, in yellow/orange
- [x] The side box saying the unit is primary is gone from every legal unit and establishment page that showed it (all eight tabs share the side column)
- [x] On a legal unit that is not primary, or a field the enterprise does not take, no warning shows
- [x] [Owner] Chooses notice or tick box, recorded in Relevant details; a notice keeps Save enabled beside it, a tick box keeps Save waiting until ticked and clears the tick when the edit closes

## Notes

2026-11-17 13:44 built on branch (Rabbit) as a notice (no tick box yet: the owner's choice is open). PrimaryUnitNotice beside Cancel/Save in all three edit wrappers; the LU and EST side-column primary boxes removed (the 'Set as primary' box for non-primary units stays). Headless tmp/acdq9d-check.log + tmp/acdq9d/: LU 29 Name and Sector show 'Primary for the enterprise EDIT PAGES AS: this change also changes the enterprise.'; EST 51 shows 'Primary for the legal unit EDIT PAGES AS: ...'; EST 17 (not primary) shows no notice; no page shows the old side box. tsc ok, lint 0 errors, jest 435 (tmp/acdq9d-checks.log). Open: which fields the enterprise takes. All the forms' fields come through the primary LU in timeline_enterprise_def (name, activities, locations, contact, legal form, sector, unit size, status, stats), so the notice shows on every field of a primary unit.

2026-11-17 19:12 owner chose the notice (19:09). Check #4: tmp/acdq9d-check.mjs now also reads Save's state; tmp/acdq9d-check-save.log: LU 29 Name and Sector and EST 51 Name show the notice with Save enabled; EST 17 (not primary) shows none, Save enabled. Branch 617f1f125 (commit 1db6cf947). Done after push and CI.


landed 839f84c on master 2026-11-18: app: editing a primary unit says, beside Save, that the change also changes the…
2026-11-18 02:32 (Rabbit): pushed to master as 82c2da035; CI green on that SHA: Fast Tests 44222154288, Go Test, app build & lint, Images, Harness Selftest. Local fast suite 145/145 (tmp/rc-fast2.log).
## History
- 2026-11-18T01:04 doing -> doing/waiting (wait)
- 2026-11-18T03:31 doing/waiting -> done (done); was waiting_asked_by: rabbit; waiting_on: branch statbus-628-all-forms pushed to master and CI green, then done; waiting_since: 2026-11-18T01:04
