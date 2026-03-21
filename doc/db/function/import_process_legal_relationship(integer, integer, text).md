```sql
CREATE OR REPLACE PROCEDURE import.process_legal_relationship(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    error_message TEXT;
    v_start_time TIMESTAMPTZ;
    v_duration_ms NUMERIC;
    v_merge_mode sql_saga.temporal_merge_mode;
BEGIN
    v_start_time := clock_timestamp();
    RAISE DEBUG '[Job %] process_legal_relationship (Batch): Starting operation for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');
    IF v_definition IS NULL THEN RAISE EXCEPTION '[Job %] Failed to load import_definition from snapshot', p_job_id; END IF;

    SELECT * INTO v_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
    WHERE code = 'legal_relationship';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] legal_relationship target step not found in snapshot', p_job_id; END IF;

    -- Create updatable view over batch data mapping to legal_relationship columns
    v_sql := format($$
        CREATE OR REPLACE TEMP VIEW temp_legal_relationship_source_view AS
        SELECT
            row_id AS data_row_id,
            founding_row_id,
            legal_relationship_id AS id,
            influencing_id,
            influenced_id,
            type_id,
            percentage,
            valid_from,
            valid_until,
            edit_by_user_id,
            edit_at,
            edit_comment,
            NULLIF(warnings,'{}'::JSONB) AS warnings,
            errors,
            merge_status
        FROM public.%1$I
        WHERE batch_seq = %2$L AND action = 'use';
    $$, v_data_table_name, p_batch_seq);
    EXECUTE v_sql;

    BEGIN
        v_merge_mode := CASE v_definition.strategy
            WHEN 'insert_or_replace' THEN 'MERGE_ENTITY_REPLACE'::sql_saga.temporal_merge_mode
            WHEN 'replace_only' THEN 'REPLACE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            WHEN 'insert_or_update' THEN 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
            WHEN 'update_only' THEN 'UPDATE_FOR_PORTION_OF'::sql_saga.temporal_merge_mode
            ELSE 'MERGE_ENTITY_PATCH'::sql_saga.temporal_merge_mode
        END;
        RAISE DEBUG '[Job %] process_legal_relationship: Determined merge mode % from strategy %', p_job_id, v_merge_mode, v_definition.strategy;

        CALL sql_saga.temporal_merge(
            target_table => 'public.legal_relationship'::regclass,
            source_table => 'temp_legal_relationship_source_view'::regclass,
            primary_identity_columns => ARRAY['id'],
            mode => v_merge_mode,
            row_id_column => 'data_row_id',
            founding_id_column => 'founding_row_id',
            update_source_with_identity => true,
            update_source_with_feedback => true,
            feedback_status_column => 'merge_status',
            feedback_status_key => 'legal_relationship',
            feedback_error_column => 'errors',
            feedback_error_key => 'legal_relationship'
        );

        v_sql := format($$ SELECT count(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.errors->'legal_relationship' IS NOT NULL $$, v_data_table_name);
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;

        v_sql := format($$
            UPDATE public.%1$I dt SET
                state = CASE WHEN dt.errors ? 'legal_relationship' THEN 'error'::public.import_data_state ELSE 'processing'::public.import_data_state END
            WHERE dt.batch_seq = $1 AND dt.action = 'use';
        $$, v_data_table_name);
        EXECUTE v_sql USING p_batch_seq;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        v_update_count := v_update_count - v_error_count;

        RAISE DEBUG '[Job %] process_legal_relationship: temporal_merge finished. Success: %, Errors: %', p_job_id, v_update_count, v_error_count;

        -- Propagate newly assigned legal_relationship_id within batch
        v_sql := format($$
            WITH id_source AS (
                SELECT DISTINCT src.founding_row_id, src.legal_relationship_id
                FROM public.%1$I src
                WHERE src.batch_seq = $1
                  AND src.legal_relationship_id IS NOT NULL
            )
            UPDATE public.%1$I dt
            SET legal_relationship_id = id_source.legal_relationship_id
            FROM id_source
            WHERE dt.batch_seq = $1
              AND dt.founding_row_id = id_source.founding_row_id
              AND dt.legal_relationship_id IS NULL;
        $$, v_data_table_name);
        EXECUTE v_sql USING p_batch_seq;

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] process_legal_relationship: Unhandled error: %', p_job_id, replace(error_message, '%', '%%');
        BEGIN
            v_sql := format($$UPDATE public.%1$I dt SET state = 'error'::public.import_data_state, errors = errors || jsonb_build_object('unhandled_error_process_legal_relationship', %2$L) WHERE dt.batch_seq = $1 AND dt.state != 'error'::public.import_data_state$$,
                           v_data_table_name, error_message);
            EXECUTE v_sql USING p_batch_seq;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '[Job %] process_legal_relationship: Failed to mark rows as error: %', p_job_id, SQLERRM;
        END;
        UPDATE public.import_job SET error = jsonb_build_object('process_legal_relationship_unhandled_error', error_message)::TEXT, state = 'failed' WHERE id = p_job_id;
    END;

    v_duration_ms := (EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time)) * 1000);
    RAISE DEBUG '[Job %] process_legal_relationship (Batch): Finished in % ms. Success: %, Errors: %', p_job_id, round(v_duration_ms, 2), v_update_count, v_error_count;
END;
$procedure$
```
