```sql
CREATE OR REPLACE FUNCTION worker.partial_change_set_size(p_establishment_id_ranges int4multirange, p_legal_unit_id_ranges int4multirange, p_enterprise_id_ranges int4multirange)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT LEAST(8000, GREATEST(1000, ceil(c.units::numeric / (4 * GREATEST(1, w.workers)))::integer))
    FROM (SELECT coalesce(sum(upper(r) - lower(r)), 0) AS units
          FROM (SELECT unnest(coalesce(p_establishment_id_ranges, '{}'::int4multirange)) AS r
                UNION ALL SELECT unnest(coalesce(p_legal_unit_id_ranges, '{}'::int4multirange))
                UNION ALL SELECT unnest(coalesce(p_enterprise_id_ranges, '{}'::int4multirange))) AS rs) AS c,
         (SELECT coalesce((SELECT q.default_concurrency FROM worker.queue_registry AS q WHERE q.queue = 'analytics'), 1) AS workers) AS w;
$function$
```
