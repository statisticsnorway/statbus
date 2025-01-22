BEGIN;

DROP POLICY IF EXISTS "regular_and_super_user_activity_access" ON public.activity;
DROP POLICY IF EXISTS restricted_user_activity_access ON public.activity;

END;
