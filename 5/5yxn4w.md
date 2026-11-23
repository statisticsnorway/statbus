---
id: 5yxn4w
title: "Regions show and upload their centre coordinates under Advanced"
state: todo
type: feature
priority: "medium"
assignee: []
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

## Acceptance
- [ ] /regions shows code, name and level; with Advanced on it also shows centre latitude, longitude and altitude; a Playwright test toggles it and asserts the columns and one region's values
- [ ] The region upload page shows the plain columns in its instructions and example, and the centre columns under Advanced; a Playwright test asserts both views
- [ ] Uploading a region file with centre coordinates stores them; a SQL test asserts the stored values

## Notes

2026-11-23 (Rabbit) From hibiscus: z2qt08's branch feat/units-on-map already adds always-shown Latitude/Longitude columns and a Map button to /regions (app/src/app/regions/region-table.tsx, page.tsx). Build this task on top of that region-table.tsx after the owner approves z2qt08 phase 1 and it lands; this task moves the coordinate columns under Advanced and adds altitude. Hibiscus does not touch the upload page.
