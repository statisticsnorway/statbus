---
id: ep47vn
title: "The primary notice names only what flows to the other unit"
state: todo
type: bug
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzh"
created: 2026-11-20
updated: 2026-11-20
design_question: "Which fields of a primary legal unit flow to its enterprise (name unless the enterprise has a short name; activities, locations, contact, sector, legal form, status, figures?), and which of a primary establishment flow to its legal unit? The notice beside Save will name the other unit only on those fields."
design_for: "jhf"
design_since: "2026-11-20T17:15"
design_asked_by: "hibiscus"
stage: "design"
---

## Goal
Editing a unit says it changes another unit only for fields that really flow there, as does the enterprise's derived-from line.

## Purpose
A notice that overstates what a change touches teaches users to ignore it. The owner (2026-11-20): the name of a non-primary legal unit does not change the enterprise's name, and an enterprise's name, primary or not, does not change the legal unit's name.

## Principle
The notice follows the derivation, field by field: what timeline_enterprise_def takes from the primary legal unit (or establishment) is what the notice names; nothing else.

## Relevant details
PrimaryUnitNotice (app/src/components/form/primary-unit-notice.tsx, 839f84c98) shows 'Primary for the enterprise X: this change also changes the enterprise' beside Save on every form of a primary unit, whatever the field. timeline_enterprise_def: the enterprise's name is COALESCE(enterprise.short_name, primary legal unit's name, primary establishment's name), so an enterprise with a short_name does not take its name from the legal unit; enterprise owns only short_name, enabled and edit stamps. On the local Norway copy no enterprise has a short_name (0 of 1,134,475). The enterprise header's derived-from line (64ae2w, answer 4) must say the same. Raised by the owner while designing 64ae2w.

## Depends on

## Acceptance
- [ ] [Owner] Confirms which fields flow from a primary legal unit to its enterprise (and from a primary establishment), and what the notice says when the enterprise has its own short name; recorded in the notes
- [ ] The notice beside Save appears only on fields that flow to the other unit, and names that unit; a jest test covers a flowing and a non-flowing field
- [ ] Editing an enterprise's short name, and a non-primary legal unit's name, shows no such notice; checked in Firefox on the local Norway data

## Questions
- 2026-11-20T17:15 question 1 by hibiscus to jhf:
  Which fields of a primary legal unit flow to its enterprise (name unless the enterprise has a short name; activities, locations, contact, sector, legal form, status, figures?), and which of a primary establishment flow to its legal unit? The notice beside Save will name the other unit only on those fields.

## Notes


## History
- 2026-11-20T17:15 todo -> todo/design (ask)
