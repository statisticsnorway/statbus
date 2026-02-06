---
paths:
  - "migrations/**"
  - "**/*.sql"
  - "test/sql/**"
  - "test/expected/**"
  - "dbseed/**"
---

# SQL Conventions (STATBUS)

Detailed SQL conventions for the STATBUS project. This project uses PostgreSQL (18+) and PostgREST (12+) for its backend, deployed on custom servers behind Caddy with HTTPS.

## Function/Procedure Definitions
- Use the function/procedure name in the literal string quote for the body (e.g., `AS $my_function_name$`).
- Specify `LANGUAGE plpgsql` (or other) before the body.
- Use the long form for parameters for documentation clarity (e.g., `param_name param_type`).
- Example:
  ```sql
  CREATE FUNCTION public.example(email text) RETURNS void LANGUAGE plpgsql AS $example$
  BEGIN
    -- Use function_name.parameter_name for clarity if needed, e.g., example.email
    SELECT * FROM some_table st WHERE st.email = example.email;
  END;
  $$;
  ```

## Function Calls
For calls with 3+ arguments, use named arguments (e.g., `arg1 => val1`).

## String Literals for `format()`
- Always prefer dollar-quoting (e.g., `format($$ ... $$)`) for the main dynamic SQL string. This avoids having to escape single quotes inside the SQL.
- **Nesting**: When nesting dollar-quoted strings (e.g., a dynamic SQL string that itself contains another `format()` call), use named dollar quotes for the outer string to avoid conflicts. The convention is to use a descriptive name like `$SQL$` or `$jsonb_expr$`. This is especially common inside function bodies, which already use a named quote (e.g., `$function_name$`).
- For `format()` calls with multiple parameters, especially if parameters repeat, use numbered placeholders for clarity:
  - `%1$I` for the 1st parameter as an identifier, `%2$L` for the 2nd as a literal, `%3$s` for the 3rd as a plain string, etc.
  - Example: `format($$Testing %3$s, %2$s, %1$s$$, 'one' /* %1 */, 'two' /* %2 */, 'three' /* %3 */);`
- Prefer parameter binding with `EXECUTE ... USING` for large arrays or values rather than interpolating with `%L` where possible.

Good:
```sql
-- Dollar-quoted format() string; identifier and literal are numbered; batch array is passed via USING.
EXECUTE format($$
    UPDATE public.%1$I AS dt SET
        last_completed_priority = %2$L
    WHERE dt.row_id = ANY($1) AND dt.action = 'skip'
$$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */)
USING p_batch_row_ids;
```

Also good (embedding quotes safely without doubling them):
```sql
EXECUTE format($$
    UPDATE public.%1$I AS dt SET
        error = COALESCE(dt.error, '{}'::jsonb) ||
                jsonb_build_object('status_code', 'Provided status_code not found and no default available'),
        state = 'error'
    WHERE dt.row_id = ANY($1) AND dt.status_code IS NOT NULL
$$, v_data_table_name)
USING p_batch_row_ids;
```

Also good (nested dollar-quoting):
```sql
-- The outer string uses a named quote ($jsonb_expr$) to avoid conflicting with the inner $$
v_error_sql := $jsonb_expr$
    jsonb_build_object('latitude', CASE ... THEN format($$Value %1$s out of range$$, lat_val) ... END)
$jsonb_expr$;
```

Avoid:
```sql
-- Hard to read and easy to break: manual '' escaping inside single-quoted format string
EXECUTE format('UPDATE public.%s SET note = ''it'''''s broken'' WHERE id = %s', tbl, id);
```

Notes:
- Use `%I` for identifiers, `%L` for SQL literals, and `%s` for raw string insertion.
- Keep the SQL readable by aligning numbered placeholders with inline comments that show which parameter they refer to.

## Table Aliases
Prefer explicit `AS` for table aliases, e.g., `FROM my_table AS mt`. For common data table aliases in import procedures, `AS dt` is preferred.

## Temporal Logic
When writing conditions involving time, always order the components chronologically for readability (e.g., `start <= point AND point < end`). Avoid non-chronological forms like `point >= start`.

## Batch Operations
Utilize PostgreSQL 18+ `MERGE` syntax for efficient batch handling where appropriate.

## Query Optimization Patterns
- **LATERAL vs CTE for Batch Processing**: LATERAL joins execute once per row from the outer query—good for single-row lookups but O(n^2) for batch operations. For batch processing, pre-aggregate in a CTE then use a regular JOIN, which is O(n).
- **`IS NOT DISTINCT FROM` Performance**: This operator treats NULL=NULL as true, which prevents PostgreSQL from using hash joins effectively. For multi-column joins with nullable columns, consider using COALESCE with sentinel values to enable hash joins, or restructure to avoid the pattern.
- **Index Usage with Functions**: Indexes on columns are not used when the column is wrapped in a function (e.g., `COALESCE(col, default)`). Create expression indexes or restructure queries to match indexed columns directly.
- **Use `EXPLAIN (ANALYZE, BUFFERS)` liberally**: Look for "Rows Removed by Filter/Join Filter" in plans—high numbers indicate inefficient joins or missing indexes.

## Temporary Table Management
To ensure procedures are idempotent and to avoid noisy `NOTICE` messages in logs, use the following pattern to clean up temporary tables at the beginning of a procedure:
```sql
-- The explicit 'pg_temp.' schema ensures we only check for session-local tables.
IF to_regclass('pg_temp.my_temp_table') IS NOT NULL THEN DROP TABLE my_temp_table; END IF;
CREATE TEMP TABLE my_temp_table (...) ON COMMIT DROP;
```

This pattern has several advantages:
1. **Silent Operation**: It avoids the `NOTICE: table "..." does not exist, skipping` message that `DROP TABLE IF EXISTS` would generate on the first run.
2. **Co-location**: It keeps the cleanup logic directly beside the creation logic, improving readability.
3. **Debuggability**: If the code does not behave as expected, then a test running in the same transaction can inspect those temporary tables to determine where the faulty logic lies.

## Database Inspection
Use `psql` for direct database inspection and querying during development. For example, to list available import definitions: `echo 'SELECT slug, name FROM public.import_definition;' | ./devops/manage-statbus.sh psql`

For a compact data model reference, see `doc/data-model.md`.

## SQL Naming Conventions
- `x_id` = foreign key to table `x`
- `x_ident` = external identifier, not originating from the database
- `x_at` = TIMESTAMPTZ (with timezone)
- `x_on` = DATE

## SQL Testing
Use pg_regress with `test/` as the base directory.
Run tests via `./devops/manage-statbus.sh test [all|xx_the_test_name]`.

### Transparent Error Testing (Avoid DO Blocks)
DO blocks that catch exceptions hide what actually happens, violating fail-fast. If an operation silently affects 0 rows, the exception handler never fires and the test "passes" without testing anything.

```sql
-- BAD: Opaque - hides actual behavior
DO $$
BEGIN
  UPDATE t SET x = 1 WHERE id = currval('t_id_seq');  -- May update 0 rows!
  RAISE EXCEPTION 'Should have failed';
EXCEPTION WHEN foreign_key_violation THEN
  RAISE NOTICE 'FK working';  -- Never printed if 0 rows matched
END $$;

-- GOOD: Transparent - shows what happens
DELETE FROM t; ALTER SEQUENCE t_id_seq RESTART WITH 1;  -- Deterministic ids
INSERT INTO t (val) VALUES ('test');  -- id=1
SELECT id, val FROM t;  -- Verify target row exists
SAVEPOINT before_test;
\set ON_ERROR_STOP off
UPDATE t SET fk_col = 99999 WHERE id = 1;  -- See actual ERROR
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_test;
SELECT COUNT(*) AS invalid_rows FROM t WHERE fk_col = 99999;  -- Verify: 0
```

Key techniques:
- Reset sequences + fixed timestamps = deterministic, reproducible ids
- SAVEPOINT + `\set ON_ERROR_STOP off` = see actual ERROR messages
- Verification queries after rollback = prove constraints work
- If something breaks, you immediately see *what* and *why*

## Iterative Development Cycle

All development work, especially bug fixing, must follow a rigorous, hypothesis-driven cycle to ensure progress is verifiable, correct, and does not waste time on flawed assumptions. **A hypothesis is not confirmed until it is supported by direct, empirical observation.**

### 1. Hypothesize: Formulate and State a Hypothesis
- **Action:** Before making any code changes, clearly state your hypothesis about the root cause of the problem in `tmp/journal.md`. This creates a locally persistent log of your thought process.
- **Example:** "Hypothesis: The import job hangs because the batch selection query is inefficient and confuses the query planner."

### 2. Isolate: Create or Identify a Reproducing Test
- **Action:** Ensure a test case exists that isolates the bug. This can be an existing pg_regress test or a temporary SQL script (`tmp/debug_*.sql`) that demonstrates the failure (e.g., a query that is slow or returns incorrect data).

### 3. Prototype: Propose a Non-Destructive Verification
- **Action:** Before proposing a permanent fix, create a temporary, non-destructive script (e.g., `tmp/verify_fix.sql`) to test your proposed change. This script must use tools like `EXPLAIN (ANALYZE, BUFFERS)` or read-only `SELECT` queries to gather performance data or check logic without altering the database state.
- **Example:** Create a script that runs `EXPLAIN ANALYZE` on a simplified query to prove it is fast and returns the expected number of rows.

### 4. Observe: Gather Empirical Evidence from the Prototype
- **Action:** Run the verification script from Step 3. **Do not proceed until you have observed the results.** This step is mandatory.
- **Standard Command**: `./devops/manage-statbus.sh psql < tmp/verify_fix.sql`

### 5. Analyze & Refine: Analyze Prototype Results
- **Action:** Carefully inspect the output from the verification script.
  - **If Successful:** The prototype confirms the hypothesis (e.g., the new query is fast). You can now proceed to propose the permanent change.
  - **If Unsuccessful:** The hypothesis was incorrect. The prototype failed (e.g., the query was still slow or returned zero rows). Analyze the new data, update `tmp/journal.md` with a new hypothesis, and return to Step 1.

### 6. Implement: Propose the Permanent Change
- **Action:** Only after the prototype has been successfully verified in Step 5, propose the specific code changes for the permanent files (e.g., migrations, functions). State the expected outcome.
- **Example:** "This change replaces the complex query with the simplified version that was verified to be fast in `tmp/verify_fix.sql`."

### 7. Validate: Run Full Regression Tests
- **Action:** After applying the permanent changes, run the relevant test suite to ensure the fix works and has not introduced any regressions.
- **Standard Command**: `./devops/manage-statbus.sh test [test_name]`

### 8. Conclude: Update Documentation
- **Action:** Only after the fix has been successfully validated in Step 7, update task tracking to mark the task as done.

## General Development Principles

- **Embrace Falsifiability**: Treat every hypothesis and plan as provisional until proven by direct, empirical observation. Frame plans as "Current Plan" or "Next Step," not "Final Plan." The goal is to be prepared to be wrong and to allow evidence to guide the development process. Optimism should be rooted in the rigor of the process itself, not in the assumed correctness of any single solution. This mindset is the primary defense against hubris and wasted effort.
- **Fail Fast**: Functionality that is expected to work should fail immediately and clearly if an unexpected state or error occurs. Do not mask or work around problems; instead, provide sufficient error or debugging information to facilitate a solution. This is crucial for maintaining system integrity and simplifying troubleshooting, especially in backend processes and SQL procedures.
- **Declarative Transparency**: Where possible, store the inputs and intermediate results of complex calculations directly on the relevant records. This makes the system's state self-documenting and easier to debug, inspect, and trust, rather than relying on dynamic calculations that can appear magical.
