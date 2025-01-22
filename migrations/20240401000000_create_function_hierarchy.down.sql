BEGIN;

\echo public.location_hierarchy
DROP FUNCTION public.location_hierarchy(parent_establishment_id INTEGER,parent_legal_unit_id INTEGER,valid_on DATE);

END;
