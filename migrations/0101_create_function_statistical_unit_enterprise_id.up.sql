\echo public.statistical_unit_enterprise_id
CREATE OR REPLACE FUNCTION public.statistical_unit_enterprise_id(unit_type public.statistical_unit_type, unit_id INTEGER, valid_on DATE DEFAULT current_date)
RETURNS INTEGER LANGUAGE sql STABLE AS $$
  SELECT CASE unit_type
         WHEN 'establishment' THEN (
            WITH selected_establishment AS (
                SELECT es.id, es.enterprise_id, es.legal_unit_id, es.valid_from, es.valid_to
                FROM public.establishment AS es
                WHERE es.id = unit_id
                  AND es.valid_after < valid_on AND valid_on <= es.valid_to
            )
            SELECT enterprise_id FROM selected_establishment WHERE enterprise_id IS NOT NULL
            UNION ALL
            SELECT lu.enterprise_id
            FROM selected_establishment AS es
            JOIN public.legal_unit AS lu ON es.legal_unit_id = lu.id
            WHERE lu.valid_after < valid_on AND valid_on <= lu.valid_to
         )
         WHEN 'legal_unit' THEN (
             SELECT lu.enterprise_id
               FROM public.legal_unit AS lu
              WHERE lu.id = unit_id
                AND lu.valid_after < valid_on AND valid_on <= lu.valid_to
         )
         WHEN 'enterprise' THEN (
            -- The same enterprise can be returned multiple times
            -- if it has multiple legal_unit's connected, so use DISTINCT.
            SELECT DISTINCT lu.enterprise_id
              FROM public.legal_unit AS lu
             WHERE lu.enterprise_id = unit_id
               AND lu.valid_after < valid_on AND valid_on <= lu.valid_to
         UNION ALL
            -- The same enterprise can be returned multiple times
            -- if it has multiple establishment's connected, so use DISTINCT.
            SELECT DISTINCT es.enterprise_id
              FROM public.establishment AS es
             WHERE es.enterprise_id = unit_id
               AND es.valid_after < valid_on AND valid_on <= es.valid_to
         )
         WHEN 'enterprise_group' THEN NULL --TODO
         END
  ;
$$;
