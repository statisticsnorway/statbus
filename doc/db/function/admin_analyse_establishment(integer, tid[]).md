```sql
CREATE OR REPLACE PROCEDURE admin.analyse_establishment(IN p_job_id integer, IN p_batch_ctids tid[])
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_snapshot JSONB;
    v_definition JSONB;
    v_step RECORD;
    v_computed_valid_from DATE;
    v_computed_valid_to DATE;
    v_data_table_name TEXT;
    v_error_ctids TID[] := ARRAY[]::TID[];
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
BEGIN
    RAISE DEBUG '[Job %] analyse_establishment (Batch): Starting analysis for % rows', p_job_id, array_length(p_batch_ctids, 1);

    -- Get job details and snapshot
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_definition := v_job.definition_snapshot; -- Assign snapshot from the job record
    v_data_table_name := v_job.data_table_name; -- Assign separately

    IF v_definition IS NULL OR jsonb_typeof(v_definition) != 'object' THEN
        RAISE EXCEPTION '[Job %] Failed to load valid definition snapshot from import_job record', p_job_id;
    END IF;

    -- Find the target details for establishment
    SELECT * INTO v_step FROM public.import_step WHERE code = 'establishment';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] establishment target not found', p_job_id;
    END IF;

    -- Get computed validity dates if time_context is used
    IF v_definition->>'time_context_ident' IS NOT NULL THEN
        SELECT tc.valid_from, tc.valid_to
        INTO v_computed_valid_from, v_computed_valid_to
        FROM public.time_context tc
        WHERE tc.ident = v_definition->>'time_context_ident';
    END IF;

    -- Step 1: Batch Update Lookups
    v_sql := format('
        UPDATE public.%I dt SET
            data_source_id = ds.id,
            status_id = s.id,
            sector_id = sec.id,
            unit_size_id = us.id
        FROM unnest(%L::TID[]) AS batch(data_ctid) -- Process only the batch
        LEFT JOIN public.data_source ds ON dt.data_source_code IS NOT NULL AND ds.code = dt.data_source_code
        LEFT JOIN public.status s ON dt.status_code IS NOT NULL AND s.code = dt.status_code
        LEFT JOIN public.sector sec ON dt.sector_code IS NOT NULL AND sec.code = dt.sector_code -- Assuming only code for establishment sector
        LEFT JOIN public.unit_size us ON dt.unit_size_code IS NOT NULL AND us.code = dt.unit_size_code
        WHERE dt.ctid = batch.data_ctid;
    ', v_data_table_name, p_batch_ctids);
    RAISE DEBUG '[Job %] analyse_establishment: Batch updating lookups: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 2: Batch Update Typed Dates
    v_sql := format('
        UPDATE public.%I dt SET
            typed_birth_date = admin.safe_cast_to_date(dt.birth_date),
            typed_death_date = admin.safe_cast_to_date(dt.death_date),
            typed_valid_from = CASE WHEN %L IS NULL THEN admin.safe_cast_to_date(dt.valid_from) ELSE NULL END,
            typed_valid_to = CASE WHEN %L IS NULL THEN admin.safe_cast_to_date(dt.valid_to) ELSE NULL END,
            computed_valid_from = CASE WHEN %L IS NOT NULL THEN %L::DATE ELSE NULL END,
            computed_valid_to = CASE WHEN %L IS NOT NULL THEN %L::DATE ELSE NULL END
        WHERE dt.ctid = ANY(%L);
    ', v_data_table_name,
       v_definition->>'time_context_ident', v_definition->>'time_context_ident',
       v_definition->>'time_context_ident', v_computed_valid_from,
       v_definition->>'time_context_ident', v_computed_valid_to,
       p_batch_ctids);
    RAISE DEBUG '[Job %] analyse_establishment: Batch updating typed dates: %', p_job_id, v_sql;
    EXECUTE v_sql;

    -- Step 3: Identify and Aggregate Errors Post-Batch
    CREATE TEMP TABLE temp_batch_errors (data_ctid TID PRIMARY KEY, error_jsonb JSONB) ON COMMIT DROP;
    v_sql := format('
        INSERT INTO temp_batch_errors (data_ctid, error_jsonb)
        SELECT
            ctid,
            jsonb_strip_nulls(
                jsonb_build_object(''data_source_code'', CASE WHEN data_source_code IS NOT NULL AND data_source_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''status_code'', CASE WHEN status_code IS NOT NULL AND status_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''sector_code'', CASE WHEN sector_code IS NOT NULL AND sector_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''unit_size_code'', CASE WHEN unit_size_code IS NOT NULL AND unit_size_id IS NULL THEN ''Not found'' ELSE NULL END) ||
                jsonb_build_object(''birth_date'', CASE WHEN birth_date IS NOT NULL AND typed_birth_date IS NULL THEN ''Invalid format'' ELSE NULL END) ||
                jsonb_build_object(''death_date'', CASE WHEN death_date IS NOT NULL AND typed_death_date IS NULL THEN ''Invalid format'' ELSE NULL END) ||
                jsonb_build_object(''valid_from'', CASE WHEN %L IS NULL AND valid_from IS NOT NULL AND typed_valid_from IS NULL THEN ''Invalid format'' ELSE NULL END) ||
                jsonb_build_object(''valid_to'', CASE WHEN %L IS NULL AND valid_to IS NOT NULL AND typed_valid_to IS NULL THEN ''Invalid format'' ELSE NULL END)
            ) AS error_jsonb
        FROM public.%I
        WHERE ctid = ANY(%L)
    ', v_definition->>'time_context_ident', v_definition->>'time_context_ident',
       v_data_table_name, p_batch_ctids);
     RAISE DEBUG '[Job %] analyse_establishment: Identifying errors post-batch: %', p_job_id, v_sql;
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
    RAISE DEBUG '[Job %] analyse_establishment: Updating error rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    v_error_count := v_update_count;
    SELECT array_agg(data_ctid) INTO v_error_ctids FROM temp_batch_errors WHERE error_jsonb != '{}'::jsonb;
    RAISE DEBUG '[Job %] analyse_establishment: Marked % rows as error.', p_job_id, v_update_count;

    -- Step 5: Batch Update Success Rows
    v_sql := format('
        UPDATE public.%I dt SET
            last_completed_priority = %L,
            error = NULL, -- Clear errors if successful now
            state = %L
        WHERE dt.ctid = ANY(%L) AND dt.ctid != ALL(%L); -- Update only non-error rows from the original batch
    ', v_data_table_name, v_step.priority, 'analysing', p_batch_ctids, COALESCE(v_error_ctids, ARRAY[]::TID[]));
    RAISE DEBUG '[Job %] analyse_establishment: Updating success rows: %', p_job_id, v_sql;
    EXECUTE v_sql;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_establishment: Marked % rows as success for this target.', p_job_id, v_update_count;

    RAISE DEBUG '[Job %] analyse_establishment (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$procedure$
```
