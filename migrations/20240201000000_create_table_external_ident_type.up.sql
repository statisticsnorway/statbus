BEGIN;

CREATE TABLE public.external_ident_type (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code VARCHAR(128) UNIQUE NOT NULL,
    name VARCHAR(50),
    by_tag_id INTEGER UNIQUE REFERENCES public.tag(id) ON DELETE RESTRICT,
    description text,
    priority integer UNIQUE,
    archived boolean NOT NULL DEFAULT false
);
COMMENT ON TABLE public.external_ident_type IS 'Defines the types of external identifiers used by source systems (e.g., tax_ident, stat_ident). Used to map external IDs to internal Statbus units.';

END;
