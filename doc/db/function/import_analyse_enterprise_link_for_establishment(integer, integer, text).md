```sql
CREATE OR REPLACE PROCEDURE import.analyse_enterprise_link_for_establishment(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT;
    v_job_mode public.import_mode;
    v_external_ident_source_columns TEXT[];
    error_message TEXT;
BEGIN
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = p_step_code;
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] Step % not found in snapshot', p_job_id, p_step_code; END IF;

    BEGIN
        -- This analysis is only for informal establishments. Other modes do nothing but advance priority.
        IF v_job_mode = 'establishment_informal' THEN
            -- Get the list of external identifier source columns to correctly associate errors.
            SELECT array_agg(idc_elem.value->>'column_name') INTO v_external_ident_source_columns
            FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS idc_elem
            JOIN jsonb_array_elements(v_job.definition_snapshot->'import_step_list') AS step_elem
                ON (step_elem.value->>'code') = 'external_idents' AND (idc_elem.value->>'step_id')::int = (step_elem.value->>'id')::int
            WHERE idc_elem.value->>'purpose' = 'source_input';

            -- For 'replace' or 'update' actions, validate that the existing establishment is informal and has an enterprise link.
            -- This step is crucial to ensure that when a new historical slice is created for an existing establishment,
            -- it correctly inherits the enterprise_id, preventing a check constraint violation in the 'process_establishment' step.
            v_sql := format($$
                WITH validation AS (
                    SELECT
                        dt.row_id,
                        est.id as found_est_id,
                        est.enterprise_id AS existing_enterprise_id,
                        est.primary_for_enterprise AS existing_primary_for_enterprise
                    FROM public.%1$I dt
                    LEFT JOIN public.establishment est ON dt.establishment_id = est.id
                    WHERE dt.batch_seq = $1
                      AND dt.operation IN ('replace', 'update')
                      AND dt.establishment_id IS NOT NULL -- This check should only apply to establishments that existed before this job.
                      AND dt.action IS DISTINCT FROM 'skip'
                )
                UPDATE public.%1$I dt SET
                    enterprise_id = v.existing_enterprise_id,
                    primary_for_enterprise = v.existing_primary_for_enterprise,
                    state = CASE
                        WHEN v.found_est_id IS NULL THEN 'error'::public.import_data_state
                        WHEN v.existing_enterprise_id IS NULL THEN 'error'::public.import_data_state
                        ELSE dt.state
                    END,
                    action = CASE
                        WHEN v.found_est_id IS NULL OR v.existing_enterprise_id IS NULL THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                    END,
                    errors = dt.errors || CASE
                        WHEN v.found_est_id IS NULL THEN (SELECT jsonb_object_agg(col, 'Informal establishment for "replace" or "update" not found.') FROM unnest(%2$L::TEXT[]) col)
                        WHEN v.existing_enterprise_id IS NULL THEN (SELECT jsonb_object_agg(col, 'Informal establishment for "replace" or "update" is not linked to an enterprise.') FROM unnest(%2$L::TEXT[]) col)
                        ELSE '{}'::jsonb
                    END
                FROM validation v
                WHERE dt.row_id = v.row_id;
            $$, v_data_table_name, v_external_ident_source_columns);
            RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (batch_seq=%): Validating "replace" and "update" rows for informal establishments.', p_job_id, p_batch_seq;
            EXECUTE v_sql USING p_batch_seq;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        RAISE WARNING '[Job %] analyse_enterprise_link_for_establishment: Error during analysis: %', p_job_id, error_message;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_enterprise_link_for_establishment_error', error_message), state = 'finished'
        WHERE id = p_job_id;
        RAISE;
    END;

    -- Always advance priority for all rows in the batch to prevent loops.
    v_sql := format('UPDATE public.%I dt SET last_completed_priority = %s WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %s', v_data_table_name, v_step.priority, v_step.priority);
    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (batch_seq=%): Advancing priority for all rows with SQL: %', p_job_id, p_batch_seq, v_sql;
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_update_count = ROW_COUNT;

    RAISE DEBUG '[Job %] analyse_enterprise_link_for_establishment (batch_seq=%): Finished analysis. Updated priority for % rows.', p_job_id, p_batch_seq, v_update_count;
END;
$procedure$
```
