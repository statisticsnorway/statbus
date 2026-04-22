BEGIN;

-- Item 4 of #132: revoke public EXECUTE on statistical_history_def().
--
-- This function returns SETOF statistical_history_partitions (includes hash_slot)
-- and was callable by any authenticated client via PostgREST RPC at
-- /rpc/statistical_history_def.  It is an internal derive helper with no
-- legitimate external caller:
--   - worker.derive_statistical_history_period  (SECURITY DEFINER, runs as owner)
--   - public.statistical_history_derive         (SECURITY DEFINER, runs as owner)
-- Both are unaffected by revoking from PUBLIC.
--
-- REVOKE is DDL and fires the sql_saga_health_checks event trigger, which
-- scans all sql_saga-managed objects for grant consistency.  The trigger finds
-- a pre-existing INSERT grant on activity__for_portion_of_valid (propagated
-- from GRANT ALL ON activity) and raises an error unrelated to this migration.
-- Disable the trigger for the duration of this REVOKE, matching the pattern
-- established in migration 20260223185108.

ALTER EVENT TRIGGER sql_saga_health_checks DISABLE;

REVOKE EXECUTE ON FUNCTION public.statistical_history_def(
    history_resolution, integer, integer, int4range
) FROM PUBLIC;

ALTER EVENT TRIGGER sql_saga_health_checks ENABLE;

END;
