---
id: jbc5bs
title: "Coordinates are named latitude, longitude, altitude; no postal coordinates"
state: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: ["maps"]
group: ""
rank: "zzzzzzzzh"
created: 2026-11-23
updated: 2026-11-23
stage: "waiting"
doing_since: "2026-11-26T21:49"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_b"
waiting_on: "Hibiscus implements the rename; owner answered: refuse the old coordinate headers"
waiting_since: "2026-11-27T01:11"
waiting_asked_by: "rabbit"
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
- [x] The import's physical location step takes latitude, longitude, altitude; the postal location step takes no coordinates; an import of a unit with a point stores it, a SQL test asserts it
- [x] The app (search export, unit history, maps) and docs (data-model, import-system, API reference) use the new names: rg finds none of the old coordinate names outside migrations
- [x] An independent reviewer (neither the implementer nor hibiscus) checked every hunk of git diff origin/master -- test/expected against the rename and its migration, and found no change beyond the rename (no changed value, row count, order, or appearing or vanishing error); its findings and their fixes are recorded in this task
- [x] Region uploads with center_* headers and unit imports with physical_* coordinate headers are refused with a message naming latitude, longitude, altitude; a SQL test asserts it
- [x] A region file or a unit import file with old coordinate headers (center_* or physical_* latitude/longitude/altitude) is refused with a message naming the new headers latitude, longitude, altitude; a SQL test asserts both refusals
- [x] Old coordinate headers meet the ordinary handling of an unknown column, with no code naming them: a region file with center_* is refused and stores nothing, a unit import keeps physical_* as ignored columns and stores no point from them; test/sql/419 asserts both

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
check 5: test/sql/415: legal unit import with latitude/longitude/altitude -> location physical row and statistical_unit legal_unit+enterprise carry 59.913868/10.752245/23.0; postal_location step has no coordinate data columns
check 6: rg outside migrations/tmp finds old names only in the refusal code, its tests (415, upload-csv-check), its doc/db page, the historical backlog doc, and 402/404 expected hunks of pre-existing drift
check 8: test/sql/415: region_upload with center_latitude/longitude/altitude refused (column does not exist; 0 regions stored), and the upload page answers 'retired coordinate columns ... Name them latitude, longitude, altitude' (upload-csv-check.test.ts); unit upload with physical_* refused by admin.import_job_keep_ignored_columns: 'The file has retired coordinate columns: physical_altitude, physical_latitude, physical_longitude. Name them latitude, longitude, altitude'
check 9: test/sql/415: region_upload with center_latitude/longitude/altitude refused (column does not exist; 0 regions stored), and the upload page answers 'retired coordinate columns ... Name them latitude, longitude, altitude' (upload-csv-check.test.ts); unit upload with physical_* refused by admin.import_job_keep_ignored_columns: 'The file has retired coordinate columns: physical_altitude, physical_latitude, physical_longitude. Name them latitude, longitude, altitude'
Checks 8 and 9 say the same thing (added twice, by me and by hibiscus); both ticked with one piece of evidence.
check 7: Independent read-only reviewer rat (neither ox nor hibiscus), 2026-11-26 23:21, report tmp/jbc5bs-expected-review-findings.md (statbus_test): every hunk of git diff origin/master...3bf2dbc6f -- test/expected normalised master->branch (postal lines removed, rename applied, whitespace collapsed) and compared residuals as multisets. Every hunk is the rename: key and column renames, postal coordinates dropped (108: 140->134 rows = the 6 postal columns; 303: 6 postal definition objects x2), jsonb key reorder and table border widths. No value, NULL, row-count or error change; no non-null postal data lost. One finding: 415 lines 38-39, a region file with center_* headers is refused by PostgreSQL's generic 'column center_latitude of relation region_upload does not exist', not a message naming latitude, longitude, altitude, though the echo says it does (check 8 and 9 claim it). To fix before merge.
2026-11-26 23:22 hibiscus: check 7's finding reopens the claim in checks 8 and 9 for region files: the center_* refusal is the generic missing-column error. Fix options for ox: keep center_* as columns on public.region_upload that raise 'Name them latitude, longitude, altitude' when given (as the physical_* import path does), or correct the 415 echo and checks 8/9 to say the generic error. Owner decides.
2026-11-27 00:10 owner on check 7's finding: a hard cut, as decided before. A region file with center_* headers gets PostgreSQL's generic 'column ... does not exist'; no transitional message. To correct: 415's echo ('naming the new headers') and the wording of checks 8 and 9 for region files. The import path's existing message for physical_* stays as it is.
2026-11-27 00:11 hibiscus to ox (ox's session not live, so here): check 7 is ticked, report /Users/jhf/ssb/statbus_test/tmp/jbc5bs-expected-review-findings.md. Please (1) correct 415's echo text for the center_* case to say it is refused by the missing column; (2) reword checks 8 and 9 for region files the same way (not 'a message naming latitude, longitude, altitude'). Do not rebase yet: feat/units-on-map lands on master first; it adds center_* code (Regions map, upload page, download menu, api-reference.md) and migration 20261126215254, so your migration needs a later timestamp and must also rename in admin.region_upload_upsert and worker.log_region_change as 20261126215254 defines them.
2026-11-27 00:11 owner: hard cut, the less hard coding the better, a clean code ship. So the rename carries no code for the old names: remove the retired-header refusal from admin.import_job_keep_ignored_columns (the physical_* RAISE) and RETIRED_COORDINATE_COLUMN with its message from app/src/app/getting-started/upload-csv-check.ts (and its test). A file with old headers is refused the ordinary way, as any unknown column is. Checks 8 and 9 asked for that refusal message; reword them to: old headers are refused as unknown columns, a SQL test asserts nothing is stored. 415's echo to match.
2026-11-27 09:12 (Hibiscus): not ready to merge. After feat/units-on-map lands: rebase feat/coordinates-named-latitude (origin, 3bf2dbc6f) onto master with a new migration timestamp after 20261126215254, rename inside admin.region_upload_upsert and worker.log_region_change as that migration defines them; apply the owner's hard cut (remove the retired-header refusal from admin.import_job_keep_ignored_columns and RETIRED_COORDINATE_COLUMN from upload-csv-check.ts; 415's echo and checks 8, 9 to match). Expected-output review done: /Users/jhf/ssb/statbus_test/tmp/jbc5bs-expected-review-findings.md. statbus_b now serves me96tn; the branch is only on origin.
2026-11-27 11:50 (hibiscus) Trial rebase of 3bf2dbc6f onto feat/units-on-map c3726cdc2 (scratch worktree, aborted): textual conflict only in doc/db/function/admin_region_upload_upsert().md (generated). Plan once feat/units-on-map is on master, done by hibiscus in statbus_test: (1) rebase; (2) move migration 20261126205623 after 20261127011934 (master's newest); (3) the migration also renames center_* in admin.region_upload_upsert and worker.log_region_change as 20261126215254 defines them, dumped with \sf; (4) rename center_* in the branch's app code: regions map, upload page, Download menu, api-reference.md; (5) owner's hard cut: drop the physical_* refusal from admin.import_job_keep_ignored_columns and RETIRED_COORDINATE_COLUMN from upload-csv-check.ts with its test; 415's echo and checks 8/9 reworded; (6) test 416 (region upload, mine) uses latitude etc.; (7) regenerate doc/db and types; fast suite; push; CI.
2026-11-27 12:22 (hibiscus) Numbering agreed with rabbit: the rename's test 415 becomes 419 (counting branch has 415_legal_unit_total_rollup_and_existence and 418; shrimp's quality 417; region upload 416 on master).
2026-11-27 12:31 (hibiscus) Checks 8 and 9 (ticked earlier for a refusal message) no longer describe the code: the owner's hard cut removed the message. hug cannot untick or strike a ticked check, so check 10 states what holds now; 8 and 9 read as superseded by it.
check 10: b534af8e5 test/sql/419: center_* region file refused (column does not exist), 0 regions stored; physical_* unit headers kept as ignored columns (physical_*_raw purpose ignored) while latitude/longitude/altitude are the step's inputs; no code names the old headers (rg outside migrations/tests finds none)
## History
- 2026-11-23T11:47 todo -> todo/depends (ask)
- 2026-11-26T21:42 answered design, by hibiscus, for hibiscus (todo/depends -> todo/depends):
  > Old headers in upload files: region files with center_latitude/longitude/altitude and unit files with physical_latitude/longitude/altitude (Erik's coordinate files use those) stop matching after the rename. Refuse them with a message naming the new headers, or accept them for one release before refusing?
  Refuse old headers with a message naming the new ones; a clean cut (owner 2026-11-26 20:41).
- 2026-11-26T21:42 answer 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-26T21:42 answer 1 acknowledged by rabbit
- 2026-11-26T21:49 todo/ready -> doing/active (take)
- 2026-11-27T00:18 handed to rabbit: ox's session ended (closed 2026-11-26 23:16)
- 2026-11-27T01:11 doing/active -> doing/waiting (wait)
