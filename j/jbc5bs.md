---
id: jbc5bs
title: "Coordinates are named latitude, longitude, altitude; no postal coordinates"
state: "doing"
type: feature
priority: ""
assignee: ["ox"]
labels: ["maps"]
group: ""
rank: "zzzzzzzzh"
created: 2026-11-23
updated: 2026-11-23
stage: "active"
doing_since: "2026-11-26T21:49"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_b"
---

## Goal
Coordinates are named latitude, longitude and altitude everywhere, for regions and units, and postal addresses carry none.

## Purpose
Owner 2026-11-23 and 2026-11-26: coordinates exist only for physical locations, so the physical_ prefix names no real distinction and center_ over-communicates; postal addresses need none. One set of names lets map code and API users read the same fields everywhere.

## Principle
One forward migration with no lasting aliases; postal coordinate columns are dropped, not renamed; an outline, if it ever comes, is a geometry of its own (e.g. boundary).

## Details
Regions: public.region center_latitude/center_longitude/center_altitude and their CHECK constraints, public.region_upload, admin.region_upload_upsert. Units: statistical_unit physical_latitude/longitude/altitude -> latitude/longitude/altitude; postal_latitude/longitude/altitude dropped (0 units carry them; location already forbids coordinates on postal rows); the timeline views (timeline_legal_unit_def, timeline_establishment_def, timeline_enterprise_def, timeline_power_group_def, statistical_unit_def, timeline_enterprise) and 15 doc/db views/functions naming them; import steps physical_location (physical_latitude/_raw, ...) and postal_location (its coordinate columns dropped) and the import definitions using them. App: search export (export-sql.ts, xlsx-stream.ts), unit-history-table.tsx, the hierarchy types, the map work on feat/units-on-map (z2qt08). Docs: data-model.md, import-system.md, integration/api-reference.md. Tests: test/sql/100_regions_with__itudes and expected outputs printing these columns. Others' tasks to align: kvbebr (decided here), Rabbit's 5yxn4w, s2wvf7, dbmsxy, 8p81cc, r39dqb (Erik's files use physical_latitude headers).

## Depends on

## Acceptance
- [x] [Owner] Decides whether region upload files with the old center_* headers are refused with a message naming the new headers, or accepted for one release; recorded here
- [x] public.region, region_upload and the upload's upsert use latitude, longitude, altitude; the fast SQL suite passes with regenerated doc/db and app types
- [x] Uploading a region file with the new headers stores each region's point; a SQL test asserts the stored values
- [x] statistical_unit and the timeline views carry latitude, longitude and altitude (no physical_ prefix) and no postal coordinate columns; the fast SQL suite passes with regenerated doc/db and app types
- [ ] The import's physical location step takes latitude, longitude, altitude; the postal location step takes no coordinates; an import of a unit with a point stores it, a SQL test asserts it
- [ ] The app (search export, unit history, maps) and docs (data-model, import-system, API reference) use the new names: rg finds none of the old coordinate names outside migrations
- [ ] An independent reviewer (neither the implementer nor hibiscus) checked every hunk of git diff origin/master -- test/expected against the rename and its migration, and found no change beyond the rename (no changed value, row count, order, or appearing or vanishing error); its findings and their fixes are recorded in this task
- [ ] Region uploads with center_* headers and unit imports with physical_* coordinate headers are refused with a message naming latitude, longitude, altitude; a SQL test asserts it
- [ ] A region file or a unit import file with old coordinate headers (center_* or physical_* latitude/longitude/altitude) is refused with a message naming the new headers latitude, longitude, altitude; a SQL test asserts both refusals

## Questions
- 2026-11-23T11:47 question 1 by hibiscus to jhf:
  Old headers in upload files: region files with center_latitude/longitude/altitude and unit files with physical_latitude/longitude/altitude (Erik's coordinate files use those) stop matching after the rename. Refuse them with a message naming the new headers, or accept them for one release before refusing?
  answered 2026-11-26T21:42 by hibiscus:
    Refuse old headers with a message naming the new ones; a clean cut (owner 2026-11-26 20:41).

## Notes

2026-11-23 10:47 widened from regions only to units too, on the owner's word: drop physical_ as well, and drop postal coordinates altogether (no coordinates for a postal address). kvbebr check 1 records the decision.


check 1: Owner 2026-11-26 20:41: refuse old headers (center_* in region files, physical_latitude/longitude/altitude in unit files) with a message naming the new ones; a clean cut, no one-release grace.
Answer delivered to rabbit as board coordinator; Hibiscus asked it and does the work (map, z2qt08).


Owner 2026-11-26 20:46: why the prefix goes: positions are recorded only for physical locations (location's coordinates apply to type physical; postal carries none), so physical_latitude names a distinction that does not exist, and postal_* coordinate columns go. Old headers refused (check 1). The result matches Erik's actual request in PR #327: one set of names in statistical_unit, location and the hierarchy RPC.
2026-11-26 20:48 delegated by hibiscus to agent ox in ~/ssb/statbus_b (slot b, demo data), branch feat/coordinates-named-latitude, together with kvbebr checks 2-3. Order agreed with the owner: feat/units-on-map lands on master first; ox then rebases and renames the map branch's new code too (regions pages, map, upload page, test 414, migration 20261126201306). PR #327 closed with the owner-approved reply.
Dep on z2qt08 removed to start building on master per owner-agreed ORDER: branch feat/coordinates-named-latitude is built now, rebased onto master after z2qt08 (feat/units-on-map) lands, and merged only after that.
Owner 2026-11-26 20:50: the expected-output changes of this rename are too large for the implementer or the coordinator to review alone; an independent reviewer agent checks every hunk before merge (new acceptance check). ox told; ox lists each changed .out with its reason in tmp/expected-review.md, hibiscus starts the reviewer.
Check 6's sweep for old names excludes the refusal code and its tests, which must name the old headers to detect them.
Slow tests 402 and 404 drift on master, separately from this rename (expected files from 2026-11-23, before ca6dk5 and later RLS changes): 402 shows WITH CHECK (true) vs (edit_by_user_id = auth.uid()), analytics completed 37 vs 36, a sector added_count key; 404 shows the enterprise/establishment employees aggregate (count 8583 -> 5686, sum 590893 -> 391133). On this branch only the rename hunks of 402/404 were taken into the expected files (tmp/coords/take_rename_hunks.py); the drift hunks keep master's expected text and still fail, and need their own ticket.
check 2: commit 3bf2dbc6f, ./dev.sh test fast: All 146 tests passed (tmp/test-fast.log), doc/db and database.types.ts regenerated
check 3: test/sql/415: region file with latitude,longitude,altitude stores 59.913868/10.752245/23.0 (and a point without altitude)
check 4: commit 3bf2dbc6f, ./dev.sh test fast: All 146 tests passed (tmp/test-fast.log), doc/db and database.types.ts regenerated; information_schema has no physical_/postal_/center_ coordinate columns after migrate up
## History
- 2026-11-23T11:47 todo -> todo/depends (ask)
- 2026-11-26T21:42 answered design, by hibiscus, for hibiscus (todo/depends -> todo/depends):
  > Old headers in upload files: region files with center_latitude/longitude/altitude and unit files with physical_latitude/longitude/altitude (Erik's coordinate files use those) stop matching after the rename. Refuse them with a message naming the new headers, or accept them for one release before refusing?
  Refuse old headers with a message naming the new ones; a clean cut (owner 2026-11-26 20:41).
- 2026-11-26T21:42 answer 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-26T21:42 answer 1 acknowledged by rabbit
- 2026-11-26T21:49 todo/ready -> doing/active (take)
