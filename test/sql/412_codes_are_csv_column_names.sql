BEGIN;

\i test/setup.sql

-- svpafa: a statistical variable's code and an external identifier type's code are
-- column names in import CSV files and the targets of import mappings, so the database
-- accepts only lower-case letters, digits and underscores (^[a-z0-9_]+$), the same rule
-- the admin forms apply.

-- The lifecycle callbacks report each regenerated index as a NOTICE; the test reads rows.
SET client_min_messages TO warning;

SELECT conrelid::regclass AS table_name, conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conname IN ('stat_definition_code_is_csv_column_name', 'external_ident_type_code_is_csv_column_name')
ORDER BY conname;

-- A valid code is accepted.
INSERT INTO public.stat_definition (code, type, frequency, name, priority, enabled)
VALUES ('demo_variable_2', 'int', 'yearly', 'Demo Variable', 90, false);
INSERT INTO public.external_ident_type (code, name, priority, enabled)
VALUES ('demo_ident_2', 'Demo Ident', 90, false);
SELECT code FROM public.stat_definition WHERE code = 'demo_variable_2';
SELECT code FROM public.external_ident_type WHERE code = 'demo_ident_2';

-- A code that is not a column name is refused by the constraint.
SAVEPOINT before_invalid;
\set ON_ERROR_STOP off
INSERT INTO public.stat_definition (code, type, frequency, name, priority, enabled)
VALUES ('Demo Variable', 'int', 'yearly', 'Demo Variable', 91, false);
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_invalid;
\set ON_ERROR_STOP off
INSERT INTO public.external_ident_type (code, name, priority, enabled)
VALUES ('Demo Variable', 'Demo Ident', 91, false);
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_invalid;
\set ON_ERROR_STOP off
UPDATE public.stat_definition SET code = 'Demo-Variable' WHERE code = 'demo_variable_2';
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_invalid;

SELECT count(*) AS stored_invalid_codes
FROM (SELECT code FROM public.stat_definition UNION ALL SELECT code FROM public.external_ident_type) AS c
WHERE c.code !~ '^[a-z0-9_]+$';

ROLLBACK;
