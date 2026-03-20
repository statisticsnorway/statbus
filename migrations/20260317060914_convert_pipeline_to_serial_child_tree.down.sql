BEGIN;

-- =============================================================================
-- Reverse: Convert pipeline back from serial child tree to flat "uncle" tasks
-- =============================================================================

-- =============================================================================
-- Restore enqueue functions (Step 10 reverse)
-- =============================================================================

CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_priority BIGINT;
  v_establishment_id_ranges int4multirange := COALESCE(p_establishment_id_ranges, '{}'::int4multirange);
  v_legal_unit_id_ranges int4multirange := COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange);
  v_enterprise_id_ranges int4multirange := COALESCE(p_enterprise_id_ranges, '{}'::int4multirange);
  v_power_group_id_ranges int4multirange := COALESCE(p_power_group_id_ranges, '{}'::int4multirange);
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));
  v_payload := jsonb_build_object(
    'command', 'derive_statistical_unit',
    'establishment_id_ranges', v_establishment_id_ranges,
    'legal_unit_id_ranges', v_legal_unit_id_ranges,
    'enterprise_id_ranges', v_enterprise_id_ranges,
    'power_group_id_ranges', v_power_group_id_ranges,
    'valid_from', v_valid_from,
    'valid_until', v_valid_until,
    'round_priority_base', v_priority
  );
  INSERT INTO worker.tasks AS t (command, payload, priority)
  VALUES ('derive_statistical_unit', v_payload, v_priority)
  ON CONFLICT (command)
  WHERE command = 'derive_statistical_unit' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_statistical_unit',
      'establishment_id_ranges', (t.payload->>'establishment_id_ranges')::int4multirange + (EXCLUDED.payload->>'establishment_id_ranges')::int4multirange,
      'legal_unit_id_ranges', (t.payload->>'legal_unit_id_ranges')::int4multirange + (EXCLUDED.payload->>'legal_unit_id_ranges')::int4multirange,
      'enterprise_id_ranges', (t.payload->>'enterprise_id_ranges')::int4multirange + (EXCLUDED.payload->>'enterprise_id_ranges')::int4multirange,
      'power_group_id_ranges', (t.payload->>'power_group_id_ranges')::int4multirange + (EXCLUDED.payload->>'power_group_id_ranges')::int4multirange,
      'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
      'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date),
      'round_priority_base', LEAST((t.payload->>'round_priority_base')::bigint, (EXCLUDED.payload->>'round_priority_base')::bigint)
    ),
    state = 'pending'::worker.task_state,
    priority = LEAST(t.priority, EXCLUDED.priority),
    processed_at = NULL, error = NULL
  RETURNING id INTO v_task_id;
  PERFORM pg_notify('worker_tasks', 'analytics');
  RETURN v_task_id;
END;
$function$;

CREATE OR REPLACE FUNCTION worker.enqueue_statistical_unit_flush_staging(p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_task_id BIGINT;
    v_priority BIGINT;
    v_payload JSONB;
BEGIN
    v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));
    v_payload := jsonb_build_object(
        'command', 'statistical_unit_flush_staging',
        'round_priority_base', v_priority
    );

    INSERT INTO worker.tasks AS t (command, payload, priority)
    VALUES ('statistical_unit_flush_staging', v_payload, v_priority)
    ON CONFLICT (command)
    WHERE command = 'statistical_unit_flush_staging' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        payload = jsonb_build_object(
            'command', 'statistical_unit_flush_staging',
            'round_priority_base', LEAST(
                (t.payload->>'round_priority_base')::bigint,
                (EXCLUDED.payload->>'round_priority_base')::bigint
            )
        ),
        priority = LEAST(t.priority, EXCLUDED.priority)
    RETURNING id INTO v_task_id;

    PERFORM pg_notify('worker_tasks', 'analytics');

    RETURN v_task_id;
END;
$function$;

CREATE OR REPLACE FUNCTION worker.enqueue_derive_reports(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_priority BIGINT;
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

  v_payload := jsonb_build_object(
    'command', 'derive_reports',
    'valid_from', v_valid_from,
    'valid_until', v_valid_until,
    'round_priority_base', v_priority
  );

  INSERT INTO worker.tasks AS t (
    command, payload, priority
  ) VALUES ('derive_reports', v_payload, v_priority)
  ON CONFLICT (command)
  WHERE command = 'derive_reports' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_reports',
      'valid_from', LEAST(
        (t.payload->>'valid_from')::date,
        (EXCLUDED.payload->>'valid_from')::date
      ),
      'valid_until', GREATEST(
        (t.payload->>'valid_until')::date,
        (EXCLUDED.payload->>'valid_until')::date
      ),
      'round_priority_base', LEAST(
        (t.payload->>'round_priority_base')::bigint,
        (EXCLUDED.payload->>'round_priority_base')::bigint
      )
    ),
    state = 'pending'::worker.task_state,
    priority = LEAST(t.priority, EXCLUDED.priority),
    processed_at = NULL,
    error = NULL
  RETURNING id INTO v_task_id;

  PERFORM pg_notify('worker_tasks', 'analytics');

  RETURN v_task_id;
END;
$function$;

CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_history(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_priority BIGINT;
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

  v_payload := jsonb_build_object(
    'command', 'derive_statistical_history',
    'valid_from', v_valid_from,
    'valid_until', v_valid_until,
    'round_priority_base', v_priority
  );

  INSERT INTO worker.tasks AS t (command, payload, priority)
  VALUES ('derive_statistical_history', v_payload, v_priority)
  ON CONFLICT (command)
  WHERE command = 'derive_statistical_history' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_statistical_history',
      'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
      'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date),
      'round_priority_base', LEAST(
        (t.payload->>'round_priority_base')::bigint,
        (EXCLUDED.payload->>'round_priority_base')::bigint
      )
    ),
    state = 'pending'::worker.task_state,
    priority = LEAST(t.priority, EXCLUDED.priority)
  RETURNING id INTO v_task_id;

  RETURN v_task_id;
END;
$function$;

CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_unit_facet(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_priority BIGINT;
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

  v_payload := jsonb_build_object(
    'command', 'derive_statistical_unit_facet',
    'valid_from', v_valid_from,
    'valid_until', v_valid_until,
    'round_priority_base', v_priority
  );

  INSERT INTO worker.tasks AS t (command, payload, priority)
  VALUES ('derive_statistical_unit_facet', v_payload, v_priority)
  ON CONFLICT (command)
  WHERE command = 'derive_statistical_unit_facet' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_statistical_unit_facet',
      'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
      'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date),
      'round_priority_base', LEAST(
        (t.payload->>'round_priority_base')::bigint,
        (EXCLUDED.payload->>'round_priority_base')::bigint
      )
    ),
    state = 'pending'::worker.task_state,
    priority = LEAST(t.priority, EXCLUDED.priority)
  RETURNING id INTO v_task_id;

  RETURN v_task_id;
END;
$function$;

CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_history_facet(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_priority BIGINT;
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

  v_payload := jsonb_build_object(
    'command', 'derive_statistical_history_facet',
    'valid_from', v_valid_from,
    'valid_until', v_valid_until,
    'round_priority_base', v_priority
  );

  INSERT INTO worker.tasks AS t (command, payload, priority)
  VALUES ('derive_statistical_history_facet', v_payload, v_priority)
  ON CONFLICT (command)
  WHERE command = 'derive_statistical_history_facet' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_statistical_history_facet',
      'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
      'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date),
      'round_priority_base', LEAST(
        (t.payload->>'round_priority_base')::bigint,
        (EXCLUDED.payload->>'round_priority_base')::bigint
      )
    ),
    state = 'pending'::worker.task_state,
    priority = LEAST(t.priority, EXCLUDED.priority)
  RETURNING id INTO v_task_id;

  RETURN v_task_id;
END;
$function$;

CREATE OR REPLACE FUNCTION worker.enqueue_statistical_history_reduce(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_priority BIGINT;
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));
  v_payload := jsonb_build_object(
    'command', 'statistical_history_reduce',
    'valid_from', v_valid_from,
    'valid_until', v_valid_until,
    'round_priority_base', v_priority
  );
  INSERT INTO worker.tasks AS t (command, payload, priority)
  VALUES ('statistical_history_reduce', v_payload, v_priority)
  ON CONFLICT (command)
  WHERE command = 'statistical_history_reduce' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'statistical_history_reduce',
      'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
      'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date),
      'round_priority_base', LEAST(
        (t.payload->>'round_priority_base')::bigint,
        (EXCLUDED.payload->>'round_priority_base')::bigint
      )
    ),
    state = 'pending'::worker.task_state,
    priority = LEAST(t.priority, EXCLUDED.priority)
  RETURNING id INTO v_task_id;
  RETURN v_task_id;
END;
$function$;

CREATE OR REPLACE FUNCTION worker.enqueue_statistical_history_facet_reduce(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_priority BIGINT;
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));
  v_payload := jsonb_build_object(
    'command', 'statistical_history_facet_reduce',
    'valid_from', v_valid_from,
    'valid_until', v_valid_until,
    'round_priority_base', v_priority
  );
  INSERT INTO worker.tasks AS t (command, payload, priority)
  VALUES ('statistical_history_facet_reduce', v_payload, v_priority)
  ON CONFLICT (command)
  WHERE command = 'statistical_history_facet_reduce' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'statistical_history_facet_reduce',
      'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
      'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date),
      'round_priority_base', LEAST(
        (t.payload->>'round_priority_base')::bigint,
        (EXCLUDED.payload->>'round_priority_base')::bigint
      )
    ),
    state = 'pending'::worker.task_state,
    priority = LEAST(t.priority, EXCLUDED.priority)
  RETURNING id INTO v_task_id;
  RETURN v_task_id;
END;
$function$;

-- Restore both overloads of enqueue_statistical_unit_facet_reduce
CREATE OR REPLACE FUNCTION worker.enqueue_statistical_unit_facet_reduce(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_dirty_partitions integer[] DEFAULT NULL::integer[], p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_priority BIGINT;
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));
  v_payload := jsonb_build_object(
    'command', 'statistical_unit_facet_reduce',
    'valid_from', v_valid_from,
    'valid_until', v_valid_until,
    'dirty_partitions', p_dirty_partitions,
    'round_priority_base', v_priority
  );
  INSERT INTO worker.tasks AS t (command, payload, priority)
  VALUES ('statistical_unit_facet_reduce', v_payload, v_priority)
  ON CONFLICT (command)
  WHERE command = 'statistical_unit_facet_reduce' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'statistical_unit_facet_reduce',
      'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
      'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date),
      'round_priority_base', LEAST(
        (t.payload->>'round_priority_base')::bigint,
        (EXCLUDED.payload->>'round_priority_base')::bigint
      )
    ),
    state = 'pending'::worker.task_state,
    priority = LEAST(t.priority, EXCLUDED.priority)
  RETURNING id INTO v_task_id;
  RETURN v_task_id;
END;
$function$;

CREATE OR REPLACE FUNCTION worker.enqueue_statistical_unit_facet_reduce(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN worker.enqueue_statistical_unit_facet_reduce(
    p_valid_from => p_valid_from,
    p_valid_until => p_valid_until,
    p_dirty_partitions => NULL,
    p_round_priority_base => NULL
  );
END;
$function$;

-- =============================================================================
-- Restore dedup indexes (Step 9 reverse)
-- =============================================================================
CREATE UNIQUE INDEX idx_tasks_derive_dedup ON worker.tasks (command) WHERE command = 'derive_statistical_unit' AND state = 'pending'::worker.task_state;
CREATE UNIQUE INDEX idx_tasks_derive_reports_dedup ON worker.tasks (command) WHERE command = 'derive_reports' AND state = 'pending'::worker.task_state;
CREATE UNIQUE INDEX idx_tasks_flush_staging_dedup ON worker.tasks (command) WHERE command = 'statistical_unit_flush_staging' AND state = 'pending'::worker.task_state;
CREATE UNIQUE INDEX idx_tasks_derive_statistical_history_dedup ON worker.tasks (command) WHERE command = 'derive_statistical_history' AND state = 'pending'::worker.task_state;
CREATE UNIQUE INDEX idx_tasks_statistical_history_reduce_dedup ON worker.tasks (command) WHERE command = 'statistical_history_reduce' AND state = 'pending'::worker.task_state;
CREATE UNIQUE INDEX idx_tasks_derive_statistical_unit_facet_dedup ON worker.tasks (command) WHERE command = 'derive_statistical_unit_facet' AND state = 'pending'::worker.task_state;
CREATE UNIQUE INDEX idx_tasks_derive_statistical_unit_facet_partition_dedup ON worker.tasks (command, ((payload->>'partition_seq')::integer)) WHERE command = 'derive_statistical_unit_facet_partition' AND state = 'pending'::worker.task_state;
CREATE UNIQUE INDEX idx_tasks_statistical_unit_facet_reduce_dedup ON worker.tasks (command) WHERE command = 'statistical_unit_facet_reduce' AND state = 'pending'::worker.task_state;
CREATE UNIQUE INDEX idx_tasks_derive_statistical_history_facet_dedup ON worker.tasks (command) WHERE command = 'derive_statistical_history_facet' AND state = 'pending'::worker.task_state;
CREATE UNIQUE INDEX idx_tasks_derive_history_facet_period_dedup ON worker.tasks (command, ((payload->>'resolution')), ((payload->>'year')), ((payload->>'month')), ((payload->>'partition_seq')::integer)) WHERE command = 'derive_statistical_history_facet_period' AND state = 'pending'::worker.task_state;
CREATE UNIQUE INDEX idx_tasks_statistical_history_facet_reduce_dedup ON worker.tasks (command) WHERE command = 'statistical_history_facet_reduce' AND state = 'pending'::worker.task_state;

-- =============================================================================
-- Restore handler procedures (Steps 6-8 reverse)
-- =============================================================================

-- Restore command_collect_changes (original version with enqueue call)
CREATE OR REPLACE PROCEDURE worker.command_collect_changes(IN p_payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
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
    v_round_priority_base BIGINT;
BEGIN
    FOR v_row IN DELETE FROM worker.base_change_log RETURNING * LOOP
        v_est_ids := v_est_ids + v_row.establishment_ids;
        v_lu_ids := v_lu_ids + v_row.legal_unit_ids;
        v_ent_ids := v_ent_ids + v_row.enterprise_ids;
        v_pg_ids := v_pg_ids + v_row.power_group_ids;
        v_valid_range := v_valid_range + v_row.valid_ranges;
    END LOOP;

    UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;

    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange
       OR v_pg_ids != '{}'::int4multirange THEN

        SELECT priority INTO v_round_priority_base
        FROM worker.tasks
        WHERE state = 'processing' AND worker_pid = pg_backend_pid()
        ORDER BY id DESC LIMIT 1;

        -- Notify frontend
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', true)::text);

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

        PERFORM worker.enqueue_derive_statistical_unit(
            p_establishment_id_ranges => v_est_ids,
            p_legal_unit_id_ranges => v_lu_ids,
            p_enterprise_id_ranges => v_ent_ids,
            p_power_group_id_ranges => v_pg_ids,
            p_valid_from => v_valid_from,
            p_valid_until => v_valid_until,
            p_round_priority_base => v_round_priority_base
        );
    ELSE
        PERFORM pg_notify('worker_status',
            json_build_object('type', 'is_deriving_statistical_units', 'status', false)::text);
    END IF;
END;
$procedure$;

-- Restore derive_statistical_unit function (with enqueue calls)
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange, p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange, p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange, p_power_group_id_ranges int4multirange DEFAULT NULL::int4multirange, p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_task_id bigint DEFAULT NULL::bigint, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_power_group_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_child_priority BIGINT;
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
    v_orphan_power_group_ids INT[];
    v_enterprise_count INT := 0;
    v_legal_unit_count INT := 0;
    v_establishment_count INT := 0;
    v_power_group_count INT := 0;
    v_partition_count INT;
    v_pg_batch_size INT;
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL
                         AND p_power_group_id_ranges IS NULL);

    v_child_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

    IF v_is_full_refresh THEN
        FOR v_batch IN SELECT * FROM public.get_closed_group_batches(p_target_batch_size => 1000)
        LOOP
            v_enterprise_count := v_enterprise_count + COALESCE(array_length(v_batch.enterprise_ids, 1), 0);
            v_legal_unit_count := v_legal_unit_count + COALESCE(array_length(v_batch.legal_unit_ids, 1), 0);
            v_establishment_count := v_establishment_count + COALESCE(array_length(v_batch.establishment_ids, 1), 0);

            PERFORM worker.spawn(
                p_command => 'statistical_unit_refresh_batch',
                p_payload => jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id => p_task_id,
                p_priority => v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;

        v_power_group_ids := ARRAY(SELECT id FROM public.power_group ORDER BY id);
        v_power_group_count := COALESCE(array_length(v_power_group_ids, 1), 0);
        IF v_power_group_count > 0 THEN
            SELECT analytics_partition_count INTO v_partition_count FROM public.settings;
            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / v_partition_count));
            FOR v_batch IN
                SELECT array_agg(pg_id ORDER BY pg_id) AS pg_ids
                FROM (SELECT pg_id, ((row_number() OVER (ORDER BY pg_id)) - 1) / v_pg_batch_size AS batch_idx
                      FROM unnest(v_power_group_ids) AS pg_id) AS t
                GROUP BY batch_idx ORDER BY batch_idx
            LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch_count + 1,
                        'power_group_ids', v_batch.pg_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id => p_task_id,
                    p_priority => v_child_priority
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;
    ELSE
        v_establishment_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r));
        v_legal_unit_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r));
        v_enterprise_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r));
        v_power_group_ids := ARRAY(SELECT generate_series(lower(r), upper(r)-1) FROM unnest(COALESCE(p_power_group_id_ranges, '{}'::int4multirange)) AS t(r));

        -- ORPHAN CLEANUP (abbreviated — same as original)
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(SELECT id FROM unnest(v_enterprise_ids) AS id EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids));
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(SELECT id FROM unnest(v_legal_unit_ids) AS id EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids));
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(SELECT id FROM unnest(v_establishment_ids) AS id EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids));
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;
        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_orphan_power_group_ids := ARRAY(SELECT id FROM unnest(v_power_group_ids) AS id EXCEPT SELECT pg.id FROM public.power_group AS pg WHERE pg.id = ANY(v_power_group_ids));
            IF COALESCE(array_length(v_orphan_power_group_ids, 1), 0) > 0 THEN
                DELETE FROM public.timepoints WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.timeline_power_group WHERE power_group_id = ANY(v_orphan_power_group_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'power_group' AND unit_id = ANY(v_orphan_power_group_ids);
            END IF;
        END IF;

        IF p_establishment_id_ranges IS NOT NULL
           OR p_legal_unit_id_ranges IS NOT NULL
           OR p_enterprise_id_ranges IS NOT NULL THEN
            IF to_regclass('pg_temp._batches') IS NOT NULL THEN DROP TABLE _batches; END IF;
            CREATE TEMP TABLE _batches ON COMMIT DROP AS
            SELECT * FROM public.get_closed_group_batches(
                p_target_batch_size => 1000,
                p_establishment_id_ranges => NULLIF(p_establishment_id_ranges, '{}'::int4multirange),
                p_legal_unit_id_ranges => NULLIF(p_legal_unit_id_ranges, '{}'::int4multirange),
                p_enterprise_id_ranges => NULLIF(p_enterprise_id_ranges, '{}'::int4multirange)
            );
            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq(t.unit_type, t.unit_id, (SELECT analytics_partition_count FROM public.settings))
            FROM (
                SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id FROM _batches AS b
                UNION ALL SELECT 'legal_unit', unnest(b.legal_unit_ids) FROM _batches AS b
                UNION ALL SELECT 'establishment', unnest(b.establishment_ids) FROM _batches AS b
            ) AS t WHERE t.unit_id IS NOT NULL
            ON CONFLICT DO NOTHING;

            <<effective_counts>>
            DECLARE
                v_all_batch_est_ranges int4multirange;
                v_all_batch_lu_ranges int4multirange;
                v_all_batch_en_ranges int4multirange;
                v_propagated_lu int4multirange;
                v_propagated_en int4multirange;
                v_eff_est int4multirange;
                v_eff_lu int4multirange;
                v_eff_en int4multirange;
            BEGIN
                v_all_batch_est_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(establishment_ids) AS id FROM _batches) AS t);
                v_all_batch_lu_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(legal_unit_ids) AS id FROM _batches) AS t);
                v_all_batch_en_ranges := (SELECT range_agg(int4range(id, id, '[]'))
                    FROM (SELECT unnest(enterprise_ids) AS id FROM _batches) AS t);

                v_eff_est := NULLIF(
                    COALESCE(v_all_batch_est_ranges, '{}'::int4multirange)
                    * COALESCE(p_establishment_id_ranges, '{}'::int4multirange),
                    '{}'::int4multirange);

                SELECT range_agg(int4range(es.legal_unit_id, es.legal_unit_id, '[]'))
                  INTO v_propagated_lu
                  FROM public.establishment AS es
                 WHERE es.id <@ COALESCE(p_establishment_id_ranges, '{}'::int4multirange)
                   AND es.legal_unit_id IS NOT NULL;
                v_eff_lu := NULLIF(
                    COALESCE(v_all_batch_lu_ranges, '{}'::int4multirange)
                    * (COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)
                     + COALESCE(v_propagated_lu, '{}'::int4multirange)),
                    '{}'::int4multirange);

                SELECT range_agg(int4range(lu.enterprise_id, lu.enterprise_id, '[]'))
                  INTO v_propagated_en
                  FROM public.legal_unit AS lu
                 WHERE lu.id <@ COALESCE(v_eff_lu, '{}'::int4multirange)
                   AND lu.enterprise_id IS NOT NULL;
                v_eff_en := NULLIF(
                    COALESCE(v_all_batch_en_ranges, '{}'::int4multirange)
                    * (COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)
                     + COALESCE(v_propagated_en, '{}'::int4multirange)),
                    '{}'::int4multirange);

                v_establishment_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_est, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
                v_legal_unit_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_lu, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
                v_enterprise_count := COALESCE((SELECT count(*) FROM unnest(COALESCE(v_eff_en, '{}'::int4multirange)) AS r, generate_series(lower(r), upper(r)-1))::INT, 0);
            END effective_counts;

            FOR v_batch IN SELECT * FROM _batches LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch.batch_seq,
                        'enterprise_ids', v_batch.enterprise_ids,
                        'legal_unit_ids', v_batch.legal_unit_ids,
                        'establishment_ids', v_batch.establishment_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until,
                        'changed_establishment_id_ranges', p_establishment_id_ranges::text,
                        'changed_legal_unit_id_ranges', p_legal_unit_id_ranges::text,
                        'changed_enterprise_id_ranges', p_enterprise_id_ranges::text
                    ),
                    p_parent_id => p_task_id,
                    p_priority => v_child_priority
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;

        IF COALESCE(array_length(v_power_group_ids, 1), 0) > 0 THEN
            v_power_group_count := array_length(v_power_group_ids, 1);
            INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
            SELECT DISTINCT public.report_partition_seq('power_group', pg_id, (SELECT analytics_partition_count FROM public.settings))
            FROM unnest(v_power_group_ids) AS pg_id
            ON CONFLICT DO NOTHING;

            SELECT analytics_partition_count INTO v_partition_count FROM public.settings;
            v_pg_batch_size := GREATEST(1, ceil(v_power_group_count::numeric / v_partition_count));
            FOR v_batch IN
                SELECT array_agg(pg_id ORDER BY pg_id) AS pg_ids
                FROM (SELECT pg_id, ((row_number() OVER (ORDER BY pg_id)) - 1) / v_pg_batch_size AS batch_idx
                      FROM unnest(v_power_group_ids) AS pg_id) AS t
                GROUP BY batch_idx ORDER BY batch_idx
            LOOP
                PERFORM worker.spawn(
                    p_command => 'statistical_unit_refresh_batch',
                    p_payload => jsonb_build_object(
                        'command', 'statistical_unit_refresh_batch',
                        'batch_seq', v_batch_count + 1,
                        'power_group_ids', v_batch.pg_ids,
                        'valid_from', p_valid_from,
                        'valid_until', p_valid_until
                    ),
                    p_parent_id => p_task_id,
                    p_priority => v_child_priority
                );
                v_batch_count := v_batch_count + 1;
            END LOOP;
        END IF;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %, counts: es=%, lu=%, en=%, pg=%',
        v_batch_count, p_task_id, v_establishment_count, v_legal_unit_count, v_enterprise_count, v_power_group_count;

    -- Store affected counts in own task's payload (for progress tracking via task tree)
    IF p_task_id IS NOT NULL THEN
        UPDATE worker.tasks
        SET payload = payload || jsonb_build_object(
            'affected_establishment_count', v_establishment_count,
            'affected_legal_unit_count', v_legal_unit_count,
            'affected_enterprise_count', v_enterprise_count,
            'affected_power_group_count', v_power_group_count
        )
        WHERE id = p_task_id;
    END IF;

    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_statistical_units', 'status', true)::text);

    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    PERFORM worker.enqueue_statistical_unit_flush_staging(
        p_round_priority_base => p_round_priority_base
    );
    PERFORM worker.enqueue_derive_reports(
        p_valid_from => p_valid_from,
        p_valid_until => p_valid_until,
        p_round_priority_base => p_round_priority_base
    );
END;
$function$;

-- Restore derive_reports function
CREATE OR REPLACE FUNCTION worker.derive_reports(p_valid_from date DEFAULT NULL::date, p_valid_until date DEFAULT NULL::date, p_round_priority_base bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM pg_notify('worker_status',
        json_build_object('type', 'is_deriving_reports', 'status', true)::text);

    CALL admin.adjust_analytics_partition_count();

    PERFORM worker.enqueue_derive_statistical_history(
        p_valid_from => p_valid_from,
        p_valid_until => p_valid_until,
        p_round_priority_base => p_round_priority_base
    );
END;
$function$;

-- Restore derive_reports procedure (original version calling function)
CREATE OR REPLACE PROCEDURE worker.derive_reports(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
    v_round_priority_base bigint = (payload->>'round_priority_base')::bigint;
BEGIN
  PERFORM worker.derive_reports(
    p_valid_from := v_valid_from,
    p_valid_until := v_valid_until,
    p_round_priority_base := v_round_priority_base
  );
END;
$procedure$;

-- Restore statistical_history_reduce (with enqueue call)
CREATE OR REPLACE PROCEDURE worker.statistical_history_reduce(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_round_priority_base bigint := (payload->>'round_priority_base')::bigint;
BEGIN
    DELETE FROM public.statistical_history WHERE partition_seq IS NULL;

    INSERT INTO public.statistical_history (
        resolution, year, month, unit_type,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count,
        physical_country_change_count, physical_address_change_count,
        stats_summary,
        partition_seq
    )
    SELECT
        resolution, year, month, unit_type,
        SUM(exists_count)::integer, SUM(exists_change)::integer,
        SUM(exists_added_count)::integer, SUM(exists_removed_count)::integer,
        SUM(countable_count)::integer, SUM(countable_change)::integer,
        SUM(countable_added_count)::integer, SUM(countable_removed_count)::integer,
        SUM(births)::integer, SUM(deaths)::integer,
        SUM(name_change_count)::integer, SUM(primary_activity_category_change_count)::integer,
        SUM(secondary_activity_category_change_count)::integer, SUM(sector_change_count)::integer,
        SUM(legal_form_change_count)::integer, SUM(physical_region_change_count)::integer,
        SUM(physical_country_change_count)::integer, SUM(physical_address_change_count)::integer,
        jsonb_stats_merge_agg(stats_summary),
        NULL
    FROM public.statistical_history
    WHERE partition_seq IS NOT NULL
    GROUP BY resolution, year, month, unit_type;

    PERFORM worker.enqueue_derive_statistical_unit_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_round_priority_base => v_round_priority_base
    );
END;
$procedure$;

-- Restore statistical_unit_facet_reduce (with payload-based dirty_partitions and enqueue call)
CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_round_priority_base bigint := (payload->>'round_priority_base')::bigint;
    v_dirty_partitions INT[];
BEGIN
    IF payload->'dirty_partitions' IS NOT NULL AND payload->'dirty_partitions' != 'null'::jsonb THEN
        SELECT array_agg(val::int)
        INTO v_dirty_partitions
        FROM jsonb_array_elements_text(payload->'dirty_partitions') AS val;
    END IF;

    TRUNCATE public.statistical_unit_facet;

    INSERT INTO public.statistical_unit_facet
    SELECT sufp.valid_from, sufp.valid_to, sufp.valid_until, sufp.unit_type,
           sufp.physical_region_path, sufp.primary_activity_category_path,
           sufp.sector_path, sufp.legal_form_id, sufp.physical_country_id, sufp.status_id,
           SUM(sufp.count)::BIGINT,
           jsonb_stats_merge_agg(sufp.stats_summary)
    FROM public.statistical_unit_facet_staging AS sufp
    GROUP BY sufp.valid_from, sufp.valid_to, sufp.valid_until, sufp.unit_type,
             sufp.physical_region_path, sufp.primary_activity_category_path,
             sufp.sector_path, sufp.legal_form_id, sufp.physical_country_id, sufp.status_id;

    IF v_dirty_partitions IS NOT NULL THEN
        DELETE FROM public.statistical_unit_facet_dirty_partitions
        WHERE partition_seq = ANY(v_dirty_partitions);
    ELSE
        TRUNCATE public.statistical_unit_facet_dirty_partitions;
    END IF;

    PERFORM worker.enqueue_derive_statistical_history_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_round_priority_base => v_round_priority_base
    );
END;
$procedure$;

-- =============================================================================
-- Restore progress functions (Step 12 reverse) — remove wrapper commands
-- =============================================================================

CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    SELECT jsonb_build_object(
        'active', EXISTS (
            SELECT 1 FROM worker.tasks
            WHERE command IN ('collect_changes', 'derive_statistical_unit', 'statistical_unit_refresh_batch', 'statistical_unit_flush_staging')
              AND state IN ('pending', 'processing', 'waiting')
        ),
        'step', (
            SELECT t.command FROM worker.tasks AS t
            WHERE t.command IN ('collect_changes', 'derive_statistical_unit', 'statistical_unit_refresh_batch', 'statistical_unit_flush_staging')
              AND (t.state IN ('processing', 'waiting') OR (t.command = 'collect_changes' AND t.state = 'pending'))
            ORDER BY t.id DESC LIMIT 1
        ),
        'total', COALESCE((
            SELECT count(*) FROM worker.tasks AS t
            WHERE t.command = 'statistical_unit_refresh_batch'
              AND EXISTS (
                  SELECT 1 FROM worker.tasks AS p
                  WHERE p.id = t.parent_id
                    AND p.command = 'derive_statistical_unit'
                    AND p.state IN ('processing', 'waiting')
              )
        ), 0),
        'completed', COALESCE((
            SELECT count(*) FROM worker.tasks AS t
            WHERE t.state IN ('completed', 'failed')
              AND t.command = 'statistical_unit_refresh_batch'
              AND EXISTS (
                  SELECT 1 FROM worker.tasks AS p
                  WHERE p.id = t.parent_id
                    AND p.command = 'derive_statistical_unit'
                    AND p.state IN ('processing', 'waiting')
              )
        ), 0),
        'affected_establishment_count', (
            SELECT (t.payload->>'affected_establishment_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'affected_legal_unit_count', (
            SELECT (t.payload->>'affected_legal_unit_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'affected_enterprise_count', (
            SELECT (t.payload->>'affected_enterprise_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'affected_power_group_count', (
            SELECT (t.payload->>'affected_power_group_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        )
    );
$function$;

CREATE OR REPLACE FUNCTION public.is_deriving_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
    SELECT jsonb_build_object(
        'active', EXISTS (
            SELECT 1 FROM worker.tasks
            WHERE command IN ('derive_reports', 'derive_statistical_history', 'derive_statistical_history_period',
                            'statistical_history_reduce', 'derive_statistical_unit_facet',
                            'derive_statistical_unit_facet_partition', 'statistical_unit_facet_reduce',
                            'derive_statistical_history_facet', 'derive_statistical_history_facet_period',
                            'statistical_history_facet_reduce')
              AND state IN ('pending', 'processing', 'waiting')
        ),
        'step', (
            SELECT t.command FROM worker.tasks AS t
            WHERE t.command IN ('derive_reports', 'derive_statistical_history',
                               'statistical_history_reduce', 'derive_statistical_unit_facet',
                               'statistical_unit_facet_reduce', 'derive_statistical_history_facet',
                               'statistical_history_facet_reduce')
              AND t.state IN ('processing', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'total', COALESCE((
            SELECT count(*) FROM worker.tasks AS t
            WHERE EXISTS (
                  SELECT 1 FROM worker.tasks AS p
                  WHERE p.id = t.parent_id
                    AND p.state IN ('processing', 'waiting')
                    AND p.command IN ('derive_statistical_history', 'derive_statistical_unit_facet',
                                    'derive_statistical_history_facet')
              )
        ), 0),
        'completed', COALESCE((
            SELECT count(*) FROM worker.tasks AS t
            WHERE t.state IN ('completed', 'failed')
              AND EXISTS (
                  SELECT 1 FROM worker.tasks AS p
                  WHERE p.id = t.parent_id
                    AND p.state IN ('processing', 'waiting')
                    AND p.command IN ('derive_statistical_history', 'derive_statistical_unit_facet',
                                    'derive_statistical_history_facet')
              )
        ), 0),
        'affected_establishment_count', (
            SELECT (t.payload->>'affected_establishment_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'affected_legal_unit_count', (
            SELECT (t.payload->>'affected_legal_unit_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'affected_enterprise_count', (
            SELECT (t.payload->>'affected_enterprise_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        ),
        'affected_power_group_count', (
            SELECT (t.payload->>'affected_power_group_count')::int
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1
        )
    );
$function$;

-- Restore notify_task_progress (without wrapper commands)
CREATE OR REPLACE FUNCTION worker.notify_task_progress()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_payload JSONB;
    v_phases JSONB := '[]'::jsonb;
    v_units_phase JSONB;
    v_reports_phase JSONB;
    v_units_active BOOLEAN;
    v_units_step TEXT;
    v_units_total BIGINT;
    v_units_completed BIGINT;
    v_affected_est INT;
    v_affected_lu INT;
    v_affected_en INT;
    v_affected_pg INT;
    v_reports_active BOOLEAN;
    v_reports_step TEXT;
    v_reports_total BIGINT;
    v_reports_completed BIGINT;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM worker.tasks
        WHERE command IN ('collect_changes', 'derive_statistical_unit', 'statistical_unit_refresh_batch', 'statistical_unit_flush_staging')
          AND state IN ('pending', 'processing', 'waiting')
    ) INTO v_units_active;

    IF v_units_active THEN
        SELECT t.command INTO v_units_step
        FROM worker.tasks AS t
        WHERE t.command IN ('collect_changes', 'derive_statistical_unit', 'statistical_unit_refresh_batch', 'statistical_unit_flush_staging')
          AND (t.state IN ('processing', 'waiting') OR (t.command = 'collect_changes' AND t.state = 'pending'))
        ORDER BY t.id DESC LIMIT 1;

        SELECT count(*) INTO v_units_total
        FROM worker.tasks AS t
        WHERE t.command = 'statistical_unit_refresh_batch'
          AND EXISTS (
              SELECT 1 FROM worker.tasks AS p
              WHERE p.id = t.parent_id
                AND p.command = 'derive_statistical_unit'
                AND p.state IN ('processing', 'waiting')
          );

        SELECT count(*) INTO v_units_completed
        FROM worker.tasks AS t
        WHERE t.state IN ('completed', 'failed')
          AND t.command = 'statistical_unit_refresh_batch'
          AND EXISTS (
              SELECT 1 FROM worker.tasks AS p
              WHERE p.id = t.parent_id
                AND p.command = 'derive_statistical_unit'
                AND p.state IN ('processing', 'waiting')
          );

        SELECT (t.payload->>'affected_establishment_count')::int,
               (t.payload->>'affected_legal_unit_count')::int,
               (t.payload->>'affected_enterprise_count')::int,
               (t.payload->>'affected_power_group_count')::int
        INTO v_affected_est, v_affected_lu, v_affected_en, v_affected_pg
        FROM worker.tasks AS t
        WHERE t.command = 'derive_statistical_unit'
          AND t.state IN ('processing', 'waiting')
        ORDER BY t.id DESC LIMIT 1;

        v_units_phase := jsonb_build_object(
            'phase', 'is_deriving_statistical_units',
            'step', v_units_step,
            'total', COALESCE(v_units_total, 0),
            'completed', COALESCE(v_units_completed, 0),
            'affected_establishment_count', v_affected_est,
            'affected_legal_unit_count', v_affected_lu,
            'affected_enterprise_count', v_affected_en,
            'affected_power_group_count', v_affected_pg
        );
        v_phases := v_phases || jsonb_build_array(v_units_phase);
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM worker.tasks
        WHERE command IN ('derive_reports', 'derive_statistical_history', 'derive_statistical_history_period',
                         'statistical_history_reduce', 'derive_statistical_unit_facet',
                         'derive_statistical_unit_facet_partition', 'statistical_unit_facet_reduce',
                         'derive_statistical_history_facet', 'derive_statistical_history_facet_period',
                         'statistical_history_facet_reduce')
          AND state IN ('pending', 'processing', 'waiting')
    ) INTO v_reports_active;

    IF v_reports_active THEN
        SELECT t.command INTO v_reports_step
        FROM worker.tasks AS t
        WHERE t.command IN ('derive_reports', 'derive_statistical_history',
                           'statistical_history_reduce', 'derive_statistical_unit_facet',
                           'statistical_unit_facet_reduce', 'derive_statistical_history_facet',
                           'statistical_history_facet_reduce')
          AND t.state IN ('processing', 'waiting')
        ORDER BY t.id DESC LIMIT 1;

        SELECT count(*) INTO v_reports_total
        FROM worker.tasks AS t
        WHERE EXISTS (
              SELECT 1 FROM worker.tasks AS p
              WHERE p.id = t.parent_id
                AND p.state IN ('processing', 'waiting')
                AND p.command IN ('derive_statistical_history', 'derive_statistical_unit_facet',
                                'derive_statistical_history_facet')
          );

        SELECT count(*) INTO v_reports_completed
        FROM worker.tasks AS t
        WHERE t.state IN ('completed', 'failed')
          AND EXISTS (
              SELECT 1 FROM worker.tasks AS p
              WHERE p.id = t.parent_id
                AND p.state IN ('processing', 'waiting')
                AND p.command IN ('derive_statistical_history', 'derive_statistical_unit_facet',
                                'derive_statistical_history_facet')
          );

        IF v_affected_est IS NULL THEN
            SELECT (t.payload->>'affected_establishment_count')::int,
                   (t.payload->>'affected_legal_unit_count')::int,
                   (t.payload->>'affected_enterprise_count')::int,
                   (t.payload->>'affected_power_group_count')::int
            INTO v_affected_est, v_affected_lu, v_affected_en, v_affected_pg
            FROM worker.tasks AS t
            WHERE t.command = 'derive_statistical_unit'
              AND t.state IN ('completed', 'waiting')
            ORDER BY t.id DESC LIMIT 1;
        END IF;

        v_reports_phase := jsonb_build_object(
            'phase', 'is_deriving_reports',
            'step', v_reports_step,
            'total', COALESCE(v_reports_total, 0),
            'completed', COALESCE(v_reports_completed, 0),
            'affected_establishment_count', v_affected_est,
            'affected_legal_unit_count', v_affected_lu,
            'affected_enterprise_count', v_affected_en,
            'affected_power_group_count', v_affected_pg
        );
        v_phases := v_phases || jsonb_build_array(v_reports_phase);
    END IF;

    IF jsonb_array_length(v_phases) > 0 THEN
        v_payload := jsonb_build_object(
            'type', 'pipeline_progress',
            'phases', v_phases
        );
        PERFORM pg_notify('worker_status', v_payload::text);
    END IF;
END;
$function$;

-- =============================================================================
-- Restore process_tasks (without cascade-fail) — Step 5 reverse
-- =============================================================================
CREATE OR REPLACE PROCEDURE worker.process_tasks(IN p_batch_size integer DEFAULT NULL::integer, IN p_max_runtime_ms integer DEFAULT NULL::integer, IN p_queue text DEFAULT NULL::text, IN p_max_priority bigint DEFAULT NULL::bigint, IN p_mode worker.process_mode DEFAULT NULL::worker.process_mode)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  task_record RECORD;
  start_time TIMESTAMPTZ;
  batch_start_time TIMESTAMPTZ;
  elapsed_ms NUMERIC;
  processed_count INT := 0;
  v_inside_transaction BOOLEAN;
  v_waiting_parent_id BIGINT;
  v_waiting_parent_child_mode worker.child_mode;
  v_max_retries CONSTANT INT := 3;
  v_retry_count INT;
  v_backoff_base_ms CONSTANT NUMERIC := 100;
BEGIN
  SELECT pg_current_xact_id_if_assigned() IS NOT NULL INTO v_inside_transaction;
  RAISE DEBUG 'Running worker.process_tasks inside transaction: %, queue: %, mode: %',
    v_inside_transaction, p_queue, COALESCE(p_mode::text, 'NULL');

  batch_start_time := clock_timestamp();

  LOOP
    IF p_max_runtime_ms IS NOT NULL AND
       EXTRACT(EPOCH FROM (clock_timestamp() - batch_start_time)) * 1000 > p_max_runtime_ms THEN
      EXIT;
    END IF;

    SELECT t.id, t.child_mode
    INTO v_waiting_parent_id, v_waiting_parent_child_mode
    FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON t.command = cr.command
    WHERE t.state = 'waiting'::worker.task_state
      AND (p_queue IS NULL OR cr.queue = p_queue)
    ORDER BY t.depth DESC, t.priority, t.id
    LIMIT 1;

    IF p_mode = 'top' THEN
      IF v_waiting_parent_id IS NOT NULL THEN
        RAISE DEBUG 'Top mode: waiting parent % exists, returning', v_waiting_parent_id;
        EXIT;
      END IF;

      SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
      INTO task_record
      FROM worker.tasks AS t
      JOIN worker.command_registry AS cr ON t.command = cr.command
      WHERE t.state = 'pending'::worker.task_state
        AND t.parent_id IS NULL
        AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
        AND (p_queue IS NULL OR cr.queue = p_queue)
        AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
      ORDER BY
        CASE WHEN t.scheduled_at IS NULL THEN 0 ELSE 1 END,
        t.scheduled_at,
        t.priority ASC NULLS LAST,
        t.id
      LIMIT 1
      FOR UPDATE OF t SKIP LOCKED;

    ELSIF p_mode = 'child' THEN
      IF v_waiting_parent_id IS NULL THEN
        RAISE DEBUG 'Child mode: no waiting parent, returning';
        EXIT;
      END IF;

      IF v_waiting_parent_child_mode = 'serial' THEN
        IF EXISTS (
          SELECT 1 FROM worker.tasks
          WHERE parent_id = v_waiting_parent_id
            AND state IN ('processing', 'waiting')
        ) THEN
          RAISE DEBUG 'Child mode: serial parent %, sibling still active', v_waiting_parent_id;
          EXIT;
        END IF;
      END IF;

      SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
      INTO task_record
      FROM worker.tasks AS t
      JOIN worker.command_registry AS cr ON t.command = cr.command
      WHERE t.state = 'pending'::worker.task_state
        AND t.parent_id = v_waiting_parent_id
        AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
        AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
      ORDER BY t.priority ASC NULLS LAST, t.id
      LIMIT 1
      FOR UPDATE OF t SKIP LOCKED;

    ELSE
      IF v_waiting_parent_id IS NOT NULL THEN
        IF v_waiting_parent_child_mode = 'serial' THEN
          IF EXISTS (
            SELECT 1 FROM worker.tasks
            WHERE parent_id = v_waiting_parent_id
              AND state IN ('processing', 'waiting')
          ) THEN
            v_waiting_parent_id := NULL;
          END IF;
        END IF;

        IF v_waiting_parent_id IS NOT NULL THEN
          SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
          INTO task_record
          FROM worker.tasks AS t
          JOIN worker.command_registry AS cr ON t.command = cr.command
          WHERE t.state = 'pending'::worker.task_state
            AND t.parent_id = v_waiting_parent_id
            AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
            AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
          ORDER BY t.priority ASC NULLS LAST, t.id
          LIMIT 1
          FOR UPDATE OF t SKIP LOCKED;
        END IF;
      END IF;

      IF v_waiting_parent_id IS NULL OR NOT FOUND THEN
        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
        INTO task_record
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE t.state = 'pending'::worker.task_state
          AND t.parent_id IS NULL
          AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
          AND (p_queue IS NULL OR cr.queue = p_queue)
          AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
        ORDER BY
          CASE WHEN t.scheduled_at IS NULL THEN 0 ELSE 1 END,
          t.scheduled_at,
          t.priority ASC NULLS LAST,
          t.id
        LIMIT 1
        FOR UPDATE OF t SKIP LOCKED;
      END IF;
    END IF;

    IF NOT FOUND THEN
      EXIT;
    END IF;

    start_time := clock_timestamp();

    UPDATE worker.tasks AS t
    SET state = 'processing'::worker.task_state,
        worker_pid = pg_backend_pid()
    WHERE t.id = task_record.id;

    IF task_record.before_procedure IS NOT NULL THEN
      BEGIN
        EXECUTE format('CALL %s()', task_record.before_procedure);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Error in before_procedure % for task %: %', task_record.before_procedure, task_record.id, SQLERRM;
      END;
    END IF;

    IF NOT v_inside_transaction THEN
      COMMIT;
    END IF;

    DECLARE
      v_state worker.task_state;
      v_processed_at TIMESTAMPTZ;
      v_completed_at TIMESTAMPTZ;
      v_duration_ms NUMERIC;
      v_error TEXT DEFAULT NULL;
      v_has_children BOOLEAN;
    BEGIN
      v_retry_count := 0;

      <<retry_loop>>
      LOOP
        DECLARE
          v_message_text TEXT;
          v_pg_exception_detail TEXT;
          v_pg_exception_hint TEXT;
          v_pg_exception_context TEXT;
        BEGIN
          IF task_record.handler_procedure IS NOT NULL THEN
            EXECUTE format('CALL %s($1)', task_record.handler_procedure)
            USING task_record.payload;
          ELSE
            RAISE EXCEPTION 'No handler procedure found for command: %', task_record.command;
          END IF;

          elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
          v_processed_at := clock_timestamp();
          v_duration_ms := elapsed_ms;

          SELECT EXISTS (
            SELECT 1 FROM worker.tasks WHERE parent_id = task_record.id
          ) INTO v_has_children;

          IF v_has_children THEN
            v_state := 'waiting'::worker.task_state;
            v_completed_at := NULL;
          ELSE
            v_state := 'completed'::worker.task_state;
            v_completed_at := clock_timestamp();
          END IF;

          EXIT retry_loop;

        EXCEPTION
          WHEN deadlock_detected THEN
            v_retry_count := v_retry_count + 1;
            IF v_retry_count <= v_max_retries THEN
              RAISE WARNING 'Task % (%) deadlock detected, retry %/%',
                task_record.id, task_record.command, v_retry_count, v_max_retries;
              PERFORM pg_sleep((v_backoff_base_ms * power(2, v_retry_count - 1) + (random() * 50)) / 1000.0);
              CONTINUE retry_loop;
            END IF;

            elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
            v_state := 'failed'::worker.task_state;
            v_processed_at := clock_timestamp();
            v_completed_at := clock_timestamp();
            v_duration_ms := elapsed_ms;
            v_error := format('Deadlock detected after %s retries', v_retry_count);
            EXIT retry_loop;

          WHEN serialization_failure THEN
            v_retry_count := v_retry_count + 1;
            IF v_retry_count <= v_max_retries THEN
              RAISE WARNING 'Task % (%) serialization failure, retry %/%',
                task_record.id, task_record.command, v_retry_count, v_max_retries;
              PERFORM pg_sleep((v_backoff_base_ms * power(2, v_retry_count - 1) + (random() * 50)) / 1000.0);
              CONTINUE retry_loop;
            END IF;

            elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
            v_state := 'failed'::worker.task_state;
            v_processed_at := clock_timestamp();
            v_completed_at := clock_timestamp();
            v_duration_ms := elapsed_ms;
            v_error := format('Serialization failure after %s retries', v_retry_count);
            EXIT retry_loop;

          WHEN OTHERS THEN
            elapsed_ms := EXTRACT(EPOCH FROM (clock_timestamp() - start_time)) * 1000;
            v_state := 'failed'::worker.task_state;
            v_processed_at := clock_timestamp();
            v_completed_at := clock_timestamp();
            v_duration_ms := elapsed_ms;

            GET STACKED DIAGNOSTICS
              v_message_text = MESSAGE_TEXT,
              v_pg_exception_detail = PG_EXCEPTION_DETAIL,
              v_pg_exception_hint = PG_EXCEPTION_HINT,
              v_pg_exception_context = PG_EXCEPTION_CONTEXT;

            v_error := format(
              'Error: %s%sContext: %s%sDetail: %s%sHint: %s',
              v_message_text, E'\n',
              v_pg_exception_context, E'\n',
              COALESCE(v_pg_exception_detail, ''), E'\n',
              COALESCE(v_pg_exception_hint, '')
            );

            RAISE WARNING 'Task % (%) failed in % ms: %', task_record.id, task_record.command, elapsed_ms, v_error;
            EXIT retry_loop;
        END;
      END LOOP retry_loop;

      UPDATE worker.tasks AS t
      SET state = v_state,
          processed_at = v_processed_at,
          completed_at = v_completed_at,
          duration_ms = v_duration_ms,
          error = v_error
      WHERE t.id = task_record.id;

      IF v_inside_transaction AND task_record.parent_id IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        PERFORM worker.complete_parent_if_ready(task_record.id);
      END IF;

      IF task_record.after_procedure IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        BEGIN
          EXECUTE format('CALL %s()', task_record.after_procedure);
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'Error in after_procedure % for task %: %', task_record.after_procedure, task_record.id, SQLERRM;
        END;
      END IF;

      IF NOT v_inside_transaction THEN
        COMMIT;
      END IF;

      IF NOT v_inside_transaction AND task_record.parent_id IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        PERFORM worker.complete_parent_if_ready(task_record.id);
        COMMIT;
      END IF;

      IF task_record.queue = 'analytics' THEN
        PERFORM worker.notify_task_progress();
        IF NOT v_inside_transaction THEN
          COMMIT;
        END IF;
      END IF;
    END;

    processed_count := processed_count + 1;
    IF p_batch_size IS NOT NULL AND processed_count >= p_batch_size THEN
      EXIT;
    END IF;
  END LOOP;
END;
$procedure$;

-- Drop cascade-fail function (Step 5 reverse)
DROP FUNCTION IF EXISTS worker.cascade_fail_descendants(bigint);

-- Drop wrapper procedures (Step 4 reverse)
DROP PROCEDURE IF EXISTS worker.derive_units_phase(jsonb);
DROP PROCEDURE IF EXISTS worker.derive_reports_phase(jsonb);

-- Remove wrapper commands from registry (Step 3 reverse)
DELETE FROM worker.command_registry WHERE command IN ('derive_units_phase', 'derive_reports_phase');

COMMIT;
