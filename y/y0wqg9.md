---
id: y0wqg9
title: "The import picks the earliest-born establishment as primary, not the first row"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzzzzy"
created: 2026-11-27
updated: 2026-11-27
---

## Goal
Within one import job, a legal unit's primary is its earliest-existing establishment, whatever the row order.

## Purpose
jo.statbus.org Frame 2023: legal unit 89's primary is establishment 86 (born 2024-11-01) while establishment 89 (born 2023-11-01) exists from November 2023, so 2023 shows no primary. The import's holistic step analyse_link_establishment_to_legal_unit ranks candidates by row order in the file (original_data_table_row_id), not by when they exist.

## Principle
Owner 2026-11-27 20:33: a primary, once stored, is settled. The import picks one only where none exists, and then by existence: the earliest birth (or valid_from) wins. Changing a stored primary is a separate step, by hand (Set as primary, 2f4c0z) or in bulk by the workflow 2gpcs7 (xhxnsy), never by a later import. No per-stretch recalculation and no row splits: the earliest-born establishment is primary from its rows' start, and before its birth nothing exists to show.

## Details
Checked 2026-11-27: link_establishment_to_legal_unit is holistic (is_holistic = true), so it sees every row of the job at once and batch boundaries do not matter. Its candidates exclude rows whose validity overlaps an already-stored primary (steps 8-11), which is the settled-primary rule the owner wants. Only the rank inside a time island is wrong: ROW_NUMBER() OVER (PARTITION BY resolved_lu_id, island_id ORDER BY original_data_table_row_id). Rank by unit_existence_from(valid_from, birth_date), then establishment id. analyse_establishment (batched, priority 20) only tidies duplicates the holistic step left; check it keeps the holistic pick. The same rule applies to a legal unit as its enterprise's primary (analyse_legal_unit / enterprise link steps): check whether they rank by row order too. The wrong case (birth in a later year than valid_from) is refused at import (test 418).

## Depends on

## Acceptance
- [ ] ~~On a copy of jo's data at Frame 2023, Drill Down Norway AS's page says which establishment is primary and that it does not exist in 2023~~ (not relevant: superseded: owner 20:33, the import ranks by existence; no page notice, rabbit, 2026-11-27)
- [ ] ~~[Owner] chooses how the inconsistency is surfaced (quality check, page notice, or both); answer recorded here~~ (not relevant: decided 20:03-20:33: consistency at import, not a quality check or notice, rabbit, 2026-11-27)
- [ ] A SQL test imports one legal unit with two establishments valid from the same day, the later-born one first in the file: the earlier-born one is primary, red on master 78c95b358 and green after
- [ ] A SQL test: an import does not change a legal unit's stored primary when it brings an earlier-born establishment
- [ ] The same ranking holds for a legal unit as its enterprise's primary, asserted in the same test

## Notes

2026-11-27 19:39 owner showed both frames on jo (tab 135). Live frame (2026): enterprise Statistics Norway O → legal unit Statistics Norway O (primary, *) → establishments Statbus Norway O (86, primary, *) and Drill Up Norway AS (89); Σ 29 = 25 + 2 + 2, all visible. Frame 2023: the enterprise has its primary legal unit, but the legal unit shows no primary establishment: 86 is the primary in the data but not born until 2024-11-01, so it is absent; only 89 (not primary) shows, and jo's v2026.11.6 Σ 25 still counts 86's 2 (fixed on master by f2gx3m). Owner: the legal unit should have had a primary establishment in 2023, as the enterprise has a primary legal unit.

2026-11-27 20:03 owner: the primary is chosen once, at import analysis, among the legal unit's establishments by existence: the one born first (existing earliest) is primary; a later-born one never becomes primary through birth alone, so the stored flag needs no per-stretch change and rows need no split. Example: A and B both valid from 2023-01-01, A born 2023-03-01, B born 2023-06-01 -> A is primary; before 2023-03-01 nothing exists, so there is no primary to show. On jo this would have chosen 89 (born 2023-11-01) over 86 (born 2024-11-01). Today the analysis ranks candidates by validity overlap and row order (analyse_link_establishment_to_legal_unit steps 8-11), not by birth date.

2026-11-27 20:43 owner: option (a). Existing wrong primaries stay; the workflow 2gpcs7 settles them per period, including legal units with no existing primary (noted there). This task only fixes the import's ranking for new primaries, test first.
