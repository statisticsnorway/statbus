```sql
CREATE OR REPLACE FUNCTION public.power_group_hierarchy(power_group_id integer, scope hierarchy_scope DEFAULT 'all'::hierarchy_scope, valid_on date DEFAULT CURRENT_DATE, primary_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
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
$function$
```
