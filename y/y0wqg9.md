---
id: y0wqg9
title: "Timeline splits at birth and death recalculate the primary establishment"
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
An establishment born inside a frame is its legal unit's primary from its birth date, and none before it.

## Purpose
jo.statbus.org Frame 2023: legal unit Statistics Norway o's primary establishment, Statbus Norway O (86), is primary from 2023-01-01 but born 2024-11-01, so in 2023 the tree shows no primary. Owner 2026-11-27 19:40: a consistency error, not a quality check or a page notice. The wrong case (born in a later year than valid_from) is refused at import (test 418); the right case, born inside the frame, must give the primary from the birth date.

## Principle
Counting and the primary follow the same existence: a unit that does not exist in a stretch counts nothing and is primary for nothing there. Test first: a SQL test shows the primary from the birth date and none before it.

## Details
f2gx3m (master 866d8e3fc) splits timelines at birth_date and death_date (unit_counts_in, timepoints). primary_for_legal_unit is stored on establishment rows by their validity. Assert per stretch, for a legal unit valid 2023-01-01..inf with an establishment primary_for_legal_unit valid 2023-01-01..inf but born 2023-11-01: before 2023-11-01 the legal unit has no existing primary establishment (statistical_unit_hierarchy and the legal unit's timeline), from 2023-11-01 that establishment is primary. Same for a death date: primary until death, none after.

## Depends on

## Acceptance
- [ ] On a copy of jo's data at Frame 2023, Drill Down Norway AS's page says which establishment is primary and that it does not exist in 2023
- [ ] [Owner] chooses how the inconsistency is surfaced (quality check, page notice, or both); answer recorded here

## Notes

2026-11-27 19:39 owner showed both frames on jo (tab 135). Live frame (2026): enterprise Statistics Norway O → legal unit Statistics Norway O (primary, *) → establishments Statbus Norway O (86, primary, *) and Drill Up Norway AS (89); Σ 29 = 25 + 2 + 2, all visible. Frame 2023: the enterprise has its primary legal unit, but the legal unit shows no primary establishment: 86 is the primary in the data but not born until 2024-11-01, so it is absent; only 89 (not primary) shows, and jo's v2026.11.6 Σ 25 still counts 86's 2 (fixed on master by f2gx3m). Owner: the legal unit should have had a primary establishment in 2023, as the enterprise has a primary legal unit.
