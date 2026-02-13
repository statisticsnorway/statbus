BEGIN;

CREATE TABLE public.person_role (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    enabled boolean NOT NULL,
    custom boolean NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE INDEX ix_person_role_enabled ON public.person_role USING btree (enabled);

END;
