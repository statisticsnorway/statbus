```sql
CREATE OR REPLACE FUNCTION worker.abandoned_processing_tasks()
 RETURNS TABLE(id bigint, command text, worker_pid integer, process_start_at timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
    -- A task claims a backend by writing worker_pid = pg_backend_pid()
    -- (worker.process_tasks). So a 'processing' row whose claiming backend is
    -- GONE was abandoned — by definition, with no threshold to tune and no
    -- per-command table to maintain. This is the ticket's own phrase, "no live
    -- claimant", asked directly.
    --
    -- ZERO FALSE POSITIVES IS THE RULING'S REQUIREMENT, and it decides one
    -- detail: the liveness test matches on pid + database only, NOT also on
    -- application_name = 'worker'. If a worker backend ever failed to set its
    -- application_name, the stricter form would report a RUNNING task as
    -- abandoned. The looser form's cost is the opposite and far cheaper: a
    -- recycled pid held by some other backend in this database could mask one
    -- abandoned task, delaying a report that recurs daily anyway.
    --
    -- Given a choice between a missed detection and a false alarm at the
    -- loudest level, the false alarm is worse: it trains operators to ignore
    -- the one message that is supposed to be unignorable.
    SELECT t.id, t.command, t.worker_pid, t.process_start_at
    FROM worker.tasks AS t
    WHERE t.state = 'processing'::worker.task_state
      AND t.worker_pid IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM pg_stat_activity AS a
          WHERE a.pid = t.worker_pid
            AND a.datname = current_database()
      )
    ORDER BY t.process_start_at;
$function$
```
