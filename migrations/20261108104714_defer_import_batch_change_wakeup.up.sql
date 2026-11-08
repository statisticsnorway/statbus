BEGIN;

CREATE FUNCTION worker.publish_base_change_wakeup()
RETURNS void
LANGUAGE plpgsql
AS $publish_base_change_wakeup$
BEGIN
    -- Serialize publication with a collector before it takes its drain snapshot.
    UPDATE worker.base_change_log_has_pending
    SET has_pending = TRUE;

    INSERT INTO worker.tasks (command, payload)
    VALUES ('collect_changes', '{"command":"collect_changes"}'::jsonb)
    ON CONFLICT (command)
    WHERE command = 'collect_changes' AND state = 'pending'::worker.task_state
    DO NOTHING;

    PERFORM pg_notify('worker_tasks', 'analytics');
END;
$publish_base_change_wakeup$;
COMMENT ON FUNCTION worker.publish_base_change_wakeup() IS
'Publishes a requested collector wakeup through the pending flag, task deduplication and analytics notification protocol. The unconditional singleton update serializes with collector drain/clear. Ordinary producers publish immediately, import batches publish at their transaction tail. Guarded producer triggers define when a request is required, including unconditional DELETE requests.';

CREATE FUNCTION worker.request_base_change_wakeup()
RETURNS void
LANGUAGE plpgsql
AS $request_base_change_wakeup$
BEGIN
    IF current_setting('statbus.defer_base_change_wakeup', true) = 'on' THEN
        PERFORM set_config('statbus.base_change_wakeup_dirty', 'on', true);
    ELSE
        PERFORM worker.publish_base_change_wakeup();
    END IF;
END;
$request_base_change_wakeup$;
COMMENT ON FUNCTION worker.request_base_change_wakeup() IS
'Requests a collector wakeup after the producer trigger has accepted its own scheduling guard. An import scope records a transaction-local dirty request for its tail, ordinary writes publish immediately. A request need not append a new log row, notably specialized DELETE scheduling.';

CREATE FUNCTION worker.begin_deferred_base_change_wakeup()
RETURNS jsonb
LANGUAGE plpgsql
AS $begin_deferred_base_change_wakeup$
DECLARE
    v_previous jsonb := jsonb_build_object(
        'scope', current_setting('statbus.defer_base_change_wakeup', true),
        'dirty', current_setting('statbus.base_change_wakeup_dirty', true)
    );
BEGIN
    PERFORM set_config('statbus.defer_base_change_wakeup', 'on', true);
    PERFORM set_config('statbus.base_change_wakeup_dirty', 'off', true);
    RETURN v_previous;
END;
$begin_deferred_base_change_wakeup$;
COMMENT ON FUNCTION worker.begin_deferred_base_change_wakeup() IS
'Begins a transaction-local import scope that keeps each change-log append immediate but defers wakeup publication. Returns the caller state for end_deferred_base_change_wakeup. Blank custom-GUC values mean unset. Begin inside the batch exception subtransaction so rollback restores both prior settings and pending dirty changes.';

CREATE FUNCTION worker.end_deferred_base_change_wakeup(p_previous_state jsonb)
RETURNS void
LANGUAGE plpgsql
AS $end_deferred_base_change_wakeup$
DECLARE
    v_dirty boolean := current_setting('statbus.base_change_wakeup_dirty', true) = 'on';
BEGIN
    IF p_previous_state IS NULL OR NOT p_previous_state ?& ARRAY['scope', 'dirty'] THEN
        RAISE EXCEPTION 'Missing deferred base-change wakeup scope state';
    END IF;

    PERFORM set_config('statbus.defer_base_change_wakeup', COALESCE(p_previous_state->>'scope', ''), true);
    PERFORM set_config('statbus.base_change_wakeup_dirty', COALESCE(p_previous_state->>'dirty', ''), true);
    IF v_dirty THEN
        IF p_previous_state->>'scope' = 'on' THEN
            -- A nested scope contributes its dirty changes to its caller.
            PERFORM set_config('statbus.base_change_wakeup_dirty', 'on', true);
        ELSE
            PERFORM worker.publish_base_change_wakeup();
        END IF;
    END IF;
END;
$end_deferred_base_change_wakeup$;
COMMENT ON FUNCTION worker.end_deferred_base_change_wakeup(jsonb) IS
'Restores the caller scope and dirty state. Dirty nested scopes propagate to the caller, while a dirty outermost scope publishes once at the batch transaction tail. An empty scope leaves publication untouched. All effects remain transactional, including notifications.';
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

        PERFORM worker.request_base_change_wakeup();
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

        PERFORM worker.request_base_change_wakeup();
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

    PERFORM worker.request_base_change_wakeup();
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

    PERFORM worker.request_base_change_wakeup();
    RETURN NULL;
END;
$function$;
CREATE OR REPLACE PROCEDURE worker.command_collect_changes(IN p_payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_row RECORD;
    v_est_ids int4multirange := '{}'::int4multirange;
    v_lu_ids int4multirange := '{}'::int4multirange;
    v_ent_ids int4multirange := '{}'::int4multirange;
    v_pg_ids int4multirange := '{}'::int4multirange;
    v_valid_range datemultirange := '{}'::datemultirange;
    v_valid_from DATE;
    v_valid_until DATE;
    v_task_id BIGINT;
    v_phase1_id BIGINT;
    v_phase2_id BIGINT;
    v_payload JSONB;
    v_direct_mode BOOLEAN;
    v_all_units BOOLEAN;
BEGIN
    -- Import-batch publishers hold this singleton at their transaction tail.
    -- Ordinary producers publish immediately. Lock before taking a drain snapshot
    -- so a committed append cannot lose its pending bit during flag clearing.
    PERFORM 1 FROM worker.base_change_log_has_pending FOR UPDATE;

    v_direct_mode :=
        p_payload ? 'establishment_id_ranges'
        OR p_payload ? 'legal_unit_id_ranges'
        OR p_payload ? 'enterprise_id_ranges'
        OR p_payload ? 'power_group_id_ranges';

    -- STATBUS-538: "everything" is one convention, carried through unchanged
    -- so every step decides from its own arguments: NULL for all four
    -- *_id_ranges means all units (worker.derive_statistical_unit's full
    -- branch), and valid_from = -infinity, valid_until = infinity means all
    -- time (the report derives then rebuild their whole per-slot cache).
    -- worker.enqueue_derive_statistical_unit_all() schedules exactly this.
    v_all_units := v_direct_mode
        AND NULLIF(p_payload->>'establishment_id_ranges', '') IS NULL
        AND NULLIF(p_payload->>'legal_unit_id_ranges', '') IS NULL
        AND NULLIF(p_payload->>'enterprise_id_ranges', '') IS NULL
        AND NULLIF(p_payload->>'power_group_id_ranges', '') IS NULL;

    IF v_all_units THEN
        -- All units: ids stay NULL, time defaults to all time. The full
        -- derive covers every logged change, so the log is drained too.
        v_est_ids := NULL;
        v_lu_ids := NULL;
        v_ent_ids := NULL;
        v_pg_ids := NULL;
        v_valid_range := COALESCE(
            NULLIF(p_payload->>'valid_ranges', '')::datemultirange,
            '{[-infinity,infinity)}'::datemultirange
        );
        DELETE FROM worker.base_change_log;
        UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;
    ELSIF v_direct_mode THEN
        -- Caller supplied explicit ranges. A NULL / JSON-null value for a
        -- given key means "all ids of that kind" — synthesise from base
        -- tables, because worker.derive_statistical_unit reads a NULL kind
        -- next to explicit kinds as none.
        v_est_ids := COALESCE(
            NULLIF(p_payload->>'establishment_id_ranges', '')::int4multirange,
            COALESCE(
                (SELECT range_agg(int4range(id, id, '[]'))::int4multirange FROM public.establishment),
                '{}'::int4multirange
            )
        );
        v_lu_ids := COALESCE(
            NULLIF(p_payload->>'legal_unit_id_ranges', '')::int4multirange,
            COALESCE(
                (SELECT range_agg(int4range(id, id, '[]'))::int4multirange FROM public.legal_unit),
                '{}'::int4multirange
            )
        );
        v_ent_ids := COALESCE(
            NULLIF(p_payload->>'enterprise_id_ranges', '')::int4multirange,
            COALESCE(
                (SELECT range_agg(int4range(id, id, '[]'))::int4multirange FROM public.enterprise),
                '{}'::int4multirange
            )
        );
        v_pg_ids := COALESCE(
            NULLIF(p_payload->>'power_group_id_ranges', '')::int4multirange,
            COALESCE(
                (SELECT range_agg(int4range(id, id, '[]'))::int4multirange FROM public.power_group),
                '{}'::int4multirange
            )
        );
        v_valid_range := COALESCE(
            NULLIF(p_payload->>'valid_ranges', '')::datemultirange,
            '{}'::datemultirange
        );
        UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;
    ELSE
        -- Drain-log mode: unchanged from 20260319124229.
        FOR v_row IN DELETE FROM worker.base_change_log RETURNING * LOOP
            v_est_ids := v_est_ids + v_row.establishment_ids;
            v_lu_ids := v_lu_ids + v_row.legal_unit_ids;
            v_ent_ids := v_ent_ids + v_row.enterprise_ids;
            v_pg_ids := v_pg_ids + v_row.power_group_ids;
            v_valid_range := v_valid_range + v_row.valid_ranges;
        END LOOP;

        UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;
    END IF;

    IF v_all_units
       OR v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange
       OR v_pg_ids != '{}'::int4multirange THEN

        -- Get own task_id for spawning children
        SELECT id INTO v_task_id
        FROM worker.tasks
        WHERE state = 'processing' AND worker_pid = pg_backend_pid()
        ORDER BY id DESC LIMIT 1;

        IF v_all_units THEN
            p_info := jsonb_build_object(
                'affected_establishment_count', (SELECT count(*) FROM public.establishment),
                'affected_legal_unit_count', (SELECT count(*) FROM public.legal_unit),
                'affected_enterprise_count', (SELECT count(*) FROM public.enterprise),
                'affected_power_group_count', (SELECT count(*) FROM public.power_group)
            );
        ELSE
            p_info := jsonb_build_object(
                'affected_establishment_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_est_ids) AS r),
                'affected_legal_unit_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_lu_ids) AS r),
                'affected_enterprise_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_ent_ids) AS r),
                'affected_power_group_count', (SELECT COALESCE(sum(upper(r) - lower(r)), 0) FROM unnest(v_pg_ids) AS r)
            );
        END IF;

        IF v_valid_range = '{}'::datemultirange THEN
            SELECT COALESCE(range_agg(vr)::datemultirange, '{}'::datemultirange)
            INTO v_valid_range
            FROM (
                SELECT valid_range AS vr FROM public.establishment AS est WHERE v_est_ids @> est.id
                UNION ALL
                SELECT valid_range AS vr FROM public.legal_unit AS lu WHERE v_lu_ids @> lu.id
            ) AS units;
        END IF;

        v_valid_from := lower(v_valid_range);
        v_valid_until := upper(v_valid_range);

        v_payload := jsonb_build_object(
            'valid_from', v_valid_from,
            'valid_until', v_valid_until
        );

        v_phase1_id := worker.spawn(
            p_command => 'derive_units_phase',
            p_payload => v_payload,
            p_parent_id => v_task_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'derive_statistical_unit',
            p_payload => jsonb_build_object(
                'establishment_id_ranges', v_est_ids::text,
                'legal_unit_id_ranges', v_lu_ids::text,
                'enterprise_id_ranges', v_ent_ids::text,
                'power_group_id_ranges', v_pg_ids::text,
                'valid_from', v_valid_from,
                'valid_until', v_valid_until
            ),
            p_parent_id => v_phase1_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'derive_statistical_history_facet_delta',
            p_payload => v_payload,
            p_parent_id => v_phase1_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'statistical_unit_flush_staging',
            p_payload => v_payload,
            p_parent_id => v_phase1_id,
            p_child_mode => 'serial'
        );

        -- BLOCK D: derive_used_tables runs AFTER statistical_unit_flush_staging
        -- has published activity/region/sector/… paths to public.statistical_unit.
        -- Previously these were invoked inline from worker.derive_statistical_unit,
        -- which ran before the flush — the views filtering on *_path IS NOT NULL
        -- returned 0 rows and *_used stayed empty on first-import cycles.
        PERFORM worker.spawn(
            p_command => 'derive_used_tables',
            p_payload => v_payload,
            p_parent_id => v_phase1_id,
            p_child_mode => 'serial'
        );

        v_phase2_id := worker.spawn(
            p_command => 'derive_reports_phase',
            p_payload => v_payload,
            p_parent_id => v_task_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'derive_statistical_unit_facet',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'statistical_unit_facet_reduce',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );

        PERFORM worker.spawn(
            p_command => 'statistical_history_facet_delta_reduce',
            p_payload => v_payload,
            p_parent_id => v_phase2_id,
            p_child_mode => 'serial'
        );
    ELSE
        p_info := jsonb_build_object(
            'affected_establishment_count', 0,
            'affected_legal_unit_count', 0,
            'affected_enterprise_count', 0,
            'affected_power_group_count', 0
        );
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    END IF;
END;
$procedure$;
CREATE OR REPLACE FUNCTION admin.import_job_process_one_batch(job import_job, p_batch_seq integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_rows_processed integer;
    v_previous_wakeup_state jsonb;
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
        v_previous_wakeup_state := worker.begin_deferred_base_change_wakeup();
        CALL admin.import_job_process_batch(job, p_batch_seq);
        EXECUTE format($SQL$
            UPDATE public.%1$I SET state = 'processed'
            WHERE batch_seq = $1 AND state = 'processing'
        $SQL$, job.data_table_name) USING p_batch_seq;
        GET DIAGNOSTICS v_rows_processed = ROW_COUNT;
        -- Keep this atomic increment at the transaction tail so progress remains live without
        -- holding the shared job row throughout temporal_merge or its supporting queries.
        UPDATE public.import_job SET imported_rows = imported_rows + v_rows_processed WHERE id = job.id;
        PERFORM worker.end_deferred_base_change_wakeup(v_previous_wakeup_state);
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
$function$;

COMMENT ON FUNCTION admin.import_job_process_one_batch(public.import_job, integer) IS
'Processes one whole dependency batch and atomically publishes its row states, imported_rows delta and requested analytics wakeup. Change-log appends and integrity checks stay immediate. Wakeup publication at the transaction tail avoids serializing independent domain writes. A committed batch is replay-safe, failures mark the job failed, and transaction conflicts propagate to the worker retry policy.';

COMMIT;
