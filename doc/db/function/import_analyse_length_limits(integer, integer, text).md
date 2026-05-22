```sql
CREATE OR REPLACE PROCEDURE import.analyse_length_limits(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_sql TEXT;
    v_update_count INT := 0;
    v_skipped_update_count INT := 0;
    v_truncate_overlong BOOLEAN;

    -- Dynamic UPDATE clause accumulators.
    v_set_clauses TEXT := '';
    v_warnings_clauses TEXT := '';
    v_errors_clauses TEXT := '';
    v_state_clause TEXT := '';

    v_col RECORD;
    v_n INT;
    v_clause_count INT := 0;

    -- Columns that emit `errors` entries (and contribute to the
    -- state='error' decision). Encoded as 'colname:N' strings.
    v_error_columns TEXT[] := ARRAY[]::TEXT[];
BEGIN
    RAISE DEBUG '[Job %] analyse_length_limits (Batch): Starting length checks for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_truncate_overlong := COALESCE(v_job.truncate_overlong, false);

    SELECT * INTO v_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
    WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_length_limits step (code=%) not found in snapshot', p_job_id, p_step_code;
    END IF;

    RAISE DEBUG '[Job %] analyse_length_limits: truncate_overlong=%, building per-column clauses', p_job_id, v_truncate_overlong;

    -- Iterate bounded columns from the definition snapshot. Bucketing
    -- is now driven entirely by (purpose, target_pg_type):
    --   - purpose='internal' + target_pg_type matches varchar(N)
    --     → descriptive (truncate or error per flag)
    --   - purpose='source_input' + target_pg_type matches varchar(N)
    --     → identifier (always error, regardless of flag)
    --   - target_pg_type='ltree' or anything non-varchar → out of scope
    FOR v_col IN
        SELECT
            entry->>'column_name'       AS column_name,
            entry->>'purpose'           AS purpose,
            entry->>'target_pg_type'    AS target_pg_type,
            (regexp_match(entry->>'target_pg_type', '^character varying\(([0-9]+)\)$'))[1]::INT AS varchar_limit
        FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS entry
        WHERE entry->>'target_pg_type' ~ '^character varying\([0-9]+\)$'
          AND entry->>'purpose' IN ('internal', 'source_input')
        ORDER BY entry->>'column_name'
    LOOP
        v_n := v_col.varchar_limit;
        IF v_col.purpose = 'internal' THEN
            IF v_truncate_overlong THEN
                -- TRUNCATE branch (opt-in): rewrite value + warning.
                v_set_clauses := v_set_clauses || format(
                    $clause$,
                %1$I = CASE
                    WHEN length(dt.%1$I) > %2$L THEN substring(dt.%1$I FROM 1 FOR %2$L)
                    ELSE dt.%1$I
                END$clause$,
                    v_col.column_name /* %1$I */,
                    v_n               /* %2$L */
                );
                v_warnings_clauses := v_warnings_clauses || format(
                    $clause$ || CASE
                        WHEN length(dt.%1$I) > %2$L THEN
                            jsonb_build_object(%3$L, jsonb_build_object('truncated_from', length(dt.%1$I), 'to', %2$L))
                        ELSE '{}'::jsonb
                    END$clause$,
                    v_col.column_name /* %1$I */,
                    v_n               /* %2$L */,
                    v_col.column_name /* %3$L */
                );
            ELSE
                -- STRICT branch (default): hard-fail on overflow.
                v_errors_clauses := v_errors_clauses || format(
                    $clause$ || CASE
                        WHEN length(dt.%1$I) > %2$L THEN
                            jsonb_build_object(%3$L, jsonb_build_object('too_long', length(dt.%1$I), 'limit', %2$L))
                        ELSE '{}'::jsonb
                    END$clause$,
                    v_col.column_name /* %1$I */,
                    v_n               /* %2$L */,
                    v_col.column_name /* %3$L */
                );
                v_error_columns := v_error_columns || ARRAY[v_col.column_name || ':' || v_n::TEXT];
            END IF;
        ELSE
            -- purpose='source_input': identifier bucket — ALWAYS error.
            -- Truncating an identifier silently changes the operator's PK.
            v_errors_clauses := v_errors_clauses || format(
                $clause$ || CASE
                    WHEN length(dt.%1$I) > %2$L THEN
                        jsonb_build_object(%3$L, jsonb_build_object('too_long', length(dt.%1$I), 'limit', %2$L))
                    ELSE '{}'::jsonb
                END$clause$,
                v_col.column_name /* %1$I */,
                v_n               /* %2$L */,
                v_col.column_name /* %3$L */
            );
            v_error_columns := v_error_columns || ARRAY[v_col.column_name || ':' || v_n::TEXT];
        END IF;
        v_clause_count := v_clause_count + 1;
    END LOOP;

    -- state clause: 'error' iff ANY error-emitting column overflowed.
    IF array_length(v_error_columns, 1) > 0 THEN
        SELECT string_agg(
            format(
                $cond$length(dt.%1$I) > %2$L$cond$,
                split_part(entry, ':', 1),
                split_part(entry, ':', 2)::INT
            ),
            ' OR '
        ) INTO v_state_clause
        FROM unnest(v_error_columns) AS entry;
    END IF;

    IF v_clause_count = 0 THEN
        RAISE DEBUG '[Job %] analyse_length_limits: no bounded columns in scope; advancing priority only', p_job_id;
    ELSE
        v_sql := format($update$
            UPDATE public.%1$I dt
            SET
                last_completed_priority = %2$L::INTEGER%3$s,
                warnings = COALESCE(dt.warnings, '{}'::jsonb) %4$s,
                errors   = COALESCE(dt.errors,   '{}'::jsonb) %5$s,
                state    = CASE
                               WHEN (%6$s) THEN 'error'::public.import_data_state
                               ELSE dt.state
                           END
            WHERE dt.batch_seq = $1
              AND dt.action IS DISTINCT FROM 'skip'
        $update$,
            v_data_table_name                              /* %1$I */,
            v_step.priority                                /* %2$L */,
            v_set_clauses                                  /* %3$s — leading comma included */,
            v_warnings_clauses                             /* %4$s */,
            v_errors_clauses                               /* %5$s */,
            COALESCE(NULLIF(v_state_clause, ''), 'FALSE')  /* %6$s — short-circuit if no error-emit cols */
        );

        RAISE DEBUG '[Job %] analyse_length_limits: batch UPDATE SQL: %', p_job_id, v_sql;

        BEGIN
            EXECUTE v_sql USING p_batch_seq;
            GET DIAGNOSTICS v_update_count = ROW_COUNT;
            RAISE DEBUG '[Job %] analyse_length_limits: Updated % rows in batch_seq %', p_job_id, v_update_count, p_batch_seq;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '[Job %] analyse_length_limits: error during batch update: %', p_job_id, SQLERRM;
            UPDATE public.import_job
            SET error = jsonb_build_object('analyse_length_limits_batch_error', SQLERRM)::TEXT,
                state = 'failed'
            WHERE id = p_job_id;
            RETURN;
        END;
    END IF;

    -- Unconditionally advance priority for all rows in batch (mirrors
    -- analyse_status pattern; ensures skip-actioned rows progress too).
    v_sql := format($adv$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L;
    $adv$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_length_limits: Advanced last_completed_priority for % total rows in batch', p_job_id, v_skipped_update_count;

    -- Propagate errors to other rows of the same entity (best-effort,
    -- matches analyse_status pattern).
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(
            p_job_id, v_data_table_name, p_batch_seq,
            ARRAY[]::TEXT[],
            'analyse_length_limits'
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_length_limits: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_length_limits (Batch): Finished for batch_seq %', p_job_id, p_batch_seq;
END;
$procedure$
```
