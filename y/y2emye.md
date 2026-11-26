---
id: y2emye
title: "Icons for data-quality checks so each card shows what it checks"
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
Each data-quality card and Quality filter option carries an icon for its kind of check, so a long name is recognised at a glance.

## Purpose
Some check names are long (the per-variable ones), so on the dashboard it is hard to tell the checks apart; the owner asked to consider iconography later (2026-11-26).

## Principle
One icon per rule of public.quality_rule, keyed by the enum like the wording, so a new rule fails the type check until it has one; the variable stays in the name. Names are not shortened at the cost of meaning.

## Details
Follows 05pe0x (catalogue of checks, wording in app/src/lib/quality-checks.ts). Candidate kinds: location (missing region, missing physical location), activity (missing activity category, establishment has another activity), counting between levels (the two per-variable rules).

## Depends on

## Acceptance
- [ ] [Owner] chooses the icon per kind of check; the choice is recorded in this task's notes
- [ ] Every Data quality card and Quality filter option shows its rule's icon, typed by the enum (tsc fails for a rule without one); seen in Firefox

## Notes
