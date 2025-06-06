BEGIN;

CREATE TABLE public.establishment (
    id SERIAL NOT NULL,
    valid_from date NOT NULL,
    valid_after date NOT NULL,
    valid_to date NOT NULL DEFAULT 'infinity',
    active boolean NOT NULL DEFAULT true,
    short_name character varying(16),
    name character varying(256) NOT NULL,
    birth_date date,
    death_date date,
    free_econ_zone boolean,
    sector_id integer REFERENCES public.sector(id) ON DELETE RESTRICT,
    status_id integer NOT NULL REFERENCES public.status(id) ON DELETE RESTRICT,
    edit_comment character varying(512),
    edit_by_user_id integer NOT NULL REFERENCES auth.user(id) ON DELETE RESTRICT,
    edit_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    unit_size_id integer REFERENCES public.unit_size(id),
    data_source_id integer REFERENCES public.data_source(id) ON DELETE RESTRICT,
    enterprise_id integer REFERENCES public.enterprise(id) ON DELETE RESTRICT,
    legal_unit_id integer,
    primary_for_legal_unit boolean,
    primary_for_enterprise boolean,
    invalid_codes jsonb,
    CONSTRAINT "Must have either legal_unit_id or enterprise_id"
    CHECK( enterprise_id IS NOT NULL AND legal_unit_id IS     NULL
        OR enterprise_id IS     NULL AND legal_unit_id IS NOT NULL
        ),
    CONSTRAINT "primary_for_legal_unit and legal_unit_id must be defined together"
    CHECK( legal_unit_id IS NOT NULL AND primary_for_legal_unit IS NOT NULL
        OR legal_unit_id IS     NULL AND primary_for_legal_unit IS     NULL
        ),
    CONSTRAINT "primary_for_enterprise and enterprise_id must be defined together"
    CHECK( enterprise_id IS NOT NULL AND primary_for_enterprise IS NOT NULL
        OR enterprise_id IS     NULL AND primary_for_enterprise IS     NULL
        ),
    CONSTRAINT "enterprise_id enables sector_id"
    CHECK( CASE WHEN enterprise_id IS NULL THEN sector_id IS NULL END)
);

CREATE INDEX establishment_active_idx ON public.establishment(active);
CREATE INDEX ix_establishment_data_source_id ON public.establishment USING btree (data_source_id);
CREATE INDEX ix_establishment_sector_id ON public.establishment USING btree (sector_id);
CREATE INDEX ix_establishment_status_id ON public.establishment USING btree (status_id);
CREATE INDEX ix_establishment_enterprise_id ON public.establishment USING btree (enterprise_id);
CREATE INDEX ix_establishment_legal_unit_id ON public.establishment USING btree (legal_unit_id);
CREATE INDEX ix_establishment_name ON public.establishment USING btree (name);
CREATE INDEX ix_establishment_size_id ON public.establishment USING btree (unit_size_id);
CREATE INDEX ix_establishment_edit_by_user_id ON public.establishment USING btree (edit_by_user_id);

CREATE INDEX establishment_enterprise_id_primary_for_enterprise_idx ON public.establishment(enterprise_id, primary_for_enterprise) WHERE enterprise_id IS NOT NULL;
CREATE INDEX establishment_legal_unit_id_primary_for_legal_unit_idx ON public.establishment(legal_unit_id, primary_for_legal_unit) WHERE legal_unit_id IS NOT NULL;

CREATE OR REPLACE FUNCTION admin.establishment_id_exists(fk_id integer) RETURNS boolean LANGUAGE sql STABLE STRICT AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.establishment WHERE id = fk_id);
$$;

CREATE TRIGGER trg_establishment_synchronize_valid_from_after
    BEFORE INSERT OR UPDATE ON public.establishment
    FOR EACH ROW EXECUTE FUNCTION public.synchronize_valid_from_after();

END;
