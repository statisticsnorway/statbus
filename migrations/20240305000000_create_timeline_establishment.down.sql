BEGIN;

DROP PROCEDURE IF EXISTS public.timeline_establishment_refresh(int[]);
DROP PROCEDURE IF EXISTS public.timeline_refresh(text, public.statistical_unit_type, int[]);
DROP TABLE IF EXISTS public.timeline_establishment;
DROP VIEW IF EXISTS public.timeline_establishment_def;

END;
