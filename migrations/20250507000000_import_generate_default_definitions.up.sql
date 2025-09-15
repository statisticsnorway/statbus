-- Migration
BEGIN;

-- Procedure to synchronize source columns and mappings for a specific step in a definition
CREATE OR REPLACE PROCEDURE import.synchronize_definition_step_mappings(p_definition_id INT, p_step_code TEXT)
LANGUAGE plpgsql AS $$
DECLARE
    v_data_col RECORD;
    v_source_col_id INT;
    v_max_priority INT;
    v_def public.import_definition;
BEGIN
    SELECT * INTO v_def FROM public.import_definition WHERE id = p_definition_id;
    -- Only synchronize active, system-provided (custom=FALSE) definitions
    IF NOT (v_def.active AND v_def.custom = FALSE) THEN
        RAISE DEBUG '[Sync Mappings Def ID %] Skipping sync for step %, definition is inactive or user-customized (custom=TRUE).', p_definition_id, p_step_code;
        RETURN;
    END IF;

    RAISE DEBUG '[Sync Mappings Def ID %] Synchronizing mappings for step % (Definition: active=%, custom=%).', p_definition_id, p_step_code, v_def.active, v_def.custom;

    FOR v_data_col IN
        SELECT
            dc.id AS data_column_id,
            dc.column_name AS data_column_name,
            regexp_replace(dc.column_name, '_raw$', '') AS source_column_name
        FROM public.import_data_column dc
        JOIN public.import_step s ON dc.step_id = s.id
        JOIN public.import_definition_step ids ON ids.step_id = s.id
        WHERE ids.definition_id = p_definition_id
          AND s.code = p_step_code
          AND dc.purpose = 'source_input'
    LOOP
        -- Ensure import_source_column exists
        SELECT id INTO v_source_col_id
        FROM public.import_source_column
        WHERE definition_id = p_definition_id AND column_name = v_data_col.source_column_name;

        IF NOT FOUND THEN
            SELECT COALESCE(MAX(priority), 0) + 1 INTO v_max_priority
            FROM public.import_source_column WHERE definition_id = p_definition_id;

            INSERT INTO public.import_source_column (definition_id, column_name, priority)
            VALUES (p_definition_id, v_data_col.source_column_name, v_max_priority)
            RETURNING id INTO v_source_col_id;
            RAISE DEBUG '[Sync Mappings Def ID %] Created source column "%" (ID: %) for data column ID %.', p_definition_id, v_data_col.source_column_name, v_source_col_id, v_data_col.data_column_id;
        END IF;

        -- Ensure import_mapping exists. If newly created by this sync, it should be a valid, non-ignored mapping.
        INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose, is_ignored)
        VALUES (p_definition_id, v_source_col_id, v_data_col.data_column_id, 'source_input'::public.import_data_column_purpose, FALSE)
        ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;
        -- If a mapping already exists (e.g., one that was manually set to is_ignored = TRUE for some reason, or a correctly configured one),
        -- DO NOTHING will preserve it. The primary goal here is to ensure that if no mapping exists, a valid, non-ignored one is created.

        RAISE DEBUG '[Sync Mappings Def ID %] Ensured mapping (is_ignored=FALSE if new) for source col ID % to data col ID %.', p_definition_id, v_source_col_id, v_data_col.data_column_id;

    END LOOP;

    -- Re-validate the definition after potential changes
    PERFORM admin.validate_import_definition(p_definition_id);
    RAISE DEBUG '[Sync Mappings Def ID %] Finished synchronizing mappings for step % and re-validated.', p_definition_id, p_step_code;

EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING '[Sync Mappings Def ID %] Error during import.synchronize_definition_step_mappings for step %: %', p_definition_id, p_step_code, SQLERRM;
END;
$$;

-- Procedure to synchronize all relevant steps for all active, system-provided (custom=FALSE) definitions
CREATE OR REPLACE PROCEDURE import.synchronize_default_definitions_all_steps()
LANGUAGE plpgsql AS $$
DECLARE
    v_def RECORD;
BEGIN
    RAISE DEBUG '--> Running import.synchronize_default_definitions_all_steps...';
    FOR v_def IN
        SELECT id FROM public.import_definition WHERE active = TRUE AND custom = FALSE
    LOOP
        RAISE DEBUG '  [-] Synchronizing definition ID: %', v_def.id;
        -- Sync for external_idents step
        IF EXISTS (SELECT 1 FROM public.import_definition_step ids JOIN public.import_step s ON ids.step_id = s.id WHERE ids.definition_id = v_def.id AND s.code = 'external_idents') THEN
            CALL import.synchronize_definition_step_mappings(v_def.id, 'external_idents');
        END IF;

        -- Sync for link_establishment_to_legal_unit step
        IF EXISTS (SELECT 1 FROM public.import_definition_step ids JOIN public.import_step s ON ids.step_id = s.id WHERE ids.definition_id = v_def.id AND s.code = 'link_establishment_to_legal_unit') THEN
            CALL import.synchronize_definition_step_mappings(v_def.id, 'link_establishment_to_legal_unit');
        END IF;

        -- Sync for statistical_variables step
        IF EXISTS (SELECT 1 FROM public.import_definition_step ids JOIN public.import_step s ON ids.step_id = s.id WHERE ids.definition_id = v_def.id AND s.code = 'statistical_variables') THEN
            CALL import.synchronize_definition_step_mappings(v_def.id, 'statistical_variables');
        END IF;
    END LOOP;
    RAISE DEBUG 'Finished import.synchronize_default_definitions_all_steps.';
END;
$$;

-- Procedure to clean up orphaned source columns and mappings for default definitions
CREATE OR REPLACE PROCEDURE import.cleanup_orphaned_synced_mappings()
LANGUAGE plpgsql AS $$
DECLARE
    v_def RECORD;
    v_source_col RECORD;
    v_data_column_exists BOOLEAN;
BEGIN
    RAISE DEBUG '--> Running import.cleanup_orphaned_synced_mappings...';
    FOR v_def IN
        SELECT id FROM public.import_definition WHERE active = TRUE AND custom = FALSE
    LOOP
        RAISE DEBUG '  [-] Checking definition ID: % for orphaned synced mappings.', v_def.id;
        FOR v_source_col IN
            SELECT isc.id AS source_column_id, isc.column_name
            FROM public.import_source_column isc
            WHERE isc.definition_id = v_def.id
        LOOP
            -- An import_source_column is an orphan ONLY if it is dynamically generated (i.e., its name
            -- matches a code in external_ident_type or stat_definition) AND its corresponding `source_input`
            -- data column no longer exists. Statically defined source columns are ignored.
            v_data_column_exists := true; -- Assume not an orphan by default
            IF v_source_col.column_name IN (SELECT code FROM public.external_ident_type) OR
               v_source_col.column_name IN (SELECT code FROM public.stat_definition) OR
               (v_source_col.column_name LIKE 'legal_unit_%' AND
                replace(v_source_col.column_name, 'legal_unit_', '') IN (SELECT code FROM public.external_ident_type))
            THEN
                -- This appears to be a dynamically managed source column. Check if its data column still exists.
                SELECT EXISTS (
                    SELECT 1
                    FROM public.import_definition_step ids
                    JOIN public.import_data_column idc ON ids.step_id = idc.step_id
                    WHERE ids.definition_id = v_def.id
                      AND idc.column_name = v_source_col.column_name || '_raw'
                      AND idc.purpose = 'source_input'
                ) INTO v_data_column_exists;
            END IF;

            IF NOT v_data_column_exists THEN
                RAISE DEBUG '    - Deleting orphaned source column ID % (name: "%") and its mappings for definition ID %.',
                            v_source_col.source_column_id, v_source_col.column_name, v_def.id;
                DELETE FROM public.import_source_column WHERE id = v_source_col.source_column_id; -- Cascades to import_mapping
            END IF;
        END LOOP;
        -- Re-validate the definition after potential cleanup
        PERFORM admin.validate_import_definition(v_def.id);
    END LOOP;
    RAISE DEBUG 'Finished import.cleanup_orphaned_synced_mappings.';
END;
$$;

-- Register lifecycle callback for synchronizing default definition mappings
-- This should run after data columns are generated/updated.
CALL lifecycle_callbacks.add(
    'import_sync_default_definition_mappings',
    ARRAY['public.external_ident_type', 'public.stat_definition']::regclass[], -- Listen to changes on these tables
    'import.synchronize_default_definitions_all_steps', -- Procedure to call
    'import.cleanup_orphaned_synced_mappings' -- Cleanup procedure
);

-- Initial call to synchronize mappings for existing default definitions
CALL import.synchronize_default_definitions_all_steps();


-- Helper function to link steps to a definition
CREATE OR REPLACE FUNCTION import.link_steps_to_definition(
    p_definition_id INT,
    p_step_codes TEXT[]
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO public.import_definition_step (definition_id, step_id)
    SELECT p_definition_id, s.id
    FROM public.import_step s
    WHERE s.code = ANY(p_step_codes);
END;
$$;

-- Helper function to create source columns and mappings for a definition.
-- This function handles two distinct cases for setting up mappings:
-- 1. If the definition's `valid_time_from` mode is 'time_context' or 'job_explicit', it creates mappings for `valid_from` and `valid_to` using `source_expression = 'default'`.
-- 2. It then iterates through the `p_source_columns` array, creating `import_source_column` records and mapping them to their corresponding `import_data_column` records. This handles all source-file-based mappings, including `valid_from`/`to` for the 'source_columns' mode.
CREATE OR REPLACE FUNCTION import.create_source_and_mappings_for_definition(
    p_definition_id INT,
    p_source_columns TEXT[] -- Array of source column names expected in the file
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_def public.import_definition;
    v_col_name TEXT;
    v_priority INT := 0;
    v_source_col_id INT;
    v_data_col_id INT;
    v_max_priority INT;
    v_col_rec RECORD;
BEGIN
    SELECT * INTO v_def FROM public.import_definition WHERE id = p_definition_id;

    -- Handle validity date mappings based on definition mode
    IF v_def.valid_time_from = 'job_provided' THEN
        FOR v_col_name IN VALUES ('valid_from'), ('valid_to') LOOP
            SELECT dc.id INTO v_data_col_id FROM public.import_data_column dc JOIN public.import_step s ON dc.step_id = s.id WHERE s.code = 'valid_time' AND dc.column_name = v_col_name || '_raw';
            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_expression, target_data_column_id, target_data_column_purpose)
                VALUES (p_definition_id, 'default', v_data_col_id, 'source_input'::public.import_data_column_purpose)
                ON CONFLICT (definition_id, target_data_column_id) WHERE is_ignored = false DO NOTHING;
            END IF;
        END LOOP;
    END IF;

    -- Create source columns and map them
    FOREACH v_col_name IN ARRAY p_source_columns LOOP
        v_priority := v_priority + 1;
        INSERT INTO public.import_source_column (definition_id, column_name, priority)
        VALUES (p_definition_id, v_col_name, v_priority)
        ON CONFLICT DO NOTHING RETURNING id INTO v_source_col_id;

        IF v_source_col_id IS NOT NULL THEN
            SELECT dc.id INTO v_data_col_id
            FROM public.import_definition_step ds
            JOIN public.import_data_column dc ON ds.step_id = dc.step_id
            WHERE ds.definition_id = p_definition_id AND dc.column_name = v_col_name || '_raw' AND dc.purpose = 'source_input';

            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose)
                VALUES (p_definition_id, v_source_col_id, v_data_col_id, 'source_input'::public.import_data_column_purpose)
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;
            ELSE
                INSERT INTO public.import_mapping (definition_id, source_column_id, is_ignored)
                VALUES (p_definition_id, v_source_col_id, TRUE)
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) WHERE target_data_column_id IS NULL DO NOTHING;
            END IF;
        END IF;
    END LOOP;

    -- Dynamically add and map source columns for Statistical Variables
    SELECT COALESCE(MAX(priority), v_priority) INTO v_max_priority FROM public.import_source_column WHERE definition_id = p_definition_id;
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT p_definition_id, stat.code, v_max_priority + ROW_NUMBER() OVER (ORDER BY stat.priority)
    FROM public.stat_definition_active stat ON CONFLICT (definition_id, column_name) DO NOTHING;

    FOR v_col_rec IN
        SELECT isc.id as source_col_id, isc.column_name as stat_code FROM public.import_source_column isc
        JOIN public.stat_definition_active sda ON isc.column_name = sda.code
        WHERE isc.definition_id = p_definition_id AND NOT EXISTS (
            SELECT 1 FROM public.import_mapping im WHERE im.definition_id = p_definition_id AND im.source_column_id = isc.id
        )
    LOOP
        SELECT dc.id INTO v_data_col_id FROM public.import_definition_step ds
        JOIN public.import_step s ON ds.step_id = s.id
        JOIN public.import_data_column dc ON ds.step_id = dc.step_id
        WHERE ds.definition_id = p_definition_id AND s.code = 'statistical_variables' AND dc.column_name = v_col_rec.stat_code || '_raw' AND dc.purpose = 'source_input';

        IF v_data_col_id IS NOT NULL THEN
            INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose)
            VALUES (p_definition_id, v_col_rec.source_col_id, v_data_col_id, 'source_input')
            ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;
        ELSE
            RAISE EXCEPTION '[Definition %] No matching source_input data column found in "statistical_variables" step for dynamically added stat source column "%".', p_definition_id, v_col_rec.stat_code;
        END IF;
    END LOOP;
END;
$$;


DO $$
DECLARE
    def_id INT;
    lu_steps TEXT[] := ARRAY['external_idents', 'data_source', 'valid_time', 'enterprise_link_for_legal_unit', 'status', 'legal_unit', 'physical_location', 'postal_location', 'primary_activity', 'secondary_activity', 'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'];
    es_steps TEXT[] := ARRAY['external_idents', 'data_source', 'valid_time', 'link_establishment_to_legal_unit', 'status', 'establishment', 'physical_location', 'postal_location', 'primary_activity', 'secondary_activity', 'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'];
    es_no_lu_steps TEXT[] := ARRAY['external_idents', 'data_source', 'valid_time', 'enterprise_link_for_establishment', 'status', 'establishment', 'physical_location', 'postal_location', 'primary_activity', 'secondary_activity', 'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'];

    lu_source_cols TEXT[] := ARRAY[
        'name', 'birth_date', 'death_date',
        'physical_address_part1', 'physical_address_part2', 'physical_address_part3', 'physical_postcode', 'physical_postplace', 'physical_latitude', 'physical_longitude', 'physical_altitude', 'physical_region_code', 'physical_country_iso_2',
        'postal_address_part1', 'postal_address_part2', 'postal_address_part3', 'postal_postcode', 'postal_postplace', 'postal_region_code', 'postal_country_iso_2',
        'web_address', 'email_address', 'phone_number', 'landline', 'mobile_number', 'fax_number',
        'primary_activity_category_code', 'secondary_activity_category_code',
        'sector_code', 'unit_size_code', 'status_code', 'data_source_code', 'legal_form_code',
        'tag_path'
    ];
    lu_explicit_source_cols TEXT[] := lu_source_cols || ARRAY['valid_from', 'valid_to'];

    es_source_cols TEXT[] := ARRAY[
        'name', 'birth_date', 'death_date',
        'physical_address_part1', 'physical_address_part2', 'physical_address_part3', 'physical_postcode', 'physical_postplace', 'physical_latitude', 'physical_longitude', 'physical_altitude', 'physical_region_code', 'physical_country_iso_2',
        'postal_address_part1', 'postal_address_part2', 'postal_address_part3', 'postal_postcode', 'postal_postplace', 'postal_region_code', 'postal_country_iso_2',
        'web_address', 'email_address', 'phone_number', 'landline', 'mobile_number', 'fax_number',
        'primary_activity_category_code', 'secondary_activity_category_code',
        'sector_code', 'unit_size_code', 'status_code', 'data_source_code',
        'tag_path',
        'legal_unit_tax_ident','legal_unit_stat_ident'
    ];
    es_explicit_source_cols TEXT[] := es_source_cols || ARRAY['valid_from', 'valid_to'];

    es_no_lu_source_cols TEXT[] := ARRAY[
        'name', 'birth_date', 'death_date',
        'physical_address_part1', 'physical_address_part2', 'physical_address_part3', 'physical_postcode', 'physical_postplace', 'physical_latitude', 'physical_longitude', 'physical_altitude', 'physical_region_code', 'physical_country_iso_2',
        'postal_address_part1', 'postal_address_part2', 'postal_address_part3', 'postal_postcode', 'postal_postplace', 'postal_region_code', 'postal_country_iso_2',
        'web_address', 'email_address', 'phone_number', 'landline', 'mobile_number', 'fax_number',
        'primary_activity_category_code', 'secondary_activity_category_code',
        'sector_code', 'unit_size_code', 'status_code', 'data_source_code',
        'tag_path'
    ];
    es_no_lu_explicit_source_cols TEXT[] := es_no_lu_source_cols || ARRAY['valid_from', 'valid_to'];

    active_ext_ident_codes TEXT[];
    nlr_data_source_id INT;
    census_data_source_id INT;
    survey_data_source_id INT;
    -- other_data_source_id INT; -- Declared if needed later
BEGIN
    -- Data sources are expected to be populated by the seeding mechanism (e.g., from dbseed/data_source.csv)
    -- This migration will verify their existence and use their IDs.

    SELECT id INTO nlr_data_source_id FROM public.data_source WHERE code = 'nlr';
    IF NOT FOUND THEN RAISE EXCEPTION 'Data source "nlr" not found or could not be created.'; END IF;

    SELECT id INTO census_data_source_id FROM public.data_source WHERE code = 'census';
    IF NOT FOUND THEN RAISE EXCEPTION 'Data source "census" not found or could not be created.'; END IF;

    SELECT id INTO survey_data_source_id FROM public.data_source WHERE code = 'survey';
    IF NOT FOUND THEN RAISE EXCEPTION 'Data source "survey" not found or could not be created.'; END IF;

    -- Ensure external_ident data columns are generated (should be idempotent)
    CALL import.generate_external_ident_data_columns();

    -- Get active external identifier codes to append to source column lists
    SELECT array_agg(code ORDER BY priority) INTO active_ext_ident_codes FROM public.external_ident_type_active;
    IF active_ext_ident_codes IS NULL THEN
        active_ext_ident_codes := ARRAY[]::TEXT[];
    END IF;

    lu_source_cols := lu_source_cols || active_ext_ident_codes;
    lu_explicit_source_cols := lu_explicit_source_cols || active_ext_ident_codes;
    es_source_cols := es_source_cols || active_ext_ident_codes;
    es_explicit_source_cols := es_explicit_source_cols || active_ext_ident_codes;
    es_no_lu_source_cols := es_no_lu_source_cols || active_ext_ident_codes;
    es_no_lu_explicit_source_cols := es_no_lu_explicit_source_cols || active_ext_ident_codes;

    -- 1. Legal Units (Job Provided Time)
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid, data_source_id, custom)
    VALUES ('legal_unit_job_provided', 'Legal Units (Job Provided Time)', 'Import legal units. Validity is determined by a time context or explicit dates provided when the job is created.', 'insert_or_update', 'legal_unit', 'job_provided', false, nlr_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, lu_steps);
    PERFORM import.create_source_and_mappings_for_definition(def_id, lu_source_cols);

    -- 2. Legal Units (via Source File Dates)
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid, data_source_id, custom)
    VALUES ('legal_unit_source_dates', 'Legal Units (Source Dates)', 'Import legal units. Validity period is determined by explicit valid_from and valid_to columns in the source file.', 'insert_or_update', 'legal_unit', 'source_columns', false, nlr_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, lu_steps);
    PERFORM import.create_source_and_mappings_for_definition(def_id, lu_explicit_source_cols);

    -- 3. Establishments for Legal Unit (Job Provided Time)
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid, data_source_id, custom)
    VALUES ('establishment_for_lu_job_provided', 'Establishments for LU (Job Provided Time)', 'Import establishments for LUs. Validity is determined by a time context or explicit dates provided on the job.', 'insert_or_update', 'establishment_formal', 'job_provided', false, nlr_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, es_steps);
    PERFORM import.create_source_and_mappings_for_definition(def_id, es_source_cols);

    -- 4. Establishments for Legal Unit (via Source File Dates)
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid, data_source_id, custom)
    VALUES ('establishment_for_lu_source_dates', 'Establishments for LU (Source Dates)', 'Import establishments linked to legal units. Validity is determined by explicit valid_from and valid_to columns in the source file.', 'insert_or_update', 'establishment_formal', 'source_columns', false, nlr_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, es_steps);
    PERFORM import.create_source_and_mappings_for_definition(def_id, es_explicit_source_cols);

    -- 5. Establishments without Legal Unit (Job Provided Time)
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid, data_source_id, custom)
    VALUES ('establishment_without_lu_job_provided', 'Establishments w/o LU (Job Provided Time)', 'Import standalone establishments. Validity is determined by a time context or explicit dates on the job.', 'insert_or_update', 'establishment_informal', 'job_provided', false, census_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, es_no_lu_steps);
    PERFORM import.create_source_and_mappings_for_definition(def_id, es_no_lu_source_cols);

    -- 6. Establishments without Legal Unit (via Source File Dates)
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid, data_source_id, custom)
    VALUES ('establishment_without_lu_source_dates', 'Establishments w/o LU (Source Dates)', 'Import standalone establishments. Validity is determined by explicit valid_from and valid_to columns in the source file.', 'insert_or_update', 'establishment_informal', 'source_columns', false, census_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, es_no_lu_steps);
    PERFORM import.create_source_and_mappings_for_definition(def_id, es_no_lu_explicit_source_cols);

    -- 7. Unit Stats Update (Job Provided Time)
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid, data_source_id, custom)
    VALUES ('generic_unit_stats_update_job_provided', 'Unit Stats Update (Job Provided Time)', 'Updates statistical variables for existing units. Validity is determined by a time context or explicit dates on the job.', 'replace_only', 'generic_unit', 'job_provided', false, survey_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, ARRAY['external_idents', 'data_source', 'valid_time', 'statistical_variables', 'edit_info', 'metadata']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, active_ext_ident_codes); -- Pass active external ident codes

    -- 8. Unit Stats Update (via Source File Dates)
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid_time_from, valid, data_source_id, custom)
    VALUES ('generic_unit_stats_update_source_dates', 'Unit Stats Update (Source Dates)', 'Updates statistical variables for existing units using explicit valid_from/valid_to from the source file.', 'replace_only', 'generic_unit', 'source_columns', false, survey_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, ARRAY['external_idents', 'data_source', 'valid_time', 'statistical_variables', 'edit_info', 'metadata']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, ARRAY['valid_from', 'valid_to'] || active_ext_ident_codes); -- Pass valid_from, valid_to, and active external ident codes

END $$;

-- Validate all definitions and fail migration if any are invalid
DO $$
DECLARE
    def RECORD;
    invalid_definitions_summary TEXT := '';
    first_error BOOLEAN := TRUE;
BEGIN
    RAISE NOTICE 'Validating all import definitions created/updated by this migration...';
    FOR def IN SELECT id, slug, valid, validation_error FROM public.import_definition LOOP
        -- Explicitly call validation for each definition.
        -- The triggers on import_definition and related tables should have already called this,
        -- but calling it again ensures any inter-dependencies or order-of-operation issues
        -- in the trigger-based validation are caught here before committing the migration.
        PERFORM admin.validate_import_definition(def.id);

        -- Re-fetch the definition to check its status after explicit validation
        SELECT slug, valid, validation_error INTO def.slug, def.valid, def.validation_error
        FROM public.import_definition WHERE id = def.id;

        IF NOT def.valid THEN
            IF first_error THEN
                invalid_definitions_summary := format('Definition "%s" (ID: %s) is invalid: %s', def.slug, def.id, def.validation_error);
                first_error := FALSE;
            ELSE
                invalid_definitions_summary := invalid_definitions_summary || format('; Definition "%s" (ID: %s) is invalid: %s', def.slug, def.id, def.validation_error);
            END IF;
        END IF;
    END LOOP;

    IF invalid_definitions_summary != '' THEN
        RAISE EXCEPTION 'Migration failed: One or more import definitions are invalid after creation/update. Errors: %', invalid_definitions_summary;
    ELSE
        RAISE NOTICE 'All import definitions successfully validated.';
    END IF;
END $$;

END;
