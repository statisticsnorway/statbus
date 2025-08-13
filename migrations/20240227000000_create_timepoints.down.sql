BEGIN;

DROP TABLE IF EXISTS public.timepoints_years;
DROP FUNCTION IF EXISTS public.timepoints_years_refresh();
DROP VIEW IF EXISTS public.timepoints_years_def;
DROP VIEW public.timepoints;

END;
