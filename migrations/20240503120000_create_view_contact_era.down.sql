-- Down Migration 20250127204854: create_view_contact_era
BEGIN;

DROP TRIGGER IF EXISTS contact_era_upsert ON public.contact_era;
DROP FUNCTION IF EXISTS admin.contact_era_upsert();
DROP VIEW IF EXISTS public.contact_era;

END;
