BEGIN;

CREATE TABLE public.sector (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    path public.ltree UNIQUE NOT NULL,
    parent_id integer,
    label varchar NOT NULL GENERATED ALWAYS AS (replace(path::text,'.','')) STORED,
    code varchar GENERATED ALWAYS AS (NULLIF(regexp_replace(path::text, '[^0-9]', '', 'g'), '')) STORED,
    name text NOT NULL,
    description text,
    enabled boolean NOT NULL,
    custom bool NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE(path, enabled, custom)
);
CREATE UNIQUE INDEX sector_code_enabled_key ON public.sector USING btree (code) WHERE enabled;
CREATE INDEX ix_sector_enabled ON public.sector USING btree (enabled);
CREATE INDEX sector_parent_id_idx ON public.sector USING btree (parent_id);

END;
