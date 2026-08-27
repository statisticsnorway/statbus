BEGIN;

-- STATBUS-267 signal (1): a task in 'processing' with NO LIVE CLAIMANT is
-- reported loudly, from the maintenance queue, every day.
--
-- THE WEDGE THIS ANSWERS. On rune, four derive children sat in 'processing' for
-- six days behind a worker that was perfectly healthy — it ran every other
-- queue, the upgrade reported completed, and the wedge was finally found by a
-- human staring at a progress bar stuck at 91%. Worker-health was the wrong
-- place to look, because the worker WAS healthy.
--
-- WHERE IT RUNS, AND WHY THAT IS THE POINT. The maintenance queue kept running
-- throughout the wedge — its continued health is exactly what made the problem
-- invisible. Putting the detector there turns the mechanism that hid the
-- problem into the one that reports it.

-- ── The predicate ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION worker.abandoned_processing_tasks()
RETURNS TABLE (id bigint, command text, worker_pid integer, process_start_at timestamptz)
LANGUAGE sql
STABLE
AS $abandoned_processing_tasks$
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
$abandoned_processing_tasks$;

COMMENT ON FUNCTION worker.abandoned_processing_tasks() IS
    'Tasks stuck in ''processing'' whose claiming backend no longer exists — '
    'abandoned by definition, no threshold. Read by command_detect_stuck_tasks '
    'and usable directly by an operator investigating a wedge (STATBUS-267).';

-- ── The handler ──────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE worker.command_detect_stuck_tasks(IN payload jsonb, INOUT p_info jsonb DEFAULT NULL::jsonb)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'worker', 'pg_temp'
AS $procedure$
DECLARE
    v_stuck RECORD;
    v_count INT := 0;
    v_ids TEXT := '';
BEGIN
    FOR v_stuck IN SELECT * FROM worker.abandoned_processing_tasks() LOOP
        v_count := v_count + 1;
        v_ids := v_ids || CASE WHEN v_ids = '' THEN '' ELSE ', ' END
                 || v_stuck.id || ' (' || v_stuck.command || ', claimed by dead pid '
                 || v_stuck.worker_pid || ' at ' || v_stuck.process_start_at || ')';
    END LOOP;

    IF v_count = 0 THEN
        -- The Info Principle: report what was actually checked, so a green run
        -- is evidence the detector RAN rather than evidence of nothing.
        p_info := COALESCE(p_info, '{}'::jsonb) || jsonb_build_object('abandoned_processing_tasks', 0);
        RETURN;
    END IF;

    -- ── HOW THIS REPORTS, AND WHAT IT DELIBERATELY DOES NOT DO ───────────────
    --
    -- NOT wired to container health. Health-check wiring would restart the
    -- worker, the startup reset would clear the rows, and the wedge would
    -- silently repair itself — the standing self-heal the King forbids. A
    -- condition that should never occur must reach a HUMAN, and the restart
    -- must be a person's decision.
    --
    -- Two surfaces, because either alone is missable. WARNING reaches the log
    -- immediately and survives the abort below. The EXCEPTION then reddens this
    -- task, which is what an operator reads in worker.tasks and the admin UI —
    -- and because recurrence belongs to the runner (STATBUS-263), a red run
    -- does NOT stop the detector: it runs again tomorrow and says so again.
    -- The finding persists until a human acts, which is the whole intent.
    RAISE WARNING 'STUCK TASKS: % task(s) in ''processing'' with no live claimant: %', v_count, v_ids;

    RAISE EXCEPTION
        'STUCK TASKS DETECTED — % task(s) are in ''processing'' but the backend that claimed each is gone: %. '
        'THIS IS NOT A FAILURE OF THIS CHECK; the check is reporting a real condition it found. '
        'Such a task will never finish on its own, and anything waiting on it waits forever — this is the '
        'STATBUS-262 wedge, which cost six days behind a worker that looked healthy. '
        'A worker restart clears it (startup crash recovery resets abandoned rows), but that decision is '
        'deliberately left to a person: auto-restarting here would repair the symptom silently and this '
        'message would never be read. Inspect first: SELECT * FROM worker.abandoned_processing_tasks();',
        v_count, v_ids;
END;
$procedure$;

-- ── Registration: recurrence is the runner's, via the registry ───────────────
-- Uses the STATBUS-263 mechanism rather than a hand-rolled timer: declare the
-- interval as data, and the worker's runner schedules the next occurrence after
-- every run REGARDLESS OF OUTCOME. That decoupling is what makes a FAILING
-- detector keep reporting instead of silencing itself — the precise property a
-- self-scheduling handler would have destroyed.
INSERT INTO worker.command_registry (command, handler_procedure, description, queue, schedule_interval)
VALUES (
    'detect_stuck_tasks',
    'worker.command_detect_stuck_tasks',
    'Reports tasks stuck in processing with no live claimant (STATBUS-267).',
    'maintenance',
    interval '24 hours'
)
ON CONFLICT (command) DO UPDATE SET
    handler_procedure = EXCLUDED.handler_procedure,
    description       = EXCLUDED.description,
    queue             = EXCLUDED.queue,
    schedule_interval = EXCLUDED.schedule_interval;

-- The per-command dedup index every recurring command must have: it is what
-- makes worker.ensure_recurring_task idempotent, and therefore what lets
-- "schedule the next run" and "seed one if absent" be the same statement
-- (STATBUS-263). Without it the startup seed would insert a duplicate pending
-- row on every boot and the wedge alarm would cry wolf on every healthy start.
-- Asserted by test 096 Property 1b.
CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_detect_stuck_tasks_dedup
    ON worker.tasks (command)
    WHERE command = 'detect_stuck_tasks' AND state = 'pending'::worker.task_state;

-- Seed the first occurrence so the detector starts without waiting for a
-- worker restart. Idempotent through the index just created.
SELECT worker.ensure_recurring_task('detect_stuck_tasks');

END;
