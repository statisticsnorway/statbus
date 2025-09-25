BEGIN;

SELECT sql_saga.drop_for_portion_of_view('public.enterprise_group');
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.enterprise_group',
    key_name => 'enterprise_group_id_valid'
);
SELECT sql_saga.drop_era('public.enterprise_group');

DROP TABLE public.enterprise_group;
DROP FUNCTION admin.enterprise_group_id_exists(integer);

END;
