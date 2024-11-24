BEGIN;

\echo public.location_hierarchy
CREATE OR REPLACE FUNCTION public.location_hierarchy(
  parent_establishment_id INTEGER DEFAULT NULL,
  parent_legal_unit_id INTEGER DEFAULT NULL,
  valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
  WITH ordered_data AS (
    SELECT to_jsonb(l.*)
        || (SELECT public.region_hierarchy(l.region_id))
        || (SELECT public.country_hierarchy(l.country_id))
        || (SELECT public.data_source_hierarchy(l.data_source_id))
        AS data
      FROM public.location AS l
     WHERE l.valid_after < valid_on AND valid_on <= l.valid_to
       AND (  parent_establishment_id IS NOT NULL AND l.establishment_id = parent_establishment_id
           OR parent_legal_unit_id    IS NOT NULL AND l.legal_unit_id    = parent_legal_unit_id
           )
       ORDER BY l.type
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('location',data)
    END
  FROM data_list;
  ;
$$;

END;