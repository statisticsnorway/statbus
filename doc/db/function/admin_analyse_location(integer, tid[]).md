```sql
CREATE OR REPLACE PROCEDURE admin.analyse_location(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step RECORD;
    v_data_table_name TEXT;
    v_error_ctids TID[] := ARRAY[]::TID[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
    v_current_target_priority INT;
BEGIN
    RAISE DEBUG '[Job %] analyse_location (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details
    SELECT * INTO v_job FROM public.import_job ij WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name; -- Assign separately

    -- Determine which target (Physical or Postal) is likely being processed
    EXECUTE format('SELECT MIN(last_completed_priority) FROM public.%I WHERE ctid = ANY(%L)',
                   v_data_table_name, p_batch_ctids)
    INTO v_current_target_priority;

    SELECT * INTO v_step
    FROM public.import_step
    WHERE priority > v_current_target_priority AND name IN ('physical_location', 'postal_location')
    ORDER BY priority
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE WARNING '[Job %] analyse_location: Could not determine current location target based on priority %. Skipping.', p_job_id, v_current_target_priority;
        RETURN;
    END IF;

    RAISE DEBUG '[Job %] analyse_location: Determined target as % (priority %)', p_job_id, v_step.name, v_step.priority;

    -- Step 1: Batch Update Lookups (Region and Country)
    v_sql := format('
        UPDATE public.%I dt SET
            physical_region_id = pr.id,
            physical_country_id = pc.id,
            postal_region_id = psr.id,
            postal_country_id = psc.id
        FROM unnest(%L::TID[]) AS batch(data_ctid)
        LEFT JOIN public.region pr ON dt.physical_region_code IS NOT NULL AND pr.code = dt.physical_region_code
        LEFT JOIN public.country pc ON dt.physical_country_iso_2 IS NOT NULL AND pc.iso_alpha_2 = dt.physical_country_iso_2
        LEFT JOIN public.region psr ON dt.postal_region_code IS NOT NULL AND psr.code = dt.postal_region_code
        LEFT JOIN public.country psc ON dt.postal_country_iso_2 IS NOT NULL AND psc.iso_alpha_2 = dt.postal_country_iso_2
        WHERE dt.ctid = batch.data_ctid;
    ', v_data_table_name, p_batch_ctids);
    RAISE DEBUG '[Job %] analyse_location: Batch updating lookups: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Batch Update Typed Coordinates
    v_sql := format('
        UPDATE public.%I dt SET
            typed_physical_latitude = admin.safe_cast_to_numeric(dt.physical_latitude),
            typed_physical_longitude = admin.safe_cast_to_numeric(dt.physical_longitude),
            typed_physical_altitude = admin.safe_cast_to_numeric(dt.physical_altitude),
            typed_postal_latitude = admin.safe_cast_to_numeric(dt.postal_latitude),
            typed_postal_longitude = admin.safe_cast_to_numeric(dt.postal_longitude),
            typed_postal_altitude = admin.safe_cast_to_numeric(dt.postal_altitude)
        WHERE dt.ctid = ANY(%L);
    ', v_data_table_name, p_batch_ctids);
    RAISE DEBUG '[Job %] analyse_location: Batch updating typed coordinates: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Identify and Aggregate Errors Post-Batch
    CREATE TEMP TABLE temp_batch_errors (data_ctid TID PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;
    v_sql := format('
        INSERT INTO temp_batch_errors (data_ctid, error_jsonb)
        SELECT
            ctid,
            jsonb_strip_nulls(
                jsonb_build_object(''physical_region_code'', CASE WHEN physical_region_code IS NOT NULL AND physical_region_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''physical_country_iso_2'', CASE WHEN physical_country_iso_2 IS NOT NULL AND physical_country_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''physical_latitude'', CASE WHEN physical_latitude IS NOT NULL AND typed_physical_latitude IS NULL THEN ''Invalid format'' ELSE NULL END) ||
                jsonb_build_object(''physical_longitude'', CASE WHEN physical_longitude IS NOT NULL AND typed_physical_longitude IS NULL THEN ''Invalid format'' ELSE NULL END) ||
                jsonb_build_object(''physical_altitude'', CASE WHEN physical_altitude IS NOT NULL AND typed_physical_altitude IS NULL THEN ''Invalid format'' ELSE NULL END) ||
                jsonb_build_object(''postal_region_code'', CASE WHEN postal_region_code IS NOT NULL AND postal_region_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''postal_country_iso_2'', CASE WHEN postal_country_iso_2 IS NOT NULL AND postal_country_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''postal_latitude'', CASE WHEN postal_latitude IS NOT NULL AND typed_postal_latitude IS NULL THEN ''Invalid format'' ELSE NULL END) ||
                jsonb_build_object(''postal_longitude'', CASE WHEN postal_longitude IS NOT NULL AND typed_postal_longitude IS NULL THEN ''Invalid format'' ELSE NULL END) ||
                jsonb_build_object(''postal_altitude'', CASE WHEN postal_altitude IS NOT NULL AND typed_postal_altitude IS NULL THEN ''Invalid format'' ELSE NULL END)
            ) AS error_jsonb
        FROM public.%I
        WHERE ctid = ANY(%L)
    ', v_data_table_name, p_batch_ctids);
     RAISE DEBUG '[Job %] analyse_location: Identifying errors post-batch: %', p_job_id, v_sql;
     EXECUTE v_sql;

    -- Step 4: Batch Update Error Rows
    v_sql := format('
        UPDATE public.%I dt SET
            state = %L,
            error = COALESCE(dt.error, %L) || err.error_jsonb,
            last_completed_priority = %L
        FROM temp_batch_errors err
        WHERE dt.ctid = err.data_ctid AND err.error_jsonb != %L;
    ', v_data_table_name, 'error', '{}'::jsonb, v_step.priority - 1, '{}'::jsonb);
    RAISE DEBUG '[Job %] analyse_location: Updating error rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    v_error_count := v_update_count;
    SELECT array_agg(data_ctid) INTO v_error_ctids FROM temp_batch_errors WHERE error_jsonb != '{}'::jsonb;
    RAISE DEBUG '[Job %] analyse_location: Marked % rows as error.', p_job_id, v_update_count;

    -- Step 5: Batch Update Success Rows
    v_sql := format('
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = NULL, -- Clear errors if successful now
            state = %L
        WHERE dt.ctid = ANY(%L) AND dt.ctid != ALL(%L); -- Update only non-error rows from the original batch
    ', v_data_table_name, v_step.priority, 'analysing', p_batch_ctids, COALESCE(v_error_ctids, ARRAY[]::TID[]));
    RAISE DEBUG '[Job %] analyse_location: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_location: Marked % rows as success for this target.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] analyse_location (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$procedure$
```
