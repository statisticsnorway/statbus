-- Migration 202504221554: Add specific worker status functions to public schema
BEGIN;

-- Function to check if any import jobs are currently being processed
CREATE FUNCTION public.is_importing()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $public_is_importing$
  SELECT EXISTS (
    SELECT 1
    FROM worker.tasks
    WHERE command = 'import_job_process'
      AND state IN ('pending', 'processing')
    LIMIT 1
  );
$public_is_importing$;

-- Function to check if statistical units are currently being derived
CREATE FUNCTION public.is_deriving_statistical_units()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $public_is_deriving_statistical_units$
  SELECT EXISTS (
    SELECT 1
    FROM worker.tasks
    WHERE command = 'derive_statistical_unit'
      AND state IN ('pending', 'processing')
    LIMIT 1
  );
$public_is_deriving_statistical_units$;

-- Function to check if reports are currently being derived
CREATE FUNCTION public.is_deriving_reports()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $public_is_deriving_reports$
  SELECT EXISTS (
    SELECT 1
    FROM worker.tasks
    WHERE command = 'derive_reports'
      AND state IN ('pending', 'processing')
    LIMIT 1
  );
$public_is_deriving_reports$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION public.is_importing() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_deriving_statistical_units() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_deriving_reports() TO authenticated;

COMMIT;
