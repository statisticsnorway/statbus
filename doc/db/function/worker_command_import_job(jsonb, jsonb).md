```sql
CREATE OR REPLACE PROCEDURE worker.command_import_job(IN p_payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'worker', 'admin', 'pg_temp'
AS $procedure$
DECLARE
  v_task_id BIGINT;
BEGIN
  SELECT id INTO v_task_id
  FROM worker.tasks
  WHERE state = 'processing' AND worker_pid = pg_backend_pid()
  ORDER BY id DESC LIMIT 1;

  PERFORM worker.spawn(
    p_command => 'import_job_process',
    p_payload => p_payload,
    p_parent_id => v_task_id,
    p_child_mode => 'serial'
  );
END;
$procedure$
```
