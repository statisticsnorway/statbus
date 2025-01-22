BEGIN;

DROP TRIGGER stat_for_unit_era_upsert ON public.stat_for_unit_era;
DROP FUNCTION admin.stat_for_unit_era_upsert();
DROP VIEW public.stat_for_unit_era;

END;
