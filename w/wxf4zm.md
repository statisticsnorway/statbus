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
The Drilldown and its region map (ppvxg2) wait 2.0 s at Norway's country level; about 1 s is fast enough (owner 2026-11-28 14:33).

## Principle
One canonical sum: jsonb_stats_merge_agg stays the only summation. Same signature and output; the change is the plan, not the answer. Keep SECURITY DEFINER and its search_path as the function has them. A migration based on \sf, doc/db regenerated.

## Details
Measured by buffalo (tmp/ppvxg2-read-study.md, 2026-11-28): the facet read is about 95 ms; each available branch costs about 0.8 s in a nested <@ loop (24 x 138k), and 7 merges run over all facet rows. Shape D (tmp/ppvxg2-read-drill-direct-def.sql): group each branch to its child key and join by equality, FILTER out empty summaries in the merge, filter the facet on the arguments directly so the GiST index is used; jsonb-identical in 15/15 cases (3 unit types x top, 03, 03.01, M, 46+L.68). Out of scope here: a facets argument (which branches to compute) is a separate step, sketched for the owner first; special region or rollup tables were declined by the owner 14:33.

## Depends on

## Acceptance
- [ ] A SQL test compares the new function's jsonb with the old one's for the 15 cases and they are equal (red first: the test runs against the old definition kept as a fixture)
- [ ] EXPLAIN ANALYZE on the test slot: Norway top level under 1.2 s for enterprise, from 2.0 s
- [ ] The Drilldown in Firefox shows the same figures before and after
- [ ] [Owner] Installed on the test slot at a moment the owner picks (worker stopped, migrate, worker started), by hibiscus

## Notes

2026-11-28 14:37 owner: this rewrite first (same signature, same output), merged quickly; buffalo builds it and stops at master + green CI. hibiscus installs it on the test slot with the owner at a moment he picks. A second step, a facets argument (which drilldown branches to compute, NULL = all as today), is to be shown to the owner as a sketch (buffalo, in tmp/ppvxg2-read-study.md) before it is built, with its own tests.


## History
- 2026-11-28T15:33 todo -> doing/active (take)
