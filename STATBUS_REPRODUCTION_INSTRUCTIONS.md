# sql_saga Native Planner Bug: PATCH_FOR_PORTION_OF Drops Target Columns

## Status

**Branch:** `integrate-sql-saga-rust-native` in `statbus_speed`
**sql_saga release:** `6facdb0` (set in `postgres/Dockerfile` as `sql_saga_release=6facdb0`)
**sql_saga repo:** https://github.com/veridit/sql_saga.git
**Blocking tests:** 307 (`307_test_lu_enterprise_link`) and 320 (`320_test_enterprise_name_preservation`)

Category B tests (310, 311, 312, 321) have been resolved by updating expected outputs.
Those are correct behavioral changes: the native planner returns `SKIPPED_IDENTICAL`
instead of `APPLIED` when source data matches the target, which is the right behavior.

Category A tests (307, 320) remain failing due to a bug in the native planner's
`PATCH_FOR_PORTION_OF` mode.


## Background

STATBUS uses `sql_saga.temporal_merge` extensively. It has two modes relevant here:

1. **`MERGE_ENTITY_UPSERT`** -- Full upsert of an entity. The source table contains ALL
   columns for the target (name, birth_date, sector_id, etc. -- 15+ columns for
   `legal_unit`). This mode works correctly.

2. **`PATCH_FOR_PORTION_OF`** -- Partial update. The source table contains only a SUBSET
   of target columns (e.g., just `id`, `enterprise_id`, `primary_for_enterprise`). Columns
   not present in the source should be inherited from the existing target row when the
   planner splits/inserts time segments.

The import pipeline first creates a `legal_unit` row via `MERGE_ENTITY_UPSERT` (all columns
populated), then a subsequent function (`connect_legal_unit_to_enterprise`) uses
`PATCH_FOR_PORTION_OF` to update only `enterprise_id` and `primary_for_enterprise` on the
same target row.


## Category A Bug Description

When `PATCH_FOR_PORTION_OF` generates its plan for an existing target row, it must produce
`INSERT` operations that carry forward ALL target columns -- not just the columns present in
the source. The native planner fails to do this: the `data` JSONB in `temporal_merge_plan`
is missing target-inherited columns.

Concretely:

1. `MERGE_ENTITY_UPSERT` fills `legal_unit` row with all columns (name='Main Company Ltd',
   birth_date='2023-01-01', sector_id=X, status_id=Y, etc.)

2. `connect_legal_unit_to_enterprise` creates a temp source table with ONLY:
   - `id`, `enterprise_id`, `primary_for_enterprise`, `valid_from`, `valid_until`

3. It calls `temporal_merge` with `mode => 'PATCH_FOR_PORTION_OF'`

4. The native planner generates INSERT operations where `data` contains only `enterprise_id`
   and `primary_for_enterprise` -- the columns NOT in the source (`name`, `birth_date`,
   `status_id`, `edit_by_user_id`, etc.) are NULL in the `data` JSONB.

5. The executor runs the INSERT, which fails:
   ```
   ERROR: null value in column "name" of relation "legal_unit" violates not-null constraint
   ```

The PL/pgSQL planner correctly inherits all target columns into the `data` JSONB for INSERT
operations in `PATCH_FOR_PORTION_OF` mode. The Rust native planner does not.

### Error Context from Test Output

```
ERROR:  null value in column "name" of relation "legal_unit" violates not-null constraint
CONTEXT:  SQL statement "
    WITH
    source_for_insert AS (
        SELECT
            p.plan_op_seq, p.new_valid_range,
            p.entity_keys || p.data as full_data
        FROM temporal_merge_plan p
        WHERE p.operation = 'INSERT' AND NOT p.is_new_entity
    ),
    ...
    INSERT ... VALUES ((s.full_data->>'name')::character varying, ...)
    ...
"
PL/pgSQL function sql_saga.temporal_merge_execute(...) line 915 at EXECUTE
SQL statement "CALL sql_saga.temporal_merge(
      target_table => 'public.legal_unit',
      source_table => 'temp_lu_source',
      primary_identity_columns => ARRAY['id'],
      mode => 'PATCH_FOR_PORTION_OF',
      row_id_column => 'row_id'
    )"
PL/pgSQL function connect_legal_unit_to_enterprise(integer,integer,date,date) line 100 at CALL
```

The key line is `p.entity_keys || p.data as full_data` -- when `p.data` is missing `name`,
`birth_date`, etc., the INSERT produces NULLs for those NOT NULL columns.


## How to Reproduce

### Prerequisites

- Docker and docker compose
- The `statbus_speed` repo checked out on branch `integrate-sql-saga-rust-native`

### Build and Run

```bash
# Build the database image (includes sql_saga + sql_saga_native at commit 6facdb0)
docker compose build db

# Recreate database from scratch (applies all migrations)
./devops/manage-statbus.sh recreate-database

# Run the two failing Category A tests
./devops/manage-statbus.sh test 307_test_lu_enterprise_link 320_test_enterprise_name_preservation

# Or run all fast tests (expects 2 failures for 307, 320)
./devops/manage-statbus.sh test fast 2>&1 | tee tmp/test-fast.log
```

### View the Diffs

```bash
# Show diffs for all failed tests
./devops/manage-statbus.sh diff-fail-all pipe
```

### Inspect the Plan Directly

To see the bug in the `temporal_merge_plan` table, connect to the database and run a
minimal reproduction (see next section).


## Minimal SQL Reproduction

This script demonstrates the bug pattern without needing the full import pipeline. Run it
inside a `psql` session connected to a STATBUS database that has been set up with
`recreate-database`:

```sql
BEGIN;

-- Set up as admin user
CALL test.set_user_from_email('test.admin@statbus.org');

-- Ensure we have a clean enterprise and legal unit
-- (In the real tests, these are created by the import pipeline)
INSERT INTO public.enterprise (id) OVERRIDING SYSTEM VALUE VALUES (9999);

INSERT INTO public.legal_unit (
    id, name, birth_date, enterprise_id, primary_for_enterprise,
    status_id, edit_by_user_id, edit_at,
    valid_from, valid_until, valid_range
) OVERRIDING SYSTEM VALUE VALUES (
    9999,
    'Test Company',
    '2023-01-01',
    9999,
    true,
    (SELECT id FROM public.status WHERE code = 'active' LIMIT 1),
    (SELECT id FROM auth."user" WHERE email = 'test.admin@statbus.org'),
    statement_timestamp(),
    '2023-01-01',
    'infinity',
    daterange('2023-01-01', NULL)
);

-- Now simulate what connect_legal_unit_to_enterprise does:
-- Create a source table with ONLY the columns being patched
CREATE TEMPORARY TABLE temp_lu_source (
    row_id int generated by default as identity,
    id integer,
    enterprise_id integer,
    primary_for_enterprise boolean,
    valid_from date,
    valid_until date
) ON COMMIT DROP;

-- Insert a patch: change enterprise_id (e.g., to a different enterprise)
INSERT INTO public.enterprise (id) OVERRIDING SYSTEM VALUE VALUES (9998);
INSERT INTO temp_lu_source (id, enterprise_id, primary_for_enterprise, valid_from, valid_until)
VALUES (9999, 9998, true, '2023-06-01', 'infinity');

-- This call will fail with the native planner bug:
-- "null value in column 'name' of relation 'legal_unit'"
--
-- The planner should produce INSERT operations where 'data' contains
-- name='Test Company', birth_date='2023-01-01', etc. inherited from
-- the existing target row. Instead, those columns are NULL.
CALL sql_saga.temporal_merge(
    target_table => 'public.legal_unit',
    source_table => 'temp_lu_source',
    primary_identity_columns => ARRAY['id'],
    mode => 'PATCH_FOR_PORTION_OF',
    row_id_column => 'row_id'
);

-- If the above succeeds, verify:
SELECT id, name, enterprise_id, primary_for_enterprise, valid_from, valid_until
FROM public.legal_unit
WHERE id = 9999
ORDER BY valid_from;

ROLLBACK;
```

### Expected Behavior (PL/pgSQL Planner)

When using the PL/pgSQL planner (without `sql_saga_native`), `PATCH_FOR_PORTION_OF` correctly:

1. Reads the existing target row (id=9999, name='Test Company', birth_date='2023-01-01', ...)
2. For the time segment being split, creates INSERT plan entries where `data` contains ALL
   non-identity, non-source columns inherited from the target (name, birth_date, status_id, etc.)
3. Overlays the source columns (enterprise_id, primary_for_enterprise) on top
4. The INSERT succeeds because all NOT NULL columns have values

### Actual Behavior (Native Rust Planner)

The native planner:

1. Reads the existing target row
2. Creates INSERT plan entries where `data` contains ONLY the source columns (enterprise_id,
   primary_for_enterprise)
3. Target-inherited columns (name, birth_date, status_id, edit_by_user_id) are absent from `data`
4. The INSERT fails: `null value in column "name" of relation "legal_unit"`


## How to Fix When sql_saga Is Updated

Once the native planner bug is fixed in the `sql_saga` repo:

```bash
# 1. Update the sql_saga release hash in postgres/Dockerfile
#    Change: ARG sql_saga_release=6facdb0
#    To:     ARG sql_saga_release=<new-commit-hash>

# 2. Rebuild the database image
docker compose build db

# 3. Recreate database with the updated extension
./devops/manage-statbus.sh recreate-database

# 4. Run the failing tests -- they should now pass
./devops/manage-statbus.sh test 307_test_lu_enterprise_link 320_test_enterprise_name_preservation

# 5. Run all fast tests to confirm no regressions
./devops/manage-statbus.sh test fast 2>&1 | tee tmp/test-fast.log

# 6. If all tests pass, commit the Dockerfile change
git add postgres/Dockerfile
git commit -m "chore: Update sql_saga to <new-commit-hash> (fixes PATCH_FOR_PORTION_OF native planner bug)"
```

### Verifying the Fix at the sql_saga Level

In the `sql_saga` repo itself, the fix can be verified by checking that
`temporal_merge_plan.data` contains all target columns (not just source columns) for INSERT
operations generated during `PATCH_FOR_PORTION_OF` mode when the source table has fewer
columns than the target table.

The Rust native planner function that builds the plan entries for time-segment splits needs
to read the existing target row's values for ALL non-identity columns and include them in
the `data` JSONB, then overlay the source columns on top.
