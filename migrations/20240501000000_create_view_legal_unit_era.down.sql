BEGIN;

DROP TRIGGER legal_unit_era_upsert ON public.legal_unit_era;
DROP FUNCTION admin.legal_unit_era_upsert();
DROP VIEW public.legal_unit_era;

END;
