SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.legal_form');
SET LOCAL client_min_messages TO INFO;

\copy public.legal_form_system(code, name) FROM 'dbseed/legal_form.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);