-- STATBUS-267 signal (1): a task in 'processing' with no live claimant is
-- reported loudly — and a healthy box stays silent.
--
-- WHY THIS EXISTS. On rune four derive children sat in 'processing' for six
-- days behind a worker that was completely healthy: it ran every other queue,
-- the upgrade reported completed, and a human eventually noticed a progress bar
-- frozen at 91%. Worker-health was the wrong thing to watch, because the worker
-- WAS healthy. The wedge's actual signature is a claimed task whose claimant is
-- gone, and that is cheap to ask directly.
--
-- BOTH ARMS MATTER EQUALLY, and the silent one is not the formality it looks:
-- a detector that fires on healthy state is worse than no detector, because the
-- loudest message in the system becomes the one operators learn to scroll past.
-- The ruling's requirement was ZERO false positives, so "stays silent when
-- healthy" is a first-class assertion here, not a courtesy check.
--
-- WHY THE PREDICATE NEEDS NO THRESHOLD. A task claims a backend by writing
-- worker_pid = pg_backend_pid(). If that backend is gone, the task is abandoned
-- by definition — no per-command duration table to maintain, nothing to tune,
-- and no argument about what "too long" means for a given command.
--
-- BOUNDARY: this pins the DATABASE side — the predicate and the handler's two
-- outcomes. That the runner SCHEDULES it every day is the STATBUS-263 mechanism
-- this rides on, pinned by test 096.
--
-- Everything runs in one transaction and is rolled back.

\set QUIET on
-- ON_ERROR_STOP stays off: the loud arm below RAISES by design, and the test
-- must continue past it to assert the state afterwards.
\set ON_ERROR_STOP off

BEGIN;

-- Determinism for the asserted message. The handler's text embeds the stuck
-- task's process_start_at — operationally valuable ("stuck since when") and
-- therefore worth asserting — so the test must fix BOTH the value and its
-- rendering. A literal timestamp alone is not enough: timestamptz renders in
-- the session's zone, so an expected file generated here would diff on a CI
-- runner in another zone. Pinning the zone makes the assertion portable.
SET LOCAL TimeZone = 'UTC';

\echo '=== ARM 1: a HEALTHY box reports nothing ==='
-- The detector must see the tasks this suite's own database contains and find
-- nothing abandoned. Asserting zero here (rather than seeding a clean fixture)
-- means a predicate that over-matches would fail on real data, which is the
-- direction that matters.
SELECT count(*) AS abandoned_on_a_healthy_box FROM worker.abandoned_processing_tasks();

\echo '=== ARM 1b: the handler is SILENT and reports what it checked ==='
CALL worker.command_detect_stuck_tasks('{}'::jsonb, NULL);

\echo '=== ARM 2: a task claimed by a LIVE backend is NOT abandoned ==='
-- The distinction the whole detector rests on. This row is in 'processing' and
-- looks exactly like the wedge — except its claimant is alive, because it is
-- THIS session. A predicate keyed on "processing for a while" would flag it;
-- one keyed on liveness must not.
INSERT INTO worker.tasks (id, command, state, worker_pid, process_start_at)
VALUES (999267001, 'task_cleanup', 'processing', pg_backend_pid(), '2026-01-01 00:00:00+00'::timestamptz);

SELECT count(*) AS abandoned_while_claimant_is_alive
FROM worker.abandoned_processing_tasks() WHERE id = 999267001;

\echo '=== ARM 3: the SAME row, claimant dead, IS abandoned ==='
-- Only one thing changes: the claiming pid becomes one that does not exist.
-- Age is untouched (the row is dated 2026-01-01 either way) — proving the
-- signal is liveness, not duration.
UPDATE worker.tasks SET worker_pid = 2147483647 WHERE id = 999267001;

SELECT id, command, worker_pid
FROM worker.abandoned_processing_tasks() WHERE id = 999267001;

\echo '=== ARM 4: the handler REFUSES LOUDLY, naming the task ==='
-- Deliberately a raise, not a return value: the message must reach a human. It
-- is asserted here in full so a future edit that softens it into silence — the
-- exact failure this ticket exists to prevent — cannot pass.
-- expected to fail: STUCK TASKS DETECTED is the detector working, not breaking
SAVEPOINT sp_stuck;
CALL worker.command_detect_stuck_tasks('{}'::jsonb, NULL);
ROLLBACK TO SAVEPOINT sp_stuck;

\echo '=== ARM 5: the row still stands — detection does NOT repair ==='
-- The King forbids standing self-heal paths. The detector reports; a human
-- decides. If this ever returns 0, detection has quietly become remediation.
SELECT count(*) AS still_stuck_after_detection
FROM worker.abandoned_processing_tasks() WHERE id = 999267001;

ROLLBACK;

\echo '=== CLEANUP: rolled back, nothing seeded survives ==='
SELECT count(*) AS seeded_rows_left_behind FROM worker.tasks WHERE id = 999267001;
