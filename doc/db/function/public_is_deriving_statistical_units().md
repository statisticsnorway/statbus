```sql
CREATE OR REPLACE FUNCTION public.is_deriving_statistical_units()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT jsonb_build_object(
    'active', pp.phase IS NOT NULL,
    'step', pp.step,
    'total', COALESCE(pp.total, 0),
    'completed', COALESCE(pp.completed, 0),
    'affected_establishment_count', pp.affected_establishment_count,
    'affected_legal_unit_count', pp.affected_legal_unit_count,
    'affected_enterprise_count', pp.affected_enterprise_count,
    'affected_power_group_count', pp.affected_power_group_count
  )
  FROM (SELECT NULL) AS dummy
  LEFT JOIN worker.pipeline_progress AS pp ON pp.phase = 'is_deriving_statistical_units';
$function$
```
