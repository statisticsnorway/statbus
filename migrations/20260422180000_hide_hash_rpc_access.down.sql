BEGIN;

GRANT EXECUTE ON FUNCTION public.statistical_history_def(
    history_resolution, integer, integer, int4range
) TO PUBLIC;

END;
