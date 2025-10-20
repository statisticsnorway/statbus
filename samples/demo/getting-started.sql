-- Set the activity category standard to ISIC v4 for the demo data.
\echo "User selected the Activity Category Standard"
INSERT INTO settings(activity_category_standard_id,country_id)
SELECT (SELECT id FROM activity_category_standard WHERE code = 'isic_v4')
     , (SELECT id FROM public.country WHERE iso_2 = 'UN')
ON CONFLICT (only_one_setting)
DO UPDATE SET
    activity_category_standard_id = EXCLUDED.activity_category_standard_id,
    country_id = EXCLUDED.country_id;

\echo "User uploads the demo activity categories"
\copy public.activity_category_available_custom(path,name) FROM 'app/public/demo/activity_custom_isic_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "User uploads the demo regions"
\copy public.region_upload(path, name) FROM 'app/public/demo/regions_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "User uploads the demo sectors"
\copy public.sector_custom_only(path,name,description) FROM 'app/public/demo/sectors_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

\echo "User uploads the demo legal forms"
\copy public.legal_form_custom_only(code,name) FROM 'app/public/demo/legal_forms_demo.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

-- The demo data uses data sources that are part of the core database seed.
-- This file is included for structural consistency with other sample data sets.


