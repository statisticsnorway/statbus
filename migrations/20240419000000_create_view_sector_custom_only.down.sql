BEGIN;

DROP VIEW public.sector_custom_only;
DROP FUNCTION admin.sector_custom_only_prepare();
DROP FUNCTION admin.sector_custom_only_upsert();

END;
