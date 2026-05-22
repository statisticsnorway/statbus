-- Migration: add_import_analyse_length_limits
--
-- Second piece of the import-length-truncate-warn campaign
-- (foundation: backfill_import_data_column_target_pg_type; tests:
-- forthcoming N_import_field_length_limits.sql).
--
-- Background:
--   Before this migration, overlong text values in the import _data
--   table flowed all the way to the process step's MERGE into public.*
--   tables, where they hit a varchar(N) check and aborted the entire
--   batch with `22001 string_data_right_truncation`. The
--   import.process_location:184-194 exception handler caught it and
--   re-threw, killing the whole import job for ONE overlong field
--   in ONE row. Albania-shaped 500-char addresses are the canonical
--   failure case.
--
-- This migration adds an analyse step that intercepts overlong
-- values BEFORE the MERGE:
--   - Descriptive columns (legal_unit.name, location.address_*,
--     contact.email_address, etc) → truncate to target length +
--     record a warning in dt.warnings. Row stored cleanly, MERGE
--     proceeds, operator sees the warning post-import.
--   - Identifier columns (external_ident.ident, currently the only
--     bounded write-surface identifier per V7 recon) → hard-fail:
--     set dt.state='error', record in dt.errors, row NOT UPSERTed.
--     Identifier truncation would silently change the operator's
--     primary key — that's a data-corruption pathway, hence the
--     hard-fail bucket.
--
-- The procedure is registered as a new import_step at priority 105:
--   - AFTER all analyse procedures (max analyse priority = 100,
--     edit_info)
--   - BEFORE the metadata step (110, no procedures)
--   - In the analysis phase (analyse_procedure set,
--     process_procedure NULL) — runs after all other analyses
--     populate the internal columns, before any process step
--     reads them for MERGE.

BEGIN;

-- ─── Procedure: import.analyse_length_limits ─────────────────────────────

CREATE OR REPLACE PROCEDURE import.analyse_length_limits(
    IN p_job_id integer,
    IN p_batch_seq integer,
    IN p_step_code text
)
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

    -- Build SET clauses by iterating bounded columns from the
    -- definition snapshot. Two buckets:
    --   1. Descriptive — internal-purpose columns whose target_pg_type
    --      matches `character varying(N)`. Truncate + warning.
    --   2. Identifier — source_input columns in the identifier-fail
    --      steps. Hard-fail at v_identifier_max_length.
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
                -- Descriptive bucket: internal + bounded varchar
                WHEN idc.purpose = 'internal'
                     AND idc.target_pg_type ~ '^character varying\([0-9]+\)$' THEN 'descriptive'
                -- Identifier-fail bucket: source_input in identifier steps
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
            -- Only buckets we care about
            (idc.purpose = 'internal' AND idc.target_pg_type ~ '^character varying\([0-9]+\)$')
            OR (idc.purpose = 'source_input' AND s.code = ANY(v_identifier_fail_steps))
        ORDER BY idc.column_name
    LOOP
        IF v_col.bucket = 'descriptive' THEN
            v_n := v_col.varchar_limit;
            -- Truncate: SET col = CASE WHEN over THEN substring ELSE col END
            v_set_clauses := v_set_clauses || format(
                $clause$,
            %1$I = CASE
                WHEN length(dt.%1$I) > %2$L THEN substring(dt.%1$I FROM 1 FOR %2$L)
                ELSE dt.%1$I
            END$clause$,
                v_col.column_name /* %1$I */,
                v_n               /* %2$L */
            );
            -- Append warning entry if over
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
            -- Hard-fail: dt.<col> unchanged; dt.errors gets entry;
            -- dt.state set to 'error' if any identifier overflows.
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

    -- Build the state clause: 'error' iff ANY identifier column
    -- overflowed. NULL when no identifier columns in scope —
    -- caller's COALESCE handles that to a literal FALSE.
    IF array_length(v_identifier_columns, 1) > 0 THEN
        SELECT string_agg(
            format($cond$length(dt.%1$I) > %2$L$cond$, col, v_identifier_max_length),
            ' OR '
        ) INTO v_state_clause
        FROM unnest(v_identifier_columns) AS col;
    END IF;

    -- Early return if no bounded columns in scope (e.g. a definition
    -- that excludes legal_unit / contact / location / external_idents).
    -- Just advance priority and exit.
    IF v_clause_count = 0 THEN
        RAISE DEBUG '[Job %] analyse_length_limits: no bounded columns in scope for this job; advancing priority only', p_job_id;
    ELSE
        -- Assemble the dynamic UPDATE.
        --   SET <truncations>,
        --       warnings = dt.warnings <warning chain>,
        --       errors   = dt.errors   <error chain>,
        --       state    = CASE WHEN <state clause> THEN 'error' ELSE dt.state END,
        --       last_completed_priority = <priority>
        --   WHERE batch_seq = $1 AND action IS DISTINCT FROM 'skip'
        --
        -- Note: v_set_clauses starts with ', ' (its own format),
        -- so we can splice it directly after `SET <last_completed_priority>`.
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

    -- Unconditionally advance priority for all rows in batch to ensure
    -- progress, mirroring the analyse_status pattern. Catches the
    -- empty-clauses branch above + any rows that were 'skip'.
    v_sql := format($adv$
        UPDATE public.%1$I dt SET
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L;
    $adv$, v_data_table_name /* %1$I */, v_step.priority /* %2$L */);
    EXECUTE v_sql USING p_batch_seq;
    GET DIAGNOSTICS v_skipped_update_count = ROW_COUNT;
    RAISE DEBUG '[Job %] analyse_length_limits: Advanced last_completed_priority for % total rows in batch', p_job_id, v_skipped_update_count;

    -- Propagate identifier errors to other rows of the same entity
    -- (best-effort, matches analyse_status pattern).
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(
            p_job_id, v_data_table_name, p_batch_seq,
            ARRAY[]::TEXT[],  -- no specific keys to clear; we only set errors here
            'analyse_length_limits'
        );
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_length_limits: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_length_limits (Batch): Finished for batch_seq %', p_job_id, p_batch_seq;
END;
$procedure$;

COMMENT ON PROCEDURE import.analyse_length_limits(integer, integer, text) IS
'Intercepts overlong text values before they reach the process step''s
MERGE into public.* tables. Descriptive overflows (legal_unit.name,
location.address_*, contact.*, etc) are truncated to their target
length with a warning recorded in dt.warnings. Identifier overflows
(currently external_ident.ident only, varchar(50)) hard-fail: row
state set to error, no UPSERT to public.external_ident. Reads
target_pg_type from import_data_column to know each column''s
bounded length — populated by the companion migration
backfill_import_data_column_target_pg_type.';


-- ─── Register the step ───────────────────────────────────────────────────

-- Priority 105: between edit_info (100, last analyse) and metadata
-- (110, no procedures). Analysis phase iterates steps in priority
-- order (see admin.import_job_analysis_phase), so this slot ensures
-- length_limits runs AFTER all other analyses have populated the
-- internal columns and BEFORE any process step's MERGE.
INSERT INTO public.import_step
    (code, name, priority, analyse_procedure, process_procedure, is_holistic)
VALUES
    ('analyse_length_limits',
     'Field Length Limits',
     105,
     'import.analyse_length_limits'::regproc,
     NULL,
     false)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    priority = EXCLUDED.priority,
    analyse_procedure = EXCLUDED.analyse_procedure,
    process_procedure = EXCLUDED.process_procedure,
    is_holistic = EXCLUDED.is_holistic;

END;
