BEGIN;

DROP TRIGGER activity_era_upsert ON public.activity_era;
DROP FUNCTION admin.activity_era_upsert();
DROP VIEW public.activity_era;

END;
