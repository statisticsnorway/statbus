-- Down Migration 20260201003119: optimize_analytics_batching
-- Reverts the analytics optimization back to the original FOR LOOP implementation
BEGIN;

-- ============================================================================
-- Part 1: Remove command handlers from worker.command_registry
-- ============================================================================
DELETE FROM worker.command_registry 
WHERE command IN ('derive_statistical_history', 'derive_statistical_unit_facet', 'derive_statistical_history_facet');


-- ============================================================================
-- Part 2: Drop the new procedures
-- ============================================================================
DROP PROCEDURE IF EXISTS worker.derive_statistical_history(JSONB);
DROP PROCEDURE IF EXISTS worker.derive_statistical_unit_facet(JSONB);
DROP PROCEDURE IF EXISTS worker.derive_statistical_history_facet(JSONB);


-- ============================================================================
-- Part 3: Drop the new enqueue functions
-- ============================================================================
DROP FUNCTION IF EXISTS worker.enqueue_derive_statistical_history(date, date);
DROP FUNCTION IF EXISTS worker.enqueue_derive_statistical_unit_facet(date, date);
DROP FUNCTION IF EXISTS worker.enqueue_derive_statistical_history_facet(date, date);


-- ============================================================================
-- Part 4: Drop the deduplication indexes
-- ============================================================================
DROP INDEX IF EXISTS worker.idx_tasks_derive_statistical_history_dedup;
DROP INDEX IF EXISTS worker.idx_tasks_derive_statistical_unit_facet_dedup;
DROP INDEX IF EXISTS worker.idx_tasks_derive_statistical_history_facet_dedup;


-- ============================================================================
-- Part 5: Restore original derive_reports function
-- ============================================================================
CREATE OR REPLACE FUNCTION worker.derive_reports(
  p_valid_from date DEFAULT NULL,
  p_valid_until date DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $derive_reports$
BEGIN
  -- Refresh derived data (facets and history)
  PERFORM public.statistical_history_derive(p_valid_from => p_valid_from, p_valid_until => p_valid_until);
  PERFORM public.statistical_unit_facet_derive(p_valid_from => p_valid_from, p_valid_until => p_valid_until);
  PERFORM public.statistical_history_facet_derive(p_valid_from => p_valid_from, p_valid_until => p_valid_until);
END;
$derive_reports$;


-- ============================================================================
-- Part 6: Restore original statistical_history_derive with FOR LOOP
-- ============================================================================
CREATE OR REPLACE FUNCTION public.statistical_history_derive(
  p_valid_from date DEFAULT '-infinity'::date,
  p_valid_until date DEFAULT 'infinity'::date
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_history_derive$
DECLARE
    v_period RECORD;
BEGIN
    RAISE DEBUG 'Running statistical_history_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Get relevant periods and store them in a temporary table
    CREATE TEMPORARY TABLE temp_periods ON COMMIT DROP AS
    SELECT *
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution, -- Get both year and year-month
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    );

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history sh
    USING temp_periods tp
    WHERE sh.year = tp.year
    AND sh.month IS NOT DISTINCT FROM tp.month;

    -- Loop through each period and insert the new data by calling the _def function.
    FOR v_period IN SELECT * FROM temp_periods
    LOOP
        INSERT INTO public.statistical_history
        SELECT * FROM public.statistical_history_def(v_period.resolution, v_period.year, v_period.month);
    END LOOP;

    -- Clean up
    DROP TABLE IF EXISTS temp_periods;
END;
$statistical_history_derive$;


-- ============================================================================
-- Part 7: Restore original statistical_history_facet_derive with FOR LOOP
-- ============================================================================
CREATE OR REPLACE FUNCTION public.statistical_history_facet_derive(
  p_valid_from date DEFAULT '-infinity'::date,
  p_valid_until date DEFAULT 'infinity'::date
)
RETURNS void
LANGUAGE plpgsql
AS $statistical_history_facet_derive$
DECLARE
    v_period RECORD;
BEGIN
    RAISE DEBUG 'Running statistical_history_facet_derive(p_valid_from=%, p_valid_until=%)', p_valid_from, p_valid_until;

    -- Get relevant periods and store them in a temporary table
    CREATE TEMPORARY TABLE temp_periods ON COMMIT DROP AS
    SELECT *
    FROM public.get_statistical_history_periods(
        p_resolution := null::public.history_resolution,
        p_valid_from := p_valid_from,
        p_valid_until := p_valid_until
    );

    -- Delete existing records for the affected periods
    DELETE FROM public.statistical_history_facet shf
    USING temp_periods tp
    WHERE shf.year = tp.year
      AND shf.month IS NOT DISTINCT FROM tp.month
      AND shf.resolution = tp.resolution;

    -- Loop through each period and insert the new data by calling the _def function.
    FOR v_period IN SELECT * FROM temp_periods LOOP
        IF COALESCE(current_setting('statbus.statistical_history_facet_derive.log', true), 'f')::boolean THEN
            RAISE NOTICE 'Processing facets for period: resolution=%, year=%, month=%', v_period.resolution, v_period.year, v_period.month;
        END IF;

        INSERT INTO public.statistical_history_facet
        SELECT * FROM public.statistical_history_facet_def(v_period.resolution, v_period.year, v_period.month);
    END LOOP;

    -- Clean up
    IF to_regclass('pg_temp.temp_periods') IS NOT NULL THEN DROP TABLE temp_periods; END IF;
END;
$statistical_history_facet_derive$;

END;
