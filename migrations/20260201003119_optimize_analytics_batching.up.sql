-- Migration 20260201003119: optimize_analytics_batching
BEGIN;

-- ============================================================================
-- Optimize Analytics Batching
-- ============================================================================
-- This migration optimizes the analytics derivation by:
-- 1. Splitting derive_reports into 3 separate tasks with separate transactions
-- 2. Using bulk INSERT instead of FOR LOOP for better performance
-- 3. Adding proper task sequencing so each phase commits before the next starts
-- ============================================================================

-- ============================================================================
-- Part 1: Create new task enqueue functions for each phase
-- ============================================================================

-- Unique index for derive_statistical_history deduplication
CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_derive_statistical_history_dedup
ON worker.tasks (command)
WHERE command = 'derive_statistical_history' AND state = 'pending'::worker.task_state;

-- Unique index for derive_statistical_unit_facet deduplication
CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_derive_statistical_unit_facet_dedup
ON worker.tasks (command)
WHERE command = 'derive_statistical_unit_facet' AND state = 'pending'::worker.task_state;

-- Unique index for derive_statistical_history_facet deduplication
CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_derive_statistical_history_facet_dedup
ON worker.tasks (command)
WHERE command = 'derive_statistical_history_facet' AND state = 'pending'::worker.task_state;


-- Enqueue function for derive_statistical_history
CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_history(
  p_valid_from date DEFAULT NULL,
  p_valid_until date DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $enqueue_derive_statistical_history$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  v_payload := jsonb_build_object(
    'command', 'derive_statistical_history',
    'valid_from', v_valid_from,
    'valid_until', v_valid_until
  );

  INSERT INTO worker.tasks AS t (command, payload)
  VALUES ('derive_statistical_history', v_payload)
  ON CONFLICT (command)
  WHERE command = 'derive_statistical_history' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_statistical_history',
      'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
      'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date)
    ),
    state = 'pending'::worker.task_state
  RETURNING id INTO v_task_id;
  
  RETURN v_task_id;
END;
$enqueue_derive_statistical_history$;


-- Enqueue function for derive_statistical_unit_facet
CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_unit_facet(
  p_valid_from date DEFAULT NULL,
  p_valid_until date DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $enqueue_derive_statistical_unit_facet$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  v_payload := jsonb_build_object(
    'command', 'derive_statistical_unit_facet',
    'valid_from', v_valid_from,
    'valid_until', v_valid_until
  );

  INSERT INTO worker.tasks AS t (command, payload)
  VALUES ('derive_statistical_unit_facet', v_payload)
  ON CONFLICT (command)
  WHERE command = 'derive_statistical_unit_facet' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_statistical_unit_facet',
      'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
      'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date)
    ),
    state = 'pending'::worker.task_state
  RETURNING id INTO v_task_id;
  
  RETURN v_task_id;
END;
$enqueue_derive_statistical_unit_facet$;


-- Enqueue function for derive_statistical_history_facet
CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_history_facet(
  p_valid_from date DEFAULT NULL,
  p_valid_until date DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $enqueue_derive_statistical_history_facet$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
  v_valid_from DATE := COALESCE(p_valid_from, '-infinity'::DATE);
  v_valid_until DATE := COALESCE(p_valid_until, 'infinity'::DATE);
BEGIN
  v_payload := jsonb_build_object(
    'command', 'derive_statistical_history_facet',
    'valid_from', v_valid_from,
    'valid_until', v_valid_until
  );

  INSERT INTO worker.tasks AS t (command, payload)
  VALUES ('derive_statistical_history_facet', v_payload)
  ON CONFLICT (command)
  WHERE command = 'derive_statistical_history_facet' AND state = 'pending'::worker.task_state
  DO UPDATE SET
    payload = jsonb_build_object(
      'command', 'derive_statistical_history_facet',
      'valid_from', LEAST((t.payload->>'valid_from')::date, (EXCLUDED.payload->>'valid_from')::date),
      'valid_until', GREATEST((t.payload->>'valid_until')::date, (EXCLUDED.payload->>'valid_until')::date)
    ),
    state = 'pending'::worker.task_state
  RETURNING id INTO v_task_id;
  
  RETURN v_task_id;
END;
$enqueue_derive_statistical_history_facet$;


-- ============================================================================
-- Part 2: Create command handlers for each phase
-- ============================================================================

-- Command handler for derive_statistical_history
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history(payload JSONB)
SECURITY DEFINER
LANGUAGE plpgsql
AS $derive_statistical_history$
DECLARE
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
BEGIN
  PERFORM public.statistical_history_derive(
    p_valid_from := v_valid_from,
    p_valid_until := v_valid_until
  );
  
  -- Enqueue the next phase
  PERFORM worker.enqueue_derive_statistical_unit_facet(
    p_valid_from => v_valid_from,
    p_valid_until => v_valid_until
  );
END;
$derive_statistical_history$;


-- Command handler for derive_statistical_unit_facet
CREATE OR REPLACE PROCEDURE worker.derive_statistical_unit_facet(payload JSONB)
SECURITY DEFINER
LANGUAGE plpgsql
AS $derive_statistical_unit_facet$
DECLARE
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
BEGIN
  PERFORM public.statistical_unit_facet_derive(
    p_valid_from := v_valid_from,
    p_valid_until := v_valid_until
  );
  
  -- Enqueue the next phase
  PERFORM worker.enqueue_derive_statistical_history_facet(
    p_valid_from => v_valid_from,
    p_valid_until => v_valid_until
  );
END;
$derive_statistical_unit_facet$;


-- Command handler for derive_statistical_history_facet
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(payload JSONB)
SECURITY DEFINER
LANGUAGE plpgsql
AS $derive_statistical_history_facet$
DECLARE
    v_valid_from date = (payload->>'valid_from')::date;
    v_valid_until date = (payload->>'valid_until')::date;
BEGIN
  PERFORM public.statistical_history_facet_derive(
    p_valid_from := v_valid_from,
    p_valid_until := v_valid_until
  );
  -- This is the last phase, no more tasks to enqueue
END;
$derive_statistical_history_facet$;


-- ============================================================================
-- Part 3: Update derive_reports to enqueue the first phase instead of running all
-- ============================================================================

-- Update derive_reports to just enqueue the first phase task
-- This allows each phase to run in its own transaction
CREATE OR REPLACE FUNCTION worker.derive_reports(
  p_valid_from date DEFAULT NULL,
  p_valid_until date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $derive_reports$
BEGIN
  -- Instead of running all phases in one transaction, enqueue the first phase.
  -- Each phase will enqueue the next one when it completes.
  PERFORM worker.enqueue_derive_statistical_history(
    p_valid_from => p_valid_from,
    p_valid_until => p_valid_until
  );
END;
$derive_reports$;


-- ============================================================================
-- Part 4: Optimize statistical_history_derive with bulk INSERT
-- ============================================================================

-- Replace the FOR LOOP with a single bulk INSERT using LATERAL join
CREATE OR REPLACE FUNCTION public.statistical_history_derive(
  p_valid_from date DEFAULT '-infinity'::date,
  p_valid_until date DEFAULT 'infinity'::date
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_history_derive$
BEGIN
    RAISE DEBUG 'Running statistical_history_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history sh
    USING public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    WHERE sh.year = tp.year
    AND sh.month IS NOT DISTINCT FROM tp.month;

    -- Bulk INSERT using LATERAL join - much faster than FOR LOOP
    INSERT INTO public.statistical_history
    SELECT h.*
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    CROSS JOIN LATERAL public.statistical_history_def(tp.resolution, tp.year, tp.month) h;
END;
$statistical_history_derive$;


-- ============================================================================
-- Part 5: Optimize statistical_history_facet_derive with bulk INSERT
-- ============================================================================

-- Replace the FOR LOOP with a single bulk INSERT using LATERAL join
CREATE OR REPLACE FUNCTION public.statistical_history_facet_derive(
  p_valid_from date DEFAULT '-infinity'::date,
  p_valid_until date DEFAULT 'infinity'::date
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_history_facet_derive$
BEGIN
    RAISE DEBUG 'Running statistical_history_facet_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history_facet shf
    USING public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    WHERE shf.year = tp.year
      AND shf.month IS NOT DISTINCT FROM tp.month
      AND shf.resolution = tp.resolution;

    -- Bulk INSERT using LATERAL join - much faster than FOR LOOP
    INSERT INTO public.statistical_history_facet
    SELECT f.*
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    ) tp
    CROSS JOIN LATERAL public.statistical_history_facet_def(tp.resolution, tp.year, tp.month) f;
END;
$statistical_history_facet_derive$;


-- ============================================================================
-- Part 6: Register new commands in worker.command_registry
-- ============================================================================

-- Add command handlers for the new analytics tasks
INSERT INTO worker.command_registry (queue, command, handler_procedure, before_procedure, after_procedure, description)
VALUES 
  ('analytics', 'derive_statistical_history', 'worker.derive_statistical_history', NULL, NULL, 'Derive statistical history aggregations'),
  ('analytics', 'derive_statistical_unit_facet', 'worker.derive_statistical_unit_facet', NULL, NULL, 'Derive statistical unit facets'),
  ('analytics', 'derive_statistical_history_facet', 'worker.derive_statistical_history_facet', NULL, NULL, 'Derive statistical history facets')
ON CONFLICT (command) DO UPDATE SET
  handler_procedure = EXCLUDED.handler_procedure,
  before_procedure = EXCLUDED.before_procedure,
  after_procedure = EXCLUDED.after_procedure;

END;
