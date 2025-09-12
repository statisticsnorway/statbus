BEGIN;

-- Drop constraints and era in reverse order of creation.
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.legal_unit',
    key_name => 'legal_unit_enterprise_id_primary_valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.legal_unit',
    key_name => 'legal_unit_id_valid'
);
SELECT sql_saga.drop_era('public.legal_unit');

DROP TABLE public.legal_unit;
DROP FUNCTION admin.legal_unit_id_exists(integer);

END;
