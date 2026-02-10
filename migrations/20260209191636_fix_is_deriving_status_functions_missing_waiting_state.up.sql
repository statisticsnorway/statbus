-- Fix is_deriving_statistical_units() to include 'waiting' state.
--
-- When derive_statistical_unit spawns children (statistical_unit_refresh_batch),
-- its state becomes 'waiting' while children run. The old function only checked
-- 'pending' and 'processing', so it returned false during active derivation.
-- This caused the frontend to never see the true->false transition, so caches
-- were never invalidated after derivation completed.
--
-- Apply the same fix to is_deriving_reports() for consistency.
BEGIN;

CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $is_deriving_statistical_units$
  SELECT EXISTS (
    SELECT 1
    FROM worker.tasks
    WHERE command = 'derive_statistical_unit'
      AND state IN ('pending', 'processing', 'waiting')
    LIMIT 1
  );
$is_deriving_statistical_units$;

CREATE OR REPLACE FUNCTION public.is_deriving_reports()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER AS $is_deriving_reports$
  SELECT EXISTS (
    SELECT 1
    FROM worker.tasks
    WHERE command = 'derive_reports'
      AND state IN ('pending', 'processing', 'waiting')
    LIMIT 1
  );
$is_deriving_reports$;

END;
