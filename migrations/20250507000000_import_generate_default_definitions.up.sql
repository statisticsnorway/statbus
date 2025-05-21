-- Migration
BEGIN;

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
                INSERT INTO public.import_mapping (definition_id, source_column_id, target_data_column_id)
                VALUES (p_definition_id, v_source_col_id, v_data_col_id)
                ON CONFLICT (definition_id, source_column_id, target_data_column_id) DO NOTHING;
            ELSE
                 -- Enhanced Debugging for Missing Data Column
                 SELECT string_agg(
                            format('StepCode: %s, StepID: %s, DC_Name: %s, DC_Purpose: %s, DC_ID: %s',
                                   s.code, ds.step_id, dc_debug.column_name, dc_debug.purpose, dc_debug.id),
                            E'\n')
                 INTO v_debug_info
                 FROM public.import_definition_step ds
                 JOIN public.import_step s ON s.id = ds.step_id
                 LEFT JOIN public.import_data_column dc_debug ON ds.step_id = dc_debug.step_id AND dc_debug.purpose = 'source_input'
                 WHERE ds.definition_id = p_definition_id;

                 RAISE EXCEPTION '[Definition %] No matching source_input data column found for source column "%". Available source_input data columns for this definition (StepCode, StepID, DC_Name, DC_Purpose, DC_ID): %',
                                 p_definition_id, v_col_name, COALESCE(v_debug_info, 'NONE');
            END IF;
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
END;
$$;


DO $$
DECLARE
    def_id INT;
    lu_steps TEXT[] := ARRAY['external_idents', 'enterprise_link_for_legal_unit', 'status', 'legal_unit', 'physical_location', 'postal_location', 'primary_activity', 'secondary_activity', 'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'];
    es_steps TEXT[] := ARRAY['external_idents', 'link_establishment_to_legal_unit', 'status', 'establishment', 'physical_location', 'postal_location', 'primary_activity', 'secondary_activity', 'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'];
    es_no_lu_steps TEXT[] := ARRAY['external_idents', 'enterprise_link_for_establishment', 'status', 'establishment', 'physical_location', 'postal_location', 'primary_activity', 'secondary_activity', 'contact', 'statistical_variables', 'tags', 'edit_info', 'metadata'];

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
        'legal_unit_tax_ident' -- Added for linking EST to LU
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
BEGIN
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
    INSERT INTO public.import_definition (slug, name, note, time_context_ident, strategy, mode, valid)
    VALUES ('legal_unit_current_year', 'Legal Unit - Current Year', 'Import legal units with validity period set to current year', 'r_year_curr', 'insert_or_replace', 'legal_unit', false)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, lu_steps || ARRAY['valid_time_from_context']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, lu_source_cols);

    -- 2. Legal unit with explicit valid_from/valid_to
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid)
    VALUES ('legal_unit_explicit_dates', 'Legal Unit - Explicit Dates', 'Import legal units with explicit valid_from and valid_to columns', 'insert_or_replace', 'legal_unit', false)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, lu_steps || ARRAY['valid_time_from_source']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, lu_explicit_source_cols);

    -- 3. Establishment for legal unit with time_context for current year
    INSERT INTO public.import_definition (slug, name, note, time_context_ident, strategy, mode, valid)
    VALUES ('establishment_for_lu_current_year', 'Establishment for Legal Unit - Current Year', 'Import establishments linked to legal units with validity period set to current year', 'r_year_curr', 'insert_or_replace', 'establishment_formal', false)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, es_steps || ARRAY['valid_time_from_context']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, es_source_cols);

    -- 4. Establishment for legal unit with explicit valid_from/valid_to
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid)
    VALUES ('establishment_for_lu_explicit_dates', 'Establishment for Legal Unit - Explicit Dates', 'Import establishments linked to legal units with explicit valid_from and valid_to columns', 'insert_or_replace', 'establishment_formal', false)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, es_steps || ARRAY['valid_time_from_source']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, es_explicit_source_cols);

    -- 5. Establishment without legal unit with time_context for current year
    INSERT INTO public.import_definition (slug, name, note, time_context_ident, strategy, mode, valid)
    VALUES ('establishment_without_lu_current_year', 'Establishment without Legal Unit - Current Year', 'Import standalone establishments with validity period set to current year', 'r_year_curr', 'insert_or_replace', 'establishment_informal', false)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, es_no_lu_steps || ARRAY['valid_time_from_context']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, es_no_lu_source_cols);

    -- 6. Establishment without legal unit with explicit valid_from/valid_to
    INSERT INTO public.import_definition (slug, name, note, strategy, mode, valid)
    VALUES ('establishment_without_lu_explicit_dates', 'Establishment without Legal Unit - Explicit Dates', 'Import standalone establishments with explicit valid_from and valid_to columns', 'insert_or_replace', 'establishment_informal', false)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, es_no_lu_steps || ARRAY['valid_time_from_source']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, es_no_lu_explicit_source_cols);

    -- 7. Unit Stats Update with time_context for current year
    INSERT INTO public.import_definition (slug, name, note, time_context_ident, strategy, valid) -- Mode is NULL/not applicable for stats update
    VALUES ('unit_stats_update_current_year', 'Unit Stats Update - Current Year', 'Updates statistical variables for existing units, validity set to current year', 'r_year_curr', 'replace_only', false)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, ARRAY['external_idents', 'valid_time_from_context', 'statistical_variables', 'edit_info', 'metadata']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, ARRAY[]::TEXT[]);

    -- 8. Unit Stats Update with explicit valid_from/valid_to
    INSERT INTO public.import_definition (slug, name, note, strategy, valid) -- Mode is NULL/not applicable for stats update
    VALUES ('unit_stats_update_explicit_dates', 'Unit Stats Update - Explicit Dates', 'Updates statistical variables for existing units using explicit valid_from/valid_to', 'replace_only', false)
    RETURNING id INTO def_id;
    PERFORM import.link_steps_to_definition(def_id, ARRAY['external_idents', 'valid_time_from_source', 'statistical_variables', 'edit_info', 'metadata']);
    PERFORM import.create_source_and_mappings_for_definition(def_id, ARRAY['valid_from', 'valid_to']);

END $$;

UPDATE public.import_definition
SET valid = true, validation_error = NULL
WHERE valid = false; 


END;
