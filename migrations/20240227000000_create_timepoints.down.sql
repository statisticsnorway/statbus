BEGIN;

DROP PROCEDURE IF EXISTS public.timepoints_refresh(int4multirange, int4multirange, int4multirange);
DROP FUNCTION IF EXISTS public.timepoints_calculate(int4multirange, int4multirange, int4multirange);
DROP TABLE IF EXISTS public.timepoints;
DROP FUNCTION IF EXISTS public.array_to_int4multirange(int[]);

END;
