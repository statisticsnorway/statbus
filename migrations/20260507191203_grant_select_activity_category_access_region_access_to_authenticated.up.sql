-- Migration 20260507191203: grant select on activity_category_access and region_access to authenticated
--
-- Bug:
--   regular_user could not UPDATE public.activity or public.location even though
--   activity_regular_user_manage and location_regular_user_manage policies say
--   "ALL TO regular_user USING (true)". The error was:
--     "permission denied for table activity_category_access"
--     "permission denied for table region_access"
--
-- Root cause:
--   regular_user inherits from restricted_user. The restricted_user_*_access
--   policies on activity and location are FOR ALL TO restricted_user with USING
--   subqueries on activity_category_access and region_access. PostgreSQL ORs
--   permissive policies and must include those subqueries in the plan for
--   regular_user, so the planner needs SELECT on the referenced access tables.
--   The original migrations (20240113 / 20240216) created RLS policies
--   `*_read_policy FOR SELECT TO authenticated USING (true)` on those tables but
--   never issued the matching table-level GRANT, so even authenticated members
--   could not pass the planner's privilege check.
--
-- Admin was unaffected because the admin policy on activity / location is
-- USING (true), letting the planner short-circuit and never reference the
-- access tables.
--
-- Fix:
--   Issue the GRANT that the existing RLS policy already implied.

GRANT SELECT ON public.activity_category_access TO authenticated;
GRANT SELECT ON public.region_access TO authenticated;
