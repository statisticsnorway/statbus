BEGIN;

CREATE TABLE public.person_role (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text UNIQUE NOT NULL,
    name text UNIQUE NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);

END;