---
id: 2gpcs7
title: "Workflow: pick the primary unit by a chosen variable"
state: todo
type: feature
priority: ""
assignee: []
labels: []
created: 2026-11-18
updated: 2026-11-18
---

## Goal
A workflow picks, for each enterprise, its primary legal unit (and for each legal unit, its primary establishment) as the one that scores highest on a chosen statistical variable such as employees, and produces an import job that sets the primary, so the enterprise's primary activity follows.

## Purpose
How the primary legal unit is chosen is not settled. The owner's idea (2026-11-18): after last year's employees are calculated and analysed, pick the biggest; the enterprise's primary activity then comes from that unit. Calculated dynamically, applied reviewably.

## Principle
A separate step that generates a change file (an import job), never a silent update. Picking the primary is this workflow's job; checks that use the primary (xz3jej) take it as given and do not re-pick it.

## Relevant details
Owner notes 2026-11-18: add support to calculate the primary activity for an enterprise based on the most important unit, with respect to a variable, say employees, and then pick the winner. This could be used for selecting the primary legal_unit, with dynamic calculation. Existing flags: legal_unit.primary_for_enterprise (one per enterprise and period, EXCLUDE constraint), establishment.primary_for_legal_unit.

## Depends on
- xhxnsy

## Acceptance
- [ ] [Owner] Decides the configuration (the variable, the frame's period, how ties are broken) and whether the same workflow covers legal units within enterprises and establishments within legal units; the answer is recorded in the notes
- [ ] A SQL test asserts which unit the workflow picks, including a tie and a unit missing the variable
- [ ] Running the workflow produces an import job that changes the primary flags only where the pick differs from today, and after applying it the enterprise's primary activity is the picked unit's

## Notes
