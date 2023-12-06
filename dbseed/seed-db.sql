BEGIN;
\copy public.region_view(path, name) FROM 'dbseed/example-norwegian-region.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);
END;
