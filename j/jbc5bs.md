---
id: jbc5bs
title: "Region coordinates are named latitude, longitude, altitude, without center_"
state: todo
type: feature
priority: ""
assignee: []
labels: ["maps"]
group: ""
rank: "zzzzzzzzh"
created: 2026-11-23
updated: 2026-11-23
---

## Goal
A region's point is stored, uploaded and returned as latitude, longitude and altitude, without the center_ prefix.

## Purpose
Owner 2026-11-23: center_ over-communicates; a region's single point can only be where it is, and an outline would be a geometry of its own, not latitude/longitude.

## Principle
One forward migration renames the columns, the region_upload view and its upsert; no lasting alias. Units keep physical_ and postal_ prefixes, which tell two places apart.

## Details
Touches public.region (center_latitude, center_longitude, center_altitude and its CHECK constraints), public.region_upload and admin.region_upload_upsert, doc/db, app types, test/sql/100_regions_with__itudes and the expected outputs that print region columns (002, 107, 109, 110, 111, 115), doc/data-model.md, the region list and map on feat/units-on-map (z2qt08), and Rabbit's 5yxn4w and s2wvf7. Region upload files with center_* headers stop matching.

## Depends on
- z2qt08

## Acceptance
- [ ] [Owner] Decides whether region upload files with the old center_* headers are refused with a message naming the new headers, or accepted for one release; recorded here
- [ ] public.region, region_upload and the upload's upsert use latitude, longitude, altitude; the fast SQL suite passes with regenerated doc/db and app types
- [ ] Uploading a region file with the new headers stores each region's point; a SQL test asserts the stored values

## Notes
