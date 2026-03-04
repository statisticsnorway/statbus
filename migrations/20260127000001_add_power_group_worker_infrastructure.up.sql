-- Migration: Add power group worker infrastructure
-- Purpose: Create views and worker commands for deriving power group hierarchies
-- power_group is TIMELESS (like enterprise) - legal_relationship.power_group_id links relationships to groups
-- Active status is derived at query time from legal_relationship.valid_range
--
-- The power_hierarchy view uses a two-phase algorithm:
-- Phase 1: Natural roots (LUs with children but no parent) with range_agg subtraction
--          to compute exact root periods even when cycles form later
-- Phase 2: Orphan/cycle connected components — picks root via:
--          1) power_root.custom_root (NSO choice), 2) adjacent Phase 1 root, 3) MIN(id)

BEGIN;

--------------------------------------------------------------------------------
-- PART 1: Two-phase power hierarchy view
-- Phase 1: Natural roots with range_agg subtraction for exact root periods
-- Phase 2: Orphan/cycle connected components for remaining nodes
--------------------------------------------------------------------------------

CREATE VIEW public.power_hierarchy WITH (security_invoker = on) AS
WITH RECURSIVE
-- ============================================================
-- Phase 1: Natural roots with range_agg subtraction
-- ============================================================

-- Step 1a: Compute exact root periods per LU using multirange subtraction
-- A LU is a natural root for periods where it has children but no parent
root_periods AS (
    SELECT lu.id AS legal_unit_id,
        datemultirange(lu.valid_range) - COALESCE(
            (SELECT range_agg(lr.valid_range)
             FROM public.legal_relationship AS lr
             WHERE lr.influenced_id = lu.id
               AND lr.valid_range && lu.valid_range),
            '{}'::datemultirange
        ) AS root_multirange
    FROM public.legal_unit AS lu
    WHERE EXISTS (
        SELECT 1 FROM public.legal_relationship AS lr
        WHERE lr.influencing_id = lu.id
          AND lr.valid_range && lu.valid_range
    )
),
-- Step 1b: Unnest multirange to individual daterange periods
root_base AS (
    SELECT rp.legal_unit_id,
           period AS valid_range,
           rp.legal_unit_id AS root_legal_unit_id,
           1 AS power_level,
           ARRAY[rp.legal_unit_id] AS path,
           FALSE AS is_cycle
    FROM root_periods AS rp,
    LATERAL unnest(rp.root_multirange) AS period
    WHERE NOT isempty(rp.root_multirange)
),
-- Step 1c: Recursive traversal downward from natural roots
phase1_hierarchy AS (
    SELECT * FROM root_base

    UNION ALL

    SELECT
        influenced_lu.id AS legal_unit_id,
        influenced_lu.valid_range * lr.valid_range * h.valid_range AS valid_range,
        h.root_legal_unit_id,
        h.power_level + 1 AS power_level,
        h.path || influenced_lu.id AS path,
        influenced_lu.id = ANY(h.path) AS is_cycle
    FROM phase1_hierarchy AS h
    JOIN public.legal_relationship AS lr
        ON lr.influencing_id = h.legal_unit_id
        AND lr.valid_range && h.valid_range
    JOIN public.legal_unit AS influenced_lu
        ON influenced_lu.id = lr.influenced_id
        AND influenced_lu.valid_range && lr.valid_range
    WHERE NOT h.is_cycle
      AND h.power_level < 100
),
phase1 AS (
    SELECT legal_unit_id, valid_range, root_legal_unit_id, power_level, path, is_cycle
    FROM phase1_hierarchy
    WHERE NOT is_cycle
),

-- ============================================================
-- Phase 2: Orphan/cycle connected components
-- ============================================================

-- Step 2a: Find all nodes participating in relationship edges
all_relationship_nodes AS (
    SELECT lu_id, range_agg(valid_range) AS participation
    FROM (
        SELECT influencing_id AS lu_id, valid_range
        FROM public.legal_relationship
        UNION ALL
        SELECT influenced_id AS lu_id, valid_range
        FROM public.legal_relationship
    ) AS t
    GROUP BY lu_id
),
-- Step 2b: Compute orphan periods (participating in edges but not covered by Phase 1)
orphan_nodes AS (
    SELECT apn.lu_id,
        apn.participation - COALESCE(  -- participation is already datemultirange from range_agg
            (SELECT range_agg(p1.valid_range)
             FROM phase1 AS p1
             WHERE p1.legal_unit_id = apn.lu_id),
            '{}'::datemultirange
        ) AS orphan_multirange
    FROM all_relationship_nodes AS apn
),
orphan_seeds AS (
    SELECT orn.lu_id, period AS valid_range
    FROM orphan_nodes AS orn,
    LATERAL unnest(orn.orphan_multirange) AS period
    WHERE NOT isempty(orn.orphan_multirange)
),
-- Step 2c: Bidirectional flood fill to find connected components
-- Each node tracks the minimum id seen, which identifies the component
orphan_flood AS (
    SELECT lu_id AS node_id, lu_id AS min_id, valid_range, ARRAY[lu_id] AS path
    FROM orphan_seeds

    UNION ALL

    SELECT neighbors.neighbor_id,
           LEAST(ofl.min_id, neighbors.neighbor_id),
           neighbors.lr_range * ofl.valid_range,
           ofl.path || neighbors.neighbor_id
    FROM orphan_flood AS ofl
    JOIN LATERAL (
        SELECT lr.influenced_id AS neighbor_id, lr.valid_range AS lr_range
        FROM public.legal_relationship AS lr
        WHERE lr.influencing_id = ofl.node_id
          AND lr.valid_range && ofl.valid_range
        UNION ALL
        SELECT lr.influencing_id AS neighbor_id, lr.valid_range AS lr_range
        FROM public.legal_relationship AS lr
        WHERE lr.influenced_id = ofl.node_id
          AND lr.valid_range && ofl.valid_range
    ) AS neighbors ON TRUE
    WHERE NOT (neighbors.neighbor_id = ANY(ofl.path))
      AND array_length(ofl.path, 1) < 100
),
-- Aggregate to find component membership
orphan_components AS (
    SELECT node_id, MIN(min_id) AS component_min
    FROM orphan_flood
    GROUP BY node_id
),
-- Step 2d: Effective root per component
-- Priority: 1) power_root.custom_root (NSO override), 2) adjacent Phase 1 root, 3) MIN(id) fallback
component_effective_roots AS (
    SELECT DISTINCT ON (oc.component_min, os.valid_range)
        oc.component_min,
        COALESCE(
            -- NSO override (via power_root.custom_root_legal_unit_id on existing PG)
            (SELECT pr.custom_root_legal_unit_id
             FROM public.legal_relationship AS lr
             JOIN public.power_root AS pr
                 ON pr.power_group_id = lr.power_group_id
                 AND pr.valid_range && os.valid_range
             WHERE lr.power_group_id IS NOT NULL
               AND (lr.influencing_id = oc.node_id OR lr.influenced_id = oc.node_id)
               AND lr.valid_range && os.valid_range
               AND pr.custom_root_legal_unit_id IS NOT NULL
             LIMIT 1),
            -- Adjacent Phase 1 root (temporal continuity — pick closest period)
            (SELECT p1.root_legal_unit_id
             FROM phase1 AS p1
             WHERE p1.legal_unit_id = oc.node_id
               AND p1.power_level = 1
             ORDER BY ABS(lower(p1.valid_range) - lower(os.valid_range))
             LIMIT 1),
            -- MIN(id) fallback
            oc.component_min
        ) AS effective_root,
        os.valid_range
    FROM orphan_components AS oc
    JOIN orphan_seeds AS os ON os.lu_id = oc.node_id
    ORDER BY oc.component_min, os.valid_range
),
-- Step 2e: Directed traversal from effective root
phase2_base AS (
    SELECT
        cer.effective_root AS legal_unit_id,
        (SELECT lu.valid_range FROM public.legal_unit AS lu WHERE lu.id = cer.effective_root) * cer.valid_range AS valid_range,
        cer.effective_root AS root_legal_unit_id,
        1 AS power_level,
        ARRAY[cer.effective_root] AS path,
        FALSE AS is_cycle
    FROM component_effective_roots AS cer
),
phase2_hierarchy AS (
    SELECT * FROM phase2_base

    UNION ALL

    SELECT
        influenced_lu.id AS legal_unit_id,
        influenced_lu.valid_range * lr.valid_range * h.valid_range AS valid_range,
        h.root_legal_unit_id,
        h.power_level + 1 AS power_level,
        h.path || influenced_lu.id AS path,
        influenced_lu.id = ANY(h.path) AS is_cycle
    FROM phase2_hierarchy AS h
    JOIN public.legal_relationship AS lr
        ON lr.influencing_id = h.legal_unit_id
        AND lr.valid_range && h.valid_range
    JOIN public.legal_unit AS influenced_lu
        ON influenced_lu.id = lr.influenced_id
        AND influenced_lu.valid_range && lr.valid_range
    WHERE NOT h.is_cycle
      AND h.power_level < 100
),
phase2 AS (
    SELECT legal_unit_id, valid_range, root_legal_unit_id, power_level, path, is_cycle
    FROM phase2_hierarchy
    WHERE NOT is_cycle
)

-- Final: combine both phases
SELECT legal_unit_id, valid_range, root_legal_unit_id, power_level, path, is_cycle
FROM phase1
UNION ALL
SELECT legal_unit_id, valid_range, root_legal_unit_id, power_level, path, is_cycle
FROM phase2;

COMMENT ON VIEW public.power_hierarchy IS
    'Two-phase power hierarchy: Phase 1 uses natural roots (range_agg subtraction), Phase 2 handles cycles/orphans via connected components with NSO override support';

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
FROM public.power_hierarchy
GROUP BY root_legal_unit_id;

COMMENT ON VIEW public.power_group_def IS
    'Defines power groups based on hierarchy traversal, computing depth/width/reach metrics. One row per root legal unit.';

--------------------------------------------------------------------------------
-- PART 3: View to identify relationship clusters
-- Each cluster of connected relationships forms a power group
--------------------------------------------------------------------------------

CREATE VIEW public.legal_relationship_cluster WITH (security_invoker = on) AS
WITH hierarchy_relationships AS (
    -- Get all relationships that are part of a hierarchy
    SELECT DISTINCT
        lr.id AS legal_relationship_id,
        ph.root_legal_unit_id
    FROM public.legal_relationship AS lr
    JOIN public.power_hierarchy AS ph
        ON (lr.influencing_id = ph.legal_unit_id OR lr.influenced_id = ph.legal_unit_id)
        AND lr.valid_range && ph.valid_range
)
SELECT
    legal_relationship_id,
    root_legal_unit_id
FROM hierarchy_relationships;

COMMENT ON VIEW public.legal_relationship_cluster IS
    'Maps each legal_relationship to its cluster root (for power_group assignment)';

--------------------------------------------------------------------------------
-- PART 4: Helper view for querying "active" power groups
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
-- PART 5: Helper view for power group membership (which LUs belong to which PG)
--------------------------------------------------------------------------------

CREATE VIEW public.power_group_membership WITH (security_invoker = on) AS
SELECT DISTINCT
    pg.id AS power_group_id,
    pg.ident AS power_group_ident,
    lu.id AS legal_unit_id,
    ph.power_level,
    ph.valid_range
FROM public.power_group AS pg
JOIN public.legal_relationship AS lr ON lr.power_group_id = pg.id
JOIN public.power_hierarchy AS ph
    ON (lr.influencing_id = ph.legal_unit_id OR lr.influenced_id = ph.legal_unit_id)
    AND lr.valid_range && ph.valid_range
JOIN public.legal_unit AS lu ON lu.id = ph.legal_unit_id;

COMMENT ON VIEW public.power_group_membership IS
    'Maps legal units to their power groups with hierarchy level information';

--------------------------------------------------------------------------------
-- PART 5b: power_root foreign key constraints and validation
-- (Added here because legal_unit doesn't exist at power_root creation time in 20240125)
--------------------------------------------------------------------------------

-- Supporting index for validation trigger queries on legal_relationship
-- No index on (power_group_id, influencing_id) exists — only single-column indexes
CREATE INDEX ix_legal_relationship_power_group_influencing
    ON public.legal_relationship USING btree (power_group_id, influencing_id);

-- Temporal FK: derived_root must be a real LU with overlapping valid_range
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.power_root'::regclass,
    fk_column_names => ARRAY['derived_root_legal_unit_id'],
    pk_table_oid => 'public.legal_unit',
    pk_column_names => ARRAY['id']
);

-- Temporal FK: custom_root (if set) must be a real LU with overlapping valid_range
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.power_root'::regclass,
    fk_column_names => ARRAY['custom_root_legal_unit_id'],
    pk_table_oid => 'public.legal_unit',
    pk_column_names => ARRAY['id']
);

-- Validation trigger: root LU must be influencing in some LR in the PG
-- Statement-level with transition table for batch efficiency
CREATE FUNCTION public.power_root_validate_root_membership()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $power_root_validate_root_membership$
DECLARE
    _invalid RECORD;
BEGIN
    -- derived_root must be influencing_id in some LR in the same PG
    SELECT nr.id, nr.power_group_id, nr.derived_root_legal_unit_id, nr.valid_range
    INTO _invalid
    FROM _new_power_root_rows AS nr
    WHERE NOT EXISTS (
        SELECT 1 FROM public.legal_relationship AS lr
        WHERE lr.power_group_id = nr.power_group_id
          AND lr.influencing_id = nr.derived_root_legal_unit_id
          AND lr.valid_range && nr.valid_range
    )
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'power_root id=% has derived_root_legal_unit_id=% '
            'which is not an influencing LU in power_group % during %',
            _invalid.id, _invalid.derived_root_legal_unit_id,
            _invalid.power_group_id, _invalid.valid_range;
    END IF;

    -- custom_root (if set) must also be influencing_id in the PG
    SELECT nr.id, nr.power_group_id, nr.custom_root_legal_unit_id, nr.valid_range
    INTO _invalid
    FROM _new_power_root_rows AS nr
    WHERE nr.custom_root_legal_unit_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.legal_relationship AS lr
        WHERE lr.power_group_id = nr.power_group_id
          AND lr.influencing_id = nr.custom_root_legal_unit_id
          AND lr.valid_range && nr.valid_range
    )
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'power_root id=% has custom_root_legal_unit_id=% '
            'which is not an influencing LU in power_group % during %',
            _invalid.id, _invalid.custom_root_legal_unit_id,
            _invalid.power_group_id, _invalid.valid_range;
    END IF;

    RETURN NULL;
END;
$power_root_validate_root_membership$;

CREATE TRIGGER power_root_validate_membership_on_insert
AFTER INSERT ON public.power_root
REFERENCING NEW TABLE AS _new_power_root_rows
FOR EACH STATEMENT
EXECUTE FUNCTION public.power_root_validate_root_membership();

CREATE TRIGGER power_root_validate_membership_on_update
AFTER UPDATE ON public.power_root
REFERENCING NEW TABLE AS _new_power_root_rows
FOR EACH STATEMENT
EXECUTE FUNCTION public.power_root_validate_root_membership();

--------------------------------------------------------------------------------
-- PART 6: Grant permissions
--------------------------------------------------------------------------------

-- Views: SELECT for authenticated, regular_user, admin_user
-- These are read-only aggregation views (not auto-updatable), so only SELECT is needed.
GRANT SELECT ON public.power_hierarchy TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.power_group_def TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.legal_relationship_cluster TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.power_group_active TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.power_group_membership TO authenticated, regular_user, admin_user;

-- Tables
GRANT SELECT ON public.legal_relationship TO authenticated;
GRANT SELECT ON public.power_group TO authenticated;
GRANT SELECT ON public.power_root TO authenticated;

END;
