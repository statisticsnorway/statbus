-- Restore is_deriving_statistical_units() and is_deriving_reports()
-- to only check 'pending' and 'processing' states.
BEGIN;

CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $is_deriving_statistical_units$
  SELECT EXISTS (
    SELECT 1
    FROM worker.tasks
    WHERE command = 'derive_statistical_unit'
      AND state IN ('pending', 'processing')
    LIMIT 1
  );
$is_deriving_statistical_units$;

CREATE OR REPLACE FUNCTION public.is_deriving_reports()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $is_deriving_reports$
  SELECT EXISTS (
    SELECT 1
    FROM worker.tasks
    WHERE command = 'derive_reports'
      AND state IN ('pending', 'processing')
    LIMIT 1
  );
$is_deriving_reports$;

END;
