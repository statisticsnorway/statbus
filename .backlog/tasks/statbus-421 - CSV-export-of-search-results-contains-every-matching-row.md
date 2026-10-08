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
PROTOTYPE REUSE IS EXPLICIT, recorded 2026-10-08 at the owner's request. The work in tmp/421-xlsx-proto/ is FEASIBILITY ONLY: it is gitignored, was not written against the app's types or test harness, and must NOT be committed as-is. Slice S3 must PORT it rather than reinvent it. Lift and adapt: streaming-xlsx.mjs, the incremental writer with a streaming ZIP container and streamed sheet XML, including the Excel serial-date rule with the pre-1900-03-01 adjustment for the fictitious 1900-02-29, the C0-character escaping, and the cell and row limit refusals; browser/worker.mjs and browser-run.mjs, the dedicated Worker shape with native CompressionStream deflate-raw and fflate supplying only the ZIP container and CRC; slice-csv.mjs, quote-aware record slicing for exact-row-count fixtures; and validate.py with validate-all.sh, the independent readers (zipfile CRC, expat, openpyxl cell by cell, headless LibreOffice). The report tmp/421-client-xlsx-feasibility.md carries the measured numbers and the constraints, including the Firefox OPFS fallback and its measured copy cost. Reusing those algorithms is expected; rewriting them from scratch is the waste this note exists to prevent. What IS new in the product version: it runs inside the real export route with the user's JWT and the real search filters, uses the app's types and test harness, and ships tests plus docs.
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
