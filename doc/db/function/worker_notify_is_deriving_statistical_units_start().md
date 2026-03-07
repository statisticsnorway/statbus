```sql
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_statistical_units_start()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  INSERT INTO worker.pipeline_progress (phase, step, total, completed, updated_at)
  VALUES ('is_deriving_statistical_units', 'derive_statistical_unit', 0, 0, clock_timestamp())
  ON CONFLICT (phase) DO UPDATE SET
    step = EXCLUDED.step, total = 0, completed = 0,
    -- Don't null counts — they were set by collect_changes and will be
    -- refined by derive_statistical_unit after batching.
    updated_at = clock_timestamp();

  PERFORM pg_notify('worker_status', json_build_object('type', 'is_deriving_statistical_units', 'status', true)::text);
  PERFORM worker.notify_pipeline_progress();
END;
$procedure$
```
