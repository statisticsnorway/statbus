BEGIN;

CREATE TABLE public.data_source (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL,
    name text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_data_source_code ON public.data_source USING btree (code) WHERE active;
CREATE INDEX ix_data_source_active ON public.data_source USING btree (active);

END;
