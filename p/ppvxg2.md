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
On Reports → Map a statistician sees each region's circle sized by units or a statistical variable, for the chosen unit types.

## Purpose
Counting units shows where businesses are registered; sizing by employees or turnover shows where activity is. Raised with the owner during the 5nq78t map work.

## Principle
Sums come from the same filter and existence rule as the list; a variable that does not add up across units is not offered.

## Details
Owner 2026-11-27 15:08-16:00: not on the search map (it has enough interaction); a focused Reports map beside the Regions map, unit map and search map. Name: Map, at /reports/map, last in the Reports menu. Interaction agreed: one circle per region at the current level (counties first) on the Regions map's look; 'Size by' Units or a variable from stat_definition_enabled that adds up; unit-type legend checkboxes; click goes in, trail above, eye and X as on the Regions map; list beside ranked by the measure with values, a row goes in; the page time frame; each region row links quietly to these units in Search. Reads statistical_unit_facet (count, stats_summary per region and time). Later, to see in use: distinct icons for the unit map and the variable map so each can jump to the other; from Drilldown to the unit map; from Variables Over Time to this map. Erik's PR #325 variable features (circle by variable, popup values, legend sums) land here; keep PR #325 open until then.

## Depends on

## Acceptance
- [ ] ~~[Owner] Decides whether circles can be sized by a variable, and which variables; recorded here~~ (not relevant: settled by the owner 2026-11-27 15:08-16:00: Units or any summable variable of stat_definition_enabled (Goal, Details), hibiscus, 2026-11-27)
- [ ] ~~With a variable chosen, each circle's size follows the variable's sum for the region, equal to a SQL sum with the same filter (jest on the helper, SQL comparison recorded)~~ (not relevant: split into one check per job: items 3 and 4, hibiscus, 2026-11-27)

## Notes

2026-11-27 16:03 (hibiscus, from rabbit) Facet stats_summary per unit type follows lu_es_rollup after counting lands (jsonb_stats_merge_agg of statistical_unit.stats_summary, legal unit by jsonb_stats_lu_es_rollup): the map reads it and never recomputes. One unit type at a time is right (no total across types; enterprise is the top-level total). Build now; do not merge before counting is on master (rabbit DMs the SHA). On-screen words sum and max, never euphemisms.


## History
- 2026-11-27T17:05 todo -> doing/active (take)
