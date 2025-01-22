BEGIN;

SELECT admin.drop_table_views_for_batch_api('public.legal_form');

DROP INDEX IF EXISTS ix_legal_form_active_code;

END;
