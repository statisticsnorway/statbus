BEGIN;

\echo public.enterprise_hierarchy
DROP FUNCTION public.enterprise_hierarchy(enterprise_id INTEGER, valid_on DATE);

END;
