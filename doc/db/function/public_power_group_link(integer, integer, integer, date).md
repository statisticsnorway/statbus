```sql
CREATE OR REPLACE FUNCTION public.power_group_link(parent_legal_unit_id integer DEFAULT NULL::integer, parent_enterprise_id integer DEFAULT NULL::integer, parent_power_group_id integer DEFAULT NULL::integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
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
$function$
```
