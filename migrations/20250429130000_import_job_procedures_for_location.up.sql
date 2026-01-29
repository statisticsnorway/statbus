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
DECLARE
    v_sql TEXT;
BEGIN
    p_value := NULL;
    p_error_message := NULL;

    IF p_text_value IS NULL OR p_text_value = '' THEN
        RETURN;
    END IF;

    BEGIN
        v_sql := format($$SELECT %1$L::%2$s$$, p_text_value /* %1$L */, p_target_type /* %2$s */);
        RAISE DEBUG 'try_cast_to_numeric_specific: Executing cast: %', v_sql;
        EXECUTE v_sql INTO p_value;
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
CREATE OR REPLACE PROCEDURE import.analyse_location(p_job_id INT, p_batch_row_id_ranges int4multirange, p_step_code TEXT)
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
    v_default_country_id INT; -- Default country from settings for region validation

    -- For coordinate validation
    v_coord_cast_error_json_expr_sql TEXT;
    v_coord_range_error_json_expr_sql TEXT;
    v_postal_coord_present_error_json_expr_sql TEXT := $$'{}'::jsonb$$; -- Default to SQL literal for empty JSONB
    v_coord_invalid_value_json_expr_sql TEXT;
    v_any_coord_error_condition_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_location (Batch) for step_code %: Starting analysis for range %s', p_job_id, p_step_code, p_batch_row_id_ranges::text;

    -- Load default country from settings for region validation - FAIL FAST if not configured
    SELECT country_id INTO v_default_country_id FROM public.settings LIMIT 1;
    IF v_default_country_id IS NULL THEN
        RAISE EXCEPTION '[Job %] analyse_location: No country_id configured in settings table. System must be configured with a default country before processing location data. Run getting-started setup first.', p_job_id;
    END IF;
    
    -- Validate that the country_id actually exists in the country table
    IF NOT EXISTS (SELECT 1 FROM public.country WHERE id = v_default_country_id) THEN
        RAISE EXCEPTION '[Job %] analyse_location: Invalid country_id % in settings table. Country does not exist in country table.', p_job_id, v_default_country_id;
    END IF;

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
            'physical_region_code_raw', 
            'physical_country_iso_2_raw', 
            'physical_latitude_raw', -- Error key for latitude issues
            'physical_longitude_raw', -- Error key for longitude issues
            'physical_altitude_raw' -- Error key for altitude issues
        ];
        v_invalid_code_keys_to_clear_arr := ARRAY['physical_region_code_raw', 'physical_country_iso_2_raw', 'physical_latitude_raw', 'physical_longitude_raw', 'physical_altitude_raw'];
        v_address_present_condition_sql := $$
            (NULLIF(dt.physical_address_part1_raw, '') IS NOT NULL OR NULLIF(dt.physical_address_part2_raw, '') IS NOT NULL OR NULLIF(dt.physical_address_part3_raw, '') IS NOT NULL OR
             NULLIF(dt.physical_postcode_raw, '') IS NOT NULL OR NULLIF(dt.physical_postplace_raw, '') IS NOT NULL OR NULLIF(dt.physical_region_code_raw, '') IS NOT NULL)
        $$;
        v_fatal_error_condition_sql := format($$
            (%s AND (NULLIF(dt.physical_country_iso_2_raw, '') IS NULL OR l.resolved_physical_country_id IS NULL))
        $$, v_address_present_condition_sql);
        v_fatal_error_json_expr_sql := $$
            jsonb_build_object('physical_country_iso_2_raw', 'Country is required and must be valid when other physical address details are provided.')
        $$;
        v_error_condition_sql := format($$
            -- Invalid region codes for any country (both domestic and foreign)
            (dt.physical_region_code_raw IS NOT NULL AND l.resolved_physical_region_id IS NULL) OR
            -- Missing region warnings for domestic countries (when country is present and domestic)
            (dt.physical_region_code_raw IS NULL AND l.resolved_physical_country_id IS NOT DISTINCT FROM %1$L AND l.resolved_physical_country_id IS NOT NULL) OR
            -- Country check is now fatal if address parts are present, otherwise non-fatal for invalid_codes
            (dt.physical_country_iso_2_raw IS NOT NULL AND l.resolved_physical_country_id IS NULL AND NOT (%2$s)) OR
            (dt.physical_latitude_raw IS NOT NULL AND l.physical_latitude_error_msg IS NOT NULL) OR
            (dt.physical_longitude_raw IS NOT NULL AND l.physical_longitude_error_msg IS NOT NULL) OR
            (dt.physical_altitude_raw IS NOT NULL AND l.physical_altitude_error_msg IS NOT NULL)
        $$, v_default_country_id, v_address_present_condition_sql); -- Format with default_country_id and address_present check

        v_invalid_codes_json_expr_sql := format($$
            CASE 
                WHEN dt.physical_region_code_raw IS NOT NULL AND l.resolved_physical_region_id IS NULL THEN jsonb_build_object('physical_region_code_raw', dt.physical_region_code_raw)  -- Invalid region code
                WHEN dt.physical_region_code_raw IS NULL AND dt.physical_country_iso_2_raw IS NOT NULL AND l.resolved_physical_country_id IS NOT DISTINCT FROM %1$L AND l.resolved_physical_country_id IS NOT NULL THEN jsonb_build_object('physical_region_code_raw', NULL)  -- Missing region for domestic country (include key with NULL)
                ELSE '{}'::jsonb
            END ||
            CASE WHEN dt.physical_country_iso_2_raw IS NOT NULL AND l.resolved_physical_country_id IS NULL THEN jsonb_build_object('physical_country_iso_2_raw', dt.physical_country_iso_2_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.physical_latitude_raw IS NOT NULL AND l.physical_latitude_error_msg IS NOT NULL THEN jsonb_build_object('physical_latitude_raw', dt.physical_latitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.physical_longitude_raw IS NOT NULL AND l.physical_longitude_error_msg IS NOT NULL THEN jsonb_build_object('physical_longitude_raw', dt.physical_longitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.physical_altitude_raw IS NOT NULL AND l.physical_altitude_error_msg IS NOT NULL THEN jsonb_build_object('physical_altitude_raw', dt.physical_altitude_raw) ELSE '{}'::jsonb END
        $$, v_default_country_id);

        -- Coordinate error expressions for physical location
        v_coord_cast_error_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('physical_latitude_raw', l.physical_latitude_error_msg) ||
                jsonb_build_object('physical_longitude_raw', l.physical_longitude_error_msg) ||
                jsonb_build_object('physical_altitude_raw', l.physical_altitude_error_msg)
            )
        $$;
        v_coord_range_error_json_expr_sql := $jsonb_expr$
            jsonb_strip_nulls(
                jsonb_build_object('physical_latitude_raw', CASE WHEN l.resolved_typed_physical_latitude IS NOT NULL AND (l.resolved_typed_physical_latitude < -90 OR l.resolved_typed_physical_latitude > 90) THEN format($$Value %1$s out of range. Expected -90 to 90.$$, l.resolved_typed_physical_latitude::TEXT /* %1$s */) ELSE NULL END) ||
                jsonb_build_object('physical_longitude_raw', CASE WHEN l.resolved_typed_physical_longitude IS NOT NULL AND (l.resolved_typed_physical_longitude < -180 OR l.resolved_typed_physical_longitude > 180) THEN format($$Value %1$s out of range. Expected -180 to 180.$$, l.resolved_typed_physical_longitude::TEXT /* %1$s */) ELSE NULL END) ||
                jsonb_build_object('physical_altitude_raw', CASE WHEN l.resolved_typed_physical_altitude IS NOT NULL AND l.resolved_typed_physical_altitude < 0 THEN format($$Value %1$s cannot be negative. Expected >= 0.$$, l.resolved_typed_physical_altitude::TEXT /* %1$s */) ELSE NULL END)
            )
        $jsonb_expr$;
        v_coord_invalid_value_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('physical_latitude_raw', CASE WHEN (dt.physical_latitude_raw IS NOT NULL AND l.physical_latitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_latitude IS NOT NULL AND (l.resolved_typed_physical_latitude < -90 OR l.resolved_typed_physical_latitude > 90)) THEN dt.physical_latitude_raw ELSE NULL END) ||
                jsonb_build_object('physical_longitude_raw', CASE WHEN (dt.physical_longitude_raw IS NOT NULL AND l.physical_longitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_longitude IS NOT NULL AND (l.resolved_typed_physical_longitude < -180 OR l.resolved_typed_physical_longitude > 180)) THEN dt.physical_longitude_raw ELSE NULL END) ||
                jsonb_build_object('physical_altitude_raw', CASE WHEN (dt.physical_altitude_raw IS NOT NULL AND l.physical_altitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_altitude IS NOT NULL AND l.resolved_typed_physical_altitude < 0) THEN dt.physical_altitude_raw ELSE NULL END)
            )
        $$;
        v_any_coord_error_condition_sql := $$
            (l.physical_latitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_latitude IS NOT NULL AND (l.resolved_typed_physical_latitude < -90 OR l.resolved_typed_physical_latitude > 90)) OR
            (l.physical_longitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_longitude IS NOT NULL AND (l.resolved_typed_physical_longitude < -180 OR l.resolved_typed_physical_longitude > 180)) OR
            (l.physical_altitude_error_msg IS NOT NULL) OR (l.resolved_typed_physical_altitude IS NOT NULL AND l.resolved_typed_physical_altitude < 0)
        $$;

    ELSIF p_step_code = 'postal_location' THEN
        v_error_keys_to_clear_arr := ARRAY[
            'postal_region_code_raw', 
            'postal_country_iso_2_raw', 
            'postal_latitude_raw', -- Error key for latitude issues
            'postal_longitude_raw', -- Error key for longitude issues
            'postal_altitude_raw', -- Error key for altitude issues
            'postal_location_has_coordinates_error' -- Specific error for postal having coords, keep this one
        ];
        v_invalid_code_keys_to_clear_arr := ARRAY['postal_region_code_raw', 'postal_country_iso_2_raw', 'postal_latitude_raw', 'postal_longitude_raw', 'postal_altitude_raw'];
        v_address_present_condition_sql := $$
            (NULLIF(dt.postal_address_part1_raw, '') IS NOT NULL OR NULLIF(dt.postal_address_part2_raw, '') IS NOT NULL OR NULLIF(dt.postal_address_part3_raw, '') IS NOT NULL OR
             NULLIF(dt.postal_postcode_raw, '') IS NOT NULL OR NULLIF(dt.postal_postplace_raw, '') IS NOT NULL OR NULLIF(dt.postal_region_code_raw, '') IS NOT NULL)
        $$;
        v_fatal_error_condition_sql := format($$
            (%s AND (NULLIF(dt.postal_country_iso_2_raw, '') IS NULL OR l.resolved_postal_country_id IS NULL))
        $$, v_address_present_condition_sql);
        v_fatal_error_json_expr_sql := $$
            jsonb_build_object('postal_country_iso_2_raw', 'Country is required and must be valid when other postal address details are provided.')
        $$;
        v_error_condition_sql := format($$
            -- Invalid region codes for any country (both domestic and foreign)
            (dt.postal_region_code_raw IS NOT NULL AND l.resolved_postal_region_id IS NULL) OR
            -- Missing region warnings only for domestic countries (whenever domestic country is present)
            (dt.postal_region_code_raw IS NULL AND l.resolved_postal_country_id IS NOT DISTINCT FROM %1$L AND l.resolved_postal_country_id IS NOT NULL) OR
            (dt.postal_country_iso_2_raw IS NOT NULL AND l.resolved_postal_country_id IS NULL AND NOT (%2$s)) OR
            (dt.postal_latitude_raw IS NOT NULL AND l.postal_latitude_error_msg IS NOT NULL) OR
            (dt.postal_longitude_raw IS NOT NULL AND l.postal_longitude_error_msg IS NOT NULL) OR
            (dt.postal_altitude_raw IS NOT NULL AND l.postal_altitude_error_msg IS NOT NULL)
        $$, v_default_country_id, v_address_present_condition_sql); -- Format with default_country_id and address_present check

        v_invalid_codes_json_expr_sql := format($$
            CASE 
                WHEN dt.postal_region_code_raw IS NOT NULL AND l.resolved_postal_region_id IS NULL THEN jsonb_build_object('postal_region_code_raw', dt.postal_region_code_raw)  -- Invalid region code
                WHEN dt.postal_region_code_raw IS NULL AND dt.postal_country_iso_2_raw IS NOT NULL AND l.resolved_postal_country_id IS NOT DISTINCT FROM %1$L AND l.resolved_postal_country_id IS NOT NULL THEN jsonb_build_object('postal_region_code_raw', NULL)  -- Missing region for domestic country (include key with NULL)
                ELSE '{}'::jsonb
            END ||
            CASE WHEN dt.postal_country_iso_2_raw IS NOT NULL AND l.resolved_postal_country_id IS NULL THEN jsonb_build_object('postal_country_iso_2_raw', dt.postal_country_iso_2_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.postal_latitude_raw IS NOT NULL AND l.postal_latitude_error_msg IS NOT NULL THEN jsonb_build_object('postal_latitude_raw', dt.postal_latitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.postal_longitude_raw IS NOT NULL AND l.postal_longitude_error_msg IS NOT NULL THEN jsonb_build_object('postal_longitude_raw', dt.postal_longitude_raw) ELSE '{}'::jsonb END ||
            CASE WHEN dt.postal_altitude_raw IS NOT NULL AND l.postal_altitude_error_msg IS NOT NULL THEN jsonb_build_object('postal_altitude_raw', dt.postal_altitude_raw) ELSE '{}'::jsonb END
        $$, v_default_country_id);

        -- Coordinate error expressions for postal location
        v_coord_cast_error_json_expr_sql := $$
            jsonb_strip_nulls(
                jsonb_build_object('postal_latitude_raw', l.postal_latitude_error_msg) ||
                jsonb_build_object('postal_longitude_raw', l.postal_longitude_error_msg) ||
                jsonb_build_object('postal_altitude_raw', l.postal_altitude_error_msg)
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
                jsonb_build_object('postal_latitude_raw', CASE WHEN dt.postal_latitude_raw IS NOT NULL AND (l.postal_latitude_error_msg IS NOT NULL OR l.resolved_typed_postal_latitude IS NOT NULL) THEN dt.postal_latitude_raw ELSE NULL END) || -- Log if provided, regardless of cast success for this error type
                jsonb_build_object('postal_longitude_raw', CASE WHEN dt.postal_longitude_raw IS NOT NULL AND (l.postal_longitude_error_msg IS NOT NULL OR l.resolved_typed_postal_longitude IS NOT NULL) THEN dt.postal_longitude_raw ELSE NULL END) ||
                jsonb_build_object('postal_altitude_raw', CASE WHEN dt.postal_altitude_raw IS NOT NULL AND (l.postal_altitude_error_msg IS NOT NULL OR l.resolved_typed_postal_altitude IS NOT NULL) THEN dt.postal_altitude_raw ELSE NULL END)
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

    -- Step 1: Materialize the batch data into a temp table for performance.
    IF to_regclass('pg_temp.t_batch_data') IS NOT NULL THEN DROP TABLE t_batch_data; END IF;
    v_sql := format($$
        CREATE TEMP TABLE t_batch_data ON COMMIT DROP AS
        SELECT
            dt.row_id,
            dt.physical_region_code_raw, dt.physical_country_iso_2_raw,
            dt.postal_region_code_raw, dt.postal_country_iso_2_raw,
            dt.physical_latitude_raw, dt.physical_longitude_raw, dt.physical_altitude_raw,
            dt.postal_latitude_raw, dt.postal_longitude_raw, dt.postal_altitude_raw
        FROM %I dt
        JOIN unnest($1) AS r(range)
          ON dt.row_id >= lower(r.range) AND dt.row_id < upper(r.range)
        WHERE dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_row_id_ranges;

    ANALYZE t_batch_data;

    -- Step 2: Resolve all distinct codes and numerics from the batch in separate temp tables.
    IF to_regclass('pg_temp.t_resolved_codes') IS NOT NULL THEN DROP TABLE t_resolved_codes; END IF;
    CREATE TEMP TABLE t_resolved_codes ON COMMIT DROP AS
    WITH distinct_codes AS (
        SELECT physical_region_code_raw AS code, 'region' AS type FROM t_batch_data WHERE NULLIF(physical_region_code_raw, '') IS NOT NULL
        UNION SELECT physical_country_iso_2_raw AS code, 'country' AS type FROM t_batch_data WHERE NULLIF(physical_country_iso_2_raw, '') IS NOT NULL
        UNION SELECT postal_region_code_raw AS code, 'region' AS type FROM t_batch_data WHERE NULLIF(postal_region_code_raw, '') IS NOT NULL
        UNION SELECT postal_country_iso_2_raw AS code, 'country' AS type FROM t_batch_data WHERE NULLIF(postal_country_iso_2_raw, '') IS NOT NULL
    )
    SELECT dc.code, dc.type, COALESCE(r.id, c.id) as resolved_id
    FROM distinct_codes dc
    LEFT JOIN public.region r ON dc.type = 'region' AND dc.code = r.code
    LEFT JOIN public.country c ON dc.type = 'country' AND dc.code = c.iso_2;

    IF to_regclass('pg_temp.t_resolved_numerics') IS NOT NULL THEN DROP TABLE t_resolved_numerics; END IF;
    CREATE TEMP TABLE t_resolved_numerics ON COMMIT DROP AS
    WITH distinct_numerics AS (
        SELECT physical_latitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(physical_latitude_raw, '') IS NOT NULL
        UNION SELECT physical_longitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(physical_longitude_raw, '') IS NOT NULL
        UNION SELECT physical_altitude_raw AS num_string, 'NUMERIC(6,1)' AS num_type FROM t_batch_data WHERE NULLIF(physical_altitude_raw, '') IS NOT NULL
        UNION SELECT postal_latitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(postal_latitude_raw, '') IS NOT NULL
        UNION SELECT postal_longitude_raw AS num_string, 'NUMERIC(9,6)' AS num_type FROM t_batch_data WHERE NULLIF(postal_longitude_raw, '') IS NOT NULL
        UNION SELECT postal_altitude_raw AS num_string, 'NUMERIC(6,1)' AS num_type FROM t_batch_data WHERE NULLIF(postal_altitude_raw, '') IS NOT NULL
    )
    SELECT
        dn.num_string, dn.num_type,
        cast_result.p_value, cast_result.p_error_message
    FROM distinct_numerics dn
    LEFT JOIN LATERAL import.try_cast_to_numeric_specific(dn.num_string, dn.num_type) AS cast_result ON TRUE;
    
    ANALYZE t_resolved_codes;
    ANALYZE t_resolved_numerics;

    v_sql := format($SQL$
        WITH
        lookups AS (
            SELECT
                bd.row_id AS data_row_id,
                -- Enhanced region resolution: always look for region by code, but validate context later
                (SELECT r.id FROM public.region r WHERE r.code = bd.physical_region_code_raw) as resolved_physical_region_id,
                phys_c.resolved_id as resolved_physical_country_id,
                -- Enhanced region resolution: always look for region by code, but validate context later
                (SELECT r.id FROM public.region r WHERE r.code = bd.postal_region_code_raw) as resolved_postal_region_id,
                post_c.resolved_id as resolved_postal_country_id,
                phys_lat.p_value as resolved_typed_physical_latitude,
                phys_lat.p_error_message as physical_latitude_error_msg,
                phys_lon.p_value as resolved_typed_physical_longitude,
                phys_lon.p_error_message as physical_longitude_error_msg,
                phys_alt.p_value as resolved_typed_physical_altitude,
                phys_alt.p_error_message as physical_altitude_error_msg,
                post_lat.p_value as resolved_typed_postal_latitude,
                post_lat.p_error_message as postal_latitude_error_msg,
                post_lon.p_value as resolved_typed_postal_longitude,
                post_lon.p_error_message as postal_longitude_error_msg,
                post_alt.p_value as resolved_typed_postal_altitude,
                post_alt.p_error_message as postal_altitude_error_msg
            FROM t_batch_data bd
            LEFT JOIN t_resolved_codes phys_c ON bd.physical_country_iso_2_raw = phys_c.code AND phys_c.type = 'country'
            LEFT JOIN t_resolved_codes post_c ON bd.postal_country_iso_2_raw = post_c.code AND post_c.type = 'country'
            LEFT JOIN t_resolved_numerics phys_lat ON bd.physical_latitude_raw = phys_lat.num_string AND phys_lat.num_type = 'NUMERIC(9,6)'
            LEFT JOIN t_resolved_numerics phys_lon ON bd.physical_longitude_raw = phys_lon.num_string AND phys_lon.num_type = 'NUMERIC(9,6)'
            LEFT JOIN t_resolved_numerics phys_alt ON bd.physical_altitude_raw = phys_alt.num_string AND phys_alt.num_type = 'NUMERIC(6,1)'
            LEFT JOIN t_resolved_numerics post_lat ON bd.postal_latitude_raw = post_lat.num_string AND post_lat.num_type = 'NUMERIC(9,6)'
            LEFT JOIN t_resolved_numerics post_lon ON bd.postal_longitude_raw = post_lon.num_string AND post_lon.num_type = 'NUMERIC(6,1)'
            LEFT JOIN t_resolved_numerics post_alt ON bd.postal_altitude_raw = post_alt.num_string AND post_alt.num_type = 'NUMERIC(6,1)'
        )
        UPDATE public.%1$I dt SET
            physical_address_part1 = NULLIF(dt.physical_address_part1_raw, ''),
            physical_address_part2 = NULLIF(dt.physical_address_part2_raw, ''),
            physical_address_part3 = NULLIF(dt.physical_address_part3_raw, ''),
            physical_postcode = NULLIF(dt.physical_postcode_raw, ''),
            physical_postplace = NULLIF(dt.physical_postplace_raw, ''),
            physical_region_id = l.resolved_physical_region_id,
            physical_country_id = l.resolved_physical_country_id,
            physical_latitude = l.resolved_typed_physical_latitude,
            physical_longitude = l.resolved_typed_physical_longitude,
            physical_altitude = l.resolved_typed_physical_altitude,
            postal_address_part1 = NULLIF(dt.postal_address_part1_raw, ''),
            postal_address_part2 = NULLIF(dt.postal_address_part2_raw, ''),
            postal_address_part3 = NULLIF(dt.postal_address_part3_raw, ''),
            postal_postcode = NULLIF(dt.postal_postcode_raw, ''),
            postal_postplace = NULLIF(dt.postal_postplace_raw, ''),
            postal_region_id = l.resolved_postal_region_id,
            postal_country_id = l.resolved_postal_country_id,
            postal_latitude = l.resolved_typed_postal_latitude,
            postal_longitude = l.resolved_typed_postal_longitude,
            postal_altitude = l.resolved_typed_postal_altitude,
            action = CASE
                        WHEN (%6$s) OR (%10$s) THEN 'skip'::public.import_row_action_type -- Fatal error: set action to skip
                        ELSE dt.action -- Preserve existing action otherwise
                     END,
            state = CASE
                        WHEN (%6$s) OR (%10$s) THEN 'error'::public.import_data_state -- Fatal country error OR any coordinate error
                        ELSE 'analysing'::public.import_data_state
                    END,
            errors = jsonb_strip_nulls(
                        (dt.errors - %3$L::text[]) -- Start with existing errors, clearing old ones for this step
                        || CASE WHEN (%6$s) THEN (%7$s) ELSE '{}'::jsonb END -- Add Fatal country error message
                        || (%11$s) -- Add Coordinate cast error messages
                        || (%12$s) -- Add Coordinate range error messages
                        || (%13$s) -- Add Postal coordinate present error message
                    ),
            invalid_codes = (
                        (dt.invalid_codes - %8$L::text[]) -- Start with existing invalid codes, clearing old ones for this step
                        || CASE WHEN (%4$s) AND NOT ((%6$s) OR (%10$s)) THEN (%5$s) ELSE '{}'::jsonb END -- Add Non-fatal region/country codes (if no fatal/coord error)
                        || CASE WHEN (%10$s) THEN jsonb_strip_nulls(%14$s) ELSE '{}'::jsonb END -- Add Original invalid coordinate values (strip nulls here)
                    ),
            last_completed_priority = %9$L::INTEGER -- Always v_step.priority
        FROM lookups l
        WHERE dt.row_id = l.data_row_id;
    $SQL$,
        v_data_table_name,                          /* %1$I (target table) */
        v_default_country_id,                       /* %2$L (default country for region resolution) */
        v_error_keys_to_clear_arr,                  /* %3$L (for clearing error keys) */
        v_error_condition_sql,                      /* %4$s (non-fatal region/country error condition) */
        v_invalid_codes_json_expr_sql,              /* %5$s (for adding non-fatal region/country invalid codes) */
        v_fatal_error_condition_sql,                /* %6$s (fatal country error condition) */
        v_fatal_error_json_expr_sql,                /* %7$s (for adding fatal country error message) */
        v_invalid_code_keys_to_clear_arr,           /* %8$L (for clearing invalid_codes keys) */
        v_step.priority,                            /* %9$L (for last_completed_priority) */
        v_any_coord_error_condition_sql,            /* %10$s (any coordinate error condition) */
        v_coord_cast_error_json_expr_sql,           /* %11$s (coordinate cast error JSON) */
        v_coord_range_error_json_expr_sql,          /* %12$s (coordinate range error JSON) */
        v_postal_coord_present_error_json_expr_sql, /* %13$s (postal has coords error JSON) */
        v_coord_invalid_value_json_expr_sql        /* %14$s (original invalid coordinate values JSON) */
    );

    RAISE DEBUG '[Job %] analyse_location: Single-pass batch update for non-skipped rows for step %: %', p_job_id, p_step_code, v_sql;

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_location: Updated % non-skipped rows in single pass for step %.', p_job_id, v_update_count, p_step_code;

        -- Unconditionally advance priority for all rows in batch to ensure progress
        v_sql := format($$
            UPDATE public.%1$I dt SET
                last_completed_priority = %2$L
            WHERE dt.row_id <@ $1 AND dt.last_completed_priority < %2$L;
        $$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
        RAISE DEBUG '[Job %] analyse_location: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_id_ranges;
        GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_location: Advanced last_completed_priority for % total rows in batch for step %.', p_job_id, v_skipped_update_count, p_step_code;

        v_sql := format($$SELECT COUNT(*) FROM public.%1$I WHERE row_id <@ $1 AND state = 'error' AND (errors ?| %2$L::text[])$$,
                       v_data_table_name /* %1$I */, v_error_keys_to_clear_arr /* %2$L */);
        RAISE DEBUG '[Job %] analyse_location: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql
        INTO v_error_count
        USING p_batch_row_id_ranges;
        RAISE DEBUG '[Job %] analyse_location: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION 
        WHEN PROGRAM_LIMIT_EXCEEDED THEN -- e.g. statement too complex, or other similar limit errors
            error_message := SQLERRM;
            RAISE WARNING '[Job %] analyse_location: Program limit exceeded during single-pass batch update for step %: %. SQLSTATE: %', p_job_id, p_step_code, error_message, SQLSTATE;
            -- Fallback or simplified error marking might be needed here if the main query is too complex
            UPDATE public.import_job
            SET error = jsonb_build_object('analyse_location_error', format($$Program limit error for step %1$s: %2$s$$, p_step_code /* %1$s */, error_message /* %2$s */))::TEXT,
                state = 'failed'
            WHERE id = p_job_id;
            -- Don't re-throw - job is marked as failed
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
                    WHERE dt.row_id <@ $1;
                $$, v_data_table_name /* %1$I */, 'error'::public.import_data_state /* %2$L */, p_step_code /* %3$s */, error_message /* %4$L */);
                RAISE DEBUG '[Job %] analyse_location: Marking rows as error in exception handler with SQL: %', p_job_id, v_sql;
                EXECUTE v_sql USING p_batch_row_id_ranges;
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING '[Job %] analyse_location: Could not mark individual data rows as error after unexpected error: %', p_job_id, SQLERRM;
            END;
            -- Mark the job as failed
            UPDATE public.import_job
            SET error = jsonb_build_object('analyse_location_error', format($SQL$Unexpected error for step %1$s: %2$s$SQL$, p_step_code /* %1$s */, error_message /* %2$s */))::TEXT,
                state = 'failed'
            WHERE id = p_job_id;
            RAISE DEBUG '[Job %] analyse_location: Marked job as failed due to unexpected error for step %: %', p_job_id, p_step_code, error_message;
            -- Don't re-throw - job is marked as failed
    END;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_row_id_ranges, v_error_keys_to_clear_arr, p_step_code);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_location: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_location (Batch): Finished analysis for batch for step %. Errors newly marked in this step: %', p_job_id, p_step_code, v_error_count;
END;
$analyse_location$;


-- Procedure to operate (insert/update/upsert) location data (handles both physical and postal) (Batch Oriented)
CREATE OR REPLACE PROCEDURE import.process_location(p_job_id INT, p_batch_row_id_ranges int4multirange, p_step_code TEXT)
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
    v_merge_mode sql_saga.temporal_merge_mode;
BEGIN
    RAISE DEBUG '[Job %] process_location (Batch) for step_code %: Starting operation for range %s', p_job_id, p_step_code, p_batch_row_id_ranges::text;

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
                dt.valid_from,
                dt.valid_to,
                dt.valid_until,
                dt.physical_address_part1 AS address_part1, dt.physical_address_part2 AS address_part2, dt.physical_address_part3 AS address_part3,
                dt.physical_postcode AS postcode, dt.physical_postplace AS postplace,
                dt.physical_region_id AS region_id, dt.physical_country_id AS country_id,
                dt.physical_latitude AS latitude, dt.physical_longitude AS longitude, dt.physical_altitude AS altitude,
                dt.data_source_id,
                dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
                dt.errors, dt.merge_status
            FROM public.%4$I dt
            WHERE dt.row_id <@ %5$L::int4multirange
              AND dt.action = 'use'
              AND dt.physical_country_id IS NOT NULL
              AND (NULLIF(dt.physical_region_code_raw, '') IS NOT NULL OR NULLIF(dt.physical_country_iso_2_raw, '') IS NOT NULL OR NULLIF(dt.physical_address_part1_raw, '') IS NOT NULL OR NULLIF(dt.physical_postcode_raw, '') IS NOT NULL);
        $$,
            v_source_view_name,    /* %1$I */
            v_select_lu_id_expr,   /* %2$s */
            v_select_est_id_expr,  /* %3$s */
            v_data_table_name,     /* %4$I */
            p_batch_row_id_ranges  /* %5$L */
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
                dt.valid_from,
                dt.valid_to,
                dt.valid_until,
                dt.postal_address_part1 AS address_part1, dt.postal_address_part2 AS address_part2, dt.postal_address_part3 AS address_part3,
                dt.postal_postcode AS postcode, dt.postal_postplace AS postplace,
                dt.postal_region_id AS region_id, dt.postal_country_id AS country_id,
                dt.postal_latitude AS latitude, dt.postal_longitude AS longitude, dt.postal_altitude AS altitude,
                dt.data_source_id,
                dt.edit_by_user_id, dt.edit_at, dt.edit_comment,
                dt.errors, dt.merge_status
            FROM public.%4$I dt
            WHERE dt.row_id <@ %5$L::int4multirange
              AND dt.action = 'use'
              AND dt.postal_country_id IS NOT NULL
              AND (NULLIF(dt.postal_region_code_raw, '') IS NOT NULL OR NULLIF(dt.postal_country_iso_2_raw, '') IS NOT NULL OR NULLIF(dt.postal_address_part1_raw, '') IS NOT NULL OR NULLIF(dt.postal_postcode_raw, '') IS NOT NULL);
        $$,
            v_source_view_name,    /* %1$I */
            v_select_lu_id_expr,   /* %2$s */
            v_select_est_id_expr,  /* %3$s */
            v_data_table_name,     /* %4$I */
            p_batch_row_id_ranges  /* %5$L */
        );
    ELSE
        RAISE EXCEPTION '[Job %] process_location: Invalid step_code %.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] process_location: Creating temp source view %s with SQL: %', p_job_id, v_source_view_name, v_sql;
    EXECUTE v_sql;

    v_sql := format('SELECT count(*) FROM %I', v_source_view_name);
    RAISE DEBUG '[Job %] process_location: Counting relevant rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql INTO v_relevant_rows_count;
    IF v_relevant_rows_count = 0 THEN
        RAISE DEBUG '[Job %] process_location: No usable location data in this batch for step %. Skipping.', p_job_id, p_step_code;
        RETURN;
    END IF;

    RAISE DEBUG '[Job %] process_location: Calling sql_saga.temporal_merge for % rows (step: %).', p_job_id, v_relevant_rows_count, p_step_code;

    BEGIN
        -- Determine merge mode from job strategy
        v_merge_mode := CASE v_definition.strategy
            WHEN 'insert_or_replace' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
            WHEN 'replace_only' THEN 'REPLACE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            WHEN 'insert_or_update' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            WHEN 'update_only' THEN 'UPDATE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode -- Default to safer patch for other cases
        END;
        RAISE DEBUG '[Job %] process_location: Determined merge mode % from strategy %', p_job_id, v_merge_mode, v_definition.strategy;

        CALL sql_saga.temporal_merge(
            target_table => 'public.location'::regclass,
            source_table => v_source_view_name::regclass,
            primary_identity_columns => ARRAY['id'],
            natural_identity_columns => ARRAY['legal_unit_id', 'establishment_id', 'type'],
            mode => v_merge_mode,
            row_id_column => 'row_id',
            founding_id_column => 'founding_row_id',
            update_source_with_identity => true,
            update_source_with_feedback => true,
            feedback_status_column => 'merge_status',
            feedback_status_key => p_step_code,
            feedback_error_column => 'errors',
            feedback_error_key => p_step_code
        );

        v_sql := format($$ SELECT count(*) FROM public.%1$I WHERE row_id <@ $1 AND errors->%2$L IS NOT NULL $$,
            v_data_table_name, /* %1$I */
            p_step_code        /* %2$L */
        );
        RAISE DEBUG '[Job %] process_location: Counting merge errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_row_id_ranges;

        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = (CASE WHEN dt.errors ? %3$L THEN 'error' ELSE 'processing' END)::public.import_data_state
            FROM %2$I v
            WHERE dt.row_id = v.row_id;
        $$,
            v_data_table_name,  /* %1$I */
            v_source_view_name, /* %2$I */
            p_step_code         /* %3$L */
        );
        RAISE DEBUG '[Job %] process_location: Updating state post-merge with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;

        RAISE DEBUG '[Job %] process_location: Merge finished for step %. Success: %, Errors: %', p_job_id, p_step_code, v_update_count, v_error_count;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_location: Error during temporal_merge for step %: %. SQLSTATE: %', p_job_id, p_step_code, error_message, SQLSTATE;
        v_sql := format($$UPDATE public.%1$I SET state = 'error'::public.import_data_state, errors = errors || jsonb_build_object('batch_error_process_location', %2$L) WHERE row_id <@ $1$$,
                        v_data_table_name, /* %1$I */
                        error_message      /* %2$L */
        );
        RAISE DEBUG '[Job %] process_location: Marking rows as error in exception handler with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_row_id_ranges;
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
