-- Down Migration: import_length_job_flag
--
-- Reverts:
--   1. Restores the pre-#88 truncate+warn-default procedure body
--      verbatim (captured from \sf at #88 migration-creation time;
--      this is the body that landed in commit 52a69c58b).
--   2. Removes the analyse_length_limits ↔ definition links that
--      this migration's up step inserted. (The step row in
--      public.import_step stays, owned by the prior #84 migration.)
--   3. Drops the truncate_overlong column from public.import_job.
--
-- Note on linkage rollback: this leaves the import_step row
-- registered but unlinked from definitions, matching the pre-#88
-- state where the procedure was effectively dead code. The prior
-- #84 down migration (when invoked) will then delete the step row
-- itself via CASCADE.

BEGIN;

-- ─── 1. Restore the pre-#88 procedure body (verbatim from commit 52a69c58b) ─

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

    -- A single dynamic UPDATE combines all bounded-column checks.
    -- The CASE-per-column lets us reference dt.<col> twice (the
    -- length probe and the rewrite/error build) without splitting
    -- into multiple UPDATE statements.
    v_set_clauses TEXT := '';
    v_warnings_clauses TEXT := '';
    v_errors_clauses TEXT := '';
    v_state_clause TEXT := '';

    v_col RECORD;
    v_n INT;
    v_clause_count INT := 0;
    v_identifier_columns TEXT[] := ARRAY[]::TEXT[];

    -- Hardcoded identifier-fail list per V7 recon: source_input
    -- columns in these steps map to bounded identifier targets
    -- (currently external_ident.ident varchar(50)).  Adding new
    -- bounded identifier targets to the import write surface
    -- requires extending this list.
    v_identifier_fail_steps TEXT[] := ARRAY['external_idents'];
    v_identifier_max_length INT := 50;  -- public.external_ident.ident
BEGIN
    RAISE DEBUG '[Job %] analyse_length_limits (Batch): Starting length checks for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
    WHERE code = p_step_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION '[Job %] analyse_length_limits step (code=%) not found in snapshot', p_job_id, p_step_code;
    END IF;

    FOR v_col IN
        WITH idc AS (
            SELECT
                (entry->>'step_id')::int    AS step_id,
                entry->>'column_name'       AS column_name,
                entry->>'purpose'           AS purpose,
                entry->>'target_pg_type'    AS target_pg_type
            FROM jsonb_array_elements(v_job.definition_snapshot->'import_data_column_list') AS entry
        ),
        steps AS (
            SELECT
                (entry->>'id')::int   AS id,
                entry->>'code'        AS code
            FROM jsonb_array_elements(v_job.definition_snapshot->'import_step_list') AS entry
        )
        SELECT
            idc.column_name,
            idc.purpose,
            idc.target_pg_type,
            s.code AS step_code,
            CASE
                WHEN idc.purpose = 'internal'
                     AND idc.target_pg_type ~ '^character varying\([0-9]+\)$' THEN 'descriptive'
                WHEN idc.purpose = 'source_input'
                     AND s.code = ANY(v_identifier_fail_steps) THEN 'identifier'
                ELSE NULL
            END AS bucket,
            CASE
                WHEN idc.target_pg_type ~ '^character varying\([0-9]+\)$' THEN
                    (regexp_match(idc.target_pg_type, '^character varying\(([0-9]+)\)$'))[1]::INT
                ELSE NULL
            END AS varchar_limit
        FROM idc
        JOIN steps s ON s.id = idc.step_id
        WHERE
            (idc.purpose = 'internal' AND idc.target_pg_type ~ '^character varying\([0-9]+\)$')
            OR (idc.purpose = 'source_input' AND s.code = ANY(v_identifier_fail_steps))
        ORDER BY idc.column_name
    LOOP
        IF v_col.bucket = 'descriptive' THEN
            v_n := v_col.varchar_limit;
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
            v_clause_count := v_clause_count + 1;
        ELSIF v_col.bucket = 'identifier' THEN
            v_n := v_identifier_max_length;
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
            v_identifier_columns := v_identifier_columns || v_col.column_name;
            v_clause_count := v_clause_count + 1;
        END IF;
    END LOOP;

    IF array_length(v_identifier_columns, 1) > 0 THEN
        SELECT string_agg(
            format($cond$length(dt.%1$I) > %2$L$cond$, col, v_identifier_max_length),
            ' OR '
        ) INTO v_state_clause
        FROM unnest(v_identifier_columns) AS col;
    END IF;

    IF v_clause_count = 0 THEN
        RAISE DEBUG '[Job %] analyse_length_limits: no bounded columns in scope for this job; advancing priority only', p_job_id;
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
            COALESCE(NULLIF(v_state_clause, ''), 'FALSE')  /* %6$s — short-circuit if no identifier cols */
        );

        BEGIN
            EXECUTE v_sql USING p_batch_seq;
            GET DIAGNOSTICS v_update_count = ROW_COUNT;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING '[Job %] analyse_length_limits: error during batch update: %', p_job_id, SQLERRM;
            UPDATE public.import_job
            SET error = jsonb_build_object('analyse_length_limits_batch_error', SQLERRM)::TEXT,
                state = 'failed'
            WHERE id = p_job_id;
            RETURN;
        END;
    END IF;

    v_sql := format($adv$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L;
    $adv$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;

    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(
            p_job_id, v_data_table_name, p_batch_seq,
            ARRAY[]::TEXT[],
            'analyse_length_limits'
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_length_limits: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;
END;
$procedure$;


-- ─── 2. Unlink the step from existing definitions ────────────────────────

DELETE FROM public.import_definition_step
WHERE step_id IN (SELECT id FROM public.import_step WHERE code = 'analyse_length_limits');


-- ─── 3. Drop the truncate_overlong column ────────────────────────────────

ALTER TABLE public.import_job
    DROP COLUMN IF EXISTS truncate_overlong;

END;
