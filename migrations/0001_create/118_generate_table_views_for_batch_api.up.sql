SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.enterprise_group_type');
SET LOCAL client_min_messages TO INFO;

\copy public.enterprise_group_type_system(code, name) FROM 'dbseed/enterprise_group_type.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);


SET LOCAL client_min_messages TO NOTICE;
SELECT admin.generate_table_views_for_batch_api('public.enterprise_group_role');
SET LOCAL client_min_messages TO INFO;

\copy public.enterprise_group_role_system(code, name) FROM 'dbseed/enterprise_group_role.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);