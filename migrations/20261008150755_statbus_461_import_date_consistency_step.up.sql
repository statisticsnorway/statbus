-- Migration 20261008150755: statbus_461 import date_consistency step
--
-- STATBUS-461: a unit's life must overlap the validity period of every record
-- that claims it. Owner decision 2026-10-07: if a unit has a birth date and is
-- not yet born, it does not yet exist, so a record for it must not be accepted.
--
-- THE RULE (overlap, NOT containment). A row is rejected iff the intersection
-- of the unit's life and the row's period [valid_from, valid_until) is empty:
--   birth_date >= valid_until   (born on or after the period ends), or
--   death_date <= valid_from    (died on or before the period starts).
-- birth_date > valid_from (born inside the period) and death_date < valid_until
-- (died inside the period) stay legal. This is the import-side counterpart of
-- the STATBUS-460 existence rule used for counting.
--
-- MECHANISM. A new analyse-only import step, date_consistency, raises a HARD
-- row error (doc/import-system.md, 'Error Handling Rule for Analysis
-- Procedures'): errors gets keys that are real source_input column names
-- (birth_date_raw + valid_to_raw for a birth after the period, death_date_raw +
-- valid_from_raw for a death before it, the same message repeated under each),
-- state = 'error', action = 'skip'. Processing only touches action = 'use'
-- rows, so the offending ROW is not imported while the rest of the file is, and
-- the job still finishes. The step clears only its own keys when the condition
-- no longer holds.
--
-- PLACEMENT: priority 12, after valid_time (10, which derives valid_from and
-- valid_until for both source_columns and job_provided definitions) and
-- length_limits (11), BEFORE external_idents (15). The step casts the raw
-- birth/death strings itself with import.safe_cast_to_date, the same cast the
-- core unit step uses at priority 20. Running after the core step was
-- prototyped and rejected: external_idents assigns founding_row_id per new
-- unit, and skipping a group's founding row after that leaves its valid
-- siblings pointing at a founder that is never processed (no enterprise is
-- created, process_legal_unit fails the whole batch on a NULL enterprise_id).
-- Rejecting before external_idents lets the valid sibling become the founder.
--
-- LINKED to every definition that imports units (has the legal_unit or the
-- establishment step), both source_columns and job_provided kinds. Generic
-- stats updates and legal relationships carry no birth/death columns.
--
-- ALSO FIXED (found by this ticket's test, case 15): import.analyse_valid_time
-- stored valid_until for a strictly inverted period (valid_from > valid_to + 1)
-- before marking the row as an error. The _data table's GIST index on
-- daterange(valid_from, valid_until) then raised 'range lower bound must be
-- less than or equal to range upper bound', failing the whole batch and
-- importing nothing. valid_until is now left NULL for such a row, which keeps
-- the existing 'Resulting period is invalid' error and skips only that row.

BEGIN;

CREATE OR REPLACE PROCEDURE import.analyse_valid_time(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['valid_from_raw', 'valid_to_raw'];
BEGIN
    RAISE DEBUG '[Job %] analyse_valid_time (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    -- Get job details
    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    -- Find the step details from the snapshot
    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'valid_time';
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] valid_time step not found in snapshot', p_job_id;
    END IF;

    -- Create a temporary table to hold batch data. This ensures subsequent operations are on a small dataset.
    IF to_regclass('pg_temp.t_batch_data') IS NOT NULL THEN DROP TABLE t_batch_data; END IF;
    CREATE TEMP TABLE t_batch_data (
        row_id integer PRIMARY KEY,
        valid_from TEXT,
        valid_to TEXT
    ) ON COMMIT DROP;

    -- Populate the temp table filtering by batch_seq.
    EXECUTE format(
        'INSERT INTO t_batch_data (row_id, valid_from, valid_to) SELECT dt.row_id, dt.valid_from_raw, dt.valid_to_raw FROM public.%I dt WHERE dt.batch_seq = $1',
        v_data_table_name
    ) USING p_batch_seq;

    ANALYZE t_batch_data; -- Provide stats for the planner.

    -- Single-pass batch update for casting, state, error, and priority
    v_sql := format($SQL$
        WITH
        -- Step 1: Get the raw text dates for the current batch of rows from the temp table.
        batch_data_cte AS (
            SELECT row_id, valid_from, valid_to FROM t_batch_data
        ),
        -- Step 2: Find all unique non-empty date strings within the batch.
        distinct_dates_cte AS (
            SELECT valid_from AS date_string FROM batch_data_cte WHERE NULLIF(valid_from, '') IS NOT NULL
            UNION
            SELECT valid_to AS date_string FROM batch_data_cte WHERE NULLIF(valid_to, '') IS NOT NULL
        ),
        -- Step 3: Call the casting function ONLY for the unique date strings.
        casted_distinct_dates_cte AS MATERIALIZED (
            SELECT
                dd.date_string,
                sc.p_value,
                sc.p_error_message
            FROM distinct_dates_cte dd
            LEFT JOIN LATERAL import.safe_cast_to_date(dd.date_string) AS sc ON TRUE
        ),
        -- Step 4: Re-assemble the casted values for each row by joining back to the batch data.
        final_cast_cte AS (
            SELECT
                bd.row_id,
                vf.p_value AS casted_vf,
                vf.p_error_message AS vf_error_msg,
                vt.p_value AS casted_vt,
                vt.p_error_message AS vt_error_msg,
                (CASE WHEN vt.p_value = 'infinity'::date THEN 'infinity'::date ELSE vt.p_value + INTERVAL '1 day' END) AS casted_vu,
                bd.valid_from AS original_vf,
                bd.valid_to AS original_vt
            FROM batch_data_cte bd
            LEFT JOIN casted_distinct_dates_cte vf ON bd.valid_from = vf.date_string
            LEFT JOIN casted_distinct_dates_cte vt ON bd.valid_to = vt.date_string
        )
        UPDATE public.%1$I dt SET
            valid_from = fcc.casted_vf,
            valid_to = fcc.casted_vt,
            -- STATBUS-461: an inverted period (valid_from > valid_until) cannot be
            -- stored as-is, because the _data table's GIST index on
            -- daterange(valid_from, valid_until) raises 'range lower bound must be
            -- less than or equal to range upper bound' and fails the WHOLE batch.
            -- Leave valid_until NULL for such a row; it is rejected below with the
            -- 'Resulting period is invalid' error and skipped like any other.
            valid_until = CASE
                              WHEN fcc.casted_vf IS NOT NULL AND fcc.casted_vu IS NOT NULL AND fcc.casted_vf > fcc.casted_vu THEN NULL
                              ELSE fcc.casted_vu
                          END,
            state = CASE
                        WHEN NULLIF(fcc.original_vf, '') IS NULL OR fcc.vf_error_msg IS NOT NULL OR
                             NULLIF(fcc.original_vt, '') IS NULL OR fcc.vt_error_msg IS NOT NULL OR
                             (fcc.casted_vf IS NOT NULL AND fcc.casted_vu IS NOT NULL AND fcc.casted_vf >= fcc.casted_vu)
                        THEN 'error'::public.import_data_state
                        ELSE
                            CASE
                                WHEN dt.state = 'error'::public.import_data_state THEN 'error'::public.import_data_state
                                ELSE 'analysing'::public.import_data_state
                            END
                    END,
            action = CASE
                        WHEN NULLIF(fcc.original_vf, '') IS NULL OR fcc.vf_error_msg IS NOT NULL OR
                             NULLIF(fcc.original_vt, '') IS NULL OR fcc.vt_error_msg IS NOT NULL OR
                             (fcc.casted_vf IS NOT NULL AND fcc.casted_vu IS NOT NULL AND fcc.casted_vf >= fcc.casted_vu)
                        THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                     END,
            errors = CASE
                        WHEN NULLIF(fcc.original_vf, '') IS NULL THEN
                            dt.errors || jsonb_build_object('valid_from_raw', 'Missing mandatory value')
                        WHEN fcc.vf_error_msg IS NOT NULL THEN
                            dt.errors || jsonb_build_object('valid_from_raw', fcc.vf_error_msg)
                        WHEN NULLIF(fcc.original_vt, '') IS NULL THEN
                            dt.errors || jsonb_build_object('valid_to_raw', 'Missing mandatory value')
                        WHEN fcc.vt_error_msg IS NOT NULL THEN
                            dt.errors || jsonb_build_object('valid_to_raw', fcc.vt_error_msg)
                        WHEN fcc.casted_vf IS NOT NULL AND fcc.casted_vu IS NOT NULL AND (fcc.casted_vf >= fcc.casted_vu) THEN
                            dt.errors || jsonb_build_object(
                                'valid_from_raw', 'Resulting period is invalid: valid_from (' || fcc.casted_vf::TEXT || ') must be before valid_until (' || fcc.casted_vu::TEXT || ')',
                                'valid_to_raw',   'Resulting period is invalid: valid_from (' || fcc.casted_vf::TEXT || ') must be before valid_until (' || fcc.casted_vu::TEXT || ')'
                            )
                        ELSE
                            dt.errors - %2$L::TEXT[]
                    END,
            last_completed_priority = %3$L
        FROM final_cast_cte fcc
        WHERE dt.row_id = fcc.row_id;
    $SQL$,
        v_data_table_name,             -- %1$I
        v_error_keys_to_clear_arr,     -- %2$L
        v_step.priority                -- %3$L
    );
    RAISE DEBUG '[Job %] analyse_valid_time: Single-pass batch update for non-skipped rows: %', p_job_id, v_sql;

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_valid_time: Updated % non-skipped rows in single pass.', p_job_id, v_update_count;

        -- Estimate error count
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        RAISE DEBUG '[Job %] analyse_valid_time: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql
        INTO v_error_count
        USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_valid_time: Estimated errors in this step for batch: %', p_job_id, v_error_count;

    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_valid_time: Error during single-pass batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job
        SET error = jsonb_build_object('analyse_valid_time_batch_error', SQLERRM)::TEXT,
            state = 'failed'
        WHERE id = p_job_id;
        RAISE DEBUG '[Job %] analyse_valid_time: Marked job as failed due to error: %', p_job_id, SQLERRM;
        -- Don't re-raise - job is marked as failed
    END;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, 'analyse_valid_time');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_valid_time: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_valid_time (Batch): Finished analysis for batch. Errors newly marked in this step: %', p_job_id, v_error_count;
END;
$procedure$
;

CREATE OR REPLACE PROCEDURE import.analyse_date_consistency(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $analyse_date_consistency$
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
$analyse_date_consistency$;

INSERT INTO public.import_step (code, name, priority, analyse_procedure, process_procedure, is_holistic)
VALUES ('date_consistency', 'Unit Life Overlaps Record Period', 12, 'import.analyse_date_consistency'::regproc, NULL, false);

-- Link to every definition that imports units. Derived from the definitions'
-- own step links (a fixed rule, not an aggregate), so a full replay and an
-- incrementally migrated box get the same links.
INSERT INTO public.import_definition_step (definition_id, step_id)
SELECT DISTINCT ds.definition_id, dc.id
FROM public.import_definition_step AS ds
JOIN public.import_step AS s ON s.id = ds.step_id
CROSS JOIN (SELECT id FROM public.import_step WHERE code = 'date_consistency') AS dc
WHERE s.code IN ('legal_unit', 'establishment')
ON CONFLICT (definition_id, step_id) DO NOTHING;

END;
