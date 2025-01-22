BEGIN;

CREATE TABLE public.legal_unit (
    id SERIAL NOT NULL,
    valid_after date GENERATED ALWAYS AS (valid_from - INTERVAL '1 day') STORED,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    active boolean NOT NULL DEFAULT true,
    short_name character varying(16),
    name character varying(256),
    birth_date date,
    death_date date,
    web_address character varying(200),
    telephone_no character varying(50),
    email_address character varying(50),
    free_econ_zone boolean,
    notes text,
    sector_id integer REFERENCES public.sector(id),
    legal_form_id integer REFERENCES public.legal_form(id),
    edit_by_user_id character varying(100) NOT NULL,
    edit_comment character varying(500),
    unit_size_id integer REFERENCES public.unit_size(id),
    foreign_participation_id integer REFERENCES public.foreign_participation(id),
    data_source_id integer REFERENCES public.data_source(id) ON DELETE RESTRICT,
    enterprise_id integer NOT NULL REFERENCES public.enterprise(id) ON DELETE RESTRICT,
    primary_for_enterprise boolean NOT NULL,
    invalid_codes jsonb
);

CREATE INDEX legal_unit_active_idx ON public.legal_unit(active);
CREATE INDEX ix_legal_unit_data_source_id ON public.legal_unit USING btree (data_source_id);
CREATE INDEX ix_legal_unit_enterprise_id ON public.legal_unit USING btree (enterprise_id);
CREATE INDEX ix_legal_unit_foreign_participation_id ON public.legal_unit USING btree (foreign_participation_id);
CREATE INDEX ix_legal_unit_sector_id ON public.legal_unit USING btree (sector_id);
CREATE INDEX ix_legal_unit_legal_form_id ON public.legal_unit USING btree (legal_form_id);
CREATE INDEX ix_legal_unit_name ON public.legal_unit USING btree (name);
CREATE INDEX ix_legal_unit_size_id ON public.legal_unit USING btree (unit_size_id);


CREATE FUNCTION admin.legal_unit_id_exists(fk_id integer) RETURNS boolean LANGUAGE sql STABLE STRICT AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.legal_unit WHERE id = fk_id);
$$;

END;