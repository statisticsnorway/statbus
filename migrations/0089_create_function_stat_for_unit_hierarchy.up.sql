\echo public.stat_for_unit_hierarchy
CREATE OR REPLACE FUNCTION public.stat_for_unit_hierarchy(
  parent_establishment_id INTEGER DEFAULT NULL,
  parent_legal_unit_id INTEGER DEFAULT NULL,
  valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH ordered_data AS (
    SELECT
        to_jsonb(sfu.*)
        || jsonb_build_object('stat_definition', to_jsonb(sd.*))
        || (SELECT public.data_source_hierarchy(sfu.data_source_id))
        AS data
    FROM public.stat_for_unit AS sfu
    JOIN public.stat_definition AS sd ON sd.id = sfu.stat_definition_id
    WHERE (  parent_establishment_id    IS NOT NULL AND sfu.establishment_id    = parent_establishment_id
          OR parent_legal_unit_id       IS NOT NULL AND sfu.legal_unit_id       = parent_legal_unit_id
          )
      AND sfu.valid_after < valid_on AND valid_on <= sfu.valid_to
    ORDER BY sd.priority ASC NULLS LAST, sd.code
), data_list AS (
    SELECT jsonb_agg(data) AS data FROM ordered_data
)
SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('stat_for_unit',data)
    END
  FROM data_list;
$$;
