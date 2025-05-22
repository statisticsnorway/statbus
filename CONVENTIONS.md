This document outlines general conventions for the STATBUS project, focusing on backend, database, and infrastructure aspects. For Next.js application-specific conventions, see `app/CONVENTIONS.md`.

This project uses PostgreSQL (17+) and PostgREST (12+) for its backend.
It is deployed on custom servers behind Caddy with HTTPS.

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
    - Use dollar-quoting (e.g., `format($$ ... $$)`) for `format()` strings to allow unescaped single quotes within.
    - For `format()` calls with multiple parameters, especially if parameters are repeated or the string is complex, use numbered arguments.
      For example: `format('Testing %3$s, %2$s, %1$s', 'one' /* %1 */, 'two' /* %2 */, 'three' /* %3 */);`
      This improves readability and maintainability.
- **Table Aliases**: Prefer explicit `AS` for table aliases, e.g., `FROM my_table AS mt`. For common data table aliases in import procedures, `AS dt` is preferred.
- **Batch Operations**: Utilize PostgreSQL 17+ `MERGE` syntax for efficient batch handling where appropriate.
- **Database Inspection**: Use `psql` for direct database inspection and querying during development. For example, to list available import definitions: `echo 'SELECT slug, name FROM public.import_definition;' | ./devops/manage-statbus.sh psql`

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
For details on running migrations, see the main `README.md` file.

## General Development Principles
- **Fail Fast**:
  - Functionality that is expected to work should fail immediately and clearly if an unexpected state or error occurs.
  - Do not mask or work around problems; instead, provide sufficient error or debugging information to facilitate a solution. This is crucial for maintaining system integrity and simplifying troubleshooting, especially in backend processes and SQL procedures.
- **Dialogue Language**:
  - All development-related dialogue, including interactions with AI assistants, should be conducted in English to ensure clarity and broad understanding.

## Development Notes
When CWD is the app dir then shell commands must remove the initial 'app/' from paths.
