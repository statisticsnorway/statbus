BEGIN;

-- Drop views (in reverse dependency order)
DROP VIEW IF EXISTS public.power_group_membership;
DROP VIEW IF EXISTS public.power_group_active;
DROP VIEW IF EXISTS public.legal_relationship_cluster;
DROP VIEW IF EXISTS public.power_group_def;
DROP VIEW IF EXISTS public.power_hierarchy;

-- Revoke table-level grants (view/function grants are implicitly revoked by DROP above)
REVOKE SELECT ON public.legal_relationship FROM authenticated;
REVOKE SELECT ON public.power_group FROM authenticated;
REVOKE SELECT ON public.power_root FROM authenticated;

-- RLS policies are created/dropped by 20240603 migration, nothing to do here

END;
