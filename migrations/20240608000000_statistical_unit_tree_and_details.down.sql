BEGIN;

DROP FUNCTION public.statistical_unit_stats(unit_type public.statistical_unit_type, unit_id INTEGER, valid_on DATE);
DROP TYPE public.statistical_unit_stats;
DROP FUNCTION public.statistical_unit_details(unit_type public.statistical_unit_type, unit_id INTEGER, valid_on DATE);
DROP FUNCTION public.statistical_unit_tree(unit_type public.statistical_unit_type, unit_id INTEGER, valid_on DATE);

DROP FUNCTION public.statistical_unit_hierarchy(unit_type public.statistical_unit_type, unit_id INTEGER, scope public.hierarchy_scope, valid_on DATE, strip_nulls BOOLEAN);
DROP FUNCTION public.enterprise_hierarchy(enterprise_id INTEGER, scope public.hierarchy_scope, valid_on DATE);
DROP FUNCTION public.legal_unit_hierarchy(legal_unit_id INTEGER, parent_enterprise_id INTEGER, scope public.hierarchy_scope, valid_on DATE);
DROP FUNCTION public.establishment_hierarchy(establishment_id INTEGER, parent_legal_unit_id INTEGER, parent_enterprise_id INTEGER, scope public.hierarchy_scope, valid_on DATE);

DROP FUNCTION public.status_hierarchy(status_id INTEGER);
DROP FUNCTION public.contact_hierarchy(parent_establishment_id INTEGER, parent_legal_unit_id INTEGER);
DROP FUNCTION public.notes_for_unit(parent_establishment_id INTEGER, parent_legal_unit_id INTEGER, parent_enterprise_id INTEGER, parent_power_group_id INTEGER);

DROP TYPE public.hierarchy_scope;

CREATE OR REPLACE FUNCTION public.establishment_hierarchy(
    parent_legal_unit_id INTEGER DEFAULT NULL,
    parent_enterprise_id INTEGER DEFAULT NULL,
    valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
  WITH ordered_data AS (
    SELECT to_jsonb(es.*)
        || (SELECT public.external_idents_hierarchy(es.id,NULL,NULL,NULL))
        || (SELECT public.activity_hierarchy(es.id,NULL,valid_on))
        || (SELECT public.location_hierarchy(es.id,NULL,valid_on))
        || (SELECT public.stat_for_unit_hierarchy(es.id,NULL,valid_on))
        || (SELECT public.sector_hierarchy(es.sector_id))
        || (SELECT public.data_source_hierarchy(es.data_source_id))
        || (SELECT public.tag_for_unit_hierarchy(es.id,NULL,NULL,NULL))
        AS data
    FROM public.establishment AS es
   WHERE (  (parent_legal_unit_id IS NOT NULL AND es.legal_unit_id = parent_legal_unit_id)
         OR (parent_enterprise_id IS NOT NULL AND es.enterprise_id = parent_enterprise_id)
         )
     AND es.valid_from <= valid_on AND valid_on < es.valid_until
   ORDER BY es.primary_for_legal_unit DESC, es.name
  ), data_list AS (
      SELECT jsonb_agg(data) AS data FROM ordered_data
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('establishment',data)
    END
  FROM data_list;
$$;

CREATE OR REPLACE FUNCTION public.legal_unit_hierarchy(
  parent_enterprise_id INTEGER,
  valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
  WITH ordered_data AS (
    SELECT to_jsonb(lu.*)
        || (SELECT public.external_idents_hierarchy(NULL,lu.id,NULL,NULL))
        || (SELECT public.establishment_hierarchy(lu.id, NULL, valid_on))
        || (SELECT public.activity_hierarchy(NULL,lu.id,valid_on))
        || (SELECT public.location_hierarchy(NULL,lu.id,valid_on))
        || (SELECT public.stat_for_unit_hierarchy(NULL,lu.id,valid_on))
        || (SELECT public.sector_hierarchy(lu.sector_id))
        || (SELECT public.legal_form_hierarchy(lu.legal_form_id))
        || (SELECT public.data_source_hierarchy(lu.data_source_id))
        || (SELECT public.tag_for_unit_hierarchy(NULL,lu.id,NULL,NULL))
        AS data
    FROM public.legal_unit AS lu
   WHERE parent_enterprise_id IS NOT NULL AND lu.enterprise_id = parent_enterprise_id
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
$$;

CREATE OR REPLACE FUNCTION public.enterprise_hierarchy(
  enterprise_id INTEGER,
  valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object(
                'enterprise',
                 to_jsonb(en.*)
                 || (SELECT public.external_idents_hierarchy(NULL,NULL,en.id,NULL))
                 || (SELECT public.legal_unit_hierarchy(en.id, valid_on))
                 || (SELECT public.establishment_hierarchy(NULL, en.id, valid_on))
                 || (SELECT public.tag_for_unit_hierarchy(NULL,NULL,en.id,NULL))
                ) AS data
          FROM public.enterprise AS en
         WHERE enterprise_id IS NOT NULL AND en.id = enterprise_id
         ORDER BY en.short_name
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;

CREATE OR REPLACE FUNCTION public.statistical_unit_hierarchy(
  unit_type public.statistical_unit_type,
  unit_id INTEGER,
  valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
  SELECT --jsonb_strip_nulls(
            public.enterprise_hierarchy(
              public.statistical_unit_enterprise_id(unit_type, unit_id, valid_on)
              , valid_on
            )
        --)
;
$$;


END;
