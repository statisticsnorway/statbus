-- Migration: import_job_procedures_for_location
-- Implements the analyse and operation procedures for the PhysicalLocation
-- and PostalLocation import targets using generic location handlers.

BEGIN;

-- Helper function to safely cast text to a specific numeric type, handling common errors.
CREATE OR REPLACE FUNCTION import.try_cast_to_numeric_specific(
    IN p_text_value TEXT,
    IN p_target_type TEXT, -- e.g., 'NUMERIC(9,6)' or 'NUMERIC(6,1)'
    OUT p_value NUMERIC,
    OUT p_error_message TEXT
) LANGUAGE plpgsql IMMUTABLE AS $try_cast_to_numeric_specific$
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_value IS NULL OR p_text_value = '' THEN
        RETURN;
    END IF;

    BEGIN
        EXECUTE format($$SELECT %1$L::%2$s$$, p_text_value /* %1$L */, p_target_type /* %2$s */) INTO p_value;
    EXCEPTION
        WHEN numeric_value_out_of_range THEN -- SQLSTATE 22003
            p_error_message := 'Value ''' || p_text_value || ''' is out of range for type ' || p_target_type || '. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN invalid_text_representation THEN -- SQLSTATE 22P02
            p_error_message := 'Value ''' || p_text_value || ''' is not a valid numeric representation for type ' || p_target_type || '. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN others THEN -- Catch any other potential errors during cast
            p_error_message := 'Unexpected error casting value ''' || p_text_value || ''' to type ' || p_target_type || '. SQLSTATE: ' || SQLSTATE || ', SQLERRM: ' || SQLERRM;
            RAISE DEBUG '%', p_error_message;
    END;
END;
$try_cast_to_numeric_specific$;

-- Procedure to analyse location data (handles both physical and postal) (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.analyse_location(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_location$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
    v_error_json_expr_sql TEXT; -- For dt.error (fatal) - though this step makes them non-fatal
    v_invalid_codes_json_expr_sql TEXT; -- For dt.invalid_codes (non-fatal)
    v_error_keys_to_clear_arr TEXT[];
    v_invalid_code_keys_to_clear_arr TEXT[];
    v_skipped_update_count INT;
    error_message TEXT;
    v_error_condition_sql TEXT; -- For non-fatal invalid codes
    v_fatal_error_condition_sql TEXT; -- For fatal errors like missing country
    v_fatal_error_json_expr_sql TEXT; -- For fatal error messages
    v_address_present_condition_sql TEXT; -- To check if any address part is present

    -- For coordinate validation
    v_coord_cast_error_json_expr_sql TEXT;
    v_coord_range_error_json_expr_sql TEXT;
    v_postal_coord_present_error_json_expr_sql TEXT := $$'{}'::jsonb$$; -- Default to SQL literal for empty JSONB
    v_coord_invalid_value_json_expr_sql TEXT;
    v_any_coord_error_condition_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_location (Batch) for step_code %: Starting analysis for % rows', p_job_id, p_step_code, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_location: Step with code % not found in snapshot.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] analyse_location: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;

    IF p_step_code = 'physical_location' THEN
        v_error_keys_to_clear_arr := ARRAY[
            'physical_region_code', 
            'physical_country_iso_2', 
            'physical_latitude', -- Error key for latitude issues
            'physical_longitude', -- Error key for longitude issues
            'physical_altitude' -- Error key for altitude issues
            -- 'physical_location_error' is now covered by more specific keys like physical_country_iso_2 for missing country
        ];
        v_invalid_code_keys_to_clear_arr := ARRAY['physical_region_code', 'physical_country_iso_2', 'physical_latitude', 'physical_longitude', 'physical_altitude'];
        v_address_present_condition_sql := $$
            (NULLIF(dt.physical_address_part1, '') IS NOT NULL OR NULLIF(dt.physical_address_part2, '') IS NOT NULL OR NULLIF(dt.physical_address_part3, '') IS NOT NULL OR
             NULLIF(dt.physical_postcode, '') IS NOT NULL OR NULLIF(dt.physical_postplace, '') IS NOT NULL OR NULLIF(dt.physical_region_code, '') IS NOT NULL)
        $$;
        v_fatal_error_condition_sql := format($$
            (%s AND (NULLIF(dt.physical_country_iso_2, '') IS NULL OR l.resolved_physical_country_id IS NULL))
        $$, v_address_present_condition_sql);
        v_fatal_error_json_expr_sql := $$
            jsonb_build_object('physical_country_iso_2', 'Country is required and must be valid when other physical address details are provided.')
        $$;
        v_error_condition_sql := $$
            (dt.physical_region_code IS NOT NULL AND l.resolved_physical_region_id IS NULL) OR
            -- Country check is now fatal if address parts are present, otherwise non-fatal for invalid_codes
            (dt.physical_country_iso_2 IS NOT NULL AND l.resolved_physical_country_id IS NULL AND NOT (%s)) OR
            (dt.physical_latitude IS NOT NULL AND l.physical_latitude_error_msg IS NOT NULL) OR
            (dt.physical_longitude IS NOT NULL AND l.physical_longitude_error_msg IS NOT NULL) OR
            (dt.physical_altitude IS NOT NULL AND l.physical_altitude_error_msg IS NOT NULL)
        $$;
        v_error_condition_sql := format(v_error_condition_sql, v_address_present_condition_sql); -- Inject address_present check

        v_invalid_codes_json_expr_sql := $$
            jsonb_build_object('physical_region_code', CASE WHEN dt.physical_region_code IS NOT NULL AND l.resolved_physical_region_id IS NULL THEN dt.physical_region_code ELSE NULL END) ||
            jsonb_build_object('physical_country_iso_2', CASE WHEN dt.physical_country_iso_2 IS NOT NULL AND l.resolved_physical_country_id IS NULL THEN dt.physical_country_iso_2 ELSE NULL END) ||
            jsonb_build_object('physical_latitude', CASE WHEN dt.physical_latitude IS NOT NULL AND l.physical_latitude_error_msg IS NOT NULL THEN dt.physical_latitude ELSE NULL END) ||
            jsonb_build_object('physical_longitude', CASE WHEN dt.physical_longitude IS NOT NULL AND l.physical_longitude_error_msg IS NOT NULL THEN dt.physical_longitude ELSE NULL END) ||
            jsonb_build_object('physical_altitude', CASE WHEN dt.physical_altitude IS NOT NULL AND l.physical_altitude_error_msg IS NOT NULL THEN dt.physical_altitude ELSE NULL END)
        $$;

        -- Coordinate error expressions for physical location
        v_coord_cast_error_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('physical_latitude', l.physical_latitude_error_msg) ||
                jsonb_build_object('physical_longitude', l.physical_longitude_error_msg) ||
                jsonb_build_object('physical_altitude', l.physical_altitude_error_msg)
            )
        $$;
        v_coord_range_error_json_expr_sql := $jsonb_expr$
            jsonb_strip_nulls(
                jsonb_build_object('physical_latitude', CASE WHEN l.resolved_typed_physical_latitude IS NOT NULL AND (l.resolved_typed_physical_latitude < -90 OR l.resolved_typed_physical_latitude > 90) THEN format($$Value %1$s out of range. Expected -90 to 90.$$, l.resolved_typed_physical_latitude::TEXT /* %1$s */) ELSE NULL END) ||
                jsonb_build_object('physical_longitude', CASE WHEN l.resolved_typed_physical_longitude IS NOT NULL AND (l.resolved_typed_physical_longitude < -180 OR l.resolved_typed_physical_longitude > 180) THEN format($$Value %1$s out of range. Expected -180 to 180.$$, l.resolved_typed_physical_longitude::TEXT /* %1$s */) ELSE NULL END) ||
                jsonb_build_object('physical_altitude', CASE WHEN l.resolved_typed_physical_altitude IS NOT NULL AND l.resolved_typed_physical_altitude < 0 THEN format($$Value %1$s cannot be negative. Expected >= 0.$$, l.resolved_typed_physical_altitude::TEXT /* %1$s */) ELSE NULL END)
            )
        $jsonb_expr$;
        v_coord_invalid_value_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('physical_latitude', CASE WHEN (dt.physical_latitude IS NOT NULL AND l.physical_latitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_latitude IS NOT NULL AND (l.resolved_typed_physical_latitude < -90 OR l.resolved_typed_physical_latitude > 90)) THEN dt.physical_latitude ELSE NULL END) ||
                jsonb_build_object('physical_longitude', CASE WHEN (dt.physical_longitude IS NOT NULL AND l.physical_longitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_longitude IS NOT NULL AND (l.resolved_typed_physical_longitude < -180 OR l.resolved_typed_physical_longitude > 180)) THEN dt.physical_longitude ELSE NULL END) ||
                jsonb_build_object('physical_altitude', CASE WHEN (dt.physical_altitude IS NOT NULL AND l.physical_altitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_altitude IS NOT NULL AND l.resolved_typed_physical_altitude < 0) THEN dt.physical_altitude ELSE NULL END)
            )
        $$;
        v_any_coord_error_condition_sql := $$
            (l.physical_latitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_latitude IS NOT NULL AND (l.resolved_typed_physical_latitude < -90 OR l.resolved_typed_physical_latitude > 90)) OR
            (l.physical_longitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_longitude IS NOT NULL AND (l.resolved_typed_physical_longitude < -180 OR l.resolved_typed_physical_longitude > 180)) OR
            (l.physical_altitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_altitude IS NOT NULL AND l.resolved_typed_physical_altitude < 0)
        $$;

    ELSIF p_step_code = 'postal_location' THEN
        v_error_keys_to_clear_arr := ARRAY[
            'postal_region_code', 
            'postal_country_iso_2', 
            'postal_latitude', -- Error key for latitude issues
            'postal_longitude', -- Error key for longitude issues
            'postal_altitude', -- Error key for altitude issues
            -- 'postal_location_error' is now covered by more specific keys like postal_country_iso_2 for missing country
            'postal_location_has_coordinates_error' -- Specific error for postal having coords, keep this one
        ];
        v_invalid_code_keys_to_clear_arr := ARRAY['postal_region_code', 'postal_country_iso_2', 'postal_latitude', 'postal_longitude', 'postal_altitude'];
        v_address_present_condition_sql := $$
            (NULLIF(dt.postal_address_part1, '') IS NOT NULL OR NULLIF(dt.postal_address_part2, '') IS NOT NULL OR NULLIF(dt.postal_address_part3, '') IS NOT NULL OR
             NULLIF(dt.postal_postcode, '') IS NOT NULL OR NULLIF(dt.postal_postplace, '') IS NOT NULL OR NULLIF(dt.postal_region_code, '') IS NOT NULL)
        $$;
        v_fatal_error_condition_sql := format($$
            (%s AND (NULLIF(dt.postal_country_iso_2, '') IS NULL OR l.resolved_postal_country_id IS NULL))
        $$, v_address_present_condition_sql);
        v_fatal_error_json_expr_sql := $$
            jsonb_build_object('postal_country_iso_2', 'Country is required and must be valid when other postal address details are provided.')
        $$;
        v_error_condition_sql := $$
            (dt.postal_region_code IS NOT NULL AND l.resolved_postal_region_id IS NULL) OR
            (dt.postal_country_iso_2 IS NOT NULL AND l.resolved_postal_country_id IS NULL AND NOT (%s)) OR
            (dt.postal_latitude IS NOT NULL AND l.postal_latitude_error_msg IS NOT NULL) OR
            (dt.postal_longitude IS NOT NULL AND l.postal_longitude_error_msg IS NOT NULL) OR
            (dt.postal_altitude IS NOT NULL AND l.postal_altitude_error_msg IS NOT NULL)
        $$;
        v_error_condition_sql := format(v_error_condition_sql, v_address_present_condition_sql); -- Inject address_present check

        v_invalid_codes_json_expr_sql := $$
            jsonb_build_object('postal_region_code', CASE WHEN dt.postal_region_code IS NOT NULL AND l.resolved_postal_region_id IS NULL THEN dt.postal_region_code ELSE NULL END) ||
            jsonb_build_object('postal_country_iso_2', CASE WHEN dt.postal_country_iso_2 IS NOT NULL AND l.resolved_postal_country_id IS NULL THEN dt.postal_country_iso_2 ELSE NULL END) ||
            jsonb_build_object('postal_latitude', CASE WHEN dt.postal_latitude IS NOT NULL AND l.postal_latitude_error_msg IS NOT NULL THEN dt.postal_latitude ELSE NULL END) ||
            jsonb_build_object('postal_longitude', CASE WHEN dt.postal_longitude IS NOT NULL AND l.postal_longitude_error_msg IS NOT NULL THEN dt.postal_longitude ELSE NULL END) ||
            jsonb_build_object('postal_altitude', CASE WHEN dt.postal_altitude IS NOT NULL AND l.postal_altitude_error_msg IS NOT NULL THEN dt.postal_altitude ELSE NULL END)
        $$;

        -- Coordinate error expressions for postal location
        v_coord_cast_error_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('postal_latitude', l.postal_latitude_error_msg) ||
                jsonb_build_object('postal_longitude', l.postal_longitude_error_msg) ||
                jsonb_build_object('postal_altitude', l.postal_altitude_error_msg)
            )
        $$;
        -- Range errors are not applicable here as the primary error is their presence.
        v_coord_range_error_json_expr_sql := $$'{}'::jsonb$$; -- Use SQL literal for empty JSONB.
        v_postal_coord_present_error_json_expr_sql := $$
            jsonb_build_object('postal_location_has_coordinates_error', -- This is a general error, not tied to a specific input coord column.
                CASE WHEN l.resolved_typed_postal_latitude IS NOT NULL OR l.resolved_typed_postal_longitude IS NOT NULL OR l.resolved_typed_postal_altitude IS NOT NULL
                THEN 'Postal locations cannot have coordinates (latitude, longitude, altitude).'
                ELSE NULL END
            )
        $$;
        v_coord_invalid_value_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('postal_latitude', CASE WHEN dt.postal_latitude IS NOT NULL AND (l.postal_latitude_error_msg IS NOT NULL OR l.resolved_typed_postal_latitude IS NOT NULL) THEN dt.postal_latitude ELSE NULL END) || -- Log if provided, regardless of cast success for this error type
                jsonb_build_object('postal_longitude', CASE WHEN dt.postal_longitude IS NOT NULL AND (l.postal_longitude_error_msg IS NOT NULL OR l.resolved_typed_postal_longitude IS NOT NULL) THEN dt.postal_longitude ELSE NULL END) ||
                jsonb_build_object('postal_altitude', CASE WHEN dt.postal_altitude IS NOT NULL AND (l.postal_altitude_error_msg IS NOT NULL OR l.resolved_typed_postal_altitude IS NOT NULL) THEN dt.postal_altitude ELSE NULL END)
            )
        $$;
        v_any_coord_error_condition_sql := $$
            (l.postal_latitude_error_msg IS NOT NULL) OR
            (l.postal_longitude_error_msg IS NOT NULL) OR
            (l.postal_altitude_error_msg IS NOT NULL) OR
            (l.resolved_typed_postal_latitude IS NOT NULL OR l.resolved_typed_postal_longitude IS NOT NULL OR l.resolved_typed_postal_altitude IS NOT NULL) -- This covers the "postal has coords" error
        $$;

    ELSE
        RAISE EXCEPTION '[Job %] analyse_location: Invalid p_step_code provided: %. Expected ''physical_location'' or ''postal_location''.', p_job_id, p_step_code;
    END IF;

    v_sql := format($$
        WITH lookups AS (
            SELECT
                dt_sub.row_id AS data_row_id,
                pr.id as resolved_physical_region_id,
                pc.id as resolved_physical_country_id,
                psr.id as resolved_postal_region_id,
                psc.id as resolved_postal_country_id,
                lat_phys.p_value as resolved_typed_physical_latitude,
                lat_phys.p_error_message as physical_latitude_error_msg,
                lon_phys.p_value as resolved_typed_physical_longitude,
                lon_phys.p_error_message as physical_longitude_error_msg,
                alt_phys.p_value as resolved_typed_physical_altitude,
                alt_phys.p_error_message as physical_altitude_error_msg,
                lat_post.p_value as resolved_typed_postal_latitude,
                lat_post.p_error_message as postal_latitude_error_msg,
                lon_post.p_value as resolved_typed_postal_longitude,
                lon_post.p_error_message as postal_longitude_error_msg,
                alt_post.p_value as resolved_typed_postal_altitude,
                alt_post.p_error_message as postal_altitude_error_msg
            FROM public.%1$I dt_sub
            LEFT JOIN public.region pr ON dt_sub.physical_region_code IS NOT NULL AND pr.code = dt_sub.physical_region_code
            LEFT JOIN public.country pc ON dt_sub.physical_country_iso_2 IS NOT NULL AND pc.iso_2 = dt_sub.physical_country_iso_2
            LEFT JOIN public.region psr ON dt_sub.postal_region_code IS NOT NULL AND psr.code = dt_sub.postal_region_code
            LEFT JOIN public.country psc ON dt_sub.postal_country_iso_2 IS NOT NULL AND psc.iso_2 = dt_sub.postal_country_iso_2
            LEFT JOIN LATERAL import.try_cast_to_numeric_specific(dt_sub.physical_latitude, 'NUMERIC(9,6)') AS lat_phys(p_value, p_error_message) ON TRUE
            LEFT JOIN LATERAL import.try_cast_to_numeric_specific(dt_sub.physical_longitude, 'NUMERIC(9,6)') AS lon_phys(p_value, p_error_message) ON TRUE
            LEFT JOIN LATERAL import.try_cast_to_numeric_specific(dt_sub.physical_altitude, 'NUMERIC(6,1)') AS alt_phys(p_value, p_error_message) ON TRUE
            LEFT JOIN LATERAL import.try_cast_to_numeric_specific(dt_sub.postal_latitude, 'NUMERIC(9,6)') AS lat_post(p_value, p_error_message) ON TRUE
            LEFT JOIN LATERAL import.try_cast_to_numeric_specific(dt_sub.postal_longitude, 'NUMERIC(9,6)') AS lon_post(p_value, p_error_message) ON TRUE
            LEFT JOIN LATERAL import.try_cast_to_numeric_specific(dt_sub.postal_altitude, 'NUMERIC(6,1)') AS alt_post(p_value, p_error_message) ON TRUE
            WHERE dt_sub.row_id = ANY($1) AND dt_sub.action = 'use'
        )
        UPDATE public.%1$I dt SET
            physical_region_id = l.resolved_physical_region_id,
            physical_country_id = l.resolved_physical_country_id,
            typed_physical_latitude = l.resolved_typed_physical_latitude,
            typed_physical_longitude = l.resolved_typed_physical_longitude,
            typed_physical_altitude = l.resolved_typed_physical_altitude,
            postal_region_id = l.resolved_postal_region_id,
            postal_country_id = l.resolved_postal_country_id,
            typed_postal_latitude = l.resolved_typed_postal_latitude,
            typed_postal_longitude = l.resolved_typed_postal_longitude,
            typed_postal_altitude = l.resolved_typed_postal_altitude,
            action = CASE
                        WHEN (%6$s) OR (%10$s) THEN 'skip'::public.import_row_action_type -- Fatal error: set action to skip
                        ELSE dt.action -- Preserve existing action otherwise
                     END,
            state = CASE
                        WHEN (%6$s) OR (%10$s) THEN 'error'::public.import_data_state -- Fatal country error OR any coordinate error
                        ELSE 'analysing'::public.import_data_state
                    END,
            errors = jsonb_strip_nulls(
                        dt.errors -- Start with existing errors
                        || CASE WHEN (%6$s) THEN (%7$s) ELSE '{}'::jsonb END -- Add Fatal country error message
                        || (%11$s) -- Add Coordinate cast error messages
                        || (%12$s) -- Add Coordinate range error messages
                        || (%13$s) -- Add Postal coordinate present error message
                    ),
            invalid_codes = jsonb_strip_nulls(
                        dt.invalid_codes -- Start with existing invalid codes
                        || CASE WHEN (%4$s) AND NOT ((%6$s) OR (%10$s)) THEN (%5$s) ELSE '{}'::jsonb END -- Add Non-fatal region/country codes (if no fatal/coord error)
                        || CASE WHEN (%10$s) THEN (%14$s) ELSE '{}'::jsonb END -- Add Original invalid coordinate values
                    ),
            last_completed_priority = %9$L::INTEGER -- Always v_step.priority
        FROM lookups l
        WHERE dt.row_id = l.data_row_id; -- Join is sufficient, lookups CTE is already filtered
    $$,
        v_data_table_name,                      /* %1$I (target table) */
        p_batch_row_ids,                        /* %2$L (kept for numbering alignment) */
        v_error_keys_to_clear_arr,              /* %3$L (for clearing error keys) */
        v_error_condition_sql,                  /* %4$s (non-fatal region/country error condition) */
        v_invalid_codes_json_expr_sql,          /* %5$s (for adding non-fatal region/country invalid codes) */
        v_fatal_error_condition_sql,            /* %6$s (fatal country error condition) */
        v_fatal_error_json_expr_sql,            /* %7$s (for adding fatal country error message) */
        v_invalid_code_keys_to_clear_arr,       /* %8$L (for clearing invalid_codes keys) */
        v_step.priority,                        /* %9$L (for last_completed_priority) */
        v_any_coord_error_condition_sql,        /* %10$s (any coordinate error condition) */
        v_coord_cast_error_json_expr_sql,       /* %11$s (coordinate cast error JSON) */
        v_coord_range_error_json_expr_sql,      /* %12$s (coordinate range error JSON) */
        v_postal_coord_present_error_json_expr_sql, /* %13$s (postal has coords error JSON) */
        v_coord_invalid_value_json_expr_sql,    /* %14$s (original invalid coordinate values JSON) */
        REPLACE(p_step_code, '_location', ''),  /* %15$L (location type: 'physical' or 'postal') */
        p_step_code                             /* %16$L (step code: 'physical_location' or 'postal_location') */
    );

    RAISE DEBUG '[Job %] analyse_location: Single-pass batch update for non-skipped rows for step %: %', p_job_id, p_step_code, v_sql;

    BEGIN
        EXECUTE v_sql USING p_batch_row_ids;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_location: Updated % non-skipped rows in single pass for step %.', p_job_id, v_update_count, p_step_code;

        -- Update priority for skipped rows
        EXECUTE format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.row_id = ANY($1) AND dt.action = 'skip';
        $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */) USING p_batch_row_ids;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_location: Updated last_completed_priority for % skipped rows for step %.', p_job_id, v_skipped_update_count, p_step_code;
        
        v_update_count := v_update_count + v_skipped_update_count; -- Total rows affected by this step's logic

        EXECUTE format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id = ANY($1) AND state = 'error' AND (errors ?| %2$L::text[])$$,
                       v_data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */)
        INTO v_error_count
        USING p_batch_row_ids;
        RAISE DEBUG '[Job %] analyse_location: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION 
        WHEN PROGRAM_LIMIT_EXCEEDED THEN -- e.g. statement too complex, or other similar limit errors
            error_message := SQLERRM;
            RAISE WARNING '[Job %] analyse_location: Program limit exceeded during single-pass batch update for step %: %. SQLSTATE: %', p_job_id, p_step_code, error_message, SQLSTATE;
            -- Fallback or simplified error marking might be needed here if the main query is too complex
            UPDATE public.import_job
            SET error = jsonb_build_object('analyse_location_error', format($$Program limit error for step %1$s: %2$s$$, p_step_code /* %1$s */, error_message /* %2$s */)),
                state = 'finished'
            WHERE id = p_job_id;
            RAISE; -- Re-throw
        WHEN OTHERS THEN
            error_message := SQLERRM; 
            RAISE WARNING '[Job %] analyse_location: Unexpected error during single-pass batch update for step %: %. SQLSTATE: %', p_job_id, p_step_code, error_message, SQLSTATE;
            -- Attempt to mark individual data rows as error (best effort)
            BEGIN
                v_sql := format($$
                    UPDATE public.%1$I dt SET
                        state = %2$L,
                        errors = dt.errors || jsonb_build_object('location_batch_error', 'Unexpected error during update for step %3$s: ' || %4$L),
                        last_completed_priority = dt.last_completed_priority -- Do not advance priority on unexpected error, use existing LCP
                    WHERE dt.row_id = ANY($1);
                $$, v_data_table_name /* %1$I */, 'error'::public.import_data_state /* %2$L */, p_step_code /* %3$s */, error_message /* %4$L */);
                EXECUTE v_sql USING p_batch_row_ids;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING '[Job %] analyse_location: Could not mark individual data rows as error after unexpected error: %', p_job_id, SQLERRM;
            END;
            -- Mark the job as failed
            UPDATE public.import_job
            SET error = jsonb_build_object('analyse_location_error', format($$Unexpected error for step %1$s: %2$s$$, p_step_code /* %1$s */, error_message /* %2$s */)),
                state = 'finished'
            WHERE id = p_job_id;
            RAISE DEBUG '[Job %] analyse_location: Marked job as failed due to unexpected error for step %: %', p_job_id, p_step_code, error_message;
            RAISE; -- Re-throw the exception
    END;

    -- Propagate errors to all rows of a new entity if one fails
    CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_row_ids, v_error_keys_to_clear_arr, p_step_code);

    RAISE DEBUG '[Job %] analyse_location (Batch): Finished analysis for batch for step %. Errors newly marked in this step: %', p_job_id, p_step_code, v_error_count;
END;
$analyse_location$;


-- Procedure to operate (insert/update/upsert) location data (handles both physical and postal) (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_location(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_location$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    error_message TEXT;
    v_job_mode public.import_mode;
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
    v_source_view_name TEXT;
    v_relevant_rows_count INT;
BEGIN
    RAISE DEBUG '[Job %] process_location (Batch) for step_code %: Starting operation for % rows', p_job_id, p_step_code, array_length(p_batch_row_ids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');
    IF v_definition IS NULL THEN RAISE EXCEPTION '[Job %] Failed to load import_definition from snapshot', p_job_id; END IF;

    -- Get step details
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] process_location: Step with code % not found in snapshot.', p_job_id, p_step_code; END IF;

    v_job_mode := v_definition.mode;

    -- Select the correct parent unit ID column based on job mode, or NULL if not applicable.
    IF v_job_mode = 'legal_unit' THEN
        v_select_lu_id_expr := 'dt.legal_unit_id';
        v_select_est_id_expr := 'NULL::INTEGER';
    ELSIF v_job_mode = 'establishment_formal' THEN
        v_select_lu_id_expr := 'NULL::INTEGER';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSIF v_job_mode = 'establishment_informal' THEN
        v_select_lu_id_expr := 'NULL::INTEGER';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSE
        RAISE EXCEPTION '[Job %] process_location: Unhandled job mode % for unit ID selection.', p_job_id, v_job_mode;
    END IF;

    -- Create an updatable view over the relevant data for this step
    v_source_view_name := 'temp_loc_source_view_' || p_step_code;
    IF p_step_code = 'physical_location' THEN
        v_sql := format($$
            CREATE OR REPLACE TEMP VIEW %1$I AS
            SELECT
                dt.row_id,
                dt.founding_row_id,
                dt.physical_location_id AS id,
                %2$s AS legal_unit_id,
                %3$s AS establishment_id,
                'physical'::public.location_type AS type,
                dt.derived_valid_from AS valid_from,
                dt.derived_valid_to AS valid_to,
                dt.derived_valid_until AS valid_until,
                dt.physical_address_part1 AS address_part1, dt.physical_address_part2 AS address_part2, dt.physical_address_part3 AS address_part3,
                dt.physical_postcode AS postcode, dt.physical_postplace AS postplace,
                dt.physical_region_id AS region_id, dt.physical_country_id AS country_id,
                dt.typed_physical_latitude AS latitude, dt.typed_physical_longitude AS longitude, dt.typed_physical_altitude AS altitude,
                dt.data_source_id,
                dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
                dt.errors, dt.merge_status
            FROM public.%4$I dt
            WHERE dt.row_id = ANY(%5$L)
              AND dt.action = 'use'
              AND dt.physical_country_id IS NOT NULL
              AND (NULLIF(dt.physical_region_code, '') IS NOT NULL OR NULLIF(dt.physical_country_iso_2, '') IS NOT NULL OR NULLIF(dt.physical_address_part1, '') IS NOT NULL OR NULLIF(dt.physical_postcode, '') IS NOT NULL);
        $$,
            v_source_view_name,   /* %1$I */
            v_select_lu_id_expr,  /* %2$s */
            v_select_est_id_expr, /* %3$s */
            v_data_table_name,    /* %4$I */
            p_batch_row_ids       /* %5$L */
        );

    ELSIF p_step_code = 'postal_location' THEN
        v_sql := format($$
            CREATE OR REPLACE TEMP VIEW %1$I AS
            SELECT
                dt.row_id,
                dt.founding_row_id,
                dt.postal_location_id AS id,
                %2$s AS legal_unit_id,
                %3$s AS establishment_id,
                'postal'::public.location_type AS type,
                dt.derived_valid_from AS valid_from,
                dt.derived_valid_to AS valid_to,
                dt.derived_valid_until AS valid_until,
                dt.postal_address_part1 AS address_part1, dt.postal_address_part2 AS address_part2, dt.postal_address_part3 AS address_part3,
                dt.postal_postcode AS postcode, dt.postal_postplace AS postplace,
                dt.postal_region_id AS region_id, dt.postal_country_id AS country_id,
                dt.typed_postal_latitude AS latitude, dt.typed_postal_longitude AS longitude, dt.typed_postal_altitude AS altitude,
                dt.data_source_id,
                dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
                dt.errors, dt.merge_status
            FROM public.%4$I dt
            WHERE dt.row_id = ANY(%5$L)
              AND dt.action = 'use'
              AND dt.postal_country_id IS NOT NULL
              AND (NULLIF(dt.postal_region_code, '') IS NOT NULL OR NULLIF(dt.postal_country_iso_2, '') IS NOT NULL OR NULLIF(dt.postal_address_part1, '') IS NOT NULL OR NULLIF(dt.postal_postcode, '') IS NOT NULL);
        $$,
            v_source_view_name,   /* %1$I */
            v_select_lu_id_expr,  /* %2$s */
            v_select_est_id_expr, /* %3$s */
            v_data_table_name,    /* %4$I */
            p_batch_row_ids       /* %5$L */
        );
    ELSE
        RAISE EXCEPTION '[Job %] process_location: Invalid step_code %.', p_job_id, p_step_code;
    END IF;

    EXECUTE v_sql;

    EXECUTE format('SELECT count(*) FROM %I', v_source_view_name) INTO v_relevant_rows_count;
    IF v_relevant_rows_count = 0 THEN
        RAISE DEBUG '[Job %] process_location: No usable location data in this batch for step %. Skipping.', p_job_id, p_step_code;
        RETURN;
    END IF;

    RAISE DEBUG '[Job %] process_location: Calling sql_saga.temporal_merge for % rows (step: %).', p_job_id, v_relevant_rows_count, p_step_code;

    BEGIN
        CALL sql_saga.temporal_merge(
            target_table => 'public.location'::regclass,
            source_table => v_source_view_name::regclass,
            identity_columns => ARRAY['id'],
            natural_identity_columns => ARRAY['legal_unit_id', 'establishment_id', 'type'],
            ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
            mode => 'MERGE_ENTITY_PATCH',
            identity_correlation_column => 'founding_row_id',
            update_source_with_identity => true,
            update_source_with_feedback => true,
            feedback_status_column => 'merge_status',
            feedback_status_key => p_step_code,
            feedback_error_column => 'errors',
            feedback_error_key => p_step_code,
            source_row_id_column => 'row_id'
        );

        EXECUTE format($$ SELECT count(*) FROM public.%1$I WHERE row_id = ANY($1) AND errors->%2$L IS NOT NULL $$,
            v_data_table_name, /* %1$I */
            p_step_code        /* %2$L */
        ) INTO v_error_count USING p_batch_row_ids;

        EXECUTE format($$
            UPDATE public.%1$I dt SET
                state = (CASE WHEN dt.errors ? %3$L THEN 'error' ELSE 'processing' END)::public.import_data_state
            FROM %2$I v
            WHERE dt.row_id = v.row_id;
        $$,
            v_data_table_name,  /* %1$I */
            v_source_view_name, /* %2$I */
            p_step_code         /* %3$L */
        );
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;

        RAISE DEBUG '[Job %] process_location: Merge finished for step %. Success: %, Errors: %', p_job_id, p_step_code, v_update_count, v_error_count;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_location: Error during temporal_merge for step %: %. SQLSTATE: %', p_job_id, p_step_code, error_message, SQLSTATE;
        v_sql := format($$UPDATE public.%1$I SET state = 'error'::public.import_data_state, errors = errors || jsonb_build_object('batch_error_process_location', %2$L) WHERE row_id = ANY($1)$$,
                        v_data_table_name, /* %1$I */
                        error_message      /* %2$L */
        );
        EXECUTE v_sql USING p_batch_row_ids;
        RAISE; -- Re-throw
    END;

    RAISE DEBUG '[Job %] process_location (Batch): Finished for step %. Total Processed: %, Errors: %',
        p_job_id, p_step_code, v_update_count + v_error_count, v_error_count;
END;
$process_location$;

-- Helper function for safe numeric casting (general numeric)
CREATE OR REPLACE FUNCTION import.safe_cast_to_numeric(
    IN p_text_numeric TEXT,
    OUT p_value NUMERIC,
    OUT p_error_message TEXT
) LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_numeric IS NULL OR p_text_numeric = '' THEN
        RETURN;
    END IF;

    BEGIN
        p_value := p_text_numeric::NUMERIC;
    EXCEPTION
        WHEN invalid_text_representation THEN
            p_error_message := 'Invalid numeric format: ''' || p_text_numeric || '''. SQLSTATE: ' || SQLSTATE;
            RAISE DEBUG '%', p_error_message;
        WHEN others THEN
            p_error_message := 'Failed to cast ''' || p_text_numeric || ''' to numeric. SQLSTATE: ' || SQLSTATE || ', SQLERRM: ' || SQLERRM;
            RAISE DEBUG '%', p_error_message;
    END;
END;
$$;


COMMIT;
