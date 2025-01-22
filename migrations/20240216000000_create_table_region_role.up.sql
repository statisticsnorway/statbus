BEGIN;

CREATE TABLE public.region_role (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role_id integer NOT NULL REFERENCES public.statbus_role(id) ON DELETE CASCADE,
    region_id integer NOT NULL REFERENCES public.region(id) ON DELETE CASCADE,
    UNIQUE(role_id, region_id)
);
CREATE INDEX ix_region_role ON public.region_role USING btree (region_id);

END;