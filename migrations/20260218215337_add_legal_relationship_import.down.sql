-- Down Migration: Remove legal_relationship import support
BEGIN;

-- Remove default definitions (cascades to import_definition_step, import_source_column, import_mapping)
DELETE FROM public.import_definition WHERE slug IN ('legal_relationship_source_dates', 'legal_relationship_job_provided');

-- Remove data columns for the legal_relationship step (cascades from step deletion)
DELETE FROM public.import_data_column
WHERE step_id = (SELECT id FROM public.import_step WHERE code = 'legal_relationship');

-- Remove the import step
DELETE FROM public.import_step WHERE code = 'legal_relationship';

-- Drop procedures
DROP PROCEDURE IF EXISTS import.process_legal_relationship(INT, INTEGER, TEXT);
DROP PROCEDURE IF EXISTS import.analyse_legal_relationship(INT, INTEGER, TEXT);

-- Note: Cannot remove enum value 'legal_relationship' from import_mode in PostgreSQL.
-- The enum value will remain but be unused.

END;
