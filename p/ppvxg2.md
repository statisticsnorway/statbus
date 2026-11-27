---
id: ppvxg2
title: "Reports has a Map of statistical variables by region"
state: "doing"
type: feature
priority: ""
assignee: ["hibiscus"]
labels: []
group: ""
rank: "zzzzzzzzzzzy"
created: 2026-11-27
updated: 2026-11-27
doing_since: "2026-11-27T17:05"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
On Reports → Map a statistician sees each region's circle sized by units or a statistical variable, for one unit type at a time.

## Purpose
Counting units shows where businesses are registered; sizing by employees or turnover shows where activity is. Raised with the owner during the 5nq78t map work.

## Principle
Totals are read as stored (statistical_unit_facet, built from statistical_unit.stats_summary, which follows each variable's lu_es_rollup); the map never recomputes them. One unit type at a time, as the other Reports: establishments are parts of legal units and legal units of enterprises, so adding types counts the same people twice. Only variables that are summed (int, float) are offered.

## Details
Owner 2026-11-27 15:08-16:00: not on the search map (it has enough interaction); a focused Reports map beside the Regions map, unit map and search map. Name: Map, at /reports/map, last in the Reports menu. Interaction: one circle per region at the current level (counties first) on the Regions map's look; 'Size by' Units or a summable variable from stat_definition_enabled; unit-type tabs as on the other Reports (one type at a time, rabbit 2026-11-27: no total across types); click goes in, trail above, eye and X as on the Regions map; list beside ranked by the measure with values, a row goes in; the page time frame; each region row links quietly to these units in Search. Reads statistical_unit_facet (count, stats_summary->var->>sum per unit type, region path and valid_on).

## Depends on

## Acceptance
- [ ] ~~[Owner] Decides whether circles can be sized by a variable, and which variables; recorded here~~ (not relevant: settled by the owner 2026-11-27 15:08-16:00: Units or any summable variable of stat_definition_enabled (Goal, Details), hibiscus, 2026-11-27)
- [ ] ~~With a variable chosen, each circle's size follows the variable's sum for the region, equal to a SQL sum with the same filter (jest on the helper, SQL comparison recorded)~~ (not relevant: split into one check per job: items 3 and 4, hibiscus, 2026-11-27)
- [ ] Reports → Map is last in the Reports menu; it opens on the country's top regions with one circle per region and a list beside it ranked by the measure, seen in Firefox
- [ ] A jest test on the helper: each region's value is the sum of its facet rows for the unit type and variable, region paths grouped by the current level
- [ ] On the test slot, the map's value for a region and variable equals a SQL sum over statistical_unit_facet for the same unit type, path and valid_on; query and numbers recorded here
- [ ] Unit-type tabs and Size by change the circles and the list; a click on a circle or a row goes in, the trail and X go back up; each row links to these units in Search, seen in Firefox
- [ ] [Owner] approves the page in Firefox

## Notes

2026-11-27 16:03 (hibiscus, from rabbit) Facet stats_summary per unit type follows lu_es_rollup after counting lands (jsonb_stats_merge_agg of statistical_unit.stats_summary, legal unit by jsonb_stats_lu_es_rollup): the map reads it and never recomputes. One unit type at a time is right (no total across types; enterprise is the top-level total). Build now; do not merge before counting is on master (rabbit DMs the SHA). On-screen words sum and max, never euphemisms.


## History
- 2026-11-27T17:05 todo -> doing/active (take)
