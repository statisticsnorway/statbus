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
UPDATE public.external_ident_type SET archived = true wHERE code = 'mobile';

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
\echo "Testing that data restoration after reset correctly restores the initial state"
\echo "---"

\echo "Calling reset to restore database (note: this incorrectly deletes system data modified during test)"
SELECT jsonb_pretty(public.reset(confirmed := true, scope := 'all'::public.reset_scope));

\echo "Re-inserting system data that was deleted during the test to trigger regeneration"
-- This simulates restoring the DB to its true pre-test state.
-- The INSERTs will trigger the lifecycle callbacks and regenerate the required import columns and mappings.

-- Restore system stat_definition
-- NOTE: The ON CONFLICT is necessary because reset() does not clear the sequence, leading to key conflicts
-- if we only used INSERT. This ensures the data is in the state defined by migrations.
INSERT INTO public.stat_definition(id, code, type, frequency, name, description, priority, archived)
OVERRIDING SYSTEM VALUE
VALUES
  (1, 'employees','int','yearly','Number of employees','The number of people receiving an official salary with government reporting.',2, false),
  (2, 'turnover','float','yearly','Turnover','The amount of money taken by a business in a particular period.',1, false)
ON CONFLICT (id) DO UPDATE SET
    code = EXCLUDED.code,
    type = EXCLUDED.type,
    frequency = EXCLUDED.frequency,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    priority = EXCLUDED.priority,
    archived = EXCLUDED.archived;

-- Restore system external_ident_type
INSERT INTO public.external_ident_type(id, code, name, priority, description, archived)
OVERRIDING SYSTEM VALUE
VALUES
    (1, 'tax_ident', 'Tax Identifier', 1, 'Official tax identification number provided by the government.', false),
    (2, 'stat_ident', 'Statistical Identifier', 2, 'Identifier assigned by the statistical office for internal tracking.', false)
ON CONFLICT (id) DO UPDATE SET
    code = EXCLUDED.code,
    name = EXCLUDED.name,
    priority = EXCLUDED.priority,
    description = EXCLUDED.description,
    archived = EXCLUDED.archived;

\echo "Checking if tables have been restored to their original baseline state after reset and data restoration"

\echo "Removed import_data_column rows after restoration (should be empty, ignoring priority):"
SELECT step_id, column_name, column_type, purpose, is_nullable, default_value, is_uniquely_identifying FROM import_data_column_baseline
EXCEPT
SELECT step_id, column_name, column_type, purpose::text, is_nullable, default_value, is_uniquely_identifying FROM public.import_data_column ORDER BY 1,2,3;

\echo "Added import_data_column rows after restoration (should be empty, ignoring priority):"
SELECT step_id, column_name, column_type, purpose::text, is_nullable, default_value, is_uniquely_identifying FROM public.import_data_column
EXCEPT
SELECT step_id, column_name, column_type, purpose, is_nullable, default_value, is_uniquely_identifying FROM import_data_column_baseline ORDER BY 1,2,3;


\echo "Removed import_source_column rows after restoration (should be empty, ignoring priority):"
SELECT definition_id, column_name FROM import_source_column_baseline
EXCEPT
SELECT definition_id, column_name FROM public.import_source_column WHERE definition_id IN (SELECT id FROM public.import_definition WHERE custom = false) ORDER BY 1,2;

\echo "Added import_source_column rows after restoration (should be empty, ignoring priority):"
SELECT definition_id, column_name FROM public.import_source_column WHERE definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
EXCEPT
SELECT definition_id, column_name FROM import_source_column_baseline ORDER BY 1,2;


\echo "Removed import_mapping rows after restoration (should be empty):"
SELECT * FROM import_mapping_baseline
EXCEPT
SELECT m.definition_id, isc.column_name, m.source_expression, idc.column_name, m.target_data_column_purpose::text, m.is_ignored, m.source_value
FROM public.import_mapping m
LEFT JOIN public.import_source_column isc ON m.source_column_id = isc.id
LEFT JOIN public.import_data_column idc ON m.target_data_column_id = idc.id
WHERE m.definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
ORDER BY 1,2,4;

\echo "Added import_mapping rows after restoration (should be empty):"
SELECT m.definition_id, isc.column_name, m.source_expression, idc.column_name, m.target_data_column_purpose::text, m.is_ignored, m.source_value
FROM public.import_mapping m
LEFT JOIN public.import_source_column isc ON m.source_column_id = isc.id
LEFT JOIN public.import_data_column idc ON m.target_data_column_id = idc.id
WHERE m.definition_id IN (SELECT id FROM public.import_definition WHERE custom = false)
EXCEPT
SELECT * FROM import_mapping_baseline
ORDER BY 1,2,4;

ROLLBACK;
