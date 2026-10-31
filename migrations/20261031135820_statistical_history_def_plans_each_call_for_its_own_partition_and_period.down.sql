-- Migration 20261031135820 down: statistical_history_def without its own plan_cache_mode and comment
BEGIN;

ALTER FUNCTION public.statistical_history_def(public.history_resolution, integer, integer, int4range)
    RESET plan_cache_mode;

COMMENT ON FUNCTION public.statistical_history_def(public.history_resolution, integer, integer, int4range) IS NULL;

END;
