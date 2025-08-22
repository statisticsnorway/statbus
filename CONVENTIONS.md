This document outlines general conventions for the STATBUS project, focusing on backend, database, and infrastructure aspects. For Next.js application-specific conventions, see `app/CONVENTIONS.md`.

This project uses PostgreSQL (17+) and PostgREST (12+) for its backend.
It is deployed on custom servers behind Caddy with HTTPS.

## Tools
When you suggest commands in the regular response (*NOT* inside a SEARCH/REPLACE) on the form
```bash
cmd1
cmd2
```
Then they are presented to the user who can accept running them, and the results are returned to you.

Key tools available for you to suggest:
- **`rg` (ripgrep)**: Your primary tool for fast, powerful code searching. Use it to find definitions, locate files, or understand code relationships.
- **`tree`**: List files to understand directory structures.
- **`head`**: Inspect the beginning of files to quickly understand their structure and content.
- **`ls`**: Check file sizes to determine if they should be read or inspected.
- **`echo "..." | ./devops/manage-statbus.sh psql`**: Run arbitrary SQL for debugging or inspection. You can also write complex queries to a temporary `.sql` file and pipe it.

For file system operations and large-scale edits, prefer suggesting shell commands over generating `SEARCH/REPLACE` blocks where appropriate. This is faster and more efficient.
- Use `rm` to delete files and `git mv` to move or rename them.
- For simple content replacement (e.g., replacing an entire file's contents), `echo "new content" > filename` can be used instead of a large `SEARCH/REPLACE` block.
- For large-scale, repetitive search-and-replace operations across multiple files, powerful tools like `ruplacer` and `renamer` are available and should be used.

## SQL
- **Function/Procedure Definitions**:
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
- **Function Calls**: For calls with 3+ arguments, use named arguments (e.g., `arg1 => val1`).
- **String Literals for `format()`**:
    - Always prefer dollar-quoting (e.g., `format($$ ... $$)`) for the main dynamic SQL string. This avoids having to escape single quotes inside the SQL.
    - **Nesting**: When nesting dollar-quoted strings (e.g., a dynamic SQL string that itself contains another `format()` call), use named dollar quotes for the outer string to avoid conflicts. The convention is to use a descriptive name like `$SQL$` or `$jsonb_expr$`. This is especially common inside function bodies, which already use a named quote (e.g., `$function_name$`).
    - For `format()` calls with multiple parameters, especially if parameters repeat, use numbered placeholders for clarity:
      - `%1$I` for the 1st parameter as an identifier, `%2$L` for the 2nd as a literal, `%3$s` for the 3rd as a plain string, etc.
      - Example: `format($$Testing %3$s, %2$s, %1$s$$, 'one' /* %1 */, 'two' /* %2 */, 'three' /* %3 */);`
    - Prefer parameter binding with `EXECUTE ... USING` for large arrays or values rather than interpolating with `%L` where possible.

    Good
    ```sql
    -- Dollar-quoted format() string; identifier and literal are numbered; batch array is passed via USING.
    EXECUTE format($$
        UPDATE public.%1$I AS dt SET
            last_completed_priority = %2$L
        WHERE dt.row_id = ANY($1) AND dt.action = 'skip'
    $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */)
    USING p_batch_row_ids;
    ```

    Also good (embedding quotes safely without doubling them)
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

    Also good (nested dollar-quoting)
    ```sql
    -- The outer string uses a named quote ($jsonb_expr$) to avoid conflicting with the inner $$
    v_error_sql := $jsonb_expr$
        jsonb_build_object('latitude', CASE ... THEN format($$Value %1$s out of range$$, lat_val) ... END)
    $jsonb_expr$;
    ```

    Avoid
    ```sql
    -- Hard to read and easy to break: manual '' escaping inside single-quoted format string
    EXECUTE format('UPDATE public.%s SET note = ''it'''''s broken'' WHERE id = %s', tbl, id);
    ```

    Notes
    - Use `%I` for identifiers, `%L` for SQL literals, and `%s` for raw string insertion.
    - Keep the SQL readable by aligning numbered placeholders with inline comments that show which parameter they refer to.
- **Table Aliases**: Prefer explicit `AS` for table aliases, e.g., `FROM my_table AS mt`. For common data table aliases in import procedures, `AS dt` is preferred.
- **Batch Operations**: Utilize PostgreSQL 17+ `MERGE` syntax for efficient batch handling where appropriate.
- **Database Inspection**: Use `psql` for direct database inspection and querying during development. For example, to list available import definitions: `echo 'SELECT slug, name FROM public.import_definition;' | ./devops/manage-statbus.sh psql`

For a super compact data model for you reference, ask for doc/data-model.md.

### SQL Testing
- Use pg_regress with `test/` as the base directory.
- Run tests via `./devops/manage-statbus.sh test [all|xx_the_test_name]`.

### SQL Naming conventions
Column name
* `x_id` is a foreign key to table `x`
* `x_ident` is an external identifier, not originating from the database
* `x_at` is a TIMESTAMPTZ (with timezone)
* `x_on` is a DATE

## Migrations
Migration files are placed in `migrations/YYYYMMDDHHmmSS_snake_case_description.up.sql` and `migrations/YYYYMMDDHHmm_snake_case_description.down.sql`.
Migrations are managed using the `statbus` CLI tool.
- To create a new migration: `./cli/bin/statbus migrate new --description "your description"`
- To apply pending migrations: `./cli/bin/statbus migrate up`
- To roll back the last migration: `./cli/bin/statbus migrate down`

For more details, see the main `README.md` file or run `./cli/bin/statbus migrate --help`.

## The Iterative Development Cycle
All development work, especially bug fixing, must follow a rigorous, hypothesis-driven cycle to ensure progress is verifiable and the system remains stable. A task is not complete until the final step of this cycle has been successfully executed.

### 1. Formulate and State a Hypothesis
- **Action:** Before making any code changes, clearly state your hypothesis about the root cause of the problem in `journal.md`. This creates a permanent record of the debugging process.
- **Example:** "Hypothesis: The test regressions are caused by the 'scorched earth' `replace` logic deleting child records that tests expect to survive a partial import."

### 2. Create or Identify a Reproducing Test
- **Action:** Before proposing a fix, ensure a test case exists that isolates the bug. This test must fail before the fix and is expected to pass after.

### 3. Propose a Change and State the Expected Outcome
- **Action:** Propose the specific code changes (using `SEARCH/REPLACE` blocks). Alongside the changes, explicitly state what the change is expected to achieve.
- **Example:** "Hope/Assumption: Applying this conditional deletion logic will prevent unintended data loss. The failing tests (`203`, `302`, `303`) will now pass."

### 4. Gather Real-World Data
- **Action:** After the user applies the changes, request that they run the relevant tests to gather empirical evidence of the change's impact.
- **Standard Command**: Use the project's testing script to run tests (e.g., `./devops/manage-statbus.sh test 203_legal_units_consecutive_days`).

### 5. Analyze Results and Verify Hypothesis
- **Action:** Carefully inspect the test output.
  - **If Successful:** The hypothesis is confirmed. The fix worked as expected.
  - **If Unsuccessful:** The hypothesis was incorrect. Analyze the new data to form a new hypothesis and return to Step 1. If the change was incorrect, it must be reverted.

### 6. Conclude and Update Documentation
- **Action:** Only after the fix has been successfully verified in Step 5, update `todo.md` to move the task to a "done" state (e.g., `[x]`).

## General Development Principles
- **Fail Fast**:
  - Functionality that is expected to work should fail immediately and clearly if an unexpected state or error occurs.
  - Do not mask or work around problems; instead, provide sufficient error or debugging information to facilitate a solution. This is crucial for maintaining system integrity and simplifying troubleshooting, especially in backend processes and SQL procedures.
- **Declarative Transparency**:
  - Where possible, store the inputs and intermediate results of complex calculations directly on the relevant records. This makes the system's state self-documenting and easier to debug, inspect, and trust, rather than relying on dynamic calculations that can appear magical.
