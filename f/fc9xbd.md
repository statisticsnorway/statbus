---
id: fc9xbd
title: "Dashboard count requests exhaust the API pool on large registers"
state: "doing"
type: feature
priority: ""
assignee: ["rabbit"]
labels: []
group: ""
rank: "zzzzzzzzzzzv"
created: 2026-11-24
updated: 2026-11-24
doing_since: "2026-11-24T20:14"
doing_with: "ca6dk5"
stage: "active"
model: "claude-opus-5-5"
branch: "master"
worktree: "/Users/jhf/ssb/statbus_test"
---

## Goal
On a 2 M-unit register the dashboard shows every card's number within seconds, and its count requests never make other API requests fail.

## Purpose
On a register the size of Norway's, the dashboard's count requests fill PostgREST's connection pool, so every other request fails and the cards stay empty for minutes.

## Principle
Counts the dashboard shows come from data already derived where possible (statistical_history countable_count, quality table sizes) rather than from count(*) on statistical_unit per page view; a count that cannot be answered quickly does not block other requests.

## Details
Observed 2026-11-24 14:56 on the test slot with the BRREG copy (2.19 M statistical_unit rows): about a dozen concurrent count requests (unit cards and Data quality cards, each an estimate then an exact count) ran 20-90 s each; browser console 504 PGRST003, 'Failed to refresh legalUnits', 'Error fetching initial worker statuses'. Finding 19:07 on a quiet server: without db-max-rows PostgREST's count=estimated runs the exact count (returns 1,134,475 in 2.3-11 s), so every card counted twice. With db-max-rows=1000 the estimate is 32-99 ms but the planner's 780,041 (31 % low), and the cap would truncate single-request lists (activity categories 2,215 on Norway); rejected. Owner decision: no estimate step, a waiting placeholder then one exact count per card. Related: dwt9kd (data version), ca6dk5.

## Depends on

## Acceptance
- [ ] On the Norway copy, a cold dashboard load shows every card's number within 10 s, measured with a Playwright test, and no API request returns 504 during it
- [ ] The number of concurrent long count queries a dashboard load starts is bounded and recorded here with the measured load

## Notes


## History
- 2026-11-24T20:14 todo -> doing/active (take with ca6dk5)
