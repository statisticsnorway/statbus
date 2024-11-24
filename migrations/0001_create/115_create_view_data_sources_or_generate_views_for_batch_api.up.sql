BEGIN;

SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.data_source');
SET LOCAL client_min_messages TO INFO;

\copy public.data_source_system(code, name) FROM 'dbseed/data_source.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

END;