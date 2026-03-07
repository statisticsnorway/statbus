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
    -- Terminate all other lingering worker backends FOR THIS DATABASE ONLY.
    FOR v_stale_pid IN
        SELECT pid FROM pg_stat_activity
        WHERE application_name = 'worker'
          AND pid <> pg_backend_pid()
          AND datname = current_database()
    LOOP
        RAISE LOG 'Terminating stale worker PID %', v_stale_pid;
        PERFORM pg_terminate_backend(v_stale_pid);
    END LOOP;

    -- Find tasks stuck in 'processing' and reset their status to 'pending'.
    FOR v_task IN
        SELECT id FROM worker.tasks WHERE state = 'processing'::worker.task_state FOR UPDATE
    LOOP
        UPDATE worker.tasks
        SET state = 'pending'::worker.task_state,
            worker_pid = NULL,
            processed_at = NULL,
            error = NULL,
            duration_ms = NULL
        WHERE id = v_task.id;

        v_reset_count := v_reset_count + 1;
    END LOOP;

    -- CRASH RECOVERY: Detect if UNLOGGED base_change_log was truncated by PG crash.
    -- If has_pending = TRUE (LOGGED, survives crash) but base_change_log is empty
    -- (UNLOGGED, truncated on unclean shutdown), we lost change data.
    -- Enqueue a full refresh to recover.
    SELECT has_pending INTO v_has_pending
    FROM worker.base_change_log_has_pending;

    IF v_has_pending THEN
        SELECT count(*) INTO v_change_log_count
        FROM worker.base_change_log;

        IF v_change_log_count = 0 THEN
            -- UNLOGGED data was lost in crash - enqueue full refresh
            RAISE LOG 'Crash recovery: base_change_log_has_pending=TRUE but base_change_log is empty. Enqueueing full refresh.';
            PERFORM worker.enqueue_derive_statistical_unit(
                p_establishment_id_ranges := '{(,)}'::int4multirange,
                p_legal_unit_id_ranges := '{(,)}'::int4multirange,
                p_enterprise_id_ranges := '{(,)}'::int4multirange,
                p_valid_from := '-infinity'::DATE,
                p_valid_until := 'infinity'::DATE
            );
            UPDATE worker.base_change_log_has_pending SET has_pending = FALSE;
        END IF;
    END IF;

    RETURN v_reset_count;
END;
$function$
```
