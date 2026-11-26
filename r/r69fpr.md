---
id: r69fpr
title: "How a unit's counting rule changed: find when birth date stopped deciding"
state: "doing"
type: feature
priority: ""
assignee: ["jcode-r69fpr"]
labels: []
group: ""
rank: "zzzzzzzzzzzz"
created: 2026-11-26
updated: 2026-11-26
doing_since: "2026-11-26T22:28"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
---

## Goal
Find when and how the rule for whether a unit is counted lost its birth/death-date condition, and state today's full rule.

## Purpose
Owner 2026-11-26: the rule used to be clear SQL where valid_from and birth_date both decide (birth/death narrow counting where set), encoded in a test. On jo, establishment 86 (valid from 2023, born 2024-11-01) is counted in 2023, so the rule was changed at some point, likely by an agent, and glossed over in review.

## Principle
Read-only investigation, evidence first: commits, tests, expected outputs and tickets, quoted with SHAs. No code changes. Report what the rule was, what it is, which commit changed it, under which ticket and by which model, and whether a test's expected output was changed to accept it.

## Details
Inputs that decide counting today, to enumerate: statistical_unit.used_for_counting and how it is derived; status (status.used_for_counting / include_unit_in_reports); valid_from/valid_until; birth_date/death_date; primary flags; legal unit and enterprise inclusion (included_*_ids, excluded_*_ids); power groups. Search: git log -S'birth_date' and -G'used_for_counting' over migrations/ and test/; doc/db for the current definitions; tests 306, 309, 310, 410 and any named for births/deaths or counting. Compare jo's release with master.

## Depends on

## Acceptance
- [x] A note on this task names the commit(s) that changed the birth/death condition, with the before and after SQL, the ticket and model trailer, and the test whose expected output changed with it
- [x] A note states today's complete counting rule as the code implements it, input by input, with the defining function names
- [ ] [Owner] reads the findings and decides whether to restore the old rule; recorded in Notes

## Notes


Owner 2026-11-26 21:29: lobster's counting change (f2gx3m on branch counting/birth-date-and-lu-es-rollup) goes ahead from where we are; if these findings show a more complete rule that was altered, that change is amended to match it. No revert to old code.
FINDINGS (read-only, git+doc/db). 1) THE RULE: a64f4ad38 2026-10-08 'one canonical unit existence rule for every unit count (STATBUS-460)', author Jørgen, no Model/Co-Authored-By trailer. migrations/20261008161441_statbus_460_canonical_unit_existence_rule.up.sql: unit_existence_from(valid_from,birth_date)=SELECT GREATEST(valid_from, birth_date); unit_existence_until(valid_until,death_date)=SELECT LEAST(valid_until, death_date); exists at d iff existence_from<=d<existence_until. Before it the chart spelled it inline since e1380f8cc (2025-09-13): COALESCE(lvc.birth_date, lvc.valid_from) <= v_curr_stop AND (lvc.death_date IS NULL OR lvc.death_date > v_curr_stop). Test: test/sql/351_statbus_460_unit_existence_rule.sql + test/expected/351_statbus_460_unit_existence_rule.out, introduced in a64f4ad38; 351.3 asserts exactly jo's case (Statistics Denmark ES, valid_from 2023-01-01, birth 2024-11-01, absent in 2023). 2) THE RULE WAS NOT CHANGED: today doc/db unit_existence_from/until still read GREATEST/LEAST; later edits of 351.out (524669e21, a4fa1e04f, 4c0ae5253, ebd890fa6) only touch a history query shape and sql_saga NOTICE lines, no expected count changed. No commit removes a birth/death condition (git log -G on birth/death comparisons in migrations shows only history functions). 3) THE ACTUAL GAP: the rule was applied to counts (cards, list, chart, drilldown c459edf82 STATBUS-475, quality) but never to stat rollups. timeline_legal_unit_def_for establishment_aggs: jsonb_stats_merge_agg(tes.stats_summary) FILTER (WHERE tes.used_for_counting) joined on from_until_overlaps(t.valid_from,t.valid_until,tes.valid_from,tes.valid_until), no birth/death; same in timeline_enterprise_def (LU and ES aggs) and timeline_power_group_def. That predates 460 (FILTER form since 439d5b730 2026-02-05, from include_unit_in_reports c6aec81e6 2025-02-10). So est 86 is not COUNTED in 2023 but its stats ARE SUMMED into LU 89 in 2023. Nearest commit touching that line: 6561172b7 2026-11-24 ca6dk5 'a legal unit's stats cover its establishments' Model: claude-opus-5-5/high: before: COALESCE(public.jsonb_stats_merge(esa.stats_summary, basis.stats_summary), ...); after: COALESCE(public.jsonb_stats_covers(own => basis.stats_summary, parts => esa.stats_summary), '{}'). It did not add or drop a birth filter; it changed expected 109,302,303,306,309,310 (stats summaries only, as its message says). It is in no tag (git tag --contains empty). 4) JO: could not read jo's upgrade record read-only from here; every tag since v2026.10.1 (v2026.11.5, .6, .7-rc.01) contains a64f4ad38, so jo has the existence rule for counts and, whatever its tag, sums unborn establishments' stats (pre-ca6dk5 sum: 23+0+2=25 matches jo, consistent with a released tag without 6561172b7).
TODAY'S COUNTING INPUTS: (a) status.used_for_counting (renamed from include_unit_in_reports 44ee7f50a) -> st.used_for_counting in timeline_establishment_def_for / timeline_legal_unit_def_for; enterprise: COALESCE(enplu.used_for_counting, enpes.used_for_counting) of the primary LU/ES (timeline_enterprise_def); power group: true AS used_for_counting (timeline_power_group_def). Copied to statistical_unit.used_for_counting via statistical_unit_def. (b) validity: record valid_from/valid_until; rollups join children by from_until_overlaps. (c) existence: unit_existence_from/until(birth/death), exposed as existence_from/existence_until(statistical_unit|legal_unit|establishment); used by dashboard cards, search list/export, detail SQL, statistical_history_facet_delta_contribution (exists/countable/births/deaths), statistical_unit_facet_def drilldown, quality_finding_derive. NOT used by any timeline_*_def stats rollup. (d) primary flags: primary_for_enterprise picks the enterprise's representative LU/ES (and its status); primary_for_legal_unit only descriptive. (e) included_/excluded_*_ids: array_agg FILTER (WHERE [NOT] child.used_for_counting) in LU (establishments), enterprise (LUs, ESs), power group (LUs, enterprises); included_legal_unit_ids=[self] when used_for_counting. (f) stats: child stats_summary merged FILTER (WHERE used_for_counting); LU uses jsonb_stats_covers(own, parts) since 6561172b7, enterprise/PG use jsonb_stats_merge_agg. (g) import gates: STATBUS-461 610c42995 rejects rows whose life cannot overlap the validity; STATBUS-573/580 warn when timeline starts after birth in same year.
check 1: Notes: the existence rule (a64f4ad38, test 351) is intact; no commit removed birth/death; the gap is rollups never applying it; nearest change 6561172b7 ca6dk5 claude-opus-5-5/high with before/after SQL and expected outputs 109/302/303/306/309/310
check 2: Note 'TODAY'S COUNTING INPUTS' lists each input with defining function
## History
- 2026-11-26T22:28 todo -> doing/active (take)
