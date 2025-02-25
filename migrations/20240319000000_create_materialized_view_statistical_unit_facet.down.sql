BEGIN;

DROP FUNCTION IF EXISTS public.statistical_unit_facet_derive(date, date);
DROP TABLE IF EXISTS public.statistical_unit_facet;
DROP VIEW IF EXISTS public.statistical_unit_facet_def;

END;
