-- Migration: length_limits_priority_and_rename
--
-- King's code review feedback on import-length-analyse-step. THREE
-- coupled corrections — all needed together, because moving the step
-- to priority 11 invalidates the prior procedure body's assumptions:
--
-- 1. Priority 105 → 11. Length-limits is a SYNTACTIC validation —
--    no FK lookups, no business resolution. At priority 105
--    (second-to-last of 21 steps), every import row burned CPU
--    through ~16 intermediate steps (external_idents at 15,
--    data_source at 16, status at 17, enterprise links at 18-19,
--    legal_relationship + legal_unit + establishment at 20-21,
--    location at 30-40, etc.) before a rejection that could have
--    been issued upfront.
--
--    Cluster with valid_time (the only other purely-syntactic
--    step, priority 10): length_limits at 11. Lookups start at 15
--    (external_idents) — every step at >=15 now runs ONLY on rows
--    that already passed the cheap syntactic gates.
--
-- 2. Step code `analyse_length_limits` → `length_limits`. Every
--    other step in public.import_step uses the bare-noun convention
--    (`valid_time`, `data_source`, `edit_info`, `metadata`,
--    `external_idents`, `legal_unit`, `physical_location`, etc.) —
--    no `analyse_` or `process_` prefix on the step code. The
--    redundant `analyse_` prefix was engineer's defensive naming.
--
--    The PROCEDURE name `import.analyse_length_limits` stays —
--    already conforms to the `import.analyse_<step_code>`
--    convention used by every other analyse procedure.
--
-- 3. Procedure body must be reworked for the new priority slot.
--    The pre-existing body assumed priority 105 (after
--    analyse_<step> populated internal columns from `_raw`). At
--    priority 11 two assumptions break:
--
--    a. **Data location.** At priority 11 the internal columns
--       (e.g. `physical_address_part1`) are still NULL —
--       `analyse_location` (priority 30) populates them later from
--       `_raw`. Reading the internal column at priority 11 yields
--       NULL, the truncate/error CASE never fires, downstream
--       `analyse_location` copies the full overlong `_raw` into
--       the internal column, and `process_location` MERGE raises
--       22001 (the canonical Albania bug).
--
--       Fix: read AND write the `<col>_raw` counterpart (the
--       source-of-truth at priority 11). The bound (varchar(N))
--       describes the eventual internal destination, so warnings
--       and errors are still keyed by the BARE INTERNAL column
--       name — that is the operator-meaningful destination.
--       Downstream `analyse_location` then reads the trimmed
--       `_raw` and copies it to the internal column; the MERGE
--       fits cleanly.
--
--    b. **State stickiness across downstream steps.** Each
--       `analyse_<step>` "owns" `state` for its scope:
--           state = CASE WHEN <own_error> THEN 'error' ELSE 'analysing' END
--       and `analyse_external_idents` additionally CLEARS the
--       identifier error keys (`tax_ident_raw`, `stat_ident_raw`,
--       `person_ident_raw`) before recomputing. Length_limits
--       errors set at priority 11 were silently wiped by these
--       downstream steps — by process phase the row looked clean.
--
--       Fix: when length_limits sets `state='error'`, ALSO set
--       `action='skip'`. Every downstream analyse_* and process_*
--       step already filters `WHERE action IS DISTINCT FROM 'skip'`.
--       This is the same convention
--       `propagate_fatal_error_to_entity_batch` uses for "this row
--       is hard-rejected; do not touch it." The error key survives
--       because downstream simply doesn't process the row.

BEGIN;

-- Step row update: single UPDATE so the row is never in a
-- half-renamed half-repriotitized state visible to concurrent
-- readers (worker queue, definition_snapshot builds).
UPDATE public.import_step
SET code = 'length_limits',
    priority = 11
WHERE code = 'analyse_length_limits';

-- Sanity check: the renamed step must exist with the new code, the
-- new priority, and no stale row at the old code.
DO $assert$
DECLARE
    v_new_count INTEGER;
    v_old_count INTEGER;
    v_new_priority INTEGER;
BEGIN
    SELECT count(*) INTO v_new_count FROM public.import_step WHERE code = 'length_limits';
    SELECT count(*) INTO v_old_count FROM public.import_step WHERE code = 'analyse_length_limits';
    SELECT priority INTO v_new_priority FROM public.import_step WHERE code = 'length_limits';

    IF v_new_count != 1 THEN
        RAISE EXCEPTION 'length_limits_priority_and_rename: expected exactly 1 row with code=length_limits, got %', v_new_count;
    END IF;
    IF v_old_count != 0 THEN
        RAISE EXCEPTION 'length_limits_priority_and_rename: % stale rows with old code=analyse_length_limits remain', v_old_count;
    END IF;
    IF v_new_priority != 11 THEN
        RAISE EXCEPTION 'length_limits_priority_and_rename: expected priority=11, got %', v_new_priority;
    END IF;
END;
$assert$;

-- import_definition_step rows reference import_step.id (an integer
-- PK), not the code. So the rename above propagates automatically
-- via the FK — no explicit link-table UPDATE needed.

-- Procedure body rewritten for priority 11 (see header comment §3).
-- Atomic with the priority change: an operator that migrates up to
-- this version gets a procedure that WORKS at priority 11, and a
-- migrate-down restores the priority-105-shaped body.
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
    v_raw_col TEXT;       -- name of the `_raw` counterpart for internal cols

    -- Columns that emit `errors` entries (and contribute to the
    -- state='error' decision). Encoded as 'colname:N' strings; colname
    -- here is the column actually READ by the state-clause length()
    -- probe (so for internal it must be the _raw counterpart).
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
    -- is driven by (purpose, target_pg_type):
    --   - purpose='internal' + target_pg_type matches varchar(N)
    --     → descriptive (truncate or error per flag). At length_limits
    --       priority (11) the internal column is still NULL — actual
    --       data lives in the `<col>_raw` source_input counterpart, so
    --       we read/write that. Downstream `analyse_<step>` (priority
    --       30+) then copies the trimmed `_raw` into the internal.
    --       Warnings/errors are keyed by the INTERNAL column name (the
    --       operator-meaningful destination, what the bound describes).
    --   - purpose='source_input' + target_pg_type matches varchar(N)
    --     → identifier bucket (e.g. tax_ident_raw): always error.
    --       column_name is already the `_raw` name; error key matches.
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
            v_raw_col := v_col.column_name || '_raw';
            IF v_truncate_overlong THEN
                -- TRUNCATE branch (opt-in): rewrite _raw + warning.
                v_set_clauses := v_set_clauses || format(
                    $clause$,
                %1$I = CASE
                    WHEN length(dt.%1$I) > %2$L THEN substring(dt.%1$I FROM 1 FOR %2$L)
                    ELSE dt.%1$I
                END$clause$,
                    v_raw_col         /* %1$I — read AND write the _raw column */,
                    v_n               /* %2$L */
                );
                v_warnings_clauses := v_warnings_clauses || format(
                    $clause$ || CASE
                        WHEN length(dt.%1$I) > %2$L THEN
                            jsonb_build_object(%3$L, jsonb_build_object('truncated_from', length(dt.%1$I), 'to', %2$L))
                        ELSE '{}'::jsonb
                    END$clause$,
                    v_raw_col         /* %1$I — probe _raw */,
                    v_n               /* %2$L */,
                    v_col.column_name /* %3$L — warning keyed by internal col name */
                );
            ELSE
                -- STRICT branch (default): hard-fail on overflow.
                v_errors_clauses := v_errors_clauses || format(
                    $clause$ || CASE
                        WHEN length(dt.%1$I) > %2$L THEN
                            jsonb_build_object(%3$L, jsonb_build_object('too_long', length(dt.%1$I), 'limit', %2$L))
                        ELSE '{}'::jsonb
                    END$clause$,
                    v_raw_col         /* %1$I — probe _raw */,
                    v_n               /* %2$L */,
                    v_col.column_name /* %3$L — error keyed by internal col name */
                );
                v_error_columns := v_error_columns || ARRAY[v_raw_col || ':' || v_n::TEXT];
            END IF;
        ELSE
            -- purpose='source_input': identifier bucket — ALWAYS error.
            -- Truncating an identifier silently changes the operator's PK.
            -- column_name IS the `_raw` name; error key matches read column.
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
        -- Note: action='skip' alongside state='error' is the convention
        -- from propagate_fatal_error_to_entity_batch — it tells all
        -- downstream analyse_* and process_* steps "this row is
        -- hard-rejected; do not touch it." Without action='skip',
        -- analyse_external_idents (priority 15) would clear our
        -- identifier error keys, and every downstream analyse_<step>
        -- would reset state='error' back to 'analysing' because it
        -- doesn't see its own error.
        v_sql := format($update$
            UPDATE public.%1$I dt
            SET
                last_completed_priority = %2$L::INTEGER%3$s,
                warnings = COALESCE(dt.warnings, '{}'::jsonb) %4$s,
                errors   = COALESCE(dt.errors,   '{}'::jsonb) %5$s,
                state    = CASE
                               WHEN (%6$s) THEN 'error'::public.import_data_state
                               ELSE dt.state
                           END,
                action   = CASE
                               WHEN (%6$s) THEN 'skip'::public.import_row_action_type
                               ELSE dt.action
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
$procedure$;

END;
