---
id: jbc5bs
title: "Coordinates are named latitude, longitude, altitude; no postal coordinates"
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
Coordinates are named latitude, longitude and altitude everywhere, for regions and units, and postal addresses carry none.

## Purpose
Owner 2026-11-23 (his boss's decision): the center_ and physical_ prefixes over-communicate, and a postal address needs no coordinates; one plain name lets map code and API users read one field.

## Principle
One forward migration with no lasting aliases; postal coordinate columns are dropped, not renamed; an outline, if it ever comes, is a geometry of its own (e.g. boundary).

## Details
Regions: public.region center_latitude/center_longitude/center_altitude and their CHECK constraints, public.region_upload, admin.region_upload_upsert. Units: statistical_unit physical_latitude/longitude/altitude -> latitude/longitude/altitude; postal_latitude/longitude/altitude dropped (0 units carry them; location already forbids coordinates on postal rows); the timeline views (timeline_legal_unit_def, timeline_establishment_def, timeline_enterprise_def, timeline_power_group_def, statistical_unit_def, timeline_enterprise) and 15 doc/db views/functions naming them; import steps physical_location (physical_latitude/_raw, ...) and postal_location (its coordinate columns dropped) and the import definitions using them. App: search export (export-sql.ts, xlsx-stream.ts), unit-history-table.tsx, the hierarchy types, the map work on feat/units-on-map (z2qt08). Docs: data-model.md, import-system.md, integration/api-reference.md. Tests: test/sql/100_regions_with__itudes and expected outputs printing these columns. Others' tasks to align: kvbebr (decided here), Rabbit's 5yxn4w, s2wvf7, dbmsxy, 8p81cc, r39dqb (Erik's files use physical_latitude headers).

## Depends on
- z2qt08

## Acceptance
- [ ] [Owner] Decides whether region upload files with the old center_* headers are refused with a message naming the new headers, or accepted for one release; recorded here
- [ ] public.region, region_upload and the upload's upsert use latitude, longitude, altitude; the fast SQL suite passes with regenerated doc/db and app types
- [ ] Uploading a region file with the new headers stores each region's point; a SQL test asserts the stored values

## Notes

2026-11-23 10:47 widened from regions only to units too, on the owner's word: drop physical_ as well, and drop postal coordinates altogether (no coordinates for a postal address). kvbebr check 1 records the decision.
