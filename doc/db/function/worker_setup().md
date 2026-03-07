```sql
CREATE OR REPLACE PROCEDURE worker.setup()
 LANGUAGE plpgsql
AS $procedure$
BEGIN
    -- Create base change tracking triggers on all 8 tables
    CALL worker.setup_base_change_triggers();

    -- Create the initial cleanup_tasks task to run daily
    PERFORM worker.enqueue_task_cleanup();
    -- Create the initial import_job_cleanup task to run daily
    PERFORM worker.enqueue_import_job_cleanup();
END;
$procedure$
```
