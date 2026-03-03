BEGIN;

-- Drop validation triggers and function
DROP TRIGGER IF EXISTS power_root_validate_membership_on_update ON public.power_root;
DROP TRIGGER IF EXISTS power_root_validate_membership_on_insert ON public.power_root;
DROP FUNCTION IF EXISTS public.power_root_validate_root_membership();

-- Drop temporal FKs
SELECT sql_saga.drop_foreign_key(
    table_oid => 'public.power_root'::regclass,
    column_names => ARRAY['custom_root_legal_unit_id']
);
SELECT sql_saga.drop_foreign_key(
    table_oid => 'public.power_root'::regclass,
    column_names => ARRAY['derived_root_legal_unit_id']
);

-- Drop supporting index
DROP INDEX IF EXISTS public.ix_legal_relationship_power_group_influencing;

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
