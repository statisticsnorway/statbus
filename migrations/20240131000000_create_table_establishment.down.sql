BEGIN;

-- Drop constraints and era in reverse order of creation.
SELECT sql_saga.drop_foreign_key(
    table_oid => 'public.establishment',
    column_names => ARRAY['legal_unit_id'],
    era_name => 'valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.establishment',
    key_name => 'establishment_legal_unit_id_primary_valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.establishment',
    key_name => 'establishment_enterprise_id_primary_valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.establishment',
    key_name => 'establishment_id_valid'
);
SELECT sql_saga.drop_era('public.establishment');

DROP TABLE public.establishment;
DROP FUNCTION admin.establishment_id_exists(integer);

END;
