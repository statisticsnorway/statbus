BEGIN;

-- Drop the refresh procedure
DROP PROCEDURE IF EXISTS public.timeline_legal_unit_refresh(int4multirange);

-- Drop the physical table
DROP TABLE IF EXISTS public.timeline_legal_unit;

-- Drop the view definition
DROP VIEW IF EXISTS public.timeline_legal_unit_def;

END;
