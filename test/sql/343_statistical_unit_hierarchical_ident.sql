BEGIN;

\i test/setup.sql

\echo "Test 343: Statistical Unit View with Hierarchical Identifiers"

-- Setup user
CALL test.set_user_from_email('test.admin@statbus.org');
\i samples/norway/getting-started.sql

-- Create hierarchical identifier type
INSERT INTO public.external_ident_type (code, name, shape, labels, description, priority, archived)
VALUES ('surveyor_ident', 'Surveyor Identifier', 'hierarchical', 'region.district.seq',
        'Region/District/Sequence hierarchical composite key', 50, false);

-- Create Legal Unit with hierarchical identifier
DO $$
DECLARE
    v_user_id INT;
    v_ent_id INT;
    v_lu_id INT;
    v_type_id INT;
BEGIN
    SELECT id INTO v_user_id FROM public.user WHERE email = 'test.admin@statbus.org';
    SELECT id INTO v_type_id FROM public.external_ident_type WHERE code = 'surveyor_ident';
    
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
    VALUES ('ENT 343', v_user_id, now()) RETURNING id INTO v_ent_id;
    
    INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise, edit_by_user_id, edit_at, valid_from)
    VALUES (v_ent_id, 'LU Hierarchical 343', (SELECT id FROM public.status WHERE code = 'active'), true, v_user_id, now(), '2023-01-01') RETURNING id INTO v_lu_id;
    
    INSERT INTO public.external_ident (legal_unit_id, type_id, idents, edit_by_user_id, edit_at)
    VALUES (v_lu_id, v_type_id, 'NORTH.KAMPALA.001'::ltree, v_user_id, now());
END $$;

-- Also create a Legal Unit with REGULAR identifier to make sure it still works
DO $$
DECLARE
    v_user_id INT;
    v_ent_id INT;
    v_lu_id INT;
    v_type_id INT;
BEGIN
    SELECT id INTO v_user_id FROM public.user WHERE email = 'test.admin@statbus.org';
    SELECT id INTO v_type_id FROM public.external_ident_type WHERE code = 'tax_ident';
    
    INSERT INTO public.enterprise (short_name, edit_by_user_id, edit_at)
    VALUES ('ENT Regular 343', v_user_id, now()) RETURNING id INTO v_ent_id;
    
    INSERT INTO public.legal_unit (enterprise_id, name, status_id, primary_for_enterprise, edit_by_user_id, edit_at, valid_from)
    VALUES (v_ent_id, 'LU Regular 343', (SELECT id FROM public.status WHERE code = 'active'), true, v_user_id, now(), '2023-01-01') RETURNING id INTO v_lu_id;
    
    INSERT INTO public.external_ident (legal_unit_id, type_id, ident, edit_by_user_id, edit_at)
    VALUES (v_lu_id, v_type_id, '987654321', v_user_id, now());
END $$;

-- Refresh timeline tables and statistical_unit
CALL public.timepoints_refresh();
CALL public.timesegments_refresh();
CALL public.timeline_enterprise_refresh();
CALL public.timeline_legal_unit_refresh();
CALL public.timeline_establishment_refresh();
CALL public.statistical_unit_refresh();

\echo "Verifying external_idents in statistical_unit:"

SELECT
    unit_type,
    name,
    external_idents
FROM public.statistical_unit
WHERE name LIKE '%343%'
ORDER BY name;

ROLLBACK;
