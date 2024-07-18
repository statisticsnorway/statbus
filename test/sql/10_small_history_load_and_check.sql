BEGIN;

\echo "Setting up Statbus for Norway"
\i samples/norway/setup.sql

\echo "Adding tags for insert into right part of history"
\i samples/norway/small-history/add-tags.sql

\echo "Loading historical units"
\echo "TODO: Use an import job that supports column mapping."
\copy public.import_establishment_current_for_legal_unit FROM 'samples/norway/small-history/2015-enheter.csv'
\copy public.import_establishment_current_for_legal_unit FROM 'samples/norway/small-history/2016-enheter.csv'
\copy public.import_establishment_current_for_legal_unit FROM 'samples/norway/small-history/2017-enheter.csv'
\copy public.import_establishment_current_for_legal_unit FROM 'samples/norway/small-history/2018-enheter.csv'

\echo Refreshing materialized views
SELECT view_name FROM statistical_unit_refresh_now();

END;