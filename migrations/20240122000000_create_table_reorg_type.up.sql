BEGIN;

CREATE TABLE public.reorg_type (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text UNIQUE NOT NULL,
    name text NOT NULL,
    description text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_reorg_type_code ON public.reorg_type USING btree (code) WHERE active;

END;
