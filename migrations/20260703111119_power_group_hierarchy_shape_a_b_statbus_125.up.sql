-- Migration 20260703111119: power_group_hierarchy_shape_a_b_statbus_125
--
-- STATBUS-125: power-group hierarchy reporting — Shape A + Shape B (DRAFT-001 build body 2).
--
-- Shape A: statistical_unit_hierarchy('power_group', X) returns the whole DAG —
--   {"power_group": {…, power_group_members: […]}} — members spanning ALL member
--   enterprises (fixes the single-enterprise collapse via statistical_unit_enterprise_id).
-- Shape B: enterprise/legal_unit/establishment hierarchies gain a lean
--   power_group_link at the enterprise root and a power_group_membership sub-key
--   (+ physical_country_iso_2 + domestic) on each member legal_unit node.
--   Units with no power-group membership emit NO new keys (existing outputs unchanged).
--
-- New param primary_only (DEFAULT false): true prunes to the primary/controlling
-- spine — edge primary = legal_rel_type.primary_influencer_only OR percentage > 50
-- (strict >, per IFRS 10: control presumes MORE THAN half the voting rights).
--
-- Deliberately UNCHANGED: statistical_unit_enterprise_id keeps its 'power_group'
-- branch (root LU's enterprise). Only the hierarchy path stops using it;
-- relevant_statistical_units and statistical_unit_stats still resolve a power
-- group to its representative enterprise — a sane semantic for stats/search.
BEGIN;

-- Signatures change (primary_only appended), so DROP + CREATE — CREATE OR REPLACE
-- would create coexisting overloads and ambiguous call sites.
DROP FUNCTION public.statistical_unit_hierarchy(statistical_unit_type, integer, hierarchy_scope, date, boolean);
DROP FUNCTION public.enterprise_hierarchy(integer, hierarchy_scope, date);
DROP FUNCTION public.legal_unit_hierarchy(integer, integer, hierarchy_scope, date);

-- ============================================================================
-- power_group_link — the reduced group reference (PowerGroupLink = PowerGroup
-- minus members). Multi-parent resolution follows the house fragment convention
-- (cf. external_idents_hierarchy): resolve the group from a legal unit's
-- membership, from an enterprise's primary legal unit, or directly by group id.
-- Returns {"power_group_link": {…}} or '{}' when no group resolves.
-- ============================================================================
CREATE FUNCTION public.power_group_link(
    parent_legal_unit_id integer DEFAULT NULL,
    parent_enterprise_id integer DEFAULT NULL,
    parent_power_group_id integer DEFAULT NULL,
    valid_on date DEFAULT CURRENT_DATE
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $power_group_link$
  WITH resolved_legal_unit AS (
      SELECT CASE
          WHEN parent_legal_unit_id IS NOT NULL THEN parent_legal_unit_id
          WHEN parent_enterprise_id IS NOT NULL THEN (
              SELECT lu.id
              FROM public.legal_unit AS lu
              WHERE lu.enterprise_id = parent_enterprise_id
                AND lu.primary_for_enterprise
                AND lu.valid_from <= valid_on AND valid_on < lu.valid_until
              LIMIT 1
          )
      END AS legal_unit_id
  ), resolved_power_group AS (
      SELECT COALESCE(
          parent_power_group_id,
          (SELECT lr.derived_power_group_id
           FROM resolved_legal_unit AS rlu
           JOIN public.legal_relationship AS lr
             ON (lr.influencing_id = rlu.legal_unit_id OR lr.influenced_id = rlu.legal_unit_id)
           WHERE lr.derived_power_group_id IS NOT NULL
             AND lr.valid_range @> valid_on
           LIMIT 1)
      ) AS power_group_id
  ), members AS (
      -- Unified member source: enumerate from legal_relationship (works for
      -- cycle groups where the power_group_membership view is empty), then
      -- LEFT JOIN the BFS level (NULL for cycles).
      SELECT m.legal_unit_id, MIN(pgm.power_level) AS power_level
      FROM (
          SELECT lr.influencing_id AS legal_unit_id
          FROM public.legal_relationship AS lr, resolved_power_group AS rpg
          WHERE lr.derived_power_group_id = rpg.power_group_id
            AND lr.valid_range @> valid_on
          UNION
          SELECT lr.influenced_id
          FROM public.legal_relationship AS lr, resolved_power_group AS rpg
          WHERE lr.derived_power_group_id = rpg.power_group_id
            AND lr.valid_range @> valid_on
      ) AS m
      LEFT JOIN public.power_group_membership AS pgm
          ON pgm.power_group_id = (SELECT rpg.power_group_id FROM resolved_power_group AS rpg)
          AND pgm.legal_unit_id = m.legal_unit_id
          AND pgm.valid_range @> valid_on
      GROUP BY m.legal_unit_id
  ), root AS (
      -- power_root exists only for cycle/multi groups; clean groups derive
      -- their root from the single power_level = 0 member.
      SELECT pr.root_legal_unit_id,
             pr.derived_root_status,
             pr.custom_root_legal_unit_id
      FROM public.power_root AS pr, resolved_power_group AS rpg
      WHERE pr.power_group_id = rpg.power_group_id
        AND pr.valid_range @> valid_on
  ), fields AS (
      SELECT jsonb_build_object(
          'ident', pg.ident,
          'name', pg.name,
          'type', (SELECT to_jsonb(pgt.*) FROM public.power_group_type AS pgt WHERE pgt.id = pg.type_id),
          'depth', (SELECT max(m.power_level) FROM members AS m),
          'width', (SELECT CASE WHEN max(m.power_level) IS NULL THEN NULL
                                ELSE count(*) FILTER (WHERE m.power_level = 1) END
                    FROM members AS m),
          'reach', (SELECT CASE WHEN count(*) = 0 THEN NULL ELSE count(*) - 1 END FROM members AS m),
          'root_legal_unit_id', COALESCE(
              (SELECT r.root_legal_unit_id FROM root AS r),
              (SELECT m.legal_unit_id FROM members AS m WHERE m.power_level = 0 LIMIT 1)
          ),
          'root_status', COALESCE((SELECT r.derived_root_status::text FROM root AS r), 'clean'),
          'root_is_custom', COALESCE((SELECT r.custom_root_legal_unit_id IS NOT NULL FROM root AS r), false)
      ) AS data
      FROM public.power_group AS pg, resolved_power_group AS rpg
      WHERE pg.id = rpg.power_group_id
  )
  SELECT CASE
      WHEN EXISTS (SELECT 1 FROM fields) THEN jsonb_build_object('power_group_link', (SELECT f.data FROM fields AS f))
      ELSE '{}'::JSONB
  END;
$power_group_link$;

-- ============================================================================
-- power_group_membership_hierarchy — a legal unit's membership fragment.
-- Emits, when the unit is a member of a power group on valid_on:
--   power_group_membership { power_level (NULL for cycle groups), is_root,
--     influencers[] (up; holds influencing_id), influencees[] (down; holds
--     influenced_id) } — each edge { <counterpart>_id, type, percentage, primary }
--   + physical_country_iso_2 + domestic (sourced from statistical_unit; inlined
--     for cross-border group reporting, DRAFT-001 decisions #4/#5).
-- Emits '{}' for non-members so existing hierarchy outputs are unchanged.
-- Edge primary = primary_influencer_only OR percentage > 50 (the unified
-- single-controller flag; both routes guarantee a single controller).
-- primary_only = true filters the edge arrays to primary edges.
-- ============================================================================
CREATE FUNCTION public.power_group_membership_hierarchy(
    parent_legal_unit_id integer,
    valid_on date DEFAULT CURRENT_DATE,
    primary_only boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $power_group_membership_hierarchy$
  WITH edges AS (
      SELECT lr.influencing_id,
             lr.influenced_id,
             lr.derived_power_group_id,
             lrt.code AS type,
             lr.percentage,
             (COALESCE(lr.primary_influencer_only, false) OR COALESCE(lr.percentage > 50, false)) AS is_primary
      FROM public.legal_relationship AS lr
      JOIN public.legal_rel_type AS lrt ON lrt.id = lr.type_id
      WHERE lr.derived_power_group_id IS NOT NULL
        AND lr.valid_range @> valid_on
        AND (lr.influencing_id = parent_legal_unit_id OR lr.influenced_id = parent_legal_unit_id)
  ), my_group AS (
      -- A legal unit belongs to at most one power group per date (groups are
      -- connected components of legal_relationship).
      SELECT e.derived_power_group_id AS power_group_id FROM edges AS e LIMIT 1
  ), level AS (
      SELECT MIN(pgm.power_level) AS power_level
      FROM public.power_group_membership AS pgm, my_group AS mg
      WHERE pgm.power_group_id = mg.power_group_id
        AND pgm.legal_unit_id = parent_legal_unit_id
        AND pgm.valid_range @> valid_on
  ), root AS (
      SELECT pr.root_legal_unit_id
      FROM public.power_root AS pr, my_group AS mg
      WHERE pr.power_group_id = mg.power_group_id
        AND pr.valid_range @> valid_on
  ), unit AS (
      SELECT su.physical_country_iso_2, su.domestic
      FROM public.statistical_unit AS su
      WHERE su.unit_type = 'legal_unit'
        AND su.unit_id = parent_legal_unit_id
        AND su.valid_from <= valid_on AND valid_on < su.valid_until
      LIMIT 1
  )
  SELECT CASE
      WHEN EXISTS (SELECT 1 FROM edges) THEN jsonb_build_object(
          'power_group_membership', jsonb_build_object(
              'power_level', (SELECT l.power_level FROM level AS l),
              'is_root', COALESCE(
                  (SELECT r.root_legal_unit_id = parent_legal_unit_id FROM root AS r),
                  (SELECT l.power_level = 0 FROM level AS l),
                  false
              ),
              'influencers', COALESCE(
                  (SELECT jsonb_agg(
                       jsonb_build_object(
                           'influencing_id', e.influencing_id,
                           'type', e.type,
                           'percentage', e.percentage,
                           'primary', e.is_primary
                       ) ORDER BY e.is_primary DESC, e.influencing_id ASC)
                   FROM edges AS e
                   WHERE e.influenced_id = parent_legal_unit_id
                     AND (NOT primary_only OR e.is_primary)),
                  '[]'::JSONB
              ),
              'influencees', COALESCE(
                  (SELECT jsonb_agg(
                       jsonb_build_object(
                           'influenced_id', e.influenced_id,
                           'type', e.type,
                           'percentage', e.percentage,
                           'primary', e.is_primary
                       ) ORDER BY e.is_primary DESC, e.influenced_id ASC)
                   FROM edges AS e
                   WHERE e.influencing_id = parent_legal_unit_id
                     AND (NOT primary_only OR e.is_primary)),
                  '[]'::JSONB
              )
          ),
          'physical_country_iso_2', (SELECT u.physical_country_iso_2 FROM unit AS u),
          'domestic', (SELECT u.domestic FROM unit AS u)
      )
      ELSE '{}'::JSONB
  END;
$power_group_membership_hierarchy$;

-- ============================================================================
-- legal_unit_hierarchy — re-created with primary_only (DEFAULT false, appended;
-- existing call sites unaffected) and the Shape-B power_group_membership
-- injection on each node (emits nothing for non-members).
-- ============================================================================
CREATE FUNCTION public.legal_unit_hierarchy(legal_unit_id integer, parent_enterprise_id integer, scope hierarchy_scope DEFAULT 'all'::hierarchy_scope, valid_on date DEFAULT CURRENT_DATE, primary_only boolean DEFAULT false)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $legal_unit_hierarchy$
  WITH ordered_data AS (
    SELECT to_jsonb(lu.*)
        || (SELECT public.external_idents_hierarchy(NULL,lu.id,NULL,NULL))
        || (SELECT public.power_group_membership_hierarchy(lu.id, valid_on, primary_only))
        || CASE WHEN scope IN ('all','tree') THEN (SELECT public.establishment_hierarchy(NULL, lu.id, NULL, scope, valid_on)) ELSE '{}'::JSONB END
        || (SELECT public.activity_hierarchy(NULL,lu.id,valid_on))
        || (SELECT public.location_hierarchy(NULL,lu.id,valid_on))
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.stat_for_unit_hierarchy(NULL,lu.id,valid_on)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.sector_hierarchy(lu.sector_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.unit_size_hierarchy(lu.unit_size_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.status_hierarchy(lu.status_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.legal_form_hierarchy(lu.legal_form_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.contact_hierarchy(NULL,lu.id,valid_on)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.data_source_hierarchy(lu.data_source_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.notes_for_unit(NULL,lu.id,NULL,NULL)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.tag_for_unit_hierarchy(NULL,lu.id,NULL,NULL)) ELSE '{}'::JSONB END
        AS data
    FROM public.legal_unit AS lu
   WHERE (  (legal_unit_id IS NOT NULL AND lu.id = legal_unit_id)
         OR (parent_enterprise_id IS NOT NULL AND lu.enterprise_id = parent_enterprise_id)
         )
     AND lu.valid_from <= valid_on AND valid_on < lu.valid_until
   ORDER BY lu.primary_for_enterprise DESC, lu.name
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('legal_unit',data)
    END
  FROM data_list;
$legal_unit_hierarchy$;

-- ============================================================================
-- power_group_hierarchy — Shape A: the whole group on top, members spanning
-- ALL member enterprises. Members are full legal-unit nodes (built by
-- legal_unit_hierarchy, so each carries its power_group_membership + country +
-- domestic) plus an explicit legal_unit_id. Cycle groups render: members
-- enumerated from legal_relationship, root from power_root.
-- primary_only = true prunes members to those reachable from the root via
-- primary edges (the consolidation spine), and edge arrays to primary edges.
-- ============================================================================
CREATE FUNCTION public.power_group_hierarchy(
    power_group_id integer,
    scope hierarchy_scope DEFAULT 'all'::hierarchy_scope,
    valid_on date DEFAULT CURRENT_DATE,
    primary_only boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $power_group_hierarchy$
  WITH all_members AS (
      SELECT m.legal_unit_id, MIN(pgm.power_level) AS power_level
      FROM (
          SELECT lr.influencing_id AS legal_unit_id
          FROM public.legal_relationship AS lr
          WHERE lr.derived_power_group_id = power_group_hierarchy.power_group_id
            AND lr.valid_range @> valid_on
          UNION
          SELECT lr.influenced_id
          FROM public.legal_relationship AS lr
          WHERE lr.derived_power_group_id = power_group_hierarchy.power_group_id
            AND lr.valid_range @> valid_on
      ) AS m
      LEFT JOIN public.power_group_membership AS pgm
          ON pgm.power_group_id = power_group_hierarchy.power_group_id
          AND pgm.legal_unit_id = m.legal_unit_id
          AND pgm.valid_range @> valid_on
      GROUP BY m.legal_unit_id
  ), effective_root AS (
      SELECT COALESCE(
          (SELECT pr.root_legal_unit_id
           FROM public.power_root AS pr
           WHERE pr.power_group_id = power_group_hierarchy.power_group_id
             AND pr.valid_range @> valid_on),
          (SELECT am.legal_unit_id FROM all_members AS am WHERE am.power_level = 0 LIMIT 1)
      ) AS legal_unit_id
  ), primary_reachable AS (
      -- The controlling spine: members reachable from the effective root via
      -- primary edges. UNION (not UNION ALL) dedupes and terminates on cycles.
      WITH RECURSIVE walk(legal_unit_id) AS (
          SELECT er.legal_unit_id FROM effective_root AS er
          UNION
          SELECT lr.influenced_id
          FROM walk AS w
          JOIN public.legal_relationship AS lr ON lr.influencing_id = w.legal_unit_id
          WHERE lr.derived_power_group_id = power_group_hierarchy.power_group_id
            AND lr.valid_range @> valid_on
            AND (COALESCE(lr.primary_influencer_only, false) OR COALESCE(lr.percentage > 50, false))
      )
      SELECT w.legal_unit_id FROM walk AS w
  ), members AS (
      SELECT am.legal_unit_id, am.power_level
      FROM all_members AS am
      WHERE NOT primary_only
         OR am.legal_unit_id IN (SELECT pr.legal_unit_id FROM primary_reachable AS pr)
  ), member_nodes AS (
      SELECT (public.legal_unit_hierarchy(m.legal_unit_id, NULL, scope, valid_on, primary_only)->'legal_unit'->0)
             || jsonb_build_object('legal_unit_id', m.legal_unit_id)
             AS node,
             m.power_level,
             m.legal_unit_id
      FROM members AS m
  ), members_json AS (
      SELECT COALESCE(
          jsonb_agg(mn.node ORDER BY mn.power_level ASC NULLS LAST, mn.node->>'name' ASC, mn.legal_unit_id ASC),
          '[]'::JSONB
      ) AS data
      FROM member_nodes AS mn
  ), data AS (
      SELECT jsonb_build_object(
          'power_group',
          (public.power_group_link(parent_power_group_id => pg.id, valid_on => valid_on)->'power_group_link')
          || (SELECT public.external_idents_hierarchy(NULL,NULL,NULL,pg.id))
          || CASE WHEN scope IN ('all','tree') THEN jsonb_build_object('power_group_members', (SELECT mj.data FROM members_json AS mj)) ELSE '{}'::JSONB END
          || CASE WHEN scope IN ('all','details') THEN (SELECT public.notes_for_unit(NULL,NULL,NULL,pg.id)) ELSE '{}'::JSONB END
          || CASE WHEN scope IN ('all','details') THEN (SELECT public.tag_for_unit_hierarchy(NULL,NULL,NULL,pg.id)) ELSE '{}'::JSONB END
      ) AS data
      FROM public.power_group AS pg
      WHERE power_group_hierarchy.power_group_id IS NOT NULL
        AND pg.id = power_group_hierarchy.power_group_id
  )
  SELECT COALESCE((SELECT d.data FROM data AS d), '{}'::JSONB);
$power_group_hierarchy$;

-- ============================================================================
-- enterprise_hierarchy — re-created with primary_only (DEFAULT false, appended)
-- threaded to legal_unit_hierarchy, and the Shape-B power_group_link lifted to
-- the enterprise root (derived from the primary legal unit; emits nothing when
-- that unit is in no power group).
-- ============================================================================
CREATE FUNCTION public.enterprise_hierarchy(enterprise_id integer, scope hierarchy_scope DEFAULT 'all'::hierarchy_scope, valid_on date DEFAULT CURRENT_DATE, primary_only boolean DEFAULT false)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $enterprise_hierarchy$
    WITH data AS (
        SELECT jsonb_build_object(
                'enterprise',
                 to_jsonb(en.*)
                 || (SELECT public.external_idents_hierarchy(NULL,NULL,en.id,NULL))
                 || (SELECT public.power_group_link(parent_enterprise_id => en.id, valid_on => valid_on))
                 || CASE WHEN scope IN ('all','tree') THEN (SELECT public.legal_unit_hierarchy(NULL, en.id, scope, valid_on, primary_only)) ELSE '{}'::JSONB END
                 || CASE WHEN scope IN ('all','tree') THEN (SELECT public.establishment_hierarchy(NULL, NULL, en.id, scope, valid_on)) ELSE '{}'::JSONB END
                 || CASE WHEN scope IN ('all','details') THEN (SELECT public.notes_for_unit(NULL,NULL,en.id,NULL)) ELSE '{}'::JSONB END
                 || CASE WHEN scope IN ('all','details') THEN (SELECT public.tag_for_unit_hierarchy(NULL,NULL,en.id,NULL)) ELSE '{}'::JSONB END
                ) AS data
          FROM public.enterprise AS en
         WHERE enterprise_id IS NOT NULL AND en.id = enterprise_id
         ORDER BY en.short_name
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$enterprise_hierarchy$;

-- ============================================================================
-- statistical_unit_hierarchy — the dispatcher. 'power_group' now dispatches to
-- power_group_hierarchy (Shape A) instead of collapsing to the root legal
-- unit's enterprise; all other unit types keep the enterprise-rooted path
-- (now Shape-B enriched). primary_only appended (DEFAULT false).
-- ============================================================================
CREATE FUNCTION public.statistical_unit_hierarchy(unit_type statistical_unit_type, unit_id integer, scope hierarchy_scope DEFAULT 'all'::hierarchy_scope, valid_on date DEFAULT CURRENT_DATE, strip_nulls boolean DEFAULT false, primary_only boolean DEFAULT false)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $statistical_unit_hierarchy$
  WITH result AS (
    SELECT CASE
      WHEN unit_type = 'power_group' THEN public.power_group_hierarchy(unit_id, scope, valid_on, primary_only)
      ELSE public.enterprise_hierarchy(
        public.statistical_unit_enterprise_id(unit_type, unit_id, valid_on)
        , scope, valid_on, primary_only
      )
      END AS data
  )
  SELECT
    CASE
      WHEN strip_nulls THEN jsonb_strip_nulls(result.data)
      ELSE result.data
    END
   FROM result
  ;
$statistical_unit_hierarchy$;

-- statistical_unit_details previously fell through to '{}' for power_group;
-- complete the dispatcher (signature unchanged — CREATE OR REPLACE).
CREATE OR REPLACE FUNCTION public.statistical_unit_details(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $statistical_unit_details$
    SELECT CASE
        WHEN unit_type = 'enterprise' THEN public.enterprise_hierarchy(unit_id, 'details', valid_on)
        WHEN unit_type = 'legal_unit' THEN public.legal_unit_hierarchy(unit_id, NULL, 'details', valid_on)
        WHEN unit_type = 'establishment' THEN public.establishment_hierarchy(unit_id, NULL, NULL, 'details', valid_on)
        WHEN unit_type = 'power_group' THEN public.power_group_hierarchy(unit_id, 'details', valid_on)
        ELSE '{}'::JSONB
    END;
$statistical_unit_details$;

END;
