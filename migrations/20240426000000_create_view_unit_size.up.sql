BEGIN;

SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.unit_size');
SET LOCAL client_min_messages TO INFO;

\copy public.unit_size_system(code, name) FROM 'dbseed/unit_size.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

END;