BEGIN;

DROP VIEW public.country_view;
DROP FUNCTION admin.upsert_country();
DROP FUNCTION admin.delete_stale_country();

END;
