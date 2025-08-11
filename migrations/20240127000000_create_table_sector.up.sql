BEGIN;

CREATE TABLE public.sector (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    path public.ltree UNIQUE NOT NULL,
    parent_id integer,
    label varchar NOT NULL GENERATED ALWAYS AS (replace(path::text,'.','')) STORED,
    code varchar GENERATED ALWAYS AS (NULLIF(regexp_replace(path::text, '[^0-9]', '', 'g'), '')) STORED,
    name text NOT NULL,
    description text,
    active boolean NOT NULL,
    custom bool NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE(path, active, custom)
);
CREATE UNIQUE INDEX sector_code_active_key ON public.sector USING btree (code) WHERE active;
CREATE INDEX ix_sector_active ON public.sector USING btree (active);
CREATE INDEX sector_parent_id_idx ON public.sector USING btree (parent_id);

END;
