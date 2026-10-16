---
id: STATBUS-460
title: >-
  Every unit count uses one canonical existence rule (birth and death dates when
  present, valid dates when not)
status: In Progress
assignee: []
created_date: '2026-10-07 22:27'
updated_date: '2026-10-16 13:34'
labels:
  - app
  - dashboard
  - data-model
dependencies: []
priority: high
ordinal: 387204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
"How many units exist at this date" has one answer in StatBus: one SQL definition decides whether a unit exists at an instant, and every screen that counts or lists units uses it.

### Zoom out
A unit's record can be valid over a wider window than the unit's own life. A record valid from 2023 can describe a unit whose birth date is 2024-11-01. Counting records that cover an instant answers "which records are valid then"; counting existing units answers "which units were alive then". Owner decision, 2026-10-07: "if it has a birth date and it is not yet born, it does not yet exist. It should not be there and it should not be counted."

The rule: a unit exists at `d` iff `COALESCE(birth_date, valid_from) <= d AND (death_date IS NULL OR death_date > d) AND valid_until > d`, at most one record per unit. Defined once in SQL and reused, so the cards, the list, the detail pages and the chart can never disagree in kind. The import side keeps data consistent with the rule (STATBUS-461, Done). The Reports drilldown follows the same rule under STATBUS-475.

### Zoom in
- **Incident, STATBUS-458 on dev:** at time context 2023 the dashboard cards showed 24 establishments while the Reports Units-over-time chart showed 11. The 13-unit gap was exactly the demo establishments with `valid_from 2023-01-01`, `valid_to infinity` and `birth_date 2024-11-01`. The cards counted records; the chart used existence.
- **Shipped:** `a64f4ad38` (migration `20261008161441_statbus_460_canonical_unit_existence_rule`): `public.unit_existence_from` = `GREATEST(valid_from, birth_date)` and `public.unit_existence_until` = `LEAST(valid_until, death_date)`, exposed as computed fields `existence_from`/`existence_until`. Switched: the dashboard unit cards (existence plus `used_for_counting`, equal to the chart's `countable_count`), both missing-region and missing-activity cards (they link to the list, so they count what it shows), the Statistical Units list and its export, and the unit detail pages. Documented in `doc/data-model.md` ("Unit existence and record validity").
- **Proof:** `test/sql/351_statbus_460_unit_existence_rule.sql` loads the same demo files as dev (the 458 rows). Run first with the old record predicate it was RED (2023-12-31 card 22 vs chart 12, a not-yet-born unit on the list and detail page); with the rule it is GREEN, card equal to chart bar for bar, and covers birth inside the window and death ending existence. First complete CI run including it: Fast Tests `37829021787` (116/116).
- **Timing:** on the restored Norway dump (3.1 million `statistical_unit` rows), card exact counts take 0.23 to 0.27 s and the list's first page 0.47 s.
- **Why the test's numbers differ from dev's:** STATBUS-461 repaired the demo file (one birth date moved a year), and passive units are not `used_for_counting`. Read-only on dev's data, the rule gives 11/23/23 at 2023-12-31 and 24/23/23 at 2024-12-31.
- **Now observable:** v2026.10.1 contains `a64f4ad38` and was deployed to dev on 2026-10-15 13:08 UTC (Deploy to dev run on `3b17af171`, success).

### Closing review
- **Memory:** none needed.
- **Documentation:** done in `doc/data-model.md`.
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 One canonical SQL definition of 'unit exists at instant d' is documented in the repo and implemented once (for example public.statistical_unit_exists_(unit_type, instant) or an equivalent view), using COALESCE(birth_date, valid_from) <= d, (death_date IS NULL OR death_date > d) and valid_until > d, deduplicated per unit.
- [ ] #2 The dashboard cards (Establishments, Legal Units, Enterprises) use that definition: on dev at 2023-12-31 they show 11 / 23 / 23 and at 2024-12-31 they show 24 / 23 / 23, matching the Reports chart bar for bar.
- [x] #3 The Statistical Units list and the unit detail pages use the same rule, so a unit born after the selected context instant is not listed for that context.
- [x] #4 The two data-quality cards that shared the old record-validity predicate (Units Missing Region, Units Missing Activity Category) use the existence rule, so they count what the Statistical Units list shows
- [x] #5 A pg_regress test covers a unit whose record window is valid_from 2023-01-01 with valid_to infinity and birth_date 2024-11-01: absent from the 2023 count, present in the 2024 count. A second case covers birth_date inside its own window (valid_from 2024-01-01, birth_date 2024-11-01) and IS counted for 2024.
- [x] #6 Two tests prove a birth date can no longer leak into an earlier period: (1) the case above with a later year, (2) a death date in the window (existence ends, the unit is gone from later counts even though the record still covers the instant).
- [x] #7 The estimated-vs-exact flapping is resolved: the card no longer shows a count that can disagree with the chart in kind, and any remaining estimate uses the same predicate.
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 Measured on the largest available dataset (the no dump) that the existence predicate is fast enough for the dashboard, with the timing recorded in the ticket.
- [x] #2 doc/data-model.md (or the closest data-model doc) names the canonical existence rule and lists the screens that use it.
- [x] #3 The 458 example rows are used as the worked example in the test, so the regression is traceable to this ticket.
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Evidence
- **AC1, AC3-7, DoD 1-3:** `a64f4ad38`; test 351 RED with the old predicate, GREEN with the rule; Fast Tests `37829021787` (116/116). Timing measured 2026-10-08 on the Norway dump.
- **AC2:** open. Owner condition (2026-10-08): close only after a release candidate containing `a64f4ad38` is observed on dev. That precondition is met as of 2026-10-15 13:08 UTC (v2026.10.1 on dev). Next: open the dev dashboard at time contexts 2023 and 2024 and record the card numbers beside the Reports chart.
- **History:** the full implementation diary (prototype, timing, AC mapping, CI verdicts, 481 follow-ups) is in Git history of this file, last full version at `03f365be5`.

### AC2 observed on dev (2026-10-16, v2026.10.2-rc.01, read-only, tmp/460-dev-cards.sql)
The card query (existence_from <= d < existence_until AND used_for_counting) returns 2023-12-31: establishment 11, legal_unit 23, enterprise 23; 2024-12-31: 24, 23, 23. Exactly the expected values.
The chart's period totals (statistical_history rows with hash_partition IS NULL) are the same: 11/23/23 and 24/23/23.
Not yet bar for bar: statistical_history_highcharts also sends one point per hash partition (STATBUS-513), so the chart has extra points beside each total. AC2 is checked when 513 lands on dev.
<!-- SECTION:NOTES:END -->
