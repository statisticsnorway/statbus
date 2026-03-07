-- Migration: Add power group worker infrastructure
-- Purpose: Create views and worker commands for deriving power group hierarchies
-- power_group is TIMELESS (like enterprise) - legal_relationship.derived_power_group_id links relationships to groups
-- Active status is derived at query time from legal_relationship.valid_range
--
-- Power level and group assignment are materialized on legal_relationship by process_power_group_link:
-- - derived_power_group_id: which power group this LR belongs to (connected component label)
-- - derived_influenced_power_level: BFS depth of the influenced LU (2 = direct child, 3 = grandchild)
-- Root LUs (level 1) are implicit: influencing LUs never influenced within the same PG.

BEGIN;

--------------------------------------------------------------------------------
-- PART 1: Power group membership view (reads materialized data from legal_relationship)
-- Power level and group are computed at write time by process_power_group_link.
-- No recursive CTE needed at read time.
--------------------------------------------------------------------------------

CREATE VIEW public.power_group_membership WITH (security_invoker = on) AS
-- Roots (level 1): influencing LUs never influenced within same PG
SELECT DISTINCT
    lr.derived_power_group_id AS power_group_id,
    pg.ident AS power_group_ident,
    lr.influencing_id AS legal_unit_id,
    1 AS power_level,
    lr.valid_range
FROM public.legal_relationship AS lr
JOIN public.power_group AS pg ON pg.id = lr.derived_power_group_id
WHERE lr.derived_power_group_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.legal_relationship AS lr2
    WHERE lr2.influenced_id = lr.influencing_id
      AND lr2.derived_power_group_id = lr.derived_power_group_id
      AND lr2.valid_range && lr.valid_range
)
UNION
-- Non-roots: influenced LUs with their stored level
SELECT
    lr.derived_power_group_id AS power_group_id,
    pg.ident AS power_group_ident,
    lr.influenced_id AS legal_unit_id,
    lr.derived_influenced_power_level AS power_level,
    lr.valid_range
FROM public.legal_relationship AS lr
JOIN public.power_group AS pg ON pg.id = lr.derived_power_group_id
WHERE lr.derived_power_group_id IS NOT NULL
  AND lr.derived_influenced_power_level IS NOT NULL;

COMMENT ON VIEW public.power_group_membership IS
    'Maps legal units to their power groups with hierarchy level information. Reads materialized data from legal_relationship — no recursive CTE.';

--------------------------------------------------------------------------------
-- PART 2: Power group definition view (computes derived metrics from LR directly)
--------------------------------------------------------------------------------

CREATE VIEW public.power_group_def WITH (security_invoker = on) AS
SELECT
    pgm.power_group_id,
    MAX(pgm.power_level) - 1 AS depth,  -- Longest path from root (0 for single root)
    COUNT(*) FILTER (WHERE pgm.power_level = 2) AS width,  -- Direct children count
    COUNT(*) - 1 AS reach  -- Total controlled units (excluding root)
FROM public.power_group_membership AS pgm
GROUP BY pgm.power_group_id;

COMMENT ON VIEW public.power_group_def IS
    'Defines power groups based on materialized hierarchy, computing depth/width/reach metrics. One row per power group.';

--------------------------------------------------------------------------------
-- PART 3: View to identify relationship clusters (via derived_power_group_id)
-- Now trivial: each LR already has its cluster identity materialized.
--------------------------------------------------------------------------------

CREATE VIEW public.legal_relationship_cluster WITH (security_invoker = on) AS
SELECT
    lr.id AS legal_relationship_id,
    lr.derived_power_group_id AS power_group_id
FROM public.legal_relationship AS lr
WHERE lr.derived_power_group_id IS NOT NULL;

COMMENT ON VIEW public.legal_relationship_cluster IS
    'Maps each legal_relationship to its power group (reads materialized derived_power_group_id)';

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
JOIN public.legal_relationship AS lr ON lr.derived_power_group_id = pg.id
WHERE lr.valid_range @> CURRENT_DATE;

COMMENT ON VIEW public.power_group_active IS
    'Power groups that are currently active (have at least one relationship with valid_range containing today)';

--------------------------------------------------------------------------------
-- PART 5b: power_root foreign key constraints and validation
-- (Added here because legal_unit doesn't exist at power_root creation time in 20240125)
--------------------------------------------------------------------------------

-- Supporting index for validation trigger queries on legal_relationship
-- No index on (derived_power_group_id, influencing_id) exists — only single-column indexes
CREATE INDEX ix_legal_relationship_power_group_influencing
    ON public.legal_relationship USING btree (derived_power_group_id, influencing_id);

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
        WHERE lr.derived_power_group_id = nr.power_group_id
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
        WHERE lr.derived_power_group_id = nr.power_group_id
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
GRANT SELECT ON public.power_group_def TO authenticated, regular_user, admin_user;
GRANT SELECT, INSERT ON public.legal_relationship_cluster TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.power_group_active TO authenticated, regular_user, admin_user;
GRANT SELECT ON public.power_group_membership TO authenticated, regular_user, admin_user;

-- Tables
GRANT SELECT ON public.legal_relationship TO authenticated;
GRANT SELECT ON public.power_group TO authenticated;
GRANT SELECT ON public.power_root TO authenticated;

END;
