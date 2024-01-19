
INSERT INTO settings(activity_category_standard_id,only_one_setting)
  SELECT id, true
  FROM activity_category_standard
  WHERE code = 'nace_v2.1';

\i samples/norway-sample-regions.sql
\i samples/100BREGUnits.sql
