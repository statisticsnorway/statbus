BEGIN;

\echo public.activity_hierarchy
DROP FUNCTION public.activity_hierarchy(parent_establishment_id INTEGER,parent_legal_unit_id INTEGER,valid_on DATE);

END;
