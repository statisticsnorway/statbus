BEGIN;

\i test/setup.sql

\echo "Establish a baseline by capturing initial state of import_data_column (stable columns)"
CREATE TEMP TABLE import_data_column_baseline AS
SELECT
    step_id,
    priority,
    column_name,
    column_type,
    purpose::text AS purpose,
    is_nullable,
    default_value,
    is_uniquely_identifying
FROM public.import_data_column
ORDER BY step_id, priority NULLS FIRST, column_name;

\echo "Establish a baseline by capturing initial state of import_source_column for default definitions"
CREATE TEMP TABLE import_source_column_baseline AS
SELECT
    definition_id,
    priority,
    column_name
FROM public.import_source_column
WHERE definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
ORDER BY definition_id, priority, column_name;

\echo "Establish a baseline by capturing initial state of import_mapping for default definitions"
CREATE TEMP TABLE import_mapping_baseline AS
SELECT
    m.definition_id,
    isc.column_name AS source_column_name,
    m.source_expression,
    idc.column_name AS target_data_column_name,
    m.target_data_column_purpose::text AS target_data_column_purpose,
    m.is_ignored,
    m.source_value
FROM public.import_mapping m
LEFT JOIN public.import_source_column isc ON m.source_column_id = isc.id
LEFT JOIN public.import_data_column idc ON m.target_data_column_id = idc.id
WHERE m.definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
ORDER BY m.definition_id, source_column_name NULLS FIRST, source_expression, target_data_column_name;

\echo "Initial import_data_column state (stable columns):"
SELECT * FROM import_data_column_baseline;

\echo "Initial import_source_column state (default definitions):"
SELECT * FROM import_source_column_baseline;

\echo "Initial import_mapping state (default definitions):"
SELECT * FROM import_mapping_baseline;

\echo "---"
\echo "Testing stat_definition lifecycle hooks for import_data_column"
\echo "---"

\echo "Modify stat_definition"

\echo "Delete unused stat variable".
DELETE FROM public.stat_definition WHERE code = 'employees';

\echo "Make turnover the first variable"
UPDATE public.stat_definition SET priority = 1 wHERE code = 'turnover';

\echo "Add new custom variables"
INSERT INTO public.stat_definition(code, type, frequency, name, description, priority) VALUES
  ('men_employees','int','yearly','Number of men employed','The number of men receiving an official salary with government reporting.',2),
  ('women_employees','int','yearly','Number of women employed','The number of women receiving an official salary with government reporting.',3),
  ('children_employees','int','yearly','Number of children employed','The number of children receiving an official salary with government reporting.',4);

\echo "Stop using the children_employees, it can no longer be imported, but will be in statistics."
UPDATE public.stat_definition SET archived = true wHERE code = 'children_employees';

\echo "Track children by gender"
INSERT INTO public.stat_definition(code, type, frequency, name, description, priority) VALUES
  ('boy_employees','int','yearly','Number of boys employed','The number of boys receiving an official salary with government reporting.',5),
  ('girl_employees','int','yearly','Number of girls employed','The number of girls receiving an official salary with government reporting.',6);

\echo "Check generated code from stat_definition modifications"

\echo "Verifying data columns..."
\echo "  - Columns for deleted 'employees' should be gone (should be empty):"
SELECT 'employees_related_columns_exist' AS test, column_name
FROM public.import_data_column
WHERE column_name IN ('employees', 'employees_raw', 'stat_for_unit_employees_id');

\echo "  - Columns for archived 'children_employees' should not exist (should be empty):"
SELECT 'archived_children_employees_columns_exist' AS test, column_name
FROM public.import_data_column
WHERE column_name LIKE 'children_employees%';

\echo "  - Columns for new definitions should exist (should be empty):"
WITH expected AS (
  SELECT code, 3::bigint AS expected_count FROM (VALUES
    ('men_employees'), ('women_employees'), ('boy_employees'), ('girl_employees')
  ) AS t(code)
), actual AS (
  SELECT regexp_replace(column_name, '(_raw|stat_for_unit_|_id)', '', 'g') AS code, count(*) AS actual_count
  FROM public.import_data_column
  WHERE step_id = (SELECT id FROM public.import_step WHERE code = 'statistical_variables')
    AND regexp_replace(column_name, '(_raw|stat_for_unit_|_id)', '', 'g') IN (SELECT code FROM expected)
  GROUP BY 1
)
SELECT e.code, e.expected_count, COALESCE(a.actual_count, 0) AS actual_count
FROM expected e LEFT JOIN actual a ON e.code = a.code
WHERE COALESCE(a.actual_count, 0) <> e.expected_count;

\echo "Verifying source columns..."
\echo "  - Source column for deleted 'employees' should be gone (should be empty):"
SELECT 'employees_source_column_exists' AS test, definition_id, column_name
FROM public.import_source_column
WHERE column_name = 'employees' AND definition_id IN (SELECT id FROM public.import_definition WHERE custom = false);

\echo "  - Source column for archived 'children_employees' should not exist (should be empty):"
SELECT 'archived_children_employees_source_column_exists' AS test, definition_id, column_name
FROM public.import_source_column
WHERE column_name = 'children_employees' AND definition_id IN (SELECT id FROM public.import_definition WHERE custom = false);

\echo "  - Source columns for new definitions should exist for all default definitions (should be empty):"
WITH expected_codes AS (
  SELECT unnest(ARRAY['men_employees', 'women_employees', 'boy_employees', 'girl_employees']) AS code
), def_count AS (
  SELECT count(*) AS ct FROM public.import_definition WHERE custom = false
), actual_counts AS (
  SELECT column_name AS code, count(*) AS ct
  FROM public.import_source_column
  WHERE column_name IN (SELECT code FROM expected_codes)
    AND definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
  GROUP BY 1
)
SELECT ec.code, (SELECT ct FROM def_count) AS expected_count, COALESCE(ac.ct, 0) AS actual_count
FROM expected_codes ec LEFT JOIN actual_counts ac ON ec.code = ac.code
WHERE COALESCE(ac.ct, 0) <> (SELECT ct FROM def_count);

\echo "Establish a new baseline after stat_definition changes"
CREATE TEMP TABLE import_data_column_baseline_2 AS
SELECT
    step_id,
    priority,
    column_name,
    column_type,
    purpose::text AS purpose,
    is_nullable,
    default_value,
    is_uniquely_identifying
FROM public.import_data_column
ORDER BY step_id, priority NULLS FIRST, column_name;

\echo "Establish a new baseline for source columns after stat_definition changes"
CREATE TEMP TABLE import_source_column_baseline_2 AS
SELECT
    definition_id,
    priority,
    column_name
FROM public.import_source_column
WHERE definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
ORDER BY definition_id, priority, column_name;

\echo "Establish a new baseline for mappings after stat_definition changes"
CREATE TEMP TABLE import_mapping_baseline_2 AS
SELECT
    m.definition_id,
    isc.column_name AS source_column_name,
    m.source_expression,
    idc.column_name AS target_data_column_name,
    m.target_data_column_purpose::text AS target_data_column_purpose,
    m.is_ignored,
    m.source_value
FROM public.import_mapping m
LEFT JOIN public.import_source_column isc ON m.source_column_id = isc.id
LEFT JOIN public.import_data_column idc ON m.target_data_column_id = idc.id
WHERE m.definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
ORDER BY m.definition_id, source_column_name NULLS FIRST, source_expression, target_data_column_name;

\echo "---"
\echo "Testing external_ident_type lifecycle hooks for import_data_column"
\echo "---"

\echo "Modify external_ident_type"

\echo "Delete unused stat identifier".
DELETE FROM public.external_ident_type WHERE code = 'stat_ident';

\echo "Make tax_ident the first identifier"
UPDATE public.external_ident_type SET priority = 1 wHERE code = 'tax_ident';

\echo "Add new custom identifiers"
INSERT INTO public.external_ident_type(code, name, priority, description) VALUES
	('pin', 'Personal Identification Number', 2, 'Stable identifier provided by the governemnt and used by all individials who have a business just for themselves.'),
	('mobile', 'Mobile Number', 3, 'Mandated reporting by all phone companies.');

\echo "Stop using the mobile, peoples number changed to often, it can no longer be imported, but will be in statistics."
UPDATE public.external_ident_type SET archived = true wHERE code = 'mobile';

\echo "Check generated code from external_ident_type modifications"

\echo "Verifying data columns..."
\echo "  - Columns for deleted 'stat_ident' should be gone (should be empty):"
SELECT 'deleted_stat_ident_columns_exist' AS test, column_name
FROM public.import_data_column
WHERE column_name IN ('stat_ident_raw', 'legal_unit_stat_ident_raw');

\echo "  - Columns for archived 'mobile' should not exist (should be empty):"
SELECT 'archived_mobile_columns_exist' AS test, column_name
FROM public.import_data_column
WHERE column_name IN ('mobile_raw', 'legal_unit_mobile_raw');

\echo "  - Columns for new 'pin' identifier should exist (should be empty):"
WITH expected AS (
    SELECT 'pin_raw' AS column_name, 1::bigint AS expected_count
    UNION ALL SELECT 'legal_unit_pin_raw', 1
), actual AS (
    SELECT column_name, count(*) AS actual_count
    FROM public.import_data_column WHERE column_name IN (SELECT column_name FROM expected)
    GROUP BY 1
)
SELECT e.column_name, e.expected_count, COALESCE(a.actual_count, 0) AS actual_count
FROM expected e LEFT JOIN actual a ON e.column_name = a.column_name
WHERE COALESCE(a.actual_count, 0) <> e.expected_count;


\echo "Verifying source columns..."
\echo "  - Source columns for deleted 'stat_ident' should be gone (should be empty):"
SELECT 'deleted_stat_ident_source_columns_exist' AS test, column_name
FROM public.import_source_column
WHERE column_name IN ('stat_ident', 'legal_unit_stat_ident')
  AND definition_id IN (SELECT id FROM public.import_definition WHERE custom = false);

\echo "  - Source columns for archived 'mobile' should not exist (should be empty):"
SELECT 'archived_mobile_source_columns_exist' AS test, column_name
FROM public.import_source_column
WHERE column_name IN ('mobile', 'legal_unit_mobile')
  AND definition_id IN (SELECT id FROM public.import_definition WHERE custom = false);

\echo "  - Source columns for new 'pin' identifier should exist for all relevant default definitions (should be empty):"
WITH expected AS (
    SELECT 'pin' AS code, (SELECT count(*) FROM public.import_definition WHERE custom=false) AS expected_count
    UNION ALL
    SELECT 'legal_unit_pin' AS code,
           (SELECT count(*) FROM public.import_definition WHERE custom=false AND slug IN ('establishment_for_lu_job_provided', 'establishment_for_lu_source_dates')) AS expected_count
), actual AS (
    SELECT column_name AS code, count(*) AS actual_count
    FROM public.import_source_column
    WHERE column_name IN ('pin', 'legal_unit_pin') AND definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
    GROUP BY 1
)
SELECT e.code, e.expected_count, COALESCE(a.actual_count, 0) AS actual_count
FROM expected e LEFT JOIN actual a ON e.code = a.code
WHERE COALESCE(a.actual_count, 0) <> e.expected_count;

\echo "---"
\echo "Testing that data restoration after reset correctly restores the initial state"
\echo "---"

\echo "Calling reset to restore database (note: this incorrectly deletes system data modified during test)"
SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'all'::public.reset_scope));

\echo "System data is restored by the reset() function now."
-- The logic to re-insert system data has been moved into the public.reset()
-- function itself, making it a true "reset to factory defaults".
-- This simplifies tests and ensures consistent state restoration.

\echo "Checking if tables have been restored to their original baseline state after reset and data restoration"

\echo "Verifying import_data_column restoration (should be empty):"
(
    SELECT 'missing' AS state, step_id, column_name, column_type, purpose, is_nullable, default_value, is_uniquely_identifying FROM import_data_column_baseline
    EXCEPT
    SELECT 'missing' AS state, step_id, column_name, column_type, purpose::text, is_nullable, default_value, is_uniquely_identifying FROM public.import_data_column
) UNION ALL (
    SELECT 'added' AS state, step_id, column_name, column_type, purpose::text, is_nullable, default_value, is_uniquely_identifying FROM public.import_data_column
    EXCEPT
    SELECT 'added' AS state, step_id, column_name, column_type, purpose, is_nullable, default_value, is_uniquely_identifying FROM import_data_column_baseline
) ORDER BY state, step_id, column_name;

\echo "Verifying import_source_column restoration (should be empty):"
(
    SELECT 'missing' as state, definition_id, column_name FROM import_source_column_baseline
    EXCEPT
    SELECT 'missing' as state, definition_id, column_name FROM public.import_source_column WHERE definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
) UNION ALL (
    SELECT 'added' as state, definition_id, column_name FROM public.import_source_column WHERE definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
    EXCEPT
    SELECT 'added' as state, definition_id, column_name FROM import_source_column_baseline
) ORDER BY state, definition_id, column_name;

\echo "Verifying import_mapping restoration (should be empty):"
(
    SELECT 'missing' AS state, definition_id, source_column_name, source_expression, target_data_column_name, target_data_column_purpose, is_ignored, source_value FROM import_mapping_baseline
    EXCEPT
    SELECT 'missing' AS state, m.definition_id, isc.column_name, m.source_expression, idc.column_name, m.target_data_column_purpose::text, m.is_ignored, m.source_value
    FROM public.import_mapping m
    LEFT JOIN public.import_source_column isc ON m.source_column_id = isc.id
    LEFT JOIN public.import_data_column idc ON m.target_data_column_id = idc.id
    WHERE m.definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
) UNION ALL (
    SELECT 'added' AS state, m.definition_id, isc.column_name, m.source_expression, idc.column_name, m.target_data_column_purpose::text, m.is_ignored, m.source_value
    FROM public.import_mapping m
    LEFT JOIN public.import_source_column isc ON m.source_column_id = isc.id
    LEFT JOIN public.import_data_column idc ON m.target_data_column_id = idc.id
    WHERE m.definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
    EXCEPT
    SELECT 'added' AS state, definition_id, source_column_name, source_expression, target_data_column_name, target_data_column_purpose, is_ignored, source_value FROM import_mapping_baseline
) ORDER BY state, definition_id, source_column_name NULLS FIRST, target_data_column_name;

ROLLBACK;
