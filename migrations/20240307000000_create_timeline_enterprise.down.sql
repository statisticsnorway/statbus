BEGIN;

-- Drop the physical table first
DROP TABLE IF EXISTS public.timeline_enterprise;

-- Drop the view definition
DROP VIEW IF EXISTS public.timeline_enterprise_def;

-- Drop the refresh function
DROP FUNCTION IF EXISTS public.timeline_enterprise_refresh;

END;
