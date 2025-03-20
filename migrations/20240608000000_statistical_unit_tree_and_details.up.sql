-- Migration 159: statistical_unit_tree_and_details
BEGIN;

-- Remove the old functions
-- Drop functions that depend on other functions first
DROP FUNCTION public.statistical_unit_hierarchy(public.statistical_unit_type, INTEGER, DATE);

DROP FUNCTION public.enterprise_hierarchy(INTEGER, DATE);
DROP FUNCTION public.legal_unit_hierarchy(INTEGER, DATE);
DROP FUNCTION public.establishment_hierarchy(INTEGER, INTEGER, DATE);

-- Create enum type for hierarchy scope
CREATE TYPE public.hierarchy_scope AS ENUM ('all', 'tree', 'details');

CREATE FUNCTION public.notes_for_unit(
  parent_establishment_id INTEGER,
  parent_legal_unit_id INTEGER,
  parent_enterprise_id INTEGER,
  parent_enterprise_group_id INTEGER
) RETURNS JSONB LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    (SELECT jsonb_build_object('notes',to_jsonb(un.*))
     FROM public.unit_notes AS un
     WHERE (  parent_establishment_id    IS NOT NULL AND un.establishment_id    = parent_establishment_id
           OR parent_legal_unit_id       IS NOT NULL AND un.legal_unit_id       = parent_legal_unit_id
           OR parent_enterprise_id       IS NOT NULL AND un.enterprise_id       = parent_enterprise_id
           OR parent_enterprise_group_id IS NOT NULL AND un.enterprise_group_id = parent_enterprise_group_id
           )),
    '{}'::JSONB
  );
$$;

CREATE FUNCTION public.contact_hierarchy(
  parent_establishment_id INTEGER,
  parent_legal_unit_id INTEGER
) RETURNS JSONB LANGUAGE sql STABLE AS $$
  SELECT COALESCE(
    (SELECT jsonb_build_object('contact',to_jsonb(c.*))
     FROM public.contact AS c
     WHERE (  parent_establishment_id IS NOT NULL AND c.establishment_id = parent_establishment_id
           OR parent_legal_unit_id    IS NOT NULL AND c.legal_unit_id    = parent_legal_unit_id
           )),
    '{}'::JSONB
  );
$$;

CREATE FUNCTION public.status_hierarchy(status_id INTEGER)
RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object('status', to_jsonb(s.*)) AS data
          FROM public.status AS s
         WHERE status_id IS NOT NULL AND s.id = status_id
         ORDER BY s.code
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;

CREATE FUNCTION public.establishment_hierarchy(
    establishment_id INTEGER,
    parent_legal_unit_id INTEGER,
    parent_enterprise_id INTEGER,
    scope public.hierarchy_scope DEFAULT 'all',
    valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
  WITH ordered_data AS (
    SELECT to_jsonb(es.*)
        || (SELECT public.external_idents_hierarchy(es.id,NULL,NULL,NULL))
        || (SELECT public.activity_hierarchy(es.id,NULL,valid_on))
        || (SELECT public.location_hierarchy(es.id,NULL,valid_on))
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.stat_for_unit_hierarchy(es.id,NULL,valid_on)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.sector_hierarchy(es.sector_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.unit_size_hierarchy(es.unit_size_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.status_hierarchy(es.status_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.contact_hierarchy(es.id,NULL)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.data_source_hierarchy(es.data_source_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.notes_for_unit(es.id,NULL,NULL,NULL)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.tag_for_unit_hierarchy(es.id,NULL,NULL,NULL)) ELSE '{}'::JSONB END
        AS data
    FROM public.establishment AS es
   WHERE (  (establishment_id IS NOT NULL AND es.id = establishment_id)
         OR (parent_legal_unit_id IS NOT NULL AND es.legal_unit_id = parent_legal_unit_id)
         OR (parent_enterprise_id IS NOT NULL AND es.enterprise_id = parent_enterprise_id)
         )
     AND es.valid_after < valid_on AND valid_on <= es.valid_to
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


CREATE FUNCTION public.legal_unit_hierarchy(
  legal_unit_id INTEGER,
  parent_enterprise_id INTEGER,
  scope public.hierarchy_scope DEFAULT 'all',
  valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
  WITH ordered_data AS (
    SELECT to_jsonb(lu.*)
        || (SELECT public.external_idents_hierarchy(NULL,lu.id,NULL,NULL))
        || CASE WHEN scope IN ('all','tree') THEN (SELECT public.establishment_hierarchy(NULL, lu.id, NULL, scope, valid_on)) ELSE '{}'::JSONB END
        || (SELECT public.activity_hierarchy(NULL,lu.id,valid_on))
        || (SELECT public.location_hierarchy(NULL,lu.id,valid_on))
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.stat_for_unit_hierarchy(NULL,lu.id,valid_on)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.sector_hierarchy(lu.sector_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.unit_size_hierarchy(lu.unit_size_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.status_hierarchy(lu.status_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.legal_form_hierarchy(lu.legal_form_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.contact_hierarchy(NULL,lu.id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.data_source_hierarchy(lu.data_source_id)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.notes_for_unit(NULL,lu.id,NULL,NULL)) ELSE '{}'::JSONB END
        || CASE WHEN scope IN ('all','details') THEN (SELECT public.tag_for_unit_hierarchy(NULL,lu.id,NULL,NULL)) ELSE '{}'::JSONB END
        AS data
    FROM public.legal_unit AS lu
   WHERE (  (legal_unit_id IS NOT NULL AND lu.id = legal_unit_id)
         OR (parent_enterprise_id IS NOT NULL AND lu.enterprise_id = parent_enterprise_id)
         )
     AND lu.valid_after < valid_on AND valid_on <= lu.valid_to
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

CREATE FUNCTION public.enterprise_hierarchy(
  enterprise_id INTEGER,
  scope public.hierarchy_scope DEFAULT 'all',
  valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
    WITH data AS (
        SELECT jsonb_build_object(
                'enterprise',
                 to_jsonb(en.*)
                 || (SELECT public.external_idents_hierarchy(NULL,NULL,en.id,NULL))
                 || CASE WHEN scope IN ('all','tree') THEN (SELECT public.legal_unit_hierarchy(NULL, en.id, scope, valid_on)) ELSE '{}'::JSONB END
                 || CASE WHEN scope IN ('all','tree') THEN (SELECT public.establishment_hierarchy(NULL, NULL, en.id, scope, valid_on)) ELSE '{}'::JSONB END
                 || CASE WHEN scope IN ('all','details') THEN (SELECT public.notes_for_unit(NULL,NULL,en.id,NULL)) ELSE '{}'::JSONB END
                 || CASE WHEN scope IN ('all','details') THEN (SELECT public.tag_for_unit_hierarchy(NULL,NULL,en.id,NULL)) ELSE '{}'::JSONB END
                ) AS data
          FROM public.enterprise AS en
         WHERE enterprise_id IS NOT NULL AND en.id = enterprise_id
         ORDER BY en.short_name
    )
    SELECT COALESCE((SELECT data FROM data),'{}'::JSONB);
$$;


CREATE FUNCTION public.statistical_unit_hierarchy(
  unit_type public.statistical_unit_type,
  unit_id INTEGER,
  scope public.hierarchy_scope DEFAULT 'all',
  valid_on DATE DEFAULT current_date,
  strip_nulls BOOLEAN DEFAULT false
) RETURNS JSONB LANGUAGE sql STABLE AS $$
  WITH result AS (
    SELECT public.enterprise_hierarchy(
      public.statistical_unit_enterprise_id(unit_type, unit_id, valid_on)
      , scope, valid_on
    ) AS data
  )
  SELECT
    CASE
      WHEN strip_nulls THEN jsonb_strip_nulls(result.data)
      ELSE result.data
    END
   FROM result
  ;
$$;


CREATE FUNCTION public.statistical_unit_tree(
    unit_type public.statistical_unit_type,
    unit_id INTEGER,
    valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
    SELECT public.statistical_unit_hierarchy(unit_type, unit_id, 'tree'::public.hierarchy_scope, valid_on);
$$;


CREATE FUNCTION public.statistical_unit_details(
    unit_type public.statistical_unit_type,
    unit_id INTEGER,
    valid_on DATE DEFAULT current_date
) RETURNS JSONB LANGUAGE sql STABLE AS $$
    SELECT CASE
        WHEN unit_type = 'enterprise' THEN public.enterprise_hierarchy(unit_id, 'details', valid_on)
        WHEN unit_type = 'legal_unit' THEN public.legal_unit_hierarchy(unit_id, NULL, 'details', valid_on)
        WHEN unit_type = 'establishment' THEN public.establishment_hierarchy(unit_id, NULL, NULL, 'details', valid_on)
        ELSE '{}'::JSONB
    END;
$$;


CREATE TYPE public.statistical_unit_stats AS (
    unit_type public.statistical_unit_type,
    unit_id integer,
    valid_from date,
    valid_to date,
    stats jsonb,
    stats_summary jsonb
);

CREATE FUNCTION public.statistical_unit_stats(
    unit_type public.statistical_unit_type,
    unit_id INTEGER,
    valid_on DATE DEFAULT current_date
) RETURNS SETOF public.statistical_unit_stats LANGUAGE sql STABLE AS $$
    SELECT unit_type, unit_id, valid_from, valid_to, stats, stats_summary FROM public.relevant_statistical_units(unit_type, unit_id, valid_on);
$$;

END;
