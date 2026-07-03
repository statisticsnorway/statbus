-- Down Migration 20260703111119: power_group_hierarchy_shape_a_b_statbus_125
--
-- Removes the Shape A/B power-group hierarchy functions and restores the
-- original (pre-primary_only) definitions dumped from the live database.
BEGIN;

DROP FUNCTION public.statistical_unit_hierarchy(statistical_unit_type, integer, hierarchy_scope, date, boolean, boolean);
DROP FUNCTION public.enterprise_hierarchy(integer, hierarchy_scope, date, boolean);
DROP FUNCTION public.legal_unit_hierarchy(integer, integer, hierarchy_scope, date, boolean);
DROP FUNCTION public.power_group_hierarchy(integer, hierarchy_scope, date, boolean);
DROP FUNCTION public.power_group_membership_hierarchy(integer, date, boolean);
DROP FUNCTION public.power_group_link(integer, integer, integer, date);

CREATE OR REPLACE FUNCTION public.legal_unit_hierarchy(legal_unit_id integer, parent_enterprise_id integer, scope hierarchy_scope DEFAULT 'all'::hierarchy_scope, valid_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.enterprise_hierarchy(enterprise_id integer, scope hierarchy_scope DEFAULT 'all'::hierarchy_scope, valid_on date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.statistical_unit_hierarchy(unit_type statistical_unit_type, unit_id integer, scope hierarchy_scope DEFAULT 'all'::hierarchy_scope, valid_on date DEFAULT CURRENT_DATE, strip_nulls boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.statistical_unit_details(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $statistical_unit_details$
    SELECT CASE
        WHEN unit_type = 'enterprise' THEN public.enterprise_hierarchy(unit_id, 'details', valid_on)
        WHEN unit_type = 'legal_unit' THEN public.legal_unit_hierarchy(unit_id, NULL, 'details', valid_on)
        WHEN unit_type = 'establishment' THEN public.establishment_hierarchy(unit_id, NULL, NULL, 'details', valid_on)
        ELSE '{}'::JSONB
    END;
$statistical_unit_details$;

END;
