```sql
CREATE OR REPLACE FUNCTION worker.notify_pipeline_progress()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM pg_notify('worker_status', (
        SELECT json_build_object(
            'type', 'pipeline_progress',
            'phases', COALESCE(json_agg(json_build_object(
                'phase', pp.phase,
                'step', pp.step,
                'total', pp.total,
                'completed', pp.completed,
                'affected_establishment_count', pp.affected_establishment_count,
                'affected_legal_unit_count', pp.affected_legal_unit_count,
                'affected_enterprise_count', pp.affected_enterprise_count,
                'affected_power_group_count', pp.affected_power_group_count
            )), '[]'::json)
        )::text
        FROM worker.pipeline_progress AS pp
    ));
END;
$function$
```
