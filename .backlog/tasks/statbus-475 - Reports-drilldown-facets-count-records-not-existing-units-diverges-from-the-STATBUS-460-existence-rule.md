---
id: STATBUS-475
title: >-
  Reports drilldown facets count records, not existing units (diverges from the
  STATBUS-460 existence rule)
status: In Progress
assignee: []
created_date: '2026-10-08 16:00'
updated_date: '2026-10-16 13:34'
labels:
  - reports
  - data-model
dependencies: []
priority: medium
ordinal: 401204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
The Reports drilldown counts existing units by the same rule as the dashboard, the Statistical Units list and the Units-over-time chart, so every "how many units" screen agrees.

### Zoom out
STATBUS-460 made one SQL definition of "a unit exists at an instant" (birth and death dates bound a unit's life inside each record's window) and switched every unit-count screen to it, except the Reports drilldown. The drilldown reads a precomputed facet table built from each record's validity window, so it kept counting records, not existing units, and disagreed with the chart for units born after their record starts or dead before it ends.

The fix moves the rule into the facet derivation itself: each record contributes over its existence window, not its record window. Records whose life never overlaps their window exist at no instant and contribute nothing. Event counts, variable aggregates, one unit's own timeline and classification counts answer different questions and are deliberately not this rule (screen inventory in the notes).

### Zoom in
- **Found:** while implementing STATBUS-460 on 2026-10-08. `public.statistical_unit_facet_def` grouped by record window, and `statistical_unit_facet_drilldown` filtered `valid_from <= valid_on < valid_until`, with no birth or death date. On dev at 2023-12-31 that kept counting the 13 not-yet-born STATBUS-458 demo establishments.
- **Shipped:** `c459edf82` (migration `20261008202243_statbus_475_drilldown_facets_follow_the_existence_rule`). Both derivation paths, `worker.derive_statistical_unit_facet_partition` (production) and the `statistical_unit_facet_def` view, use `[unit_existence_from, unit_existence_until)`. Table shape, unique key and reduce are unchanged. In v2026.10.1.
- **Proof:** test `353_statbus_475_drilldown_facets_follow_existence_rule` on the 458 demo rows plus a legal unit that dies inside its window. RED with the old derivation (2023-12-31 establishments 22 vs chart 12; the dead unit still counted); GREEN with drilldown equal to chart in every bar (2023: 24/24/12; 2024: 23/23/22), and region, status and country breakdowns each summing to the total. Fast Tests `37845723194`, 117/117. One existing expected output moved by the rule itself (107: a unit dying on 2012-12-31 now ends its facet on 2012-12-30).
- **Timing:** measured on the Norway dump before and after (notes); derivation got no slower.
- **Now observable:** v2026.10.1 contains `c459edf82` and was deployed to dev on 2026-10-15 13:08 UTC.

### Closing review
- **Memory:** none needed.
- **Documentation:** `doc/data-model.md` "Unit existence and record validity" names the drilldown (STATBUS-460 section).
- **Cleanup:** none.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 statistical_unit_facet (or its drilldown) counts a unit at valid_on iff it exists by the STATBUS-460 rule; the 458 demo rows are absent from the 2023 drilldown and present in 2024
- [ ] #2 On dev the drilldown total equals the dashboard card and the Units-over-time chart for 2023-12-31 and 2024-12-31
- [x] #3 pg_regress covers a unit born after its record window starts and a unit that died inside its window, in the drilldown
- [x] #4 Facet derivation time on the Norway dump is measured before and after and recorded in the ticket
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
IMPLEMENTED as c459edf82 (migration 20261008202243_statbus_475_drilldown_facets_follow_the_existence_rule, test 353).
DESIGN: the facet window is the unit's EXISTENCE window within each record, [public.unit_existence_from(valid_from, birth_date), public.unit_existence_until(valid_until, death_date)), with valid_to = end - 1 day, in both derivation paths: worker.derive_statistical_unit_facet_partition (production, hash-partitioned staging then reduce) and the statistical_unit_facet_def view (public.statistical_unit_facet_derive). Records whose life does not overlap their window are left out (they exist at no instant). The table shape, its unique key, the reduce MERGE, the dirty-hash-slot machinery and statistical_unit_facet_drilldown are UNCHANGED: the drilldown's existing valid_from <= valid_on < valid_until now applies the canonical rule. A one-shot rebuild in the migration (TRUNCATE staging, then a full collect_changes, the rc48 pattern) re-derives facets on any box with data, so no box keeps serving record counts until its next import.
TEST 353 (STATBUS-458 demo rows, plus a legal unit that dies 2024-06-30 inside its window). RED with the old derivation: drilldown vs chart at 2023-12-31 establishment 22 vs 12; at 2024-12-31 enterprise 24 vs 23 and legal_unit 24 vs 23; Statistics Denmark ES counted in its region at 2023-12-31 and 2024-10-31; the dead legal unit's region count 5 at 2024-06-29 and still 5 at 2024-06-30. GREEN: drilldown = chart in every bar (2023: 24/24/12; 2024: 23/23/22); the region, status and country breakdowns each sum to the total; Statistics Denmark 0, 0, then 1 from 2024-11-01; dead unit 5 then 4 from 2024-06-30.
EXISTING EXPECTED OUTPUT MOVED, EXPLAINED: 107_load_and_verify_history_functions only. Its fixture legal unit 823573673 (KRANLØFT ENK) has record window 2010-01-01..2012-12-31 and death_date 2012-12-31, so its existence ends ON 2012-12-31 (death_date > d is false that day) and its legal_unit and enterprise facet rows now end valid_to 2012-12-30 instead of 2012-12-31 (the rows reorder accordingly). That is the rule, not a regression. Fast suite otherwise green: 116/117 with only 306, the known local float artifact (variance .41 vs .38) that CI judged green on the committed expected output; not blessed.
TIMING (AC #4), Norway data: the 3,113,504 statistical_unit rows from the restored February dump, copied into a scratch clone of the current seed (hash_slot and stats_summary recomputed with today's functions), running the REAL worker procedures (all 256 hash partitions of derive_statistical_unit_facet_partition, then statistical_unit_facet_reduce). BEFORE: derive 110.5 s / 101.1 s, reduce 28.6 s / 40.7 s, 3,049,022 staging rows, 381,265 facet rows, drilldown 0.57 s / 0.44 s. AFTER: derive 85.8 s / 95.8 s, reduce 38.7 s / 38.6 s, 3,049,022 staging rows, 381,276 facet rows (+11: a few windows split at birth or death), drilldown 0.41 s / 0.41 s. The drilldown totals at 2026-10-08 (EN 1,134,844, LU 1,134,844, ES 825,126) equal the existence-rule count from statistical_unit directly. No regression in time.

SCREEN INVENTORY (what each count-showing screen counts; rule = STATBUS-460 existence):
| screen | source | counts | rule? |
| Dashboard Enterprises/Legal Units/Establishments cards | statistical_unit existence_from/until + used_for_counting | existing countable units | yes (460) |
| Dashboard Units Missing Region / Missing Activity Category | statistical_unit existence filter | existing LU+ES lacking region / activity | yes (460) |
| Statistical Units list (/search) and its CSV/XLSX export | statistical_unit existence filter | existing units | yes (460) |
| Unit detail pages (header, details, hierarchy, stats) | legal_unit/establishment existence filter; *_hierarchy, statistical_unit_enterprise_id, statistical_unit_stats, relevant_statistical_units | the unit if it exists at the context | yes (460) |
| Reports Units over time (/reports) | statistical_history countable_count via statistical_history_def / _facet_def | existing countable units at period end | yes (always did; now via the shared functions, 460) |
| Reports History changes (/reports/history-changes) | statistical_history (births, deaths, name/activity/... change counts) | EVENTS between period ends of existing units | distinct case: event counts, not a stock |
| Reports Statistical variables (/reports/statistical-variables) | statistical_history stats_summary | sums/means of variables (employees, turnover) of existing units | distinct case: variable aggregates over the existing set |
| Reports drilldown (/reports/drilldown) | statistical_unit_facet via statistical_unit_facet_drilldown | existing countable units per facet | yes (475) |
| Unit history chart on a detail page | statistical_unit_history_highcharts | one unit's own variables over its record windows | distinct case: a single unit's timeline, not a count of units |
| Dashboard Regions / Activity Categories / Custom Activity Categories / Statistical Variables cards | region, activity_category_enabled(_custom), stat_definition | CLASSIFICATION rows (codes), not units | distinct case: classification counts |
| *_used views (region_used, sector_used, ...) | statistical_unit any record | which classification codes are used by any unit at any time | distinct case: code usage, time-independent by design |

CI: c459edf82 Images 37844915411 SUCCESS (the seed round trip, effective-ACL digest and restored-seed types check passed with the 475 migration), and Go Test, app build & lint and Harness Selftest succeeded. Fast Tests 37845723194 on a8faa8142 (first-parent descendant; c459edf82's own run 37845546975 was cancelled by that push) ran job 'pg_regress fast suite' = SUCCESS: seed restored (migration 20261008202243), '# All 117 tests passed.' including ok 117 353_statbus_475_drilldown_facets_follow_existence_rule, ok 29 107_load_and_verify_history_functions and ok 14 016. Left In Progress until AC #2 is observed on dev (same as 460).

2026-10-15: v2026.10.1 contains a64f4ad38 (460) and c459edf82 (475) and was deployed to dev on 2026-10-15 13:08 UTC (Deploy to dev run on 3b17af171, success). AC #2 can now be observed: dev drilldown total vs dashboard card vs Units-over-time chart at 2023-12-31 and 2024-12-31.

### AC2 status (2026-10-16)
Card and chart totals on dev agree (see STATBUS-460 notes). The Units-over-time chart carries partition points beside the totals (STATBUS-513); the drilldown comparison is completed together with 513 on dev.
<!-- SECTION:NOTES:END -->
