BEGIN;

-- REVOKE FROM PUBLIC in 20260422180000 removed EXECUTE from all roles including
-- admin_user.  Test 204 (and legitimate admin inspection) calls
-- statistical_history_def() as admin_user.  Restore EXECUTE for admin_user only;
-- authenticated and regular_user remain revoked (no PostgREST /rpc exposure).
--
-- Bracket with sql_saga_health_checks DISABLE to prevent the event trigger from
-- scanning pre-existing activity__for_portion_of_valid grant state (same pattern
-- as migrations 20260223185108 and 20260422180000).

ALTER EVENT TRIGGER sql_saga_health_checks DISABLE;

GRANT EXECUTE ON FUNCTION public.statistical_history_def(
    history_resolution, integer, integer, int4range
) TO admin_user;

ALTER EVENT TRIGGER sql_saga_health_checks ENABLE;

END;
