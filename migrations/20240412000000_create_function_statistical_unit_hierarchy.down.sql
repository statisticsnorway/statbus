BEGIN;

\echo public.statistical_unit_hierarchy
DROP FUNCTION public.statistical_unit_hierarchy(unit_type public.statistical_unit_type, unit_id INTEGER, valid_on DATE);

END;
