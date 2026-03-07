-- Create Import Job for Legal Units (Demo CSV with source dates)
INSERT INTO public.import_job (definition_id, slug, description, note, user_id)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_unit_source_dates'),
    'import_demo_lu_wsd',
    'Import Demo Legal Units (With Source Dates)',
    'Import job for app/public/demo/legal_units_with_source_dates_demo.csv.',
    (select id from public.user where email = :'USER_EMAIL')
ON CONFLICT (slug) DO NOTHING;

-- Create Import Job for Formal Establishments (Demo CSV with source dates)
INSERT INTO public.import_job (definition_id, slug, description, note, user_id)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_for_lu_source_dates'),
    'import_demo_es_for_lu_wsd',
    'Import Demo Formal Establishments (With Source Dates)',
    'Import job for app/public/demo/formal_establishments_units_with_source_dates_demo.csv.',
    (select id from public.user where email = :'USER_EMAIL')
ON CONFLICT (slug) DO NOTHING;

-- Create Import Job for Informal Establishments (Demo CSV with source dates)
INSERT INTO public.import_job (definition_id, slug, description, note, user_id)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'establishment_without_lu_source_dates'),
    'import_demo_es_without_lu_wsd',
    'Import Demo Informal Establishments (With Source Dates)',
    'Import job for app/public/demo/informal_establishments_units_with_source_dates_demo.csv.',
    (select id from public.user where email = :'USER_EMAIL')
ON CONFLICT (slug) DO NOTHING;

-- Create Import Job for Legal Relationships (Demo CSV with source dates)
INSERT INTO public.import_job (definition_id, slug, description, note, user_id)
SELECT
    (SELECT id FROM public.import_definition WHERE slug = 'legal_relationship_source_dates'),
    'import_demo_lr_wsd',
    'Import Demo Legal Relationships (With Source Dates)',
    'Import job for app/public/demo/legal_relationships_with_source_dates_demo.csv.',
    (select id from public.user where email = :'USER_EMAIL')
ON CONFLICT (slug) DO NOTHING;
