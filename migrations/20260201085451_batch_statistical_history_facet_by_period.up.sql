-- Migration: Batch statistical_history_facet derivation by period
-- 
-- Instead of processing all periods in one giant transaction, this splits
-- the work into individual period tasks. Benefits:
-- 1. Progress visibility - see each period complete in worker.tasks
-- 2. Partial completion - if period 5 fails, periods 1-4 are preserved
-- 3. Foundation for parallelization - periods are independent
-- 4. Smaller transactions - reduced lock contention

BEGIN;

-- ============================================================================
-- Part 1: Deduplication index for single-period tasks
-- ============================================================================
-- Uses composite of (resolution, year, month) as unique key for pending tasks
CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_derive_history_facet_period_dedup
ON worker.tasks (command, (payload->>'resolution'), (payload->>'year'), (payload->>'month'))
WHERE command = 'derive_statistical_history_facet_period' AND state = 'pending'::worker.task_state;


-- ============================================================================
-- Part 2: Enqueue function for a single period
-- ============================================================================
CREATE OR REPLACE FUNCTION worker.enqueue_derive_statistical_history_facet_period(
  p_resolution public.history_resolution,
  p_year integer,
  p_month integer DEFAULT NULL
) RETURNS BIGINT
LANGUAGE plpgsql
AS $enqueue_derive_statistical_history_facet_period$
DECLARE
  v_task_id BIGINT;
  v_payload JSONB;
BEGIN
  v_payload := jsonb_build_object(
    'command', 'derive_statistical_history_facet_period',
    'resolution', p_resolution::text,
    'year', p_year,
    'month', p_month  -- NULL for year resolution
  );

  INSERT INTO worker.tasks AS t (command, payload)
  VALUES ('derive_statistical_history_facet_period', v_payload)
  ON CONFLICT (command, (payload->>'resolution'), (payload->>'year'), (payload->>'month'))
  WHERE command = 'derive_statistical_history_facet_period' AND state = 'pending'::worker.task_state
  DO NOTHING
  RETURNING id INTO v_task_id;
  
  RETURN v_task_id;
END;
$enqueue_derive_statistical_history_facet_period$;


-- ============================================================================
-- Part 3: Handler for a single period - does the actual work
-- ============================================================================
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet_period(payload JSONB)
SECURITY DEFINER
LANGUAGE plpgsql
AS $derive_statistical_history_facet_period$
DECLARE
    v_resolution public.history_resolution := (payload->>'resolution')::public.history_resolution;
    v_year integer := (payload->>'year')::integer;
    v_month integer := (payload->>'month')::integer;  -- NULL for year resolution
BEGIN
    RAISE DEBUG 'Processing statistical_history_facet for resolution=%, year=%, month=%', 
                 v_resolution, v_year, v_month;

    -- Delete existing data for this specific period
    DELETE FROM public.statistical_history_facet 
    WHERE resolution = v_resolution 
      AND year = v_year 
      AND month IS NOT DISTINCT FROM v_month;
    
    -- Insert new data for this specific period
    INSERT INTO public.statistical_history_facet
    SELECT * FROM public.statistical_history_facet_def(v_resolution, v_year, v_month);
    
    RAISE DEBUG 'Completed statistical_history_facet for resolution=%, year=%, month=%', 
                 v_resolution, v_year, v_month;
END;
$derive_statistical_history_facet_period$;


-- ============================================================================
-- Part 4: Modified parent handler - enqueues individual periods
-- ============================================================================
CREATE OR REPLACE PROCEDURE worker.derive_statistical_history_facet(payload JSONB)
SECURITY DEFINER
LANGUAGE plpgsql
AS $derive_statistical_history_facet$
DECLARE
    v_valid_from date := COALESCE((payload->>'valid_from')::date, '-infinity'::date);
    v_valid_until date := COALESCE((payload->>'valid_until')::date, 'infinity'::date);
    v_period RECORD;
    v_enqueued_count integer := 0;
BEGIN
    RAISE DEBUG 'Enqueueing statistical_history_facet periods for valid_from=%, valid_until=%', 
                 v_valid_from, v_valid_until;

    -- Enqueue a task for each period
    FOR v_period IN 
        SELECT resolution, year, month
        FROM public.get_statistical_history_periods(
            p_resolution := null::public.history_resolution,  -- Get all resolutions
            p_valid_from := v_valid_from,
            p_valid_until := v_valid_until
        )
    LOOP
        PERFORM worker.enqueue_derive_statistical_history_facet_period(
            v_period.resolution,
            v_period.year,
            v_period.month
        );
        v_enqueued_count := v_enqueued_count + 1;
    END LOOP;
    
    RAISE DEBUG 'Enqueued % period tasks for statistical_history_facet', v_enqueued_count;
    -- Note: This procedure completes quickly, the actual work happens in the period tasks
END;
$derive_statistical_history_facet$;


-- ============================================================================
-- Part 5: Register the new command
-- ============================================================================
INSERT INTO worker.command_registry (queue, command, handler_procedure, description)
VALUES ('analytics', 'derive_statistical_history_facet_period', 
        'worker.derive_statistical_history_facet_period',
        'Derive statistical history facets for a single period (resolution/year/month)')
ON CONFLICT (command) DO UPDATE SET
  handler_procedure = EXCLUDED.handler_procedure,
  description = EXCLUDED.description;

END;
