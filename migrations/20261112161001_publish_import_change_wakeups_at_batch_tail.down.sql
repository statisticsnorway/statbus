BEGIN;

CREATE OR REPLACE FUNCTION worker.log_base_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_columns TEXT;
    v_has_valid_range BOOLEAN;
    v_where_clause TEXT := '';
    v_source TEXT;
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_ent_ids int4multirange;
    v_pg_ids int4multirange;
    v_valid_range datemultirange;
BEGIN
    CASE TG_TABLE_NAME
        WHEN 'establishment' THEN
            v_columns := 'id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'legal_unit' THEN
            v_columns := 'NULL::INT AS est_id, id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'enterprise' THEN
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'activity', 'location', 'contact', 'stat_for_unit' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, NULL::INT AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'person_for_unit' THEN
            -- Temporal table linking person to LU or ES (mutually exclusive).
            -- Has valid_range from sql_saga.
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, NULL::INT AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := TRUE;
        WHEN 'external_ident' THEN
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id, NULL::INT AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'tag_for_unit' THEN
            -- Non-temporal table linking tag to any unit type.
            -- Has all four unit ID columns (exactly one non-NULL per row).
            v_columns := 'establishment_id AS est_id, legal_unit_id AS lu_id, enterprise_id AS ent_id, power_group_id AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'legal_relationship' THEN
            -- LR changes only affect power groups, not individual LUs/enterprises.
            -- Only log when derived_power_group_id is assigned (NULL = PG not yet linked).
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, derived_power_group_id AS pg_id';
            v_has_valid_range := TRUE;

            v_where_clause := ' WHERE derived_power_group_id IS NOT NULL';
        WHEN 'power_group' THEN
            -- PG metadata changes (name, type_id, etc.) affect PG statistical units.
            -- Timeless table — no valid_range.
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, id AS pg_id';
            v_has_valid_range := FALSE;
        WHEN 'power_root' THEN
            -- PR changes (NSO custom_root override) affect the power group's timeline.
            -- Temporal table — has valid_range.
            v_columns := 'NULL::INT AS est_id, NULL::INT AS lu_id, NULL::INT AS ent_id, power_group_id AS pg_id';
            v_has_valid_range := TRUE;
        ELSE
            RAISE EXCEPTION 'log_base_change: unsupported table %', TG_TABLE_NAME;
    END CASE;

    IF v_has_valid_range THEN
        v_columns := v_columns || ', valid_range';
    ELSE
        v_columns := v_columns || ', NULL::daterange AS valid_range';
    END IF;

    CASE TG_OP
        WHEN 'INSERT' THEN v_source := format('SELECT %s FROM new_rows%s', v_columns, v_where_clause);
        WHEN 'DELETE' THEN v_source := format('SELECT %s FROM old_rows%s', v_columns, v_where_clause);
        WHEN 'UPDATE' THEN v_source := format('SELECT %s FROM old_rows%s UNION ALL SELECT %s FROM new_rows%s', v_columns, v_where_clause, v_columns, v_where_clause);
        ELSE RAISE EXCEPTION 'log_base_change: unsupported operation %', TG_OP;
    END CASE;

    -- No UNION ALL for influenced_id — LR changes only log PG IDs, not individual LU IDs

    EXECUTE format(
        'SELECT COALESCE(range_agg(int4range(est_id, est_id, %1$L)) FILTER (WHERE est_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(lu_id, lu_id, %1$L)) FILTER (WHERE lu_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(ent_id, ent_id, %1$L)) FILTER (WHERE ent_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(int4range(pg_id, pg_id, %1$L)) FILTER (WHERE pg_id IS NOT NULL), %2$L::int4multirange),
                COALESCE(range_agg(valid_range) FILTER (WHERE valid_range IS NOT NULL), %3$L::datemultirange)
         FROM (%s) AS mapped',
        '[]', '{}', '{}', v_source
    ) INTO v_est_ids, v_lu_ids, v_ent_ids, v_pg_ids, v_valid_range;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange
       OR v_pg_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, power_group_ids, valid_ranges)
        VALUES (v_est_ids, v_lu_ids, v_ent_ids, v_pg_ids, v_valid_range);

        PERFORM worker.publish_base_change_wakeup();
    END IF;

    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION worker.log_region_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_est_ids int4multirange;
    v_lu_ids int4multirange;
    v_valid_ranges datemultirange;
    v_source TEXT;
BEGIN
    -- Build source query based on operation
    CASE TG_OP
        WHEN 'INSERT' THEN v_source := 'new_rows';
        WHEN 'DELETE' THEN v_source := 'old_rows';
        WHEN 'UPDATE' THEN v_source := 'old_rows UNION ALL SELECT * FROM new_rows';
        ELSE RAISE EXCEPTION 'log_region_change: unsupported operation %', TG_OP;
    END CASE;

    -- Find affected units by joining region → location
    EXECUTE format(
        $SQL$
        SELECT
            COALESCE(range_agg(int4range(l.establishment_id, l.establishment_id, '[]')) FILTER (WHERE l.establishment_id IS NOT NULL), '{}'::int4multirange),
            COALESCE(range_agg(int4range(l.legal_unit_id, l.legal_unit_id, '[]')) FILTER (WHERE l.legal_unit_id IS NOT NULL), '{}'::int4multirange),
            COALESCE(range_agg(l.valid_range) FILTER (WHERE l.valid_range IS NOT NULL), '{}'::datemultirange)
        FROM (%s) AS affected_regions
        JOIN public.location AS l ON l.region_id = affected_regions.id
        $SQL$,
        format('SELECT * FROM %s', v_source)
    ) INTO v_est_ids, v_lu_ids, v_valid_ranges;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange THEN
        INSERT INTO worker.base_change_log (establishment_ids, legal_unit_ids, enterprise_ids, power_group_ids, valid_ranges)
        VALUES (v_est_ids, v_lu_ids, '{}'::int4multirange, '{}'::int4multirange, v_valid_ranges);

        PERFORM worker.publish_base_change_wakeup();
    END IF;

    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION worker.ensure_collect_changes_for_legal_relationship()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Only schedule collection if any changed row has a PG assigned.
    -- During initial import, LR rows are inserted with derived_power_group_id = NULL,
    -- then process_power_group_link assigns PG IDs (triggering this again).
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        IF NOT EXISTS (SELECT 1 FROM new_rows WHERE derived_power_group_id IS NOT NULL) THEN
            RETURN NULL;
        END IF;
    END IF;

    PERFORM worker.publish_base_change_wakeup();
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION worker.ensure_collect_changes_for_power_root()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        IF NOT EXISTS (SELECT 1 FROM new_rows WHERE custom_root_legal_unit_id IS NOT NULL) THEN
            RETURN NULL;
        END IF;
    END IF;

    PERFORM worker.publish_base_change_wakeup();
    RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION admin.import_job_process_one_batch(job public.import_job, p_batch_seq integer)
RETURNS integer
LANGUAGE plpgsql
AS $import_job_process_one_batch$
DECLARE
    v_rows_processed integer;
    error_message text;
    error_context text;
BEGIN
    -- The task uniqueness index gives each (job, batch) one scheduled leaf. This lock also makes a
    -- direct replay wait for an in-flight invocation before checking its committed row states.
    PERFORM pg_advisory_xact_lock(hashtextextended(format('import_batch:%s:%s', job.id, p_batch_seq), 0));
    EXECUTE format($SQL$
        SELECT count(*) FROM public.%1$I WHERE batch_seq = $1 AND state = 'processing'
    $SQL$, job.data_table_name) INTO v_rows_processed USING p_batch_seq;
    IF v_rows_processed = 0 THEN
        RETURN 0;
    END IF;

    BEGIN
        CALL admin.import_job_process_batch(job, p_batch_seq);
        EXECUTE format($SQL$
            UPDATE public.%1$I SET state = 'processed'
            WHERE batch_seq = $1 AND state = 'processing'
        $SQL$, job.data_table_name) USING p_batch_seq;
        GET DIAGNOSTICS v_rows_processed = ROW_COUNT;
        -- Keep this atomic increment at the transaction tail so progress remains live without
        -- holding the shared job row throughout temporal_merge or its supporting queries.
        UPDATE public.import_job SET imported_rows = imported_rows + v_rows_processed WHERE id = job.id;
    EXCEPTION
        WHEN deadlock_detected OR serialization_failure THEN
            RAISE;
        WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT, error_context = PG_EXCEPTION_CONTEXT;
            RAISE WARNING '[Job %] Error processing batch %: %. Context: %. Marking batch rows as error and failing job.',
                job.id, p_batch_seq, error_message, error_context;
            EXECUTE format($SQL$
                UPDATE public.%1$I
                SET state = 'error', errors = COALESCE(errors, '{}'::jsonb) || $1
                WHERE batch_seq = $2
            $SQL$, job.data_table_name)
            USING jsonb_build_object('process_batch_error', error_message, 'context', error_context), p_batch_seq;
            UPDATE public.import_job
            SET error = jsonb_build_object('error_in_processing_batch', error_message, 'context', error_context)::text,
                state = 'failed'
            WHERE id = job.id;
            RETURN NULL;
    END;
    RETURN v_rows_processed;
END;
$import_job_process_one_batch$;

COMMENT ON FUNCTION admin.import_job_process_one_batch(public.import_job, integer) IS
'Processes one whole dependency batch and atomically publishes its row states and imported_rows delta. A committed batch is replay-safe, failures mark the job failed, and transaction conflicts propagate to the worker retry policy.';

DROP FUNCTION worker.end_deferred_base_change_wakeup(jsonb);
DROP FUNCTION worker.begin_deferred_base_change_wakeup();
DROP FUNCTION worker.request_base_change_wakeup();

COMMIT;
