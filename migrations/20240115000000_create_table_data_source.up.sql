BEGIN;

CREATE TABLE public.data_source (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL,
    name text NOT NULL,
    enabled boolean NOT NULL,
    custom boolean NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_data_source_code ON public.data_source USING btree (code) WHERE enabled;
CREATE INDEX ix_data_source_enabled ON public.data_source USING btree (enabled);

END;
