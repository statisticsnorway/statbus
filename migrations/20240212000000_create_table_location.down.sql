BEGIN;

-- Drop constraints and era in reverse order of creation.
SELECT sql_saga.drop_foreign_key(
    table_oid => 'public.location',
    column_names => ARRAY['legal_unit_id'],
    era_name => 'valid'
);
SELECT sql_saga.drop_foreign_key(
    table_oid => 'public.location',
    column_names => ARRAY['establishment_id'],
    era_name => 'valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.location',
    key_name => 'location_type_legal_unit_id_valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.location',
    key_name => 'location_type_establishment_id_valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.location',
    key_name => 'location_id_valid'
);
SELECT sql_saga.drop_era('public.location');

DROP TABLE public.location;
DROP TYPE public.location_type;

END;
