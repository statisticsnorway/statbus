BEGIN;

-- Legal reorganization types (merger, acquisition, spin-off, etc.)
CREATE TABLE public.legal_reorg_type (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text UNIQUE NOT NULL,
    name text NOT NULL,
    description text NOT NULL,
    active boolean NOT NULL,
    custom boolean NOT NULL,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL
);
CREATE UNIQUE INDEX ix_legal_reorg_type_code ON public.legal_reorg_type USING btree (code) WHERE active;
CREATE INDEX ix_legal_reorg_type_active ON public.legal_reorg_type USING btree (active);

COMMENT ON TABLE public.legal_reorg_type IS 'Types of legal unit reorganizations (merger, acquisition, spin-off, etc.)';

END;
