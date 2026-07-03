```sql
CREATE OR REPLACE FUNCTION public.power_group_membership_hierarchy(parent_legal_unit_id integer, valid_on date DEFAULT CURRENT_DATE, primary_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
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
$function$
```
