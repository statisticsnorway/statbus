INSERT INTO settings(activity_category_standard_id,country_id,region_version_id)
SELECT (SELECT id FROM activity_category_standard WHERE code = 'nace_v2.1')
     , (SELECT id FROM public.country WHERE iso_2 = 'NO')
     , (SELECT id FROM public.region_version WHERE code = 'initial')
ON CONFLICT (only_one_setting)
DO UPDATE SET
   activity_category_standard_id = EXCLUDED.activity_category_standard_id,
   country_id = EXCLUDED.country_id,
   region_version_id = EXCLUDED.region_version_id
   WHERE settings.only_one_setting = EXCLUDED.only_one_setting;
;
