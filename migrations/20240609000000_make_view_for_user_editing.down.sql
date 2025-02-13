-- Down Migration 0003: Make view for user editing
BEGIN;

-- Drop the unique constraint
ALTER TABLE auth.users DROP CONSTRAINT users_email_key;

-- Drop view and associated trigger first
DROP VIEW statbus_user_with_email_and_role;
DROP FUNCTION admin.trigger_update_statbus_user_with_email_and_role();

-- Drop helper functions
DROP FUNCTION public.statbus_user_update_role(text, statbus_role_type);
DROP PROCEDURE test.set_user_from_email(text);
REVOKE USAGE ON SCHEMA test FROM authenticated;
DROP SCHEMA test CASCADE;
DROP FUNCTION auth.check_is_system_account();
DROP FUNCTION auth.check_is_super_user();
DROP FUNCTION auth.assert_is_super_user_or_system_account();
DROP FUNCTION public.statbus_user_create(text, statbus_role_type, text);

END;
