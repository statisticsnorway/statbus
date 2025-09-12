BEGIN;

-- Drop the refresh procedure
DROP PROCEDURE IF EXISTS public.timeline_enterprise_refresh(int[]);

-- Drop the physical table
DROP TABLE IF EXISTS public.timeline_enterprise;

-- Drop the view definition
DROP VIEW IF EXISTS public.timeline_enterprise_def;

END;
