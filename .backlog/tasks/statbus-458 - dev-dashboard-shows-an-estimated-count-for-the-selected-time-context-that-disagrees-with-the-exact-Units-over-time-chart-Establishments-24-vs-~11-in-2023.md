---
id: STATBUS-458
title: >-
  dev dashboard shows an estimated count for the selected time context that
  disagrees with the exact Units-over-time chart (Establishments 24 vs ~11 in
  2023)
status: In Progress
assignee:
  - '@wyvern'
created_date: '2026-10-07 12:43'
updated_date: '2026-10-07 12:44'
labels:
  - app
  - dashboard
  - reports
dependencies: []
priority: medium
ordinal: 386203
---

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
