\i test/setup.sql

\set ON_ERROR_STOP on

-- STATBUS-347: a fleet box can reach this migration with a failed row written
-- by the legacy text-prefix binary. The forward repair must recover the instant
-- of that failed transition from upgrade_state_log, strip the retired prefix,
-- and pass through the widened trigger so the new held sub-state is audited.
-- Exercise the migration's shipped down/up files rather than a copied repair.

\echo -- Return to the exact pre-migration schema.
\i migrations/20260903205636_statbus_347_rollback_finish_pending_column.down.sql

DELETE FROM public.upgrade_state_log WHERE upgrade_id = 9347001;
DELETE FROM public.upgrade WHERE id = 9347001 OR commit_sha = '3470000000000000000000000000000000000099';

INSERT INTO public.upgrade (
  id, commit_sha, committed_at, summary, scheduled_at, started_at, error, state
) OVERRIDING SYSTEM VALUE
VALUES (
  9347001,
  '3470000000000000000000000000000000000099',
  '2026-09-03 19:00:00+00',
  'STATBUS-347 legacy rollback finishing repair fixture',
  '2026-09-03 19:30:00+00',
  '2026-09-03 20:00:00+00',
  'ROLLBACK_FINISH_PENDING: restore completed; marker removal interrupted',
  'failed'
);

-- Two failed-transition rows prove the migration selects the most recent one,
-- not merely any matching audit row and not the upgrade.started_at fallback.
INSERT INTO public.upgrade_state_log (
  upgrade_id, old_state, new_state, application_name, logged_at
) VALUES
  (9347001, 'in_progress', 'failed', 'statbus-347-repair-test-old', '2026-09-03 20:30:00+00'),
  (9347001, 'in_progress', 'failed', 'statbus-347-repair-test-new', '2026-09-03 21:34:56+00');

\echo -- Apply the edited forward migration, including trigger installation before repair.
\i migrations/20260903205636_statbus_347_rollback_finish_pending_column.up.sql

\echo -- The repair uses the most recent failed-transition logged_at and strips the prefix.
SELECT rollback_finish_pending_at = '2026-09-03 21:34:56+00'::timestamptz AS pending_at_from_latest_failed_log,
       error = 'restore completed; marker removal interrupted' AS legacy_prefix_removed
  FROM public.upgrade
 WHERE id = 9347001;

\echo -- The widened trigger audited the repair NULL -> pending transition.
SELECT count(*) = 1 AS pending_transition_audited
  FROM public.upgrade_state_log
 WHERE upgrade_id = 9347001
   AND old_rollback_finish_pending_at IS NULL
   AND new_rollback_finish_pending_at = '2026-09-03 21:34:56+00'::timestamptz;

DELETE FROM public.upgrade_state_log WHERE upgrade_id = 9347001;
DELETE FROM public.upgrade WHERE id = 9347001;
