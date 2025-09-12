BEGIN;

DROP TABLE public.timepoints;
DROP FUNCTION public.timepoints_calculate(p_establishment_ids int[], p_legal_unit_ids int[], p_enterprise_ids int[]);
DROP PROCEDURE public.timepoints_refresh(p_unit_ids int[], p_unit_type public.statistical_unit_type);

END;
