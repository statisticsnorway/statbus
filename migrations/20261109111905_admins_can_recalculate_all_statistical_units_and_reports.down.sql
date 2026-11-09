-- Down Migration 20261109111905: admins can recalculate all statistical units and reports
BEGIN;

DROP FUNCTION public.recalculate_all();

END;
