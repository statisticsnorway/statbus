BEGIN;

DROP VIEW public.region_upload;
DROP FUNCTION admin.region_upload_upsert();

DROP FUNCTION admin.type_numeric_field(jsonb, text, int, int, jsonb);
DROP FUNCTION admin.type_ltree_field(jsonb, text, jsonb);

END;
