-- While the datestyle is set for the database, the pg_regress tool sets the MDY format
-- to ensure consistent date formatting, so we must manually override this
SET datestyle TO 'ISO, DMY';

\if :{?DEBUG}
SET client_min_messages TO debug1;
\else
SET client_min_messages TO NOTICE;
\endif

\echo Add users for testing purposes
SELECT * FROM public.statbus_user_create('test.super@statbus.org', 'super_user'::statbus_role_type, 'Super#123!');
SELECT * FROM public.statbus_user_create('test.regular@statbus.org', 'regular_user'::statbus_role_type, 'Regular#123!');
SELECT * FROM public.statbus_user_create('test.restricted@statbus.org', 'restricted_user'::statbus_role_type, 'Restricted#123!');
