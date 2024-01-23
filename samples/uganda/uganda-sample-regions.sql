BEGIN;
\copy public.region_7_levels_view FROM 'samples/uganda-sample-regions.csv' WITH (FORMAT csv, DELIMITER ';', QUOTE '"', HEADER true);
END;

