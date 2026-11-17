---
id: acdq9d
title: "Editing a primary legal unit warns inside the edit form, beside Save"
status: todo
type: feature
priority: ""
assignee: []
labels: ["app", "edit"]
created: 2026-11-17
updated: 2026-11-17
---

## Goal
A user editing a field of the enterprise's primary legal unit sees, inside that edit form next to Save, that the change will also change the enterprise, and acknowledges it before saving. The side box that says this on every page goes away.

## Purpose
Owner review 2026-11-17: the yellow 'This legal unit is the primary legal unit for the enterprise ... Changes you make ... will affect the enterprise' box sits under the side menu on every page, also where nothing is being edited. It matters only while editing a field the enterprise takes from its primary legal unit, so it belongs at that Save.

## Principle
Physical locality: the warning sits where the action it qualifies is taken. Shown only when it applies.

## Relevant details
Box: app/src/app/legal-units/[id]/@primaryUnitInfo/default.tsx. Owner's options: a tick box 'Yes, I know I'm editing the primary and it changes the enterprise' that Save waits for, or the same text as a yellow/orange notice. Which fields the enterprise takes from its primary legal unit decides where it shows.

## Depends on

## Acceptance
- [ ] On a primary legal unit, opening an edit of a field the enterprise takes from it shows the warning to the left of Cancel and Save, in yellow/orange
- [ ] The side box under the menu is gone from the legal unit and establishment pages
- [ ] On a legal unit that is not primary, or a field the enterprise does not take, no warning shows
- [ ] [Owner] Decides tick box (Save waits) or notice only

## Notes
