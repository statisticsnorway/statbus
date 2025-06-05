-- Migration 202504221554: Drop specific worker status functions from public schema
BEGIN;

-- Revoke execute permissions
REVOKE EXECUTE ON FUNCTION public.is_importing() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.is_deriving_statistical_units() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.is_deriving_reports() FROM authenticated;

-- Drop the functions
DROP FUNCTION IF EXISTS public.is_importing();
DROP FUNCTION IF EXISTS public.is_deriving_statistical_units();
DROP FUNCTION IF EXISTS public.is_deriving_reports();

COMMIT;
