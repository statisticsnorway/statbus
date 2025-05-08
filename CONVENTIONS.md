This document outlines general conventions for the STATBUS project, focusing on backend, database, and infrastructure aspects. For Next.js application-specific conventions, see `app/CONVENTIONS.md`.

This project uses PostgreSQL (17+) and PostgREST (12+) for its backend.
It is deployed on custom servers behind Caddy with HTTPS.

## SQL
When defining functions and procedures use the function name as part of the literal string quote
for the body and specify the LANGUAGE before the body, so one knows how to parse it up front.
Ensure that parameters are documentation friendly, and therefore always use the long form
to avoid ambiguity.
```
CREATE FUNCTION public.example(email text) RETURNS void LANGUAGE plpgsql AS $example$
BEGIN
  ...
  SELECT * FROM ...
  WHERE email = example.email
  ...
END;
$$;
```

When calling functions with multiple arguments (3+), use named arguments for clarity, arg1 => val1, arg2 => val2, etc.

PostgreSQL 17 supports the new MERGE syntax for efficient batch handling.

When creating large string for format, use $$ to allow inline ' in comments, so
```plpgsql
format($$
  ... -- A comment with a '
$$, arg1, arg2, ...)
```

### SQL Testing
Is done with pg_regress with test/ as base.
Run with `./devops/manage-statbus.sh test [all|xx_the_test_name]`.

### SQL Naming conventions
Column name
* `x_id` is a foreign key to table `x`
* `x_ident` is an external identifier, not originating from the database
* `x_at` is a TIMESTAMPTZ (with timezone)
* `x_on` is a DATE

## Migrations
Migration files are placed in `migrations/YYYYMMDDHHmmSS_snake_case_description.up.sql` and `migrations/YYYYMMDDHHmm_snake_case_description.down.sql`.
For details on running migrations, see the main `README.md` file.

## Development Notes
When CWD is the app dir then shell commands must remove the initial 'app/' from paths.
