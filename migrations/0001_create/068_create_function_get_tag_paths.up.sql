BEGIN;

\echo public.get_tag_paths
CREATE FUNCTION public.get_tag_paths(
  unit_type public.statistical_unit_type,
  unit_id INTEGER
) RETURNS public.ltree[] LANGUAGE sql STABLE STRICT AS $$
  WITH ordered_data AS (
    SELECT DISTINCT t.path
    FROM public.tag_for_unit AS tfu
    JOIN public.tag AS t ON t.id = tfu.tag_id
    WHERE
      CASE unit_type
      WHEN 'enterprise' THEN tfu.enterprise_id = unit_id
      WHEN 'legal_unit' THEN tfu.legal_unit_id = unit_id
      WHEN 'establishment' THEN tfu.establishment_id = unit_id
      WHEN 'enterprise_group' THEN tfu.enterprise_group_id = unit_id
      END
    ORDER BY t.path
  ), agg_data AS (
    SELECT array_agg(path) AS tag_paths FROM ordered_data
  )
  SELECT COALESCE(tag_paths, ARRAY[]::public.ltree[]) AS tag_paths
  FROM agg_data;
$$;

END;