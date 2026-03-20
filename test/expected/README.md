# Test Expected Output

## `performance/` and `explain/` — Baseline Tracking

Files in `performance/` and `explain/` are **not strict pass/fail tests**. They capture
baseline snapshots of query plans and timing data so we can spot regressions.

**When you see changes in these files:**

1. **Review the diff** — look for red flags like order-of-magnitude timing increases,
   new sequential scans on large tables, or dramatically higher row counts.
2. **If it looks like a regression** — flag it and discuss before committing.
3. **If the changes are trivial** (minor plan reorderings, small timing fluctuations,
   cost estimate shifts) — **discard the changes** with `git checkout -- test/expected/performance/ test/expected/explain/`.
   These are normal and expected after template rebuilds or unrelated schema changes.

Do not commit baseline drift unless there is a deliberate reason (e.g., a new index
that legitimately changes plans, or updated test data that shifts row counts).
