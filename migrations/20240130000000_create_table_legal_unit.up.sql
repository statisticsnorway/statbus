BEGIN;

CREATE TABLE public.legal_unit (
    id SERIAL NOT NULL,
    valid_from date NOT NULL,
    valid_to date,
    valid_until date,
    short_name character varying(16),
    name character varying(256) NOT NULL,
    birth_date date,
    death_date date,
    free_econ_zone boolean,
    sector_id integer REFERENCES public.sector(id) ON DELETE RESTRICT,
    status_id integer NOT NULL REFERENCES public.status(id) ON DELETE RESTRICT,
    legal_form_id integer REFERENCES public.legal_form(id),
    edit_comment character varying(512),
    edit_by_user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE RESTRICT,
    edit_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    unit_size_id integer REFERENCES public.unit_size(id),
    foreign_participation_id integer REFERENCES public.foreign_participation(id),
    data_source_id integer REFERENCES public.data_source(id) ON DELETE RESTRICT,
    enterprise_id integer NOT NULL REFERENCES public.enterprise(id) ON DELETE RESTRICT,
    primary_for_enterprise boolean NOT NULL,
    invalid_codes jsonb
);

CREATE INDEX ix_legal_unit_data_source_id ON public.legal_unit USING btree (data_source_id);
CREATE INDEX ix_legal_unit_enterprise_id ON public.legal_unit USING btree (enterprise_id);
CREATE INDEX ix_legal_unit_foreign_participation_id ON public.legal_unit USING btree (foreign_participation_id);
CREATE INDEX ix_legal_unit_sector_id ON public.legal_unit USING btree (sector_id);
CREATE INDEX ix_legal_unit_status_id ON public.legal_unit USING btree (status_id);
CREATE INDEX ix_legal_unit_legal_form_id ON public.legal_unit USING btree (legal_form_id);
CREATE INDEX ix_legal_unit_name ON public.legal_unit USING btree (name);
CREATE INDEX ix_legal_unit_size_id ON public.legal_unit USING btree (unit_size_id);
CREATE INDEX ix_legal_unit_edit_by_user_id ON public.legal_unit USING btree (edit_by_user_id);


CREATE FUNCTION admin.legal_unit_id_exists(fk_id integer) RETURNS boolean LANGUAGE sql STABLE STRICT AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.legal_unit WHERE id = fk_id);
$$;

-- Activate era handling
SELECT sql_saga.add_era('public.legal_unit', synchronize_valid_to_column => 'valid_to');
-- This creates a GIST exclusion constraint (`legal_unit_id_valid_excl`) to ensure that
-- there are no overlapping time periods for the same legal_unit ID. This is backed by a GIST
-- index, which also accelerates temporal queries on the primary key.
SELECT sql_saga.add_unique_key(
    table_oid => 'public.legal_unit',
    key_type => 'primary',
    column_names => ARRAY['id'],
    unique_key_name => 'legal_unit_id_valid'
);
-- Enforce that an enterprise can only have one primary legal unit at any given time.
-- This creates a GIST exclusion constraint (`legal_unit_enterprise_id_primary_valid_excl`)
-- to prevent overlapping time periods for primary legal units within the same enterprise.
SELECT sql_saga.add_unique_key(
    table_oid => 'public.legal_unit',
    column_names => ARRAY['enterprise_id'],
    key_type => 'predicated',
    predicate => 'primary_for_enterprise IS TRUE',
    unique_key_name => 'legal_unit_enterprise_id_primary_valid'
);


-- Add a view for portion-of updates, allowing for easier updates to specific time slices.
SELECT sql_saga.add_for_portion_of_view('public.legal_unit');

END;
