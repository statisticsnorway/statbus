BEGIN;

CREATE TABLE public.unit_size (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text NOT NULL,
    name text NOT NULL,
    enabled boolean NOT NULL,
    custom boolean NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_unit_size_code ON public.unit_size USING btree (code) WHERE enabled;
CREATE INDEX ix_unit_size_enabled ON public.unit_size USING btree (enabled);

END;
