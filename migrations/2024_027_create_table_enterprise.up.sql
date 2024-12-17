BEGIN;

\echo public.enterprise
CREATE TABLE public.enterprise (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    active boolean NOT NULL DEFAULT true,
    short_name character varying(16),
    notes text,
    edit_by_user_id character varying(100) NOT NULL,
    edit_comment character varying(500)
);

END;