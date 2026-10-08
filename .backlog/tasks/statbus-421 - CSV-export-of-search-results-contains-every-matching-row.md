---
id: STATBUS-421
title: CSV export of search results contains every matching row
status: Done
assignee: []
created_date: '2026-09-25 14:02'
updated_date: '2026-10-08 18:24'
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
- [x] #1 A full export on the largest real dataset returns exactly the exact count for its filter (1,976,463 rows for unit_type in (legal_unit, establishment) on the restored Norway dump), or fails loudly. The current silent shortfall of 29,470 rows (98.5 percent delivered while reporting HTTP 200) is not acceptable.
- [x] #2 The export completes reliably within the production authenticated-role statement_timeout of 120s, whether by chunked keyset paging, a deliberate export-specific timeout, or another mechanism, and the chosen mechanism and its measured wall time are recorded in this ticket.
- [x] #3 A mid-stream failure is visible to the user: the UI shows the error with rows received versus expected and does not save a partial file, and the log receives the request URL, rows received, expected rows, bytes and elapsed time.
- [x] #4 Excel refuses honestly above the sheet limit with a clear message instead of building an unbounded workbook in memory (this dataset exceeds it: 1,976,463 rows against 1,048,575).
- [x] #5 No RLS change: the export uses the same /rest path and cookie JWT as the search page, and an anonymous request is still rejected.
- [x] #6 Equivalence with the old export is verified as a bounded row-for-row comparison on a subset plus an exact row count on the full dataset. A full-set row-for-row comparison is explicitly NOT required, because the old JSON path cannot run at this size (PostgreSQL 1 GiB string-buffer limit, measured 2026-10-08).
- [x] #7 Progress is visible while the export streams, showing rows received against the search total.
- [x] #8 Real-data timing is recorded for the exact count and for the export, on the restored Norway dump.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 The fix is re-measured on the restored Norway dump and rows received equals expected, with wall time and bytes recorded in the ticket.
- [x] #2 The ticket states which mechanism was chosen, why the alternatives were rejected, and the measured margin under the 120s statement timeout.
- [x] #3 The 2026-10-08 measurement is retained in the ticket as the before-state evidence, including the shortfall number.
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

S1 LANDED, 2026-10-08, commit 54be3d809 (Phase 2 implementer). GET /api/search/export now runs COPY (SELECT ...) TO STDOUT WITH (FORMAT CSV, HEADER) as the caller's own role: a dedicated connection as authenticator, BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY, auth.jwt_switch_role(<statbus cookie>), then count(*) and COPY in the SAME snapshot. The count is announced in X-Export-Total-Rows. The stream ends cleanly only when COPY's own command-tag row count AND the quote-aware record count of the streamed bytes both equal that total, otherwise the response is aborted. The search page's PostgREST filter syntax is translated by a whitelist (app/src/app/search/export/export-sql.ts). Unknown keys or operators are a 400, never silently ignored. Column order is explicit: identifiers, then shared columns with each *_name directly after its *_code, then statistics. The three names come through LEFT JOIN LATERAL on the SETOF functions, so no row can be dropped.
MEASURED ON THE RESTORED NORWAY DUMP, filter unit_type in (legal_unit, establishment), order name.asc plus tiebreakers. (1) Through the Next route (curl with the statbus cookie, Next dev server): HTTP 200, X-Export-Total-Rows 1976463, 415,392,207 bytes, 21.8 s wall, 11.6 s to first byte (the sort), app server RSS flat (916,400 KB before, 916,544 KB peak, so +144 KB for a 415 MB export). (2) The same core under Node without HTTP: 1,976,463 rows sent, count phase 158 ms, 19.7 s wall, harness peak RSS 77 MB. The two outputs are byte-identical. (3) Equivalence with Phase 1 (tmp/421-corrected-full.csv, PostgREST text/csv), compared by header name with a python csv reader: ALL 1,976,463 rows in the same order, the same column set, and zero cell differences except 87 cells (55 physical_address_part1, 29 postal_address_part1, 2 name, 1 web_address) where the value contains a backslash. PostgREST's CSV DOUBLES backslashes (e.g. LEIRVIK UTLEIGEBYGG A\\S), and psql confirms the stored value has ONE backslash (length 23). So COPY is the faithful one, and this is a latent PostgREST CSV fidelity defect that the new path fixes. (4) Filter parity, 20 query shapes covering every operator the search page emits (fts with negation, cd on region/activity/sector, is.null, in on codes, ov, external_idents eq/like, stats_summary gte+lt range and in, is.false, valid_from/valid_to time context, jsonb and external-ident ordering, empty results): COPY rows = announced = PostgREST rows for every case, 0 cell differences beyond the backslash class (log tmp/421-p2/parity.log, harness tmp/421-p2/parity.ts).
TIMEOUT (AC#2): the export runs inside its own transaction with SET LOCAL statement_timeout = 30min. The authenticated role's 120 s is a login default that SET ROLE does not apply. The measured 21.8 s statement leaves a 98 s margin under 120 s anyway, but a slow client's backpressure legitimately holds the COPY open longer, so the export-specific timeout is the deliberate choice.
FAILURE VISIBILITY, SERVER SIDE (AC#3, server half): backend terminated mid-stream with pg_terminate_backend. The client got HTTP 200 then a truncated transfer (curl exit 18, 77,808,048 bytes). The server logged 'Search export failed mid-stream' with url, rowsSent 370173, bytesSent 77808048, expectedRows 1976463, elapsedMs 21837, and the partial file has exactly 370,173 records, matching the log. A client cancel is logged as 'Export aborted: the client disconnected' and the database backend goes away once the in-flight statement returns. The client half (no partial file saved, error with rows received vs expected) is S2.
AUTH AND RLS (AC#5): no cookie gives 401, a garbage token 401, an expired token 401 'Token has expired', and a refresh token used as access 401 'Invalid token type'. A regular_user (sej@dst.dk) and an admin get the same 188,949 rows for region 03, as the current statistical_unit policies (USING true for both roles) dictate. The export applies the same role and policies as /rest.
EXCEL REFUSAL (AC#4, server half): max_rows=1048575 on the full filter gives 413 with X-Export-Total-Rows 1976463 and the message 'This export has 1976463 rows; at most 1048575 are allowed for this format. Use CSV instead.', before a single row is streamed.
LOCAL-ONLY SHIM: the February dump predates the external_ident_type_enabled / stat_definition_enabled view names that the app reads, so two alias views over the *_active views were created in the LOCAL database only (each commented 'LOCAL-ONLY alias ... drop when done'). This is not a migration and nothing ships with it.
VALIDATION: jest src/app/search/export 66/66, tsc clean, eslint clean, prettier applied. CI for 54be3d809 is recorded in the next note.

S1 CI AND RED/GREEN PROOF, 2026-10-08. CI for 54be3d809: app build & lint success, Images success, Go Test success, Harness Selftest success, Push on master success, Notify success. The Fast Tests (pg_regress) run for it was cancelled by workflow concurrency when the next master push superseded it. That is the SQL suite, which this commit does not touch. Tests for the stream committed in 0a3c5b6 (export-copy-stream.test.ts, 8 tests, fake pg plus COPY). Each load-bearing test was SEEN FAILING with the guarded code removed, then passing with it restored. UNIT: (a) row-count guard disabled -> 2 tests fail ('errors the stream when COPY's row count differs', 'errors when the streamed records differ'). (b) max_rows refusal disabled -> 'refuses before streaming when the count exceeds maxRows' fails. (c) auth.jwt_switch_role call removed -> 'runs as the user's role' and 'propagates an authentication failure' fail. Restored -> 8/8 pass. ROUTE against the dev server and the Norway dump (tmp/421-p2/route-redgreen.sh): GREEN anonymous 401, expired 401, over max_rows 413, at max_rows 200. RED with the route's max_rows dropped -> 'over max_rows -> 413' FAILS (got 200). RED with the role switch removed -> 'expired token -> 401' FAILS (got 500, the token was never verified). Restored -> all PASS. The local-only alias views were created for that run and dropped in the same command (0 left, verified).

CORRECTION: the stream tests named in the previous note landed in commit 699d0409b, not '0a3c5b6'.

S2 LANDED, 2026-10-08, commit 642876ce0 (takeover of the orphaned S2/S3 work after the previous holder failed on an API overload). WHAT IT IS: the client CSV path. The search page and unit-history buttons fetch /api/search/export (the S1 COPY route, the user's own role) and pump the body through app/src/app/search/export/export-download.ts into a sink: a showSaveFilePicker file where available (FileSystemWritableFileStream, writes coalesced to 1 MiB, staged until close so abort leaves nothing), otherwise an in-memory Blob download. Records are counted while streaming and the file is committed ONLY when they equal X-Export-Total-Rows. A short or long stream, a network failure, a server abort, a disk-write failure or a cancel calls sink.abort(), and the error shows rows received versus expected. A missing or non-integer X-Export-Total-Rows refuses the export. Progress shows rows and bytes, and a new 'waiting' phase covers the server-side sort before the first byte. The unit-history button now shows the error text instead of a bare 'Export failed'.
SCOPE, STATED PLAINLY: the orphaned work is S2 ONLY and is coherent for S2. S3 (streaming XLSX Worker ported from tmp/421-xlsx-proto, the 1900 serial unit test, EXCEL_MAX_ROWS consolidation) was NOT started: XLSX still reads JSON from /rest and builds the workbook in memory, guarded by the row cap before the request and again on the rows received. The 'opfs' sink kind is declared but nothing creates it yet (that is S4). The browser path was verified by unit tests, not exercised in a real browser against the Norway dump in this session.
RED/GREEN (owner standard), full log tmp/421-s2-redgreen.log. Each guard in export-download.ts was removed, the suite ran, then the file was restored byte-identical (cmp) and re-run. Baseline 18/18 green. (A) completeness check records !== announced disabled -> RED 2 failed: 'never commits a short export', 'never commits a long export either'; GREEN 18/18. (B1) sink.abort() removed from the mid-stream failure path -> RED 2 failed: 'aborts on a mid-stream network failure', 'aborts when the disk write fails'; GREEN 18/18. (B2) sink abort() made to commit the partial file (memory sink downloads it, writable sink flushes+closes) -> RED 2 failed: 'saves nothing when aborted', 'abort discards buffered bytes and aborts the file'; GREEN 18/18. (C) X-Export-Total-Rows plain-digits guard removed -> RED 2 failed: 'refuses a missing or empty header instead of reading it as 0 rows', 'refuses anything that is not a plain non-negative integer'; GREEN 18/18. (D) filename and MIME dropped (picker without suggestedName/types, memory download named 'download' untyped) -> RED 2 failed: 'suggests the export's filename and restricts the type to its extension', 'downloads every chunk under the export's filename and type on close'; GREEN 18/18. (E1) Excel cap off by one (forgetting the header row) -> RED 1 failed: 'refuses one row more, and the Norway export'; GREEN. (E2) Excel refusal removed -> RED same test; GREEN.
SUITE: pnpm test 21 suites / 179 tests pass; export tests 92/92; pnpm run lint 0 errors (5 pre-existing warnings in unrelated files); pnpm run tsc clean; prettier applied to the test file.
CI: for 642876ce0, Images, Harness Selftest, Push on master and Notify succeeded. app build & lint and Go Test were CANCELLED by workflow concurrency when 610c42995 (461) was pushed 1 minute later. 610c42995 contains 642876ce0 and has an identical app/src tree (the only app/ difference is a demo CSV). On it, app build & lint run 37806233673 (job build-app) and Go Test both succeeded. Fast Tests (pg_regress) are pending; this commit touches no SQL.
REMAINING: S3 entirely (see above). S4: Firefox OPFS sink (stream into navigator.storage.getDirectory(), then hand the File to a normal download, documenting the measured 7.7 s copy for 117 MB), which replaces the in-memory fallback that today holds the whole CSV (about 415 MB on Norway) in browser memory. S5: retire the direct-REST XLSX path once S3 lands (the remaining /rest consumer in use-statistical-unit-export.ts, plus export-completeness.ts and the Content-Range helpers it alone uses), update doc/DEPLOYMENT.md and the export docs. AC#3/#7 client halves still need one real-browser observation on the Norway dump (abort, no file saved, progress).

S3 LANDED, 2026-10-08, commit 1dbc263e8 (implementer tigress). WHAT IT IS: the Excel export no longer reads JSON from /rest or builds the workbook in memory. Both formats fetch /api/search/export (the S1 COPY route). For Excel, the CSV stream is converted to a workbook WHILE it arrives, in a dedicated Worker (xlsx-export.worker.ts, started by create-xlsx-worker.ts with new Worker(new URL(...)), and Turbopack emits it as its own chunk). The converter is app/src/app/search/export/xlsx-stream.ts, PORTED from tmp/421-xlsx-proto/streaming-xlsx.mjs rather than rewritten: the same streaming CSV record parser, inline-string SpreadsheetML with no sharedStrings, native CompressionStream('deflate-raw') with fflate (new dependency fflate ^0.8.3) supplying only the ZIP container and CRC, and fflate deflate as the fallback. The workbook goes to the same sink as CSV (save-picker file or in-memory download) and is driven by the same pumpExportToSink. So Excel inherits every S2 guarantee: it is committed only when the CSV records equal X-Export-Total-Rows, and it is aborted on a network failure, server abort, disk failure, cancel, or Excel refusal. The column order is the route's CSV header order, so the workbook and the CSV always agree. There is no post-transfer conversion phase, and the old 'Building Excel workbook' state is gone.
DIFFERENCES FROM THE PROTOTYPE (deliberate): (1) excelDateSerial also rejects non-calendar dates such as 2024-02-30 (Date.UTC would otherwise normalise them silently), so those stay text. (2) There is no fieldOrder re-mapping, because the COPY route already emits the historical column order, so the converter takes the header as is. (3) A conversion in the Worker reaches the page as an XlsxChunkConverter (write/end/dispose over postMessage with transferred buffers), and an ExcelRefusedError keeps its type and code across the boundary.
EXCEL LIMIT: one sheet holds 1,048,576 rows INCLUDING the header, so 1,048,575 data rows. It is refused at three layers. (a) Before the save dialog and before any request, against the search total (the menu item is also disabled above it, unchanged). (b) By the route: Excel requests carry max_rows=1048575, and the route's 413 message ('This export has N rows; at most 1048575 are allowed for this format. Use CSV instead.') is shown AS IS. (c) On the fly in the writer. A mid-stream refusal propagates unwrapped (ExportRefusedError), so the user reads the refusal, not 'Export interrupted'.
DATES: Excel serials with the 1900 correction (1900-01-01 -> 1, 1900-02-28 -> 59, 1900-03-01 -> 61, plus 1970-01-01 -> 25569 and 2024-01-15 -> 45306), unit-tested. Pre-1900 values stay text.
CONSTANT CONSOLIDATION: EXCEL_MAX_ROWS, EXCEL_MAX_DATA_ROWS and EXCEL_MAX_CELL_CHARS, plus excelDataRowsFit(), now live ONCE in app/src/lib/excel-limits.ts. export-query.ts re-exports them, and the duplicates in progress-download-button.tsx, command-palette.tsx and app/api/import/download/route.ts are gone. SIDE FIX FOUND WHILE CONSOLIDATING: those three compared data rows against 1,048,576 (rows > EXCEL_MAX_ROWS), so they offered and accepted Excel for exactly one data row too many. They now use excelDataRowsFit (<= 1,048,575). The import route message now reads 'Excel holds at most 1,048,575 data rows. Please download as CSV.'
ALSO: pumpExportToSink aborts the file when committing it fails (a workbook whose ZIP end failed is discarded, not left half-made).
RED/GREEN (owner standard), full log tmp/421-s3-redgreen.log. Each guard was broken, the tests run, then every guarded file was restored from tmp/421-s3/orig, checked with cmp (identical), and re-run. Baseline 44/44. (1) 1900 correction removed -> RED 2: 'is one lower before 1900-03-01...', 'writes a valid workbook...'; GREEN 19/19. (2) the writer's on-the-fly row limit removed -> RED 3: 'refuses on the fly at one data row over the limit', 'aborts the file and shows the refusal itself when Excel's limit is crossed mid-stream', 'keeps an Excel refusal a refusal across the worker boundary'; GREEN. (3) the writer limit off by one (> instead of >=) -> RED the same 3; GREEN. (4) shared EXCEL_MAX_DATA_ROWS = EXCEL_MAX_ROWS (header forgotten) -> RED 4: 'defaults to the sheet limit, the header row excluded', 'excelRowLimitError refuses one row more...', 'exportRequestUrl asks the route to refuse...', 'xlsx bounds keeps the hard cap...'; GREEN 70/70. (5) XLSX request without max_rows -> RED 1: 'exportRequestUrl asks the route to refuse an Excel export above the sheet's data rows'; GREEN. (6) the 413 refusal wrapped as 'Export request failed (413)' -> RED 1: 'shows the route's 413 refusal as is'; GREEN. (7) a mid-stream refusal wrapped as 'interrupted' -> RED 2: '...shows the refusal itself...', 'passes a format refusal through unwrapped'; GREEN. (8) no abort when the commit fails -> RED 1: 'aborts the file when committing it fails'; GREEN. (9) XLSX sink abort() commits the target -> RED 2: '...refusal itself...', 'never commits a workbook for a short export'; GREEN. (10) Worker error rebuilt as a plain Error -> RED 1: 'keeps an Excel refusal a refusal across the worker boundary'; GREEN. (11) XML escaping skipped -> RED 1: 'writes a valid workbook: header, typed cells, escaped text'; GREEN.
REAL DATA (production module, Node via jest, input tmp/421-xlsx-proto/out/in-1048575.csv, the prototype's Norway slice): pump + XLSX sink at EXACTLY 1,048,575 data rows: committed, 225,799,800 CSV bytes -> 113,364,276 xlsx bytes, 45.0 s wall, peak RSS 643 MB (jest process; the prototype's 64 MB-heap browser figure is the flat-memory evidence). The independent validator tmp/421-xlsx-proto/validate.py gives testzip CRC OK, sheet XML well-formed, 1,048,576 <row> elements with last r=1048576, openpyxl compared 1,048,575 data rows cell by cell with 0 mismatches, and 1,362 pre-1900 dates kept as text (log tmp/421-s3/validate-prod-1048575.log). At 1,048,576 data rows (in-1048576.csv): refused with ExcelRefusedError 'Excel supports at most 1 048 575 data rows and this export has more. Use CSV instead.', the sink aborted, file 0 bytes.
REAL BROWSER (headless Chromium via Playwright against the Next dev server, through the real search UI; script tmp/421-s3/browser-smoke.mjs). Because the February dump lacks stat_definition_enabled/external_ident_type_enabled and the DB is read-only for this work, the route's response was served by Playwright interception from a 94,140-row Norway CSV slice with X-Export-Total-Rows, and stat_definition_enabled was answered with [employees, turnover]. Observed: (a) the Worker bundle loads (turbopack-worker chunk for xlsx-export_worker_ts). (b) Picker path: suggestedName statistical_units.xlsx with the Excel MIME/.xlsx type, request /api/search/export?...&max_rows=1048575, status 'Downloaded 94 140 rows in 2s', writable ended with close, 10,077,188 bytes, and validate.py found 0 mismatches over 94,140 rows. (c) Download fallback (no picker): file statistical_units.xlsx, 0 mismatches. (d) Announced 94,141 while 94,140 were served: UI 'Export incomplete: received 94 140 of 94 141 rows. The file was not saved.', writable ended with ABORT, 0 bytes. (e) Route 413 with S1's exact message: the UI shows 'This export has 1976463 rows; at most 1048575 are allowed for this format. Use CSV instead.', ABORT, 0 bytes. NOT observed: the route itself serving Excel on this dump (it 500s on the missing *_enabled views without the local-only shim, which I did not recreate), and a real Excel acceptance (the owner's).
SUITE: pnpm test 22 suites / 206 tests; pnpm run lint 0 errors (5 pre-existing warnings elsewhere); pnpm run tsc clean.
CI: for 1dbc263e8, Push on master, Harness Selftest and Notify succeeded, and Fast Tests @ exercised-sha=1dbc263e8 succeeded (37816968936). app build & lint and Go Test were CANCELLED by concurrency when b4f129104 (477 D) was pushed. b4f129104 contains 1dbc263e8 with an IDENTICAL app/ tree (git diff --quiet), and on it app build & lint 37816603967 (build-app) succeeded and Go Test succeeded. Those are the evidence for this commit, stated as such. Images FAILED on 1dbc263e8 and on b4f129104, but only in its seed job: 'pg_restore: cannot revoke MAINTAIN directly from establishment__for_portion_of_valid'. That has failed identically on every master push since at least e1387ff48 (8 runs before this commit). All image builds and manifests, including app, succeeded. This is pre-existing and on the DB side, not caused by S3, and reported to the coordinator.
REMAINING: S4, the Firefox OPFS sink (stream into navigator.storage.getDirectory(), then hand the File to a normal download, documenting the measured 7.7 s copy for 117 MB). Today, without a picker, BOTH formats use the in-memory sink, so a Firefox CSV of the full Norway set holds about 415 MB in memory (a workbook about 113 MB at the sheet limit). The 'opfs' sink kind exists but nothing creates it. S5: the direct-REST path is now unused by the export: export-completeness.ts (Content-Range helpers), composeExportSearchParams/composeExportSelect/exportFieldNames in export-query.ts and their tests have no production caller. Retire them, update doc/DEPLOYMENT.md and the export docs. @protobi/exceljs stays, because the import download route still uses it. AC#3/#7 client halves were observed in a real browser only against an intercepted route (above), not on the live route plus Norway dump.

CORRECTION TO THE S3 NOTE, 2026-10-08 (coordinator caught it; I verified it myself): Fast Tests did NOT run pg_regress for 1dbc263e8 or for b4f129104. In runs 37816968936 and 37817137264, job 'classify' succeeded and job 'pg_regress fast suite' was SKIPPED. A skipped job does not fail the workflow, so the run reads as success. My S3 note cited 'Fast Tests @ exercised-sha=1dbc263e8 succeeded (37816968936)' as evidence. Withdrawn: that run proves nothing about the SQL suite. The valid CI evidence for S3 is app build & lint 37816603967 and Go Test on descendant b4f129104 (identical app/ tree). pg_regress was unavailable for every commit while STATBUS-481 broke Images (seed job). S3 touches no SQL, so the suite is not the relevant gate for it, but no green suite is claimed.

S5 LANDED, 2026-10-08, commit 323aef9e3: the direct-REST export path is retired. Removed: app/src/app/search/export/export-completeness.ts and its test (parseContentRangeTotal, resolveExpectedRows, exportIncompleteError, EXACT_COUNT_PREFER), plus composeExportSearchParams, composeExportSelect, exportFieldNames, exportOrder and ExportBaseData from export-query.ts, with their tests. Those tests included the STATBUS-462 request-boundary invariants, which guarded a PostgREST select that no longer exists. The COPY select's equivalent guard is export-sql.test.ts 'joins the computed names laterally, so rows without them survive'. Kept, because they are in use: parseUnitTypeFilter, exportBaseName, EXCEL_CONFIRM_ROWS and the re-exported Excel limits. @protobi/exceljs is kept, because the import download uses it. Before deleting, I searched the whole repository (app, cli, test, ops, docs; production and tests) and found no unexpected caller. After the commit, rg over app/cli/test/ops for every removed name returns nothing. The comments describing the /rest path were corrected (export-logger.ts, csv-row-counter.ts, unit-history-export-button.tsx). Docs: doc/DEPLOYMENT.md has a new 'Statistical unit export' section (route, authenticator plus jwt_switch_role so RLS applies, one-snapshot count in X-Export-Total-Rows, constant memory, 30 min export statement_timeout, measured Norway timing, completeness and logging, Excel limit, where the file goes and what it costs, proxy buffering). doc/USAGE.md's Excel FAQ states the 1,048,575 limit and the never-save-a-partial-file rule. doc/postgrest-query-audit.md carries an update noting that its export template R21 is retired and its later references describe the audited state. pnpm test 22 suites / 179 tests after the removal, lint 0 errors, tsc clean.

SIDE FINDING, an independent defect fixed in 1dbc263e8 and pinned by a test in e593b401a: Excel for the IMPORT download accepted one data row too many. Three places compared data rows against 1,048,576, the sheet's total including the header, instead of 1,048,575: app/src/app/api/import/download/route.ts ('if (totalRows > 1_048_576)' before building the workbook), app/src/components/progress-download-button.tsx ('rowCount > EXCEL_MAX_ROWS' with a local EXCEL_MAX_ROWS = 1_048_576) and app/src/components/command-palette/command-palette.tsx (the same, local constant). A job with exactly 1,048,576 rows was offered Excel and the route tried to build a sheet that cannot hold header plus rows. All three now use excelDataRowsFit() from app/src/lib/excel-limits.ts (data rows <= 1,048,575). The route message reads 'Excel holds at most 1,048,575 data rows. Please download as CSV.' Test app/src/lib/excel-limits.test.ts: RED with the pre-fix comparison (dataRows <= EXCEL_MAX_ROWS), where 'fits exactly the data rows a sheet can hold below its header, and not one more' fails (1 of 2). GREEN with the file restored from HEAD and compared with cmp (2 of 2). Log tmp/421-sidefix-redgreen.log. The defect predates the export work; it was found while consolidating the constant.

S4 LANDED, 2026-10-08, commit 5bf1dc967: without a save picker, exports stream into OPFS. WHY: Firefox has no showSaveFilePicker, so until S4 both formats were collected in browser memory there. That is about 415 MB for the full Norway CSV (415,392,207 bytes measured through the route) and about 113 MB for an Excel file at the sheet limit (113,364,276 / 113,536,311 bytes measured). WHAT: createOpfsSink (export-download.ts) writes into the Origin Private File System, which is disk-backed with flat memory. Each export gets its own entry. On close it commits the entry and hands the disk-backed File to a normal download. The UI shows 'Saving file…' for the copy to Downloads, a measured one-off cost after completion: 7.7 s for a 117 MB workbook and 3.6 s at 500k rows in Firefox 142, from the feasibility report tmp/421-client-xlsx-feasibility.md. The entry is removed 60 s after the hand-off, or at once on abort. Selection order in the hook: picker (Chromium/Edge over HTTPS), then OPFS (Firefox), then memory only where neither exists (plain HTTP is not a secure context in any browser, and some private windows). doc/DEPLOYMENT.md states this order and the costs.
RED/GREEN (tmp/421-s4-redgreen.log; export-download.ts restored from tmp/421-s4-export-download.orig.ts and compared with cmp after every red). Baseline 30/30. (1) abort leaves the OPFS entry behind -> RED 2: 'is never committed for a short export when driven by the pump', 'on abort, discards the bytes, removes the entry at once and never downloads'; GREEN 30/30. (2) entry never removed after a completed download -> RED 1: 'streams to OPFS, then downloads the committed file under the export's name and removes the entry'; GREEN. (3) every export writes the same entry -> RED 1: 'gives every export its own OPFS entry'; GREEN. (4) no 'Saving file' signal before the copy -> RED 1: the 'streams to OPFS ...' test; GREEN. The red/green ran before a final one-line comment rewording in the same file; diff against the red/green original = that comment line only.
REAL FIREFOX 142 (headless Playwright, through the real search UI; origin allow-listed as secure the way an HTTPS deployment is; export response intercepted, because the February dump lacks the *_enabled views and the DB stays read-only). (a) Excel, 94,140 real rows: picker absent and OPFS present, so the OPFS sink was used. Download statistical_units.xlsx, 10,091,866 bytes, validate.py 0 mismatches over 94,140 rows. One OPFS entry right after, none 65 s later. (b) CSV, 94,140 rows: download statistical_units.csv, byte-identical to the served CSV. (c) Excel at EXACTLY 1,048,575 real rows: 'Downloaded 1 048 575 rows in 31s', download event at 31.9 s, 113,536,311 bytes. validate.py: CRC OK, XML well-formed, 1,048,576 <row>, 0 mismatches over 1,048,575 rows. OPFS entry removed after 65 s. The 'Saving file' phase was not caught by the 50 ms UI sampler because Playwright's headless download hand-off is immediate; the 7.7 s figure is the feasibility measurement, not re-measured here. (d) Short stream (announced 94,141, served 94,140), CSV and Excel: UI 'Export incomplete: received 94 140 of 94 141 rows. The file was not saved.', no download, OPFS empty. (e) REAL MID-STREAM CUT (a local server sends 200 + X-Export-Total-Rows 94140, writes 5,000,000 bytes, then destroys the socket), CSV and Excel: UI 'Export interrupted after 24 034 of 94 140 rows: Error in input stream. The file was not saved.', no download, OPFS empty. /api/logger received level error with format, url, rowsReceived 24034, expectedRows 94140, bytesReceived 5000000, elapsedMs and error (logs tmp/421-s4/cut-firefox-*.log).
SUITE: pnpm test 22 suites / 184 tests, lint 0 errors (5 pre-existing warnings elsewhere), tsc clean.
CI for 5bf1dc967: Images SUCCEEDED (seed fixed by 481), Harness Selftest and Push succeeded. app build & lint and Go Test were cancelled by concurrency; descendant c4203d184 (478) has them green (37820407667, 37820407658), but its app/ differs from 5bf1dc967 only in app/src/lib/database.types.ts (generated types). The Fast Tests pg_regress suite RAN for 5bf1dc967 (37820685605) and FAILED 2 of 113: 016_generate_typescript_types_from_db and 351_statbus_460_unit_existence_rule. Neither involves 421 code. 016 compares the generated database.types.ts with the committed file and 478 then committed a regenerated one. 351 is the 460 test. 421 touches no SQL, migration or generated type. The two later runs (c4203d184, 580433a19) skipped pg_regress again. So no green pg_regress covering these commits exists yet. The first real suite run after 3ce591f16 is the one to read (guppy is reading it).

FINAL ACCEPTANCE ON THE SHIPPED CODE, 2026-10-08, master app tree at 5bf1dc967 (export dir equal to HEAD). The shipped export core openExportStream (authenticator, READ ONLY REPEATABLE READ, auth.jwt_switch_role on a token for jorgen@veridit.no, snapshot count, COPY) ran under Node against the restored Norway dump, filter unit_type=in.(legal_unit,establishment), order name.asc. Announced X-Export-Total-Rows 1,976,463; rows received (production quote-aware counter) 1,976,463; 415,392,207 bytes; 16.6 s wall; no failure. Independent checks: python csv.reader counts 1,976,463 data rows over 41 columns; psql count(*) for the same filter is 1,976,463; the file is byte-identical to S1's measured COPY output (tmp/421-p2/copy-full.csv). Log tmp/421-s4/final-acceptance.log. One local-only caveat, unchanged since S1: the February dump names the column-config views *_active, so the column codes were passed explicitly (tax_ident, stat_ident, employees, turnover) instead of being read from *_enabled. Everything else is the shipped path. (A first attempt under bun stalled in ClientWrite after 168 MB with the backend idle in COPY. I cancelled it, confirmed the backend went away, and reran under Node. This is a bun harness stream issue, not the product's.)

AC#6 EQUIVALENCE, BOUNDED ROW-FOR-ROW, 2026-10-08 (tmp/421-ac6/). Subset: unit_type=in.(legal_unit) AND physical_region_path=cd.03, order name.asc, on the restored Norway dump. OLD path, exactly as shipped before S2/S3: the composed select from export-query.ts at 642876ce0, recovered verbatim, requested from PostgREST as JSON with Prefer count=exact, each value rendered as the old toCSV did (null -> '', else String(v)). Result: 188,949 rows, Content-Range 0-188948/188949, 5.7 s. NEW path: the shipped openExportStream (COPY as the user's role) on the same filter. Result: announced 188,949, received 188,949, 37,326,383 bytes, 4.0 s. Comparison by header name, row by row in order: identical column set (40 columns, none only in one side), 188,949 rows compared, 7,557,960 cells compared, 0 mismatches. The full-set exact count on the shipped code is in the FINAL ACCEPTANCE note: 1,976,463 = announced = python = psql. Together these meet AC#6 as worded. Known, previously documented difference, absent from this subset: PostgREST CSV doubled backslashes in 87 cells of the full set, and COPY writes the stored value.

CLOSE-OUT, 2026-10-08 (tigress). S1 54be3d809 + 699d0409b, S2 642876ce0, S3 1dbc263e8, S5 323aef9e3, S4 5bf1dc967, side-fix test e593b401a. The criteria, each against its evidence above:
AC#1 MET: the full Norway export on the shipped core delivers 1,976,463 of an exact 1,976,463 (FINAL ACCEPTANCE). Any shortfall fails loudly (route guard 699d0409b, client guard 642876ce0, both shown red/green).
AC#2 MET by the clause 'a deliberate export-specific timeout': the export runs under SET LOCAL statement_timeout 30min. Measured wall time is 21.8 s through the route (S1) and 16.6 s on the core today, about 98 s under the 120 s role default it no longer depends on.
AC#3 MET: on a real mid-stream socket cut in Firefox 142 the UI shows 'Export interrupted after 24 034 of 94 140 rows ... The file was not saved.' and no download happens. The client log carries url, rowsReceived, expectedRows, bytesReceived and elapsedMs. The server log carries url, rowsSent, expectedRows, bytesSent and elapsedMs, shown with pg_terminate_backend in S1.
AC#4 MET: the menu item is disabled above 1,048,575, the route answers 413 with the message shown as is, and the writer refuses on the fly. No unbounded workbook: the conversion is streaming, measured at 1,048,575 rows, and 1,048,576 rows is refused with 0 bytes left.
AC#5 already checked. Its wording 'the same /rest path' is superseded by the owner's single-mechanism decision (the COPY route). The substance holds: the same cookie JWT and the same RLS role, anonymous/expired/garbage tokens get 401 (S1).
AC#6 MET: the bounded subset is identical cell for cell (188,949 rows, 7,557,960 cells, 0 mismatches) and the full set has the exact count.
AC#7 MET: rows received against the total and MB received are shown while streaming. The UI phase 'Downloading' was observed at 5.8 s in the Firefox 1,048,575-row run. The reference total is the server-announced exact count, which supersedes the search page total by design.
AC#8 MET: count phase 158 ms, export 21.8 s / 16.6 s, 415 MB (S1 and FINAL ACCEPTANCE).
DoD#1 MET (FINAL ACCEPTANCE). DoD#2 MET (TRANSPORT DECISION plus S1 timeout note). DoD#3 MET (the 2026-10-08 measurement with the 29,470 shortfall is retained above).
CAVEATS, recorded rather than dropped: (1) CI. No green pg_regress covers these commits. Fast Tests skipped pg_regress until 481 landed. The first run that executed it, for 5bf1dc967 (37820685605), failed 2 of 113 in 016_generate_typescript_types_from_db and 351_statbus_460_unit_existence_rule. 421 touches no SQL, migration or generated types; those belong to 478's regenerated types and to 460. The first real suite run after 3ce591f16 is the one that can confirm them (guppy is reading it). The app gates (app build & lint, Go Test) are green on descendants, with the tree differences stated in each note. (2) The browser runs intercepted the export response, because the February dump lacks the *_enabled views and the DB was kept read-only, so the live route was never driven end to end by a browser on this dump. The route itself was driven by curl in S1 and the core by Node harnesses. (3) A real-Excel open of a sheet-limit workbook is still the owner's acceptance; LibreOffice and openpyxl accepted it. (4) The 7.7 s OPFS-to-Downloads copy is the feasibility measurement, not re-measured in this session.
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
