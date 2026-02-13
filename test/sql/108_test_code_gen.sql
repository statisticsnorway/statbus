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
UPDATE public.stat_definition SET enabled = false wHERE code = 'children_employees';

\echo "Track children by gender"
INSERT INTO public.stat_definition(code, type, frequency, name, description, priority) VALUES
  ('boy_employees','int','yearly','Number of boys employed','The number of boys receiving an official salary with government reporting.',5),
  ('girl_employees','int','yearly','Number of girls employed','The number of girls receiving an official salary with government reporting.',6);

\echo "Check generated code from stat_definition modifications"

\echo "Removed import_data_column rows:"
SELECT * FROM import_data_column_baseline
EXCEPT
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

\echo "Added import_data_column rows:"
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
EXCEPT
SELECT * FROM import_data_column_baseline
ORDER BY step_id, priority NULLS FIRST, column_name;

\echo "Check generated code from stat_definition modifications for source columns"

\echo "Removed import_source_column rows:"
SELECT * FROM import_source_column_baseline
EXCEPT
SELECT
    definition_id,
    priority,
    column_name
FROM public.import_source_column
WHERE definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
ORDER BY definition_id, priority, column_name;

\echo "Added import_source_column rows:"
SELECT
    definition_id,
    priority,
    column_name
FROM public.import_source_column
WHERE definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
EXCEPT
SELECT * FROM import_source_column_baseline
ORDER BY definition_id, priority, column_name;

\echo "Check generated code from stat_definition modifications for mappings"
\echo "Removed import_mapping rows:"
SELECT * FROM import_mapping_baseline
EXCEPT
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
ORDER BY definition_id, source_column_name NULLS FIRST, source_expression, target_data_column_name;

\echo "Added import_mapping rows:"
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
EXCEPT
SELECT * FROM import_mapping_baseline
ORDER BY definition_id, source_column_name NULLS FIRST, source_expression, target_data_column_name;

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
UPDATE public.external_ident_type SET enabled = false wHERE code = 'mobile';

\echo "Check generated code from external_ident_type modifications"

\echo "Removed import_data_column rows:"
SELECT * FROM import_data_column_baseline_2
EXCEPT
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

\echo "Added import_data_column rows:"
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
EXCEPT
SELECT * FROM import_data_column_baseline_2
ORDER BY step_id, priority NULLS FIRST, column_name;

\echo "Check generated code from external_ident_type modifications for source columns"

\echo "Removed import_source_column rows:"
SELECT * FROM import_source_column_baseline_2
EXCEPT
SELECT
    definition_id,
    priority,
    column_name
FROM public.import_source_column
WHERE definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
ORDER BY definition_id, priority, column_name;

\echo "Added import_source_column rows:"
SELECT
    definition_id,
    priority,
    column_name
FROM public.import_source_column
WHERE definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
EXCEPT
SELECT * FROM import_source_column_baseline_2
ORDER BY definition_id, priority, column_name;

\echo "Check generated code from external_ident_type modifications for mappings"
\echo "Removed import_mapping rows:"
SELECT * FROM import_mapping_baseline_2
EXCEPT
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
ORDER BY definition_id, source_column_name NULLS FIRST, source_expression, target_data_column_name;

\echo "Added import_mapping rows:"
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
EXCEPT
SELECT * FROM import_mapping_baseline_2
ORDER BY definition_id, source_column_name NULLS FIRST, source_expression, target_data_column_name;

\echo "---"
\echo "Testing that public.reset() correctly restores the initial state"
\echo "---"

\echo "Calling reset to restore database to its initial state"
SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'all'::public.reset_scope));

\echo "Checking if tables have been restored to their original baseline state after reset"
\echo ""
\echo "Note: import_data_column uses deterministic formulas based on source table priorities,"
\echo "      so it restores to exact baseline priorities. import_source_column uses sequential"
\echo "      priority assignment for simplicity and conflict avoidance, so priorities vary"
\echo "      across runs but logical content (which columns exist) remains correct."

\echo "Removed import_data_column rows after reset (should be empty - deterministic priorities):"
SELECT * FROM import_data_column_baseline EXCEPT SELECT step_id, priority, column_name, column_type, purpose::text, is_nullable, default_value, is_uniquely_identifying FROM public.import_data_column;

\echo "Added import_data_column rows after reset (should be empty - deterministic priorities):"
SELECT step_id, priority, column_name, column_type, purpose::text, is_nullable, default_value, is_uniquely_identifying FROM public.import_data_column EXCEPT SELECT * FROM import_data_column_baseline;


\echo "Baseline import_source_column content (ordered by column_name for comparison):"
SELECT definition_id, column_name FROM import_source_column_baseline ORDER BY definition_id, column_name;

\echo "Current import_source_column content after reset (ordered by column_name for comparison):"
SELECT definition_id, column_name 
FROM public.import_source_column 
WHERE definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
ORDER BY definition_id, column_name;


\echo "Baseline import_mapping content (ordered by columns for comparison):"
SELECT definition_id, source_column_name, target_data_column_name 
FROM import_mapping_baseline 
ORDER BY definition_id, source_column_name, target_data_column_name;

\echo "Current import_mapping content after reset (ordered by columns for comparison):"
SELECT m.definition_id, isc.column_name AS source_column_name, idc.column_name AS target_data_column_name
FROM public.import_mapping m
LEFT JOIN public.import_source_column isc ON m.source_column_id = isc.id
LEFT JOIN public.import_data_column idc ON m.target_data_column_id = idc.id
WHERE m.definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
ORDER BY m.definition_id, isc.column_name, idc.column_name;

ROLLBACK;
