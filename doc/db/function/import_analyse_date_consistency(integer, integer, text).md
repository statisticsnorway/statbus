```sql
CREATE OR REPLACE PROCEDURE import.analyse_date_consistency(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_job_mode public.import_mode;
    v_unit_label TEXT;
    v_sql TEXT;
    v_ident_label_expr TEXT;
    v_has_name BOOLEAN;
    v_update_count INT := 0;
    -- The keys this step owns. They are real source_input column names, so the
    -- import UI (ErrorDisplay strips the _raw suffix) shows a meaningful field label.
    -- A birth after the window names birth_date and the window end (valid_to);
    -- a death before the window names death_date and the window start (valid_from).
    v_error_keys_arr TEXT[] := ARRAY['birth_date_raw', 'death_date_raw', 'valid_from_raw', 'valid_to_raw'];
BEGIN
    RAISE DEBUG '[Job %] analyse_date_consistency (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;
    v_job_mode := (v_job.definition_snapshot->'import_definition'->>'mode')::public.import_mode;

    SELECT * INTO v_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
    WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_date_consistency: step % not found in snapshot', p_job_id, p_step_code;
    END IF;

    -- The rule needs both life dates. A definition whose data table has neither
    -- (a definition without a unit step) has nothing to check: advance only.
    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS idc
        WHERE idc->>'column_name' = 'birth_date_raw' AND idc->>'purpose' = 'source_input'
    ) AND EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS idc
        WHERE idc->>'column_name' = 'death_date_raw' AND idc->>'purpose' = 'source_input'
    ) THEN
        v_unit_label := CASE v_job_mode
            WHEN 'legal_unit' THEN 'Legal unit'
            WHEN 'establishment_formal' THEN 'Establishment'
            WHEN 'establishment_informal' THEN 'Establishment'
            ELSE 'Unit'
        END;

        SELECT EXISTS (
            SELECT 1
            FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS idc
            WHERE idc->>'column_name' = 'name_raw' AND idc->>'purpose' = 'source_input'
        ) INTO v_has_name;

        -- Name the unit by the identifiers the row itself carries (at this point
        -- in the pipeline the unit has no database id yet), e.g. 'tax_ident 123'.
        SELECT COALESCE(
                   'concat_ws('', '', ' || string_agg(
                       format($fmt$CASE WHEN NULLIF(dt.%1$I, '') IS NOT NULL THEN %2$L || ' ' || dt.%1$I END$fmt$,
                              idc.column_name, regexp_replace(idc.column_name, '_raw$', '')),
                       ', ' ORDER BY idc.column_name) || ')',
                   'NULL::TEXT')
        INTO v_ident_label_expr
        FROM (
            SELECT idc->>'column_name' AS column_name
            FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS idc
            JOIN jsonb_array_elements(v_job.definition_snapshot->'import_step_list') AS s
              ON (s->>'id')::int = (idc->>'step_id')::int
            WHERE s->>'code' = 'external_idents' AND idc->>'purpose' = 'source_input'
        ) AS idc;

        v_sql := format($SQL$
            WITH batch AS (
                SELECT dt.row_id,
                       dt.valid_from,
                       dt.valid_to,
                       dt.valid_until,
                       NULLIF(dt.birth_date_raw, '') AS birth_date_raw,
                       NULLIF(dt.death_date_raw, '') AS death_date_raw,
                       %4$s AS unit_name,
                       NULLIF(%5$s, '') AS ident_label
                FROM public.%1$I AS dt
                WHERE dt.batch_seq = $1
                  AND dt.action IS DISTINCT FROM 'skip'
            ),
            distinct_dates AS (
                SELECT birth_date_raw AS date_string FROM batch WHERE birth_date_raw IS NOT NULL
                UNION
                SELECT death_date_raw AS date_string FROM batch WHERE death_date_raw IS NOT NULL
            ),
            -- The same cast the core unit step uses later. An unparseable date is
            -- NULL here; reporting it is the core step's job (a warning), not ours.
            cast_dates AS MATERIALIZED (
                SELECT dd.date_string, sc.p_value
                FROM distinct_dates AS dd
                LEFT JOIN LATERAL import.safe_cast_to_date(dd.date_string) AS sc ON TRUE
            ),
            checked AS (
                SELECT b.*,
                       bd.p_value AS birth_date,
                       dd.p_value AS death_date,
                       (bd.p_value IS NOT NULL AND b.valid_until IS NOT NULL AND bd.p_value >= b.valid_until) AS born_after_window,
                       (dd.p_value IS NOT NULL AND b.valid_from IS NOT NULL AND dd.p_value <= b.valid_from) AS died_before_window
                FROM batch AS b
                LEFT JOIN cast_dates AS bd ON bd.date_string = b.birth_date_raw
                LEFT JOIN cast_dates AS dd ON dd.date_string = b.death_date_raw
            ),
            described AS (
                SELECT c.*,
                       format('%2$s %%s%%s', quote_literal(c.unit_name), CASE WHEN c.ident_label IS NULL THEN '' ELSE ' (' || c.ident_label || ')' END) AS unit_text,
                       c.valid_from::TEXT || ' to ' || CASE WHEN c.valid_to = 'infinity'::date THEN 'infinity' ELSE c.valid_to::TEXT END
                           || ' (valid until ' || CASE WHEN c.valid_until = 'infinity'::date THEN 'infinity' ELSE c.valid_until::TEXT END || ')' AS window_text
                FROM checked AS c
            ),
            messages AS (
                SELECT d.row_id,
                       d.born_after_window,
                       d.died_before_window,
                       CASE WHEN d.born_after_window THEN
                           'Row ' || d.row_id || ': ' || d.unit_text || ' was born ' || d.birth_date::TEXT
                           || ', on or after the end of this row''s validity period ' || d.window_text
                           || ', so the unit cannot exist in that period. Correct the birth date or the period.'
                       END AS birth_message,
                       CASE WHEN d.died_before_window THEN
                           'Row ' || d.row_id || ': ' || d.unit_text || ' died ' || d.death_date::TEXT
                           || ', on or before the start of this row''s validity period ' || d.window_text
                           || ', so the unit cannot exist in that period. Correct the death date or the period.'
                       END AS death_message
                FROM described AS d
            )
            UPDATE public.%1$I AS dt SET
                state = CASE
                            WHEN m.born_after_window OR m.died_before_window THEN 'error'::public.import_data_state
                            ELSE dt.state
                        END,
                action = CASE
                            WHEN m.born_after_window OR m.died_before_window THEN 'skip'::public.import_row_action_type
                            ELSE dt.action
                         END,
                errors = (COALESCE(dt.errors, '{}'::jsonb) - %3$L::TEXT[])
                         || jsonb_strip_nulls(jsonb_build_object(
                                'birth_date_raw', m.birth_message,
                                'valid_to_raw',   m.birth_message,
                                'death_date_raw', m.death_message,
                                'valid_from_raw', m.death_message
                            )),
                last_completed_priority = %6$L
            FROM messages AS m
            WHERE dt.row_id = m.row_id;
        $SQL$,
            v_data_table_name                                                       /* %1$I */,
            v_unit_label                                                            /* %2$s */,
            v_error_keys_arr                                                        /* %3$L */,
            CASE WHEN v_has_name THEN 'NULLIF(trim(dt.name_raw), '''')' ELSE 'NULL::TEXT' END /* %4$s */,
            v_ident_label_expr                                                      /* %5$s */,
            v_step.priority                                                         /* %6$L */
        );
        RAISE DEBUG '[Job %] analyse_date_consistency: batch UPDATE SQL: %', p_job_id, v_sql;

        BEGIN
            EXECUTE v_sql USING p_batch_seq;
            GET DIAGNOSTICS v_update_count = ROW_COUNT;
            RAISE DEBUG '[Job %] analyse_date_consistency: checked % rows in batch_seq %', p_job_id, v_update_count, p_batch_seq;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '[Job %] analyse_date_consistency: error during batch update: %', p_job_id, SQLERRM;
            UPDATE public.import_job
            SET error = jsonb_build_object('analyse_date_consistency_batch_error', SQLERRM)::TEXT,
                state = 'failed'
            WHERE id = p_job_id;
            RETURN;
        END;
    ELSE
        RAISE DEBUG '[Job %] analyse_date_consistency: no birth_date_raw/death_date_raw columns; advancing priority only', p_job_id;
    END IF;

    -- Always advance every row of the batch, including rows already skipped by
    -- an earlier step, so the analysis pipeline cannot loop.
    v_sql := format($adv$
        UPDATE public.%1$I AS dt SET last_completed_priority = %2$L
        WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L
    $adv$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
    EXECUTE v_sql USING p_batch_seq;

    RAISE DEBUG '[Job %] analyse_date_consistency (Batch): Finished for batch_seq %', p_job_id, p_batch_seq;
END;
$procedure$
```
