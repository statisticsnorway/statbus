SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.reorg_type');
SET LOCAL client_min_messages TO INFO;

\copy public.reorg_type_system(code, name, description) FROM 'dbseed/reorg_type.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);