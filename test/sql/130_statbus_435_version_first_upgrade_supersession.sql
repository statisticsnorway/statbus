-- STATBUS-435: release_status is metadata, never an upgrade chronology tier.
\i test/setup.sql

BEGIN;
SET LOCAL statbus.actor = 'pg_regress STATBUS-435';
ALTER TABLE public.upgrade DISABLE TRIGGER upgrade_block_obsolete_pending_trigger;

\echo '=== older installed release does not supersede newer failed commit ==='
TRUNCATE public.upgrade RESTART IDENTITY;

INSERT INTO public.upgrade
    (commit_sha, committed_at, release_status, state, summary, commit_version,
     commit_tags, completed_at, log_relative_file_path)
VALUES
    (repeat('a', 40), '2026-09-29 00:30:59+00', 'release', 'completed',
     'installed A', 'v2026.09.3', ARRAY['v2026.09.3'],
     '2026-09-29 01:00:00+00', 'test-fixture-log.txt');

INSERT INTO public.upgrade
    (commit_sha, committed_at, release_status, state, summary, commit_version,
     commit_tags, scheduled_at, started_at, error)
VALUES
    (repeat('b', 40), '2026-09-29 14:40:27+00', 'commit', 'failed',
     'failed B', repeat('b', 8), ARRAY[]::text[],
     '2026-09-29 14:41:00+00', '2026-09-29 14:42:00+00', 'upgrade failed');

CALL public.upgrade_supersede_older(repeat('a', 40), 0);
SELECT summary, state FROM public.upgrade ORDER BY id;

\echo '=== newer scheduled candidate supersedes failed commit ==='
INSERT INTO public.upgrade
    (commit_sha, committed_at, release_status, state, summary, commit_version,
     commit_tags, scheduled_at)
VALUES
    (repeat('c', 40), '2026-09-30 10:00:00+00', 'prerelease', 'scheduled',
     'scheduled C', 'v2026.09.4-rc.1', ARRAY['v2026.09.4-rc.1'],
     '2026-09-30 10:05:00+00');

CALL public.upgrade_supersede_older(repeat('c', 40), 0);
SELECT summary, state FROM public.upgrade ORDER BY id;

\echo '=== equal version uses committed_at as tie-break ==='
TRUNCATE public.upgrade RESTART IDENTITY;

INSERT INTO public.upgrade
    (commit_sha, committed_at, release_status, state, summary, commit_version,
     commit_tags, scheduled_at)
VALUES
    (repeat('d', 40), '2026-09-30 08:00:00+00', 'release', 'available',
     'equal version older', 'v2026.09.5', ARRAY['v2026.09.5'], NULL),
    (repeat('e', 40), '2026-09-30 09:00:00+00', 'commit', 'scheduled',
     'equal version newer', 'v2026.09.5', ARRAY[]::text[], '2026-09-30 09:05:00+00');

CALL public.upgrade_supersede_older(repeat('e', 40), 0);
SELECT summary, state FROM public.upgrade ORDER BY id;

\echo '=== mixed version keys fall back to committed_at ==='
TRUNCATE public.upgrade RESTART IDENTITY;

INSERT INTO public.upgrade
    (commit_sha, committed_at, release_status, state, summary, commit_version,
     commit_tags, scheduled_at)
VALUES
    (repeat('f', 40), '2026-09-30 07:00:00+00', 'release', 'available',
     'tagged but older', 'v2099.01.0', ARRAY['v2099.01.0'], NULL),
    (repeat('1', 40), '2026-09-30 08:00:00+00', 'commit', 'scheduled',
     'unkeyed newer target', repeat('1', 8), ARRAY[]::text[], '2026-09-30 08:05:00+00');

CALL public.upgrade_supersede_older(repeat('1', 40), 0);
SELECT summary, state FROM public.upgrade ORDER BY id;

TRUNCATE public.upgrade RESTART IDENTITY;

INSERT INTO public.upgrade
    (commit_sha, committed_at, release_status, state, summary, commit_version,
     commit_tags, scheduled_at)
VALUES
    (repeat('2', 40), '2026-09-30 07:00:00+00', 'commit', 'available',
     'unkeyed older', repeat('2', 8), ARRAY[]::text[], NULL),
    (repeat('3', 40), '2026-09-30 08:00:00+00', 'release', 'scheduled',
     'tagged newer target', 'v2020.01.0', ARRAY['v2020.01.0'], '2026-09-30 08:05:00+00');

CALL public.upgrade_supersede_older(repeat('3', 40), 0);
SELECT summary, state FROM public.upgrade ORDER BY id;

ROLLBACK;
