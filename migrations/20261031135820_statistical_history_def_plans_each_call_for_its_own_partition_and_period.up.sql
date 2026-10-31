-- Migration 20261031135820: statistical_history_def plans each call for its own partition and period
BEGIN;

-- The worker calls this function once per history child, dozens of times in
-- one session. PL/pgSQL switches a statement to a generic plan after five
-- executions when its estimated cost looks no worse. For this query the
-- generic estimate is wrong by orders of magnitude: without the partition
-- range and the period dates it expects a handful of units, and joins the
-- per-unit versions with nested loops. With ~2,400 units in a partition range
-- that is millions of discarded join rows: 60 ms per child became 3.5 s on the
-- BRREG selection and about 50 s on test 401 (STATBUS-555). How many units a
-- call covers depends on exactly those values, so each call is planned for them.
ALTER FUNCTION public.statistical_history_def(public.history_resolution, integer, integer, int4range)
    SET plan_cache_mode = force_custom_plan;

COMMENT ON FUNCTION public.statistical_history_def(public.history_resolution, integer, integer, int4range) IS
'Demographics and stats of statistical units for one history period, per hash slot, optionally limited to the units whose hash_slot lies in p_hash_partition. Planned for each call''s own values (plan_cache_mode = force_custom_plan): the number of units a call covers depends on the partition range and the period, and a generic plan that cannot see them chose nested-loop joins that grow quadratically with the units (STATBUS-555).';

END;
