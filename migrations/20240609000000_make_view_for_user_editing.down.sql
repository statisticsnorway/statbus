-- Down Migration: Make view for user editing
BEGIN;

-- Drop functions and procedures first, respecting dependencies
DROP FUNCTION public.user_create(text, public.statbus_role, text);
DROP PROCEDURE test.set_user_from_email(text);

-- Drop test schema
-- REVOKE USAGE is implicitly handled by DROP SCHEMA CASCADE
DROP SCHEMA test CASCADE;

-- Drop the view
DROP VIEW public.user;

END;
