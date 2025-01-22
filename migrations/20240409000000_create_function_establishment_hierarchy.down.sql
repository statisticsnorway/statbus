BEGIN;

\echo public.legal_unit_hierarchy
DROP FUNCTION public.legal_unit_hierarchy(parent_enterprise_id INTEGER, valid_on DATE);

\echo public.establishment_hierarchy
DROP FUNCTION public.establishment_hierarchy(parent_legal_unit_id INTEGER,parent_enterprise_id INTEGER,valid_on DATE);

END;
