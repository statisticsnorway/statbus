BEGIN;
\echo "Setting up Statbus to load establishments without legal units"
-- Only load settings and sectors from samples/norway/getting-started.sql to get lots of errors due to missing lookup information.
\i samples/norway/settings.sql
-- \i samples/norway/activity_category/activity_category_norway.sql
-- \i samples/norway/regions/norway-regions-2024.sql
-- \i samples/norway/sector/sector_norway.sql
-- \i samples/norway/legal_form/legal_form_norway.sql
-- \i samples/norway/data_source/data_source_norway.sql

SELECT acs.code
  FROM public.settings AS s
  JOIN activity_category_standard AS acs
    ON s.activity_category_standard_id = acs.id;

\d public.sector_custom_only
\sf admin.sector_custom_only_upsert

\echo "User uploads the sectors with errors"
\copy public.sector_custom_only(path,name,description) FROM 'test/data/30_ug_sectorcodes_with_index_error.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

ROLLBACK;
