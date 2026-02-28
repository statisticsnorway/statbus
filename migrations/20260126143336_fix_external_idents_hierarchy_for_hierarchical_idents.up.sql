-- Migration 20260126143336: fix_external_idents_hierarchy_for_hierarchical_idents
BEGIN;

-- Fix external_idents_hierarchy to include hierarchical identifiers
-- Previously only ei.ident was used, but hierarchical identifiers store data in ei.idents (ltree)
CREATE OR REPLACE FUNCTION public.external_idents_hierarchy(
  parent_establishment_id INTEGER DEFAULT NULL,
  parent_legal_unit_id INTEGER DEFAULT NULL,
  parent_enterprise_id INTEGER DEFAULT NULL,
  parent_power_group_id INTEGER DEFAULT NULL
) RETURNS JSONB LANGUAGE sql STABLE AS $external_idents_hierarchy$
  WITH agg_data AS (
    SELECT jsonb_object_agg(eit.code, COALESCE(ei.ident, ei.idents::text) ORDER BY eit.priority NULLS LAST, eit.code) AS data
     FROM public.external_ident AS ei
     JOIN public.external_ident_type AS eit ON eit.id = ei.type_id
     WHERE (  parent_establishment_id    IS NOT NULL AND ei.establishment_id    = parent_establishment_id
           OR parent_legal_unit_id       IS NOT NULL AND ei.legal_unit_id       = parent_legal_unit_id
           OR parent_enterprise_id       IS NOT NULL AND ei.enterprise_id       = parent_enterprise_id
           OR parent_power_group_id IS NOT NULL AND ei.power_group_id = parent_power_group_id
           )
  )
  SELECT CASE
    WHEN data IS NULL THEN '{}'::JSONB
    ELSE jsonb_build_object('external_idents',data)
    END
  FROM agg_data;
$external_idents_hierarchy$;

END;
