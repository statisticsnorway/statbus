-- Migration: implement_location_procedures
-- Implements the analyse and operation procedures for the PhysicalLocation
-- and PostalLocation import targets using generic location handlers.

BEGIN;

-- Procedure to analyse location data (handles both physical and postal) (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.analyse_location(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_location$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_location (Batch) for step_code %: Starting analysis for % rows', p_job_id, p_step_code, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_step FROM public.import_step WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_location: Step with code % not found.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] analyse_location: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;

    v_sql := format($$
        UPDATE public.%I dt SET
            physical_region_id = src.physical_region_id,
            physical_country_id = src.physical_country_id,
            postal_region_id = src.postal_region_id,
            postal_country_id = src.postal_country_id
        FROM (
            SELECT
                dt_sub.row_id AS row_id_for_join,
                pr.id as physical_region_id,
                pc.id as physical_country_id,
                psr.id as postal_region_id,
                psc.id as postal_country_id
            FROM public.%I dt_sub
            LEFT JOIN public.region pr ON dt_sub.physical_region_code IS NOT NULL AND pr.code = dt_sub.physical_region_code
            LEFT JOIN public.country pc ON dt_sub.physical_country_iso_2 IS NOT NULL AND pc.iso_2 = dt_sub.physical_country_iso_2
            LEFT JOIN public.region psr ON dt_sub.postal_region_code IS NOT NULL AND psr.code = dt_sub.postal_region_code
            LEFT JOIN public.country psc ON dt_sub.postal_country_iso_2 IS NOT NULL AND psc.iso_2 = dt_sub.postal_country_iso_2
            WHERE dt_sub.row_id = ANY(%L)
        ) AS src
        WHERE dt.row_id = src.row_id_for_join;
    $$, v_data_table_name, v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] analyse_location: Batch updating lookups: %', p_job_id, v_sql;
    EXECUTE v_sql;

    IF p_step_code = 'physical_location' THEN
        v_sql := format($$
            UPDATE public.%I dt SET
                typed_physical_latitude = admin.safe_cast_to_numeric(dt.physical_latitude),
                typed_physical_longitude = admin.safe_cast_to_numeric(dt.physical_longitude),
                typed_physical_altitude = admin.safe_cast_to_numeric(dt.physical_altitude)
            WHERE dt.row_id = ANY(%L);
        $$, v_data_table_name, p_batch_row_ids);
    ELSIF p_step_code = 'postal_location' THEN
        v_sql := format($$
            UPDATE public.%I dt SET
                typed_postal_latitude = admin.safe_cast_to_numeric(dt.postal_latitude),
                typed_postal_longitude = admin.safe_cast_to_numeric(dt.postal_longitude),
                typed_postal_altitude = admin.safe_cast_to_numeric(dt.postal_altitude)
            WHERE dt.row_id = ANY(%L);
        $$, v_data_table_name, p_batch_row_ids);
    ELSE
        RAISE EXCEPTION '[Job %] analyse_location: Invalid step_code % for coordinate update.', p_job_id, p_step_code;
    END IF;
    RAISE DEBUG '[Job %] analyse_location: Batch updating typed coordinates for %: %', p_job_id, p_step_code, v_sql;
    EXECUTE v_sql;

    CREATE TEMP TABLE temp_batch_errors (row_id BIGINT PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_batch_errors (row_id, error_jsonb)
        SELECT
            row_id,
            jsonb_strip_nulls(
                jsonb_build_object('physical_region_code', CASE WHEN physical_region_code IS NOT NULL AND physical_region_id IS NULL THEN 'Not found' ELSE NULL END) ||
                jsonb_build_object('physical_country_iso_2', CASE WHEN physical_country_iso_2 IS NOT NULL AND physical_country_id IS NULL THEN 'Not found' ELSE NULL END) ||
                jsonb_build_object('physical_latitude', CASE WHEN physical_latitude IS NOT NULL AND typed_physical_latitude IS NULL THEN 'Invalid format' ELSE NULL END) ||
                jsonb_build_object('physical_longitude', CASE WHEN physical_longitude IS NOT NULL AND typed_physical_longitude IS NULL THEN 'Invalid format' ELSE NULL END) ||
                jsonb_build_object('physical_altitude', CASE WHEN physical_altitude IS NOT NULL AND typed_physical_altitude IS NULL THEN 'Invalid format' ELSE NULL END) ||
                jsonb_build_object('postal_region_code', CASE WHEN postal_region_code IS NOT NULL AND postal_region_id IS NULL THEN 'Not found' ELSE NULL END) ||
                jsonb_build_object('postal_country_iso_2', CASE WHEN postal_country_iso_2 IS NOT NULL AND postal_country_id IS NULL THEN 'Not found' ELSE NULL END) ||
                jsonb_build_object('postal_latitude', CASE WHEN postal_latitude IS NOT NULL AND typed_postal_latitude IS NULL THEN 'Invalid format' ELSE NULL END) ||
                jsonb_build_object('postal_longitude', CASE WHEN postal_longitude IS NOT NULL AND typed_postal_longitude IS NULL THEN 'Invalid format' ELSE NULL END) ||
                jsonb_build_object('postal_altitude', CASE WHEN postal_altitude IS NOT NULL AND typed_postal_altitude IS NULL THEN 'Invalid format' ELSE NULL END)
            ) AS error_jsonb
        FROM public.%I
        WHERE row_id = ANY(%L)
     $$, v_data_table_name, p_batch_row_ids);
     RAISE DEBUG '[Job %] analyse_location: Identifying errors post-batch: %', p_job_id, v_sql;
     EXECUTE v_sql;

    v_sql := format($$
        UPDATE public.%I dt SET
            state = %L,
            error = COALESCE(dt.error, %L) || err.error_jsonb,
            last_completed_priority = %L
        FROM temp_batch_errors err
        WHERE dt.row_id = err.row_id AND err.error_jsonb != %L;
    $$, v_data_table_name, 'error', '{}'::jsonb, v_step.priority - 1, '{}'::jsonb);
    RAISE DEBUG '[Job %] analyse_location: Updating error rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    v_error_count := v_update_count;
    SELECT array_agg(row_id) INTO v_error_row_ids FROM temp_batch_errors WHERE error_jsonb != '{}'::jsonb;
    RAISE DEBUG '[Job %] analyse_location: Marked % rows as error.', p_job_id, v_update_count;

    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = CASE WHEN (dt.error - 'physical_region_code' - 'physical_country_iso_2' - 'physical_latitude' - 'physical_longitude' - 'physical_altitude' - 'postal_region_code' - 'postal_country_iso_2' - 'postal_latitude' - 'postal_longitude' - 'postal_altitude') = '{}'::jsonb THEN NULL ELSE (dt.error - 'physical_region_code' - 'physical_country_iso_2' - 'physical_latitude' - 'physical_longitude' - 'physical_altitude' - 'postal_region_code' - 'postal_country_iso_2' - 'postal_latitude' - 'postal_longitude' - 'postal_altitude') END,
            state = %L
        WHERE dt.row_id = ANY(%L) AND dt.row_id != ALL(%L);
    $$, v_data_table_name, v_step.priority, 'analysing', p_batch_row_ids, COALESCE(v_error_row_ids, ARRAY[]::BIGINT[]));
    RAISE DEBUG '[Job %] analyse_location: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_location: Marked % rows as success for this target.', p_job_id, v_update_count;

    DROP TABLE IF EXISTS temp_batch_errors;

    RAISE DEBUG '[Job %] analyse_location (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_location$;


-- Procedure to operate (insert/update/upsert) location data (handles both physical and postal) (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.process_location(p_job_id INT, p_batch_row_ids BIGINT[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_location$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
    v_strategy public.import_strategy;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    statbus_constraints_already_deferred BOOLEAN;
    error_message TEXT;
    v_location_type public.location_type;
    v_has_lu_id_col BOOLEAN := FALSE;
    v_has_est_id_col BOOLEAN := FALSE;
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
    v_batch_upsert_result RECORD;
    v_batch_upsert_error_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_batch_upsert_success_row_ids BIGINT[] := ARRAY[]::BIGINT[];
    v_final_id_col TEXT;
BEGIN
    RAISE DEBUG '[Job %] process_location (Batch) for step_code %: Starting operation for % rows', p_job_id, p_step_code, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_definition := v_job.definition_snapshot->'import_definition';

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    SELECT * INTO v_step FROM public.import_step WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] process_location: Step with code % not found.', p_job_id, p_step_code;
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
    v_strategy := (v_definition->>'strategy')::public.import_strategy;

    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = v_data_table_name AND column_name = 'legal_unit_id') INTO v_has_lu_id_col;
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = v_data_table_name AND column_name = 'establishment_id') INTO v_has_est_id_col;

    v_select_lu_id_expr := CASE WHEN v_has_lu_id_col THEN 'legal_unit_id' ELSE 'NULL::INTEGER' END;
    v_select_est_id_expr := CASE WHEN v_has_est_id_col THEN 'establishment_id' ELSE 'NULL::INTEGER' END;

    CREATE TEMP TABLE temp_batch_data (
        row_id BIGINT PRIMARY KEY,
        legal_unit_id INT,
        establishment_id INT,
        valid_from DATE,
        valid_to DATE,
        data_source_id INT,
        edit_by_user_id INT,
        edit_at TIMESTAMPTZ,
        address_part1 TEXT, address_part2 TEXT, address_part3 TEXT,
        postcode TEXT, postplace TEXT, region_id INT, country_id INT,
        latitude NUMERIC, longitude NUMERIC, altitude NUMERIC,
        existing_loc_id INT
    ) ON COMMIT DROP;

    v_sql := format($$
        INSERT INTO temp_batch_data (
            row_id, legal_unit_id, establishment_id, valid_from, valid_to, data_source_id,
            edit_by_user_id, edit_at,
            address_part1, address_part2, address_part3, postcode, postplace,
            region_id, country_id, latitude, longitude, altitude
        )
        SELECT
            row_id, %s, %s,
            derived_valid_from,
            derived_valid_to,
            data_source_id,
            edit_by_user_id, edit_at,
            %I, %I, %I, %I, %I,
            %I, %I,
            %I, %I, %I
         FROM public.%I WHERE row_id = ANY(%L);
    $$,
        v_select_lu_id_expr,
        v_select_est_id_expr,
        CASE v_location_type WHEN 'physical' THEN 'physical_address_part1' ELSE 'postal_address_part1' END,
        CASE v_location_type WHEN 'physical' THEN 'physical_address_part2' ELSE 'postal_address_part2' END,
        CASE v_location_type WHEN 'physical' THEN 'physical_address_part3' ELSE 'postal_address_part3' END,
        CASE v_location_type WHEN 'physical' THEN 'physical_postcode' ELSE 'postal_postcode' END,
        CASE v_location_type WHEN 'physical' THEN 'physical_postplace' ELSE 'postal_postplace' END,
        CASE v_location_type WHEN 'physical' THEN 'physical_region_id' ELSE 'postal_region_id' END,
        CASE v_location_type WHEN 'physical' THEN 'physical_country_id' ELSE 'postal_country_id' END,
        CASE v_location_type WHEN 'physical' THEN 'typed_physical_latitude' ELSE 'typed_postal_latitude' END,
        CASE v_location_type WHEN 'physical' THEN 'typed_physical_longitude' ELSE 'typed_postal_longitude' END,
        CASE v_location_type WHEN 'physical' THEN 'typed_physical_altitude' ELSE 'typed_postal_altitude' END,
        v_data_table_name, p_batch_row_ids);
    RAISE DEBUG '[Job %] process_location: Fetching batch data for type %: %', p_job_id, v_location_type, v_sql;
    EXECUTE v_sql;

    v_sql := format($$
        UPDATE temp_batch_data tbd SET
            existing_loc_id = loc.id
        FROM public.location loc
        WHERE loc.type = %L
          AND loc.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
          AND loc.establishment_id IS NOT DISTINCT FROM tbd.establishment_id;
    $$, v_location_type);
    RAISE DEBUG '[Job %] process_location: Determining existing IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    BEGIN
        -- Create temp source table for batch upsert
        CREATE TEMP TABLE temp_loc_upsert_source (
            row_id BIGINT PRIMARY KEY, -- Link back to original _data row
            id INT, -- Target location ID
            valid_from DATE NOT NULL,
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

        -- Populate temp source table
        INSERT INTO temp_loc_upsert_source (
            row_id, id, valid_from, valid_to, legal_unit_id, establishment_id, type,
            address_part1, address_part2, address_part3, postcode, postplace, region_id, country_id,
            latitude, longitude, altitude, data_source_id, edit_by_user_id, edit_at, edit_comment
        )
        SELECT
            tbd.row_id,
            tbd.existing_loc_id,
            tbd.valid_from,
            tbd.valid_to,
            tbd.legal_unit_id,
            tbd.establishment_id,
            v_location_type,
            tbd.address_part1, tbd.address_part2, tbd.address_part3, tbd.postcode, tbd.postplace,
            tbd.region_id, tbd.country_id, tbd.latitude, tbd.longitude, tbd.altitude,
            tbd.data_source_id, tbd.edit_by_user_id, tbd.edit_at,
            'Import Job Batch Update/Upsert'
        FROM temp_batch_data tbd
        WHERE
            (tbd.region_id IS NOT NULL OR tbd.country_id IS NOT NULL OR tbd.address_part1 IS NOT NULL) -- Only process rows with actual location data
            AND
            CASE v_strategy
                WHEN 'insert_only' THEN tbd.existing_loc_id IS NULL
                WHEN 'update_only' THEN tbd.existing_loc_id IS NOT NULL
                WHEN 'upsert' THEN TRUE
            END;

        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] process_location: Populated temp_loc_upsert_source with % rows for batch upsert (type: %).', p_job_id, v_update_count, v_location_type;

        IF v_update_count > 0 THEN
            -- Call batch upsert function
            RAISE DEBUG '[Job %] process_location: Calling batch_upsert_generic_valid_time_table for location (type: %).', p_job_id, v_location_type;
            FOR v_batch_upsert_result IN
                SELECT * FROM admin.batch_upsert_generic_valid_time_table(
                    p_target_schema_name => 'public',
                    p_target_table_name => 'location',
                    p_source_schema_name => 'pg_temp',
                    p_source_table_name => 'temp_loc_upsert_source',
                    p_source_row_id_column_name => 'row_id',
                    p_unique_columns => '[]'::jsonb, -- ID is provided directly
                    p_temporal_columns => ARRAY['valid_from', 'valid_to'],
                    p_ephemeral_columns => ARRAY['edit_comment', 'edit_by_user_id', 'edit_at'],
                    p_id_column_name => 'id'
                )
            LOOP
                IF v_batch_upsert_result.status = 'ERROR' THEN
                    v_batch_upsert_error_row_ids := array_append(v_batch_upsert_error_row_ids, v_batch_upsert_result.source_row_id);
                    EXECUTE format($$
                        UPDATE public.%I SET
                            state = %L,
                            error = COALESCE(error, '{}'::jsonb) || jsonb_build_object('batch_upsert_location_error', %L),
                            last_completed_priority = %L
                        WHERE row_id = %L;
                    $$, v_data_table_name, 'error'::public.import_data_state, v_batch_upsert_result.error_message, v_step.priority - 1, v_batch_upsert_result.source_row_id);
                ELSE
                    v_batch_upsert_success_row_ids := array_append(v_batch_upsert_success_row_ids, v_batch_upsert_result.source_row_id);
                END IF;
            END LOOP;

            v_error_count := array_length(v_batch_upsert_error_row_ids, 1);
            RAISE DEBUG '[Job %] process_location: Batch upsert finished for type %. Success: %, Errors: %', p_job_id, v_location_type, array_length(v_batch_upsert_success_row_ids, 1), v_error_count;

            -- Update _data table for successful rows
            IF array_length(v_batch_upsert_success_row_ids, 1) > 0 THEN
                v_sql := format($$
                    UPDATE public.%I dt SET
                        %I = tbd.existing_loc_id, -- Set the correct pk_id column
                        last_completed_priority = %L,
                        error = NULL,
                        state = %L
                    FROM temp_batch_data tbd
                    WHERE dt.row_id = tbd.row_id
                      AND dt.row_id = ANY(%L);
                $$, v_data_table_name, v_final_id_col, v_step.priority, 'processing'::public.import_data_state, v_batch_upsert_success_row_ids);
                RAISE DEBUG '[Job %] process_location: Updating _data table for successful rows (type: %): %', p_job_id, v_location_type, v_sql;
                EXECUTE v_sql;
            END IF;
        END IF; -- End if v_update_count > 0

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_location: Error during batch operation for type %: %', p_job_id, v_location_type, error_message;
        v_sql := format($$UPDATE public.%I SET state = %L, error = COALESCE(error, '{}'::jsonb) || %L, last_completed_priority = %L WHERE row_id = ANY(%L)$$,
                       v_data_table_name, 'error'::public.import_data_state, jsonb_build_object('batch_error_process_location', error_message), v_step.priority - 1, p_batch_row_ids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        UPDATE public.import_job SET error = jsonb_build_object('process_location_error', format('Error for type %s: %s', v_location_type, error_message)) WHERE id = p_job_id;
    END;

    -- Update priority for rows that didn't have location data
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L
        WHERE dt.row_id = ANY(%L) AND dt.state != %L
          AND NOT EXISTS (SELECT 1 FROM temp_batch_data tbd WHERE tbd.row_id = dt.row_id);
    $$, v_data_table_name, v_step.priority, p_batch_row_ids, 'error');
    EXECUTE v_sql;

    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_location (Batch): Finished operation for batch type %. Initial batch size: %. Errors (estimated): %', p_job_id, v_location_type, array_length(p_batch_row_ids, 1), v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
    DROP TABLE IF EXISTS temp_loc_upsert_source;
END;
$process_location$;

-- Helper function for safe numeric casting (example)
CREATE OR REPLACE FUNCTION admin.safe_cast_to_numeric(p_text_numeric TEXT)
RETURNS NUMERIC LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_text_numeric IS NULL OR p_text_numeric = '' THEN
        RETURN NULL;
    END IF;
    RETURN p_text_numeric::NUMERIC;
EXCEPTION WHEN others THEN
    RAISE WARNING 'Invalid numeric format: "%". Returning NULL.', p_text_numeric;
    RETURN NULL;
END;
$$;


COMMIT;
