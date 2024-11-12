-- Load seed data after all constraints are in place
SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.sector');
SET LOCAL client_min_messages TO INFO;

\copy public.sector_system(path, name) FROM 'dbseed/sector.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);