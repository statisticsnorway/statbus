---
id: wxf4zm
title: "Drilldown read 2× faster: same answer, branches grouped by key"
state: "doing"
type: feature
priority: ""
assignee: ["buffalo"]
labels: []
group: ""
rank: "zzzzzzzzzzzy"
created: 2026-11-28
updated: 2026-11-28
doing_since: "2026-11-28T15:33"
stage: "active"
model: "claude-opus-4-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus"
---

## Goal
statistical_unit_facet_drilldown answers Norway's top level in about 1 s instead of 2 s, with byte-identical output.

## Purpose
The Drilldown (and its region map, ppvxg2) waits 2.0 s at the country level on Norway. Worker buffalo's study (tmp/ppvxg2-read-study.md, 2026-11-28) found 0.8 s per branch in a nested <@ loop and 7 merges over all facet rows.

## Principle
One canonical sum: jsonb_stats_merge_agg stays the only summation. Same signature and output; the change is the plan, not the answer. Keep SECURITY DEFINER and its search_path as the function has them. A migration based on \sf, doc/db regenerated.

## Details
Shape D in tmp/ppvxg2-read-study.md and tmp/ppvxg2-read-drill-direct-def.sql: group each branch to its child key and join by equality, FILTER out empty summaries in the merge, filter the facet on the arguments directly so the GiST index is used. Measured jsonb-identical in 15/15 cases (3 unit types x top, 03, 03.01, M, 46+L.68). A dims argument (only the branches a page shows; region only: 0.33-0.47 s at top) is a further step to decide with the owner. A region-only facet table (1-2 ms) is a bigger change, its own task if wanted.

## Depends on

## Acceptance
- [ ] A SQL test compares the new function's jsonb with the old one's for the 15 cases and they are equal (red first: the test runs against the old definition kept as a fixture)
- [ ] EXPLAIN ANALYZE on the test slot: Norway top level under 1.2 s for enterprise, from 2.0 s
- [ ] The Drilldown in Firefox shows the same figures before and after

## Notes

2026-11-28 14:37 owner: this rewrite first (same signature, same output), merged quickly; buffalo builds it and stops at master + green CI. hibiscus installs it on the test slot with the owner at a moment he picks. A second step, a facets argument (which drilldown branches to compute, NULL = all as today), is to be shown to the owner as a sketch (buffalo, in tmp/ppvxg2-read-study.md) before it is built, with its own tests.


## History
- 2026-11-28T15:33 todo -> doing/active (take)
