BEGIN;

\echo public.get_external_idents
CREATE FUNCTION public.get_external_idents(
  unit_type public.statistical_unit_type,
  unit_id INTEGER
) RETURNS JSONB LANGUAGE sql STABLE STRICT AS $$
    SELECT jsonb_object_agg(eit.code, ei.ident ORDER BY eit.priority NULLS LAST, eit.code) AS external_idents
    FROM public.external_ident AS ei
    JOIN public.external_ident_type AS eit ON eit.id = ei.type_id
    WHERE
      CASE unit_type
        WHEN 'enterprise' THEN ei.enterprise_id = unit_id
        WHEN 'legal_unit' THEN ei.legal_unit_id = unit_id
        WHEN 'establishment' THEN ei.establishment_id = unit_id
        WHEN 'enterprise_group' THEN ei.enterprise_group_id = unit_id
      END;
$$;


\echo public.enterprise_external_idents
CREATE VIEW public.enterprise_external_idents AS
  SELECT 'enterprise'::public.statistical_unit_type AS unit_type
        , plu.enterprise_id AS unit_id
        , public.get_external_idents('legal_unit', plu.id) AS external_idents
        , plu.valid_after
        , plu.valid_to
  FROM public.legal_unit plu
  WHERE  plu.primary_for_enterprise = true
  UNION ALL
  SELECT 'enterprise'::public.statistical_unit_type AS unit_type
       , pes.enterprise_id AS unit_id
       , public.get_external_idents('establishment', pes.id) AS external_idents
       , pes.valid_after
       , pes.valid_to
  FROM public.establishment pes
  WHERE pes.enterprise_id IS NOT NULL
; -- END public.enterprise_external_idents

END;
