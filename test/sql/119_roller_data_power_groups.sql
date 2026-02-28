BEGIN;

\i test/setup.sql

\echo "=== Test 119: Legal Relationship Import and Power Group Derivation ==="
\echo "Tests the complete flow: import LUs -> import relationships -> derive power groups"
\echo "Uses mixed BRREG types: HFOR (primary_influencer_only=TRUE) and DTPR (FALSE)"

-- Reset sequences for deterministic output
ALTER SEQUENCE public.power_group_ident_seq RESTART WITH 1;

-- A Super User configures statbus.
CALL test.set_user_from_email('test.admin@statbus.org');

-- Load base configuration
\i samples/norway/getting-started.sql

-- Seed BRREG relationship types (real Norwegian roller codes)
-- HFOR: Hovedforetak (parent company), structurally 1:1 → TRUE
-- DTPR: Deltaker med proratarisk ansvar (partner, pro-rata), 1:N → FALSE
INSERT INTO public.legal_rel_type (code, name, description, primary_influencer_only, enabled, custom)
SELECT 'HFOR', 'Hovedforetak', 'Main enterprise / parent company (structurally 1:1)', TRUE, true, false
WHERE NOT EXISTS (SELECT 1 FROM public.legal_rel_type WHERE code = 'HFOR');

INSERT INTO public.legal_rel_type (code, name, description, primary_influencer_only, enabled, custom)
SELECT 'DTPR', 'Partner (proratarisk)', 'Partner with pro-rata liability (multiple per entity)', FALSE, true, false
WHERE NOT EXISTS (SELECT 1 FROM public.legal_rel_type WHERE code = 'DTPR');

-- ============================================================================
\echo "=== Phase 1: Import Legal Units ==="
-- ============================================================================

-- Create import job for legal units
DO $$
DECLARE
    v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_unit_source_dates';
    IF v_definition_id IS NULL THEN
        RAISE EXCEPTION 'Import definition "legal_unit_source_dates" not found.';
    END IF;
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, 'import_119_legal_units', 'Test 119: Legal Units for Roller Data', 'Importing LUs for power group testing', 'Test 119');
END $$;

-- Upload LU data
\copy public.import_119_legal_units_upload(valid_from, valid_to, tax_ident, name) FROM 'test/data/roller_sample_legal_units.csv' WITH (FORMAT csv, HEADER true);

-- Process the LU import
CALL worker.process_tasks(p_queue => 'import');

\echo "LU import job status:"
SELECT slug, state, total_rows, imported_rows FROM public.import_job WHERE slug = 'import_119_legal_units';

\echo "Verify legal units were created:"
SELECT ei.ident AS tax_ident, lu.name, lu.valid_from, lu.valid_to
FROM public.legal_unit AS lu
JOIN public.external_ident AS ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type AS eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
WHERE ei.ident LIKE '10000000%'
ORDER BY ei.ident;

-- ============================================================================
\echo "=== Phase 2: Import Mixed Legal Relationships ==="
\echo "Nordic hierarchy uses HFOR (primary_influencer_only=TRUE)"
\echo "Baltic hierarchy uses DTPR (primary_influencer_only=FALSE)"
-- ============================================================================

-- Verify the legal_relationship import definition exists and is valid
\echo "Legal relationship import definitions:"
SELECT slug, name, valid FROM public.import_definition WHERE slug LIKE 'legal_relationship%';

-- Create import job for legal relationships
DO $$
DECLARE
    v_definition_id INT;
BEGIN
    SELECT id INTO v_definition_id FROM public.import_definition WHERE slug = 'legal_relationship_source_dates';
    IF v_definition_id IS NULL THEN
        RAISE EXCEPTION 'Import definition "legal_relationship_source_dates" not found.';
    END IF;
    INSERT INTO public.import_job (definition_id, slug, description, note, edit_comment)
    VALUES (v_definition_id, 'import_119_legal_rels', 'Test 119: Legal Relationships from Roller Data', 'Importing ownership/control relationships', 'Test 119');
END $$;

-- Upload relationship data (mixed types: HFOR for Nordic, DTPR for Baltic)
\copy public.import_119_legal_rels_upload(valid_from, valid_to, influencing_tax_ident, influenced_tax_ident, rel_type_code, percentage) FROM 'test/data/roller_sample.csv' WITH (FORMAT csv, HEADER true);

-- Process the relationship import
CALL worker.process_tasks(p_queue => 'import');

\echo "Relationship import job status:"
SELECT slug, state, total_rows, imported_rows FROM public.import_job WHERE slug = 'import_119_legal_rels';

\echo "Import data rows state:"
SELECT row_id, state, action, operation, errors
FROM public.import_119_legal_rels_data
ORDER BY row_id;

\echo "Verify legal relationships were created (note mixed types):"
SELECT
    ei_ing.ident AS influencing_tax_ident,
    ei_ed.ident AS influenced_tax_ident,
    lrt.code AS rel_type,
    lr.primary_influencer_only,
    lr.percentage,
    lr.valid_from,
    lr.valid_to
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS lu_ing ON lu_ing.id = lr.influencing_id
JOIN public.external_ident AS ei_ing ON ei_ing.legal_unit_id = lu_ing.id
JOIN public.external_ident_type AS eit_ing ON eit_ing.id = ei_ing.type_id AND eit_ing.code = 'tax_ident'
JOIN public.legal_unit AS lu_ed ON lu_ed.id = lr.influenced_id
JOIN public.external_ident AS ei_ed ON ei_ed.legal_unit_id = lu_ed.id
JOIN public.external_ident_type AS eit_ed ON eit_ed.id = ei_ed.type_id AND eit_ed.code = 'tax_ident'
JOIN public.legal_rel_type AS lrt ON lrt.id = lr.type_id
ORDER BY ei_ing.ident, ei_ed.ident;

-- ============================================================================
\echo "=== Phase 3: Derive Power Groups ==="
-- ============================================================================

-- Derive power groups directly (skipping full analytics pipeline for speed)
SELECT worker.derive_power_groups();

\echo "Power groups created (only from HFOR/primary_influencer_only=TRUE):"
SELECT pg.ident, pg.name
FROM public.power_group AS pg
ORDER BY pg.ident;

\echo "Power group membership (which LUs belong to which group):"
SELECT
    pgm.power_group_ident,
    ei.ident AS tax_ident,
    lu.name AS legal_unit_name
FROM public.power_group_membership AS pgm
JOIN public.legal_unit AS lu ON lu.id = pgm.legal_unit_id
JOIN public.external_ident AS ei ON ei.legal_unit_id = lu.id
JOIN public.external_ident_type AS eit ON eit.id = ei.type_id AND eit.code = 'tax_ident'
ORDER BY pgm.power_group_ident, ei.ident;

\echo "Legal relationship clusters (connected components by root LU):"
SELECT
    ei_root.ident AS root_tax_ident,
    COUNT(lrc.legal_relationship_id) AS relationship_count
FROM public.legal_relationship_cluster AS lrc
JOIN public.external_ident AS ei_root ON ei_root.legal_unit_id = lrc.root_legal_unit_id
JOIN public.external_ident_type AS eit_root ON eit_root.id = ei_root.type_id AND eit_root.code = 'tax_ident'
GROUP BY ei_root.ident
ORDER BY ei_root.ident;

\echo "Legal relationships with power_group_id assigned:"
SELECT
    ei_ing.ident AS influencing,
    ei_ed.ident AS influenced,
    lrt.code AS rel_type,
    lr.primary_influencer_only,
    pg.ident AS power_group_ident
FROM public.legal_relationship AS lr
JOIN public.legal_unit AS lu_ing ON lu_ing.id = lr.influencing_id
JOIN public.external_ident AS ei_ing ON ei_ing.legal_unit_id = lu_ing.id
JOIN public.external_ident_type AS eit_ing ON eit_ing.id = ei_ing.type_id AND eit_ing.code = 'tax_ident'
JOIN public.legal_unit AS lu_ed ON lu_ed.id = lr.influenced_id
JOIN public.external_ident AS ei_ed ON ei_ed.legal_unit_id = lu_ed.id
JOIN public.external_ident_type AS eit_ed ON eit_ed.id = ei_ed.type_id AND eit_ed.code = 'tax_ident'
JOIN public.legal_rel_type AS lrt ON lrt.id = lr.type_id
LEFT JOIN public.power_group AS pg ON pg.id = lr.power_group_id
ORDER BY ei_ing.ident, ei_ed.ident;

-- ============================================================================
\echo "=== Phase 4: Summary ==="
-- ============================================================================
\echo "Nordic hierarchy (HFOR, primary_influencer_only=TRUE) forms PG0001"
\echo "Baltic hierarchy (DTPR, primary_influencer_only=FALSE) has no power group"

SELECT COUNT(*) AS total_power_groups FROM public.power_group;
SELECT COUNT(*) AS total_relationships FROM public.legal_relationship;
SELECT COUNT(*) AS total_memberships FROM public.power_group_membership;

ROLLBACK;
