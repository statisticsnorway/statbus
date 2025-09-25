```sql
CREATE OR REPLACE FUNCTION admin.validate_import_definition(p_definition_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_definition public.import_definition;
    v_error_messages TEXT[] := ARRAY[]::TEXT[];
    v_is_valid BOOLEAN := true;
    v_step_codes TEXT[];
    v_has_time_from_context_step BOOLEAN;
    v_has_time_from_source_step BOOLEAN;
    v_has_valid_from_mapping BOOLEAN := false;
    v_has_valid_to_mapping BOOLEAN := false;
    v_source_col_rec RECORD;
    v_mapping_rec RECORD;
    v_temp_text TEXT;
BEGIN
    SELECT * INTO v_definition FROM public.import_definition WHERE id = p_definition_id;
    IF NOT FOUND THEN
        RAISE DEBUG 'validate_import_definition: Definition ID % not found. Skipping validation.', p_definition_id;
        RETURN;
    END IF;

    -- 1. Time Validity Method Check
    -- All definitions must include the 'valid_time' step to ensure uniform processing.
    IF NOT EXISTS (SELECT 1 FROM public.import_definition_step ids JOIN public.import_step s ON s.id = ids.step_id WHERE ids.definition_id = p_definition_id AND s.code = 'valid_time') THEN
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, 'All import definitions must include the "valid_time" step.');
    END IF;

    -- The following checks ensure the mappings for 'valid_from' and 'valid_to' are consistent with the chosen time validity mode.
    IF v_definition.valid_time_from = 'source_columns' THEN
        -- Check that 'valid_from_raw' and 'valid_to_raw' are mapped from source columns.
        SELECT EXISTS (
            SELECT 1 FROM public.import_mapping im
            JOIN public.import_data_column idc ON im.target_data_column_id = idc.id JOIN public.import_step s ON idc.step_id = s.id
            WHERE im.definition_id = p_definition_id AND s.code = 'valid_time' AND idc.column_name = 'valid_from_raw' AND im.source_column_id IS NOT NULL AND im.is_ignored = FALSE
        ) INTO v_has_valid_from_mapping;
        SELECT EXISTS (
            SELECT 1 FROM public.import_mapping im
            JOIN public.import_data_column idc ON im.target_data_column_id = idc.id JOIN public.import_step s ON idc.step_id = s.id
            WHERE im.definition_id = p_definition_id AND s.code = 'valid_time' AND idc.column_name = 'valid_to_raw' AND im.source_column_id IS NOT NULL AND im.is_ignored = FALSE
        ) INTO v_has_valid_to_mapping;

        IF NOT (v_has_valid_from_mapping AND v_has_valid_to_mapping) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'When valid_time_from="source_columns", mappings for both "valid_from_raw" and "valid_to_raw" from source columns are required.');
        END IF;

    ELSIF v_definition.valid_time_from = 'job_provided' THEN
        -- If validity is derived from job-level parameters, the definition must map 'valid_from_raw'
        -- and 'valid_to_raw' to the 'default' source expression. This allows the `import_job_prepare`
        -- function to populate these columns from the job's `default_valid_from`/`to` fields.
        SELECT EXISTS (
            SELECT 1 FROM public.import_mapping im
            JOIN public.import_data_column idc ON im.target_data_column_id = idc.id JOIN public.import_step s ON idc.step_id = s.id
            WHERE im.definition_id = p_definition_id AND s.code = 'valid_time' AND idc.column_name = 'valid_from_raw' AND im.source_expression = 'default' AND im.is_ignored = FALSE
        ) INTO v_has_valid_from_mapping;
        SELECT EXISTS (
            SELECT 1 FROM public.import_mapping im
            JOIN public.import_data_column idc ON im.target_data_column_id = idc.id JOIN public.import_step s ON idc.step_id = s.id
            WHERE im.definition_id = p_definition_id AND s.code = 'valid_time' AND idc.column_name = 'valid_to_raw' AND im.source_expression = 'default' AND im.is_ignored = FALSE
        ) INTO v_has_valid_to_mapping;

        IF NOT (v_has_valid_from_mapping AND v_has_valid_to_mapping) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'When valid_time_from="job_provided", mappings for both "valid_from_raw" and "valid_to_raw" using source_expression="default" are required.');
        END IF;

    ELSE
      v_is_valid := false;
      v_error_messages := array_append(v_error_messages, 'valid_time_from is NULL or has an unhandled value.');
    END IF;

    -- 2. Mode-specific step checks
    SELECT array_agg(s.code) INTO v_step_codes
    FROM public.import_definition_step ids
    JOIN public.import_step s ON ids.step_id = s.id
    WHERE ids.definition_id = p_definition_id;
    v_step_codes := COALESCE(v_step_codes, ARRAY[]::TEXT[]);

    IF v_definition.mode = 'legal_unit' THEN
        IF NOT ('legal_unit' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'Mode "legal_unit" requires the "legal_unit" step.');
        END IF;
        IF NOT ('enterprise_link_for_legal_unit' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'Mode "legal_unit" requires the "enterprise_link_for_legal_unit" step.');
        END IF;
    ELSIF v_definition.mode = 'establishment_formal' THEN
        IF NOT ('establishment' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'Mode "establishment_formal" requires the "establishment" step.');
        END IF;
        IF NOT ('link_establishment_to_legal_unit' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'Mode "establishment_formal" requires the "link_establishment_to_legal_unit" step.');
        END IF;
    ELSIF v_definition.mode = 'establishment_informal' THEN
        IF NOT ('establishment' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'Mode "establishment_informal" requires the "establishment" step.');
        END IF;
        IF NOT ('enterprise_link_for_establishment' = ANY(v_step_codes)) THEN
            v_is_valid := false;
            v_error_messages := array_append(v_error_messages, 'Mode "establishment_informal" requires the "enterprise_link_for_establishment" step.');
        END IF;
    ELSIF v_definition.mode = 'generic_unit' THEN
        -- Generic unit mode might have fewer structural step requirements.
        -- It still needs external_idents to find the unit, and likely statistical_variables if that's its purpose.
        -- For now, no specific structural checks beyond the global mandatory ones.
        RAISE DEBUG '[Validate Def ID %] Mode is generic_unit, skipping LU/ES specific step checks.', p_definition_id;
    ELSE
        -- This case should ideally not be reached if the mode enum is exhaustive and NOT NULL
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, format('Unknown or unhandled import mode: %L.', v_definition.mode));
    END IF;

    -- Enforce unique step priorities within a definition (prevents equal-priority deadlocks in analysis scheduling)
    IF EXISTS (
        SELECT 1
        FROM (
            SELECT s.priority
            FROM public.import_definition_step ids
            JOIN public.import_step s ON s.id = ids.step_id
            WHERE ids.definition_id = p_definition_id
            GROUP BY s.priority
            HAVING COUNT(*) > 1
        ) dup
    ) THEN
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, 'import_step priorities must be unique per definition (duplicates found).');
    END IF;

    -- 3. Check for mandatory steps
    IF NOT ('external_idents' = ANY(v_step_codes)) THEN
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, 'The "external_idents" step is mandatory.');
    END IF;
    IF NOT ('edit_info' = ANY(v_step_codes)) THEN
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, 'The "edit_info" step is mandatory.');
    END IF;
    IF NOT ('metadata' = ANY(v_step_codes)) THEN
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, 'The "metadata" step is mandatory.');
    END IF;

    -- 4. Source Column and Mapping Consistency

    -- Specific check for 'external_idents' step:
    -- If 'external_idents' step is included, at least one of its 'source_input' data columns must be mapped.
    IF 'external_idents' = ANY(v_step_codes) THEN
        DECLARE
            v_has_mapped_external_ident BOOLEAN;
        BEGIN
            SELECT EXISTS (
                SELECT 1 FROM public.import_mapping im
                JOIN public.import_data_column idc ON im.target_data_column_id = idc.id
                JOIN public.import_step s ON idc.step_id = s.id
                WHERE im.definition_id = p_definition_id
                  AND s.code = 'external_idents'
                  AND idc.purpose = 'source_input'
                  AND im.is_ignored = FALSE
            ) INTO v_has_mapped_external_ident;

            IF NOT v_has_mapped_external_ident THEN
                v_is_valid := false;
                v_error_messages := array_append(v_error_messages, 'At least one external identifier column (e.g., tax_ident, stat_ident) must be mapped for the "external_idents" step.');
            END IF;
        END;
    END IF;

    -- Specific check for 'status' step removed, as status_code mapping is now optional.
    -- The analyse_status procedure will handle defaults, and analyse_legal_unit/_establishment
    -- will error if status_id is ultimately not resolved.

    -- Conditional check for 'data_source_code_raw' mapping:
    -- If import_definition.data_source_id is NULL, a mapping for 'data_source_code_raw' is required.
    IF v_definition.data_source_id IS NULL THEN
        DECLARE
            v_data_source_code_mapped BOOLEAN;
            v_data_source_code_data_column_exists BOOLEAN;
        BEGIN
            -- Check if a data_source_code_raw data column even exists for any of the definition's steps
            SELECT EXISTS (
                SELECT 1
                FROM public.import_definition_step ids
                JOIN public.import_data_column idc ON ids.step_id = idc.step_id
                WHERE ids.definition_id = p_definition_id
                  AND idc.column_name = 'data_source_code_raw'
                  AND idc.purpose = 'source_input'
            ) INTO v_data_source_code_data_column_exists;

            IF v_data_source_code_data_column_exists THEN
                -- If the data column exists, check if it's mapped
                SELECT EXISTS (
                    SELECT 1 FROM public.import_mapping im
                    JOIN public.import_data_column idc ON im.target_data_column_id = idc.id
                    WHERE im.definition_id = p_definition_id
                      AND idc.column_name = 'data_source_code_raw'
                      AND idc.purpose = 'source_input'
                      AND im.is_ignored = FALSE
                ) INTO v_data_source_code_mapped;

                IF NOT v_data_source_code_mapped THEN
                    v_is_valid := false;
                    v_error_messages := array_append(v_error_messages, 'If import_definition.data_source_id is NULL and a "data_source_code_raw" source_input data column is available for the definition''s steps, it must be mapped.');
                END IF;
            ELSE
                -- If data_source_id is NULL and no data_source_code_raw data column is available from steps, it's an error.
                v_is_valid := false;
                v_error_messages := array_append(v_error_messages, 'If import_definition.data_source_id is NULL, a "data_source_code_raw" source_input data column must be available via one of the definition''s steps and mapped. None found.');
            END IF;
        END;
    END IF;

    -- The old generic loop checking all source_input columns for mapping is removed.
    -- Only specific, critical mappings are checked above.

    FOR v_source_col_rec IN
        SELECT isc.column_name
        FROM public.import_source_column isc
        WHERE isc.definition_id = p_definition_id
          AND NOT EXISTS (
            SELECT 1 FROM public.import_mapping im
            WHERE im.definition_id = p_definition_id AND im.source_column_id = isc.id
          )
    LOOP
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, format('Unused import_source_column: "%s". It is defined but not used in any mapping.', v_source_col_rec.column_name));
    END LOOP;

    FOR v_mapping_rec IN
        SELECT im.id as mapping_id, idc.column_name as target_col_name, s.code as target_step_code
        FROM public.import_mapping im
        JOIN public.import_data_column idc ON im.target_data_column_id = idc.id -- This JOIN implies target_data_column_id IS NOT NULL
        JOIN public.import_step s ON idc.step_id = s.id
        WHERE im.definition_id = p_definition_id
          AND im.is_ignored = FALSE -- Only validate non-ignored mappings for this check
          AND NOT EXISTS (
            SELECT 1 FROM public.import_definition_step ids
            WHERE ids.definition_id = p_definition_id AND ids.step_id = s.id
          )
    LOOP
        v_is_valid := false;
        v_error_messages := array_append(v_error_messages, format('Mapping ID %s targets data column "%s" in step "%s", but this step is not part of the definition.', v_mapping_rec.mapping_id, v_mapping_rec.target_col_name, v_mapping_rec.target_step_code));
    END LOOP;

    -- Final Update
    IF v_is_valid THEN
        UPDATE public.import_definition
        SET valid = true, validation_error = NULL
        WHERE id = p_definition_id;
    ELSE
        -- Concatenate unique error messages
        SELECT string_agg(DISTINCT error_msg, '; ') INTO v_temp_text FROM unnest(v_error_messages) AS error_msg;
        UPDATE public.import_definition
        SET valid = false, validation_error = v_temp_text
        WHERE id = p_definition_id;
    END IF;

END;
$function$
```
