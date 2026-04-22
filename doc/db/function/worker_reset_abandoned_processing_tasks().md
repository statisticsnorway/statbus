```sql
CREATE OR REPLACE FUNCTION worker.reset_abandoned_processing_tasks()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_reset_count int := 0;
    v_task RECORD;
    v_stale_pid INT;
    v_has_pending BOOLEAN;
    v_change_log_count BIGINT;
BEGIN
    FOR v_stale_pid IN
        SELECT pid FROM pg_stat_activity
        WHERE application_name = 'worker'
          AND pid <> pg_backend_pid()
          AND datname = current_database()
    LOOP
        RAISE LOG 'Terminating stale worker PID %', v_stale_pid;
        PERFORM pg_terminate_backend(v_stale_pid);
    END LOOP;

    FOR v_task IN
        SELECT id FROM worker.tasks WHERE state = 'processing'::worker.task_state FOR UPDATE
    LOOP
        UPDATE worker.tasks
        SET state = 'interrupted'::worker.task_state,
            worker_pid = NULL,
            process_start_at = NULL,
            error = NULL,
            process_duration_ms = NULL
        WHERE id = v_task.id;

        v_reset_count := v_reset_count + 1;
    END LOOP;

    SELECT has_pending INTO v_has_pending
    FROM worker.base_change_log_has_pending;

    IF v_has_pending THEN
        SELECT count(*) INTO v_change_log_count
        FROM worker.base_change_log;

        IF v_change_log_count = 0 THEN
            IF NOT EXISTS (
                SELECT 1 FROM worker.tasks
                WHERE command = 'collect_changes'
                  AND state IN ('pending', 'interrupted')
            ) THEN
                RAISE LOG 'Crash recovery: base_change_log_has_pending=TRUE but base_change_log is empty. Spawning full refresh.';
                -- NULL-means-everything direct-mode payload. Keys present,
                -- values NULL → command_collect_changes synthesises ids from
                -- base tables and runs the full phase tree.
                PERFORM worker.spawn(
                    p_command => 'collect_changes',
                    p_payload => jsonb_build_object(
                        'establishment_id_ranges', NULL,
                        'legal_unit_id_ranges',    NULL,
                        'enterprise_id_ranges',    NULL,
                        'power_group_id_ranges',   NULL,
                        'valid_ranges',            NULL
                    )
                );
            END IF;
            UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;
        END IF;
    END IF;

    RETURN v_reset_count;
END;
$function$
```
