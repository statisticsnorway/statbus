BEGIN;
\copy public.region_view(path, name) FROM 'samples/norway-sample-regions.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
END;

