BEGIN;

SELECT admin.drop_table_views_for_batch_api('public.enterprise_group_type');
SELECT admin.drop_table_views_for_batch_api('public.enterprise_group_role');

END;
