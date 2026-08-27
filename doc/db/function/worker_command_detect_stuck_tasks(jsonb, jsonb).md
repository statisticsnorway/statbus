```sql
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
$procedure$
```
