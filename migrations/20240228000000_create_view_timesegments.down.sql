BEGIN;

-- Drop the refresh function
DROP PROCEDURE IF EXISTS public.timesegments_refresh(int4multirange, int4multirange, int4multirange);

-- Drop the physical table
DROP TABLE IF EXISTS public.timesegments;

-- Drop the definition view
DROP VIEW IF EXISTS public.timesegments_def;

DROP TABLE IF EXISTS public.timesegments_years;
DROP PROCEDURE IF EXISTS public.timesegments_years_refresh();
DROP VIEW IF EXISTS public.timesegments_years_def;

END;
