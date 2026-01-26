-- Hierarchical Demo: Setup with Hierarchical Identifier Types
-- This extends the base demo configuration with hierarchical identifier types
-- demonstrating both deep (4-level) and shallow (2-level) hierarchies.

-- First, run the base demo setup
\echo "Running base demo setup"
\i samples/demo/getting-started.sql

-- Add a hierarchical external identifier type for census tracking (Uganda use case)
-- 4-level hierarchy: census.region.surveyor.unit_no
\echo "Adding hierarchical census identifier type (4-level)"
INSERT INTO public.external_ident_type (code, name, shape, labels, priority, archived)
VALUES ('census_ident', 'Census Identifier', 'hierarchical', 'census.region.surveyor.unit_no', 50, false)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    shape = EXCLUDED.shape,
    labels = EXCLUDED.labels,
    priority = EXCLUDED.priority,
    archived = EXCLUDED.archived;

-- Add a hierarchical external identifier type for judicial court tracking (Morocco use case)
-- 2-level hierarchy: court.unit_no
-- CNSS (Caisse Nationale de Sécurité Sociale) assigns businesses to judicial courts,
-- and HCP (Haut-Commissariat au Plan) assigns unit numbers within each court jurisdiction.
\echo "Adding hierarchical judicial identifier type (2-level)"
INSERT INTO public.external_ident_type (code, name, shape, labels, priority, archived)
VALUES ('judicial_ident', 'Judicial Court Identifier', 'hierarchical', 'court.unit_no', 51, false)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    shape = EXCLUDED.shape,
    labels = EXCLUDED.labels,
    priority = EXCLUDED.priority,
    archived = EXCLUDED.archived;

