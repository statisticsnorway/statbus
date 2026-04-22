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

REVOKE EXECUTE ON FUNCTION public.statistical_history_def(
    history_resolution, integer, integer, int4range
) FROM PUBLIC;

END;
