```sql
CREATE OR REPLACE PROCEDURE import.analyse_legal_unit(IN p_job_id integer, IN p_batch_seq integer, IN p_step_code text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_job public.import_job;
    v_step public.import_step;
    v_sql TEXT;
    v_update_count INT := 0;
    v_error_count INT := 0;
    v_data_table_name TEXT;
    v_error_keys_to_clear_arr TEXT[] := ARRAY['name_raw', 'legal_form_code_raw', 'sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw', 'status_code_raw', 'legal_unit'];
    v_invalid_code_keys_arr TEXT[] := ARRAY['legal_form_code_raw', 'sector_code_raw', 'unit_size_code_raw', 'birth_date_raw', 'death_date_raw']; -- Keys that go into invalid_codes
BEGIN
    RAISE DEBUG '[Job %] analyse_legal_unit (Batch): Starting analysis for batch_seq %', p_job_id, p_batch_seq;

    SELECT * INTO v_job FROM public.import_job WHERE id = p_job_id;
    v_data_table_name := v_job.data_table_name;

    SELECT * INTO v_step FROM jsonb_populate_recordset(NULL::public.import_step, v_job.definition_snapshot->'import_step_list') WHERE code = 'legal_unit';
    IF NOT FOUND THEN RAISE EXCEPTION '[Job %] legal_unit target step not found in snapshot', p_job_id; END IF;

    v_sql := format($$
        UPDATE %1$I dt SET
            action = 'skip'::public.import_row_action_type,
            last_completed_priority = %2$L
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip'
          AND NULLIF(dt.name_raw, '') IS NULL
          AND NULLIF(dt.legal_form_code_raw, '') IS NULL
          AND NULLIF(dt.sector_code_raw, '') IS NULL
          AND NULLIF(dt.unit_size_code_raw, '') IS NULL
          AND NULLIF(dt.birth_date_raw, '') IS NULL
          AND NULLIF(dt.death_date_raw, '') IS NULL
          AND dt.status_id IS NULL; -- status_id is resolved from status_code_raw in a prior step
    $$, v_data_table_name, v_step.priority);
    EXECUTE v_sql USING p_batch_seq;

    -- Step 1: Materialize the batch data into a temp table for performance.
    IF to_regclass('pg_temp.t_batch_data') IS NOT NULL THEN DROP TABLE t_batch_data; END IF;
    v_sql := format($$
        CREATE TEMP TABLE t_batch_data ON COMMIT DROP AS
        SELECT dt.row_id, dt.operation, dt.name_raw, dt.status_id, dt.legal_unit_id,
               dt.legal_form_code_raw, dt.sector_code_raw, dt.unit_size_code_raw,
               dt.birth_date_raw, dt.death_date_raw
        FROM %I dt
        WHERE dt.batch_seq = $1
          AND dt.action IS DISTINCT FROM 'skip';
    $$, v_data_table_name);
    EXECUTE v_sql USING p_batch_seq;

    ANALYZE t_batch_data;

    -- Step 2: Resolve all distinct codes and dates from the batch in separate temp tables.
    IF to_regclass('pg_temp.t_resolved_codes') IS NOT NULL THEN DROP TABLE t_resolved_codes; END IF;
    CREATE TEMP TABLE t_resolved_codes ON COMMIT DROP AS
    WITH distinct_codes AS (
        SELECT legal_form_code_raw AS code, 'legal_form' AS type FROM t_batch_data WHERE NULLIF(legal_form_code_raw, '') IS NOT NULL
        UNION SELECT sector_code_raw AS code, 'sector' AS type FROM t_batch_data WHERE NULLIF(sector_code_raw, '') IS NOT NULL
        UNION SELECT unit_size_code_raw AS code, 'unit_size' AS type FROM t_batch_data WHERE NULLIF(unit_size_code_raw, '') IS NOT NULL
    )
    SELECT
        dc.code, dc.type, COALESCE(lf.id, s.id, us.id) AS resolved_id
    FROM distinct_codes dc
    LEFT JOIN public.legal_form_available lf ON dc.type = 'legal_form' AND dc.code = lf.code
    LEFT JOIN public.sector_available s ON dc.type = 'sector' AND dc.code = s.code
    LEFT JOIN public.unit_size_available us ON dc.type = 'unit_size' AND dc.code = us.code;

    IF to_regclass('pg_temp.t_resolved_dates') IS NOT NULL THEN DROP TABLE t_resolved_dates; END IF;
    CREATE TEMP TABLE t_resolved_dates ON COMMIT DROP AS
    WITH distinct_dates AS (
        SELECT birth_date_raw AS date_string FROM t_batch_data WHERE NULLIF(birth_date_raw, '') IS NOT NULL
        UNION SELECT death_date_raw AS date_string FROM t_batch_data WHERE NULLIF(death_date_raw, '') IS NOT NULL
    )
    SELECT dd.date_string, sc.p_value, sc.p_error_message
    FROM distinct_dates dd
    LEFT JOIN LATERAL import.safe_cast_to_date(dd.date_string) AS sc ON TRUE;

    ANALYZE t_resolved_codes;
    ANALYZE t_resolved_dates;

    -- Step 3: Perform the main update using the pre-resolved lookup tables.
    v_sql := format($SQL$
        WITH lookups AS (
            SELECT
                bd.row_id as data_row_id,
                bd.operation, bd.name_raw as name, bd.status_id, bd.legal_unit_id,
                bd.legal_form_code_raw as legal_form_code,
                bd.sector_code_raw as sector_code,
                bd.unit_size_code_raw as unit_size_code,
                bd.birth_date_raw as birth_date,
                bd.death_date_raw as death_date,
                lf.resolved_id as resolved_legal_form_id,
                s.resolved_id as resolved_sector_id,
                us.resolved_id as resolved_unit_size_id,
                b_date.p_value as resolved_typed_birth_date,
                b_date.p_error_message as birth_date_error_msg,
                d_date.p_value as resolved_typed_death_date,
                d_date.p_error_message as death_date_error_msg
            FROM t_batch_data bd
            LEFT JOIN t_resolved_codes lf ON bd.legal_form_code_raw = lf.code AND lf.type = 'legal_form'
            LEFT JOIN t_resolved_codes s ON bd.sector_code_raw = s.code AND s.type = 'sector'
            LEFT JOIN t_resolved_codes us ON bd.unit_size_code_raw = us.code AND us.type = 'unit_size'
            LEFT JOIN t_resolved_dates b_date ON bd.birth_date_raw = b_date.date_string
            LEFT JOIN t_resolved_dates d_date ON bd.death_date_raw = d_date.date_string
        )
        UPDATE public.%1$I dt SET
            name = NULLIF(trim(l.name), ''),
            legal_form_id = l.resolved_legal_form_id,
            sector_id = l.resolved_sector_id,
            unit_size_id = l.resolved_unit_size_id,
            birth_date = l.resolved_typed_birth_date,
            death_date = l.resolved_typed_death_date,
            state = CASE
                        WHEN l.legal_unit_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN 'error'::public.import_data_state
                        WHEN l.status_id IS NULL THEN 'error'::public.import_data_state
                        ELSE 'analysing'::public.import_data_state
                    END,
            action = CASE
                        WHEN l.legal_unit_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN 'skip'::public.import_row_action_type
                        WHEN l.status_id IS NULL THEN 'skip'::public.import_row_action_type
                        ELSE dt.action
                     END,
            errors = CASE
                        WHEN l.legal_unit_id IS NULL AND NULLIF(trim(l.name), '') IS NULL THEN
                            dt.errors || jsonb_build_object('name_raw', 'Missing required name for legal unit.')
                        WHEN l.status_id IS NULL THEN
                            dt.errors || jsonb_build_object('status_code_raw', 'Status code could not be resolved and is required for this operation.')
                        ELSE
                            dt.errors - %2$L::TEXT[]
                    END,
            invalid_codes = CASE
                                WHEN (l.operation = 'update' OR NULLIF(trim(l.name), '') IS NOT NULL) AND l.status_id IS NOT NULL THEN
                                    jsonb_strip_nulls(
                                     (dt.invalid_codes - %3$L::TEXT[]) ||
                                     jsonb_build_object('legal_form_code_raw', CASE WHEN NULLIF(l.legal_form_code, '') IS NOT NULL AND l.resolved_legal_form_id IS NULL THEN l.legal_form_code ELSE NULL END) ||
                                     jsonb_build_object('sector_code_raw', CASE WHEN NULLIF(l.sector_code, '') IS NOT NULL AND l.resolved_sector_id IS NULL THEN l.sector_code ELSE NULL END) ||
                                     jsonb_build_object('unit_size_code_raw', CASE WHEN NULLIF(l.unit_size_code, '') IS NOT NULL AND l.resolved_unit_size_id IS NULL THEN l.unit_size_code ELSE NULL END) ||
                                     jsonb_build_object('birth_date_raw', CASE WHEN NULLIF(l.birth_date, '') IS NOT NULL AND l.birth_date_error_msg IS NOT NULL THEN l.birth_date ELSE NULL END) ||
                                     jsonb_build_object('death_date_raw', CASE WHEN NULLIF(l.death_date, '') IS NOT NULL AND l.death_date_error_msg IS NOT NULL THEN l.death_date ELSE NULL END)
                                    )
                                ELSE dt.invalid_codes
                            END
        FROM lookups l
        WHERE dt.row_id = l.data_row_id;
    $SQL$,
        v_data_table_name,             -- %1$I
        v_error_keys_to_clear_arr,     -- %2$L
        v_invalid_code_keys_arr       -- %3$L
    );

    BEGIN
        RAISE DEBUG '[Job %] analyse_legal_unit: Updating batch data with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql;
        GET DIAGNOSTICS v_update_count = ROW_COUNT;
        RAISE DEBUG '[Job %] analyse_legal_unit: Updated % rows in batch.', p_job_id, v_update_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Error during batch update: %', p_job_id, SQLERRM;
        UPDATE public.import_job SET error = jsonb_build_object('analyse_legal_unit_batch_error', SQLERRM)::TEXT, state = 'failed' WHERE id = p_job_id;
        -- Don't re-raise - job is marked as failed
    END;

    -- Unconditionally advance priority for all rows in batch to ensure progress
    v_sql := format('UPDATE public.%1$I dt SET last_completed_priority = %2$L WHERE dt.batch_seq = $1 AND dt.last_completed_priority < %2$L',
                    v_data_table_name, v_step.priority);
    RAISE DEBUG '[Job %] analyse_legal_unit: Unconditionally advancing priority for all batch rows with SQL: %', p_job_id, v_sql;
    EXECUTE v_sql USING p_batch_seq;

    BEGIN
        v_sql := format($$SELECT COUNT(*) FROM public.%1$I dt WHERE dt.batch_seq = $1 AND dt.state = 'error' AND (dt.errors ?| %2$L::text[])$$,
                       v_data_table_name, v_error_keys_to_clear_arr);
        RAISE DEBUG '[Job %] analyse_legal_unit: Counting errors with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql INTO v_error_count USING p_batch_seq;
        RAISE DEBUG '[Job %] analyse_legal_unit: Estimated errors in this step for batch: %', p_job_id, v_error_count;
    EXCEPTION WHEN others THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Error during error count: %', p_job_id, SQLERRM;
    END;

    -- Propagate errors to all rows of a new entity if one fails (best-effort)
    BEGIN
        CALL import.propagate_fatal_error_to_entity_batch(p_job_id, v_data_table_name, p_batch_seq, v_error_keys_to_clear_arr, 'analyse_legal_unit');
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Non-fatal error during error propagation: %', p_job_id, SQLERRM;
    END;

    -- Resolve primary_for_enterprise conflicts (best-effort)
    BEGIN
        RAISE DEBUG '[Job %] analyse_legal_unit: Resolving primary_for_enterprise conflicts within the batch in %s.', p_job_id, v_data_table_name;
        v_sql := format($$
            WITH BatchPrimaries AS (
                SELECT
                    src.row_id,
                    FIRST_VALUE(src.row_id) OVER (
                        PARTITION BY src.enterprise_id, daterange(src.valid_from, src.valid_until, '[)')
                        ORDER BY src.legal_unit_id ASC NULLS LAST, src.row_id ASC
                    ) as winner_row_id
                FROM public.%1$I src
                WHERE src.batch_seq = $1
                  AND src.primary_for_enterprise = true AND src.enterprise_id IS NOT NULL
            )
            UPDATE public.%1$I dt
            SET primary_for_enterprise = false
            FROM BatchPrimaries bp
            WHERE dt.row_id = bp.row_id
              AND dt.row_id != bp.winner_row_id
              AND dt.primary_for_enterprise = true;
        $$, v_data_table_name);
        RAISE DEBUG '[Job %] analyse_legal_unit: Resolving primary conflicts with SQL: %', p_job_id, v_sql;
        EXECUTE v_sql USING p_batch_seq;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[Job %] analyse_legal_unit: Non-fatal error during primary conflict resolution: %', p_job_id, SQLERRM;
    END;

    RAISE DEBUG '[Job %] analyse_legal_unit (Batch): Finished analysis for batch. Total errors in batch: %', p_job_id, v_error_count;
END;
$procedure$
```
