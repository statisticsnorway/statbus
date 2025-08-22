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
            WHERE dt_sub.row_id = ANY($1) AND dt_sub.action != 'skip'
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
            error = jsonb_strip_nulls(
                        COALESCE(dt.error, '{}'::jsonb) -- Start with existing errors
                        || CASE WHEN (%6$s) THEN (%7$s) ELSE '{}'::jsonb END -- Add Fatal country error message
                        || (%11$s) -- Add Coordinate cast error messages
                        || (%12$s) -- Add Coordinate range error messages
                        || (%13$s) -- Add Postal coordinate present error message
                    ),
            invalid_codes = jsonb_strip_nulls(
                        COALESCE(dt.invalid_codes, '{}'::jsonb) -- Start with existing invalid codes
                        || CASE WHEN (%4$s) AND NOT ((%6$s) OR (%10$s)) THEN (%5$s) ELSE '{}'::jsonb END -- Add Non-fatal region/country codes (if no fatal/coord error)
                        || CASE WHEN (%10$s) THEN (%14$s) ELSE '{}'::jsonb END -- Add Original invalid coordinate values
                    ),
            last_completed_priority = %9$L::INTEGER -- Always v_step.priority
        FROM lookups l
        WHERE dt.row_id = l.data_row_id AND dt.row_id = ANY($1) AND dt.action IS DISTINCT FROM 'skip';
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
        v_coord_invalid_value_json_expr_sql     /* %14$s (original invalid coordinate values JSON) */
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

        EXECUTE format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id = ANY($1) AND state = 'error' AND (error ?| %2$L::text[])$$,
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
            SET error = jsonb_build_object('analyse_location_error', format($$Program limit error for step %s: %s$$, p_step_code, error_message)),
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
                        error = COALESCE(dt.error, '{}'::jsonb) || jsonb_build_object('location_batch_error', 'Unexpected error during update for step %3$s: ' || %4$L),
                        last_completed_priority = dt.last_completed_priority -- Do not advance priority on unexpected error, use existing LCP
                    WHERE dt.row_id = ANY($1);
                $$, v_data_table_name /* %1$I */, 'error'::public.import_data_state /* %2$L */, p_step_code /* %3$s */, error_message /* %4$L */);
                EXECUTE v_sql USING p_batch_row_ids;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING '[Job %] analyse_location: Could not mark individual data rows as error after unexpected error: %', p_job_id, SQLERRM;
            END;
            -- Mark the job as failed
            UPDATE public.import_job
            SET error = jsonb_build_object('analyse_location_error', format($$Unexpected error for step %s: %s$$, p_step_code, error_message)),
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
    v_snapshot JSONB;
    v_definition public.import_definition;
    v_step public.import_step;
    v_strategy public.import_strategy;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_inserted_new_loc_count INT := 0;
    v_updated_existing_loc_count INT := 0;
    v_update_count INT; -- Declaration for v_update_count
    error_message TEXT;
    v_location_type public.location_type;
    v_job_mode public.import_mode;
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
    v_batch_upsert_result RECORD;
    v_batch_upsert_error_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_batch_upsert_success_row_ids INTEGER[] := ARRAY[]::INTEGER[];
    v_final_id_col TEXT;
    v_row RECORD; -- For debugging loop
BEGIN
    RAISE DEBUG '[Job %] process_location (Batch) for step_code %: Starting operation for % rows', p_job_id, p_step_code, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    IF v_definition IS NULL THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] process_location: Step with code % not found in snapshot.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] process_location: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;
    v_location_type := CASE v_step.code
        WHEN 'physical_location' THEN 'physical'::public.location_type
        WHEN 'postal_location' THEN 'postal'::public.location_type
        ELSE NULL
    END;

    IF v_location_type IS NULL THEN
        RAISE EXCEPTION '[Job %] process_location: Invalid step_code % provided for location processing.', p_job_id, p_step_code;
    END IF;

    v_final_id_col := CASE v_location_type WHEN 'physical' THEN 'physical_location_id' ELSE 'postal_location_id' END;
    v_strategy := v_definition.strategy;

    v_job_mode := v_definition.mode;

    IF v_job_mode = 'legal_unit' THEN
        v_select_lu_id_expr := 'dt.legal_unit_id';
        v_select_est_id_expr := 'NULL::INTEGER';
    ELSIF v_job_mode = 'establishment_formal' THEN
        v_select_lu_id_expr := 'dt.legal_unit_id';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSIF v_job_mode = 'establishment_informal' THEN
        v_select_lu_id_expr := 'NULL::INTEGER';
        v_select_est_id_expr := 'dt.establishment_id';
    ELSE
        RAISE EXCEPTION '[Job %] process_location: Unhandled job mode % for unit ID selection. Expected one of (legal_unit, establishment_formal, establishment_informal).', p_job_id, v_job_mode;
    END IF;
    RAISE DEBUG '[Job %] process_location: Based on mode %, using lu_id_expr: %, est_id_expr: % for table %', 
        p_job_id, v_job_mode, v_select_lu_id_expr, v_select_est_id_expr, v_data_table_name;

    CREATE TEMP TABLE temp_batch_data (
        data_row_id INTEGER PRIMARY KEY,
        founding_row_id INTEGER, -- Added to link rows of the same logical entity
        legal_unit_id INT,
        establishment_id INT,
        valid_after DATE,
        valid_from DATE,
        valid_to DATE,
        data_source_id INT,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        edit_comment TEXT,
        address_part1 TEXT, address_part2 TEXT, address_part3 TEXT,
        postcode TEXT, postplace TEXT, region_id INT, country_id INT,
        latitude NUMERIC, longitude NUMERIC, altitude NUMERIC,
        existing_loc_id INT, -- Will store the ID of the location in public.location
        action public.import_row_action_type
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_batch_data (
            data_row_id, founding_row_id, legal_unit_id, establishment_id, valid_after, valid_from, valid_to, data_source_id,
            edit_by_user_id, edit_at, edit_comment,
            address_part1, address_part2, address_part3, postcode, postplace,
            region_id, country_id, latitude, longitude, altitude, action
        )
        SELECT
            dt.row_id, dt.founding_row_id, %2$s, %3$s,
            dt.derived_valid_after,
            dt.derived_valid_from,
            dt.derived_valid_to,
            dt.data_source_id,
            dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
            dt.%4$I, dt.%5$I, dt.%6$I, dt.%7$I, dt.%8$I,
            dt.%9$I, dt.%10$I,
            dt.%11$I, dt.%12$I, dt.%13$I,
            dt.action
         FROM public.%1$I dt WHERE dt.row_id = ANY($1) AND dt.action != 'skip';
    $$,
        v_data_table_name, /* %1$I */
        v_select_lu_id_expr, /* %2$s */
        v_select_est_id_expr, /* %3$s */
        CASE v_location_type WHEN 'physical' THEN 'physical_address_part1' ELSE 'postal_address_part1' END, /* %4$I */
        CASE v_location_type WHEN 'physical' THEN 'physical_address_part2' ELSE 'postal_address_part2' END, /* %5$I */
        CASE v_location_type WHEN 'physical' THEN 'physical_address_part3' ELSE 'postal_address_part3' END, /* %6$I */
        CASE v_location_type WHEN 'physical' THEN 'physical_postcode' ELSE 'postal_postcode' END, /* %7$I */
        CASE v_location_type WHEN 'physical' THEN 'physical_postplace' ELSE 'postal_postplace' END, /* %8$I */
        CASE v_location_type WHEN 'physical' THEN 'physical_region_id' ELSE 'postal_region_id' END, /* %9$I */
        CASE v_location_type WHEN 'physical' THEN 'physical_country_id' ELSE 'postal_country_id' END, /* %10$I */
        CASE v_location_type WHEN 'physical' THEN 'typed_physical_latitude' ELSE 'typed_postal_latitude' END, /* %11$I */
        CASE v_location_type WHEN 'physical' THEN 'typed_physical_longitude' ELSE 'typed_postal_longitude' END, /* %12$I */
        CASE v_location_type WHEN 'physical' THEN 'typed_physical_altitude' ELSE 'typed_postal_altitude' END /* %13$I */
    );
    RAISE DEBUG '[Job %] process_location: Fetching batch data for type %: %', p_job_id, v_location_type, v_sql;
    EXECUTE v_sql USING p_batch_row_ids;

    -- Debug: Log content of temp_batch_data
    FOR v_row IN SELECT * FROM temp_batch_data LOOP
        RAISE DEBUG '[Job %] process_location: temp_batch_data content for data_row_id %: FRID:% LU_ID:%, EST_ID:%, ExLocID:% VF:% VT:% Action:% Addr1:% Postcode:%',
            p_job_id, v_row.data_row_id, v_row.founding_row_id, v_row.legal_unit_id, v_row.establishment_id, v_row.existing_loc_id, v_row.valid_from, v_row.valid_to, v_row.action, v_row.address_part1, v_row.postcode;
    END LOOP;

    -- Step 2: Determine existing_loc_id for entities that pre-exist in public.location
    -- This updates temp_batch_data.existing_loc_id for all rows matching a unit.
    IF v_job_mode = 'legal_unit' THEN
        v_sql := format($$
            UPDATE temp_batch_data tbd SET
                existing_loc_id = loc.id
            FROM public.location loc
            WHERE loc.type = %L
              AND loc.legal_unit_id = tbd.legal_unit_id
              AND loc.establishment_id IS NULL; -- Location is exclusively for the Legal Unit
        $$, v_location_type);
    ELSIF v_job_mode IN ('establishment_formal', 'establishment_informal') THEN
        v_sql := format($$
            UPDATE temp_batch_data tbd SET
                existing_loc_id = loc.id
            FROM public.location loc
            WHERE loc.type = %L
              AND loc.establishment_id = tbd.establishment_id
              AND loc.legal_unit_id IS NULL; -- Location is exclusively for the Establishment
        $$, v_location_type);
    ELSE
        -- This case should have been caught earlier by the job mode check, but as a safeguard:
        RAISE EXCEPTION '[Job %] process_location: Unhandled job mode % for existing_loc_id lookup.', p_job_id, v_job_mode;
    END IF;
    RAISE DEBUG '[Job %] process_location: Determining existing IDs (mode: %): %', p_job_id, v_job_mode, v_sql;
    EXECUTE v_sql;

    -- Temp table to store newly created location_ids and their original data_row_id
    CREATE TEMP TABLE temp_created_locs (
        data_row_id INTEGER PRIMARY KEY,
        new_location_id INT NOT NULL
    ) ON COMMIT DROP;

    BEGIN
        -- Handle INSERTs for new locations (action = 'insert') using MERGE
        RAISE DEBUG '[Job %] process_location: Handling INSERTS for new locations (type: %) using MERGE.', p_job_id, v_location_type;

        WITH source_for_insert AS (
            SELECT
                tbd.data_row_id, tbd.legal_unit_id, tbd.establishment_id, tbd.valid_after, tbd.valid_from, tbd.valid_to, tbd.data_source_id, -- Added valid_after
                tbd.edit_by_user_id, tbd.edit_at, tbd.edit_comment,
                tbd.address_part1, tbd.address_part2, tbd.address_part3, tbd.postcode, tbd.postplace,
                tbd.region_id, tbd.country_id, tbd.latitude, tbd.longitude, tbd.altitude
            FROM temp_batch_data tbd
            WHERE tbd.action = 'insert' AND tbd.existing_loc_id IS NULL -- Only insert if no existing location ID was found
            AND (tbd.region_id IS NOT NULL OR tbd.country_id IS NOT NULL OR tbd.address_part1 IS NOT NULL OR tbd.postcode IS NOT NULL) -- Ensure some actual location data exists
        ),
        merged_locations AS (
            MERGE INTO public.location loc
            USING source_for_insert sfi
            ON 1 = 0 -- Always false to force INSERT for all rows from sfi
            WHEN NOT MATCHED THEN
                INSERT (
                    legal_unit_id, establishment_id, type,
                    address_part1, address_part2, address_part3, postcode, postplace,
                    region_id, country_id, latitude, longitude, altitude,
                    data_source_id, valid_after, valid_to, -- Changed
                    edit_by_user_id, edit_at, edit_comment
                )
                VALUES (
                    CASE WHEN v_job_mode = 'legal_unit' THEN sfi.legal_unit_id ELSE NULL END,
                    CASE WHEN v_job_mode IN ('establishment_formal', 'establishment_informal') THEN sfi.establishment_id ELSE NULL END,
                    v_location_type,
                    sfi.address_part1, sfi.address_part2, sfi.address_part3, sfi.postcode, sfi.postplace,
                    sfi.region_id, sfi.country_id, sfi.latitude, sfi.longitude, sfi.altitude,
                    sfi.data_source_id, sfi.valid_after, sfi.valid_to, -- Changed
                    sfi.edit_by_user_id, sfi.edit_at, sfi.edit_comment -- Use sfi.edit_comment
                )
            RETURNING loc.id AS new_location_id, sfi.data_row_id AS data_row_id
        )
        INSERT INTO temp_created_locs (data_row_id, new_location_id)
        SELECT ml.data_row_id, ml.new_location_id
        FROM merged_locations ml;

        GET DIAGNOSTICS v_inserted_new_loc_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_location: Inserted % new locations into temp_created_locs via MERGE (type: %).', p_job_id, v_inserted_new_loc_count, v_location_type;

        IF v_inserted_new_loc_count > 0 THEN
            EXECUTE format($$
                UPDATE public.%1$I dt SET
                    %2$I = tcl.new_location_id,
                    error = NULL,
                    state = %3$L
                FROM temp_created_locs tcl
                WHERE dt.row_id = tcl.data_row_id AND dt.state != 'error';
            $$, v_data_table_name /* %1$I */, v_final_id_col /* %2$I */, 'processing'::public.import_data_state /* %3$L */);
            RAISE DEBUG '[Job %] process_location: Updated _data table for % new locations (type: %).', p_job_id, v_inserted_new_loc_count, v_location_type;
        END IF;

        -- Step 4: Propagate newly created location_ids to other rows in temp_batch_data
        -- belonging to the same logical entity (identified by founding_row_id and unit id).
        -- This ensures that 'replace' actions for newly created entities use the correct location_id.
        IF v_inserted_new_loc_count > 0 THEN
            RAISE DEBUG '[Job %] process_location: Propagating new location_ids within temp_batch_data (type: %).', p_job_id, v_location_type;
            WITH new_entity_details AS (
                SELECT
                    tcl.new_location_id,
                    tbd_founder.founding_row_id,
                    tbd_founder.legal_unit_id,
                    tbd_founder.establishment_id
                FROM temp_created_locs tcl
                JOIN temp_batch_data tbd_founder ON tcl.data_row_id = tbd_founder.data_row_id -- tbd_founder is the row that caused the insert
            )
            UPDATE temp_batch_data tbd -- tbd are the rows to be updated
            SET existing_loc_id = ned.new_location_id
            FROM new_entity_details ned
            WHERE tbd.founding_row_id = ned.founding_row_id
              AND ( -- Match on the correct unit ID based on job mode
                    (v_job_mode = 'legal_unit' AND tbd.legal_unit_id = ned.legal_unit_id) OR
                    (v_job_mode IN ('establishment_formal', 'establishment_informal') AND tbd.establishment_id = ned.establishment_id)
                  )
              AND tbd.existing_loc_id IS NULL -- Only update if not already set
              AND tbd.action IN ('replace', 'update'); -- Apply to subsequent actions for the same new entity
            GET DIAGNOSTICS v_update_count = ROW_COUNT;
            RAISE DEBUG '[Job %] process_location: Propagated new location_ids to % rows in temp_batch_data (type: %).', p_job_id, v_update_count, v_location_type;
        END IF;

        -- Handle REPLACES for existing locations (action = 'replace' or 'update')
        RAISE DEBUG '[Job %] process_location: Handling REPLACES/UPDATES for existing locations (type: %).', p_job_id, v_location_type;
        -- Create temp source table for batch upsert
        CREATE TEMP TABLE temp_loc_upsert_source (
            row_id INTEGER PRIMARY KEY,
            id INT,
            valid_after DATE NOT NULL, -- Changed
            valid_to DATE NOT NULL,
            legal_unit_id INT,
            establishment_id INT,
            type public.location_type,
            address_part1 TEXT, address_part2 TEXT, address_part3 TEXT,
            postcode TEXT, postplace TEXT, region_id INT, country_id INT,
            latitude NUMERIC, longitude NUMERIC, altitude NUMERIC,
            data_source_id INT,
            edit_by_user_id INT,
            edit_at TIMESTAMPTZ,
            edit_comment TEXT
        ) ON COMMIT DROP;

        INSERT INTO temp_loc_upsert_source (
            row_id, id, valid_after, valid_to, legal_unit_id, establishment_id, type, -- Changed valid_from to valid_after
            address_part1, address_part2, address_part3, postcode, postplace, region_id, country_id,
            latitude, longitude, altitude, data_source_id, edit_by_user_id, edit_at, edit_comment
        )
        SELECT
            tbd.data_row_id, -- This becomes row_id in temp_loc_upsert_source
            tbd.existing_loc_id,
            tbd.valid_after, -- Changed
            tbd.valid_to,
            CASE WHEN v_job_mode = 'legal_unit' THEN tbd.legal_unit_id ELSE NULL END,
            CASE WHEN v_job_mode IN ('establishment_formal', 'establishment_informal') THEN tbd.establishment_id ELSE NULL END,
            v_location_type,
            tbd.address_part1, tbd.address_part2, tbd.address_part3, tbd.postcode, tbd.postplace,
            tbd.region_id, tbd.country_id, tbd.latitude, tbd.longitude, tbd.altitude,
            tbd.data_source_id, tbd.edit_by_user_id, tbd.edit_at,
            tbd.edit_comment
        FROM temp_batch_data tbd
        WHERE tbd.action IN ('replace', 'update') -- Process both 'replace' and 'update' actions here
        AND tbd.existing_loc_id IS NOT NULL -- Crucially, only process if we have a location ID
        AND (tbd.region_id IS NOT NULL OR tbd.country_id IS NOT NULL OR tbd.address_part1 IS NOT NULL OR tbd.postcode IS NOT NULL); -- Ensure some actual location data exists

        GET DIAGNOSTICS v_updated_existing_loc_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_location: Populated temp_loc_upsert_source with % rows for batch replace/update (type: %).', p_job_id, v_updated_existing_loc_count, v_location_type;

        IF v_updated_existing_loc_count > 0 THEN
            RAISE DEBUG '[Job %] process_location: Calling batch_insert_or_replace_generic_valid_time_table for location (type: %). Found % rows to process.', p_job_id, v_location_type, v_updated_existing_loc_count;
            FOR v_batch_upsert_result IN
                SELECT * FROM import.batch_insert_or_replace_generic_valid_time_table(
                    p_target_schema_name => 'public',
                    p_target_table_name => 'location',
                    p_source_schema_name => 'pg_temp',
                    p_source_table_name => 'temp_loc_upsert_source',
                    p_unique_columns => '[]'::jsonb,
                    p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                    p_id_column_name => 'id'
                )
            LOOP
                IF v_batch_upsert_result.status = 'ERROR' THEN
                    v_batch_upsert_error_row_ids := array_append(v_batch_upsert_error_row_ids, v_batch_upsert_result.source_row_id);
                    EXECUTE format($$
                        UPDATE public.%1$I SET
                            state = %2$L,
                            error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_replace_location_error', %3$L)
                            -- last_completed_priority is preserved (not changed) on error
                        WHERE row_id = %4$L;
                    $$, v_data_table_name /* %1$I */, 'error'::public.import_data_state /* %2$L */, v_batch_upsert_result.error_message /* %3$L */, v_batch_upsert_result.source_row_id /* %4$L */);
                ELSE
                    v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                END IF;
            END LOOP;

            v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
            RAISE DEBUG '[Job %] process_location: Batch replace finished for type %. Success: %, Errors: %', p_job_id, v_location_type, array_length(v_batch_upsert_success_row_ids, 1), v_error_count;

            IF array_length(v_batch_upsert_success_row_ids, 1) > 0 THEN
                v_sql := format($$
                    UPDATE public.%1$I dt SET
                        %2$I = tbd.existing_loc_id,
                        error = NULL,
                        state = %3$L
                    FROM temp_batch_data tbd
                    WHERE dt.row_id = tbd.data_row_id
                      AND dt.row_id = ANY($1);
                $$, v_data_table_name /* %1$I */, v_final_id_col /* %2$I */, 'processing'::public.import_data_state /* %3$L */);
                RAISE DEBUG '[Job %] process_location: Updating _data table for successful replace rows (type: %): %', p_job_id, v_location_type, v_sql;
                EXECUTE v_sql USING v_batch_upsert_success_row_ids;
            END IF;
        END IF;
        IF to_regclass('pg_temp.temp_loc_upsert_source') IS NOT NULL THEN DROP TABLE temp_loc_upsert_source; END IF;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_location: Error during batch operation for type %: %. SQLSTATE: %', p_job_id, v_location_type, error_message, SQLSTATE;
        -- Attempt to mark individual data rows as error (best effort)
        BEGIN
            v_sql := format($$UPDATE public.%1$I SET state = %2$L, error = COALESCE(error, '{}'::jsonb) || %3$L WHERE row_id = ANY($1)$$, -- LCP not changed here
                           v_data_table_name /* %1$I */, 'error'::public.import_data_state /* %2$L */, jsonb_build_object('batch_error_process_location', error_message) /* %3$L */);
            EXECUTE v_sql USING p_batch_row_ids;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '[Job %] process_location: Could not mark individual data rows as error: %', p_job_id, SQLERRM;
        END;
        -- Mark the job as failed
        UPDATE public.import_job
        SET error = jsonb_build_object('process_location_error', format($$Error for type %s: %s$$, v_location_type, error_message)),
            state = 'finished' -- Consistently set state to 'finished' on error
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] process_location: Marked job as failed due to error for type %: %', p_job_id, v_location_type, error_message;
        RAISE; -- Re-throw the exception to halt the phase
    END;

    -- The framework now handles advancing priority for all rows, including unprocessed and skipped rows. No update needed here.

    RAISE DEBUG '[Job %] process_location (Batch): Finished. New: %, Replaced: %. Errors: %',
        p_job_id, v_inserted_new_loc_count, v_updated_existing_loc_count, v_error_count;

    IF to_regclass('pg_temp.temp_batch_data') IS NOT NULL THEN DROP TABLE temp_batch_data; END IF;
    IF to_regclass('pg_temp.temp_created_locs') IS NOT NULL THEN DROP TABLE temp_created_locs; END IF;
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
