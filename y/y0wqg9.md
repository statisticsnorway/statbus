---
id: y0wqg9
title: "A legal unit's primary establishment is not born yet in the period shown"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzz"
created: 2026-11-27
updated: 2026-11-27
---

## Goal
In every period a legal unit exists, its primary establishment is one that exists in that period, or the user is told none does.

## Purpose
jo.statbus.org, Frame 2023, Drill Down Norway AS (establishment 89): the page says it is not the primary establishment of legal unit 89 (Statistics Norway o), yet the Links tree shows no primary. The primary is establishment 86 (Statbus Norway O), primary_for_legal_unit from 2023-01-01 but born 2024-11-01, so in 2023 it does not exist and is rightly left out of the tree (and, since f2gx3m, out of the totals).

## Principle
Report what the data says, do not repair it silently. A primary flag on a unit that does not exist in the period is a data inconsistency to surface, like the quality checks; which unit should be primary is the user's choice (Set as primary, 2gpcs7).

## Details
Read-only on jo 2026-11-26 (tmp/f2gx3m/jo-unit.out): establishment 86 born 2024-11-01, valid 2023-01-01..infinity, primary_for_legal_unit true; establishment 89 born 2023-11-01, primary false. On master since 2026-11-27 (f2gx3m) a row born in a later year than its valid_from is refused at import, so 86's 2023 row would not load again; existing data keeps it. Options for the owner: (a) a quality check 'legal unit without an existing primary establishment' listing such legal unit periods; (b) the unit page saying 'the primary establishment, Statbus Norway O, does not exist in this period' instead of offering only Set as primary; (c) both. Owner screenshot paste-1537.png was attached to z2qt08 by mistake (same image as f2gx3m's paste-1540.png).

## Depends on

## Acceptance
- [ ] On a copy of jo's data at Frame 2023, Drill Down Norway AS's page says which establishment is primary and that it does not exist in 2023
- [ ] [Owner] chooses how the inconsistency is surfaced (quality check, page notice, or both); answer recorded here

## Notes
