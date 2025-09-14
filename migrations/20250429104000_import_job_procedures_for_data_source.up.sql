-- Migration for data_source import step
BEGIN;

-- Procedure to analyse data source from code
CREATE OR REPLACE PROCEDURE import.analyse_data_source(p_job_id INT, p_batch_row_ids INTEGER[], p_step_code TEXT)
LANGUAGE plpgsql AS $analyse_data_source$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_sql TEXT;
    v_update_count INT;
    v_skipped_update_count INT;
BEGIN
    RAISE DEBUG '[Job %] analyse_data_source (Batch): Starting analysis for % rows.', p_job_id, array_length(p_batch_row_ids, 1);

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] Step % not found in snapshot', p_job_id, p_step_code; END IF;

    v_sql := format($SQL$
        WITH
        batch_data AS (
            SELECT row_id, data_source_code
            FROM public.%1$I
            WHERE row_id = ANY($1) AND action IS DISTINCT FROM 'skip'
        ),
        distinct_codes AS (
            SELECT data_source_code AS code
            FROM batch_data
            WHERE NULLIF(data_source_code, '') IS NOT NULL
            GROUP BY 1
        ),
        resolved_codes AS (
            SELECT
                dc.code,
                ds.id as resolved_id
            FROM distinct_codes dc
            LEFT JOIN public.data_source_available ds ON ds.code = dc.code
        ),
        lookups AS (
            SELECT
                bd.row_id,
                rc.resolved_id as resolved_data_source_id
            FROM batch_data bd
            LEFT JOIN resolved_codes rc ON bd.data_source_code = rc.code
        )
        UPDATE public.%1$I dt SET
            data_source_id = COALESCE(l.resolved_data_source_id, dt.data_source_id), -- Only update if resolved, don't nullify
            invalid_codes = jsonb_strip_nulls(
                (COALESCE(dt.invalid_codes, '{}'::jsonb) - 'data_source_code') ||
                jsonb_build_object('data_source_code',
                    CASE
                        WHEN NULLIF(dt.data_source_code, '') IS NOT NULL AND l.resolved_data_source_id IS NULL THEN dt.data_source_code
                        ELSE NULL
                    END
                )
            ),
            last_completed_priority = %2$L
        FROM lookups l
        WHERE dt.row_id = l.row_id;
    $SQL$, v_job.data_table_name, v_step.priority);

    EXECUTE v_sql USING p_batch_row_ids;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_data_source (Batch): Updated % non-skipped rows.', p_job_id, v_update_count;

    -- Advance priority for rows that were already skipped to prevent loops.
    EXECUTE format('UPDATE public.%I SET last_completed_priority = %s WHERE row_id = ANY($1) AND action = ''skip''', v_job.data_table_name, v_step.priority)
    USING p_batch_row_ids;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_data_source (Batch): Updated priority for % previously skipped rows.', p_job_id, v_skipped_update_count;

    v_update_count := v_update_count + v_skipped_update_count;
    RAISE DEBUG '[Job %] analyse_data_source (Batch): Finished. Updated priority for % total rows.', p_job_id, v_update_count;
END;
$analyse_data_source$;

COMMIT;
