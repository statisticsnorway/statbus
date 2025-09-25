BEGIN;

CREATE TABLE public.person_for_unit (
    id SERIAL NOT NULL,
    valid_from date NOT NULL,
    valid_to date,
    valid_until date,
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
CREATE INDEX ix_person_for_unit_legal_unit_id_valid_range ON public.person_for_unit USING gist (legal_unit_id, daterange(valid_from, valid_until, '[)'));
CREATE INDEX ix_person_for_unit_establishment_id_valid_range ON public.person_for_unit USING gist (establishment_id, daterange(valid_from, valid_until, '[)'));

-- Activate era handling
SELECT sql_saga.add_era('public.person_for_unit', synchronize_valid_to_column => 'valid_to');
-- This creates a GIST exclusion constraint (`person_for_unit_id_valid_excl`) to ensure that
-- there are no overlapping time periods for the same person_for_unit ID.
SELECT sql_saga.add_unique_key(
    table_oid => 'public.person_for_unit'::regclass,
    key_type => 'primary',
    column_names => ARRAY['id'],
    unique_key_name => 'person_for_unit_id_valid'
);
-- This creates a GIST exclusion constraint (`person_for_unit_person_role_establishment_valid_excl`)
-- to ensure a person cannot have the same role for the same establishment at the same time.
SELECT sql_saga.add_unique_key(
    table_oid => 'public.person_for_unit'::regclass,
    key_type => 'natural',
    column_names => ARRAY['person_id', 'person_role_id', 'establishment_id'],
    unique_key_name => 'person_for_unit_person_role_establishment_valid'
);
-- This creates a GIST exclusion constraint (`person_for_unit_person_role_legal_unit_valid_excl`)
-- to ensure a person cannot have the same role for the same legal unit at the same time.
SELECT sql_saga.add_unique_key(
    table_oid => 'public.person_for_unit'::regclass,
    key_type => 'natural',
    column_names => ARRAY['person_id', 'person_role_id', 'legal_unit_id'],
    unique_key_name => 'person_for_unit_person_role_legal_unit_valid'
);
-- This creates triggers to enforce that a person_for_unit's validity period is always contained
-- within the validity period of its parent establishment.
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.person_for_unit'::regclass,
    fk_column_names => ARRAY['establishment_id'],
    fk_era_name => 'valid',
    unique_key_name => 'establishment_id_valid'
);
-- This creates triggers to enforce that a person_for_unit's validity period is always contained
-- within the validity period of its parent legal unit.
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.person_for_unit'::regclass,
    fk_column_names => ARRAY['legal_unit_id'],
    fk_era_name => 'valid',
    unique_key_name => 'legal_unit_id_valid'
);

-- Add a view for portion-of updates, allowing for easier updates to specific time slices.
SELECT sql_saga.add_for_portion_of_view('public.person_for_unit');

END;
