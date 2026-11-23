---
id: s2wvf7
title: "Norwegian regions get centre coordinates from postcodes"
state: todo
type: feature
priority: "low"
assignee: []
labels: []
group: ""
rank: "zzzzzzzx"
created: 2026-11-23
updated: 2026-11-23
---

## Goal
Each Norwegian region (fylke, kommune) has a centre latitude and longitude derived from the postcodes inside it.

## Purpose
Owner 2026-11-22: lat+lon for Norwegian regions, using postnummer. Erik (Slack 2026-11-11): in Norway coordinates are per postcode, so the region load must accept lat+lon.

## Principle
Derived from Bring's open postcode register (NLOD), reproducibly by a script in samples/norway/regions; the result is an ordinary region file the upload accepts.

## Details
Bring publishes the postcode register (TAB, Latin-1, weekly; https://www.bring.no/postnummerregister-ansi.txt) with kommunenummer per postcode, and its guide lists a 'Postnummer med koordinater' file. A fylke is the first two digits of kommunenummer. Centre = mean of the postcode points in the region (the owner may prefer another rule). Columns: 5yxn4w; 2026 regions: 4pj9bz.

## Depends on
- 4pj9bz

## Acceptance
- [ ] [Owner] Agrees the centre rule (mean of postcode points or another) and the postcode file to use; recorded here
- [ ] The script writes a 2026 region file with centre coordinates for every fylke and kommune; uploading it on a scratch database stores a centre for every region, and Oslo's lies inside Oslo; the counts are recorded here
- [ ] No kommune keeps its county's exact centre after the derived file is loaded (e.g. Haugesund 11.06 no longer at 59.407159, 5.278156); a SQL check over the loaded regions returns no kommune whose centre equals its fylke's

## Notes

2026-11-23 (Rabbit) From hibiscus: on the local Norway copy Haugesund (11.06) has Rogaland's exact centre (59.407159, 5.278156); derived centres must replace such copied county centres, not keep them. Maps read region.center_latitude/longitude, so better data shows with no map change.

2026-11-23 (Rabbit) Coordinate names: jbc5bs (hibiscus, after z2qt08) renames them to latitude, longitude, altitude everywhere (regions drop center_, units drop physical_, postal locations carry none). Use today's names until jbc5bs lands; whichever lands later uses the new names.
