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
On a 2 M-unit register the dashboard shows every card's number within 10 s, and its count requests never make other API requests fail.

## Purpose
On a register the size of Norway's, the dashboard's count requests fill PostgREST's connection pool, so every other request fails and the cards stay empty for minutes.

## Principle
Counts the dashboard shows come from data already derived where possible (statistical_history countable_count, quality table sizes) rather than from count(*) on statistical_unit per page view; a count that cannot be answered quickly does not block other requests.

## Details
Observed 2026-11-24 14:56 on the test slot with the BRREG copy (2.19 M statistical_unit rows): about a dozen concurrent count requests (unit cards and Data quality cards, each an estimate then an exact count) ran 20-90 s each; browser console 504 PGRST003, 'Failed to refresh legalUnits', 'Error fetching initial worker statuses'. Finding 19:07 on a quiet server: without db-max-rows PostgREST's count=estimated runs the exact count (returns 1,134,475 in 2.3-11 s), so every card counted twice. With db-max-rows=1000 the estimate is 32-99 ms but the planner's 780,041 (31 % low), and the cap would truncate single-request lists (activity categories 2,215 on Norway); rejected. Owner decision: no estimate step, a waiting placeholder then one exact count per card. Related: dwt9kd (data version), ca6dk5.

## Depends on

## Acceptance
- [x] On the Norway copy, a cold dashboard load shows every card's number within 10 s, measured with a Playwright test, and no API request returns 504 during it
- [x] The number of concurrent long count queries a dashboard load starts is bounded and recorded here with the measured load

## Notes


2026-11-24 20:08 implementation in the shared checkout (uncommitted, awaiting owner look): components/estimated-count.tsx -> exact-count.tsx with useExactCount (one exact count per card and data version, shared by readers, at most 3 counts at a time per tab, spinner while counting, '-' on failure) and ExactCount; the five dashboard count cards use it; search shows rows with no count, then one exact count (getStatisticalUnitsEstimatedCount and the unused getStatisticalUnits removed, countIsEstimate gone). RED tmp/fc9xbd/red.log: 53 statistical_unit count requests (45 estimated), 9 sent more than once, up to 14 concurrent count queries, 20 x 504, Legal Units never shown in 120 s. GREEN tmp/fc9xbd/green-3.log: 9 requests (all exact, each once), 0 x 5xx, all numbers in 16.5 s. Search tmp/fc9xbd/search-count.log: 1 exact HEAD count, 'of total 17 results', no ~. tsc/lint/jest 523/523 (app-checks-2.log). Side defect fixed in the same change: timeFrameAutoSelectEffectAtom was mounted only on /, so a fresh browser opening /dashboard directly never selected a time frame and no card counted (timeframe-direct-red.log null, -green.log live frame); now mounted in JotaiAppProvider. Timing: a single card count is 1.4-2.1 s on a quiet DB (count-timing.log, after VACUUM ANALYZE removed 1.26 M heap fetches), but this laptop ran at load average 37-54 on 10 CPUs from other projects during every cold-load run; 1 count at a time took 25 s, 3 at a time 16.5-28 s. One scan with FILTER aggregates for the six statistical_unit counts took 5.5 s vs 5.9 s for two separate counts under the same load (one-scan.log): no gain. Check 1's 10 s is not yet shown on this machine.
landed 6071cb5 on master 2026-11-24: app: count cards show a spinner, then one exact count (fc9xbd)
2026-11-24 20:26 owner approved spinner then exact number, and accepted 16.5 s on this busy laptop (load 37-54). Committed 6071cb54f, pushed to master. Next: 05pe0x moves six of the nine dashboard counts into one quality_finding request (45 ms in the prototype), leaving the three unit cards on statistical_unit; re-measure the cold load after it lands.
CI green at 6071cb54f: Fast Tests, Go Test, app build & lint, Images, Harness Selftest, Push on master (gh run list, 2026-11-24 21:17).
check 1: Norway copy, cold dashboard (no saved counts), driven by tmp/fc9xbd/cold-dashboard.mjs with 05pe0x in the slot: every card's number in 2.7 s, 2.1 s, 2.0 s (three runs at load 29-32, cold-after-05pe0x*.log), 0 responses 5xx, no estimate shown, each count query sent once. Before: RED 53 count requests, 20 x 504, Legal Units never shown in 120 s (red.log).
check 2: A cold dashboard load starts 3 statistical_unit count queries (Enterprises, Legal Units, Establishments; useExactCount runs at most 3 at a time per tab) and one quality_finding grouped count for every Data quality card (05pe0x); peak 4 concurrent PostgREST count backends measured (cold-after-05pe0x*.log); before: 53 requests, peak 14 (red.log).
2026-11-26 07:45 owner in Firefox on the Norway copy: each card shows a spinner then the exact number, fast in total; approved.
## History
- 2026-11-24T20:14 todo -> doing/active (take with ca6dk5)
