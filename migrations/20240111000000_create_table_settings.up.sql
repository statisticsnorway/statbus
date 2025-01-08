BEGIN;

-- Settings as configured by the system.
\echo public.settings
CREATE TABLE public.settings (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    activity_category_standard_id integer NOT NULL REFERENCES public.activity_category_standard(id) ON DELETE RESTRICT,
    only_one_setting BOOLEAN NOT NULL DEFAULT true,
    CHECK(only_one_setting),
    UNIQUE(only_one_setting)
);

END;