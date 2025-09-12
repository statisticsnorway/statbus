BEGIN;

-- Drop the refresh function
DROP PROCEDURE IF EXISTS public.timesegments_refresh(p_unit_ids int[], p_unit_type public.statistical_unit_type);

-- Drop the physical table
DROP TABLE IF EXISTS public.timesegments;

-- Drop the definition view
DROP VIEW IF EXISTS public.timesegments_def;

DROP TABLE IF EXISTS public.timesegments_years;
DROP FUNCTION IF EXISTS public.timesegments_years_refresh();
DROP VIEW IF EXISTS public.timesegments_years_def;

END;
