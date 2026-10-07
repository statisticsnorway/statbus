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
updated_date: '2026-10-07 13:22'
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
## North Star

A dashboard number and a chart on the same box disagree (Establishments 24 vs 2023 ≈ 11), so one of them is wrong or they count different things. The owner needs to know which, with numbers rather than argument, before anything is changed: the answer decides whether this is a wrong *estimate* (a display-honesty bug), a wrong *label* on the time context (a data bug), or two different populations (a wording bug).

## Owner observation, 2026-10-07 (dev.statbus.org)

Time-context selector reads `2023 (Data)`.

- **Dashboard** (`/dashboard`, "Statbus Status Dashboard" → DATA METRICS) says **Establishments 24** (also Enterprises 23, Legal Units 23; last update `2026-10-02 15:41:47 by erik.soberg`; footer `v2026.10.0 (bce5bf39)`).
- **Reports → Units over time**, Establishments, `All Years`, shows bars of roughly **2023 ≈ 11**, 2024 ≈ 24, 2025 ≈ 24, 2026 ≈ 24.

## What is already known (coordinator, read from the code)

`app/src/app/dashboard/statistical-unit-count-card.tsx`:

- it **does** apply the time-context filter (`.lte('valid_from', validOn).gte('valid_to', validOn)` with `valid_on` from `useTimeContext()`), so "the card failed to date filter" is not obviously the cause;
- but it requests `count: "estimated"` and renders that — PostgREST's planner estimate, not a count. The exact value is only fetched on demand (`EstimatedCount` popover → `onGetExact` → `count: "exact"`), cached in `localStorage` under `statbus:exactCount:<key>`.

`app/src/app/reports/unit-count-chart.tsx` renders the per-period series behind the chart (exact period values, `All Years` selector) — a different data path from the dashboard card.

## Hypotheses to test, in order

- **H1 — the estimate is simply wrong.** `count=estimated` derives from the query plan; on a table this small the planner's estimate can be a rounded guess. The real 2023 value is then the chart's ~11, and the dashboard is displaying an estimate as though it were a fact.
- **H2 — label/value mismatch on the time context.** The selected context's `valid_on` may not be a 2023 instant (e.g. the 2026-10-02 import date), so the card counts a different instant than its `2023 (Data)` label implies. The numbers would then be "consistent" but the label would be lying.
- **H3 — different populations.** The chart's period series and the dashboard predicate select different rows (different temporal-inclusion rules), so both are right for their own definition and the wording is what needs fixing.

## What the investigation must produce

A short report with **evidence, not inference**:

1. dev's actual time-context rows: `ident` and `valid_on` for the context shown as `2023 (Data)` (`time_context` is not anon-readable; use the owner's session).
2. the **exact** establishment count on dev for that `valid_on`.
3. what PostgREST returns for `count=estimated` for the very same predicate — if it differs from (2), H1 is demonstrated.
4. which hypothesis holds, stated plainly, with the numbers.
5. the recommended fix and its risk, for the owner to approve.

## Constraints

- Read-only on dev: no writes, no imports, no migrations, no installs. Use the owner's browser session for the authenticated reads; never extract, store or print cookies or tokens.
- Local reproduction is welcome (local box, `localhost:3014/statbus_local`) — say honestly if local data cannot show the divergence.
- **No product-code change and no commit until the owner approves the fix.** This is an investigation first.
- Report as `tmp/458-dashboard-estimate-investigation.md` and summarise in this ticket.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 dev's real time-context rows (ident, valid_on) are recorded, with the exact establishment count for that valid_on.
- [x] #2 count=estimated is compared against count=exact for the identical predicate, and the two numbers are shown.
- [x] #3 The verdict names which hypothesis holds (H1/H2/H3) with the numbers that decide it.
- [x] #4 A recommended fix and its risk are stated for owner approval; no product code is changed and nothing is committed.
- [x] #5 The report exists at tmp/458-dashboard-estimate-investigation.md and the ticket summarises it.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
INVESTIGATION COMPLETE (delegated to wyvern; full report tmp/458-dashboard-estimate-investigation.md). Verdict: H3 HOLDS - two different definitions, neither number is a bug. Card predicate valid_from <= valid_on <= valid_to over statistical_unit records: at valid_on=2023-12-31 exactly 24 establishment records, 13 of which have birth_date=2024-11-01 (not yet born in 2023). Reports/Units-over-time uses statistical_history_def's existence rule (COALESCE(birth_date,valid_from) <= period_end AND valid_until > period_end AND (death_date IS NULL OR death_date > period_end), deduplicated, used_for_counting): 11 for 2023, 24 for 2024/2025/2026. H2 FAILS: y_2023.valid_on = 2023-12-31 (time_context sets year rows to Dec 31). H1 is NOT the cause, though the estimate is genuinely wrong: on dev count=estimated for the same predicate is 23 vs exact 24 (PostgREST returns the planner root Plan Rows), and the card displays the EXACT count (24, no ~ prefix) because EstimatedCount auto-fetches the exact value within seconds. Local box cannot show the business divergence (no establishments; 23 vs 23) but does show estimates being wildly wrong on small tables (0 matching rows -> estimate 72). RECOMMENDATION (owner decision): introduce one server-side definition of 'units existing at an instant' - public.statistical_unit_count(unit_type, valid_on), SECURITY INVOKER, using the same rule as statistical_history_def - and point the three dashboard cards at it (also removes the estimated/exact flapping and the statbus:exactCount localStorage cache). Validated read-only on dev: 2023-12-31 -> establishment 11 / legal_unit 23 / enterprise 23; 2024-12-31 -> 24/23/23, i.e. reproduces the chart bar-for-bar. Costs: count(DISTINCT unit_id) is a real aggregate, measure on the largest deployment; the 2023 card changes 24 -> 11 on purpose; two data-quality cards share the predicate. ALTERNATIVES: (A) if birth_date=2024-11-01 on those 15 source rows is a placeholder rather than a real birth date, fix the data instead and the chart's 2023 rises to 24; (B) relabel the cards to state the validity-window definition, cheapest and zero data risk. OPEN QUESTION ONLY THE OWNER CAN SETTLE: is birth_date 01.11.2024 real? It chooses between the primary fix and Alternative A. SCOPE: the same predicate is used app-wide (Statistical Units list, unit detail pages, both missing-* cards), so this is a convention decision, not a one-card typo. The fix itself is OUT of this investigation ticket (AC4 forbids code changes); a follow-up ticket is needed once the owner picks.
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
