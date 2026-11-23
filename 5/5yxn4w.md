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
---

## Goal
The regions page, the region upload and its instructions show code, name and level by default, and the centre coordinates under Advanced.

## Purpose
Owner 2026-11-22: show region lat+lon on /regions, with the same simple/advanced split for plain regions and their extras, for display, upload and upload instructions. Regions already hold center_latitude, center_longitude and center_altitude, but the page does not show them.

## Principle
One switch per screen: simple shows what every country needs, Advanced adds the optional columns; the upload accepts the optional columns either way.

## Details
public.region: path, level, code, name, center_latitude numeric(9,6), center_longitude numeric(9,6), center_altitude numeric(6,1). Pages: app/src/app/regions (region-table.tsx), app/src/app/getting-started/upload-regions. Norway's coordinates come from postcodes (see the Norwegian region coordinates task); a map is z2qt08.

## Depends on

- z2qt08
## Acceptance
- [ ] /regions shows code, name and level; with Advanced on it also shows centre latitude, longitude and altitude; a Playwright test toggles it and asserts the columns and one region's values
- [ ] The region upload page shows the plain columns in its instructions and example, and the centre columns under Advanced; a Playwright test asserts both views
- [ ] Uploading a region file with centre coordinates stores them; a SQL test asserts the stored values

## Notes

2026-11-23 (Rabbit) From hibiscus: z2qt08's branch feat/units-on-map already adds always-shown Latitude/Longitude columns and a Map button to /regions (app/src/app/regions/region-table.tsx, page.tsx). Build this task on top of that region-table.tsx after the owner approves z2qt08 phase 1 and it lands; this task moves the coordinate columns under Advanced and adds altitude. Hibiscus does not touch the upload page.

2026-11-23 (owner) Handed to hibiscus: the region coordinates under Advanced are done together with the map work (z2qt08), on his branch's region-table.tsx; the owner reviews the map things with him.

2026-11-23 (hibiscus) Taken with z2qt08. The coordinate columns move under Advanced in the branch's region-table.tsx (worktree /Users/jhf/ssb/statbus-map), and altitude is added. jbc5bs will later rename center_latitude/longitude/altitude to latitude/longitude/altitude; this task keeps today's column names.

2026-11-23 (hibiscus) This replaces Rabbit's earlier note that hibiscus does not touch the upload page. The owner handed the whole task to hibiscus, so hibiscus also does the upload page and its instructions (check 2).

2026-11-23 (hibiscus) Owner: drop the 'Without coordinates' filter (empty columns confused), and add a way for an admin to look up a missing region's centre. Done on branch feat/units-on-map, f3637eb36: a region without a centre shows 'Not set'; an admin gets 'Place on map', which searches OpenStreetMap (Nominatim) by the region's name in the installation's country, puts the pin on the chosen match, and lets the admin check and Save it (region.center_latitude/longitude). Observed: Bjørnøya naturreservat (21.21) finds Bear Island Nature Reserve at 74.424213, 19.010207, with the pin on the island. Save was not pressed on the owner's data.
