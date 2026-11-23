---
id: 5necw2
title: "Regions say whether they are a place, no place, or unknown"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "zzzzzzzzv"
created: 2026-11-23
updated: 2026-11-23
---

## Goal
Each region records whether it is a place, a code with no place, or 'not stated'.

## Purpose
Official region lists hold codes that are not places (Norway: airspace, continental shelf, abroad, sea areas, extra county) and a 'not stated' code (99 Uoppgitt). Today the list offers Place on map for them, and a unit on 'not stated' counts as having a region, so the Units Missing Region card misses it.

## Principle
The region upload file says what each code is; nothing is hard-coded per country. The official file is kept as published.

## Details
Owner 2026-11-23 (review of z2qt08/5yxn4w): keep the official file; not in this iteration. Proposal: a region kind column (place, no_place, unknown) in public.region and the region upload. no_place shows 'No place' in the coordinate column and gets no Place on map; unknown counts as a missing region in data quality (missing-region-card.tsx counts physical_region_path IS NULL today) and on the Regions map. Norway today: 23, 24, 25, 26, 27, 28 have no centre and 0 units; 99 and 99.99 Uoppgitt have 0 units (tmp/z2qt08-placeholder-regions.sql).

## Depends on

- 5yxn4w
## Acceptance
- [ ] The region upload accepts a kind per region and stores it; a SQL test asserts place, no_place and unknown rows
- [ ] /regions shows 'No place' for a no_place region and offers Place on map only for a place without a centre; a Playwright test asserts both
- [ ] A unit on an unknown region counts in Units Missing Region and in the Regions map's units without a region; a test asserts the count

## Notes
