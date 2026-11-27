---
id: 5necw2
title: "Regions say whether they are a place, no place, or unknown"
state: todo
type: feature
priority: ""
assignee: []
labels: []
group: ""
rank: "00000000000n"
created: 2026-11-23
updated: 2026-11-23
stage: "ready"
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

## Questions
- 2026-11-27T14:47 question 1 by hibiscus to jhf:
  The United Nations country (UN, a demo installation's country) has its centre at 0,0 in dbseed/country/country_centres.csv, which puts it in the Gulf of Guinea on the world map. Should it have no centre, so it is listed as not on the map, as a region that is no place would be?
  answered 2026-11-27T15:37 by jhf:
    Why don't we put it at the UN headquarters?

## Notes


2026-11-27 14:37 (hibiscus) Owner's answer to the UN centre question (relayed by rabbit): put the United Nations at UN Headquarters in New York (about 40.7489, -73.9680), not at 0,0 and not without a centre. Hibiscus does it: dbseed/country/country_centres.csv plus a forward migration for installed data, test 408 updated.


2026-11-27 16:18 (hibiscus) UN centre done as the owner answered: e52d18107 puts UN at 40.7489, -73.9680 (seed file + forward migration 20261127161436, data only). Test 408 red (0,0, tmp/5necw2-408-red.log) then green (tmp/5necw2-408-green.log); migrate down gives 0,0, up gives HQ. The task's region-kind work (checks 1-3) is unchanged and still open.
## History
- 2026-11-27T14:47 todo -> todo/design (ask)
- 2026-11-27T15:37 answered design, by jhf, for hibiscus (todo/design -> todo/ready):
  > The United Nations country (UN, a demo installation's country) has its centre at 0,0 in dbseed/country/country_centres.csv, which puts it in the Gulf of Guinea on the world map. Should it have no centre, so it is listed as not on the map, as a region that is no place would be?
  Why don't we put it at the UN headquarters?
- 2026-11-27T15:37 answer 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-27T15:37 answer 1 acknowledged by rabbit
- 2026-11-27T17:18 hibiscus read the answer: hug task note 5necw2 "2026-11-27 16:18 (hibiscus) UN centre done as the owner answered: e52d18107 puts UN at 40.7489, -73.9680 (seed file + f…"
- 2026-11-27T17:18 outcome 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
