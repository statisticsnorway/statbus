```sql
CREATE OR REPLACE PROCEDURE worker.pipeline_progress_on_child_completed(IN p_phase worker.pipeline_phase, IN p_parent_task_id bigint)
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    UPDATE worker.pipeline_progress
    SET completed = completed + 1,
        updated_at = clock_timestamp()
    WHERE phase = p_phase;

    PERFORM pg_notify('worker_status',
        json_build_object(
            'type', 'pipeline_progress',
            'phases', COALESCE(
                (SELECT json_agg(json_build_object(
                    'phase', pp.phase, 'step', pp.step,
                    'total', pp.total, 'completed', pp.completed,
                    'affected_establishment_count', pp.affected_establishment_count,
                    'affected_legal_unit_count', pp.affected_legal_unit_count,
                    'affected_enterprise_count', pp.affected_enterprise_count,
                    'affected_power_group_count', pp.affected_power_group_count
                )) FROM worker.pipeline_progress AS pp),
                '[]'::json
            )
        )::text
    );
END;
$procedure$
```
