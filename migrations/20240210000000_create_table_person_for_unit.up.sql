BEGIN;

CREATE TABLE public.person_for_unit (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    valid_until date NOT NULL,
    person_id integer NOT NULL REFERENCES public.person(id) ON DELETE RESTRICT,
    person_role_id integer REFERENCES public.person_role(id),
    data_source_id integer REFERENCES public.data_source(id) ON DELETE RESTRICT,
    establishment_id integer,
    legal_unit_id integer,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL
        )
);
CREATE INDEX ix_person_for_unit_person_id ON public.person_for_unit USING btree (person_id);
CREATE INDEX ix_person_for_unit_person_role_id ON public.person_for_unit USING btree (person_role_id);
CREATE INDEX ix_person_for_unit_data_source_id ON public.person_for_unit USING btree (data_source_id);
CREATE INDEX ix_person_for_unit_legal_unit_id ON public.person_for_unit USING btree (legal_unit_id);
CREATE INDEX ix_person_for_unit_establishment_id ON public.person_for_unit USING btree (establishment_id);

-- Activate era handling
SELECT sql_saga.add_era('public.person_for_unit', p_synchronize_valid_to_column := 'valid_to');
SELECT sql_saga.add_unique_key(
    table_oid => 'public.person_for_unit',
    column_names => ARRAY['id'],
    unique_key_name => 'person_for_unit_id_valid'
);
SELECT sql_saga.add_unique_key(
    table_oid => 'public.person_for_unit',
    column_names => ARRAY['person_id', 'person_role_id', 'establishment_id'],
    unique_key_name => 'person_for_unit_person_role_establishment_valid'
);
SELECT sql_saga.add_unique_key(
    table_oid => 'public.person_for_unit',
    column_names => ARRAY['person_id', 'person_role_id', 'legal_unit_id'],
    unique_key_name => 'person_for_unit_person_role_legal_unit_valid'
);
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.person_for_unit',
    fk_column_names => ARRAY['establishment_id'],
    fk_era_name => 'valid',
    unique_key_name => 'establishment_id_valid'
);
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.person_for_unit',
    fk_column_names => ARRAY['legal_unit_id'],
    fk_era_name => 'valid',
    unique_key_name => 'legal_unit_id_valid'
);

END;
