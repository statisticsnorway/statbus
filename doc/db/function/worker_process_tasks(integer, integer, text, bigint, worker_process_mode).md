```sql
CREATE OR REPLACE PROCEDURE worker.process_tasks(IN p_batch_size integer DEFAULT NULL::integer, IN p_max_runtime_ms integer DEFAULT NULL::integer, IN p_queue text DEFAULT NULL::text, IN p_max_priority bigint DEFAULT NULL::bigint, IN p_mode worker.process_mode DEFAULT NULL::worker.process_mode)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
  task_record RECORD;
  start_time TIMESTAMPTZ;
  batch_start_time TIMESTAMPTZ;
  elapsed_ms NUMERIC;
  processed_count INT := 0;
  v_inside_transaction BOOLEAN;
  v_waiting_concurrent_parent_id BIGINT;
  v_waiting_serial_parent_id BIGINT;
  v_max_retries CONSTANT INT := 3;
  v_retry_count INT;
  v_backoff_base_ms CONSTANT NUMERIC := 100;
BEGIN
  SELECT pg_current_xact_id_if_assigned() IS NOT NULL INTO v_inside_transaction;
  RAISE DEBUG 'Running worker.process_tasks inside transaction: %, queue: %, mode: %',
    v_inside_transaction, p_queue, COALESCE(p_mode::text, 'NULL');

  batch_start_time := clock_timestamp();

  LOOP
    IF p_max_runtime_ms IS NOT NULL AND
       EXTRACT(EPOCH FROM (clock_timestamp() - batch_start_time)) * 1000 > p_max_runtime_ms THEN
      EXIT;
    END IF;

    SELECT t.id
    INTO v_waiting_concurrent_parent_id
    FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON t.command = cr.command
    WHERE t.state = 'waiting'::worker.task_state
      AND t.child_mode = 'concurrent'
      AND (p_queue IS NULL OR cr.queue = p_queue)
    ORDER BY t.depth DESC, t.priority, t.id
    LIMIT 1;

    SELECT t.id
    INTO v_waiting_serial_parent_id
    FROM worker.tasks AS t
    JOIN worker.command_registry AS cr ON t.command = cr.command
    WHERE t.state = 'waiting'::worker.task_state
      AND t.child_mode = 'serial'
      AND (p_queue IS NULL OR cr.queue = p_queue)
      AND NOT EXISTS (
        SELECT 1 FROM worker.tasks AS sib
        WHERE sib.parent_id = t.id
          AND sib.state IN ('processing', 'waiting')
      )
    ORDER BY t.depth DESC, t.priority, t.id
    LIMIT 1;

    IF p_mode = 'serial' THEN
      IF v_waiting_concurrent_parent_id IS NOT NULL THEN
        RAISE DEBUG 'Serial mode: concurrent parent % exists, returning to Crystal',
          v_waiting_concurrent_parent_id;
        EXIT;
      END IF;

      IF v_waiting_serial_parent_id IS NOT NULL THEN
        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
        INTO task_record
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE t.state IN ('interrupted'::worker.task_state, 'pending'::worker.task_state)
          AND t.parent_id = v_waiting_serial_parent_id
          AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
          AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
        ORDER BY CASE WHEN t.state = 'interrupted' THEN 0 ELSE 1 END, t.priority ASC NULLS LAST, t.id
        LIMIT 1
        FOR UPDATE OF t SKIP LOCKED;
      END IF;

      IF NOT FOUND OR v_waiting_serial_parent_id IS NULL THEN
        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
        INTO task_record
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE t.state IN ('interrupted'::worker.task_state, 'pending'::worker.task_state)
          AND t.parent_id IS NULL
          AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
          AND (p_queue IS NULL OR cr.queue = p_queue)
          AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
        ORDER BY
          CASE WHEN t.state = 'interrupted' THEN 0 ELSE 1 END,
          CASE WHEN t.scheduled_at IS NULL THEN 0 ELSE 1 END,
          t.scheduled_at,
          t.priority ASC NULLS LAST,
          t.id
        LIMIT 1
        FOR UPDATE OF t SKIP LOCKED;
      END IF;

    ELSIF p_mode = 'concurrent' THEN
      IF v_waiting_concurrent_parent_id IS NULL THEN
        RAISE DEBUG 'Concurrent mode: no concurrent waiting parent, returning';
        EXIT;
      END IF;

      SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
      INTO task_record
      FROM worker.tasks AS t
      JOIN worker.command_registry AS cr ON t.command = cr.command
      WHERE t.state IN ('interrupted'::worker.task_state, 'pending'::worker.task_state)
        AND t.parent_id = v_waiting_concurrent_parent_id
        AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
        AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
      ORDER BY CASE WHEN t.state = 'interrupted' THEN 0 ELSE 1 END, t.priority ASC NULLS LAST, t.id
      LIMIT 1
      FOR UPDATE OF t SKIP LOCKED;

    ELSE
      IF v_waiting_concurrent_parent_id IS NOT NULL THEN
        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
        INTO task_record
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE t.state IN ('interrupted'::worker.task_state, 'pending'::worker.task_state)
          AND t.parent_id = v_waiting_concurrent_parent_id
          AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
          AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
        ORDER BY CASE WHEN t.state = 'interrupted' THEN 0 ELSE 1 END, t.priority ASC NULLS LAST, t.id
        LIMIT 1
        FOR UPDATE OF t SKIP LOCKED;
      END IF;

      IF (v_waiting_concurrent_parent_id IS NULL OR NOT FOUND) AND v_waiting_serial_parent_id IS NOT NULL THEN
        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
        INTO task_record
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE t.state IN ('interrupted'::worker.task_state, 'pending'::worker.task_state)
          AND t.parent_id = v_waiting_serial_parent_id
          AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
          AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
        ORDER BY CASE WHEN t.state = 'interrupted' THEN 0 ELSE 1 END, t.priority ASC NULLS LAST, t.id
        LIMIT 1
        FOR UPDATE OF t SKIP LOCKED;
      END IF;

      IF (v_waiting_concurrent_parent_id IS NULL AND v_waiting_serial_parent_id IS NULL) OR NOT FOUND THEN
        SELECT t.*, cr.handler_procedure, cr.before_procedure, cr.after_procedure, cr.queue
        INTO task_record
        FROM worker.tasks AS t
        JOIN worker.command_registry AS cr ON t.command = cr.command
        WHERE t.state IN ('interrupted'::worker.task_state, 'pending'::worker.task_state)
          AND t.parent_id IS NULL
          AND (t.scheduled_at IS NULL OR t.scheduled_at <= clock_timestamp())
          AND (p_queue IS NULL OR cr.queue = p_queue)
          AND (p_max_priority IS NULL OR t.priority <= p_max_priority)
        ORDER BY
          CASE WHEN t.state = 'interrupted' THEN 0 ELSE 1 END,
          CASE WHEN t.scheduled_at IS NULL THEN 0 ELSE 1 END,
          t.scheduled_at,
          t.priority ASC NULLS LAST,
          t.id
        LIMIT 1
        FOR UPDATE OF t SKIP LOCKED;
      END IF;
    END IF;

    IF NOT FOUND THEN
      EXIT;
    END IF;

    start_time := clock_timestamp();

    UPDATE worker.tasks AS t
    SET state = 'processing'::worker.task_state,
        worker_pid = pg_backend_pid(),
        process_start_at = start_time
    WHERE t.id = task_record.id;

    IF task_record.before_procedure IS NOT NULL THEN
      BEGIN
        EXECUTE format('CALL %s()', task_record.before_procedure);
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Error in before_procedure % for task %: %', task_record.before_procedure, task_record.id, SQLERRM;
      END;
    END IF;

    IF NOT v_inside_transaction THEN
      COMMIT;
    END IF;

    DECLARE
      v_state worker.task_state;
      v_process_stop_at TIMESTAMPTZ;
      v_completed_at TIMESTAMPTZ;
      v_process_duration_ms NUMERIC;
      v_completion_duration_ms NUMERIC;
      v_error TEXT DEFAULT NULL;
      v_has_children BOOLEAN;
      v_handler_info JSONB;
    BEGIN
      v_retry_count := 0;

      <<retry_loop>>
      LOOP
        DECLARE
          v_message_text TEXT;
          v_pg_exception_detail TEXT;
          v_pg_exception_hint TEXT;
          v_pg_exception_context TEXT;
        BEGIN
          IF task_record.handler_procedure IS NOT NULL THEN
            -- INOUT protocol: EXECUTE INTO captures the INOUT return value;
            -- plain EXECUTE USING does NOT capture INOUT in PG.
            EXECUTE format('CALL %s($1, $2)', task_record.handler_procedure)
            INTO v_handler_info
            USING task_record.payload, NULL::jsonb;
          ELSE
            RAISE EXCEPTION 'No handler procedure found for command: %', task_record.command;
          END IF;

          v_process_stop_at := clock_timestamp();
          v_process_duration_ms := EXTRACT(EPOCH FROM (v_process_stop_at - start_time)) * 1000;

          SELECT EXISTS (
            SELECT 1 FROM worker.tasks WHERE parent_id = task_record.id
          ) INTO v_has_children;

          IF v_has_children THEN
            v_state := 'waiting'::worker.task_state;
            v_completed_at := NULL;
            v_completion_duration_ms := NULL;
          ELSE
            v_state := 'completed'::worker.task_state;
            v_completed_at := clock_timestamp();
            v_completion_duration_ms := EXTRACT(EPOCH FROM (v_completed_at - start_time)) * 1000;
          END IF;

          EXIT retry_loop;

        EXCEPTION
          WHEN deadlock_detected THEN
            v_retry_count := v_retry_count + 1;
            IF v_retry_count <= v_max_retries THEN
              RAISE WARNING 'Task % (%) deadlock detected, retry %/%',
                task_record.id, task_record.command, v_retry_count, v_max_retries;
              PERFORM pg_sleep((v_backoff_base_ms * power(2, v_retry_count - 1) + (random() * 50)) / 1000.0);
              CONTINUE retry_loop;
            END IF;

            v_process_stop_at := clock_timestamp();
            v_state := 'failed'::worker.task_state;
            v_completed_at := v_process_stop_at;
            v_process_duration_ms := EXTRACT(EPOCH FROM (v_process_stop_at - start_time)) * 1000;
            v_completion_duration_ms := v_process_duration_ms;
            v_error := format('Deadlock detected after %s retries', v_retry_count);
            EXIT retry_loop;

          WHEN serialization_failure THEN
            v_retry_count := v_retry_count + 1;
            IF v_retry_count <= v_max_retries THEN
              RAISE WARNING 'Task % (%) serialization failure, retry %/%',
                task_record.id, task_record.command, v_retry_count, v_max_retries;
              PERFORM pg_sleep((v_backoff_base_ms * power(2, v_retry_count - 1) + (random() * 50)) / 1000.0);
              CONTINUE retry_loop;
            END IF;

            v_process_stop_at := clock_timestamp();
            v_state := 'failed'::worker.task_state;
            v_completed_at := v_process_stop_at;
            v_process_duration_ms := EXTRACT(EPOCH FROM (v_process_stop_at - start_time)) * 1000;
            v_completion_duration_ms := v_process_duration_ms;
            v_error := format('Serialization failure after %s retries', v_retry_count);
            EXIT retry_loop;

          WHEN OTHERS THEN
            v_process_stop_at := clock_timestamp();
            v_state := 'failed'::worker.task_state;
            v_completed_at := v_process_stop_at;
            v_process_duration_ms := EXTRACT(EPOCH FROM (v_process_stop_at - start_time)) * 1000;
            v_completion_duration_ms := v_process_duration_ms;

            GET STACKED DIAGNOSTICS
              v_message_text = MESSAGE_TEXT,
              v_pg_exception_detail = PG_EXCEPTION_DETAIL,
              v_pg_exception_hint = PG_EXCEPTION_HINT,
              v_pg_exception_context = PG_EXCEPTION_CONTEXT;

            v_error := format(
              'Error: %s%sContext: %s%sDetail: %s%sHint: %s',
              v_message_text, E'\n',
              v_pg_exception_context, E'\n',
              COALESCE(v_pg_exception_detail, ''), E'\n',
              COALESCE(v_pg_exception_hint, '')
            );

            RAISE WARNING 'Task % (%) failed in % ms: %', task_record.id, task_record.command, v_process_duration_ms, v_error;
            EXIT retry_loop;
        END;
      END LOOP retry_loop;

      -- Post-handler UPDATE now includes info from INOUT
      UPDATE worker.tasks AS t
      SET state = v_state,
          process_stop_at = v_process_stop_at,
          completed_at = v_completed_at,
          process_duration_ms = v_process_duration_ms,
          completion_duration_ms = v_completion_duration_ms,
          error = v_error,
          info = COALESCE(t.info, '{}'::jsonb) || COALESCE(v_handler_info, '{}'::jsonb)
      WHERE t.id = task_record.id;

      IF v_state = 'failed' THEN
        PERFORM worker.cascade_fail_descendants(task_record.id);
      END IF;

      IF v_inside_transaction AND task_record.parent_id IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        PERFORM worker.complete_parent_if_ready(task_record.id);
      END IF;

      IF task_record.after_procedure IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        BEGIN
          EXECUTE format('CALL %s()', task_record.after_procedure);
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'Error in after_procedure % for task %: %', task_record.after_procedure, task_record.id, SQLERRM;
        END;
      END IF;

      IF NOT v_inside_transaction THEN
        COMMIT;
      END IF;

      IF NOT v_inside_transaction AND task_record.parent_id IS NOT NULL AND v_state IN ('completed', 'failed') THEN
        PERFORM worker.complete_parent_if_ready(task_record.id);
        COMMIT;
      END IF;

      IF task_record.queue = 'analytics' THEN
        PERFORM worker.notify_task_progress();
        IF NOT v_inside_transaction THEN
          COMMIT;
        END IF;
      END IF;
    END;

    processed_count := processed_count + 1;
    IF p_batch_size IS NOT NULL AND processed_count >= p_batch_size THEN
      EXIT;
    END IF;
  END LOOP;
END;
$procedure$
```
