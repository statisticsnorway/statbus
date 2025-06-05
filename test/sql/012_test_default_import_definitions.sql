BEGIN;

\i test/setup.sql

-- No specific user context is strictly needed for querying definition tables,
-- but setting it to admin for consistency with other tests.
CALL test.set_user_from_email('test.admin@statbus.org');

\echo "Test: Verify mappings of key identifier source columns in default import definitions"
\echo "------------------------------------------------------------------------------------"
\echo "These tests check if source columns (like 'tax_ident' from a CSV) are correctly mapped"
\echo "to the appropriate data columns within the import steps of default definitions."
\echo "A common issue is 'tax_ident' not being mapped to the 'external_ident_value' data column"
\echo "in the 'external_idents' step, which is necessary for identifying units."

\echo ""
\echo "1. Definition: legal_unit_current_year, Source Column: tax_ident"
\echo "   ----------------------------------------------------------------"
\echo "   Expected: The 'tax_ident' source column should be mapped to the 'external_ident_value' data column"
\echo "             (purpose: 'external_ident_value') within the 'external_idents' import step."
\echo "             The 'external_ident_type_code' data column (purpose: 'external_ident_type_code')"
\echo "             within the same step should effectively be 'tax_ident' for this mapping."
SELECT
    id.slug AS definition_slug,
    isc.column_name AS source_column_name,
    isc.priority AS source_column_priority,
    im.id IS NOT NULL AS is_mapped,
    COALESCE(target_dc.column_name, 'N/A') AS target_data_column_name,
    COALESCE(target_dc.purpose::text, 'N/A') AS target_data_column_purpose,
    COALESCE(target_step.code, 'N/A') AS target_step_code
FROM public.import_definition id
JOIN public.import_source_column isc ON isc.definition_id = id.id
LEFT JOIN public.import_mapping im ON im.source_column_id = isc.id AND im.definition_id = id.id
LEFT JOIN public.import_data_column target_dc ON im.target_data_column_id = target_dc.id
LEFT JOIN public.import_step target_step ON target_dc.step_id = target_step.id
WHERE id.slug = 'legal_unit_current_year'
  AND isc.column_name = 'tax_ident';

\echo ""
\echo "2. Definition: establishment_for_lu_current_year, Source Column: tax_ident (for the establishment itself)"
\echo "   -------------------------------------------------------------------------------------------------------"
\echo "   Expected: Similar to legal units, the 'tax_ident' source column for an establishment should be mapped"
\echo "             to 'external_ident_value' (purpose: 'external_ident_value') in the 'external_idents' step."
SELECT
    id.slug AS definition_slug,
    isc.column_name AS source_column_name,
    isc.priority AS source_column_priority,
    im.id IS NOT NULL AS is_mapped,
    COALESCE(target_dc.column_name, 'N/A') AS target_data_column_name,
    COALESCE(target_dc.purpose::text, 'N/A') AS target_data_column_purpose,
    COALESCE(target_step.code, 'N/A') AS target_step_code
FROM public.import_definition id
JOIN public.import_source_column isc ON isc.definition_id = id.id
LEFT JOIN public.import_mapping im ON im.source_column_id = isc.id AND im.definition_id = id.id
LEFT JOIN public.import_data_column target_dc ON im.target_data_column_id = target_dc.id
LEFT JOIN public.import_step target_step ON target_dc.step_id = target_step.id
WHERE id.slug = 'establishment_for_lu_current_year'
  AND isc.column_name = 'tax_ident';

\echo ""
\echo "3. Definition: establishment_for_lu_current_year, Source Column: legal_unit_tax_ident (for linking)"
\echo "   ---------------------------------------------------------------------------------------------------"
\echo "   Expected: This 'legal_unit_tax_ident' source column (used to link an establishment to its legal unit)"
\echo "             should be mapped to the 'legal_unit_tax_ident' data column (purpose: 'source_input')"
\echo "             within the 'link_establishment_to_legal_unit' import step."
SELECT
    id.slug AS definition_slug,
    isc.column_name AS source_column_name,
    isc.priority AS source_column_priority,
    im.id IS NOT NULL AS is_mapped,
    COALESCE(target_dc.column_name, 'N/A') AS target_data_column_name,
    COALESCE(target_dc.purpose::text, 'N/A') AS target_data_column_purpose,
    COALESCE(target_step.code, 'N/A') AS target_step_code
FROM public.import_definition id
JOIN public.import_source_column isc ON isc.definition_id = id.id
LEFT JOIN public.import_mapping im ON im.source_column_id = isc.id AND im.definition_id = id.id
LEFT JOIN public.import_data_column target_dc ON im.target_data_column_id = target_dc.id
LEFT JOIN public.import_step target_step ON target_dc.step_id = target_step.id
WHERE id.slug = 'establishment_for_lu_current_year'
  AND isc.column_name = 'legal_unit_tax_ident';

\echo ""
\echo "4. Test dynamic updates to 'external_idents' step data columns via external_ident_type changes"
\echo "   ------------------------------------------------------------------------------------------"

\echo ""
\echo "   4a. Archive 'tax_ident' and insert 'vat_ident' as a new active external_ident_type"
-- Ensure user context allows modification if RLS/permissions are very strict, though admin should be fine.
-- CALL test.set_user_from_email('test.admin@statbus.org'); -- Already set at the beginning

-- Archive tax_ident
UPDATE public.external_ident_type SET archived = true WHERE code = 'tax_ident';
DO $$ BEGIN RAISE NOTICE 'Archived tax_ident'; END; $$;

-- Insert vat_ident (or ensure it's active with the correct priority if it somehow exists)
-- tax_ident was priority 35. stat_ident is 36. We can reuse 35 for vat_ident.
INSERT INTO public.external_ident_type (code, name, priority, description, archived)
VALUES ('vat_ident', 'VAT Identifier', 35, 'Value Added Tax Identifier (dynamic test)', false)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    priority = EXCLUDED.priority,
    description = EXCLUDED.description,
    archived = EXCLUDED.archived;
DO $$ BEGIN RAISE NOTICE 'Inserted/Updated vat_ident'; END; $$;

-- Display current active external_ident_types and all data columns for external_idents step
\echo "   Active external_ident_types after modification:"
SELECT code, name, priority, archived FROM public.external_ident_type WHERE archived = false ORDER BY priority;

\echo ""
\echo "   4b. Verify 'import_data_column's for 'external_idents' step reflect these changes"
\echo "       Expected: 'tax_ident' data column removed from 'external_idents' step, 'vat_ident' data column added."
SELECT dc.column_name, dc.purpose, dc.column_type
FROM public.import_data_column dc
JOIN public.import_step s ON dc.step_id = s.id
WHERE s.code = 'external_idents' AND dc.purpose = 'source_input'
ORDER BY dc.column_name;

\echo ""
\echo "   4c. Verify mapping for 'legal_unit_current_year' and (now archived) 'tax_ident'"
\echo "       Expected: The 'tax_ident' source column on the definition is removed because its external_ident_type was archived."
\echo "                 Therefore, no mapping exists, and the query should return 0 rows."
SELECT
    id.slug AS definition_slug,
    isc.column_name AS source_column_name,
    isc.priority AS source_column_priority,
    im.id IS NOT NULL AS is_mapped_to_external_idents_step_dc, -- This specific mapping should be gone
    COALESCE(target_dc.column_name, 'N/A') AS target_data_column_name,
    COALESCE(target_dc.purpose::text, 'N/A') AS target_data_column_purpose,
    COALESCE(target_step.code, 'N/A') AS target_step_code
FROM public.import_definition id
JOIN public.import_source_column isc ON isc.definition_id = id.id AND isc.column_name = 'tax_ident'
LEFT JOIN public.import_mapping im ON im.source_column_id = isc.id AND im.definition_id = id.id
LEFT JOIN public.import_data_column target_dc ON im.target_data_column_id = target_dc.id
LEFT JOIN public.import_step target_step ON target_dc.step_id = target_step.id AND target_step.code = 'external_idents' -- Crucial: only check mappings to data_columns within external_idents step
WHERE id.slug = 'legal_unit_current_year';

\echo ""
\echo "   4d. Verify mapping for 'legal_unit_current_year' and new 'vat_ident'"
\echo "       Expected: A 'vat_ident' source column is automatically created and mapped on the 'legal_unit_current_year' definition"
\echo "                 because 'vat_ident' became an active external_ident_type. (Query should return 1 row)"
SELECT
    id.slug AS definition_slug,
    isc.column_name AS source_column_name,
    isc.priority AS source_column_priority,
    im.id IS NOT NULL AS is_mapped,
    COALESCE(target_dc.column_name, 'N/A') AS target_data_column_name,
    COALESCE(target_dc.purpose::text, 'N/A') AS target_data_column_purpose,
    COALESCE(target_step.code, 'N/A') AS target_step_code
FROM public.import_definition id
JOIN public.import_source_column isc ON isc.definition_id = id.id AND isc.column_name = 'vat_ident' -- This join condition will find the auto-created source column
LEFT JOIN public.import_mapping im ON im.source_column_id = isc.id AND im.definition_id = id.id
LEFT JOIN public.import_data_column target_dc ON im.target_data_column_id = target_dc.id
LEFT JOIN public.import_step target_step ON target_dc.step_id = target_step.id
WHERE id.slug = 'legal_unit_current_year';

ROLLBACK;
