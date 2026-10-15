---
id: STATBUS-512
title: >-
  Test 306 pins float statistics to more digits than f64 carries, so it passes
  only on one machine
status: To Do
assignee: []
created_date: '2026-10-15 21:43'
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
- [ ] #1 Test 306 produces identical output on amd64 (CI) and arm64 (local), shown by a green CI run and a green local run at the same commit
- [ ] #2 The other expected files that print float variance are checked against the same rule and fixed where they pin digits beyond f64 precision
<!-- AC:END -->
