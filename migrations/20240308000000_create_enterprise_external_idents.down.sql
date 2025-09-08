BEGIN;

DROP VIEW public.enterprise_external_idents;
DROP FUNCTION public.get_external_idents(public.statistical_unit_type, INTEGER);

END;
