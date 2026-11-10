BEGIN;

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
            -- STATBUS-589: a crash truncated the UNLOGGED change log, so the
            -- changes that were waiting are unknown: derive all units over all
            -- time. A collector already pending or interrupted would read the
            -- empty log and derive nothing; enqueue_derive_statistical_unit_all
            -- turns a pending one into the full request (ON CONFLICT DO UPDATE)
            -- and otherwise adds it beside an interrupted one.
            RAISE LOG 'Crash recovery: base_change_log_has_pending=TRUE but base_change_log is empty. Spawning full refresh.';
            PERFORM worker.enqueue_derive_statistical_unit_all();
            UPDATE worker.base_change_log_has_pending SET has_pending = FALSE WHERE has_pending;
        END IF;
    END IF;

    RETURN v_reset_count;
END;
$function$
;

END;
