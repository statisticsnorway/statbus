BEGIN;

-- Drop the refresh function
DROP FUNCTION IF EXISTS public.timesegments_refresh;

-- Drop the physical table
DROP TABLE IF EXISTS public.timesegments;

-- Drop the definition view
DROP VIEW IF EXISTS public.timesegments_def;

END;
