# Testing Rules

## Never run destructive database commands without asking

Always ask the user before running commands that destroy or recreate the development database:
- `./dev.sh recreate-database`
- `./dev.sh delete-db`
- `./dev.sh delete-db-structure`
- `./dev.sh create-db` (drops and recreates)

Tests (`./dev.sh test`) are safe — they run against cloned databases, not the user's active development database.

## Performance and explain baselines are not strict tests

Files in `test/expected/performance/` and `test/expected/explain/` track baseline snapshots
of query plans and timing data. When these change:

1. **Review the diff** for red flags (order-of-magnitude timing increases, new sequential scans, dramatically higher row counts).
2. **If trivial** (minor plan reorderings, small timing shifts, cost estimate changes) — **discard with `git checkout`**. Do not commit baseline drift.
3. **If suspicious** — flag it and discuss before proceeding.
