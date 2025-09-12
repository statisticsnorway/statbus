-- Down Migration 20240206120000: create_table_contact
BEGIN;

-- Drop constraints and era in reverse order of creation.
SELECT sql_saga.drop_foreign_key(
    table_oid => 'public.contact',
    column_names => ARRAY['legal_unit_id'],
    era_name => 'valid'
);
SELECT sql_saga.drop_foreign_key(
    table_oid => 'public.contact',
    column_names => ARRAY['establishment_id'],
    era_name => 'valid'
);
SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.contact',
    key_name => 'contact_id_valid'
);
SELECT sql_saga.drop_era('public.contact');

DROP TABLE public.contact;

END;
