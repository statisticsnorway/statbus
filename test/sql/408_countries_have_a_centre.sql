-- z2qt08: every shipped country has a centre where the Regions map's world level draws
-- it, from dbseed/country/country_centres.csv: the United Nations, a demo installation's
-- country, at 0,0 and the US Minor Outlying Islands at Wake Island. A centre is a latitude and a
-- longitude together.
BEGIN;

\i test/setup.sql

\echo "Countries with and without a centre"
SELECT count(*) AS countries,
       count(latitude) AS with_centre,
       string_agg(iso_2, ',' ORDER BY iso_2) FILTER (WHERE latitude IS NULL) AS without_centre
FROM public.country;

\echo "Some centres, as shipped"
SELECT iso_2, latitude, longitude
FROM public.country
WHERE iso_2 IN ('NO', 'SE', 'FJ', 'SS', 'MA', 'UG', 'UN', 'UM')
ORDER BY iso_2;

\echo "A centre is a latitude and a longitude together"
-- Terse errors name the constraint that refuses the row; the row itself carries timestamps of
-- when the seed was built.
\set VERBOSITY terse
SAVEPOINT half;
UPDATE public.country SET longitude = NULL WHERE iso_2 = 'NO';
ROLLBACK TO SAVEPOINT half;

\echo "A latitude is within -90 to 90 degrees"
SAVEPOINT range;
UPDATE public.country SET latitude = 91 WHERE iso_2 = 'NO';
ROLLBACK TO SAVEPOINT range;

ROLLBACK;
