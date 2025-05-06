-- Down Migration 20250505120000: generate_default_import_definitions
BEGIN;

-- Define the slugs created in the corresponding UP migration
WITH slugs_to_delete AS (
    SELECT slug FROM (VALUES
        ('legal_unit_current_year'),
        ('legal_unit_explicit_dates'),
        ('establishment_for_lu_current_year'),
        ('establishment_for_lu_explicit_dates'),
        ('establishment_without_lu_current_year'),
        ('establishment_without_lu_explicit_dates'),
        ('unit_stats_update_current_year'),       -- Added missing slug
        ('unit_stats_update_explicit_dates')      -- Added missing slug
    ) AS t(slug)
)
-- Delete the import definitions. Related data in import_job, import_mapping,
-- import_source_column, and import_definition_step will be deleted via CASCADE.
DELETE FROM public.import_definition idf
WHERE idf.slug IN (SELECT slug FROM slugs_to_delete);

-- Drop helper functions created by the UP migration
DROP FUNCTION IF EXISTS admin.link_steps_to_definition(INT, TEXT[]);
DROP FUNCTION IF EXISTS admin.create_source_and_mappings_for_definition(INT, TEXT[]);

END;
