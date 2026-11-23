---
id: 5yxn4w
title: "Regions show and upload their centre coordinates under Advanced"
state: todo
type: feature
priority: "medium"
assignee: ["hibiscus"]
labels: []
group: ""
rank: "zzzzzzzq"
created: 2026-11-23
updated: 2026-11-23
design_question: "Checks 1, 2, 4 and 5 ask for Playwright tests, but the app has no Playwright suite (doc/design/units-on-map.md says starting one is your decision, also asked by 5nq78t check 2). Should I start a minimal Playwright suite on this branch for /regions (filter counts; Place on map saving a region's centre against a test database), or should these checks be met by driven-browser runs recorded in tmp/hug plus jest and SQL tests?"
design_for: "jhf"
design_since: "2026-11-23T13:58"
design_asked_by: "hibiscus"
stage: "depends"
---

## Goal
Regions show and upload centre latitude, longitude and altitude, and an admin places a region that lacks one.

## Purpose
Regions hold centre coordinates, but people cannot see them on /regions or fill in a missing one, and the upload instructions do not say how to supply them.

## Principle
One switch per screen: simple shows what every country needs, Advanced adds the optional columns; the upload accepts the optional columns either way.

## Details
Owner 2026-11-22: show region latitude and longitude on /regions, with the same simple/Advanced split for display, upload and upload instructions. public.region already has center_latitude, center_longitude and center_altitude. Pages: app/src/app/regions (region-table.tsx, region-table-filters.tsx, use-region.ts), app/src/app/getting-started/upload-regions. Simple view: code, name, level; Advanced adds centre latitude, longitude and altitude. Owner 2026-11-23: the list filters All / With / Without coordinates, and a region without a centre gets 'Place on map' for admins (OpenStreetMap Nominatim name search limited to the installation's country; pin on the chosen match; Save writes the centre). Built on branch feat/units-on-map with z2qt08: f3637eb36, 14fd35fff. jbc5bs later renames the columns to latitude, longitude, altitude. Codes that are no place or 'not stated' are 5necw2.

## Depends on

- z2qt08
## Acceptance
- [ ] /regions shows code, name and level; with Advanced on it also shows centre latitude, longitude and altitude; a Playwright test toggles it and asserts the columns and one region's values
- [ ] The region upload page shows the plain columns in its instructions and example, and the centre columns under Advanced; a Playwright test asserts both views
- [ ] Uploading a region file with centre coordinates stores them; a SQL test asserts the stored values
- [ ] /regions filters All, With coordinates and Without coordinates; a Playwright test asserts each count against the region table
- [ ] An admin's Place on map for a region without a centre searches OpenStreetMap by its name, puts the pin on the chosen match, and Save stores the region's centre; a Playwright test saves one and reads it back

## Questions
- 2026-11-23T13:58 question 1 by hibiscus to jhf:
  Checks 1, 2, 4 and 5 ask for Playwright tests, but the app has no Playwright suite (doc/design/units-on-map.md says starting one is your decision, also asked by 5nq78t check 2). Should I start a minimal Playwright suite on this branch for /regions (filter counts; Place on map saving a region's centre against a test database), or should these checks be met by driven-browser runs recorded in tmp/hug plus jest and SQL tests?

## Notes

2026-11-23 (Rabbit) From hibiscus: z2qt08's branch feat/units-on-map already adds always-shown Latitude/Longitude columns and a Map button to /regions (app/src/app/regions/region-table.tsx, page.tsx). Build this task on top of that region-table.tsx after the owner approves z2qt08 phase 1 and it lands; this task moves the coordinate columns under Advanced and adds altitude. Hibiscus does not touch the upload page.

2026-11-23 (owner) Handed to hibiscus: the region coordinates under Advanced are done together with the map work (z2qt08), on his branch's region-table.tsx; the owner reviews the map things with him.

2026-11-23 (hibiscus) Taken with z2qt08. The coordinate columns move under Advanced in the branch's region-table.tsx (worktree /Users/jhf/ssb/statbus-map), and altitude is added. jbc5bs will later rename center_latitude/longitude/altitude to latitude/longitude/altitude; this task keeps today's column names.

2026-11-23 (hibiscus) This replaces Rabbit's earlier note that hibiscus does not touch the upload page. The owner handed the whole task to hibiscus, so hibiscus also does the upload page and its instructions (check 2).

2026-11-23 (hibiscus) Owner: drop the 'Without coordinates' filter (empty columns confused), and add a way for an admin to look up a missing region's centre. Done on branch feat/units-on-map, f3637eb36: a region without a centre shows 'Not set'; an admin gets 'Place on map', which searches OpenStreetMap (Nominatim) by the region's name in the installation's country, puts the pin on the chosen match, and lets the admin check and Save it (region.center_latitude/longitude). Observed: Bjørnøya naturreservat (21.21) finds Bear Island Nature Reserve at 74.424213, 19.010207, with the pin on the island. Save was not pressed on the owner's data.

2026-11-23 (hibiscus) Correction to the earlier note: the owner first dropped the single 'Without coordinates' checkbox (empty columns confused him), then asked at 12:23 for a list filter showing regions with and without coordinates. That is check 4's three-way filter (All / With / Without), built in 14fd35fff. Place on map searches only within the installation's country (settings.country_id).


## History
- 2026-11-23T13:58 todo -> todo/depends (ask)
