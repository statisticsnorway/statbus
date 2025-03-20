BEGIN;

-- Drop the physical table first
DROP TABLE IF EXISTS public.timeline_legal_unit;

-- Drop the view definition
DROP VIEW IF EXISTS public.timeline_legal_unit_def;

-- Drop the refresh function
DROP FUNCTION IF EXISTS public.timeline_legal_unit_refresh;

END;
