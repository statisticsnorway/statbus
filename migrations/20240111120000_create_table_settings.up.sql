BEGIN;

-- Settings as configured by the system.
CREATE TABLE public.settings (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    activity_category_standard_id integer NOT NULL REFERENCES public.activity_category_standard(id) ON DELETE RESTRICT,
    country_id integer NOT NULL REFERENCES public.country(id) ON DELETE RESTRICT,
    only_one_setting BOOLEAN GENERATED ALWAYS AS (id IS NOT NULL) STORED,
    UNIQUE(only_one_setting)
);

END;
