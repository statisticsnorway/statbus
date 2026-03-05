```sql
CREATE OR REPLACE PROCEDURE import.propagate_fatal_error_to_entity_holistic(IN p_job_id integer, IN p_data_table_name text, IN p_temp_error_table_name text, IN p_error_keys text[], IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_failed_entity_founding_rows INTEGER[];
    v_error_key_for_json TEXT;
BEGIN
    v_error_key_for_json := COALESCE(p_error_keys[1], 'propagated_error');

    -- Find founding_row_ids for any row that was marked as an error by this step (held in a temp table).
    EXECUTE format($$
        SELECT array_agg(DISTINCT dt.founding_row_id)
        FROM public.%1$I dt
        JOIN %2$I tbe ON dt.row_id = tbe.data_row_id
        WHERE dt.founding_row_id IS NOT NULL;
    $$, p_data_table_name, p_temp_error_table_name)
    INTO v_failed_entity_founding_rows;

    IF array_length(v_failed_entity_founding_rows, 1) > 0 THEN
        RAISE DEBUG '[Job %] %s: Propagating errors for % failed entities.', p_job_id, p_step_code, array_length(v_failed_entity_founding_rows, 1);
        EXECUTE format($$
            WITH failed_rows AS (
                SELECT dt.founding_row_id, array_agg(tbe.data_row_id) as error_source_row_ids
                FROM %2$I tbe
                JOIN public.%1$I dt ON dt.row_id = tbe.data_row_id
                GROUP BY dt.founding_row_id
            )
            UPDATE public.%1$I dt SET
                state = 'error',
                action = 'skip',
                errors = COALESCE(dt.errors, '{}'::jsonb) || jsonb_build_object(
                    %3$L,
                    'An error on a related new entity row caused this row to be skipped. Source error row(s): ' || fr.error_source_row_ids::TEXT
                )
            FROM failed_rows fr
            WHERE dt.founding_row_id = fr.founding_row_id
              AND dt.state != 'error' -- Don't re-process rows already in error
              AND dt.row_id NOT IN (SELECT data_row_id FROM %2$I); -- Don't update rows from the error temp table
        $$, p_data_table_name, p_temp_error_table_name, v_error_key_for_json)
        USING v_failed_entity_founding_rows;
    END IF;
END;
$procedure$
```
