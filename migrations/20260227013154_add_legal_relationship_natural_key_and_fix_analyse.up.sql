BEGIN;

-- ============================================================================
-- Section 1: Register natural key for legal_relationship
-- ============================================================================
-- This enables temporal_merge to look up existing relationships by their
-- business key (influencing_id, influenced_id, type_id) when the surrogate
-- key (id) is not known (i.e., during import of new data).
-- Without this, temporal_merge treats all rows with NULL id as new inserts,
-- causing exclusion constraint violations on the second import round.

SELECT sql_saga.add_unique_key(
    'public.legal_relationship'::regclass,
    ARRAY['influencing_id', 'influenced_id', 'type_id']::name[],
    'valid',
    'natural'
);

-- ============================================================================
-- Section 2: Fix analyse_legal_relationship to look up existing relationships
-- ============================================================================
-- The analyse step now resolves existing legal_relationship records by their
-- natural key (influencing_id + influenced_id + type_id) with overlapping
-- valid_range. This sets legal_relationship_id and operation correctly,
-- so temporal_merge can determine insert vs update.

CREATE OR REPLACE PROCEDURE import.analyse_legal_relationship(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $analyse_legal_relationship$
DECLARE
    v_job public.import_job;
    v_definition public.import_definition;
    v_step public.import_step;
    v_data_table_name TEXT;
    v_error_count INT := 0;
    v_update_count INT := 0;
    v_sql TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY[
        'missing_influencing_tax_ident',
        'unknown_influencing_tax_ident',
        'missing_influenced_tax_ident',
        'unknown_influenced_tax_ident',
        'missing_rel_type_code',
        'unknown_rel_type_code',
        'invalid_percentage'
    ];
    v_invalid_code_keys_arr TEXT[] := ARRAY['rel_type_code'];
BEGIN
    RAISE DEBUG '[Job %] analyse_legal_relationship (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_definition FROM jsonb_populate_record(NULL::public.import_definition, v_job.definition_snapshot->'import_definition');

    SELECT * INTO v_step
    FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list')
    WHERE code = 'legal_relationship';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] legal_relationship target step not found in snapshot', p_job_id; END IF;

    -- STEP 1: Materialize batch data into temp table
    IF to_regclass('pg_temp.t_lr_batch_data') IS NOT NULL THEN DROP TABLE t_lr_batch_data; END IF;
    v_sql := format($$
        CREATE TEMP TABLE t_lr_batch_data ON COMMIT DROP AS
        SELECT dt.row_id,
               dt.influencing_tax_ident_raw,
               dt.influenced_tax_ident_raw,
               dt.rel_type_code_raw,
               dt.percentage_raw,
               dt.valid_from,
               dt.valid_until
        FROM %I dt
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_seq;
    ANALYZE t_lr_batch_data;

    -- STEP 2: Resolve distinct tax_idents to legal_unit IDs
    IF to_regclass('pg_temp.t_lr_influencing_ids') IS NOT NULL THEN DROP TABLE t_lr_influencing_ids; END IF;
    CREATE TEMP TABLE t_lr_influencing_ids ON COMMIT DROP AS
    WITH distinct_idents AS (
        SELECT DISTINCT NULLIF(TRIM(influencing_tax_ident_raw), '') AS tax_ident
        FROM t_lr_batch_data
        WHERE NULLIF(TRIM(influencing_tax_ident_raw), '') IS NOT NULL
    )
    SELECT
        di.tax_ident,
        lu.id AS legal_unit_id
    FROM distinct_idents AS di
    LEFT JOIN public.external_ident AS ei
        ON ei.ident = di.tax_ident
        AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
    LEFT JOIN public.legal_unit AS lu
        ON lu.id = ei.legal_unit_id
        AND lu.valid_range @> CURRENT_DATE;
    ANALYZE t_lr_influencing_ids;

    IF to_regclass('pg_temp.t_lr_influenced_ids') IS NOT NULL THEN DROP TABLE t_lr_influenced_ids; END IF;
    CREATE TEMP TABLE t_lr_influenced_ids ON COMMIT DROP AS
    WITH distinct_idents AS (
        SELECT DISTINCT NULLIF(TRIM(influenced_tax_ident_raw), '') AS tax_ident
        FROM t_lr_batch_data
        WHERE NULLIF(TRIM(influenced_tax_ident_raw), '') IS NOT NULL
    )
    SELECT
        di.tax_ident,
        lu.id AS legal_unit_id
    FROM distinct_idents AS di
    LEFT JOIN public.external_ident AS ei
        ON ei.ident = di.tax_ident
        AND ei.type_id = (SELECT id FROM public.external_ident_type WHERE code = 'tax_ident')
    LEFT JOIN public.legal_unit AS lu
        ON lu.id = ei.legal_unit_id
        AND lu.valid_range @> CURRENT_DATE;
    ANALYZE t_lr_influenced_ids;

    -- Resolve rel_type codes
    IF to_regclass('pg_temp.t_lr_type_ids') IS NOT NULL THEN DROP TABLE t_lr_type_ids; END IF;
    CREATE TEMP TABLE t_lr_type_ids ON COMMIT DROP AS
    WITH distinct_codes AS (
        SELECT DISTINCT NULLIF(TRIM(rel_type_code_raw), '') AS code
        FROM t_lr_batch_data
        WHERE NULLIF(TRIM(rel_type_code_raw), '') IS NOT NULL
    )
    SELECT
        dc.code,
        lrt.id AS type_id
    FROM distinct_codes AS dc
    LEFT JOIN public.legal_rel_type AS lrt ON lrt.code = dc.code AND lrt.enabled;
    ANALYZE t_lr_type_ids;

    -- STEP 3: Main update with resolved values and existing relationship lookup
    v_sql := format($SQL$
        WITH lookups AS (
            SELECT
                bd.row_id AS data_row_id,
                infl.legal_unit_id AS influencing_id,
                infld.legal_unit_id AS influenced_id,
                tp.type_id,
                CASE
                    WHEN NULLIF(TRIM(bd.percentage_raw), '') IS NOT NULL THEN
                        CASE
                            WHEN bd.percentage_raw ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' THEN
                                TRIM(bd.percentage_raw)::numeric(5,2)
                            ELSE NULL
                        END
                    ELSE NULL
                END AS percentage,
                NULLIF(TRIM(bd.influencing_tax_ident_raw), '') IS NULL AS missing_influencing,
                NULLIF(TRIM(bd.influenced_tax_ident_raw), '') IS NULL AS missing_influenced,
                NULLIF(TRIM(bd.rel_type_code_raw), '') IS NULL AS missing_rel_type,
                NULLIF(TRIM(bd.influencing_tax_ident_raw), '') IS NOT NULL AND infl.legal_unit_id IS NULL AS unknown_influencing,
                NULLIF(TRIM(bd.influenced_tax_ident_raw), '') IS NOT NULL AND infld.legal_unit_id IS NULL AS unknown_influenced,
                NULLIF(TRIM(bd.rel_type_code_raw), '') IS NOT NULL AND tp.type_id IS NULL AS unknown_rel_type,
                NULLIF(TRIM(bd.percentage_raw), '') IS NOT NULL
                    AND NOT (bd.percentage_raw ~ '^\s*[0-9]+(\.[0-9]+)?\s*$')
                    AS invalid_percentage,
                -- Look up existing legal_relationship by natural key with overlapping time range
                lr.id AS existing_legal_relationship_id
            FROM t_lr_batch_data AS bd
            LEFT JOIN t_lr_influencing_ids AS infl ON infl.tax_ident = NULLIF(TRIM(bd.influencing_tax_ident_raw), '')
            LEFT JOIN t_lr_influenced_ids AS infld ON infld.tax_ident = NULLIF(TRIM(bd.influenced_tax_ident_raw), '')
            LEFT JOIN t_lr_type_ids AS tp ON tp.code = NULLIF(TRIM(bd.rel_type_code_raw), '')
            LEFT JOIN public.legal_relationship AS lr
                ON lr.influencing_id = infl.legal_unit_id
                AND lr.influenced_id = infld.legal_unit_id
                AND lr.type_id = tp.type_id
                AND lr.valid_range && daterange(bd.valid_from, bd.valid_until, '[)')
        ),
        -- Deduplicate: if multiple existing relationships match (e.g., split ranges),
        -- pick the one with the earliest valid_from
        deduped AS (
            SELECT DISTINCT ON (data_row_id) *
            FROM lookups
            ORDER BY data_row_id, existing_legal_relationship_id ASC NULLS LAST
        )
        UPDATE public.%1$I dt SET
            influencing_id = l.influencing_id,
            influenced_id = l.influenced_id,
            type_id = l.type_id,
            percentage = l.percentage,
            legal_relationship_id = l.existing_legal_relationship_id,
            state = CASE
                WHEN l.missing_influencing OR l.unknown_influencing
                  OR l.missing_influenced OR l.unknown_influenced
                  OR l.missing_rel_type OR l.unknown_rel_type
                  OR l.invalid_percentage
                THEN 'error'::public.import_data_state
                ELSE 'analysing'::public.import_data_state
            END,
            action = CASE
                WHEN l.missing_influencing OR l.unknown_influencing
                  OR l.missing_influenced OR l.unknown_influenced
                  OR l.missing_rel_type OR l.unknown_rel_type
                  OR l.invalid_percentage
                THEN 'skip'::public.import_row_action_type
                ELSE 'use'::public.import_row_action_type
            END,
            operation = CASE
                WHEN l.missing_influencing OR l.unknown_influencing
                  OR l.missing_influenced OR l.unknown_influenced
                  OR l.missing_rel_type OR l.unknown_rel_type
                  OR l.invalid_percentage
                THEN NULL
                WHEN l.existing_legal_relationship_id IS NOT NULL
                THEN CASE %4$L::public.import_strategy
                    WHEN 'insert_or_update' THEN 'update'::public.import_row_operation_type
                    WHEN 'update_only' THEN 'update'::public.import_row_operation_type
                    ELSE 'replace'::public.import_row_operation_type
                END
                ELSE 'insert'::public.import_row_operation_type
            END,
            errors = (dt.errors - %2$L::TEXT[])
                || CASE WHEN l.missing_influencing THEN jsonb_build_object('missing_influencing_tax_ident', 'influencing_tax_ident is required') ELSE '{}'::jsonb END
                || CASE WHEN l.unknown_influencing THEN jsonb_build_object('unknown_influencing_tax_ident', 'No legal unit found for influencing_tax_ident') ELSE '{}'::jsonb END
                || CASE WHEN l.missing_influenced THEN jsonb_build_object('missing_influenced_tax_ident', 'influenced_tax_ident is required') ELSE '{}'::jsonb END
                || CASE WHEN l.unknown_influenced THEN jsonb_build_object('unknown_influenced_tax_ident', 'No legal unit found for influenced_tax_ident') ELSE '{}'::jsonb END
                || CASE WHEN l.missing_rel_type THEN jsonb_build_object('missing_rel_type_code', 'rel_type_code is required') ELSE '{}'::jsonb END
                || CASE WHEN l.unknown_rel_type THEN jsonb_build_object('unknown_rel_type_code', 'Unknown rel_type_code') ELSE '{}'::jsonb END
                || CASE WHEN l.invalid_percentage THEN jsonb_build_object('invalid_percentage', 'percentage must be a number 0-100') ELSE '{}'::jsonb END,
            invalid_codes = CASE
                WHEN l.unknown_rel_type THEN jsonb_strip_nulls((dt.invalid_codes - %3$L::TEXT[]) || jsonb_build_object('rel_type_code', dt.rel_type_code_raw))
                ELSE dt.invalid_codes - %3$L::TEXT[]
            END
        FROM deduped AS l
        WHERE dt.row_id = l.data_row_id;
    $SQL$, v_data_table_name, v_error_keys_to_clear_arr, v_invalid_code_keys_arr, v_definition.strategy);

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_legal_relationship: Updated % rows in batch.', p_job_id, v_update_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_relationship: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_legal_relationship_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
    END;

    -- STEP 4: Compute founding_row_id for rows with same natural key in the batch.
    -- When multiple rows share (influencing_id, influenced_id, type_id) — e.g., different
    -- temporal periods for the same relationship — they must be linked via founding_row_id
    -- so temporal_merge knows they belong to the same entity.
    -- Offset of 1000000000 avoids collision between legal_relationship IDs and row_ids,
    -- matching the pattern used in analyse_external_idents.
    v_sql := format($SQL$
        WITH entity_groups AS (
            SELECT
                dt.row_id,
                dt.influencing_id,
                dt.influenced_id,
                dt.type_id,
                COALESCE(
                    dt.legal_relationship_id + 1000000000,
                    MIN(dt.row_id) OVER (
                        PARTITION BY dt.influencing_id, dt.influenced_id, dt.type_id
                    )
                ) AS computed_founding_id
            FROM public.%1$I AS dt
            WHERE dt.batch_seq = $1
              AND dt.action = 'use'
              AND dt.influencing_id IS NOT NULL
              AND dt.influenced_id IS NOT NULL
              AND dt.type_id IS NOT NULL
        )
        UPDATE public.%1$I dt SET
            founding_row_id = eg.computed_founding_id
        FROM entity_groups AS eg
        WHERE dt.row_id = eg.row_id
          AND dt.founding_row_id IS DISTINCT FROM eg.computed_founding_id;
    $SQL$, v_data_table_name);
    BEGIN
        EXECUTE v_sql USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_legal_relationship: Set founding_row_id for batch rows.', p_job_id;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_relationship: Error during founding_row_id computation: %', p_job_id, SQLERRM;
    END;

    -- Advance priority for all batch rows
    v_sql := format('UPDATE public.%1$I dt SET last_completed_priority = %2$L WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L',
                    v_data_table_name, v_step.priority);
    EXECUTE v_sql USING p_batch_seq;

    -- Count errors
    BEGIN
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_relationship: Error during error count: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_legal_relationship (Batch): Finished analysis for batch. Total errors: %', p_job_id, v_error_count;
END;
$analyse_legal_relationship$;

END;
