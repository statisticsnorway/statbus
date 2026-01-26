BEGIN;

CREATE TYPE external_ident_shape AS ENUM ('regular', 'hierarchical');

CREATE TABLE public.external_ident_type (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code VARCHAR(128) UNIQUE NOT NULL,
    name VARCHAR(50),
    shape external_ident_shape NOT NULL DEFAULT 'regular',
    labels LTREE, -- e.g., 'region.district.unit' for hierarchical types
    description text,
    priority integer UNIQUE,
    archived boolean NOT NULL DEFAULT false,
    
    -- Constraint: hierarchical types must have labels, regular types must not
    CONSTRAINT shape_labels_consistency CHECK (
        (shape = 'regular' AND labels IS NULL) OR
        (shape = 'hierarchical' AND labels IS NOT NULL)
    )
);
COMMENT ON TABLE public.external_ident_type IS 'Defines the types of external identifiers used by source systems (e.g., tax_ident, stat_ident). Types can be regular (simple text) or hierarchical (ltree structure).';

-- Register with lifecycle callbacks for code generation triggers
CALL lifecycle_callbacks.add_table('public.external_ident_type');

END;
