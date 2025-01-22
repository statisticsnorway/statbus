BEGIN;

DROP TRIGGER establishment_era_upsert ON public.establishment_era;
DROP FUNCTION admin.establishment_era_upsert();
DROP VIEW public.establishment_era;

END;
