BEGIN;

\echo public.statistical_unit_enterprise_id
DROP FUNCTION public.statistical_unit_enterprise_id(unit_type public.statistical_unit_type, unit_id INTEGER, valid_on DATE);

END;
