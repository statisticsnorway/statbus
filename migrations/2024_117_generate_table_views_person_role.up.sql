BEGIN;

SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.person_role');
SET LOCAL client_min_messages TO INFO;

\copy public.person_role_system(code, name) FROM 'dbseed/person_role.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);

END;