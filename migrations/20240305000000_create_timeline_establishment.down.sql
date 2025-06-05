BEGIN;

DROP FUNCTION IF EXISTS public.timeline_establishment_refresh(INTEGER[], DATE, DATE);
DROP TABLE IF EXISTS public.timeline_establishment;
DROP VIEW IF EXISTS public.timeline_establishment_def;

END;
