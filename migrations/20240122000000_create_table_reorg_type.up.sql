BEGIN;

-- Legal reorganization types (merger, acquisition, spin-off, etc.)
CREATE TABLE public.legal_reorg_type (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text UNIQUE NOT NULL,
    name text NOT NULL,
    description text NOT NULL,
    enabled boolean NOT NULL,
    custom boolean NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_legal_reorg_type_code ON public.legal_reorg_type USING btree (code) WHERE enabled;
CREATE INDEX ix_legal_reorg_type_enabled ON public.legal_reorg_type USING btree (enabled);

COMMENT ON TABLE public.legal_reorg_type IS 'Types of legal unit reorganizations (merger, acquisition, spin-off, etc.)';

END;
