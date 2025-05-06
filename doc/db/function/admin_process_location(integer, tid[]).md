```sql
CREATE OR REPLACE PROCEDURE admin.process_location(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$
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
    v_current_target_priority INT;
    v_location_type public.location_type;
BEGIN
    RAISE DEBUG '[Job %] process_location (Batch): Starting operation for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately
    v_definition := v_job.definition_snapshot->'import_definition'; -- Read from snapshot column

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid import_definition object from definition_snapshot', p_job_id;
    END IF;

    -- Determine which target step (Physical or Postal) is likely being processed
    EXECUTE format('SELECT MIN(last_completed_priority) FROM public.%I WHERE ctid = ANY(%L)',
                   v_data_table_name, p_batch_ctids)
    INTO v_current_target_priority;

    SELECT * INTO v_step
    FROM public.import_step
    WHERE priority > v_current_target_priority AND name IN ('physical_location', 'postal_location')
    ORDER BY priority
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE WARNING '[Job %] process_location: Could not determine current location target based on priority %. Skipping.', p_job_id, v_current_target_priority;
        RETURN;
    END IF;

    RAISE DEBUG '[Job %] process_location: Determined target as % (priority %)', p_job_id, v_step.name, v_step.priority;
    v_location_type := CASE v_step.name WHEN 'physical_location' THEN 'physical' WHEN 'postal_location' THEN 'postal' END;

    -- Determine operation type
    v_strategy := (v_definition->>'strategy')::public.import_strategy;
    -- v_edit_by_user_id is now fetched per row

    -- Check if constraints are already deferred
    SELECT COALESCE(NULLIF(current_setting('statbus.constraints_already_deferred', true),'')::boolean,false) INTO statbus_constraints_already_deferred;
    IF NOT statbus_constraints_already_deferred THEN
        SET CONSTRAINTS ALL DEFERRED;
    END IF;

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

    -- Select columns based on the determined location type, including audit columns
    v_sql := format('
        INSERT INTO temp_batch_data (
            data_ctid, legal_unit_id, establishment_id, valid_from, valid_to, data_source_id,
            edit_by_user_id, edit_at, -- Added
            address_part1, address_part2, address_part3, postcode, postplace,
            region_id, country_id, latitude, longitude, altitude
        )
        SELECT
            ctid, legal_unit_id, establishment_id,
            COALESCE(typed_valid_from, computed_valid_from),
            COALESCE(typed_valid_to, computed_valid_to),
            data_source_id,
            edit_by_user_id, edit_at, -- Added
            %I, %I, %I, %I, %I, -- Address parts, postcode, postplace
            %I, %I, -- region_id, country_id
            %I, %I, %I -- latitude, longitude, altitude
         FROM public.%I WHERE ctid = ANY(%L);
    ',
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
    v_sql := format('
        UPDATE temp_batch_data tbd SET
            existing_loc_id = loc.id
        FROM public.location loc
        WHERE loc.type = %L
          AND loc.legal_unit_id IS NOT DISTINCT FROM tbd.legal_unit_id
          AND loc.establishment_id IS NOT DISTINCT FROM tbd.establishment_id;
          -- Note: This simple matching might link multiple source rows to the same existing location.
          -- More complex matching based on address might be needed if a unit can have multiple locations of the same type.
    ', v_location_type);
    RAISE DEBUG '[Job %] process_location: Determining existing IDs: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Perform Batch INSERT into location_era (Leveraging Trigger)
    BEGIN
        v_sql := format('
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
                    WHEN ''insert_only'' THEN tbd.existing_loc_id IS NULL
                    WHEN ''update_only'' THEN tbd.existing_loc_id IS NOT NULL
                    WHEN ''upsert'' THEN TRUE
                END;
        ', v_location_type, v_strategy); -- Removed v_edit_by_user_id, v_timestamp from format args

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
           v_step.priority, 'importing', 'error', v_strategy);
        RAISE DEBUG '[Job %] process_location: Updating _data table with final IDs: %', p_job_id, v_sql;
        EXECUTE v_sql;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_location: Error during batch operation for type %: %', p_job_id, v_location_type, error_message;
        -- Mark the entire batch as error in _data table
        v_sql := format('UPDATE public.%I SET state = %L, error = %L, last_completed_priority = %L WHERE ctid = ANY(%L)',
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
END;
$procedure$
```
