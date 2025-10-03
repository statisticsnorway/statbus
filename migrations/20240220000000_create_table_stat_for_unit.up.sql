BEGIN;

CREATE TABLE public.stat_for_unit (
    id SERIAL NOT NULL,
    stat_definition_id integer NOT NULL REFERENCES public.stat_definition(id) ON DELETE RESTRICT,
    valid_from date NOT NULL,
    valid_to date,
    valid_until date,
    data_source_id integer REFERENCES public.data_source(id) ON DELETE SET NULL,
    establishment_id integer,
    legal_unit_id integer,
    CONSTRAINT "One and only one statistical unit id must be set"
    CHECK( establishment_id IS NOT NULL AND legal_unit_id IS     NULL
        OR establishment_id IS     NULL AND legal_unit_id IS NOT NULL
        ),
    value_int INTEGER,
    value_float FLOAT,
    value_string VARCHAR,
    value_bool BOOLEAN,
    CHECK(
        (value_int IS NOT NULL AND value_float IS     NULL AND value_string IS     NULL AND value_bool IS     NULL) OR
        (value_int IS     NULL AND value_float IS NOT NULL AND value_string IS     NULL AND value_bool IS     NULL) OR
        (value_int IS     NULL AND value_float IS     NULL AND value_string IS NOT NULL AND value_bool IS     NULL) OR
        (value_int IS     NULL AND value_float IS     NULL AND value_string IS     NULL AND value_bool IS NOT NULL)
    ),
    -- Note: Audit columns (edit_by_user_id, edit_at) are populated by import procedures
    -- using values derived during the import job prepare step.
    created_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    edit_comment character varying(512),
    edit_by_user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE RESTRICT,
    edit_at timestamp with time zone NOT NULL DEFAULT statement_timestamp()
);

CREATE INDEX ix_stat_for_unit_stat_definition_id ON public.stat_for_unit USING btree (stat_definition_id);
CREATE INDEX ix_stat_for_unit_data_source_id ON public.stat_for_unit USING btree (data_source_id);
CREATE INDEX ix_stat_for_unit_legal_unit_id ON public.stat_for_unit USING btree (legal_unit_id);
CREATE INDEX ix_stat_for_unit_establishment_id ON public.stat_for_unit USING btree (establishment_id);
CREATE INDEX ix_stat_for_unit_legal_unit_id_valid_range ON public.stat_for_unit USING gist (legal_unit_id, daterange(valid_from, valid_until, '[)'));
CREATE INDEX ix_stat_for_unit_establishment_id_valid_range ON public.stat_for_unit USING gist (establishment_id, daterange(valid_from, valid_until, '[)'));

-- Activate era handling
SELECT sql_saga.add_era('public.stat_for_unit', synchronize_valid_to_column => 'valid_to');
-- This creates a GIST exclusion constraint (`stat_for_unit_id_valid_excl`) to ensure that
-- there are no overlapping time periods for the same stat_for_unit ID.
SELECT sql_saga.add_unique_key(
    table_oid => 'public.stat_for_unit',
    key_type => 'primary',
    column_names => ARRAY['id'],
    unique_key_name => 'stat_for_unit_id_valid'
);
-- A stat is uniquely defined by its type and the unit it belongs to. Since a stat can belong
-- to either a legal unit or an establishment (but not both), the true natural key is the
-- combination of all three columns. The CHECK constraint on the table ensures that one of the
-- unit ID columns is always NULL. By defining a single natural key with all three columns,
-- we provide the exact metadata signature that sql_saga's temporal_merge function needs to
-- correctly identify and coalesce adjacent, identical records. This creates a GIST exclusion
-- constraint (`stat_for_unit_natural_key_valid_excl`).
SELECT sql_saga.add_unique_key(
    table_oid => 'public.stat_for_unit',
    key_type => 'natural',
    column_names => ARRAY['stat_definition_id', 'legal_unit_id', 'establishment_id'],
    mutually_exclusive_columns => ARRAY['establishment_id','legal_unit_id'],
    unique_key_name => 'stat_for_unit_natural_key_valid'
);

-- This creates triggers to enforce that a stat_for_unit's validity period is always contained
-- within the validity period of its parent establishment.
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.stat_for_unit',
    fk_column_names => ARRAY['establishment_id'],
    pk_table_oid => 'public.establishment',
    pk_column_names => ARRAY['id']
);
-- This creates triggers to enforce that a stat_for_unit's validity period is always contained
-- within the validity period of its parent legal unit.
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.stat_for_unit',
    fk_column_names => ARRAY['legal_unit_id'],
    pk_table_oid => 'public.legal_unit',
    pk_column_names => ARRAY['id']
);

-- Add a view for portion-of updates, allowing for easier updates to specific time slices.
SELECT sql_saga.add_for_portion_of_view('public.stat_for_unit');

END;
