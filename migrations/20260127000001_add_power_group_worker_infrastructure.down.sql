BEGIN;

-- Drop trigger
DROP TRIGGER IF EXISTS legal_relationship_derive_power_groups_trigger ON public.legal_relationship;
DROP FUNCTION IF EXISTS public.legal_relationship_queue_derive_power_groups();

-- Remove from command registry
DELETE FROM worker.command_registry WHERE command = 'derive_power_groups';

-- Drop worker functions
DROP FUNCTION IF EXISTS worker.enqueue_derive_power_groups();
DROP PROCEDURE IF EXISTS worker.notify_is_deriving_power_groups_stop();
DROP PROCEDURE IF EXISTS worker.notify_is_deriving_power_groups_start();
DROP PROCEDURE IF EXISTS worker.derive_power_groups(JSONB);
DROP FUNCTION IF EXISTS worker.derive_power_groups();

-- Drop deduplication index
DROP INDEX IF EXISTS worker.idx_tasks_derive_power_groups_dedup;

-- Drop views (in reverse dependency order)
DROP VIEW IF EXISTS public.power_group_membership;
DROP VIEW IF EXISTS public.power_group_active;
DROP VIEW IF EXISTS public.legal_relationship_cluster;
DROP VIEW IF EXISTS public.power_group_def;
DROP VIEW IF EXISTS public.legal_unit_power_hierarchy;

-- RLS policies are created/dropped by 20240603 migration, nothing to do here

END;
