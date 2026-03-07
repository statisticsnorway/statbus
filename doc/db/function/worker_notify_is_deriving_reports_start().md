```sql
CREATE OR REPLACE PROCEDURE worker.notify_is_deriving_reports_start()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
  -- UPSERT phase row: resets progress but preserves unit counts
  -- (counts were pre-populated by derive_statistical_unit)
  INSERT INTO worker.pipeline_progress (phase, step, total, completed, updated_at)
  VALUES ('is_deriving_reports', 'derive_reports', 0, 0, clock_timestamp())
  ON CONFLICT (phase) DO UPDATE SET
    step = EXCLUDED.step, total = 0, completed = 0,
    updated_at = clock_timestamp();

  PERFORM pg_notify('worker_status', json_build_object('type', 'is_deriving_reports', 'status', true)::text);
END;
$procedure$
```
