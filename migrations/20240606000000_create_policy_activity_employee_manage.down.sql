BEGIN;

DROP POLICY IF EXISTS "regular_user_activity_access" ON public.activity;
DROP POLICY IF EXISTS "admin_user_activity_access" ON public.activity;
DROP POLICY IF EXISTS restricted_user_activity_access ON public.activity;
DROP POLICY IF EXISTS restricted_user_location_access ON public.location;

END;
