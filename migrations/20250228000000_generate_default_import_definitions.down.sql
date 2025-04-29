-- Down Migration 20250228000000: generate_default_import_definitions
BEGIN;

-- Define the slugs created in the corresponding UP migration
WITH slugs_to_delete AS (
    SELECT slug FROM (VALUES
        ('legal_unit_current_year'),
        ('legal_unit_explicit_dates'),
        ('establishment_for_lu_current_year'),
        ('establishment_for_lu_explicit_dates'),
        ('establishment_without_lu_current_year'),
        ('establishment_without_lu_explicit_dates')
    ) AS t(slug)
),
-- Find the definition IDs for these slugs
definitions_to_delete AS (
    SELECT id
    FROM public.import_definition idf
    JOIN slugs_to_delete std ON idf.slug = std.slug
),
-- Delete related import jobs first
deleted_jobs AS (
    DELETE FROM public.import_job ij
    WHERE ij.definition_id IN (SELECT id FROM definitions_to_delete)
    RETURNING *
)
-- Finally, delete the import definitions (cascades to mapping/source_column)
DELETE FROM public.import_definition idf
WHERE idf.id IN (SELECT id FROM definitions_to_delete);

END;
