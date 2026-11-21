---
id: 2gpcs7
title: "Workflow: pick the primary unit by a chosen variable"
state: todo
type: feature
priority: "high"
assignee: ["hibiscus"]
labels: []
group: ""
rank: "000000000002"
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

2026-11-18 14:54 Erik Søberg's rule from PR #328 (https://github.com/statisticsnorway/statbus/pull/328, closed today, his comment 12:16): for each legal unit, the most significant establishment is the one with the most employees valid today; on a tie, any of the tied ones; a legal unit passes when its primary activity equals that of the most significant establishment, or of one of the tied ones. Scope: all active, countable legal units. That rule has two steps: picking the establishment (this workflow, with employees as the variable and Erik's tie rule as a candidate for check 1), and comparing activities (the quality check xz3jej, merged to master 8aaf0262b, which compares with the recorded primary). Once this workflow moves primary_for_legal_unit to the largest establishment, xz3jej answers Erik's question; his example: Equinor's legal unit filed as green energy while its biggest establishment is oil. Measured on the Norway restore with his rule (tmp/hug/328-reference.sql): 10,129 legal units with more than one establishment, 1,826 whose top establishment has another activity, 1,911 with tied top establishments (750 where the tie decides), 1,749 whose top establishment has 0 employees. Owner 14:52: fix the primary first (this workflow), then the check is right.
