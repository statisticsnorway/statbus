BEGIN;

-- Classification of legal unit relationships (ownership, control)
CREATE TABLE public.legal_rel_type (
    id integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code text UNIQUE NOT NULL,
    name text NOT NULL,
    description text,
    primary_influencer_only boolean NOT NULL DEFAULT FALSE,
    enabled boolean NOT NULL DEFAULT true,
    custom boolean NOT NULL DEFAULT false,
    created_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    updated_at timestamp with time zone DEFAULT statement_timestamp() NOT NULL,
    UNIQUE (id, primary_influencer_only)
);

CREATE UNIQUE INDEX ix_legal_rel_type_code ON public.legal_rel_type USING btree (code) WHERE enabled;
CREATE INDEX ix_legal_rel_type_enabled ON public.legal_rel_type USING btree (enabled);

COMMENT ON TABLE public.legal_rel_type IS 'Classification of legal unit relationships (ownership, control)';
COMMENT ON COLUMN public.legal_rel_type.code IS 'Unique code for the relationship type';
COMMENT ON COLUMN public.legal_rel_type.name IS 'Human-readable name';
COMMENT ON COLUMN public.legal_rel_type.description IS 'Detailed description of this relationship type';
COMMENT ON COLUMN public.legal_rel_type.primary_influencer_only IS 'When TRUE, this relationship type forms power group hierarchies (guaranteed single root per influenced unit)';

-- Enable RLS (required by 20240603 migration check)
ALTER TABLE public.legal_rel_type ENABLE ROW LEVEL SECURITY;

END;
