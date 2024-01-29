BEGIN;
\copy public.region_view(path, name) FROM 'samples/norway/regions/norway-regions-2023.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
END;

