BEGIN;

CREATE TYPE public.activity_type AS ENUM ('primary', 'secondary', 'ancilliary');

CREATE TABLE public.activity (
    id SERIAL NOT NULL,
    valid_from date NOT NULL,
    valid_to date NOT NULL,
    valid_until date NOT NULL,
    type public.activity_type NOT NULL,
    category_id integer NOT NULL REFERENCES public.activity_category(id) ON DELETE CASCADE,
    data_source_id integer REFERENCES public.data_source(id) ON DELETE SET NULL,
    edit_comment character varying(512),
    edit_by_user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE RESTRICT,
    edit_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    establishment_id integer,
    legal_unit_id integer,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL
        )
);
CREATE INDEX ix_activity_type ON public.activity USING btree (type);
CREATE INDEX ix_activity_category_id ON public.activity USING btree (category_id);
CREATE INDEX ix_activity_establishment_id ON public.activity USING btree (establishment_id);
CREATE INDEX ix_activity_legal_unit_id ON public.activity USING btree (legal_unit_id);
CREATE INDEX ix_activity_edit_by_user_id ON public.activity USING btree (edit_by_user_id);
CREATE INDEX ix_activity_data_source_id ON public.activity USING btree (data_source_id);
CREATE INDEX ix_activity_establishment_valid_from_valid_until ON public.activity USING btree (establishment_id, valid_from, valid_until);
CREATE INDEX ix_activity_legal_unit_id_valid_range ON public.activity USING gist (legal_unit_id, daterange(valid_from, valid_until, '[)'));

-- Activate era handling
SELECT sql_saga.add_era('public.activity', synchronize_valid_to_column => 'valid_to');
SELECT sql_saga.add_unique_key(
    table_oid => 'public.activity'::regclass,
    key_type => 'primary',
    column_names => ARRAY['id'],
    unique_key_name => 'activity_id_valid'
);
SELECT sql_saga.add_unique_key(
    table_oid => 'public.activity'::regclass,
    key_type => 'natural',
    column_names => ARRAY['type', 'establishment_id'],
    unique_key_name => 'activity_type_establishment_id_valid'
);
SELECT sql_saga.add_unique_key(
    table_oid => 'public.activity'::regclass,
    key_type => 'natural',
    column_names => ARRAY['type', 'legal_unit_id'],
    unique_key_name => 'activity_type_legal_unit_id_valid'
);
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.activity'::regclass,
    fk_column_names => ARRAY['establishment_id'],
    fk_era_name => 'valid',
    unique_key_name => 'establishment_id_valid'
);
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.activity'::regclass,
    fk_column_names => ARRAY['legal_unit_id'],
    fk_era_name => 'valid',
    unique_key_name => 'legal_unit_id_valid'
);

-- Add a view for portion-of updates
SELECT sql_saga.add_for_portion_of_view('public.activity');

END;
