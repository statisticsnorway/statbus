BEGIN;

-- ============================================================================
-- Section 1: Restore original analyse_legal_relationship (without lookup)
-- ============================================================================

CREATE OR REPLACE PROCEDURE import.analyse_legal_relationship(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
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
               dt.percentage_raw
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

    -- STEP 3: Main update with resolved values
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
                    AS invalid_percentage
            FROM t_lr_batch_data AS bd
            LEFT JOIN t_lr_influencing_ids AS infl ON infl.tax_ident = NULLIF(TRIM(bd.influencing_tax_ident_raw), '')
            LEFT JOIN t_lr_influenced_ids AS infld ON infld.tax_ident = NULLIF(TRIM(bd.influenced_tax_ident_raw), '')
            LEFT JOIN t_lr_type_ids AS tp ON tp.code = NULLIF(TRIM(bd.rel_type_code_raw), '')
        )
        UPDATE public.%1$I dt SET
            influencing_id = l.influencing_id,
            influenced_id = l.influenced_id,
            type_id = l.type_id,
            percentage = l.percentage,
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
        FROM lookups AS l
        WHERE dt.row_id = l.data_row_id;
    $SQL$, v_data_table_name, v_error_keys_to_clear_arr, v_invalid_code_keys_arr);

    BEGIN
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_legal_relationship: Updated % rows in batch.', p_job_id, v_update_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_relationship: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_legal_relationship_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
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
$procedure$;

-- ============================================================================
-- Section 2: Remove natural key for legal_relationship
-- ============================================================================

SELECT sql_saga.drop_unique_key(
    'public.legal_relationship'::regclass,
    (SELECT unique_key_name FROM sql_saga.unique_keys
     WHERE table_schema = 'public'
       AND table_name = 'legal_relationship'
       AND key_type = 'natural'
       AND column_names = ARRAY['influencing_id', 'influenced_id', 'type_id']::name[])
);

END;
