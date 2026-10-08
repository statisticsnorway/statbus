---
id: STATBUS-421
title: CSV export of search results contains every matching row
status: In Progress
assignee: []
created_date: '2026-09-25 14:02'
updated_date: '2026-10-08 13:25'
labels:
  - app
dependencies: []
priority: high
ordinal: 370200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Reported by Erik 2026-09-25 (Slack): exporting all legal units + establishments to CSV stops at ~119 thousand rows; expected ~1.9 million.
## Investigation, 2026-09-25 (coordinator, grounded)

**Root cause found.** The search page export (`ExportCSVLink`, app/src/app/search/components/search-export-csv-link.tsx) calls `/api/search/export`, whose route handler sets `searchParams.set("limit", "100000")` and `offset=0` and then makes ONE GET to `/rest/statistical_unit` (app/src/app/api/search/export/route.ts, limit at ~line 85; fetch at getStatisticalUnits, app/src/app/search/search-requests.ts:148). The cap was introduced in commit 20562bb30 ("ui: Adjust export to dynamic columns"). No PostgREST max-rows is configured anywhere (cli/internal/config, compose files), so this hardcoded 100,000 is the only cap.

**The reporter's number explained:** the CSV showed 119,083 lines, which looked inconsistent with a 100,000 cap — but CSV fields with embedded newlines inflate the line count; 119,083 lines is consistent with 100,000 records (sorted name.asc by default, stopping alphabetically around "ARILD H...", matching the screenshot).

**Design notes for the fix:**
- Export must page (or stream) until the result set is exhausted, not take the first 100,000. Offset pagination on a name-sorted live view can skip/duplicate rows under concurrent writes; consider keyset pagination on a stable column or a snapshot approach.
- Excel (.xlsx) has a hard format limit of 1,048,576 rows (EXCEL_MAX_ROWS already used in app/src/components/progress-download-button.tsx and command-palette). A 1.9M-row result cannot fit in xlsx: the UI must say so and offer CSV. The search page ExportCSVLink currently does NOT disable xlsx by count (unlike the import-jobs button).
- Memory: buffering 1.9M rows as JSON in the route handler is heavy; CSV should stream page-by-page into the response.
- Expected full count for Norway: ~1.9M units (legal units + establishments).

## Fix merged, 2026-09-25 (commit bc8d94082)

/app/src/app/api/search/export/route.ts now streams successive 100k-row PostgREST pages into the CSV response with backpressure; ordering is name.asc + tiebreakers unit_type, unit_id, valid_from, valid_to (unique per the view's UNION ALL timeline inputs). XLSX fails closed with 413 + CSV recommendation when the exact count is unavailable or exceeds 1,048,575 data rows, and accumulation is bounded by the up-front count. UI disables Excel above the threshold. Two independent review rounds; Jest coverage for multi-page assembly, refusals, ordering. Known limit (documented in code): offset pagination is not snapshot-consistent under concurrent writes; a stronger guarantee needs a snapshot/keyset design. Awaiting CI green + candidate gate as final evidence.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A full export on the largest real dataset returns exactly the exact count for its filter (1,976,463 rows for unit_type in (legal_unit, establishment) on the restored Norway dump), or fails loudly. The current silent shortfall of 29,470 rows (98.5 percent delivered while reporting HTTP 200) is not acceptable.
- [ ] #2 The export completes reliably within the production authenticated-role statement_timeout of 120s, whether by chunked keyset paging, a deliberate export-specific timeout, or another mechanism, and the chosen mechanism and its measured wall time are recorded in this ticket.
- [ ] #3 A mid-stream failure is visible to the user: the UI shows the error with rows received versus expected and does not save a partial file, and the log receives the request URL, rows received, expected rows, bytes and elapsed time.
- [ ] #4 Excel refuses honestly above the sheet limit with a clear message instead of building an unbounded workbook in memory (this dataset exceeds it: 1,976,463 rows against 1,048,575).
- [x] #5 No RLS change: the export uses the same /rest path and cookie JWT as the search page, and an anonymous request is still rejected.
- [ ] #6 Equivalence with the old export is verified as a bounded row-for-row comparison on a subset plus an exact row count on the full dataset. A full-set row-for-row comparison is explicitly NOT required, because the old JSON path cannot run at this size (PostgreSQL 1 GiB string-buffer limit, measured 2026-10-08).
- [ ] #7 Progress is visible while the export streams, showing rows received against the search total.
- [ ] #8 Real-data timing is recorded for the exact count and for the export, on the restored Norway dump.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 The fix is re-measured on the restored Norway dump and rows received equals expected, with wall time and bytes recorded in the ticket.
- [ ] #2 The ticket states which mechanism was chosen, why the alternatives were rejected, and the measured margin under the 120s statement timeout.
- [ ] #3 The 2026-10-08 measurement is retained in the ticket as the before-state evidence, including the shortfall number.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
NOTES HISTORY RESTORED 2026-10-08 (Phase 2 implementer): each earlier backlog --notes edit REPLACED the previous notes instead of appending, so the transport decision, the feasibility numbers, the fallback/date rules and the slice plan had vanished from the ticket. They are restored below in chronological order from git history; later entries supersede earlier ones where they conflict (in particular the feasibility report's date rule, real dates with the 1900 serial correction and pre-1900 kept as text, supersedes the earlier dates-as-text rule; and client-side streaming XLSX supersedes the earlier server-side XLSX decision).

REAL-DATA MEASUREMENT, 2026-10-08 (collected from the delegated worker's read-only run on the restored no_20260210_105613 dump). Verdict: the shipped single-request text/csv export DOES NOT meet the goal on real data. Restore took 1,323s; dataset is the February artifact, so it still exposes the legacy metadata view names (external_ident_type_active, stat_definition_active) and was not migrated (an unrelated migration attempt failed on a missing public.power_group, no product source changed).

MEASURED NUMBERS.
* Exact count for the export filter unit_type in (legal_unit, establishment), confirmed independently by the coordinator in psql: 1,976,463 rows.
* Full composed CSV export via PostgREST text/csv, no timeout override: HTTP 200, 421,121,756 bytes (about 402 MiB), wall time 114.64s, rows received 1,946,993, expected 1,976,463, SHORT BY 29,470 (98.509%), curl exit 0, no error text anywhere.
* The server's own Content-Range (0-1946992/*) agrees with the received row count, so this is not a row-counter artifact.
* Timeout margin: 5.36s under the unchanged 120s authenticated-role statement_timeout. The ticket's assumption that one request finishes comfortably under the timeout is contradicted.
* The db log shows no statement-timeout cancellation for this request, and the request is not configured with any PostgREST max-rows that we could confirm. So the shortfall cannot be attributed to a logged timeout, and the cause is still open.

OPEN QUESTION THAT DECIDES THE FIX (owner steering requested, do not code past it). Are the 29,470 rows cut off by the statement timeout at the transport layer, or does the query/serialisation path itself return fewer rows? Chunked keyset paging fixes the first and does nothing for the second, so the next experiment must settle it first. Note the composed select reads JSONB columns on statistical_unit itself (external_idents, primary_activity_category, physical_region, stats_summary, and CAST(... AS float8) on the coordinates), so the export query performs no joins that could drop rows; that makes a query-side row loss less likely and a transport-level cut more likely, but this is inference, not measurement.

BLOCKED ACCEPTANCE ITEM. The old-vs-new row-for-row CSV comparison cannot run on this dataset: the old JSON path dies with 500 "54000: string buffer exceeds maximum allowed length (1073741823 bytes)" (PostgreSQL's 1 GiB limit) after about 47s. The criterion must be redefined, for example a bounded subset compared row-for-row plus an exact count on the full set.

NOT RE-MEASURED YET: the deliberate mid-stream failure surfacing in the UI and in the logs; the Excel refusal above the sheet limit (this dataset's 1,976,463 rows are above Excel's 1,048,575 limit); in-browser progress.

PASSING: no RLS change (the measurement used the normal authenticated PostgREST path); the production createCsvRowCounter counted the downloaded body correctly.

RELATED, MEASURED THE SAME DAY: the STATBUS-461 violator scan on this same real dataset returns ZERO rows (1,137,041 legal units, 839,422 establishments, 1,137,041 enterprises; 13 establishments with the legitimate birth_date > valid_from). So the data-side gate would not block a real import, and the fleet-posture question for 461 is answered by measurement rather than speculation.

SECOND PASS, 2026-10-08 (coordinator, on the restored Norway dump). The first pass blamed the 120s statement timeout because the export took 114.64s. That reading is WRONG, and the corrected diagnosis changes the fix.

DECISIVE EXPERIMENTS.
1. Auth on the restored (old) artifact no longer comes from /rpc/login (the documented dev credential returns USER_NOT_FOUND there); a token can be minted in SQL with SELECT auth.generate_jwt(auth.build_jwt_claims('jorgen@veridit.no')). That is how these requests were made.
2. Narrow select, same filter (select=unit_id, order=unit_id.asc, Prefer: count=exact): HTTP 200, Content-Range 0-1976462/1976463, 13,722,928 bytes, ALL 1,976,463 rows delivered. So the filter and the connection can carry the full row count.
3. Wide export select, same filter, Prefer: count=exact: HTTP 206 Partial Content, Content-Range 0-1946992/1976463, Content-Length 421,121,756 bytes, i.e. 1,946,993 rows sent while the server ANNOUNCES the true total 1,976,463.
4. Repeat of the wide export: wall time 62.15s where the first pass measured 114.64s, with a BYTE-IDENTICAL response (421,121,756 bytes, same row count). A timeout cut would vary between runs; this does not.
5. db log for the wide request: duration 60407.766 ms execute, completed, and NO statement-timeout cancellation anywhere in the window. The database finished the query.
6. PostgREST configuration: the rest container has no PGRST_DB_MAX_ROWS and no MAX_ROWS in .env/.env.config/compose; port 3013 is published by the rest container itself, not by Caddy, so no proxy truncation is involved. PGRST_DB_CONFIG=true is set but this old artifact has no pgrst.db_config table.

CORRECTED DIAGNOSIS. The shortfall is a deterministic PARTIAL RESPONSE from PostgREST for this wide select: it applies a limit that correlates with row width/payload (a one-column select is complete at 13.7 MB; the full select is cut at 421 MB), it announces the true total in Content-Range, and it is reproducible byte for byte. It is not a statement timeout, not a data or filter problem, and not a row-count cap on the table.

WHAT THIS MEANS FOR THE FIX.
* The app must never treat one request as a complete export. It must page and it must verify: compare the rows actually received against the total the server announces in Content-Range, and fail loudly on a mismatch. That check alone would have turned this into a visible error on the user's very first attempt.
* Paging over the recorded total is the natural mechanism and PostgREST already exposes exactly what is needed: Content-Range with the true total, HTTP 206 for a partial range, and Range headers to request the next slice. Keyset paging (the existing D5 decision) is the alternative and avoids deep offsets.
* The acceptance criterion "completes reliably within the production 120s statement timeout" needs rewording: the timeout was never the binding constraint. The real criterion is "the export delivers every row, and any shortfall is an error the user sees".

STILL TO DO ONCE THE DIRECTION IS CONFIRMED: re-measure with the chosen paging mechanism until rows received equals the announced total; rework the equivalence criterion (full-set row-for-row against the old path is impossible, see below); re-measure the UI failure and progress paths.

UNCHANGED FROM PASS 1: the old-vs-new full row-for-row comparison cannot run at this size (the old JSON path dies with 54000 string buffer exceeds maximum allowed length, PostgreSQL 1 GiB limit); no RLS change (PASS); the restored artifact is the February dump with legacy metadata view names.

IMPLEMENTATION STATUS AS OF 2026-10-08 (read from the code, not from memory). WHAT EXISTS, landed in 1e5ac2ccf: app/src/app/search/export/use-statistical-unit-export.ts performs ONE fetch against /rest with Accept: text/csv, streams the body with response.body.getReader() and counts records with csv-row-counter.ts for the progress bar, supports cancellation, refuses XLSX above the sheet limit, confirms above 100k rows, logs start/success/failure via export-logger.ts, and ends with a completeness guard: if rowsReceived !== expectedTotal it errors with 'Export incomplete: received X of Y rows. The download was not saved - please try again.' export-query.ts composes the select and the deterministic order. WHAT DOES NOT EXIST: any piece-by-piece fetch, paging or client-side assembly. There is no Range header, no offset, no keyset page loop anywhere in the export path, so nothing is downloaded in parts and reassembled. A comment in search-export-csv-link.tsx mentioning 'paging' is stale and describes no code. Two further notes on the guard: it compares against the search's expected total, which can be a planner estimate rather than an exact count, and it never consults the total the server announces in Content-Range. DESIGN INVESTIGATION UNDER WAY, delegated to worker @duckling on 2026-10-08: establish the root cause of the partial response, test whether any single request can return the entire set, measure HTTP Range paging versus keyset paging including a rigorous coverage proof that the union is exactly 1,976,463 distinct rows with no gaps or duplicates, and recommend the client-side design (page size, progress, completeness proof, memory and time estimates) with rejected alternatives. Deliverable tmp/421-export-design.md. Design first: no product code is being changed while that runs. WORKING PRINCIPLE FROM THE OWNER: do not design to failure - the guard stays as a safety net, but the design must deliver every row.

MODEL DECISIONS AND DELEGATION, 2026-10-08 (owner instruction). The export DESIGN investigation runs on gpt-6.1-sol (worker @mizaru, spawned 10:07). The first attempt was delegated at 09:24 to @duckling, which came up on the configured swarm default gpt-5.6-sol and produced nothing in 30 minutes (never touched a file, no output), so it was stopped and the task re-delegated. The IMPLEMENTATION that follows the design is to be done on claude-opus-5-5, per the owner. The owner's standing guidance for this work: do not design to failure - the completeness guard stays as a safety net, but the design must deliver every row, fetched from the client side with progress.

SWARM DEFAULT FIXED, 2026-10-08: the configured default was ~/.jcode/config.toml [agents] swarm_model = 'gpt-5.6-luna', an obsolete generation, which is why the first delegated design worker landed on gpt-5.6-sol and produced nothing. It is now set to 'gpt-6.1-sol' so no future worker inherits an obsolete model. Owner guidance: GPT 5.6 is obsolete, GPT 6 and 6.1 replaced it, and Sol is the only 6.1 variant. Design work runs on gpt-6.1-sol (@mizaru), implementation on claude-opus-5-5.

DESIGN FINDING, 2026-10-08 (worker @mizaru on gpt-6.1-sol, design-only, no product code changed). THE ROOT CAUSE IS OURS, NOT POSTGREST'S, AND IT IS A SILENT ROW-LOSS BUG IN OUR OWN SELECT.

WHAT HAPPENS. The export select in app/src/app/search/export/export-query.ts lines 96, 98 and 106 uses arrow syntax on three computed relationships:
  primary_activity_category_name:primary_activity_category->>name
  secondary_activity_category_name:secondary_activity_category->>name
  physical_region_name:physical_region->>name
Those three names are computed-relationship functions returning SETOF (public.primary_activity_category(statistical_unit) RETURNS SETOF activity_category STABLE ROWS 1, likewise secondary_activity_category and physical_region). PostgreSQL evaluates set-returning functions in a select list in lockstep, and a row produces NO output row when all such functions return an empty set. So rows whose activity categories and region are all absent are silently dropped from the response.

EVIDENCE. Direct SQL under SET ROLE authenticated on the restored Norway dump: base count 1,976,463; the same query with all three SRFs projected returns 1,946,993. The shortfall, 29,470, is exactly the number the export lost and exactly what the server reported as Content-Range 0-1946992/1976463. PostgREST's active config has db-max-rows = "" (verified with postgrest --dump-config and docker inspect; no PGRST_DB_MAX_ROWS), and its CSV path builds the body with string_agg while computing page_total from count(_postgrest_t) in the same statement, which is why the page query genuinely produced 1,946,993 rows while the count query counted 1,976,463. There is no cap, no timeout and no truncation involved.

THE FIX (one projection change, no paging needed). Use PostgREST's documented spread syntax for to-one relationships:
  primary_activity_category(primary_activity_category_name:name)
  secondary_activity_category(secondary_activity_category_name:name)
  physical_region(physical_region_name:name)
With that correction a single CSV request returned ALL 1,976,463 rows: HTTP 200, Content-Range 0-1976462/1976463, 426,331,946 bytes, in 21.60 seconds. So a single request does deliver the entire export at the current size (about 2 million rows, 426 MB), and it is FASTER than the broken version (21.60s versus 114.64s). Paging is therefore NOT required for correctness now. If paging is ever added for future growth, keyset paging measured materially faster than Range/OFFSET paging.

SCOPE CHECK (coordinator): the arrow-style projection appears ONLY in export-query.ts (lines 96, 98, 106). No other app query uses that form, so the silent row loss is confined to the export select; the search page's own display query is unaffected.

FUTURE CEILING TO KNOW ABOUT (not today's bug): PostgREST's CSV path assembles the whole body with string_agg in one value, so a response approaching PostgreSQL's roughly 1 GiB varlena limit is unsafe as one aggregated response. That is the same class of limit that killed the old JSON comparison path at 1,073,741,823 bytes. At 426 MB there is headroom, but the design should record the ceiling alongside the fix.

KEEP REGARDLESS OF THE FIX: compare the rows received against the total the SERVER announces in Content-Range, not against the search page's expected total, which can be a planner estimate. That turns any future shortfall into a visible error instead of a silently short file. The existing guard's idea is right; its reference value is wrong.

AC WORDING NOW SUPERSEDED: the criterion 'completes reliably within the production 120s statement timeout' should be replaced by 'delivers exactly the announced total, and any shortfall is an error the user sees'. The 120s timeout was never the binding constraint.

INDEPENDENT VERIFICATION BY THE COORDINATOR, 2026-10-08. The worker's corrected-export artifact was re-checked with a DIFFERENT method than the app's row counter, so the claim does not rest on the code under test. tmp/421-corrected-full.csv: 426,331,946 bytes, HTTP 200, Content-Range 0-1976462/1976463, wall time 21.60s. A Python csv.reader (which handles embedded newlines and quoted fields properly) counted exactly 1,976,463 data rows over 41 columns: MATCH. Conclusion, verified: the spread-syntax projection fix delivers the entire export in ONE request, and the 29,470-row shortfall of the current implementation is caused by the SETOF computed-relationship projection in export-query.ts. Note: the corrected artifact is a 426 MB file in tmp (gitignored) if anyone wants to re-verify; it can be deleted when the work is done.

TRANSPORT DESIGN RECONCILIATION, 2026-10-08 (owner asked to lay out the options and resolve).

FACTS ON THE TABLE.
* Search export today (1e5ac2ccf): the BROWSER calls PostgREST /rest with Accept: text/csv, one request, streamed with getReader(), with a row counter for progress. It delivered 1,946,993 of 1,976,463 rows because of our projection bug, and with the projection fixed it delivers all rows in 21.6s / 426 MB. Its hard ceiling is PostgREST's own CSV construction: the whole body is one string_agg value (confirmed in PostgREST 14.14 source, SqlFragment.hs), so it breaks near PostgreSQL's ~1 GiB limit and the database holds the entire body in memory while it is produced.
* The IMPORT DOWNLOAD route already streams CSV from PostgreSQL through a Next.js route with COPY: app/src/app/api/import/download/route.ts line 296: COPY (select) TO STDOUT WITH (FORMAT CSV, HEADER) executed with pg-copy-streams (copyTo) and piped into a ReadableStream response (line 299). The same file also shows the cursor alternative, DECLARE download_cursor CURSOR + FETCH 5000 in a loop, which it uses for XLSX generation. Both paths authenticate by connecting as authenticator and calling SELECT auth.jwt_switch_role(<statbus cookie access token>) (lines 133-139), so ROW LEVEL SECURITY STILL APPLIES with the user's own role and claims. So COPY is not a new idea here; it is a proven in-repo mechanism, and it does not require a service-role bypass.

OPTIONS.
A. Stay pure REST (browser to /rest, one request).
   + No server code; RLS through the user's cookie; browser progress; verified fast at today's size.
   - Hard ~1 GiB ceiling from the string_agg body; database memory holds the whole response; no resume; one more row-width or row-count growth step breaks it again.
B. Server-side streaming export route reusing the import-download mechanism (COPY TO STDOUT, user JWT).
   + Constant memory in the database and in the app (COPY streams; pg-copy-streams applies backpressure to the browser); no aggregate ceiling, so it scales the whole way; the received byte stream carries the same row counter for progress; RLS preserved via jwt_switch_role; fastest serialisation PostgreSQL offers; the pattern is already proven in this codebase.
   - Costs one new route and the SQL equivalent of the composed select (the three computed relationships become function calls such as public.primary_activity_category(su)); the app process carries the streaming load for the duration; a long export occupies one app connection.
C. Browser to /rest with keyset paging, assembled client side.
   + Arbitrarily large; resumable; per-page progress; no server code.
   - N requests with a stable keyset ordering, duplicate and gap detection, and the browser must hold every part in memory unless we stream to disk (File System Access API). Most complexity and the least reuse.

RESOLUTION (proposed plan).
Phase 1, now, small: apply the three-line projection fix in export-query.ts, keep the single-request browser-to-/rest streaming export for the current size, and make the completeness guard compare against the server's announced Content-Range total. XLSX stays client side and bounded. This unblocks the field immediately and is independent of the transport decision.
Phase 2, the whole way: move the export onto a server-side streaming route that uses COPY (SELECT ...) TO STDOUT with the user's JWT, mirroring app/src/app/api/import/download/route.ts. Constant memory, no ceiling, same browser progress, RLS intact. With that in place the direct-REST single request can either be retired for one mechanism or kept for small exports; that is the one open choice.
Phase 3, only if exports ever exceed browser memory: stream the response to disk in the browser with the File System Access API. Because Phase 2 already yields a byte stream, this becomes a client-only change.
Before writing Phase 2 code: run a short benchmark on the restored Norway dump comparing COPY TO STDOUT against PostgREST text/csv (wall time, memory, completeness) so the transport choice is measured rather than assumed. Both mechanisms must be checked for identical content.

NOTE: Phase 1 does not depend on this reconciliation, and the field fix should not wait for Phase 2.

TRANSPORT DECISION, 2026-10-08 (owner): ONE mechanism only, the COPY route. Rationale: it is already secure because it authenticates with auth.jwt_switch_role on the user cookie, so RLS still applies, and it is already proven in this repository for import downloads. Phase 1 (the projection fix plus a guard against the server-announced Content-Range total) still ships first and is independent of this decision.
CLIENT PROGRESS AND STREAMING TO DISK (owner question: can the stream go all the way to disk in the first pass?). Yes, as a progressive enhancement. Where the File System Access API is available (Chromium browsers), the client can let the user choose a file and write each received chunk straight to it, so browser memory stays constant. Where it is not available (Firefox), fall back to assembling in memory as today. Progress by RECEIVED BYTES is the right indicator, because the total byte count is not known in advance; rows-received stays available as a secondary line for CSV, since the row counter already exists. Practically this means the response carries no meaningful total, and the UI shows 'received N MB' plus rows.
XLSX (owner: think about the delay after all bytes are received). Generate XLSX SERVER-SIDE with a streaming writer over DECLARE cursor plus FETCH batches, exactly as app/src/app/api/import/download/route.ts already does, and stream it to the client. That removes the delay: the bytes the client receives ARE the finished workbook, so there is no client-side conversion step after the transfer and 'received bytes' is honest progress for Excel too. Browser-side workbook assembly must not be the mechanism for large exports, because the user would otherwise watch all bytes arrive and then wait with no explanation.

PHASE 1 SHIPPED, commit 7d89a032a (2026-10-08). (1) export-query.ts: the three name columns use the spread syntax ...primary_activity_category(primary_activity_category_name:name), ...secondary_activity_category(secondary_activity_category_name:name), ...physical_region(physical_region_name:name). exportFieldNames resolves the spread's inner alias so XLSX keeps names and order. (2) Guard: the request now sends Prefer: count=exact (without it PostgREST answers Content-Range 0-N/* with no total). Rows received are checked against the Content-Range denominator, counted by the same statement as the rows. The search page total is the fallback only when the header has no total AND that total is exact. A mismatch errors with both counts and saves nothing; the check also covers XLSX. MEASURED on the restored Norway dump, unit_type=in.(legal_unit,establishment): new select, HTTP 200, Content-Range 0-1976462/1976463, 1,976,463 rows (python csv reader), 426,331,946 bytes, 28.1s with count=exact (33.6s on another run without it), byte-identical to tmp/421-corrected-full.csv. Old arrow select under the same request: HTTP 206, Content-Range 0-1946992/1976463, 1,946,993 rows, 80.2s, so the guard rejects it. COLUMN ORDER CAVEAT: PostgREST writes embedded/spread columns after all plain columns, so in the CSV the three *_name columns are now the LAST columns, after the stat variables (names unchanged; XLSX order unchanged). Restoring the historical CSV position is left for Phase 2, where the COPY route controls the column order.

OWNER DECISION 2026-10-08: the CSV column-order caveat (the three *_name columns moving to the end because PostgREST writes embedded columns after plain ones) NEEDS NO ACTION. The owner considers it irrelevant because we are leaving this design for the COPY route, where column order is explicit. Do not spend work on reordering the CSV in the PostgREST path. The broader question of whether the arrow-syntax construct bites elsewhere is filed as its own ticket.

CLIENT-SIDE XLSX FALLBACK DEFINED (owner asked to define it, 2026-10-08). Prototype evidence in tmp/421-xlsx-proto/out/: a streamed XLSX of 1,048,575 rows was written in 24.9 s with tailAfterLastInputMs 16, so there is no pause after the last input byte, and progress was reported in bytes and rows. Measured browser support: Chromium has showSaveFilePicker, so chunks stream straight to the user's chosen file with flat memory; Firefox 142 has no showSaveFilePicker but does have OPFS and createWritable.

THE DEFINITION.
1. PREFERRED (showSaveFilePicker available): stream workbook chunks directly to the chosen file as rows arrive. Flat memory at any size. Progress = received bytes, bytes written, rows written.
2. FALLBACK (Firefox; OPFS available): write the streamed workbook progressively to the origin private file system, so memory stays flat while the export runs, then offer it for saving by reading it back as a Blob. Document the one-off read-back cost (memory equal to the file, measured about 113 MB at 1,048,575 rows) and warn above a threshold such as 500 MB instead of failing silently.
3. DEGRADED (neither API): refuse XLSX above a small bound and point the operator at CSV, rather than buffering a large workbook without saying so.
4. DATES: keep sentinel and historical date columns as TEXT, never date-typed cells. The prototype found 29 cells where the sentinel 1900-01-01 returned a day off through Excel's 1900 date system, and it already keeps pre-1900 values as text (1,362 cells). Our data uses 1900-01-01 as a sentinel, so the rule is: write date columns as text unless the value is a real date in Excel's unambiguous range.
5. XLSX stays capped at the sheet limit with the existing honest refusal; CSV remains the primary path for large exports.

CLIENT-SIDE XLSX FEASIBILITY CONFIRMED AND MEASURED, 2026-10-08 (report tmp/421-client-xlsx-feasibility.md, prototype kept in tmp/421-xlsx-proto/). VERDICT: feasible, with ONE server mechanism (COPY CSV streamed with the user's JWT) feeding both formats; the browser converts that same stream to XLSX while it arrives and writes the workbook straight to disk. At the full Excel limit in headless Chromium 141: 17.5 s wall, a 113 MB file, a 14 ms tail after the last network byte, completed under a 64 MB V8 heap cap which is proven to kill a Worker that buffers. Firefox native works and the fflate fallback works; Firefox lacks showSaveFilePicker, so its fallback streams into OPFS and then hands the finished file to a normal download, a measured 7.7 s copy for a 117 MB workbook. Independent readers all accept the output: zipfile CRC, expat, openpyxl cell by cell with 0 mismatches, and LibreOffice 7.6 in headless mode, which sees 1,048,575 data rows and the last row 993998656 LYSTGAARDEN BAR & RESTAURANT AS. IT ALSO EXPLAINS THE EARLIER MISMATCH LOG: the first full run had 29 mismatches, all dates 1900-01-01 to 1900-02-28 arriving one day late, because Excel's serial numbers include the fictitious 1900-02-29 (serial 60, the Lotus compatibility quirk), so dates before 1900-03-01 must be one lower. Fixed in the prototype and the rerun shows 0 mismatches; a production writer needs a unit test for 1900-01-01 -> 1, 1900-02-28 -> 59 and 1900-03-01 -> 61. CONSTRAINTS RECORDED: run the conversion in a dedicated Worker; use native CompressionStream deflate-raw with fflate supplying only the ZIP container and CRC; refuse above EXCEL_MAX_DATA_ROWS both before the request and on the fly; abort() on any failure; Firefox OPFS fallback. A real-Excel acceptance check remains the owner's to perform.

PHASE 2 SLICES, 2026-10-08, now that the XLSX feasibility question is answered. One mechanism: a server-side streaming export route authenticated with the user's JWT, feeding both formats, with the client writing to disk. Land each slice as its own commit with its own evidence; stop and report if a slice turns out much larger than it looks.
S1, the server route: authenticate with auth.jwt_switch_role on the user's cookie exactly as app/src/app/api/import/download/route.ts does, run COPY (SELECT ...) TO STDOUT WITH (FORMAT CSV, HEADER) with pg-copy-streams, and stream it to the response with backpressure. Constant memory, no aggregate, no 1 GiB ceiling. The composed select moves into SQL, where column order is explicit, which also settles the CSV column-order caveat from Phase 1.
S2, the client CSV path: fetch that route, stream with getReader, write chunks straight to a file chosen through showSaveFilePicker where available, report progress in received bytes AND rows, abort() on any failure, and keep the completeness check against the server-announced total.
S3, the client XLSX path: a dedicated Worker converting the incoming CSV records into XLSX while they arrive, using native CompressionStream('deflate-raw') with fflate supplying only the ZIP container and CRC; write straight to disk; refuse above EXCEL_MAX_DATA_ROWS both before the request and on the fly. Include the unit test the feasibility report calls for: 1900-01-01 -> serial 1, 1900-02-28 -> 59, 1900-03-01 -> 61, because Excel's serials include the fictitious 1900-02-29.
S4, the Firefox fallback: no showSaveFilePicker there, so stream into OPFS and then hand the finished file to a normal download, documenting the measured copy cost (7.7 s for a 117 MB workbook).
S5, retire the direct-REST single-request path per the single-mechanism decision, and update doc/DEPLOYMENT.md and the export docs. The 421 criteria authored on 2026-10-08 remain the acceptance bar.

CONSTANT CONSOLIDATION AND THE CAP QUESTION, 2026-10-08. Owner decision: a single source of truth for the constants. EXCEL_MAX_ROWS = 1_048_576 is currently duplicated in app/src/app/search/export/export-query.ts, app/src/components/progress-download-button.tsx and app/src/components/command-palette.tsx; consolidate into one exported constant that the others import, and fold that into slice S3 rather than opening a ticket of its own.
THE CAP IS BY DESIGN, NOT COINCIDENCE: one sheet holds at most 1,048,576 rows INCLUDING the header row, so the export caps DATA rows at EXCEL_MAX_DATA_ROWS = EXCEL_MAX_ROWS - 1 = 1,048,575, which is why the last row index of a maximum-size export is exactly 1048576. The refusal is therefore testable locally and visibly: the restored Norway dump has 1,976,463 rows in the export filter, roughly 928,000 above the cap, so the Excel option is unavailable with the message that Excel supports at most 1,048,575 data rows, while CSV proceeds. That is the intended behaviour, not a bug.
<!-- SECTION:NOTES:END -->

## 2026-10-07: the export still cannot deliver — owner-observed failure on no.statbus.org, diagnosed

Status correction: **the ticket is NOT finished.** The merged fix removed the 100k cap but the
real export on the production data fails, silently, in four independent ways. Evidence below is
from the actual failed downloads plus the code deployed in rc.20 (`bce5bf39`); nothing was
changed on the box.

### Observation

Owner ran the export on `no.statbus.org` (rc.20, `/search?...&unit_type=establishment`,
"Showing 1-10 of total 825 126 results", page 1 of 82 513). The Firefox downloads panel showed
both attempts failed ("Mislykket") and left partial files:

| file | bytes | records | of 825,126 | trailing newline |
|---|---|---|---|---|
| `establishments.oBbFLgCQ.csv.part` | 77,361,463 | 400,000 | 48% | no |
| `establishments(1).vmuT8S7_.csv.part` | 19,299,981 | 100,000 | 12% | no |
| `establishments.csv` | 0 | 0 | — | — |
| `establishments(1).csv` | 0 | 0 | — | — |

Both partials parsed with a real CSV reader: **zero malformed rows**, 37 columns, every record
complete. So the data that arrived is valid; it is simply truncated.

### Finding 1 — truncation happens exactly at a PAGE boundary

100,000 and 400,000 are exact multiples of `PAGE_SIZE = 100_000`
(`app/src/app/api/search/export/route.ts:15`). The streaming loop explains why:

```ts
const stream = new ReadableStream<Uint8Array>({
  async pull(controller) {
    if (offset < total) {
      const { header, body } = toCSV(page);
      controller.enqueue(encoder.encode((first ? header : "\n") + body));   // separator is the NEXT chunk's prefix
      first = false;
      offset += page.length;
      if (offset < total) {
        page = await fetchPage(offset);   // page N+1 fetched AFTER page N was flushed
      }
    }
    if (offset >= total) controller.close();
```

`fetchPage` runs inside the *same* `pull` after page N has been enqueued, so when the fetch for
page N+1 throws, the client has exactly N complete pages — and no trailing newline, because the
`"\n"` separator belongs to the chunk that never came. A mid-page network cut could not produce
these counts; a failure while fetching page N+1 produces them precisely.

### Finding 2 — the page fetch exceeds a 120-second statement timeout

```
postgres/init-db.sh:167          ALTER ROLE authenticated SET statement_timeout = '120s';
migrations/post_restore.sql:41   (same)
migrations/20240102000000_create_schema_admin.up.sql:33   (origin)
```

The export runs as `authenticated` (the user's JWT), so every statement is capped at 120 s. Each
page request is expensive for two compounding reasons:

1. `getStatisticalUnits` sets `Prefer: count=exact`
   (`app/src/app/search/search-requests.ts:165-172`), so **every page repeats a full exact
   COUNT over the whole filtered set** (825,126 rows) in addition to returning 100k rows.
2. `fetchPage` uses `offset`/`limit` (route.ts `searchParams.set("offset", …)`), i.e. deep
   `OFFSET` with a filter the index cannot serve as a prefix — see the corrected schema note
   below — so each page re-scans/re-sorts the filtered set and discards N×100k rows.

Page cost grows with depth; the first page to cross 120 s is cancelled (SQLSTATE 57014),
PostgREST returns an error, `fetchPage` throws, and the stream dies at that boundary. Four pages
fit inside the budget, the fifth did not — which is why one attempt reached 400,000 records and
the other only 100,000. Timing variance, not data.

**Schema correction (verified 2026-10-07, local DB).** An earlier draft of this note called
`statistical_unit` "a UNION ALL over the temporal tables". That is wrong:
`statistical_unit` is a **plain table** (`relkind = 'r'`) rebuilt by the
`public.statistical_unit_refresh()` procedure (migration `20240311000000`), with useful btree
indexes: `idx_statistical_unit_name (name)`, `idx_statistical_unit_establishment_id (unit_id)`,
`idx_statistical_unit_unit_type (unit_type)`, plus filter columns (region, sector, activity
category, …). Consequences that shape the fix:

- The data is snapshot-stable between refreshes, so the "offset pagination is not
  snapshot-consistent under concurrent writes" caveat in the current code is weaker than
  assumed — the real defects are cost and observability, not write skew.
- `ORDER BY name` **can** use an index, so a keyset cursor on the order key is practical rather
  than merely theoretical, and so is batching on `unit_id` ranges (constant cost per batch,
  independently parallelizable and resumable).
- A filter that is not a prefix of the chosen index still makes each deep `OFFSET` page do a
  scan/sort of the filtered set — which is the cost that must go.

### Finding 3 — the failure is invisible to the operator

The streaming `pull`'s catch calls `controller.error(error)` and **logs nothing**; only the outer
catch, which runs before streaming begins, has `console.error`. That is exactly why
`log.statbus.org` showed no exception for a failed export. An export that dies mid-stream is
unobservable by construction.

### Finding 4 — Excel is offered, then cannot possibly work

The row limit in both UI and route is `EXCEL_MAX_ROWS - 1 = 1,048,575` — the *xlsx format* limit,
not a practical one (`app/src/app/search/components/search-export-csv-link.tsx:14,40-47`;
route.ts `EXCEL_MAX_ROWS`). At 825,126 rows Excel is therefore **offered**, and the route then
builds an entire ExcelJS workbook in memory for 825k rows × 37 columns before writing a single
byte (`workbook.xlsx.write(passThrough)` happens only after the whole loop). The two 0-byte
files are consistent with those Excel attempts: nothing to stream while the workbook is being
built (inference from file sizes/timestamps, not a server observation). It looks like a no-op
download; in truth it is an unbounded in-memory build.

### Consequences for the acceptance criterion

The ticket's finish line ("a Norway export after v2026.09.3 yields the full row count and Erik
confirms") is **unmet**. The 825,126-establishment export has never been delivered by any
version, so the multi-page path has still only ever been proven by Jest assembly tests, never
against 825k real rows.

### Remaining work (owner-approved direction 2026-10-07)

1. **Count once.** Use `count=exact` for the first request only; subsequent pages use
   `count=estimated` or no count. Removes 8 of 9 full counts on this dataset.
2. **Keyset pagination instead of deep OFFSET**, on the export order
   (`app/src/app/api/search/export/export-order.ts`: name.asc + unit_type, unit_id, valid_from,
   valid_to). This removes both the growing scan (Finding 2) and the skip/duplicate flaw the
   current code already documents as its known limit.
3. **Log mid-stream failures** with the page offset and the underlying error — a failed export
   must be findable afterwards.
4. **Practical XLSX bound** (memory/time, far below 1,048,575) plus a *visible* refusal in the UI,
   not a JSON body and not an offered-then-hung download.
5. **Managed progress** (owner ask: "it should probably be more managed, i.e. to see progress").
   Options to decide: a job-based export (generate to a file, then download with progress) or a
   chunked client-side download that reports page progress. Split from 1-4 if it grows: 1-4 are
   correctness, 5 is experience.
6. **Verification**: restore the Norway dump locally, time each page, and catch the 57014 at
   ~120 s — then repeat after the fix and count records end to end.

Ticket split (owner to confirm): keep 1-4 here as the correctness fix, and cut a separate ticket
for 5 if it is not a small addition.

## FINAL AGREED SCOPE (owner decisions 2026-10-07) — implement this, do not redesign

Full reasoning and rejected alternatives: `tmp/421-export-plan-20261007.md`.

**D1 — PostgREST `text/csv` first, measured.** Replace the page loop with a single streaming
request asking PostgREST for CSV (verified: `GET /` advertises `text/csv` on postgrest/14.14):

```
GET /rest/statistical_unit?<filters>&select=<composed>&order=<exportOrder>
Accept: text/csv
```

Keep `/api/search/export` as a thin proxy (adds the composed `select` and the `Accept` header),
or delete it — but the composed select must stay in exactly one shared place.
Benchmark it on real data. If the single statement exceeds the 120 s role timeout, the measured
fallback is `COPY (…) TO STDOUT WITH CSV HEADER` over a direct session that connects as the
**authenticator**, `SET LOCAL role` to the token's role and
`set_config('request.jwt.claims', …, true)` — i.e. the *user's own* JWT (the one the command
palette's "Show API Key" shows), never the app's broader owner credential — with a test that a
restricted user receives a restricted export.

**D2 — the browser calls `/rest` directly** (owner: "better transparency, less to debug"). No
`/api` proxy in the browser path.

**D3 — progress is in scope; resume only if it is nearly free.** Rows-received against the total
the search page already has. A keyset re-issue for resume is optional; if it is more than a few
lines, leave it out and say so.

**D4 — hard cap stays 1,048,575 rows; require confirmation above ~100k** (Excel itself will
struggle). Consequence: an xlsx built *server-side* at that size is a shared-container OOM risk,
so build it client-side (ExcelJS runs in the browser) or keep a much lower server-side bound.

**D5 — ordering:** the single-request form makes `ORDER BY` cheap (one index-ordered scan).
If batching turns out to be necessary, batch by keyset on the order key using
`or=(name.gt.<LAST>,and(name.eq.<LAST>,unit_id.gt.<LAST_ID>))`; do NOT detour through
"gather every id then request `unit_id=in.(…)`" — that hits URL-length limits at roughly a
thousand ids per request.

**Observability is part of the fix:** a mid-stream failure must be logged with enough context
(page/offset and the underlying error) to be found afterwards. Today it is swallowed by the
stream's catch, which is why `log.statbus.org` showed nothing for a dead export.

**Acceptance for this work**

- [ ] The 825,126-establishment export completes and the CSV record count matches the search
      page's total.
- [ ] PostgREST's CSV output is compared row-for-row with today's `toCSV` output (quoting, NULLs,
      dates, embedded newlines) before the old path is removed.
- [ ] A failing export is visible afterwards in the logs with the page/offset and error.
- [ ] XLSX refuses honestly above the practical bound, and the refusal is visible in the UI.
- [ ] Progress is visible while the export runs.
- [ ] No RLS or permission change: an export by a restricted user returns only what that user can
      see, with a test proving it.
- [ ] Timing measured on real data and stated in the report (the whole point of D1).
