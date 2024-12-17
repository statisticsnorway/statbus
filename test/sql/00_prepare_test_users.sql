BEGIN;

-- Insert users for other tests.

SELECT * FROM public.statbus_user_create('test.super@statbus.org', 'super_user'::statbus_role_type, 'Super#123!');
SELECT * FROM public.statbus_user_create('test.regular@statbus.org', 'regular_user'::statbus_role_type, 'Regular#123!');
SELECT * FROM public.statbus_user_create('test.restricted@statbus.org', 'restricted_user'::statbus_role_type, 'Restricted#123!');

CALL test.set_user_from_email('test.regular@statbus.org');

END;
