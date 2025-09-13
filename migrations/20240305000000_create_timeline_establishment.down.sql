BEGIN;

DROP PROCEDURE IF EXISTS public.timeline_establishment_refresh(int4multirange);
DROP PROCEDURE IF EXISTS public.timeline_refresh(text, public.statistical_unit_type, int4multirange);
DROP TABLE IF EXISTS public.timeline_establishment;
DROP VIEW IF EXISTS public.timeline_establishment_def;

END;
