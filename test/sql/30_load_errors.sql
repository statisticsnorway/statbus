BEGIN;
\echo "Setting up Statbus to load establishments without legal units"
\echo "User selected the Activity Category Standard"
INSERT INTO settings(activity_category_standard_id,only_one_setting)
SELECT id, true FROM activity_category_standard WHERE code = 'nace_v2.1'
ON CONFLICT (only_one_setting)
DO UPDATE SET
   activity_category_standard_id =(SELECT id FROM activity_category_standard WHERE code = 'nace_v2.1')
   WHERE settings.id = EXCLUDED.id;
;
SELECT acs.code
  FROM public.settings AS s
  JOIN activity_category_standard AS acs
    ON s.activity_category_standard_id = acs.id;

--\echo "User uploads the sample activity categories"
--\copy public.activity_category_available_custom(path,name,description) FROM 'app/public/activity_category_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
--SELECT count(*) FROM public.activity_category_available;

--\echo "User uploads the sample regions"
--\copy public.region_upload(path, name) FROM 'app/public/norway-regions-2024.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
--SELECT count(*) FROM public.region;

--\echo "User uploads the sample legal forms"
--\copy public.legal_form_custom_only(code,name) FROM 'app/public/legal_form_norway.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
--SELECT count(*) FROM public.legal_form_available;

--\d public.sector_custom_only
--\sf admin.sector_custom_only_upsert

\echo "User uploads the sample sectors"
\copy public.sector_custom_only(path,name,description) FROM 'test/data/30_ug_sectorcodes_with_index_error.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

ROLLBACK;