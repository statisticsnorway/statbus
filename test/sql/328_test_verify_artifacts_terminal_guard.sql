-- Test: verifyArtifacts/markCIImagesFailed terminal-state guard.
--
-- Bug this regression covers (observed on statbus_dev pre-rc.63):
--   verifyArtifacts called markCIImagesFailed on a row whose state was
--   already terminal (e.g. 'completed'). The UPDATE transitioning
--   docker_images_status='failed' errored with chk_upgrade_state_attributes
--   and fired INVARIANT CI_FAILURE_DETECTED_TRANSITIONS_ROW as a false
--   positive. Fix: include a `state NOT IN (terminal…)` filter in the
--   UPDATE WHERE clause so terminal rows are silently skipped (0 rows
--   affected), not error-escalated.
--
-- Test strategy: for each terminal state, insert a row with
-- docker_images_status='building' and invoke the guarded UPDATE that
-- markCIImagesFailed uses. Verify that docker_images_status stays
-- 'building' for every terminal row, and transitions to 'failed'
-- only on the non-terminal happy-path row. No timestamps in the
-- assertion output — deterministic.
--
-- Shared-test harness: BEGIN/ROLLBACK for cloned-template isolation.

BEGIN;

TRUNCATE public.upgrade RESTART IDENTITY;

-- Terminal-state fixtures. Each carries docker_images_status='building'.
-- Fixed timestamps (2025-01-01) keep fixtures deterministic.
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, docker_images_status, completed_at, log_relative_file_path) VALUES
  (lpad(to_hex(1), 40, '0'), '2025-01-01 00:00:00+00', 'release', 'completed',
   'terminal completed', ARRAY['v2026.01.0'], 'building', '2025-01-01 01:00:00+00', 'log.txt');

INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, docker_images_status, scheduled_at, started_at, error) VALUES
  (lpad(to_hex(2), 40, '0'), '2025-01-01 00:00:00+00', 'release', 'failed',
   'terminal failed', ARRAY['v2026.02.0'], 'building', '2025-01-01 00:30:00+00', '2025-01-01 00:45:00+00', 'simulated failure');

INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, docker_images_status, scheduled_at, started_at, error, rolled_back_at) VALUES
  (lpad(to_hex(3), 40, '0'), '2025-01-01 00:00:00+00', 'release', 'rolled_back',
   'terminal rolled_back', ARRAY['v2026.03.0'], 'building', '2025-01-01 00:30:00+00', '2025-01-01 00:45:00+00', 'simulated rollback', '2025-01-01 01:00:00+00');

INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, docker_images_status, skipped_at) VALUES
  (lpad(to_hex(4), 40, '0'), '2025-01-01 00:00:00+00', 'release', 'skipped',
   'terminal skipped', ARRAY['v2026.04.0'], 'building', '2025-01-01 01:00:00+00');

INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, docker_images_status, scheduled_at, started_at, error, dismissed_at) VALUES
  (lpad(to_hex(5), 40, '0'), '2025-01-01 00:00:00+00', 'release', 'dismissed',
   'terminal dismissed', ARRAY['v2026.05.0'], 'building', '2025-01-01 00:30:00+00', '2025-01-01 00:45:00+00', 'simulated dismiss', '2025-01-01 01:00:00+00');

INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, docker_images_status, superseded_at) VALUES
  (lpad(to_hex(6), 40, '0'), '2025-01-01 00:00:00+00', 'release', 'superseded',
   'terminal superseded', ARRAY['v2026.06.0'], 'building', '2025-01-01 01:00:00+00');

-- Non-terminal happy-path: state='available', docker_images_status='building'.
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, docker_images_status) VALUES
  (lpad(to_hex(7), 40, '0'), '2025-01-01 00:00:00+00', 'release', 'available',
   'happy path available', ARRAY['v2026.07.0'], 'building');

\echo '=== rows before guarded UPDATE ==='
SELECT id, state, docker_images_status FROM public.upgrade ORDER BY id;

-- Apply the guarded UPDATE to each row in sequence. The `state NOT IN (…)`
-- filter must skip every terminal row (UPDATE 0) while letting the
-- non-terminal row through (UPDATE 1).
UPDATE public.upgrade
   SET docker_images_status = 'failed', error = 'test-fire'
 WHERE id = 1 AND docker_images_status = 'building'
   AND state NOT IN ('completed', 'failed', 'rolled_back', 'skipped', 'dismissed', 'superseded');
UPDATE public.upgrade
   SET docker_images_status = 'failed', error = 'test-fire'
 WHERE id = 2 AND docker_images_status = 'building'
   AND state NOT IN ('completed', 'failed', 'rolled_back', 'skipped', 'dismissed', 'superseded');
UPDATE public.upgrade
   SET docker_images_status = 'failed', error = 'test-fire'
 WHERE id = 3 AND docker_images_status = 'building'
   AND state NOT IN ('completed', 'failed', 'rolled_back', 'skipped', 'dismissed', 'superseded');
UPDATE public.upgrade
   SET docker_images_status = 'failed', error = 'test-fire'
 WHERE id = 4 AND docker_images_status = 'building'
   AND state NOT IN ('completed', 'failed', 'rolled_back', 'skipped', 'dismissed', 'superseded');
UPDATE public.upgrade
   SET docker_images_status = 'failed', error = 'test-fire'
 WHERE id = 5 AND docker_images_status = 'building'
   AND state NOT IN ('completed', 'failed', 'rolled_back', 'skipped', 'dismissed', 'superseded');
UPDATE public.upgrade
   SET docker_images_status = 'failed', error = 'test-fire'
 WHERE id = 6 AND docker_images_status = 'building'
   AND state NOT IN ('completed', 'failed', 'rolled_back', 'skipped', 'dismissed', 'superseded');
UPDATE public.upgrade
   SET docker_images_status = 'failed', error = 'test-fire'
 WHERE id = 7 AND docker_images_status = 'building'
   AND state NOT IN ('completed', 'failed', 'rolled_back', 'skipped', 'dismissed', 'superseded');

\echo '=== rows after guarded UPDATE ==='
\echo 'Rows 1..6 (terminal) must still be docker_images_status=''building''.'
\echo 'Row 7 (available) must transition to docker_images_status=''failed'' with error set.'
SELECT id, state, docker_images_status, (error IS NOT NULL) AS has_error
  FROM public.upgrade
 ORDER BY id;

ROLLBACK;
