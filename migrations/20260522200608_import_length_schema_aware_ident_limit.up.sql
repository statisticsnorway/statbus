-- Migration: import_length_schema_aware_ident_limit
--
-- Architect review of the landed import-length campaign
-- (commits 050443c32 / 52a69c58b / ebec4793b / 9aab392ca) flagged
-- two improvements:
--
-- Finding A (medium, latent): the procedure hardcodes
--   v_identifier_fail_steps := ARRAY['external_idents']
--   v_identifier_max_length := 50
-- and applies the 50-char limit to ALL source_input columns in the
-- external_idents step. But external_ident has TWO targets per its
-- shape_data_consistency constraint:
--   - ident   (varchar(50))  ← source_input target for shape='regular'
--   - idents  (ltree)        ← source_input target for shape='hierarchical'
-- For hierarchical types (active in production for clients with
-- classification trees), the 50-char limit is wrong — LTREE has its
-- own length constraints (256 bytes per label, much longer overall).
--
-- The principled fix: derive each column's bound from target_pg_type
-- (the source of truth populated by import-length-target-fill) so the
-- procedure is schema-aware, matching how the descriptive-bucket
-- iteration already works. This means:
--   - For external_idents source_input rows the GENERATOR must set
--     target_pg_type properly per shape (this migration does the
--     generator update + backfill).
--   - The PROCEDURE then drops the hardcoded constants and treats
--     any source_input column with target_pg_type ~ 'character
--     varying(N)' as an identifier-error bucket, length=N. LTREE
--     and other types fall outside the check.
--
-- Finding B (minor test coverage): test 347's C5 (Albania 500-char)
-- shows the row stores correctly, but with only ONE row in the job
-- it does NOT demonstrate the headline bug — that ONE bad row in a
-- batch killed the WHOLE batch. New C12 case asserts: 3 good +
-- 1 overlong → 3 stored + 1 errored + job state='finished'.

BEGIN;

-- ─── 1. Update generator: target_pg_type per shape ───────────────────────

-- Regular external_ident_type → source_input column maps to
-- external_ident.ident (varchar(50)).
-- Hierarchical external_ident_type → source_input column maps to
-- external_ident.idents (ltree).
--
-- Both share the existing `_raw` source_input shape; only the
-- target_pg_type assignment changes.
CREATE OR REPLACE PROCEDURE import.generate_external_ident_data_columns()
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_step_id INT;
    v_ident_type RECORD;
    v_base_priority INT;
    v_active_codes TEXT[];
    v_calculated_priority INT;
    v_slot_base INT;
    v_label TEXT;
    v_label_index INT;
    v_num_labels INT;
    v_labels_array TEXT[];
BEGIN
    SELECT id INTO v_step_id FROM public.import_step WHERE code = 'external_idents';
    IF v_step_id IS NULL THEN
        RAISE EXCEPTION 'external_idents step not found, cannot generate data columns.';
        RETURN;
    END IF;

    SELECT array_agg(code ORDER BY priority) INTO v_active_codes FROM public.external_ident_type_enabled;
    RAISE DEBUG '[import.generate_external_ident_data_columns] For step_id % (external_idents), ensuring data columns for active codes: %', v_step_id, v_active_codes;

    -- Get the highest priority among non-dynamic columns (those without purpose='source_input' and 'internal')
    SELECT COALESCE(MAX(idc.priority), 0) INTO v_base_priority
    FROM public.import_data_column idc
    WHERE idc.step_id = v_step_id
      AND idc.purpose NOT IN ('source_input', 'internal');

    FOR v_ident_type IN
        SELECT code, priority, shape, labels
        FROM public.external_ident_type_enabled
        ORDER BY priority
    LOOP
        IF v_ident_type.shape = 'regular' THEN
            -- Regular: source_input maps to external_ident.ident (varchar(50))
            v_calculated_priority := v_base_priority + 2 + v_ident_type.priority;

            INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority, target_pg_type)
            VALUES (v_step_id, v_ident_type.code || '_raw', 'TEXT', 'source_input', true, true, v_calculated_priority, 'character varying(50)')
            ON CONFLICT (step_id, column_name) DO UPDATE SET
                priority = EXCLUDED.priority,
                is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
                column_type = EXCLUDED.column_type,
                purpose = EXCLUDED.purpose,
                target_pg_type = EXCLUDED.target_pg_type
            WHERE public.import_data_column.priority != EXCLUDED.priority
               OR public.import_data_column.column_type != EXCLUDED.column_type
               OR public.import_data_column.purpose != EXCLUDED.purpose
               OR public.import_data_column.target_pg_type IS DISTINCT FROM EXCLUDED.target_pg_type;

            RAISE DEBUG '[import.generate_external_ident_data_columns] Regular type "%": created/updated column "%_raw" with priority %',
                v_ident_type.code, v_ident_type.code, v_calculated_priority;

        ELSIF v_ident_type.shape = 'hierarchical' THEN
            -- Hierarchical: source_input maps to external_ident.idents (ltree)
            -- Per V7 recon + architect review: LTREE has its own internal
            -- limits (each label ≤ 256 bytes, full path many segments).
            -- target_pg_type='ltree' signals the analyse_length_limits
            -- procedure to skip the varchar bound check.
            v_labels_array := string_to_array(ltree2text(v_ident_type.labels), '.');
            v_num_labels := array_length(v_labels_array, 1);

            IF v_num_labels IS NULL OR v_num_labels = 0 THEN
                RAISE WARNING '[import.generate_external_ident_data_columns] Hierarchical type "%" has no labels, skipping', v_ident_type.code;
                CONTINUE;
            END IF;

            v_slot_base := v_base_priority + 2 + v_ident_type.priority * 11;

            v_label_index := 0;
            FOREACH v_label IN ARRAY v_labels_array
            LOOP
                v_calculated_priority := v_slot_base + v_label_index;

                INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority, target_pg_type)
                VALUES (v_step_id, v_ident_type.code || '_' || v_label || '_raw', 'TEXT', 'source_input', true, true, v_calculated_priority, 'ltree')
                ON CONFLICT (step_id, column_name) DO UPDATE SET
                    priority = EXCLUDED.priority,
                    is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
                    column_type = EXCLUDED.column_type,
                    purpose = EXCLUDED.purpose,
                    target_pg_type = EXCLUDED.target_pg_type
                WHERE public.import_data_column.priority != EXCLUDED.priority
                   OR public.import_data_column.column_type != EXCLUDED.column_type
                   OR public.import_data_column.purpose != EXCLUDED.purpose
                   OR public.import_data_column.target_pg_type IS DISTINCT FROM EXCLUDED.target_pg_type;

                RAISE DEBUG '[import.generate_external_ident_data_columns] Hierarchical type "%": created/updated column "%_%_raw" with priority % (target_pg_type=ltree)',
                    v_ident_type.code, v_ident_type.code, v_label, v_calculated_priority;

                v_label_index := v_label_index + 1;
            END LOOP;

            -- Generate internal path column (computed during analysis).
            v_calculated_priority := v_slot_base + v_num_labels;

            INSERT INTO public.import_data_column (step_id, column_name, column_type, purpose, is_nullable, is_uniquely_identifying, priority, target_pg_type)
            VALUES (v_step_id, v_ident_type.code || '_path', 'LTREE', 'internal', true, false, v_calculated_priority,
                    COALESCE(import.resolve_target_pg_type('external_idents', v_ident_type.code || '_path'), 'LTREE'))
            ON CONFLICT (step_id, column_name) DO UPDATE SET
                priority = EXCLUDED.priority,
                is_uniquely_identifying = EXCLUDED.is_uniquely_identifying,
                column_type = EXCLUDED.column_type,
                purpose = EXCLUDED.purpose,
                target_pg_type = EXCLUDED.target_pg_type
            WHERE public.import_data_column.priority != EXCLUDED.priority
               OR public.import_data_column.column_type != EXCLUDED.column_type
               OR public.import_data_column.purpose != EXCLUDED.purpose
               OR public.import_data_column.target_pg_type IS DISTINCT FROM EXCLUDED.target_pg_type;

            RAISE DEBUG '[import.generate_external_ident_data_columns] Hierarchical type "%": created/updated path column "%_path" with priority %',
                v_ident_type.code, v_ident_type.code, v_calculated_priority;
        END IF;
    END LOOP;
END;
$procedure$;


-- ─── 2. Backfill existing source_input external_idents rows ─────────────

-- Update the existing source_input rows that were generated with
-- target_pg_type='TEXT' by the pre-#89 generator. Pattern matches the
-- generator above:
--   - {code}_raw       for regular shape   → varchar(50)
--   - {code}_<label>_raw for hierarchical shape → ltree
UPDATE public.import_data_column idc
SET target_pg_type = 'character varying(50)'
FROM public.import_step s,
     public.external_ident_type_enabled t
WHERE idc.step_id = s.id
  AND s.code = 'external_idents'
  AND idc.purpose = 'source_input'
  AND t.shape = 'regular'
  AND idc.column_name = t.code || '_raw'
  AND idc.target_pg_type IS DISTINCT FROM 'character varying(50)';

UPDATE public.import_data_column idc
SET target_pg_type = 'ltree'
FROM public.import_step s,
     public.external_ident_type_enabled t,
     LATERAL string_to_array(ltree2text(t.labels), '.') AS v_label(label_arr)
WHERE idc.step_id = s.id
  AND s.code = 'external_idents'
  AND idc.purpose = 'source_input'
  AND t.shape = 'hierarchical'
  AND idc.column_name = ANY(
      SELECT t.code || '_' || lbl || '_raw'
      FROM unnest(v_label.label_arr) AS lbl
  )
  AND idc.target_pg_type IS DISTINCT FROM 'ltree';


-- ─── 3. Refactor procedure: schema-aware via target_pg_type ─────────────

-- Drops the hardcoded v_identifier_fail_steps and v_identifier_max_length
-- constants. The "identifier-fail" bucket is now defined structurally as
-- "purpose=source_input AND target_pg_type matches varchar(N)". LTREE
-- (and any other non-varchar) source_input columns fall outside the
-- check naturally.
--
-- The descriptive-vs-identifier distinction is now purely on `purpose`:
--   - internal     → descriptive (truncate or error based on flag)
--   - source_input → identifier (always error, regardless of flag)
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
$procedure$;


COMMENT ON PROCEDURE import.analyse_length_limits(integer, integer, text) IS
'Intercepts overlong text values before they reach process-step MERGEs.
Schema-aware: derives each column''s bound from import_data_column.target_pg_type
(populated by import_resolve_target_pg_type). No hardcoded step or
column lists.

Branches on public.import_job.truncate_overlong:
  - false (default): ANY overflow on a bounded column → dt.state=error,
    dt.errors entry. No truncation.
  - true (opt-in): descriptive (internal-purpose) overflows truncated to
    target length with dt.warnings entry; identifier (source_input-purpose)
    overflows still error.
Identifier truncation is never safe — it would silently change the
operator''s primary key, hence the per-purpose behavior.

LTREE-targeted columns (hierarchical external_idents) fall outside the
varchar(N) check naturally — their target_pg_type does not match the
regex, so the column is skipped. LTREE has its own internal limits
enforced at INSERT/MERGE time by PostgreSQL.';

END;
