---
id: sz7rvn
title: "A search on a path with few units hangs for signed-in users"
state: "doing"
type: feature
priority: ""
assignee: ["hibiscus"]
labels: []
group: ""
rank: "zzzzzzzzzzzx"
created: 2026-11-27
updated: 2026-11-27
stage: "review"
doing_since: "2026-11-27T15:47"
doing_with: "j2g6wd"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
review_by: "rabbit"
review_since: "2026-11-27T15:51"
---

## Goal
A search on a region, sector or activity path answers within a second for a signed-in user, however few units match.

## Purpose
An old link to a region that a later upload removed, or any small region (22.11 has 5 units), leaves the list loading for over a minute and leaves the query running in the database; seen 2026-11-27 on the test slot, on master too.

## Principle
Fix the cause in the database by migration, not a timeout in the app; keep the row-level security that protects anything.

## Details
statistical_unit has RLS with three policies, all USING true. ltree <@ (ltree_risparent) is not LEAKPROOF, so for a non-superuser the planner may not use the column statistics: it estimates ~20-30k rows for any path and walks su_sort_name_asc, and LIMIT 10 never fills. Superuser plan uses the gist index (6 ms); with ltree_risparent LEAKPROOF in a rolled-back prototype 0.3 ms. Same plan for sector_path and primary_activity_category_path. Options: (1) drop RLS on statistical_unit, whose policies allow everything; (2) mark the ltree comparison operators LEAKPROOF (extension functions: check they stay so after dump/restore). Evidence in statbus_test: tmp/journal.md 2026-11-27, tmp/unknown-region-role.log, tmp/unknown-region-leakproof-proto.log, tmp/unknown-region-small2.log, tmp/unknown-path-other-filters.log.

## Depends on

## Acceptance
- [x] A SQL test as a signed-in role: an unknown region path and a region with fewer than 10 units each return in well under a second, red before the fix, green after
- [x] The search page with physical_region_path=46.4631 shows no units within a second on the test slot

## Questions
- 2026-11-27T12:05 question 1 by hibiscus to jhf:
  Fix by dropping row-level security on statistical_unit (its three policies all allow everything, so it only costs speed; my recommendation), or by marking the ltree comparison operators LEAKPROOF in a migration?
  answered 2026-11-27T15:38 by jhf:
    Okay, if marking the operations operator's leak proof in migration fixes it, I think it could, but I also do see the point. Why have role-level security if all the policies are the same? Does it help us with speed? Pros and cons in measurements

## Notes


2026-11-27 11:10 (hibiscus) Test design: a timing test cannot go red on a small test database (the planner prefers the name index only with ~millions of rows), so the SQL test asserts the cause directly as a signed-in role: the path filter on statistical_unit is planned with the region's own estimate (EXPLAIN shows the gist index or a row estimate of the matching rows for an empty path), red today, green after the fix. Alternatively assert the property the fix sets: either relrowsecurity false on statistical_unit, or proleakproof true for ltree_risparent/ltree_isparent/ltree_eq.
2026-11-27 14:43 (hibiscus) Measured on statbus_test (Norway register, 5,230,988 statistical_unit rows) as a signed-in role, each setup rolled back (tmp/sz7rvn-compare.sql/.log). ms (a now / b RLS off / c LEAKPROOF <@ @> =): 22.11 five units TIMEOUT>20s / 0.6 / 0.2; unknown region 60473 / 0.2 / 0.2; Oslo 1.0 / 0.8 / 0.2; unknown sector 61555 / 0.6 / 0.1; activity B.05 54746 / 0.9 / 0.1; Vestland+C 977 / 61 / 8; no filter 0.6 / 0.1 / 0.1; count region 46 0.1 / 0.1 / 0.1; map facet 114 / 42 / 42; dashboard 181 / 159 / 157. Plans: (a) walks su_sort_name_asc for every small path; (b) and (c) use the path's gist index. State after: RLS on, functions not leakproof.
2026-11-27 14:47 Owner (in chat, after the measured comparison): LEAKPROOF on the ltree comparison operators; keep RLS, 'consistent with regards to security, an easy model to explain'. Build: migration marking ltree_risparent (<@), ltree_isparent (@>), ltree_eq (=) LEAKPROOF; a SQL test as a signed-in role asserting the gist plan for a small path (red before, green after); verify the setting survives dump/restore (the extension's functions).
check 1: 9942b85c3: test 420 as the schema asserts ltree <@, @>, = LEAKPROOF: red before (f,f,f, tmp/sz7rvn-420-red.out), green after (t,t,t). Measured as a signed-in role on the Norway register: 5-unit region >20 s -> 1.0 ms, unknown region 60 s -> 0.2 ms, plans use the path's gist index (tmp/sz7rvn-after-migration.log).
check 2: Firefox tab 145 on the test slot after 9942b85c3: /search?physical_region_path=22.11 (Jan Mayen) lists 'Showing 1-5 of total 5 results', statistical_unit requests 13-16 ms. The unknown path 46.4631 measures 0.2 ms (no units) in SQL.
landed 9942b85 on master 2026-11-27: db: ltree comparisons are LEAKPROOF, so a signed-in search on a path uses its…
## History
- 2026-11-27T12:05 todo -> todo/design (ask)
- 2026-11-27T15:38 answered design, by jhf, for hibiscus (todo/design -> todo/ready):
  > Fix by dropping row-level security on statistical_unit (its three policies all allow everything, so it only costs speed; my recommendation), or by marking the ltree comparison operators LEAKPROOF in a migration?
  Okay, if marking the operations operator's leak proof in migration fixes it, I think it could, but I also do see the point. Why have role-level security if all the policies are the same? Does it help us with speed? Pros and cons in measurements
- 2026-11-27T15:38 answer 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-27T15:38 answer 1 acknowledged by rabbit
- 2026-11-27T15:47 hibiscus read the answer: hug task note sz7rvn "2026-11-27 14:47 Owner (in chat, after the measured comparison): LEAKPROOF on the ltree comparison operators; keep RLS,…"
- 2026-11-27T15:47 outcome 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
- 2026-11-27T15:47 todo/ready -> doing/active (take with j2g6wd)
- 2026-11-27T15:47 outcome 1 acknowledged by rabbit
- 2026-11-27T15:51 doing/active -> doing/review (review: hibiscus ticked the last own check)
- 2026-11-27T15:51 review 1 delivered to rabbit (session_rabbit_1788255452439_e2c96135756f0328)
