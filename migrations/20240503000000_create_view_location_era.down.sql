BEGIN;

DROP TRIGGER location_era_upsert ON public.location_era;
DROP FUNCTION admin.location_era_upsert();
DROP VIEW public.location_era;

END;
