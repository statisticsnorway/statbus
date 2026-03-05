```sql
CREATE OR REPLACE PROCEDURE worker.notify_collecting_changes_start()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  INSERT INTO worker.pipeline_progress (phase, step, total, completed, updated_at)
  VALUES ('is_deriving_statistical_units', 'collect_changes', 0, 0, clock_timestamp())
  ON CONFLICT (phase) DO UPDATE SET
    step = 'collect_changes', total = 0, completed = 0,
    affected_establishment_count = NULL, affected_legal_unit_count = NULL,
    affected_enterprise_count = NULL, affected_power_group_count = NULL,
    updated_at = clock_timestamp();

  PERFORM pg_notify('worker_status',
    json_build_object('type', 'is_deriving_statistical_units', 'status', true)::text
  );
END;
$procedure$
```
