-- Migration: Add power group worker infrastructure
-- Purpose: Create views and worker commands for deriving power group hierarchies
-- power_group is TIMELESS (like enterprise) - legal_relationship.power_group_id links relationships to groups
-- Active status is derived at query time from legal_relationship.valid_range

BEGIN;

--------------------------------------------------------------------------------
-- PART 1: Recursive CTE view for hierarchy traversal
-- Traverses temporal legal_relationship to find controlling ownership hierarchies
--------------------------------------------------------------------------------

CREATE VIEW public.legal_unit_power_hierarchy WITH (security_invoker = on) AS
WITH RECURSIVE hierarchy AS (
    -- Base case: Root legal units (those that have controlling children but no controlling parent)
    SELECT 
        lu.id AS legal_unit_id,
        lu.valid_range,
        lu.id AS root_legal_unit_id,
        1 AS power_level,
        ARRAY[lu.id] AS path,
        FALSE AS is_cycle
    FROM public.legal_unit AS lu
    WHERE EXISTS (
        -- Has at least one primary-influencer child
        SELECT 1
        FROM public.legal_relationship AS lr
        WHERE lr.influencing_id = lu.id
          AND lr.primary_influencer_only IS TRUE
          AND lr.valid_range && lu.valid_range
    )
    AND NOT EXISTS (
        -- Does NOT have a primary-influencer parent
        SELECT 1
        FROM public.legal_relationship AS lr
        WHERE lr.influenced_id = lu.id
          AND lr.primary_influencer_only IS TRUE
          AND lr.valid_range && lu.valid_range
    )
    
    UNION ALL
    
    -- Recursive case: Children of legal units already in the hierarchy
    SELECT 
        influenced_lu.id AS legal_unit_id,
        influenced_lu.valid_range * lr.valid_range * h.valid_range AS valid_range,
        h.root_legal_unit_id,
        h.power_level + 1 AS power_level,
        h.path || influenced_lu.id AS path,
        influenced_lu.id = ANY(h.path) AS is_cycle
    FROM hierarchy AS h
    JOIN public.legal_relationship AS lr
        ON lr.influencing_id = h.legal_unit_id
        AND lr.valid_range && h.valid_range
        AND lr.primary_influencer_only IS TRUE
    JOIN public.legal_unit AS influenced_lu 
        ON influenced_lu.id = lr.influenced_id
        AND influenced_lu.valid_range && lr.valid_range
    WHERE NOT h.is_cycle
      AND h.power_level < 100
)
SELECT 
    legal_unit_id,
    valid_range,
    root_legal_unit_id,
    power_level,
    path,
    is_cycle
FROM hierarchy
WHERE NOT is_cycle;

COMMENT ON VIEW public.legal_unit_power_hierarchy IS
    'Recursive view showing power hierarchy traversal from root legal units down through primary_influencer_only relationships';

--------------------------------------------------------------------------------
-- PART 2: Power group definition view (computes derived metrics)
-- Groups by root_legal_unit_id to define what power groups should exist
--------------------------------------------------------------------------------

CREATE VIEW public.power_group_def WITH (security_invoker = on) AS
SELECT 
    root_legal_unit_id,
    MAX(power_level) - 1 AS depth,  -- Longest path from root (0 for single root)
    COUNT(*) FILTER (WHERE power_level = 2) AS width,  -- Direct children count
    COUNT(*) - 1 AS reach  -- Total controlled units (excluding root)
FROM public.legal_unit_power_hierarchy
GROUP BY root_legal_unit_id;

COMMENT ON VIEW public.power_group_def IS 
    'Defines power groups based on hierarchy traversal, computing depth/width/reach metrics. One row per root legal unit.';

--------------------------------------------------------------------------------
-- PART 3: View to identify relationship clusters
-- Each cluster of connected relationships forms a power group
--------------------------------------------------------------------------------

CREATE VIEW public.legal_relationship_cluster WITH (security_invoker = on) AS
WITH hierarchy_relationships AS (
    -- Get all relationships that are part of a controlling hierarchy
    SELECT DISTINCT
        lr.id AS legal_relationship_id,
        lph.root_legal_unit_id
    FROM public.legal_relationship AS lr
    JOIN public.legal_unit_power_hierarchy AS lph
        ON (lr.influencing_id = lph.legal_unit_id OR lr.influenced_id = lph.legal_unit_id)
        AND lr.valid_range && lph.valid_range
    WHERE lr.primary_influencer_only IS TRUE  -- Only primary-influencer relationships form power groups
)
SELECT 
    legal_relationship_id,
    root_legal_unit_id
FROM hierarchy_relationships;

COMMENT ON VIEW public.legal_relationship_cluster IS 
    'Maps each controlling legal_relationship to its cluster root (for power_group assignment)';

--------------------------------------------------------------------------------
-- PART 4: Worker infrastructure
--------------------------------------------------------------------------------

-- Deduplication index for pending tasks
CREATE UNIQUE INDEX idx_tasks_derive_power_groups_dedup
ON worker.tasks (command)
WHERE command = 'derive_power_groups' AND state = 'pending'::worker.task_state;

-- Core function: creates/updates power_group records AND updates legal_relationship.power_group_id
CREATE FUNCTION worker.derive_power_groups()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $derive_power_groups$
DECLARE
    _cluster RECORD;
    _power_group power_group;
    _created_count integer := 0;
    _updated_count integer := 0;
    _linked_count integer := 0;
    _row_count integer;
    _current_user_id integer;
BEGIN
    RAISE DEBUG '[derive_power_groups] Starting power group derivation';

    -- Disable the trigger that re-enqueues derive_power_groups when we update legal_relationship.power_group_id
    -- Without this, every UPDATE below fires the trigger → enqueues a new task → infinite loop
    ALTER TABLE public.legal_relationship DISABLE TRIGGER legal_relationship_derive_power_groups_trigger;

    -- Find a user for edit tracking
    SELECT id INTO _current_user_id 
    FROM auth.user 
    WHERE email = session_user 
       OR session_user = 'postgres';
    
    IF _current_user_id IS NULL THEN
        SELECT id INTO _current_user_id 
        FROM auth.user 
        WHERE role_id = (SELECT id FROM auth.role WHERE name = 'super_user')
        LIMIT 1;
    END IF;
    
    IF _current_user_id IS NULL THEN
        RAISE EXCEPTION 'No user found for power group derivation';
    END IF;
    
    -- Step 1: For each cluster (identified by root_legal_unit_id), find or create power_group
    -- and assign to relationships
    FOR _cluster IN 
        SELECT DISTINCT root_legal_unit_id
        FROM public.legal_relationship_cluster
    LOOP
        -- Check if any relationship in this cluster already has a power_group assigned
        SELECT pg.* INTO _power_group
        FROM public.power_group AS pg
        JOIN public.legal_relationship AS lr ON lr.power_group_id = pg.id
        JOIN public.legal_relationship_cluster AS lrc ON lrc.legal_relationship_id = lr.id
        WHERE lrc.root_legal_unit_id = _cluster.root_legal_unit_id
        LIMIT 1;
        
        IF NOT FOUND THEN
            -- Create new power_group for this cluster
            INSERT INTO public.power_group (
                edit_by_user_id
            ) VALUES (
                _current_user_id
            )
            RETURNING * INTO _power_group;
            
            _created_count := _created_count + 1;
            RAISE DEBUG '[derive_power_groups] Created power_group % for root LU %', 
                _power_group.ident, _cluster.root_legal_unit_id;
        ELSE
            _updated_count := _updated_count + 1;
        END IF;
        
        -- Step 2: Assign power_group_id to all relationships in this cluster
        UPDATE public.legal_relationship AS lr
        SET power_group_id = _power_group.id
        FROM public.legal_relationship_cluster AS lrc
        WHERE lr.id = lrc.legal_relationship_id
          AND lrc.root_legal_unit_id = _cluster.root_legal_unit_id
          AND (lr.power_group_id IS DISTINCT FROM _power_group.id);
        
        GET DIAGNOSTICS _row_count = ROW_COUNT;
        _linked_count := _linked_count + _row_count;
    END LOOP;
    
    -- Step 3: Handle cluster merges - when one cluster acquires another
    -- Find relationships where power_group differs from what the cluster says
    -- Use the "larger" power_group (more relationships) as the survivor
    WITH cluster_sizes AS (
        SELECT 
            lr.power_group_id,
            COUNT(*) AS rel_count
        FROM public.legal_relationship AS lr
        WHERE lr.power_group_id IS NOT NULL
        GROUP BY lr.power_group_id
    ),
    merge_candidates AS (
        SELECT DISTINCT
            lrc.root_legal_unit_id,
            lr.power_group_id AS current_pg_id,
            cs.rel_count
        FROM public.legal_relationship_cluster AS lrc
        JOIN public.legal_relationship AS lr ON lr.id = lrc.legal_relationship_id
        JOIN cluster_sizes AS cs ON cs.power_group_id = lr.power_group_id
        WHERE lr.power_group_id IS NOT NULL
    ),
    clusters_with_multiple_pgs AS (
        SELECT 
            root_legal_unit_id,
            array_agg(current_pg_id ORDER BY rel_count DESC, current_pg_id) AS pg_ids
        FROM merge_candidates
        GROUP BY root_legal_unit_id
        HAVING COUNT(DISTINCT current_pg_id) > 1
    )
    -- For each cluster with multiple power_groups, update all relationships to use the "biggest" one
    UPDATE public.legal_relationship AS lr
    SET power_group_id = cwmp.pg_ids[1]  -- First element is the one with most relationships
    FROM public.legal_relationship_cluster AS lrc
    JOIN clusters_with_multiple_pgs AS cwmp ON cwmp.root_legal_unit_id = lrc.root_legal_unit_id
    WHERE lr.id = lrc.legal_relationship_id
      AND lr.power_group_id != cwmp.pg_ids[1];
    
    GET DIAGNOSTICS _row_count = ROW_COUNT;
    IF _row_count > 0 THEN
        RAISE DEBUG '[derive_power_groups] Merged % relationships into surviving power groups', _row_count;
    END IF;
    
    -- Step 4: Clear power_group_id from relationships that are not primary-influencer
    UPDATE public.legal_relationship AS lr
    SET power_group_id = NULL
    WHERE lr.power_group_id IS NOT NULL
      AND lr.primary_influencer_only IS NOT TRUE;
    
    GET DIAGNOSTICS _row_count = ROW_COUNT;
    IF _row_count > 0 THEN
        RAISE DEBUG '[derive_power_groups] Cleared power_group from % non-primary-influencer relationships', _row_count;
    END IF;
    
    RAISE DEBUG '[derive_power_groups] Completed: created=%, updated=%, linked=%',
        _created_count, _updated_count, _linked_count;

    -- Re-enable the trigger so future DML on legal_relationship queues derivation normally
    ALTER TABLE public.legal_relationship ENABLE TRIGGER legal_relationship_derive_power_groups_trigger;
END;
$derive_power_groups$;

COMMENT ON FUNCTION worker.derive_power_groups() IS 
    'Derives power_group records and updates legal_relationship.power_group_id based on ownership hierarchies';

-- Command handler procedure (wrapper for worker system)
CREATE PROCEDURE worker.derive_power_groups(payload JSONB)
SECURITY DEFINER
SET search_path = public, worker, pg_temp
LANGUAGE plpgsql
AS $procedure$
BEGIN
    PERFORM worker.derive_power_groups();
END;
$procedure$;

-- Enqueue function with deduplication
CREATE FUNCTION worker.enqueue_derive_power_groups()
RETURNS BIGINT
LANGUAGE plpgsql
AS $enqueue_derive_power_groups$
DECLARE
    _task_id BIGINT;
    _payload JSONB;
BEGIN
    _payload := jsonb_build_object('command', 'derive_power_groups');
    
    INSERT INTO worker.tasks AS t (command, payload)
    VALUES ('derive_power_groups', _payload)
    ON CONFLICT (command)
    WHERE command = 'derive_power_groups' AND state = 'pending'::worker.task_state
    DO UPDATE SET
        state = 'pending'::worker.task_state,
        priority = EXCLUDED.priority,
        processed_at = NULL,
        error = NULL
    RETURNING id INTO _task_id;
    
    PERFORM pg_notify('worker_tasks', 'analytics');
    
    RETURN _task_id;
END;
$enqueue_derive_power_groups$;

COMMENT ON FUNCTION worker.enqueue_derive_power_groups() IS 
    'Enqueues a task to derive power groups from legal_relationship data';

-- Register command in worker system
INSERT INTO worker.command_registry (queue, command, handler_procedure, description)
VALUES (
    'analytics',
    'derive_power_groups',
    'worker.derive_power_groups',
    'Derive power_group records and assign to legal_relationships based on ownership hierarchies'
);

--------------------------------------------------------------------------------
-- PART 5: Trigger to queue derivation on legal_relationship changes
--------------------------------------------------------------------------------

CREATE FUNCTION public.legal_relationship_queue_derive_power_groups()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, worker, pg_temp
AS $legal_relationship_queue_derive_power_groups$
BEGIN
    PERFORM worker.enqueue_derive_power_groups();
    RETURN NULL;
END;
$legal_relationship_queue_derive_power_groups$;

CREATE TRIGGER legal_relationship_derive_power_groups_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.legal_relationship
FOR EACH STATEMENT
EXECUTE FUNCTION public.legal_relationship_queue_derive_power_groups();

--------------------------------------------------------------------------------
-- PART 6: Helper view for querying "active" power groups
-- A power group is "active" at a given time if any of its relationships
-- have a valid_range containing that time
--------------------------------------------------------------------------------

CREATE VIEW public.power_group_active WITH (security_invoker = on) AS
SELECT DISTINCT
    pg.id,
    pg.ident,
    pg.short_name,
    pg.name,
    pg.type_id
FROM public.power_group AS pg
JOIN public.legal_relationship AS lr ON lr.power_group_id = pg.id
WHERE lr.valid_range @> CURRENT_DATE;

COMMENT ON VIEW public.power_group_active IS 
    'Power groups that are currently active (have at least one relationship with valid_range containing today)';

--------------------------------------------------------------------------------
-- PART 7: Helper view for power group membership (which LUs belong to which PG)
--------------------------------------------------------------------------------

CREATE VIEW public.power_group_membership WITH (security_invoker = on) AS
SELECT DISTINCT
    pg.id AS power_group_id,
    pg.ident AS power_group_ident,
    lu.id AS legal_unit_id,
    lph.power_level,
    lph.valid_range
FROM public.power_group AS pg
JOIN public.legal_relationship AS lr ON lr.power_group_id = pg.id
JOIN public.legal_unit_power_hierarchy AS lph 
    ON (lr.influencing_id = lph.legal_unit_id OR lr.influenced_id = lph.legal_unit_id)
    AND lr.valid_range && lph.valid_range
JOIN public.legal_unit AS lu ON lu.id = lph.legal_unit_id;

COMMENT ON VIEW public.power_group_membership IS 
    'Maps legal units to their power groups with hierarchy level information';

--------------------------------------------------------------------------------
-- PART 8: Grant permissions
--------------------------------------------------------------------------------

-- Views: SELECT for authenticated, regular_user, admin_user
-- These are read-only aggregation views (not auto-updatable), so only SELECT is needed.
GRANT SELECT ON public.legal_unit_power_hierarchy TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.power_group_def TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.legal_relationship_cluster TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.power_group_active TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.power_group_membership TO authenticated, regular_user, admin_user;

-- Tables
GRANT SELECT ON public.legal_relationship TO authenticated;
GRANT SELECT ON public.power_group TO authenticated;
GRANT EXECUTE ON FUNCTION worker.enqueue_derive_power_groups() TO authenticated;

END;
