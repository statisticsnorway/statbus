-- Create Import Job for Legal Units with Hierarchical Census Identifier
INSERT INTO public.import_job (definition_id, slug, description, note, user_id, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_job_provided'),
    'import_hierarchical_demo_lu_current',
    'Import Hierarchical Demo Legal Units (Current Time Context)',
    'Import job for samples/hierarchical-demo/legal_units_hierarchical_demo.csv.',
    (select id from public.user where email = :'USER_EMAIL'),
    'r_year_curr'
ON CONFLICT (slug) DO NOTHING;

-- Create Import Job for Formal Establishments with Hierarchical Census Identifier
INSERT INTO public.import_job (definition_id, slug, description, note, user_id, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_job_provided'),
    'import_hierarchical_demo_es_for_lu_current',
    'Import Hierarchical Demo Formal Establishments (Current Time Context)',
    'Import job for samples/hierarchical-demo/formal_establishments_hierarchical_demo.csv.',
    (select id from public.user where email = :'USER_EMAIL'),
    'r_year_curr'
ON CONFLICT (slug) DO NOTHING;

