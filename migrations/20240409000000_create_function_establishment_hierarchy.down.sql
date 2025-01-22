BEGIN;

DROP FUNCTION public.legal_unit_hierarchy(parent_enterprise_id INTEGER, valid_on DATE);

DROP FUNCTION public.establishment_hierarchy(parent_legal_unit_id INTEGER,parent_enterprise_id INTEGER,valid_on DATE);

END;
