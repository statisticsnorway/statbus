# Testing Rules

## Never run destructive database commands without asking

Always ask the user before running commands that destroy or recreate the development database:
- `./dev.sh recreate-database`
- `./dev.sh delete-db`
- `./dev.sh delete-db-structure`
- `./dev.sh create-db` (drops and recreates)

Tests (`./dev.sh test`) are safe — they run against cloned databases, not the user's active development database.

## pg_regress shared tests do NOT auto-wrap in a transaction

The runner message "BEGIN/ROLLBACK isolation on cloned database" refers to
cloned-template isolation, NOT to transaction wrapping of each test file.
If a test uses `SAVEPOINT`, it must open its own transaction with `BEGIN;`
at the top and `ROLLBACK;` at the bottom — otherwise the SAVEPOINT errors
and, with `\set ON_ERROR_STOP on`, psql exits 3 and truncates the output
file silently.

## Rollback restores rows, not sequences — and what that means for ids

**The mechanism.** `nextval()` is non-transactional. A value consumed by an
INSERT that later rolls back is burned, not returned. Most test files open
`BEGIN;` *before* `\i test/setup.sql`, so the fixture users created there are
rolled back at the end of the file — the rows vanish, the burned ids do not
come back. Shared tests run sequentially on one database, so the next file's
setup inserts its users at higher ids. The ids a test sees depend on **which
tests ran before it**, which is why a targeted run and a full replay disagree.

Measured with a probe test that printed the fixture ids (STATBUS-315):

| run                                   | admin | regular | restricted |
|---------------------------------------|-------|---------|------------|
| alone, before the fix                 | 1     | 2       | 3          |
| after `009` + `013` + `018`, before   | 19    | 20      | 21         |
| either order, after the fix           | 1     | 2       | 3          |

**More transaction discipline is not the fix.** The tests already run in a
transaction and already roll back — that is precisely what burns the ids. The
sequence sits outside transactional control on purpose, so wrapping the test
more tightly cannot help.

**The fix, in `test/setup.sql`:** normalize the user sequence by *derivation
from the data* (`setval(..., max(id))`) rather than by `RESTART`. Deriving from
the rows discards the burn history, so two databases holding the same users
agree on ids regardless of the path they took. `RESTART WITH 1` is only correct
when the table is empty — which is why the unit sequences above it can use it
and the user sequence cannot.

**So: may a test assert an id?** For the fixture users, they are now dependably
1, 2, 3 and a test may rely on that. What is *not* promised is permanence:
those numbers are derived from the seed's user set, so a migration that seeds
or removes users moves all of them, and every expected file printing one has to
be re-blessed. Prefer, in order:

1. **Natural key** — address the row by something the test chose itself (an
   email, a code, a sha it generated). `329_test_upgrade_schema_skew` counts its
   own row by `commit_sha = lpad(to_hex(999), 40, '0')` instead of `id = 1`,
   which had passed only because that row happened to land on id 1.
2. **Same-replay comparison** — compare against a lookup made in the same run
   and print the boolean. `098_user_delete_door` is the worked example:

       SELECT (id = (SELECT u.id FROM auth."user" AS u
                      WHERE u.email = 'test.regular@statbus.org')) AS returned_target_row
         FROM public.user_delete(...);

   This is strictly stronger than blessing `2` was: a literal id proved the row
   was number two, never that it was the *right* row.
3. **A count** — when the claim is "nothing happened" or "exactly one matched",
   `count(*)` says so directly and cannot drift.

Printing an id is acceptable where it is the subject of the test; just know you
have blessed a value that moves with seed content, not a behavioural fact.

## Performance and explain baselines are not strict tests

Files in `test/expected/performance/` and `test/expected/explain/` track baseline snapshots
of query plans and timing data. When these change:

1. **Review the diff** for red flags (order-of-magnitude timing increases, new sequential scans, dramatically higher row counts).
2. **If trivial** (minor plan reorderings, small timing shifts, cost estimate changes) — **discard with `git checkout`**. Do not commit baseline drift.
3. **If suspicious** — flag it and discuss before proceeding.
