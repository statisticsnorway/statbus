---
id: ppvxg2
title: "Reports has a Map of statistical variables by region"
state: "doing"
type: feature
priority: ""
assignee: ["hibiscus"]
labels: []
group: ""
rank: "zzzzzzzzzzzx"
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


Erik's PR #325 variable features (circle by variable, popup values, legend sums) land here; keep PR #325 open until then. Later, separate from this task: icons so the unit map and this map jump to each other; Drilldown to the unit map; Variables Over Time to this map.
2026-11-27 16:09 design study before building (owner: think it through together, prototype in PostgREST). Read: jsonb_stats README (stats_agg exact mergeable count/sum/sum_sq, stats_delta in/out), derive-pipeline.md (facet = date ranges, additive stats_delta so no min/max), statistical_history_facet_delta comments (monthly deltas, stock = running sum), existing computed fields. Measured as a signed-in browser (tmp/ppvxg2-rest-sum.mjs, -rest-sum.log, -rest-rpc.log): (A) rpc/statistical_unit_facet_drilldown already returns per child region count + merged stats_agg (jsonb_stats_merge_agg): top level 2.7 s (it also computes activity, sector, status, legal form, country), region 03 0.17 s, 46 establishments 0.26 s; national enterprise employees 3,892,227. (B) PostgREST aggregate statistical_unit_facet?select=physical_region_path,count.sum(),employees:stats_summary->employees->sum::numeric.sum() 0.73 s, sums only. (C) not yet built: a focused function per region level returning rows, so PostgREST selects/orders/filters on it.
2026-11-27 16:18 prototype by worker blowfish: tmp/ppvxg2-proto.md, live page /reports/map-proto (uncommitted, trial functions ppvxg2_proto_* in the test slot DB). Top level enterprise: A drilldown RPC 2.1-2.6 s; B facet aggregate 0.13-0.2 s (sums, browser rolls up); C computed relationship 0.17-0.34 s (cannot order by the aggregate, nested values); C' RPC rows with merged stats_agg 0.45-0.94 s (sum, mean, coverage, coords, orderable). All four match a direct SQL sum per county. Awaiting the owner's choice in Firefox.
2026-11-27 16:29 rabbit asked to hold pushes to master ~15 min while counting+quality (1a6a62288, migrations 20261127162600/162610/162620) run their pre-merge suite; any ppvxg2 migration gets a later timestamp. Page moved to /reports/map (owner: build where it belongs), menu entry Map added, uncommitted.
2026-11-27 16:38 owner: prototype zoom-driven region depth in this map only (zoom in past a level enters the region at the view's centre, out goes up; at the lowest level the region's units, by region path prefix); port to other maps only if it works well, not hastily. Also wanted, to prototype as real views: picking one or several variables, a spider of the picked variables around a region, a radar chart (blowfish), the trail over a Selected box as on the other maps, sizes named in full (Number of enterprises / Total employees).
2026-11-27 16:50 page rebuilt around real views (uncommitted: app/src/app/reports/map/{page.tsx,read.ts,variable-spider.tsx}, menu entry in reports/layout.tsx): Size by 'Number of <units>' / 'Total <variable>', variable ticks, spider of the picked measures round a region (eye or click), trail over a Selected box with own totals, mean and coverage, X up, row/double click in, lowest level lists the region's largest units + Search link, zoom-drives-level switch off by default, read picker B/C′ with timing. Owner trying it now; the slot's migrate to 866d8e3fc and full derive wait until he has.
2026-11-27 17:08 owner feedback 17:00 fixed and observed in tab 145: (1) zoom-drives-level no longer snaps back: only user zooms (originalEvent) change the level, a step made by zooming does not re-frame, a frame keeps the zoom inside the level's band; zoom in over Bergen -> Norway › Vestland at 6.8, out to 5.0 -> Norway, zoom kept. (2) fit button (⤢) frames all circles. (3) the picked region and its spider stay on unit-type change (Vestland: Establishments 91,868/405,923 employees -> Enterprises 121,507/422,321). (4) Search is an icon on the Selected box and each row; it opens /search?physical_region_path=46&unit_type=...&order=employees.desc.nullslast when sized by a variable. Erik's PR #325 statistical_units.html studied (tmp/pr325/): stat radio buttons from stat_definition_enabled, cluster labels show the stat's sum, colour ramps by stat per unit type, popup with coloured header, region, activity, stat values; legend with per-type stat sums.
2026-11-27 17:39 owner 'let's explore' Erik's ideas: added as 'Try' switches on /reports/map, all off by default: (a) every ticked figure on the map labels (e.g. Oslo 188,463 enterprises / 888.6K employees), (b) all unit types side by side in the Selected box (one facet read grouped by unit_type; Norway enterprises 1.1M/3.9M employees, legal units 1.1M/3.9M, establishments 823.8K/3.4M; never added across types), (c) unit cards at the lowest level (Erik's popup: header in type colour, place, activity code, every variable). Radar from blowfish (region-radar.tsx) mounted below the map: tick a row's box to compare; 'share of largest' axes = number of units, each variable's total, its mean per unit and % of units reporting it; white background (was black). Observed in tab 145 with Oslo, Vestland, Rogaland.
2026-11-27 20:20 owner 20:16: (1) radar below the map was out of view -> now a card over the map's lower-left corner while regions are compared, X clears; (2) the search icon read as zoom -> a list icon (List) on the Selected box and rows, opens the units in Search; (3) a row click selects it for comparison (checkbox shown at the row start), going in is a › chevron at the row end (or double click); eye unchanged. Also: Selected box shows nothing rather than 0 while a newly ticked variable is read. Erik's PR #325 had no compare chart; blowfish built it. Dev server had died 18:08 (exit 143): restarted as bg 755888dhse.
2026-11-27 20:30 owner voted NO on the radar (spider-web) chart for the first version: 'nail the basic version that does one thing very well'; a later upgrade. Erik's PR #325 had no such chart. Component kept for later at tmp/ppvxg2-later/region-radar.tsx (blowfish's, with mean and coverage axes added). Next, owner 20:30: variables chosen like the unit-type tabs (several selected, one marked primary that sizes the circles); explore two ways to compare: the right side in three parts (selected, available, comparison) or the spider on the map.
2026-11-27 20:32 owner icon rule: a link to this view's own list (the search map's List view of the same search) uses a list icon; a link that leaves for another page/list uses the box-with-arrow-out icon (SquareArrowOutUpRight). Today the search map's 'units without a region'/'no location' rows link to List with SquareArrowOutUpRight: change to the list icon there. On the Reports Map, the row's link to Search leaves this page: box-with-arrow-out.
2026-11-27 20:34 built from owner 20:30-20:32 (uncommitted, observed in tab 145): (1) measures as pills like the unit types: Enterprises (units), Employees, Turnover; each on/off; a radio dot marks the primary that sizes the circles (primary stays on); replaces the Size by dropdown and checkboxes (measure-picker.tsx). (2) two ways to show a picked region's figures, a Try radio: the spider round its circle on the map, or a third side-panel part 'Picked, as a share of <selection>' with value, % and a bar (Vestland: 121,507 enterprises 11.3%, 422,321 employees 10.9% of Norway). (3) icon rule: this view's own list = list icon, leaving for another page = box-with-arrow-out: Reports Map rows now SquareArrowOutUpRight to Search; search map's CountRow (no location / without region -> its own List) now List icon (app/src/app/search/map/regions-map.tsx). (4) row click selects (same as circle click); › goes in. Radar removed (later upgrade).
2026-11-27 20:35 radar set aside on branch later/ppvxg2-region-radar (commit cf1607843, pushed), recorded on task cnm602 (later upgrade, depends on this task). tmp/ppvxg2-later copy no longer needed as the source.
2026-11-27 20:41 owner 20:40: measure pills reworked: a click on a pill makes it primary (sizes the circles) and the only one shown, the simple default; a small + inside another pill adds it alongside (shows ✓ when added; click ✓ removes). Primary pill is filled dark. Observed in tab 145: click Employees -> only Employees shown, 'regions by total employees'; + on Enterprises -> Enterprises ✓ added, Selected box shows both. Heading now 'Map: Statistical variables by region' with subtitle (owner 20:37).
2026-11-27 21:01 owner: check boxes instead of +: every pill ends in a check box; primary = dark pill with a white checked box (always shown, cannot be unchecked); others: empty box, tick to show alongside, untick to remove; a click on the name makes that one primary and the only one shown. Built and compiled; owner testing in tab 145, reloads himself.
2026-11-27 21:03 owner 21:02: the 20:16 'row click selects' made a second kind of selection; confusing beside 'Picked, as a share of Norway'. Back to the other maps' pattern: row click goes in (becomes Selected), eye shows a region's figures without going in, › removed. Side-panel box reworded 'Shown, part of Norway' with '(10.9% of Norway)' and a dashed border, X = Hide.
2026-11-27 21:21 owner agreed to try a simpler model: selection = where you are (one); map = circles sized by the primary measure only; all numbers in the side panel as a table (a column per checked measure, optional % of the selection); eye only rings a circle; no spider, no side box, no compare switch. The current version is saved on branch explore/ppvxg2-spider-and-side-box (commit 99b61e5c2, pushed) to jump back to.
## History
- 2026-11-27T17:05 todo -> doing/active (take)
