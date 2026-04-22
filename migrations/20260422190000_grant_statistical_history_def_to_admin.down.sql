BEGIN;

REVOKE EXECUTE ON FUNCTION public.statistical_history_def(
    history_resolution, integer, integer, int4range
) FROM admin_user;

END;
