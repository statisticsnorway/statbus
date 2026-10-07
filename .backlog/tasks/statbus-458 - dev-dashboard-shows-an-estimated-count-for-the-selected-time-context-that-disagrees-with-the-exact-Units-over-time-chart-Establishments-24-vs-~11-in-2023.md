---
id: STATBUS-458
title: >-
  dev dashboard shows an estimated count for the selected time context that
  disagrees with the exact Units-over-time chart (Establishments 24 vs ~11 in
  2023)
status: Done
assignee:
  - '@wyvern'
created_date: '2026-10-07 12:43'
updated_date: '2026-10-07 22:28'
labels:
  - app
  - dashboard
  - reports
dependencies: []
priority: medium
ordinal: 386203
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Done. Investigation of the dev dashboard/card divergence. RESULT: H3 - two different definitions, neither number wrong in itself. The fix (one canonical existence rule for every count) is STATBUS-460.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 dev's real time-context rows (ident, valid_on) are recorded, with the exact establishment count for that valid_on.
- [x] #2 count=estimated is compared against count=exact for the identical predicate, and the two numbers are shown.
- [x] #3 The verdict names which hypothesis holds (H1/H2/H3) with the numbers that decide it.
- [x] #4 A recommended fix and its risk are stated for owner approval; no product code is changed and nothing is committed.
- [x] #5 The report exists at tmp/458-dashboard-estimate-investigation.md and the ticket summarises it.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Report exists at tmp/458-dashboard-estimate-investigation.md; the verdict, the numbers that decide it, the recommendation with its risks, and the one question only the owner can settle are all in the ticket; 5/5 acceptance criteria checked; no product code changed and nothing committed by the investigation.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ANSWER TO THE OWNER'S LOAD-SEQUENCE QUESTION (2026-10-07): it is visible from the import tables, and it is NOT a load-sequence artefact. One file, one batch: job 34 (import_definition 4, 'Establishments for LU (Source Dates)') was created 2026-10-01 09:33:41 with 26 rows, every row at batch_seq = 1; job 33 (definition 2, 'Legal Units (Source Dates)') ran 19 seconds earlier and carries a yearly series (valid_from_raw 2022-01-01 two rows, 2023-01-01 twenty-five, 2024-01-01 twenty-five, 2025-01-01 twenty-four). All 26 rows of job 34 have valid_from_raw 2023-01-01 and valid_to_raw infinity, and the upload table import_job_34_upload has explicit valid_from, valid_to, birth_date and death_date columns, so the file states the window itself. The rows match the committed demo file app/public/demo/formal_establishments_units_with_source_dates_demo.csv exactly, including 15 rows with birth_date 01.11.2024. Unit 17 has TWO rows in that same file, 2023-01-01..2023-12-31 and 2024-01-01..infinity, both with birth_date 01.11.2024, which is the intended semantic that a record window may be narrower than the unit's life. So nothing was loaded for 2023 and then re-loaded for 2024: the same file row pairs a 2023 window with a November 2024 birth date. Two further observations: (a) legal_units_demo.csv carries birth_date 01.11.1924 for the same kind of rows, so these 01.11.YYYY values look like generated demo placeholders rather than real founding dates; (b) no test in test/sql sets a birth_date in 2024 or 2025 at all, confirming that 'window in year N, born in year N+1' is untested. Owner decision reached from this investigation: a unit that has a birth date and is not yet born does not exist and must not be counted, so all counts use one canonical rule - COALESCE(birth_date, valid_from) when no birth date, death_date when present, valid dates otherwise. The fix is filed as STATBUS-460; this ticket stays Done as the investigation.
<!-- SECTION:NOTES:END -->

## Owner observation, 2026-10-07 (dev.statbus.org)

Time-context selector reads **`2023 (Data)`**.

- **Dashboard** (`/dashboard`, "Statbus Status Dashboard" → DATA METRICS) says
  **Establishments 24** (also Enterprises 23, Legal Units 23; last update
  `2026-10-02 15:41:47 by erik.soberg`; footer `v2026.10.0 (bce5bf39)`).
- **Reports → Units over time**, Establishments, `All Years`, shows bars of roughly
  **2023 ≈ 11**, 2024 ≈ 24, 2025 ≈ 24, 2026 ≈ 24.

The owner's question: *how many establishments are there in 2023?* The chart says ~11;
the dashboard says 24 for a context labelled 2023. One of them is wrong, or they count
different things.

## What is already known (coordinator, read from the code at 12:43)

`app/src/app/dashboard/statistical-unit-count-card.tsx`:

- it **does** apply the time-context filter
  (`.lte('valid_from', validOn).gte('valid_to', validOn)` with `valid_on` from
  `useTimeContext()`), so "the card failed to date filter" is not obviously the cause;
- but it requests `count: "estimated"` and renders that, i.e. **PostgREST's planner
  estimate, not a count**. The exact value is only fetched on demand
  (`EstimatedCount` popover → `onGetExact` → `count: "exact"`) and cached in
  `localStorage` under `statbus:exactCount:<key>`.

`app/src/app/reports/unit-count-chart.tsx` renders the per-period series behind the
chart (exact period values, `All Years` selector), which is a different data path from
the dashboard card.

## Hypotheses to test (in order)

- **H1 — the estimate is simply wrong.** PostgREST `count=estimated` derives from the
  query plan; on a table this small (24 establishments) the planner's estimate can be a
  rounded guess. The real 2023 value is then the chart's ~11, and the dashboard is
  displaying an estimate as though it were a fact.
- **H2 — label/value mismatch on the time context.** The selected context's `valid_on`
  may not be a 2023 instant at all (e.g. it is the 2026-10-02 import date), so the card
  counts a different instant than its `2023 (Data)` label implies. The numbers would be
  "consistent" but the label would be lying.
- **H3 — different populations.** The chart's period series and the dashboard's
  `valid_from <= valid_on <= valid_to` predicate select different rows (e.g. different
  temporal-inclusion rules), in which case both are right for their own definition and
  the wording is what needs fixing.

## What the delegated investigation must produce

A short report with **evidence, not inference**:

1. dev's actual time-context rows: `ident`, `valid_on` for the context shown as
   `2023 (Data)` (owner's session can read `time_context`; it is not anon-readable).
2. the **exact** establishment count on dev for that `valid_on` (SQL or
   `count=exact` in the owner's session).
3. what PostgREST returns for `count=estimated` with the very same predicate — if it
   differs from (2), H1 is demonstrated.
4. which hypothesis holds, stated plainly, with the numbers.
5. the recommended fix and its risk, for the owner to approve — do **not** change product
   code before that. Candidate directions to weigh, not to implement silently:
   - request exact counts for these three cards (they are cheap at this size, and the
     exact-count cache already exists), or
   - label the numbers as approximate in the UI (`EstimatedCount` already opens a popover
     for the exact value — does the dashboard make that obvious?),
   - or fix the context's `valid_on` if H2 is the cause.

## Constraints

- Read-only on dev: no writes, no imports, no migrations, no installs. Use the owner's
  browser session for the two authenticated reads above; do not extract or store cookies or
  tokens, and do not print private log contents.
- Local reproduction is welcome and cheap (the local box runs the same code path with
  `localhost:3014/statbus_local`): reproduce the estimated-vs-exact divergence locally if
  the local data can show it, and say so honestly either way.
- No product-code change, no commit, until the owner approves the fix. This ticket is an
  investigation first.
- Report as `tmp/458-dashboard-estimate-investigation.md` and summarise in the ticket.
