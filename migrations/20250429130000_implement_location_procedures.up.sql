-- Migration: implement_location_procedures
-- Implements the analyse and operation procedures for the PhysicalLocation
-- and PostalLocation import targets using generic location handlers.

BEGIN;

-- Procedure to analyse location data (handles both physical and postal) (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.analyse_location(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_location$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_error_ctids TID[] := ARRAY[]::TID[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
    -- v_current_target_priority INT; -- Removed
BEGIN
    RAISE DEBUG '[Job %] analyse_location (Batch) for step_code %: Starting analysis for % rows', p_job_id, p_step_code, array_length(p_batch_ctids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately

    -- Get the specific step details using p_step_code
    SELECT * INTO v_step FROM public.import_step WHERE code = p_step_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_location: Step with code % not found. This should not happen if called by import_job_process_phase.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] analyse_location: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;

    -- Step 1: Batch Update Lookups (Region and Country)
    v_sql := format($$
        UPDATE public.%I dt SET
            physical_region_id = src.physical_region_id,
            physical_country_id = src.physical_country_id,
            postal_region_id = src.postal_region_id,
            postal_country_id = src.postal_country_id
        FROM (
            SELECT
                dt_sub.ctid AS ctid_for_join,
                pr.id as physical_region_id,
                pc.id as physical_country_id,
                psr.id as postal_region_id,
                psc.id as postal_country_id
            FROM public.%I dt_sub
            LEFT JOIN public.region pr ON dt_sub.physical_region_code IS NOT NULL AND pr.code = dt_sub.physical_region_code
            LEFT JOIN public.country pc ON dt_sub.physical_country_iso_2 IS NOT NULL AND pc.iso_2 = dt_sub.physical_country_iso_2 -- Changed to iso_2
            LEFT JOIN public.region psr ON dt_sub.postal_region_code IS NOT NULL AND psr.code = dt_sub.postal_region_code
            LEFT JOIN public.country psc ON dt_sub.postal_country_iso_2 IS NOT NULL AND psc.iso_2 = dt_sub.postal_country_iso_2 -- Changed to iso_2
            WHERE dt_sub.ctid = ANY(%L) -- Filter for the batch
        ) AS src
        WHERE dt.ctid = src.ctid_for_join;
    $$, v_data_table_name, v_data_table_name, p_batch_ctids);
    RAISE DEBUG '[Job %] analyse_location: Batch updating lookups: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Batch Update Typed Coordinates
    IF p_step_code = 'physical_location' THEN
        v_sql := format($$
            UPDATE public.%I dt SET
                typed_physical_latitude = admin.safe_cast_to_numeric(dt.physical_latitude),
                typed_physical_longitude = admin.safe_cast_to_numeric(dt.physical_longitude),
                typed_physical_altitude = admin.safe_cast_to_numeric(dt.physical_altitude)
            WHERE dt.ctid = ANY(%L);
        $$, v_data_table_name, p_batch_ctids);
    ELSIF p_step_code = 'postal_location' THEN
        v_sql := format($$
            UPDATE public.%I dt SET
                typed_postal_latitude = admin.safe_cast_to_numeric(dt.postal_latitude),
                typed_postal_longitude = admin.safe_cast_to_numeric(dt.postal_longitude),
                typed_postal_altitude = admin.safe_cast_to_numeric(dt.postal_altitude)
            WHERE dt.ctid = ANY(%L);
        $$, v_data_table_name, p_batch_ctids);
    ELSE
        -- Should not happen if p_step_code is validated earlier
        RAISE EXCEPTION '[Job %] analyse_location: Invalid step_code % for coordinate update.', p_job_id, p_step_code;
    END IF;
    RAISE DEBUG '[Job %] analyse_location: Batch updating typed coordinates for %: %', p_job_id, p_step_code, v_sql;
    EXECUTE v_sql;

    -- Step 3: Identify and Aggregate Errors Post-Batch
    CREATE TEMP TABLE temp_batch_errors (data_ctid TID PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;
    v_sql := format($$
        INSERT INTO temp_batch_errors (data_ctid, error_jsonb)
        SELECT
            ctid,
            jsonb_strip_nulls(
                jsonb_build_object('physical_region_code', CASE WHEN physical_region_code IS NOT NULL AND physical_region_id IS NULL THEN 'Not found' ELSE NULL END) ||
                jsonb_build_object('physical_country_iso_2', CASE WHEN physical_country_iso_2 IS NOT NULL AND physical_country_id IS NULL THEN 'Not found' ELSE NULL END) || -- Keep source column name for error key
                jsonb_build_object('physical_latitude', CASE WHEN physical_latitude IS NOT NULL AND typed_physical_latitude IS NULL THEN 'Invalid format' ELSE NULL END) ||
                jsonb_build_object('physical_longitude', CASE WHEN physical_longitude IS NOT NULL AND typed_physical_longitude IS NULL THEN 'Invalid format' ELSE NULL END) ||
                jsonb_build_object('physical_altitude', CASE WHEN physical_altitude IS NOT NULL AND typed_physical_altitude IS NULL THEN 'Invalid format' ELSE NULL END) ||
                jsonb_build_object('postal_region_code', CASE WHEN postal_region_code IS NOT NULL AND postal_region_id IS NULL THEN 'Not found' ELSE NULL END) ||
                jsonb_build_object('postal_country_iso_2', CASE WHEN postal_country_iso_2 IS NOT NULL AND postal_country_id IS NULL THEN 'Not found' ELSE NULL END) || -- Keep source column name for error key
                jsonb_build_object('postal_latitude', CASE WHEN postal_latitude IS NOT NULL AND typed_postal_latitude IS NULL THEN 'Invalid format' ELSE NULL END) ||
                jsonb_build_object('postal_longitude', CASE WHEN postal_longitude IS NOT NULL AND typed_postal_longitude IS NULL THEN 'Invalid format' ELSE NULL END) ||
                jsonb_build_object('postal_altitude', CASE WHEN postal_altitude IS NOT NULL AND typed_postal_altitude IS NULL THEN 'Invalid format' ELSE NULL END)
            ) AS error_jsonb
        FROM public.%I
        WHERE ctid = ANY(%L)
     $$, v_data_table_name, p_batch_ctids);
     RAISE DEBUG '[Job %] analyse_location: Identifying errors post-batch: %', p_job_id, v_sql;
     EXECUTE v_sql;

    -- Step 4: Batch Update Error Rows
    v_sql := format($$
        UPDATE public.%I dt SET
            state = %L,
            error = COALESCE(dt.error, %L) || err.error_jsonb,
            last_completed_priority = %L
        FROM temp_batch_errors err
        WHERE dt.ctid = err.data_ctid AND err.error_jsonb != %L;
    $$, v_data_table_name, 'error', '{}'::jsonb, v_step.priority - 1, '{}'::jsonb);
    RAISE DEBUG '[Job %] analyse_location: Updating error rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    v_error_count := v_update_count;
    SELECT array_agg(data_ctid) INTO v_error_ctids FROM temp_batch_errors WHERE error_jsonb != '{}'::jsonb;
    RAISE DEBUG '[Job %] analyse_location: Marked % rows as error.', p_job_id, v_update_count;

    -- Step 5: Batch Update Success Rows
    v_sql := format($$
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = CASE WHEN (dt.error - 'physical_region_code' - 'physical_country_iso_2' - 'physical_latitude' - 'physical_longitude' - 'physical_altitude' - 'postal_region_code' - 'postal_country_iso_2' - 'postal_latitude' - 'postal_longitude' - 'postal_altitude') = '{}'::jsonb THEN NULL ELSE (dt.error - 'physical_region_code' - 'physical_country_iso_2' - 'physical_latitude' - 'physical_longitude' - 'physical_altitude' - 'postal_region_code' - 'postal_country_iso_2' - 'postal_latitude' - 'postal_longitude' - 'postal_altitude') END, -- Clear only this step''s error keys
            state = %L
        WHERE dt.ctid = ANY(%L) AND dt.ctid != ALL(%L); -- Update only non-error rows from the original batch
    $$, v_data_table_name, v_step.priority, 'analysing', p_batch_ctids, COALESCE(v_error_ctids, ARRAY[]::TID[]));
    RAISE DEBUG '[Job %] analyse_location: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_location: Marked % rows as success for this target.', p_job_id, v_update_count;

    DROP TABLE IF EXISTS temp_batch_errors;

    RAISE DEBUG '[Job %] analyse_location (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$analyse_location$;


-- Procedure to operate (insert/update/upsert) location data (handles both physical and postal) (Batch Oriented)
CREATE OR REPLACE PROCEDURE admin.process_location(p_job_id INT, p_batch_ctids TID[], p_step_code TEXT)
LANGUAGE plpgsql AS $process_location$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
    v_strategy public.import_strategy;
    -- v_edit_by_user_id INT; -- Now read from _data table
    -- v_timestamp TIMESTAMPTZ := clock_timestamp(); -- Now read from _data table
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    statbus_constraints_already_deferred BOOLEAN;
    error_message TEXT;
    -- v_current_target_priority INT; -- Removed
    v_location_type public.location_type;
    v_has_lu_id_col BOOLEAN := FALSE;
    v_has_est_id_col BOOLEAN := FALSE;
    v_select_lu_id_expr TEXT;
    v_select_est_id_expr TEXT;
BEGIN
    RAISE DEBUG '[Job %] process_location (Batch) for step_code %: Starting operation for % rows', p_job_id, p_step_code, array_length(p_batch_ctids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    v_definition := v_job.definition_snapshot->'import_definition'; -- Read from snapshot column

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    -- Get the specific step details using p_step_code
    SELECT * INTO v_step FROM public.import_step WHERE code = p_step_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] process_location: Step with code % not found. This should not happen if called by import_job_process_phase.', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] process_location: Processing for target % (code: %, priority %)', p_job_id, v_step.name, v_step.code, v_step.priority;
    v_location_type := CASE v_step.code -- Use v_step.code
        WHEN 'physical_location' THEN 'physical'::public.location_type
        WHEN 'postal_location' THEN 'postal'::public.location_type
        ELSE NULL -- Should not happen if p_step_code is valid
    END;

    IF v_location_type IS NULL THEN
        RAISE EXCEPTION '[Job %] process_location: Invalid step_code % provided for location processing.', p_job_id, p_step_code;
    END IF;

    -- Determine operation type
    v_strategy := (v_definition->>'strategy')::public.import_strategy;
    -- v_edit_by_user_id is now fetched per row

    -- Check if constraints are already deferred
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

    -- Check which unit ID columns exist in the source _data table
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = v_data_table_name AND column_name = 'legal_unit_id') INTO v_has_lu_id_col;
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = v_data_table_name AND column_name = 'establishment_id') INTO v_has_est_id_col;

    -- Build dynamic SELECT expressions for unit IDs
    v_select_lu_id_expr := CASE WHEN v_has_lu_id_col THEN 'legal_unit_id' ELSE 'NULL::INTEGER' END;
    v_select_est_id_expr := CASE WHEN v_has_est_id_col THEN 'establishment_id' ELSE 'NULL::INTEGER' END;

    -- Step 1: Fetch batch data into a temporary table
    CREATE TEMP TABLE temp_batch_data (
        data_ctid TID PRIMARY KEY,
        legal_unit_id INT,
        establishment_id INT,
        valid_from DATE,
        valid_to DATE,
        data_source_id INT,
        edit_by_user_id INT, -- Added
        edit_at TIMESTAMPTZ, -- Added
        address_part1 TEXT, address_part2 TEXT, address_part3 TEXT,
        postcode TEXT, postplace TEXT, region_id INT, country_id INT,
        latitude NUMERIC, longitude NUMERIC, altitude NUMERIC,
        existing_loc_id INT
    ) ON COMMIT DROP;

    -- Select columns based on the determined location type, including audit columns and dynamic unit IDs
    v_sql := format($$
        INSERT INTO temp_batch_data (
            data_ctid, legal_unit_id, establishment_id, valid_from, valid_to, data_source_id,
            edit_by_user_id, edit_at, -- Added
            address_part1, address_part2, address_part3, postcode, postplace,
            region_id, country_id, latitude, longitude, altitude
        )
        SELECT
            ctid, %s, %s, -- Dynamic unit ID selection
            derived_valid_from, -- Changed to derived_valid_from
            derived_valid_to,   -- Changed to derived_valid_to
            data_source_id,
            edit_by_user_id, edit_at, -- Added
            %I, %I, %I, %I, %I, -- Address parts, postcode, postplace
            %I, %I, -- region_id, country_id
            %I, %I, %I -- latitude, longitude, altitude
         FROM public.%I WHERE ctid = ANY(%L);
    $$,
        v_select_lu_id_expr, -- Use dynamic expression
        v_select_est_id_expr, -- Use dynamic expression
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
        v_data_table_name, p_batch_ctids);
    RAISE DEBUG '[Job %] process_location: Fetching batch data for type %: %', p_job_id, v_location_type, v_sql;
    EXECUTE v_sql;

    -- Step 2: Determine existing location IDs
    v_sql := format($$
        UPDATE temp_batch_data tbd SET
            existing_loc_id = loc.id
        FROM public.location loc
        WHERE loc.type = %L
          AND loc.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
          AND loc.establishment_id IS NOT DISTINCT FROM tbd.establishment_id;
          -- Note: This simple matching might link multiple source rows to the same existing location.
          -- More complex matching based on address might be needed if a unit can have multiple locations of the same type.
    $$, v_location_type);
    RAISE DEBUG '[Job %] process_location: Determining existing IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Perform Batch INSERT into location_era (Leveraging Trigger)
    BEGIN
        v_sql := format($$
            INSERT INTO public.location_era (
                id, legal_unit_id, establishment_id, type, valid_from, valid_to, address_part1, address_part2, address_part3,
                postcode, postplace, region_id, country_id, latitude, longitude, altitude,
                data_source_id, edit_by_user_id, edit_at
            )
            SELECT
                tbd.existing_loc_id, tbd.legal_unit_id, tbd.establishment_id, %L, tbd.valid_from, tbd.valid_to,
                tbd.address_part1, tbd.address_part2, tbd.address_part3, tbd.postcode, tbd.postplace,
                tbd.region_id, tbd.country_id, tbd.latitude, tbd.longitude, tbd.altitude,
                tbd.data_source_id, tbd.edit_by_user_id, tbd.edit_at -- Use values from temp table
            FROM temp_batch_data tbd
            WHERE
                -- Filter based on operation type and if data exists for this location type
                (tbd.region_id IS NOT NULL OR tbd.country_id IS NOT NULL OR tbd.address_part1 IS NOT NULL)
                AND
                CASE %L::public.import_strategy
                    WHEN 'insert_only' THEN tbd.existing_loc_id IS NULL
                    WHEN 'update_only' THEN tbd.existing_loc_id IS NOT NULL
                    WHEN 'upsert' THEN TRUE
                END;
        $$, v_location_type, v_strategy);

        RAISE DEBUG '[Job %] process_location: Performing batch INSERT into location_era: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT; -- Count of rows INSERTED into _era

        -- Step 3b: Update _data table with resulting location_id (Post-INSERT)
        v_sql := format('
            WITH loc_lookup AS (
                 SELECT DISTINCT ON (legal_unit_id, establishment_id) -- Assuming one location of a type per unit
                        id as location_id, legal_unit_id, establishment_id
                 FROM public.location
                 WHERE type = %L
                 ORDER BY legal_unit_id, establishment_id, id DESC -- Get latest ID if multiple somehow exist
            )
            UPDATE public.%I dt SET
                %I = loc.location_id, -- Set physical_location_id or postal_location_id
                last_completed_priority = %L,
                error = NULL,
                state = %L
            FROM temp_batch_data tbd
            JOIN loc_lookup loc ON loc.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
                               AND loc.establishment_id IS NOT DISTINCT FROM tbd.establishment_id
            WHERE dt.ctid = tbd.data_ctid
              AND dt.state != %L
              AND (tbd.region_id IS NOT NULL OR tbd.country_id IS NOT NULL OR tbd.address_part1 IS NOT NULL) -- Only update if location data existed
              AND CASE %L::public.import_strategy
                    WHEN ''insert_only'' THEN tbd.existing_loc_id IS NULL
                    WHEN ''update_only'' THEN tbd.existing_loc_id IS NOT NULL
                    WHEN ''upsert'' THEN TRUE
                  END;
        ', v_location_type, v_data_table_name,
           CASE v_location_type WHEN 'physical' THEN 'physical_location_id' ELSE 'postal_location_id' END,
           v_step.priority, 'processing', 'error', v_strategy); -- Changed 'importing' to 'processing'
        RAISE DEBUG '[Job %] process_location: Updating _data table with final IDs: %', p_job_id, v_sql;
        EXECUTE v_sql;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_location: Error during batch operation for type %: %', p_job_id, v_location_type, error_message;
        -- Mark the entire batch as error in _data table
        v_sql := format($$UPDATE public.%I SET state = %L, error = %L, last_completed_priority = %L WHERE ctid = ANY(%L)$$,
                       v_data_table_name, 'error', jsonb_build_object('batch_error', error_message), v_step.priority - 1, p_batch_ctids);
        EXECUTE v_sql;
        GET DIAGNOSTICS v_error_count = ROW_COUNT;
        -- Update job error
        UPDATE public.import_job SET error = jsonb_build_object('process_location_error', format('Error for type %s: %s', v_location_type, error_message)) WHERE id = p_job_id;
    END;

    -- Reset constraints if they were deferred by this function
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL IMMEDIATE;
    END IF;

    RAISE DEBUG '[Job %] process_location (Batch): Finished operation for batch type %. Initial batch size: %. Errors (estimated): %', p_job_id, v_location_type, array_length(p_batch_ctids, 1), v_error_count;

    DROP TABLE IF EXISTS temp_batch_data;
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
