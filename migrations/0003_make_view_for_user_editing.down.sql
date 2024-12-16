-- Down Migration 0003: Make view for user editing
BEGIN;

-- Drop the unique constraint
ALTER TABLE auth.users DROP CONSTRAINT IF EXISTS users_email_key;

-- Drop view and associated trigger first
DROP VIEW IF EXISTS statbus_user_with_email_and_role;
DROP FUNCTION IF EXISTS trigger_update_statbus_user_with_email_and_role();

-- Drop helper functions
DROP FUNCTION IF EXISTS public.statbus_user_update_role(text, statbus_role_type);
REVOKE USAGE ON SCHEMA test FROM authenticated;
DROP SCHEMA IF EXISTS test CASCADE;
DROP FUNCTION IF EXISTS auth.check_is_system_account();
DROP FUNCTION IF EXISTS auth.check_is_super_user();
DROP FUNCTION IF EXISTS auth.assert_is_super_user_or_system_account();
DROP FUNCTION IF EXISTS public.statbus_user_create(text, statbus_role_type, text);

END;
