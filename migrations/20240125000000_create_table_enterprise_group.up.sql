BEGIN;

CREATE TABLE public.enterprise_group (
    id SERIAL NOT NULL,
    valid_after date GENERATED ALWAYS AS (valid_from - INTERVAL '1 day') STORED,
    valid_from date NOT NULL DEFAULT current_date,
    valid_to date NOT NULL DEFAULT 'infinity',
    active boolean NOT NULL DEFAULT true,
    short_name varchar(16),
    name varchar(256),
    created_at timestamp with time zone NOT NULL DEFAULT statement_timestamp(),
    enterprise_group_type_id integer REFERENCES public.enterprise_group_type(id),
    contact_person text,
    edit_by_user_id integer NOT NULL,
    edit_comment text,
    unit_size_id integer REFERENCES public.unit_size(id),
    data_source_id integer REFERENCES public.data_source(id),
    reorg_references text,
    reorg_date timestamp with time zone,
    reorg_type_id integer REFERENCES public.reorg_type(id),
    foreign_participation_id integer REFERENCES public.foreign_participation(id)
);
CREATE INDEX ix_enterprise_group_data_source_id ON public.enterprise_group USING btree (data_source_id);
CREATE INDEX ix_enterprise_group_enterprise_group_type_id ON public.enterprise_group USING btree (enterprise_group_type_id);
CREATE INDEX ix_enterprise_group_foreign_participation_id ON public.enterprise_group USING btree (foreign_participation_id);
CREATE INDEX ix_enterprise_group_name ON public.enterprise_group USING btree (name);
CREATE INDEX ix_enterprise_group_reorg_type_id ON public.enterprise_group USING btree (reorg_type_id);
CREATE INDEX ix_enterprise_group_size_id ON public.enterprise_group USING btree (unit_size_id);


CREATE FUNCTION admin.enterprise_group_id_exists(fk_id integer) RETURNS boolean LANGUAGE sql STABLE STRICT AS $$
    SELECT fk_id IS NULL OR EXISTS (SELECT 1 FROM public.enterprise_group WHERE id = fk_id);
$$;

END;
