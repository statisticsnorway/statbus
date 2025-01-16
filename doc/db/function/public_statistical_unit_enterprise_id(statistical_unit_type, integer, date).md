```sql
CREATE OR REPLACE FUNCTION public.statistical_unit_enterprise_id(unit_type statistical_unit_type, unit_id integer, valid_on date DEFAULT CURRENT_DATE)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE unit_type
         WHEN 'establishment' THEN (
            WITH selected_establishment AS (
                SELECT es.id, es.enterprise_id, es.legal_unit_id, es.valid_from, es.valid_to
                FROM public.establishment AS es
                WHERE es.id = unit_id
                  AND es.valid_after < valid_on AND valid_on <= es.valid_to
            )
            -- Either the establishment has a a direct enterprise connection
            SELECT enterprise_id FROM selected_establishment WHERE enterprise_id IS NOT NULL
            UNION ALL
            -- Or connects to an enterprise through it's legal unit.
            SELECT lu.enterprise_id
            FROM selected_establishment AS es
            JOIN public.legal_unit AS lu ON es.legal_unit_id = lu.id
            WHERE lu.valid_after < valid_on AND valid_on <= lu.valid_to
         )
         WHEN 'legal_unit' THEN (
             -- A legal_unit is always connected to an enterprise.
             SELECT lu.enterprise_id
               FROM public.legal_unit AS lu
              WHERE lu.id = unit_id
                AND lu.valid_after < valid_on AND valid_on <= lu.valid_to
         )
         WHEN 'enterprise' THEN (
            -- Handle both formal (legal unit) and informal (establishment) connections
            -- Return the enterprise ID if it matches either connection type
            SELECT DISTINCT unit_id AS enterprise_id
            FROM (
                SELECT lu.enterprise_id
                FROM public.legal_unit AS lu
                WHERE lu.enterprise_id = unit_id
                  AND lu.valid_after < valid_on AND valid_on <= lu.valid_to
                UNION ALL
                SELECT es.enterprise_id
                FROM public.establishment AS es
                WHERE es.enterprise_id = unit_id
                  AND es.valid_after < valid_on AND valid_on <= es.valid_to
            ) combined_connections
            WHERE enterprise_id IS NOT NULL
         )
         WHEN 'enterprise_group' THEN NULL --TODO
         END
  ;
$function$
```
