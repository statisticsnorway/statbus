-- Create Import Job for Legal Units (Demo CSV)
INSERT INTO public.import_job (definition_id, slug, description, note, user_id, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_job_provided'),
    'import_demo_lu_current',
    'Import Demo Legal Units (Current Time Context)',
    'Import job for app/public/demo/legal_units_demo.csv.',
    (select id from public.user where email = :'USER_EMAIL'),
    'r_year_curr'
ON CONFLICT (slug) DO NOTHING;

-- Create Import Job for Formal Establishments (Demo CSV)
INSERT INTO public.import_job (definition_id, slug, description, note, user_id, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_job_provided'),
    'import_demo_es_for_lu_current',
    'Import Demo Formal Establishments (Current Time Context)',
    'Import job for app/public/demo/formal_establishments_units_demo.csv.',
    (select id from public.user where email = :'USER_EMAIL'),
    'r_year_curr'
ON CONFLICT (slug) DO NOTHING;

-- Create Import Job for Informal Establishments (Demo CSV)
INSERT INTO public.import_job (definition_id, slug, description, note, user_id, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_job_provided'),
    'import_demo_es_without_lu_current',
    'Import Demo Informal Establishments (Current Time Context)',
    'Import job for app/public/demo/informal_establishments_units_demo.csv.',
    (select id from public.user where email = :'USER_EMAIL'),
    'r_year_curr'
ON CONFLICT (slug) DO NOTHING;

-- Create Import Job for Legal Relationships (Demo CSV)
INSERT INTO public.import_job (definition_id, slug, description, note, user_id, time_context_ident)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_relationship_job_provided'),
    'import_demo_lr_current',
    'Import Demo Legal Relationships (Current Time Context)',
    'Import job for app/public/demo/legal_relationships_demo.csv.',
    (select id from public.user where email = :'USER_EMAIL'),
    'r_year_curr'
ON CONFLICT (slug) DO NOTHING;
