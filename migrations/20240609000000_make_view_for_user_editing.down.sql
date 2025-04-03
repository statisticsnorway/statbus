-- Down Migration: Make view for user editing
BEGIN;

-- Drop the unique constraint
ALTER TABLE auth.user DROP CONSTRAINT user_email_key;

-- Drop view and associated trigger first
DROP VIEW public.user_with_role;
DROP FUNCTION admin.trigger_update_user_with_role();

-- Drop helper functions
DROP FUNCTION public.user_update_role(text, statbus_role);
DROP PROCEDURE test.set_user_from_email(text);
REVOKE USAGE ON SCHEMA test FROM authenticated;
DROP SCHEMA test CASCADE;
DROP FUNCTION auth.check_is_system_account();
DROP FUNCTION auth.check_is_admin_user();
DROP FUNCTION auth.assert_is_admin_user_or_system_account();
DROP FUNCTION public.user_create(text, statbus_role, text);

END;
