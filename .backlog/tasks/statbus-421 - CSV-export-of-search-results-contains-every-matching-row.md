---
id: STATBUS-421
title: CSV export of search results contains every matching row
status: To Do
assignee: []
created_date: '2026-09-25 14:02'
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
