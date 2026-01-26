-- Hierarchical Demo: Setup with Census Identifier
-- This extends the base demo configuration with a hierarchical identifier type

-- First, run the base demo setup
\echo "Running base demo setup"
\i samples/demo/getting-started.sql

-- Add a hierarchical external identifier type for census tracking
\echo "Adding hierarchical census identifier type"
INSERT INTO public.external_ident_type (code, name, shape, labels, priority, archived)
VALUES ('census_ident', 'Census Identifier', 'hierarchical', 'census.region.surveyor.unit_no', 50, false)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    shape = EXCLUDED.shape,
    labels = EXCLUDED.labels,
    priority = EXCLUDED.priority,
    archived = EXCLUDED.archived;

