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
        SELECT dc.id AS data_column_id, dc.column_name AS data_column_name
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
        WHERE definition_id = p_definition_id AND column_name = v_data_col.data_column_name;

        IF NOT FOUND THEN
            SELECT COALESCE(MAX(priority), 0) + 1 INTO v_max_priority
            FROM public.import_source_column WHERE definition_id = p_definition_id;

            INSERT INTO public.import_source_column (definition_id, column_name, priority)
            VALUES (p_definition_id, v_data_col.data_column_name, v_max_priority)
            RETURNING id INTO v_source_col_id;
            RAISE DEBUG '[Sync Mappings Def ID %] Created source column "%" (ID: %) for data column ID %.', p_definition_id, v_data_col.data_column_name, v_source_col_id, v_data_col.data_column_id;
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
    v_step_codes_to_check TEXT[] := ARRAY['external_idents', 'statistical_variables', 'link_establishment_to_legal_unit'];
    v_current_step_code TEXT;
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
            v_data_column_exists := FALSE;
            -- Check if this source column name corresponds to a data column in any of the relevant steps for this definition
            FOREACH v_current_step_code IN ARRAY v_step_codes_to_check
            LOOP
                IF EXISTS (
                    SELECT 1
                    FROM public.import_definition_step ids
                    JOIN public.import_step s ON ids.step_id = s.id
                    JOIN public.import_data_column idc ON idc.step_id = s.id
                    WHERE ids.definition_id = v_def.id
                      AND s.code = v_current_step_code
                      AND idc.column_name = v_source_col.column_name
                      AND idc.purpose = 'source_input'
                ) THEN
                    v_data_column_exists := TRUE;
                    EXIT; -- Found corresponding data column, no need to check other steps for this source_col
                END IF;
            END LOOP;

            IF NOT v_data_column_exists THEN
                -- This source column does not correspond to an existing data column in the relevant steps.
                -- It might be an orphaned synchronized column.
                -- We also need to ensure it's part of an 'is_ignored=TRUE' mapping,
                -- as manually added (is_ignored=FALSE) source columns should not be auto-cleaned.
                IF EXISTS (
                    SELECT 1 FROM public.import_mapping im
                    WHERE im.definition_id = v_def.id
                      AND im.source_column_id = v_source_col.source_column_id
                      AND im.is_ignored = TRUE
                ) OR NOT EXISTS ( -- Or if it has no mappings at all (less likely but possible if sync failed midway)
                    SELECT 1 FROM public.import_mapping im
                    WHERE im.definition_id = v_def.id
                      AND im.source_column_id = v_source_col.source_column_id
                ) THEN
                    RAISE DEBUG '    - Deleting orphaned source column ID % (name: "%") and its mappings for definition ID %.',
                                v_source_col.source_column_id, v_source_col.column_name, v_def.id;
                    DELETE FROM public.import_source_column WHERE id = v_source_col.source_column_id; -- Cascades to import_mapping
                END IF;
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

-- Helper function to create source columns and mappings for a definition
CREATE OR REPLACE FUNCTION import.create_source_and_mappings_for_definition(
    p_definition_id INT,
    p_source_columns TEXT[] -- Array of source column names expected in the file
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_col_name TEXT;
    v_priority INT := 0;
    v_source_col_id INT;
    v_data_col_id INT;
    v_max_priority INT;
    v_debug_info TEXT;
    v_col_rec RECORD; -- Added declaration for the loop variable
BEGIN
    RAISE NOTICE '[Def ID: %] create_source_and_mappings_for_definition: Received p_source_columns: %', p_definition_id, p_source_columns;

    -- Create source columns based on input array (which now includes external ident codes)
    FOREACH v_col_name IN ARRAY p_source_columns
    LOOP
        v_priority := v_priority + 1;
        INSERT INTO public.import_source_column (definition_id, column_name, priority)
        VALUES (p_definition_id, v_col_name, v_priority)
        ON CONFLICT DO NOTHING
        RETURNING id INTO v_source_col_id;

        -- Map static source column to corresponding data column
        IF v_source_col_id IS NOT NULL THEN
            -- Find the target data column by joining through the steps linked to this definition
            SELECT dc.id INTO v_data_col_id
            FROM public.import_definition_step ds
            JOIN public.import_data_column dc ON ds.step_id = dc.step_id
            WHERE ds.definition_id = p_definition_id
              AND dc.column_name = v_col_name
              AND dc.purpose = 'source_input';

            IF v_data_col_id IS NOT NULL THEN
                INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose)
                VALUES (p_definition_id, v_source_col_id, v_data_col_id, 'source_input'::public.import_data_column_purpose)
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;
            ELSE
                -- If no target_data_column is found, mark this source_column as ignored
                INSERT INTO public.import_mapping (definition_id, source_column_id, is_ignored, target_data_column_id, target_data_column_purpose, source_value, source_expression)
                VALUES (p_definition_id, v_source_col_id, TRUE, NULL, NULL, NULL, NULL)
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) WHERE target_data_column_id IS NULL -- Handle potential conflict if an ignored mapping already exists
                DO NOTHING; -- If it already exists as an ignored mapping, do nothing.
                RAISE DEBUG '[Definition %] Source column "%" (ID: %) has no target_data_column, marked as ignored.', p_definition_id, v_col_name, v_source_col_id;
                IF p_definition_id IN (23, 24) THEN
                    RAISE NOTICE '[Def ID: %] Source column % (ID: %) marked as ignored.', p_definition_id, v_col_name, v_source_col_id;
                END IF;
            END IF;
        END IF;
        IF p_definition_id IN (23, 24) AND v_source_col_id IS NOT NULL THEN
            RAISE NOTICE '[Def ID: %] Processed source column: %. Target data_col_id: % (Source Col ID: %)', p_definition_id, v_col_name, v_data_col_id, v_source_col_id;
        END IF;
    END LOOP;

    -- Add dynamic source columns for Statistical Variables
    -- External Ident source columns are now created by the main loop as their codes are part of p_source_columns.
    SELECT COALESCE(MAX(priority), v_priority) INTO v_max_priority FROM public.import_source_column WHERE definition_id = p_definition_id;
    INSERT INTO public.import_source_column (definition_id, column_name, priority)
    SELECT p_definition_id, stat.code, v_max_priority + ROW_NUMBER() OVER (ORDER BY stat.priority)
    FROM public.stat_definition_active stat
    ON CONFLICT (definition_id, column_name) DO NOTHING;

    -- Mapping for external identifiers is now handled by the main loop,
    -- as their codes are included in p_source_columns and target data columns
    -- are expected to be present from import.generate_external_ident_data_columns().

    -- Create mappings for dynamically added statistical variable source columns
    FOR v_col_rec IN
        SELECT isc.id as source_col_id, isc.column_name as stat_code
        FROM public.import_source_column isc
        JOIN public.stat_definition_active sda ON isc.column_name = sda.code -- Ensure it's a known stat
        WHERE isc.definition_id = p_definition_id
          AND NOT EXISTS ( -- Avoid re-mapping if already handled by p_source_columns (unlikely for stats)
              SELECT 1 FROM public.import_mapping im
              WHERE im.definition_id = p_definition_id AND im.source_column_id = isc.id
          )
    LOOP
        -- Find the target data column for this stat (should be linked to 'statistical_variables' step)
        SELECT dc.id INTO v_data_col_id
        FROM public.import_definition_step ds
        JOIN public.import_step s ON ds.step_id = s.id
        JOIN public.import_data_column dc ON ds.step_id = dc.step_id
        WHERE ds.definition_id = p_definition_id
          AND s.code = 'statistical_variables' -- The step that defines data columns for stats
          AND dc.column_name = v_col_rec.stat_code
          AND dc.purpose = 'source_input';

        IF v_data_col_id IS NOT NULL THEN
            INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id, target_data_column_purpose)
            VALUES (p_definition_id, v_col_rec.source_col_id, v_data_col_id, 'source_input')
            ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;
        ELSE
            -- This should now be a fatal error if a stat_definition_active exists,
            -- its import_source_column was created, but its import_data_column under 'statistical_variables' step was not.
            RAISE EXCEPTION '[Definition %] No matching source_input data column found in "statistical_variables" step for dynamically added stat source column "%". Mapping cannot be created. This indicates an issue with import_data_column setup for stats.',
                             p_definition_id, v_col_rec.stat_code;
        END IF;
    END LOOP;

    IF p_definition_id IN (23, 24) THEN
        DECLARE
            mapped_info TEXT;
        BEGIN
            RAISE NOTICE '[Def ID: %] Debugging for definition % after all mapping attempts:', p_definition_id, p_definition_id;

            SELECT string_agg(
                       format('MappingID: %s, Ignored: %s, SourceColName: %s (ID: %s) -> TargetDataColName: %s (ID: %s, StepCode: %s, Purpose: %s)',
                              im.id, im.is_ignored, isc.column_name, im.source_column_id,
                              idc.column_name, im.target_data_column_id, s.code, idc.purpose),
                       E'\n'
                   )
            INTO mapped_info
            FROM public.import_mapping im
            LEFT JOIN public.import_source_column isc ON im.source_column_id = isc.id AND isc.definition_id = im.definition_id
            LEFT JOIN public.import_data_column idc ON im.target_data_column_id = idc.id
            LEFT JOIN public.import_step s ON idc.step_id = s.id
            WHERE im.definition_id = p_definition_id;
            RAISE NOTICE '[Def ID: %] All import_mappings for this definition:\n%', p_definition_id, COALESCE(mapped_info, 'NONE');

            SELECT string_agg(
                       format('SourceColName: %s (ID: %s), Priority: %s',
                              isc.column_name, isc.id, isc.priority),
                       E'\n'
                   )
            INTO mapped_info -- reuse variable
            FROM public.import_source_column isc
            WHERE isc.definition_id = p_definition_id;
            RAISE NOTICE '[Def ID: %] All import_source_columns for this definition:\n%', p_definition_id, COALESCE(mapped_info, 'NONE');

            SELECT string_agg(
                       format('DataColName: %s (ID: %s, StepCode: %s, Purpose: %s, UniquelyIdentifying: %s)',
                              idc.column_name, idc.id, s.code, idc.purpose, idc.is_uniquely_identifying),
                        E'\n'
                    )
            INTO mapped_info -- reuse
            FROM public.import_data_column idc
            JOIN public.import_step s ON idc.step_id = s.id
            JOIN public.import_definition_step ids ON ids.step_id = s.id
            WHERE ids.definition_id = p_definition_id AND s.code = 'external_idents';
            RAISE NOTICE '[Def ID: %] All import_data_columns for external_idents step for this definition:\n%', p_definition_id, COALESCE(mapped_info, 'NONE');

            SELECT string_agg(
                       format('DataColName: %s (ID: %s, StepCode: %s, Purpose: %s, UniquelyIdentifying: %s)',
                              idc.column_name, idc.id, s.code, idc.purpose, idc.is_uniquely_identifying),
                        E'\n'
                    )
            INTO mapped_info -- reuse
            FROM public.import_data_column idc
            JOIN public.import_step s ON idc.step_id = s.id
            JOIN public.import_definition_step ids ON ids.step_id = s.id
            WHERE ids.definition_id = p_definition_id AND idc.column_name = 'data_source_code';
            RAISE NOTICE '[Def ID: %] All import_data_columns named "data_source_code" for this definition:\n%', p_definition_id, COALESCE(mapped_info, 'NONE');

        END;
    END IF;
END;
$$;


DO $$
DECLARE
    def_id INT;
    lu_steps TEXT[] := ARRAY['external_idents', 'enterprise_link_for_legal_unit', 'status', 'legal_unit', 'physical_location', 'postal_location', 'primary_activity', 'secondary_activity', 'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'];
    es_steps TEXT[] := ARRAY['external_idents', 'link_establishment_to_legal_unit', 'status', 'establishment', 'physical_location', 'postal_location', 'primary_activity', 'secondary_activity', 'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'];
    es_no_lu_steps TEXT[] := ARRAY['external_idents', 'enterprise_link_for_establishment', 'status', 'establishment', 'physical_location', 'postal_location', 'primary_activity', 'secondary_activity', 'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'];

    lu_source_cols TEXT[] := ARRAY[
        'tax_ident','stat_ident',
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
        'tax_ident','stat_ident',
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
        'tax_ident','stat_ident',
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

    -- 1. Legal unit with time_context for current year
    INSERT INTO public.import_definition (slug, name, note, time_context_ident, strategy, mode, valid, data_source_id, custom)
    VALUES ('legal_unit_current_year', 'Legal Unit - Current Year', 'Import legal units with validity period set to current year', 'r_year_curr', 'insert_or_replace', 'legal_unit', false, nlr_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, lu_steps || ARRAY['valid_time_from_context']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, lu_source_cols);

    -- 2. Legal unit with explicit valid_from/valid_to
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid, data_source_id, custom)
    VALUES ('legal_unit_explicit_dates', 'Legal Unit - Explicit Dates', 'Import legal units with explicit valid_from and valid_to columns', 'insert_or_replace', 'legal_unit', false, nlr_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, lu_steps || ARRAY['valid_time_from_source']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, lu_explicit_source_cols);

    -- 3. Establishment for legal unit with time_context for current year
    INSERT INTO public.import_definition (slug, name, note, time_context_ident, strategy, mode, valid, data_source_id, custom)
    VALUES ('establishment_for_lu_current_year', 'Establishment for Legal Unit - Current Year', 'Import establishments linked to legal units with validity period set to current year', 'r_year_curr', 'insert_or_replace', 'establishment_formal', false, nlr_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, es_steps || ARRAY['valid_time_from_context']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, es_source_cols);

    -- 4. Establishment for legal unit with explicit valid_from/valid_to
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid, data_source_id, custom)
    VALUES ('establishment_for_lu_explicit_dates', 'Establishment for Legal Unit - Explicit Dates', 'Import establishments linked to legal units with explicit valid_from and valid_to columns', 'insert_or_replace', 'establishment_formal', false, nlr_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, es_steps || ARRAY['valid_time_from_source']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, es_explicit_source_cols);

    -- 5. Establishment without legal unit with time_context for current year
    INSERT INTO public.import_definition (slug, name, note, time_context_ident, strategy, mode, valid, data_source_id, custom)
    VALUES ('establishment_without_lu_current_year', 'Establishment without Legal Unit - Current Year', 'Import standalone establishments with validity period set to current year', 'r_year_curr', 'insert_or_replace', 'establishment_informal', false, census_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, es_no_lu_steps || ARRAY['valid_time_from_context']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, es_no_lu_source_cols);

    -- 6. Establishment without legal unit with explicit valid_from/valid_to
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid, data_source_id, custom)
    VALUES ('establishment_without_lu_explicit_dates', 'Establishment without Legal Unit - Explicit Dates', 'Import standalone establishments with explicit valid_from and valid_to columns', 'insert_or_replace', 'establishment_informal', false, census_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, es_no_lu_steps || ARRAY['valid_time_from_source']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, es_no_lu_explicit_source_cols);

    -- 7. Unit Stats Update with time_context for current year
    INSERT INTO public.import_definition (slug, name, note, time_context_ident, strategy, mode, valid, data_source_id, custom)
    VALUES ('generic_unit_stats_update_current_year', 'Unit Stats Update - Current Year', 'Updates statistical variables for existing units, validity set to current year', 'r_year_curr', 'replace_only', 'generic_unit', false, survey_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, ARRAY['external_idents', 'valid_time_from_context', 'statistical_variables', 'edit_info', 'metadata']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, active_ext_ident_codes); -- Pass active external ident codes

    -- 8. Unit Stats Update with explicit valid_from/valid_to
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid, data_source_id, custom)
    VALUES ('generic_unit_stats_update_explicit_dates', 'Unit Stats Update - Explicit Dates', 'Updates statistical variables for existing units using explicit valid_from/valid_to', 'replace_only', 'generic_unit', false, survey_data_source_id, FALSE)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, ARRAY['external_idents', 'valid_time_from_source', 'statistical_variables', 'edit_info', 'metadata']);
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
