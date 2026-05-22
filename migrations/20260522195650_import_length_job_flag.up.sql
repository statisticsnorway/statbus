-- Migration: import_length_job_flag
--
-- Adds the `truncate_overlong` boolean opt-in flag to public.import_job
-- and rewrites import.analyse_length_limits to branch on it.
--
-- Background:
--   Commit 52a69c58b landed import.analyse_length_limits with a
--   policy of "descriptive columns truncate+warn; identifier
--   columns error". Architect+King review reversed that default:
--   the safer policy is "ANY overflow → error" (no silent
--   truncation, no quiet data drift). Operators who genuinely
--   want truncate behavior opt in per-job via the new flag.
--
--   This migration:
--     1. Adds the column with DEFAULT FALSE (strict-mode default).
--     2. Fixes a missed linkage from 52a69c58b: the
--        analyse_length_limits step was registered in import_step
--        but NOT linked to existing definitions via
--        import_definition_step — so the procedure never ran in
--        practice. Surface 347's C5 (Albania 500-char) caught
--        this on first fast-suite run (state='failed' with the
--        original 22001 overflow). Fixed here because the strict-
--        mode rewrite needs the procedure to actually run for it
--        to be observable.
--     3. CREATE OR REPLACE PROCEDURE with IF/ELSE wrapping the
--        existing landed truncate+warn logic in the truncate
--        branch; new strict logic in the else branch.
--
-- Identifier columns (currently external_ident.ident varchar(50))
-- always error on overflow regardless of flag — truncating an
-- identifier would silently change the operator's primary key.

BEGIN;

-- ─── 1. Add the truncate_overlong column ─────────────────────────────────

ALTER TABLE public.import_job
    ADD COLUMN truncate_overlong boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.import_job.truncate_overlong IS
'When true, descriptive columns exceeding their target varchar(N) length
are truncated to N and a warning is recorded in dt.warnings. When false
(default), any overlong descriptive value causes dt.state=error +
dt.errors entry. Identifier columns (external_ident.ident) ALWAYS error
on overflow regardless of this flag — identifier truncation would
silently change the operator''s primary key.';


-- ─── 2. Link the step to every existing definition ───────────────────────

-- See migration header for context. ON CONFLICT DO NOTHING so a future
-- redo of this migration on a partially-applied DB is idempotent.
INSERT INTO public.import_definition_step (definition_id, step_id)
SELECT d.id, s.id
FROM public.import_definition d
CROSS JOIN public.import_step s
WHERE s.code = 'analyse_length_limits'
ON CONFLICT (definition_id, step_id) DO NOTHING;


-- ─── 3. Rewrite import.analyse_length_limits with IF/ELSE branching ──────

-- Architecture: a single per-batch UPDATE assembled dynamically.
-- The bounded-column iteration is shared; only the per-column
-- clause-emit shape changes per branch.
--
--   IF v_truncate_overlong THEN
--     descriptive cols → truncate+warn (existing landed logic)
--     identifier cols  → error
--   ELSE
--     descriptive cols → error (strict default)
--     identifier cols  → error (unchanged)
--
-- Identifiers always error regardless of flag. The strict branch's
-- per-column shape converges with the identifier-always-error shape
-- — both emit `errors = errors || jsonb_build_object(col, {too_long, limit})`.
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
    -- state='error' decision). Encoded as 'colname:N' strings so we
    -- can rebuild the length-probe later without re-iterating the
    -- snapshot.
    v_error_columns TEXT[] := ARRAY[]::TEXT[];

    -- Hardcoded identifier-fail list per V7 recon: source_input
    -- columns in these steps map to bounded identifier targets
    -- (currently external_ident.ident varchar(50)).
    v_identifier_fail_steps TEXT[] := ARRAY['external_idents'];
    v_identifier_max_length INT := 50;  -- public.external_ident.ident
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

    -- Iterate bounded columns from the definition snapshot. Two buckets:
    --   1. Descriptive — internal-purpose columns whose target_pg_type
    --      matches `character varying(N)`.
    --   2. Identifier — source_input columns in the identifier-fail
    --      steps (currently external_idents; cap = 50).
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
            v_clause_count := v_clause_count + 1;
        ELSIF v_col.bucket = 'identifier' THEN
            v_n := v_identifier_max_length;
            -- Identifiers ALWAYS error regardless of flag — truncating
            -- an identifier silently changes the operator's PK.
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
            v_clause_count := v_clause_count + 1;
        END IF;
    END LOOP;

    -- state clause: 'error' iff ANY error-emitting column overflowed.
    -- In strict mode: descriptives + identifiers.
    -- In truncate mode: identifiers only.
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
$procedure$;


COMMENT ON PROCEDURE import.analyse_length_limits(integer, integer, text) IS
'Intercepts overlong text values before they reach process-step MERGEs.
Branches on public.import_job.truncate_overlong:
  - false (default): ANY overflow on a bounded column → dt.state=error,
    dt.errors entry. No truncation.
  - true (opt-in): descriptive overflows truncated to target length
    with dt.warnings entry; identifier overflows still error.
Identifier overflows (external_ident.ident varchar(50)) ALWAYS error
regardless of flag — truncating an identifier would silently change
the operator''s primary key.';

END;
