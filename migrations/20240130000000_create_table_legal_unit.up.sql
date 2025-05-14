BEGIN;

CREATE TABLE public.legal_unit (
    id SERIAL NOT NULL,
    valid_from date NOT NULL DEFAULT current_date,
    valid_after date NOT NULL,
    valid_to date NOT NULL DEFAULT 'infinity',
    active boolean NOT NULL DEFAULT true,
    short_name character varying(16),
    name character varying(256),
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

CREATE INDEX legal_unit_active_idx ON public.legal_unit(active);
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

CREATE TRIGGER trg_legal_unit_synchronize_valid_from_after
    BEFORE INSERT OR UPDATE ON public.legal_unit
    FOR EACH ROW EXECUTE FUNCTION public.synchronize_valid_from_after();

END;
