BEGIN;

-- Drop the trigger and function for cycle check
DROP TRIGGER IF EXISTS legal_relationship_cycle_check_trigger ON public.legal_relationship;
DROP FUNCTION IF EXISTS public.legal_relationship_cycle_check();

-- Drop the trigger and function for primary_influencer_only auto-set
DROP TRIGGER IF EXISTS trg_legal_relationship_set_primary_influencer_only ON public.legal_relationship;
DROP FUNCTION IF EXISTS public.legal_relationship_set_primary_influencer_only();

-- Drop sql_saga components
SELECT sql_saga.drop_for_portion_of_view('public.legal_relationship');

SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.legal_relationship',
    key_name => 'legal_relationship_influenced_primary'
);

SELECT sql_saga.drop_foreign_key(
    fk_table_oid => 'public.legal_relationship'::regclass,
    fk_column_names => ARRAY['influenced_id'],
    pk_table_oid => 'public.legal_unit',
    pk_column_names => ARRAY['id']
);

SELECT sql_saga.drop_foreign_key(
    fk_table_oid => 'public.legal_relationship'::regclass,
    fk_column_names => ARRAY['influencing_id'],
    pk_table_oid => 'public.legal_unit',
    pk_column_names => ARRAY['id']
);

SELECT sql_saga.drop_unique_key_by_name(
    table_oid => 'public.legal_relationship',
    key_name => 'legal_relationship_id_valid'
);

SELECT sql_saga.drop_era('public.legal_relationship');

DROP TABLE public.legal_relationship;

END;
