BEGIN;

\i test/setup.sql

CALL test.set_user_from_email('test.admin@statbus.org');

\echo "Test: Verify structure of _data tables for default import definitions"
\echo "--------------------------------------------------------------------"
\echo "This test creates a minimal import job for each default definition"
\echo "and then uses psql's \d command to inspect the structure of the"
\echo "dynamically created _data table. This helps ensure that all expected"
\echo "columns (both static and dynamically generated based on steps and types)"
\echo "are present in the _data tables."

-- Create jobs with hardcoded short slugs
DO $$
DECLARE
    v_def_id INT;
    v_job_slug_val TEXT;
    v_def_slug TEXT;
BEGIN
    -- legal_unit_current_year
    v_def_slug := 'legal_unit_current_year';
    v_job_slug_val := 't54_lu_cy';
    SELECT id INTO v_def_id FROM public.import_definition WHERE slug = v_def_slug;
    IF NOT FOUND THEN RAISE WARNING 'Definition slug % not found, cannot create job.', v_def_slug;
    ELSE
        DELETE FROM public.import_job WHERE slug = v_job_slug_val;
        INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
        VALUES (v_def_id, v_job_slug_val, 'Test 54 job for ' || v_def_slug, 'Automated test 54', 'Test 54');
    END IF;

    -- legal_unit_explicit_dates
    v_def_slug := 'legal_unit_explicit_dates';
    v_job_slug_val := 't54_lu_ed';
    SELECT id INTO v_def_id FROM public.import_definition WHERE slug = v_def_slug;
    IF NOT FOUND THEN RAISE WARNING 'Definition slug % not found, cannot create job.', v_def_slug;
    ELSE
        DELETE FROM public.import_job WHERE slug = v_job_slug_val;
        INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
        VALUES (v_def_id, v_job_slug_val, 'Test 54 job for ' || v_def_slug, 'Automated test 54', 'Test 54');
    END IF;

    -- establishment_for_lu_current_year
    v_def_slug := 'establishment_for_lu_current_year';
    v_job_slug_val := 't54_est_lu_cy';
    SELECT id INTO v_def_id FROM public.import_definition WHERE slug = v_def_slug;
    IF NOT FOUND THEN RAISE WARNING 'Definition slug % not found, cannot create job.', v_def_slug;
    ELSE
        DELETE FROM public.import_job WHERE slug = v_job_slug_val;
        INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
        VALUES (v_def_id, v_job_slug_val, 'Test 54 job for ' || v_def_slug, 'Automated test 54', 'Test 54');
    END IF;

    -- establishment_for_lu_explicit_dates
    v_def_slug := 'establishment_for_lu_explicit_dates';
    v_job_slug_val := 't54_est_lu_ed';
    SELECT id INTO v_def_id FROM public.import_definition WHERE slug = v_def_slug;
    IF NOT FOUND THEN RAISE WARNING 'Definition slug % not found, cannot create job.', v_def_slug;
    ELSE
        DELETE FROM public.import_job WHERE slug = v_job_slug_val;
        INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
        VALUES (v_def_id, v_job_slug_val, 'Test 54 job for ' || v_def_slug, 'Automated test 54', 'Test 54');
    END IF;

    -- establishment_without_lu_current_year
    v_def_slug := 'establishment_without_lu_current_year';
    v_job_slug_val := 't54_est_wolu_cy';
    SELECT id INTO v_def_id FROM public.import_definition WHERE slug = v_def_slug;
    IF NOT FOUND THEN RAISE WARNING 'Definition slug % not found, cannot create job.', v_def_slug;
    ELSE
        DELETE FROM public.import_job WHERE slug = v_job_slug_val;
        INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
        VALUES (v_def_id, v_job_slug_val, 'Test 54 job for ' || v_def_slug, 'Automated test 54', 'Test 54');
    END IF;

    -- establishment_without_lu_explicit_dates
    v_def_slug := 'establishment_without_lu_explicit_dates';
    v_job_slug_val := 't54_est_wolu_ed';
    SELECT id INTO v_def_id FROM public.import_definition WHERE slug = v_def_slug;
    IF NOT FOUND THEN RAISE WARNING 'Definition slug % not found, cannot create job.', v_def_slug;
    ELSE
        DELETE FROM public.import_job WHERE slug = v_job_slug_val;
        INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
        VALUES (v_def_id, v_job_slug_val, 'Test 54 job for ' || v_def_slug, 'Automated test 54', 'Test 54');
    END IF;
END;
$$;

\echo ""
\echo "Verifying created import_job records:"
\echo "====================================="
SELECT
    ij.slug, 
    ij.data_table_name, 
    id.slug AS definition_slug
FROM public.import_job ij
JOIN public.import_definition id ON ij.definition_id = id.id
WHERE ij.slug IN ('t54_lu_cy', 't54_lu_ed', 't54_est_lu_cy', 't54_est_lu_ed', 't54_est_wolu_cy', 't54_est_wolu_ed')
ORDER BY ij.slug;

-- Inspect data table structures directly
\echo ""
\echo "Inspecting _data table structures:"
\echo "=================================="
\pset pager off

\echo '\nDescribing table for definition: legal_unit_current_year (Job: t54_lu_cy, Data Table: public.t54_lu_cy_data)'
\d public.t54_lu_cy_data
\echo '--------------------------------------------------'

\echo '\nDescribing table for definition: legal_unit_explicit_dates (Job: t54_lu_ed, Data Table: public.t54_lu_ed_data)'
\d public.t54_lu_ed_data
\echo '--------------------------------------------------'

\echo '\nDescribing table for definition: establishment_for_lu_current_year (Job: t54_est_lu_cy, Data Table: public.t54_est_lu_cy_data)'
\d public.t54_est_lu_cy_data
\echo '--------------------------------------------------'

\echo '\nDescribing table for definition: establishment_for_lu_explicit_dates (Job: t54_est_lu_ed, Data Table: public.t54_est_lu_ed_data)'
\d public.t54_est_lu_ed_data
\echo '--------------------------------------------------'

\echo '\nDescribing table for definition: establishment_without_lu_current_year (Job: t54_est_wolu_cy, Data Table: public.t54_est_wolu_cy_data)'
\d public.t54_est_wolu_cy_data
\echo '--------------------------------------------------'

\echo '\nDescribing table for definition: establishment_without_lu_explicit_dates (Job: t54_est_wolu_ed, Data Table: public.t54_est_wolu_ed_data)'
\d public.t54_est_wolu_ed_data
\echo '--------------------------------------------------'

ROLLBACK;
