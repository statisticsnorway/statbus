BEGIN;

\echo public.stat_for_unit_hierarchy
DROP FUNCTION public.stat_for_unit_hierarchy(parent_establishment_id INTEGER, parent_legal_unit_id INTEGER,valid_on DATE);

END;
