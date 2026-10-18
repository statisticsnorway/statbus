---
id: STATBUS-512
title: >-
  Test 306 pins float statistics to more digits than f64 carries, so it passes
  only on one machine
status: Done
assignee: []
created_date: '2026-10-15 21:43'
updated_date: '2026-10-18 12:41'
labels:
  - testing
  - jsonb_stats
dependencies: []
priority: medium
ordinal: 438204
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### North Star
A test's expected output is the same on every machine that runs the suite.

### Zoom out
jsonb_stats merges float statistics with Chan's parallel formula (`src/merge.rs:84-87`). The result depends on merge order and on the CPU's floating-point rounding. Test 306 prints `variance` (~1.7e14) and `sum_sq_diff` (~1.2e16) to the cent, which is beyond the ~15-16 significant digits an f64 carries. So the last digits differ between machines.

### Zoom in
- **Observed 2026-10-15:** Block 1, enterprise, turnover. CI (amd64), scan order: variance ...595.41. Local (arm64), scan order: ...595.38. Same rows on arm64: ORDER BY unit_id gives .38, DESC gives .44.
- **Tried and reverted:** declaring `ORDER BY unit_id` in the merge (0342c80e2, reverted by 5bd8ebfa8). It made arm64 deterministic, but amd64 then failed: order alone does not remove the architecture difference.
- **Likely fix:** the test should compare the statistics at the precision f64 actually carries (for example rounding variance/stddev/sum_sq_diff to a fixed number of significant digits in the test's own output), and possibly the merge should declare an order so a value is stable on one machine. Decide which layer owns this: the test's presentation, or jsonb_stats' output rounding (`final_fn.rs` round2 on values beyond f64's precision).
- **Scope check:** 10 other expected files print variance/sum_sq_diff (004, 104-110, 302, 303, 305); verify each against the same rule.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Test 306 produces identical output on amd64 (CI) and arm64 (local), shown by a green CI run and a green local run at the same commit
- [x] #2 The other expected files that print float variance are checked against the same rule and fixed where they pin digits beyond f64 precision
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
### Closing review
- Memory: none needed yet; record the f64 precision rule if the fix sets one.
- Documentation: if the fix rounds in the test, state the rule in the test's own comment where the floats are printed.
- Cleanup: none.

### Upstream fix chosen (owner, 2026-10-16)
The fix goes into jsonb_stats (the owner's extension). The issue and a possible fix are written up in ../jsonb_stats/todo.md for a local agent: the cause is the f64 state shared by all four numeric aggregates (NumFields, src/state.rs), not the stat types. Proposed: exact i128 state for int/nat/dec2 (matching the PL/pgSQL numeric reference and the README's dec2 promise), compensated combine plus significant-digit output for float_agg, one combine path, README correction.
StatBus side after the jsonb_stats release: bump jsonb_stats_release in postgres/Dockerfile, re-record expected outputs once, check the 10 other files that print variance.

### jsonb_stats v3.0.0 released (2026-10-18)
- Tag v3.0.0 = 04cff87 on veridit/jsonb_stats. State is exact (count, sum, sum_sq, min, max as decimals), and derived fields are rounded once, so the results are order- and machine-independent.
- **Upgrade path:** `ALTER EXTENSION jsonb_stats UPDATE` (sql/jsonb_stats--2.0.0--3.0.0.sql is a no-op for SQL). Stored 2.x summaries are upgraded on read (sum_sq rebuilt from count, sum and sum_sq_diff) and become exact at their next recompute. Note: dev/STATBUS_HANDOFF.md (bb3bc43) predates this; it says there is no ALTER path and stored summaries are rejected. The released README and CHANGELOG supersede it.
- **Plan:** bump the pin, add a guarded ALTER EXTENSION migration, prove the box-shaped upgrade, re-record the expected outputs, and get CI amd64 identical to arm64.

### Upgrade proof (2026-10-18 11:45, local stack shaped like a box upgrade; tmp/512-proof-local.sh, tmp/512-proof-step4.sh)
1. **Old image** (2.0.0): the demo fixture was loaded through the real import and analytics jobs, giving 163 statistical_unit rows with summaries and 0 of 163 carrying sum_sq. The merge of enterprise employees gave count 135, sum 2239, sum_sq_diff 8378.95.
2. **db recreated on the new image** (3.0.0 library, 2.0.0 schema, as the upgrade's db restart does). It reads and merges the stored 2.0.0 summaries with no error, and the merge now carries sum_sq 45513.
3. **./sb migrate up** applies 20261018113522: extversion becomes 3.0.0. The stored summaries are byte-identical before and after (md5 over every unit's stats_summary). A second run is a no-op.
4. **Recompute** (timeline_*_refresh, then statistical_unit_refresh): 163 of 163 summaries carry sum_sq. The sample's {10, 23} gives sum_sq 629 = 10² + 23², and sum_sq_diff 84.50, which is exact.
- **Note:** statistical_unit_refresh alone copies from the timeline tables, so a recompute must start at the timelines. On a box the next import or derive does this per unit.

### Committed d506471b4 (2026-10-18)
- Pin jsonb_stats_release=v3.0.0. Migration 20261018113522 (guarded ALTER EXTENSION jsonb_stats UPDATE TO '3.0.0'; its down refuses). app types: sum_sq?: number.
- **Red:** on master (2.0.0) test 306 passes locally on arm64 but failed in CI on amd64 (5bd8ebfa8 history), and the variance digits differ between them.
- **Green locally (arm64), with 3.0.0:** 16 expected files re-recorded. All 118 fast tests pass; tsc and lint pass.
- **Review of every changed line:** `tmp/512-verify-exact.py` recomputed sum_sq_diff, mean, variance and stddev with rational arithmetic from count, sum and sum_sq for every numeric aggregate in the new outputs: **1870 values, 0 mismatches**. `tmp/512-residual.py` removed derived fields and number formatting; what remains is only the new sum_sq lines and the 107 HINT that now lists stats_summary.*.sum_sq.
- **AC2 (the other files that print variance):** the 15 other files are re-recorded under the same exact values. 404 (4xx, not in fast) is left to STATBUS-480.
- Waiting: Fast Tests on amd64 in CI for d506471b4. Identical output there means AC1 is proven.

### Closed 2026-10-18 12:41
- **AC1:** Fast Tests run 39127010713 (amd64, CI) passed on 373cd0f80, which contains d506471b4, with the same expected outputs that pass locally on arm64 (118/118). Go Test passed on d506471b4.
- **AC2:** every fast-suite file that prints statistics was re-recorded under exact values and checked (1870 values, 0 mismatches). 404 (4xx, not in any CI) belongs to STATBUS-480.
- **Closing review:** Memory: none. Documentation: the migration comment carries the upgrade meaning; jsonb_stats's README covers the rest. Cleanup: the local image tag statbus-db:pre-512 was kept only for the proof.
<!-- SECTION:NOTES:END -->
