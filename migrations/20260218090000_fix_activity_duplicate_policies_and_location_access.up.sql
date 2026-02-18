BEGIN;

-- Drop 2 redundant policies on activity table.
-- These were created by migration 20240606000000 but are duplicates of the
-- auto-generated policies from 20240603000000 (activity_admin_user_manage,
-- activity_regular_user_manage).
DROP POLICY admin_user_activity_access ON public.activity;
DROP POLICY regular_user_activity_access ON public.activity;

-- Fix security bug in restricted_user_location_access policy.
-- The original policy had `ra.region_id = region_id` which resolves to
-- `ra.region_id = ra.region_id` (always true for non-NULL) since both
-- region_access and location have a region_id column. This means restricted
-- users could access ALL locations, not just their assigned regions.
DROP POLICY restricted_user_location_access ON public.location;
CREATE POLICY restricted_user_location_access ON public.location FOR ALL TO restricted_user
USING (EXISTS (
    SELECT 1 FROM public.region_access AS ra
    WHERE ra.user_id = auth.uid() AND ra.region_id = location.region_id
))
WITH CHECK (EXISTS (
    SELECT 1 FROM public.region_access AS ra
    WHERE ra.user_id = auth.uid() AND ra.region_id = location.region_id
));

END;
