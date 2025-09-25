BEGIN;

-- Drop constraints and era in reverse order of creation.
SELECT sql_saga.drop_for_portion_of_view('public.activity');
SELECT sql_saga.drop_foreign_key(
    table_oid => 'public.activity',
    column_names => ARRAY['legal_unit_id'],
    era_name => 'valid'
);
SELECT sql_saga.drop_foreign_key(
    table_oid => 'public.activity',
    column_names => ARRAY['establishment_id'],
    era_name => 'valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.activity',
    key_name => 'activity_type_legal_unit_id_valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.activity',
    key_name => 'activity_type_establishment_id_valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.activity',
    key_name => 'activity_id_valid'
);
SELECT sql_saga.drop_era('public.activity');

DROP TABLE public.activity;
DROP TYPE public.activity_type;

END;
