-- Migration 20260224191329: fix_pipeline_round_priority_and_progress_reporting
--
-- Fix 1: Round-based priority — all tasks in a pipeline round get the SAME
--         priority (the collect_changes task's priority). Within a round,
--         ORDER BY priority ASC, id tiebreaks by creation order.
--
-- Fix 2: Progress reporting — is_deriving_reports() and
--         is_deriving_statistical_units() now also check worker.tasks for
--         pending/processing/waiting analytics tasks, not just pipeline_progress.
BEGIN;

-- =========================================================================
-- Fix 2: Progress reporting
-- =========================================================================

CREATE OR REPLACE FUNCTION public.is_deriving_reports()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object(
    'active', (
      EXISTS (
        SELECT 1 FROM worker.pipeline_progress
        WHERE step IN (
          'derive_reports',
          'derive_statistical_history',
          'derive_statistical_history_period',
          'statistical_history_reduce',
          'derive_statistical_unit_facet',
          'derive_statistical_unit_facet_partition',
          'statistical_unit_facet_reduce',
          'derive_statistical_history_facet',
          'derive_statistical_history_facet_period',
          'statistical_history_facet_reduce'
        )
      )
      OR EXISTS (
        SELECT 1 FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE cr.queue = 'analytics'
          AND t.command IN (
            'derive_reports',
            'derive_statistical_history',
            'derive_statistical_history_period',
            'statistical_history_reduce',
            'derive_statistical_unit_facet',
            'derive_statistical_unit_facet_partition',
            'statistical_unit_facet_reduce',
            'derive_statistical_history_facet',
            'derive_statistical_history_facet_period',
            'statistical_history_facet_reduce'
          )
          AND t.state IN ('pending', 'processing', 'waiting')
      )
    ),
    'progress', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'step', pp.step, 'total', pp.total, 'completed', pp.completed
      )) FROM worker.pipeline_progress AS pp
      WHERE pp.step IN (
        'derive_statistical_history',
        'derive_statistical_unit_facet',
        'derive_statistical_history_facet'
      )
        AND pp.total > 1),
      '[]'::jsonb
    )
  );
$function$;

CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object(
    'active', (
      EXISTS (
        SELECT 1 FROM worker.pipeline_progress
        WHERE step IN (
          'derive_statistical_unit',
          'derive_statistical_unit_continue',
          'statistical_unit_refresh_batch',
          'statistical_unit_flush_staging'
        )
      )
      OR EXISTS (
        SELECT 1 FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE cr.queue = 'analytics'
          AND t.command IN (
            'derive_statistical_unit',
            'derive_statistical_unit_continue',
            'statistical_unit_refresh_batch',
            'statistical_unit_flush_staging'
          )
          AND t.state IN ('pending', 'processing', 'waiting')
      )
    ),
    'progress', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'step', pp.step, 'total', pp.total, 'completed', pp.completed
      )) FROM worker.pipeline_progress AS pp
      WHERE pp.step IN (
        'derive_statistical_unit',
        'derive_statistical_unit_continue'
      )
        AND pp.total > 1),
      '[]'::jsonb
    )
  );
$function$;

-- =========================================================================
-- Fix 1: Round-based priority — enqueue functions
-- =========================================================================

-- DROP old overloads first: adding a DEFAULT parameter creates ambiguous
-- overloads, so we must drop the old signatures before creating new ones.
-- The new functions accept the same parameters plus p_round_priority_base
-- with DEFAULT NULL, making them backward compatible.
DROP FUNCTION worker.enqueue_derive_statistical_unit(int4multirange, int4multirange, int4multirange, date, date);
DROP FUNCTION worker.enqueue_statistical_unit_flush_staging();
DROP FUNCTION worker.enqueue_derive_reports(date, date);
DROP FUNCTION worker.enqueue_derive_statistical_history(date, date);
DROP FUNCTION worker.enqueue_statistical_history_reduce(date, date);
DROP FUNCTION worker.enqueue_derive_statistical_unit_facet(date, date);
-- Keep enqueue_statistical_unit_facet_reduce(date, date) unchanged (no round_priority_base)
-- Only modify the 3-arg version by adding 4th param — must drop 3-arg first
DROP FUNCTION worker.enqueue_statistical_unit_facet_reduce(date, date, integer[]);
DROP FUNCTION worker.enqueue_derive_statistical_history_facet(date, date);
DROP FUNCTION worker.enqueue_statistical_history_facet_reduce(date, date);

-- Also drop old handler overloads that gain the round_priority_base parameter
DROP FUNCTION worker.derive_statistical_unit(int4multirange, int4multirange, int4multirange, date, date, bigint);
DROP FUNCTION worker.derive_reports(date, date);

-- enqueue_derive_statistical_unit: add p_round_priority_base parameter
CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_unit(
    p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date,
    p_round_priority_base bigint DEFAULT NULL
)
 RETURNS bigint
 LANGUAGE plpgsql
AS $enqueue_derive_statistical_unit$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_priority BIGINT;
  v_establishment_id_ranges int4multirange := COALESCE(p_establishment_id_ranges, '{}'::int4multirange);
  v_legal_unit_id_ranges int4multirange := COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange);
  v_enterprise_id_ranges int4multirange := COALESCE(p_enterprise_id_ranges, '{}'::int4multirange);
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  -- Round priority: use round base if provided, otherwise fall back to sequence
  v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

  v_payload := jsonb_build_object(
    'command', 'derive_statistical_unit',
    'establishment_id_ranges', v_establishment_id_ranges,
    'legal_unit_id_ranges', v_legal_unit_id_ranges,
    'enterprise_id_ranges', v_enterprise_id_ranges,
    'valid_from', v_valid_from,
    'valid_until', v_valid_until,
    'round_priority_base', v_priority
  );

  INSERT INTO worker.tasks AS t (
    command, payload, priority
  ) VALUES ('derive_statistical_unit', v_payload, v_priority)
  ON CONFLICT (command)
  WHERE command = 'derive_statistical_unit' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_statistical_unit',
      'establishment_id_ranges', (t.payload->>'establishment_id_ranges')::int4multirange + (EXCLUDED.payload->>'establishment_id_ranges')::int4multirange,
      'legal_unit_id_ranges', (t.payload->>'legal_unit_id_ranges')::int4multirange + (EXCLUDED.payload->>'legal_unit_id_ranges')::int4multirange,
      'enterprise_id_ranges', (t.payload->>'enterprise_id_ranges')::int4multirange + (EXCLUDED.payload->>'enterprise_id_ranges')::int4multirange,
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
$enqueue_derive_statistical_unit$;

-- enqueue_statistical_unit_flush_staging: add p_round_priority_base
CREATE OR REPLACE FUNCTION worker.enqueue_statistical_unit_flush_staging(
    p_round_priority_base bigint DEFAULT NULL
)
 RETURNS bigint
 LANGUAGE plpgsql
AS $enqueue_statistical_unit_flush_staging$
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
$enqueue_statistical_unit_flush_staging$;

-- enqueue_derive_reports: add p_round_priority_base
CREATE OR REPLACE FUNCTION worker.enqueue_derive_reports(
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date,
    p_round_priority_base bigint DEFAULT NULL
)
 RETURNS bigint
 LANGUAGE plpgsql
AS $enqueue_derive_reports$
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
$enqueue_derive_reports$;

-- enqueue_derive_statistical_history: add p_round_priority_base
CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_history(
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date,
    p_round_priority_base bigint DEFAULT NULL
)
 RETURNS bigint
 LANGUAGE plpgsql
AS $enqueue_derive_statistical_history$
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
$enqueue_derive_statistical_history$;

-- enqueue_statistical_history_reduce: add p_round_priority_base
CREATE OR REPLACE FUNCTION worker.enqueue_statistical_history_reduce(
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date,
    p_round_priority_base bigint DEFAULT NULL
)
 RETURNS bigint
 LANGUAGE plpgsql
AS $enqueue_statistical_history_reduce$
DECLARE
    v_task_id BIGINT;
    v_priority BIGINT;
    v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
    v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
    v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

    INSERT INTO worker.tasks AS t (command, payload, priority)
    VALUES ('statistical_history_reduce', jsonb_build_object(
        'command', 'statistical_history_reduce',
        'valid_from', v_valid_from,
        'valid_until', v_valid_until,
        'round_priority_base', v_priority
    ), v_priority)
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
$enqueue_statistical_history_reduce$;

-- enqueue_derive_statistical_unit_facet: add p_round_priority_base
CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_unit_facet(
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date,
    p_round_priority_base bigint DEFAULT NULL
)
 RETURNS bigint
 LANGUAGE plpgsql
AS $enqueue_derive_statistical_unit_facet$
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
$enqueue_derive_statistical_unit_facet$;

-- enqueue_statistical_unit_facet_reduce (2-arg): add p_round_priority_base
CREATE OR REPLACE FUNCTION worker.enqueue_statistical_unit_facet_reduce(
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date
)
 RETURNS bigint
 LANGUAGE plpgsql
AS $enqueue_statistical_unit_facet_reduce$
DECLARE
    v_task_id BIGINT;
    v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
    v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
    -- 2-arg overload: no round_priority_base, falls through to column default
    INSERT INTO worker.tasks AS t (command, payload)
    VALUES ('statistical_unit_facet_reduce', jsonb_build_object(
        'command', 'statistical_unit_facet_reduce',
        'valid_from', v_valid_from,
        'valid_until', v_valid_until
    ))
    ON CONFLICT (command)
    WHERE command = 'statistical_unit_facet_reduce' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        payload = jsonb_build_object(
            'command', 'statistical_unit_facet_reduce',
            'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
            'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date)
        ),
        state = 'pending'::worker.task_state
    RETURNING id INTO v_task_id;

    RETURN v_task_id;
END;
$enqueue_statistical_unit_facet_reduce$;

-- enqueue_statistical_unit_facet_reduce (3-arg with dirty_partitions): add p_round_priority_base
CREATE OR REPLACE FUNCTION worker.enqueue_statistical_unit_facet_reduce(
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date,
    p_dirty_partitions integer[] DEFAULT NULL::integer[],
    p_round_priority_base bigint DEFAULT NULL
)
 RETURNS bigint
 LANGUAGE plpgsql
AS $enqueue_statistical_unit_facet_reduce_dirty$
DECLARE
    v_task_id BIGINT;
    v_priority BIGINT;
    v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
    v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
    v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

    INSERT INTO worker.tasks AS t (command, payload, priority)
    VALUES ('statistical_unit_facet_reduce', jsonb_build_object(
        'command', 'statistical_unit_facet_reduce',
        'valid_from', v_valid_from,
        'valid_until', v_valid_until,
        'dirty_partitions', p_dirty_partitions,
        'round_priority_base', v_priority
    ), v_priority)
    ON CONFLICT (command)
    WHERE command = 'statistical_unit_facet_reduce' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        payload = jsonb_build_object(
            'command', 'statistical_unit_facet_reduce',
            'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
            'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date),
            'dirty_partitions', CASE
                WHEN t.payload->'dirty_partitions' = 'null'::jsonb
                  OR EXCLUDED.payload->'dirty_partitions' = 'null'::jsonb
                THEN NULL
                ELSE (
                    SELECT jsonb_agg(DISTINCT val ORDER BY val)
                    FROM (
                        SELECT jsonb_array_elements(t.payload->'dirty_partitions') AS val
                        UNION
                        SELECT jsonb_array_elements(EXCLUDED.payload->'dirty_partitions') AS val
                    ) AS combined
                )
            END,
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
$enqueue_statistical_unit_facet_reduce_dirty$;

-- enqueue_derive_statistical_history_facet: add p_round_priority_base
CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_history_facet(
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date,
    p_round_priority_base bigint DEFAULT NULL
)
 RETURNS bigint
 LANGUAGE plpgsql
AS $enqueue_derive_statistical_history_facet$
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
$enqueue_derive_statistical_history_facet$;

-- enqueue_statistical_history_facet_reduce: add p_round_priority_base
CREATE OR REPLACE FUNCTION worker.enqueue_statistical_history_facet_reduce(
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date,
    p_round_priority_base bigint DEFAULT NULL
)
 RETURNS bigint
 LANGUAGE plpgsql
AS $enqueue_statistical_history_facet_reduce$
DECLARE
    v_task_id BIGINT;
    v_priority BIGINT;
    v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
    v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
    v_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

    INSERT INTO worker.tasks AS t (command, payload, priority)
    VALUES ('statistical_history_facet_reduce', jsonb_build_object(
        'command', 'statistical_history_facet_reduce',
        'valid_from', v_valid_from,
        'valid_until', v_valid_until,
        'round_priority_base', v_priority
    ), v_priority)
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
$enqueue_statistical_history_facet_reduce$;

-- =========================================================================
-- Fix 1: Round-based priority — handlers (read + propagate round_priority_base)
-- =========================================================================

-- command_collect_changes: read own priority as round base, reserve block, propagate
CREATE OR REPLACE PROCEDURE worker.command_collect_changes(IN p_payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $command_collect_changes$
DECLARE
    v_row RECORD;
    v_est_ids int4multirange := '{}'::int4multirange;
    v_lu_ids int4multirange := '{}'::int4multirange;
    v_ent_ids int4multirange := '{}'::int4multirange;
    v_valid_range datemultirange := '{}'::datemultirange;
    v_valid_from DATE;
    v_valid_until DATE;
    v_round_priority_base BIGINT;
BEGIN
    -- Atomically drain all committed rows, merging multiranges.
    -- No FOR UPDATE needed: structured concurrency ensures only one
    -- collect_changes runs at a time (serial top-level analytics tasks).
    FOR v_row IN DELETE FROM worker.base_change_log RETURNING * LOOP
        v_est_ids := v_est_ids + v_row.establishment_ids;
        v_lu_ids := v_lu_ids + v_row.legal_unit_ids;
        v_ent_ids := v_ent_ids + v_row.enterprise_ids;
        v_valid_range := v_valid_range + v_row.edited_by_valid_range;
    END LOOP;

    -- Clear crash recovery flag
    UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;

    -- If any changes exist, enqueue derive
    IF v_est_ids != '{}'::int4multirange
       OR v_lu_ids != '{}'::int4multirange
       OR v_ent_ids != '{}'::int4multirange THEN

        -- ROUND PRIORITY: Read own priority as the round base.
        -- All downstream tasks in this pipeline round will share this priority.
        -- With equal priority, ORDER BY priority ASC, id tiebreaks by creation order.
        -- No sequence reservation needed: the sequence is monotonically increasing,
        -- so any future collect_changes always gets a higher priority number.
        SELECT priority INTO v_round_priority_base
        FROM worker.tasks
        WHERE state = 'processing' AND worker_pid = pg_backend_pid()
        ORDER BY id DESC LIMIT 1;

        -- If date range is empty (all changes from tables without valid_range,
        -- e.g. enterprise or external_ident), look up actual valid ranges from
        -- affected units to avoid full-scope refresh.
        IF v_valid_range = '{}'::datemultirange THEN
            SELECT COALESCE(range_agg(vr)::datemultirange, '{}'::datemultirange)
            INTO v_valid_range
            FROM (
                SELECT valid_range AS vr FROM public.establishment AS est
                  WHERE v_est_ids @> est.id
                UNION ALL
                SELECT valid_range AS vr FROM public.legal_unit AS lu
                  WHERE v_lu_ids @> lu.id
            ) AS units;
            -- Note: enterprise has no valid_range. If only enterprise IDs changed
            -- and no est/lu IDs, v_valid_range stays empty -> enqueue_derive
            -- COALESCEs to -infinity/infinity, which is correct for structural changes.
        END IF;

        -- Extract date bounds for enqueue_derive interface (takes DATE, not daterange)
        v_valid_from := lower(v_valid_range);
        v_valid_until := upper(v_valid_range);

        PERFORM worker.enqueue_derive_statistical_unit(
            p_establishment_id_ranges := v_est_ids,
            p_legal_unit_id_ranges := v_lu_ids,
            p_enterprise_id_ranges := v_ent_ids,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until,
            p_round_priority_base := v_round_priority_base
        );
    END IF;
END;
$command_collect_changes$;

-- derive_statistical_unit (procedure): propagate round_priority_base from payload
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_establishment_id_ranges int4multirange = (payload->>'establishment_id_ranges')::int4multirange;
    v_legal_unit_id_ranges int4multirange = (payload->>'legal_unit_id_ranges')::int4multirange;
    v_enterprise_id_ranges int4multirange = (payload->>'enterprise_id_ranges')::int4multirange;
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
    v_round_priority_base bigint = (payload->>'round_priority_base')::bigint;
    v_task_id BIGINT;
BEGIN
    -- Get current task ID from the tasks table (the one being processed)
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY processed_at DESC NULLS LAST, id DESC
    LIMIT 1;

    -- Call the function with task_id for spawning children
    PERFORM worker.derive_statistical_unit(
        p_establishment_id_ranges := v_establishment_id_ranges,
        p_legal_unit_id_ranges := v_legal_unit_id_ranges,
        p_enterprise_id_ranges := v_enterprise_id_ranges,
        p_valid_from := v_valid_from,
        p_valid_until := v_valid_until,
        p_task_id := v_task_id,
        p_round_priority_base := v_round_priority_base
    );
END;
$procedure$;

-- derive_statistical_unit (function): accept + propagate round_priority_base
CREATE OR REPLACE FUNCTION worker.derive_statistical_unit(
    p_establishment_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_legal_unit_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_enterprise_id_ranges int4multirange DEFAULT NULL::int4multirange,
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date,
    p_task_id bigint DEFAULT NULL::bigint,
    p_round_priority_base bigint DEFAULT NULL
)
 RETURNS void
 LANGUAGE plpgsql
AS $derive_statistical_unit$
DECLARE
    v_batch RECORD;
    v_establishment_ids INT[];
    v_legal_unit_ids INT[];
    v_enterprise_ids INT[];
    v_batch_count INT := 0;
    v_is_full_refresh BOOLEAN;
    v_child_priority BIGINT;
    v_orphan_enterprise_ids INT[];
    v_orphan_legal_unit_ids INT[];
    v_orphan_establishment_ids INT[];
BEGIN
    v_is_full_refresh := (p_establishment_id_ranges IS NULL
                         AND p_legal_unit_id_ranges IS NULL
                         AND p_enterprise_id_ranges IS NULL);

    -- Priority for children: use round base if available, otherwise nextval
    v_child_priority := COALESCE(p_round_priority_base, nextval('public.worker_task_priority_seq'));

    IF v_is_full_refresh THEN
        -- Full refresh: spawn batch children (no orphan cleanup needed - covers everything)
        -- No dirty partition tracking needed: full refresh recomputes all partitions
        FOR v_batch IN
            SELECT * FROM public.get_closed_group_batches(p_target_batch_size := 1000)
        LOOP
            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;
    ELSE
        -- Partial refresh: convert multiranges to arrays
        v_establishment_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_establishment_id_ranges, '{}'::int4multirange)) AS t(r)
        );
        v_legal_unit_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_legal_unit_id_ranges, '{}'::int4multirange)) AS t(r)
        );
        v_enterprise_ids := ARRAY(
            SELECT generate_series(lower(r), upper(r)-1)
            FROM unnest(COALESCE(p_enterprise_id_ranges, '{}'::int4multirange)) AS t(r)
        );

        -- =====================================================================
        -- ORPHAN CLEANUP: Handle deleted entities BEFORE batching
        -- =====================================================================
        IF COALESCE(array_length(v_enterprise_ids, 1), 0) > 0 THEN
            v_orphan_enterprise_ids := ARRAY(
                SELECT id FROM unnest(v_enterprise_ids) AS id
                EXCEPT SELECT e.id FROM public.enterprise AS e WHERE e.id = ANY(v_enterprise_ids)
            );
            IF COALESCE(array_length(v_orphan_enterprise_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan enterprise IDs',
                    array_length(v_orphan_enterprise_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.timeline_enterprise WHERE enterprise_id = ANY(v_orphan_enterprise_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'enterprise' AND unit_id = ANY(v_orphan_enterprise_ids);
            END IF;
        END IF;

        IF COALESCE(array_length(v_legal_unit_ids, 1), 0) > 0 THEN
            v_orphan_legal_unit_ids := ARRAY(
                SELECT id FROM unnest(v_legal_unit_ids) AS id
                EXCEPT SELECT lu.id FROM public.legal_unit AS lu WHERE lu.id = ANY(v_legal_unit_ids)
            );
            IF COALESCE(array_length(v_orphan_legal_unit_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan legal_unit IDs',
                    array_length(v_orphan_legal_unit_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.timeline_legal_unit WHERE legal_unit_id = ANY(v_orphan_legal_unit_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'legal_unit' AND unit_id = ANY(v_orphan_legal_unit_ids);
            END IF;
        END IF;

        IF COALESCE(array_length(v_establishment_ids, 1), 0) > 0 THEN
            v_orphan_establishment_ids := ARRAY(
                SELECT id FROM unnest(v_establishment_ids) AS id
                EXCEPT SELECT es.id FROM public.establishment AS es WHERE es.id = ANY(v_establishment_ids)
            );
            IF COALESCE(array_length(v_orphan_establishment_ids, 1), 0) > 0 THEN
                RAISE DEBUG 'derive_statistical_unit: Cleaning up % orphan establishment IDs',
                    array_length(v_orphan_establishment_ids, 1);
                DELETE FROM public.timepoints WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timesegments WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.timeline_establishment WHERE establishment_id = ANY(v_orphan_establishment_ids);
                DELETE FROM public.statistical_unit WHERE unit_type = 'establishment' AND unit_id = ANY(v_orphan_establishment_ids);
            END IF;
        END IF;

        -- =====================================================================
        -- BATCHING: Only existing entities, partitioned with no overlap
        -- Compute batches FIRST, then mark dirty partitions for ALL units
        -- in ALL batches (covers closed-group expansion).
        -- =====================================================================

        -- Collect all batches into a temp table for two-pass processing
        IF to_regclass('pg_temp._batches') IS NOT NULL THEN
            DROP TABLE _batches;
        END IF;
        CREATE TEMP TABLE _batches ON COMMIT DROP AS
        SELECT * FROM public.get_closed_group_batches(
            p_target_batch_size := 1000,
            p_establishment_ids := NULLIF(v_establishment_ids, '{}'),
            p_legal_unit_ids := NULLIF(v_legal_unit_ids, '{}'),
            p_enterprise_ids := NULLIF(v_enterprise_ids, '{}')
        );

        -- =====================================================================
        -- DIRTY PARTITION TRACKING: Mark partitions for ALL units in ALL batches
        -- Explicit count from settings (no function DEFAULT).
        -- =====================================================================
        INSERT INTO public.statistical_unit_facet_dirty_partitions (partition_seq)
        SELECT DISTINCT public.report_partition_seq(
            t.unit_type, t.unit_id,
            (SELECT analytics_partition_count FROM public.settings)
        )
        FROM (
            SELECT 'enterprise'::text AS unit_type, unnest(b.enterprise_ids) AS unit_id
            FROM _batches AS b
            UNION ALL
            SELECT 'legal_unit', unnest(b.legal_unit_ids)
            FROM _batches AS b
            UNION ALL
            SELECT 'establishment', unnest(b.establishment_ids)
            FROM _batches AS b
        ) AS t
        WHERE t.unit_id IS NOT NULL
        ON CONFLICT DO NOTHING;

        RAISE DEBUG 'derive_statistical_unit: Tracked dirty facet partitions for closed group across % batches',
            (SELECT count(*) FROM _batches);

        -- Spawn batch children
        FOR v_batch IN SELECT * FROM _batches
        LOOP
            PERFORM worker.spawn(
                p_command := 'statistical_unit_refresh_batch',
                p_payload := jsonb_build_object(
                    'command', 'statistical_unit_refresh_batch',
                    'batch_seq', v_batch.batch_seq,
                    'enterprise_ids', v_batch.enterprise_ids,
                    'legal_unit_ids', v_batch.legal_unit_ids,
                    'establishment_ids', v_batch.establishment_ids,
                    'valid_from', p_valid_from,
                    'valid_until', p_valid_until
                ),
                p_parent_id := p_task_id,
                p_priority := v_child_priority
            );
            v_batch_count := v_batch_count + 1;
        END LOOP;
    END IF;

    RAISE DEBUG 'derive_statistical_unit: Spawned % batch children with parent_id %', v_batch_count, p_task_id;

    -- Refresh derived data (used flags) - always full refreshes, run synchronously
    PERFORM public.activity_category_used_derive();
    PERFORM public.region_used_derive();
    PERFORM public.sector_used_derive();
    PERFORM public.data_source_used_derive();
    PERFORM public.legal_form_used_derive();
    PERFORM public.country_used_derive();

    -- =========================================================================
    -- STAGING PATTERN: Enqueue flush task (runs after all batches complete)
    -- =========================================================================
    PERFORM worker.enqueue_statistical_unit_flush_staging(
        p_round_priority_base := p_round_priority_base
    );
    RAISE DEBUG 'derive_statistical_unit: Enqueued flush_staging task';

    -- Enqueue derive_reports as an "uncle" task (runs after flush completes)
    PERFORM worker.enqueue_derive_reports(
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until,
        p_round_priority_base := p_round_priority_base
    );

    RAISE DEBUG 'derive_statistical_unit: Enqueued derive_reports';
END;
$derive_statistical_unit$;

-- derive_reports (procedure): propagate round_priority_base from payload
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
  -- Call the reports refresh function with the extracted parameters
  PERFORM worker.derive_reports(
    p_valid_from := v_valid_from,
    p_valid_until := v_valid_until,
    p_round_priority_base := v_round_priority_base
  );
END;
$procedure$;

-- derive_reports (function): accept + propagate round_priority_base
CREATE OR REPLACE FUNCTION worker.derive_reports(
    p_valid_from date DEFAULT NULL::date,
    p_valid_until date DEFAULT NULL::date,
    p_round_priority_base bigint DEFAULT NULL
)
 RETURNS void
 LANGUAGE plpgsql
AS $derive_reports$
BEGIN
  -- Auto-scale partition count based on data volume
  CALL admin.adjust_analytics_partition_count();

  -- Instead of running all phases in one transaction, enqueue the first phase.
  -- Each phase will enqueue the next one when it completes.
  PERFORM worker.enqueue_derive_statistical_history(
    p_valid_from => p_valid_from,
    p_valid_until => p_valid_until,
    p_round_priority_base := p_round_priority_base
  );
END;
$derive_reports$;

-- derive_statistical_history: propagate round_priority_base
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_round_priority_base bigint := (payload->>'round_priority_base')::bigint;
    v_task_id bigint;
    v_period record;
    v_dirty_partitions INT[];
    v_partition INT;
    v_child_count integer := 0;
BEGIN
    -- Get own task_id for spawning children
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_history: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    -- Read dirty partitions (snapshot)
    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    -- If no partition entries exist yet (first run), force full refresh
    IF NOT EXISTS (SELECT 1 FROM public.statistical_history WHERE partition_seq IS NOT NULL LIMIT 1) THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_history: No partition entries exist, forcing full refresh';
    END IF;

    -- Enqueue reduce uncle task (runs after children complete)
    PERFORM worker.enqueue_statistical_history_reduce(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_round_priority_base := v_round_priority_base
    );

    -- Spawn one child per period x partition combination
    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution := null::public.history_resolution,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until
        )
    LOOP
        IF v_dirty_partitions IS NULL THEN
            -- Full refresh: all populated partitions
            FOR v_partition IN
                SELECT DISTINCT report_partition_seq
                FROM public.statistical_unit
                ORDER BY report_partition_seq
            LOOP
                PERFORM worker.spawn(
                    p_command := 'derive_statistical_history_period',
                    p_payload := jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq', v_partition
                    ),
                    p_parent_id := v_task_id,
                    p_priority := v_round_priority_base
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            -- Partial refresh: only dirty partitions
            FOREACH v_partition IN ARRAY v_dirty_partitions LOOP
                PERFORM worker.spawn(
                    p_command := 'derive_statistical_history_period',
                    p_payload := jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq', v_partition
                    ),
                    p_parent_id := v_task_id,
                    p_priority := v_round_priority_base
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        END IF;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history: spawned % period x partition children (dirty_partitions=%)',
        v_child_count, v_dirty_partitions;
END;
$derive_statistical_history$;

-- statistical_history_reduce: propagate round_priority_base
CREATE OR REPLACE PROCEDURE worker.statistical_history_reduce(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_history_reduce$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_round_priority_base bigint := (payload->>'round_priority_base')::bigint;
BEGIN
    RAISE DEBUG 'statistical_history_reduce: valid_from=%, valid_until=%', v_valid_from, v_valid_until;

    -- Delete existing root entries
    DELETE FROM public.statistical_history WHERE partition_seq IS NULL;

    -- Recalculate root entries by summing across all partition entries
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

    -- Enqueue next phase: derive_statistical_unit_facet
    PERFORM worker.enqueue_derive_statistical_unit_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_round_priority_base := v_round_priority_base
    );

    RAISE DEBUG 'statistical_history_reduce: done, enqueued derive_statistical_unit_facet';
END;
$statistical_history_reduce$;

-- derive_statistical_unit_facet: propagate round_priority_base
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_unit_facet$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_round_priority_base bigint := (payload->>'round_priority_base')::bigint;
    v_task_id bigint;
    v_dirty_partitions INT[];
    v_populated_partitions INT;
    v_expected_partitions INT;
    v_child_count INT := 0;
    v_i INT;
BEGIN
    -- Get own task_id for spawning children
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_unit_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    -- =====================================================================
    -- INTEGRITY CHECK: Ensure partition table is fully populated.
    -- UNLOGGED table loses data on crash; also handles first-run case.
    -- If partition table is incomplete, force a full refresh.
    -- =====================================================================
    SELECT COUNT(DISTINCT partition_seq) INTO v_populated_partitions
    FROM public.statistical_unit_facet_staging;

    SELECT COUNT(DISTINCT report_partition_seq) INTO v_expected_partitions
    FROM public.statistical_unit
    WHERE used_for_counting;

    -- Snapshot dirty partitions (atomically read current state)
    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    IF v_populated_partitions < v_expected_partitions THEN
        -- Partition table lost data (crash or first run) -> force full refresh
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_unit_facet: Staging has %/% expected partitions populated, forcing full refresh',
            v_populated_partitions, v_expected_partitions;
    END IF;

    -- Enqueue reduce task with the snapshot of dirty partitions in payload.
    -- This way reduce knows exactly which partitions to clear from dirty tracking.
    PERFORM worker.enqueue_statistical_unit_facet_reduce(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_dirty_partitions => v_dirty_partitions,
        p_round_priority_base := v_round_priority_base
    );

    -- Spawn partition children
    IF v_dirty_partitions IS NULL THEN
        -- Full refresh: only partitions that have data
        RAISE DEBUG 'derive_statistical_unit_facet: Full refresh -- spawning % partition children (populated)',
            v_expected_partitions;
        FOR v_i IN
            SELECT DISTINCT report_partition_seq
            FROM public.statistical_unit
            WHERE used_for_counting
            ORDER BY report_partition_seq
        LOOP
            PERFORM worker.spawn(
                p_command := 'derive_statistical_unit_facet_partition',
                p_payload := jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq', v_i
                ),
                p_parent_id := v_task_id,
                p_priority := v_round_priority_base
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    ELSE
        -- Partial refresh: only dirty partitions
        RAISE DEBUG 'derive_statistical_unit_facet: Partial refresh -- spawning % dirty partition children',
            array_length(v_dirty_partitions, 1);
        FOREACH v_i IN ARRAY v_dirty_partitions LOOP
            PERFORM worker.spawn(
                p_command := 'derive_statistical_unit_facet_partition',
                p_payload := jsonb_build_object(
                    'command', 'derive_statistical_unit_facet_partition',
                    'partition_seq', v_i
                ),
                p_parent_id := v_task_id,
                p_priority := v_round_priority_base
            );
            v_child_count := v_child_count + 1;
        END LOOP;
    END IF;

    RAISE DEBUG 'derive_statistical_unit_facet: Spawned % partition children', v_child_count;
END;
$derive_statistical_unit_facet$;

-- statistical_unit_facet_reduce: propagate round_priority_base
CREATE OR REPLACE PROCEDURE worker.statistical_unit_facet_reduce(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_unit_facet_reduce$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
    v_round_priority_base bigint := (payload->>'round_priority_base')::bigint;
    v_dirty_partitions INT[];
BEGIN
    RAISE DEBUG 'statistical_unit_facet_reduce: valid_from=%, valid_until=%', v_valid_from, v_valid_until;

    -- Extract dirty partitions from payload (NULL = full refresh)
    IF payload->'dirty_partitions' IS NOT NULL AND payload->'dirty_partitions' != 'null'::jsonb THEN
        SELECT array_agg(val::int)
        INTO v_dirty_partitions
        FROM jsonb_array_elements_text(payload->'dirty_partitions') AS val;
    END IF;

    -- TRUNCATE is instant (no dead tuples, no per-row WAL), unlike DELETE which
    -- accumulates dead tuples per cycle causing progressive slowdown.
    TRUNCATE public.statistical_unit_facet;

    -- Aggregate from UNLOGGED staging table into main table
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

    -- Clear only the dirty partitions that were processed
    IF v_dirty_partitions IS NOT NULL THEN
        DELETE FROM public.statistical_unit_facet_dirty_partitions
        WHERE partition_seq = ANY(v_dirty_partitions);
        RAISE DEBUG 'statistical_unit_facet_reduce: cleared % dirty partitions', array_length(v_dirty_partitions, 1);
    ELSE
        TRUNCATE public.statistical_unit_facet_dirty_partitions;
        RAISE DEBUG 'statistical_unit_facet_reduce: full refresh -- truncated dirty partitions';
    END IF;

    -- Enqueue next phase: derive_statistical_history_facet
    PERFORM worker.enqueue_derive_statistical_history_facet(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_round_priority_base := v_round_priority_base
    );

    RAISE DEBUG 'statistical_unit_facet_reduce: done, enqueued derive_statistical_history_facet';
END;
$statistical_unit_facet_reduce$;

-- derive_statistical_history_facet: propagate round_priority_base
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $derive_statistical_history_facet$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_round_priority_base bigint := (payload->>'round_priority_base')::bigint;
    v_task_id bigint;
    v_period record;
    v_dirty_partitions INT[];
    v_partition INT;
    v_child_count integer := 0;
BEGIN
    SELECT id INTO v_task_id
    FROM worker.tasks
    WHERE state = 'processing' AND worker_pid = pg_backend_pid()
    ORDER BY id DESC LIMIT 1;

    RAISE DEBUG 'derive_statistical_history_facet: task_id=%, valid_from=%, valid_until=%',
                 v_task_id, v_valid_from, v_valid_until;

    -- Read dirty partitions
    SELECT array_agg(partition_seq ORDER BY partition_seq) INTO v_dirty_partitions
    FROM public.statistical_unit_facet_dirty_partitions;

    -- If no partition entries exist yet (UNLOGGED data lost or first run), force full refresh
    IF NOT EXISTS (SELECT 1 FROM public.statistical_history_facet_partitions LIMIT 1) THEN
        v_dirty_partitions := NULL;
        RAISE DEBUG 'derive_statistical_history_facet: No partition entries exist, forcing full refresh';
    END IF;

    -- Enqueue reduce uncle task
    PERFORM worker.enqueue_statistical_history_facet_reduce(
        p_valid_from => v_valid_from,
        p_valid_until => v_valid_until,
        p_round_priority_base := v_round_priority_base
    );

    -- Spawn period x partition children
    FOR v_period IN
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution := null::public.history_resolution,
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until
        )
    LOOP
        IF v_dirty_partitions IS NULL THEN
            -- Include all partitions (not just used_for_counting) because
            -- statistical_history_facet tracks exists_count for all units
            FOR v_partition IN
                SELECT DISTINCT report_partition_seq
                FROM public.statistical_unit
                ORDER BY report_partition_seq
            LOOP
                PERFORM worker.spawn(
                    p_command := 'derive_statistical_history_facet_period',
                    p_payload := jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq', v_partition
                    ),
                    p_parent_id := v_task_id,
                    p_priority := v_round_priority_base
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        ELSE
            FOREACH v_partition IN ARRAY v_dirty_partitions LOOP
                PERFORM worker.spawn(
                    p_command := 'derive_statistical_history_facet_period',
                    p_payload := jsonb_build_object(
                        'resolution', v_period.resolution::text,
                        'year', v_period.year,
                        'month', v_period.month,
                        'partition_seq', v_partition
                    ),
                    p_parent_id := v_task_id,
                    p_priority := v_round_priority_base
                );
                v_child_count := v_child_count + 1;
            END LOOP;
        END IF;
    END LOOP;

    RAISE DEBUG 'derive_statistical_history_facet: spawned % period x partition children', v_child_count;
END;
$derive_statistical_history_facet$;

-- statistical_history_facet_reduce: terminal stage, no downstream enqueue needed
-- but still read round_priority_base for consistency (no propagation needed)
CREATE OR REPLACE PROCEDURE worker.statistical_history_facet_reduce(IN payload jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $statistical_history_facet_reduce$
DECLARE
    v_valid_from date := (payload->>'valid_from')::date;
    v_valid_until date := (payload->>'valid_until')::date;
BEGIN
    RAISE DEBUG 'statistical_history_facet_reduce: valid_from=%, valid_until=%', v_valid_from, v_valid_until;

    -- Drop indexes before bulk insert (18 indexes on 287K+ rows costs 15s to maintain
    -- row-by-row; dropping and recreating after is ~11s total including index build).
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_year;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_month;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_unit_type;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_primary_activity_category_path;
    DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_primary_activity_category_pa;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_secondary_activity_category_path;
    DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_secondary_activity_category_;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_sector_path;
    DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_sector_path;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_legal_form_id;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_physical_region_path;
    DROP INDEX IF EXISTS public.idx_gist_statistical_history_facet_physical_region_path;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_physical_country_id;
    DROP INDEX IF EXISTS public.idx_statistical_history_facet_stats_summary;
    DROP INDEX IF EXISTS public.statistical_history_facet_month_key;
    DROP INDEX IF EXISTS public.statistical_history_facet_year_key;

    -- TRUNCATE is instant (no dead tuples, no per-row WAL), unlike DELETE which
    -- accumulates ~800K dead tuples per cycle causing progressive slowdown.
    TRUNCATE public.statistical_history_facet;

    -- Aggregate from UNLOGGED partition table into main LOGGED table
    INSERT INTO public.statistical_history_facet (
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        exists_count, exists_change, exists_added_count, exists_removed_count,
        countable_count, countable_change, countable_added_count, countable_removed_count,
        births, deaths,
        name_change_count, primary_activity_category_change_count,
        secondary_activity_category_change_count, sector_change_count,
        legal_form_change_count, physical_region_change_count,
        physical_country_change_count, physical_address_change_count,
        unit_size_change_count, status_change_count,
        stats_summary
    )
    SELECT
        resolution, year, month, unit_type,
        primary_activity_category_path, secondary_activity_category_path,
        sector_path, legal_form_id, physical_region_path,
        physical_country_id, unit_size_id, status_id,
        SUM(exists_count)::integer, SUM(exists_change)::integer,
        SUM(exists_added_count)::integer, SUM(exists_removed_count)::integer,
        SUM(countable_count)::integer, SUM(countable_change)::integer,
        SUM(countable_added_count)::integer, SUM(countable_removed_count)::integer,
        SUM(births)::integer, SUM(deaths)::integer,
        SUM(name_change_count)::integer, SUM(primary_activity_category_change_count)::integer,
        SUM(secondary_activity_category_change_count)::integer, SUM(sector_change_count)::integer,
        SUM(legal_form_change_count)::integer, SUM(physical_region_change_count)::integer,
        SUM(physical_country_change_count)::integer, SUM(physical_address_change_count)::integer,
        SUM(unit_size_change_count)::integer, SUM(status_change_count)::integer,
        jsonb_stats_merge_agg(stats_summary)
    FROM public.statistical_history_facet_partitions
    GROUP BY resolution, year, month, unit_type,
             primary_activity_category_path, secondary_activity_category_path,
             sector_path, legal_form_id, physical_region_path,
             physical_country_id, unit_size_id, status_id;

    -- Recreate indexes after bulk insert
    CREATE UNIQUE INDEX statistical_history_facet_month_key
        ON public.statistical_history_facet (resolution, year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path, physical_country_id)
        WHERE resolution = 'year-month'::public.history_resolution;
    CREATE UNIQUE INDEX statistical_history_facet_year_key
        ON public.statistical_history_facet (year, month, unit_type,
            primary_activity_category_path, secondary_activity_category_path,
            sector_path, legal_form_id, physical_region_path, physical_country_id)
        WHERE resolution = 'year'::public.history_resolution;
    CREATE INDEX idx_statistical_history_facet_year ON public.statistical_history_facet (year);
    CREATE INDEX idx_statistical_history_facet_month ON public.statistical_history_facet (month);
    CREATE INDEX idx_statistical_history_facet_unit_type ON public.statistical_history_facet (unit_type);
    CREATE INDEX idx_statistical_history_facet_primary_activity_category_path ON public.statistical_history_facet (primary_activity_category_path);
    CREATE INDEX idx_gist_statistical_history_facet_primary_activity_category_pa ON public.statistical_history_facet USING GIST (primary_activity_category_path);
    CREATE INDEX idx_statistical_history_facet_secondary_activity_category_path ON public.statistical_history_facet (secondary_activity_category_path);
    CREATE INDEX idx_gist_statistical_history_facet_secondary_activity_category_ ON public.statistical_history_facet USING GIST (secondary_activity_category_path);
    CREATE INDEX idx_statistical_history_facet_sector_path ON public.statistical_history_facet (sector_path);
    CREATE INDEX idx_gist_statistical_history_facet_sector_path ON public.statistical_history_facet USING GIST (sector_path);
    CREATE INDEX idx_statistical_history_facet_legal_form_id ON public.statistical_history_facet (legal_form_id);
    CREATE INDEX idx_statistical_history_facet_physical_region_path ON public.statistical_history_facet (physical_region_path);
    CREATE INDEX idx_gist_statistical_history_facet_physical_region_path ON public.statistical_history_facet USING GIST (physical_region_path);
    CREATE INDEX idx_statistical_history_facet_physical_country_id ON public.statistical_history_facet (physical_country_id);
    CREATE INDEX idx_statistical_history_facet_stats_summary ON public.statistical_history_facet USING GIN (stats_summary jsonb_path_ops);

    RAISE DEBUG 'statistical_history_facet_reduce: done';
END;
$statistical_history_facet_reduce$;

END;
