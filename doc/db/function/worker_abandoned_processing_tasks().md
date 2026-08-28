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
    -- application_name = 'worker'.
    --
    -- Both directions are real, and they are NOT symmetric:
    --
    --   LOOSE (this) risks a FALSE NEGATIVE — a dead claimant's pid reused by
    --   an unrelated backend in this database reads as alive, hiding one
    --   abandoned task for one run.
    --
    --   STRICT (adding application_name) risks a FALSE POSITIVE — if a worker
    --   backend ever failed to set its application_name, a RUNNING task would
    --   be reported abandoned, at EXCEPTION level.
    --
    -- The asymmetry that settles it is about TIME, not likelihood. THE FALSE
    -- NEGATIVE SELF-CORRECTS UNDER RECURRENCE: tomorrow's run re-evaluates
    -- against a different set of live backends, and pid reuse will not repeat
    -- for the same row. THE FALSE POSITIVE DOES NOT DECAY: an EXCEPTION-level
    -- false alarm teaches operators to ignore the one message built to be
    -- unignorable, and that damage persists long after the bug is fixed.
    --
    -- COUPLING — THIS CHOICE IS LICENSED BY RECURRENCE, NOT FREE.
    -- The looseness is only acceptable because this detector runs again
    -- tomorrow, which is what turns a false negative into a delay rather than a
    -- miss. IF THIS DETECTOR EVER BECOMES ONE-SHOT, or leaves the recurring
    -- maintenance family (schedule_interval removed, moved to a manual command,
    -- invoked only from install or upgrade), THE application_name DECISION MUST
    -- BE REVISITED — without a second run there is no correction, and a hidden
    -- wedge stops being a delayed report and becomes a permanent silence.
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
