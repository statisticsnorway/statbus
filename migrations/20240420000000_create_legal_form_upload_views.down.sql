BEGIN;

DROP VIEW public.legal_form_custom_only;
DROP FUNCTION admin.legal_form_custom_only_prepare();
DROP FUNCTION admin.legal_form_custom_only_upsert();

END;
