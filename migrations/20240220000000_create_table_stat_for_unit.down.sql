BEGIN;

-- Drop constraints and era in reverse order of creation.
SELECT sql_saga.drop_for_portion_of_view('public.stat_for_unit');
SELECT sql_saga.drop_foreign_key(
    table_oid => 'public.stat_for_unit',
    column_names => ARRAY['legal_unit_id'],
    era_name => 'valid'
);
SELECT sql_saga.drop_foreign_key(
    table_oid => 'public.stat_for_unit',
    column_names => ARRAY['establishment_id'],
    era_name => 'valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.stat_for_unit',
    key_name => 'stat_for_unit_stat_definition_id_legal_unit_id_valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.stat_for_unit',
    key_name => 'stat_for_unit_stat_definition_id_establishment_id_valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.stat_for_unit',
    key_name => 'stat_for_unit_id_valid'
);
SELECT sql_saga.drop_era('public.stat_for_unit');

DROP TABLE public.stat_for_unit;

END;
