```sql
CREATE OR REPLACE PROCEDURE import.propagate_fatal_error_to_entity_batch(IN p_job_id integer, IN p_data_table_name text, IN p_batch_seq integer, IN p_error_keys text[], IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_failed_entity_founding_rows INTEGER[];
    v_error_key_for_json TEXT;
BEGIN
    v_error_key_for_json := COALESCE(p_error_keys[1], 'propagated_error');

    -- Find the founding_row_ids for any row in the current batch that was just marked as an error by this step.
    EXECUTE format($$
        SELECT array_agg(DISTINCT dt.founding_row_id)
        FROM public.%1$I dt
        WHERE dt.batch_seq = $1 -- from the current batch
          AND dt.state = 'error'
          AND dt.founding_row_id IS NOT NULL
          AND (dt.errors ?| %2$L::text[]); -- and the error is from this step
    $$, p_data_table_name, p_error_keys)
    INTO v_failed_entity_founding_rows
    USING p_batch_seq;

    IF array_length(v_failed_entity_founding_rows, 1) > 0 THEN
        RAISE DEBUG '[Job %] %s: Propagating errors for % failed entities.', p_job_id, p_step_code, array_length(v_failed_entity_founding_rows, 1);
        EXECUTE format($$
            WITH failed_rows AS (
                SELECT founding_row_id, array_agg(row_id) as error_source_row_ids
                FROM public.%1$I
                WHERE founding_row_id = ANY($1) AND state = 'error' AND (errors ?| %2$L::text[])
                GROUP BY founding_row_id
            )
            UPDATE public.%1$I dt SET
                state = 'error',
                action = 'skip',
                errors = COALESCE(dt.errors, '{}'::jsonb) || jsonb_build_object(
                    %4$L,
                    'An error on a related new entity row caused this row to be skipped. Source error row(s): ' || fr.error_source_row_ids::TEXT
                )
            FROM failed_rows fr
            WHERE dt.founding_row_id = fr.founding_row_id
              AND dt.state != 'error' -- Don't re-process rows already in error
              AND NOT (dt.errors ?| %2$L::text[]); -- Don't update the row that was the source of the error
        $$, p_data_table_name, p_error_keys, v_failed_entity_founding_rows, v_error_key_for_json)
        USING v_failed_entity_founding_rows;
    END IF;
END;
$procedure$
```
