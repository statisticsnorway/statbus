SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.foreign_participation');
SET LOCAL client_min_messages TO INFO;

\copy public.foreign_participation_system(code, name) FROM 'dbseed/foreign_participation.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);