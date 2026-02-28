BEGIN;

SELECT admin.drop_table_views_for_batch_api('public.power_group_type');
SELECT admin.drop_table_views_for_batch_api('public.legal_rel_type');

END;
