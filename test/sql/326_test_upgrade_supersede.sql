-- Test: public.upgrade_supersede_older(commit_sha)
--
-- Exercises the shared procedure:
--   1. Supersedes rows older by topological_order
--   2. Supersedes rows older by committed_at (when topo is NULL)
--   3. Does NOT supersede the installed row itself
--   4. Does NOT supersede completed/started/skipped rows
--   5. Does NOT supersede rows newer than the installed one
--   6. Does NOT supersede failed rows with higher release_status
--   7. Returns correct count via INOUT p_superseded
--   8. Hierarchy: commit does NOT supersede prerelease or release
--   9. Hierarchy: prerelease supersedes commits but NOT releases
--
-- Shared-test harness: wrap in BEGIN/ROLLBACK for cloned-template isolation.

BEGIN;

\echo '=== supersede: setup ==='

-- Clean slate.
TRUNCATE public.upgrade RESTART IDENTITY;

\echo '=== supersede: fixtures ==='

-- Row 1: the just-installed commit (newest by both topo and committed_at)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, completed_at, log_relative_file_path)
VALUES (lpad(to_hex(100), 40, '0'), now() - '1 hour'::interval, 100, 'release', 'completed',
        'installed release v2026.04.0', ARRAY['v2026.04.0'], now(), 'test-fixture-log.txt');

-- Row 2: older available (should be superseded — older topo + committed_at, same status)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags)
VALUES (lpad(to_hex(50), 40, '0'), now() - '10 days'::interval, 50, 'release', 'available',
        'older release v2026.03.0', ARRAY['v2026.03.0']);

-- Row 3: older available commit (no topo, should be superseded by committed_at)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags)
VALUES (lpad(to_hex(30), 40, '0'), now() - '20 days'::interval, NULL, 'commit', 'available',
        'old commit', ARRAY['sha-000000001e']);

-- Row 4: older but COMPLETED (should NOT be superseded — already terminal)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, completed_at, log_relative_file_path)
VALUES (lpad(to_hex(40), 40, '0'), now() - '15 days'::interval, 40, 'release', 'completed',
        'prior completed release', ARRAY['v2026.02.0'], now() - '14 days'::interval, 'test-fixture-log.txt');

-- Row 5: older but IN_PROGRESS (should NOT be superseded — state not in supersedable set)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, scheduled_at, started_at)
VALUES (lpad(to_hex(45), 40, '0'), now() - '12 days'::interval, 45, 'prerelease', 'in_progress',
        'stuck in_progress', ARRAY['v2026.03.0-rc.1'], now() - '12 days'::interval, now() - '12 days'::interval);

-- Row 6: NEWER than installed (should NOT be superseded — topo 200 > 100)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags)
VALUES (lpad(to_hex(200), 40, '0'), now() + '1 day'::interval, 200, 'release', 'available',
        'newer release v2026.05.0', ARRAY['v2026.05.0']);

-- Row 7: older FAILED prerelease (should be superseded — release supersedes prerelease)
-- state='failed' requires scheduled_at + started_at + error per CHECK constraint.
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, scheduled_at, started_at, error)
VALUES (lpad(to_hex(35), 40, '0'), now() - '18 days'::interval, 35, 'prerelease', 'failed',
        'failed prerelease', ARRAY['v2026.02.0-rc.5'],
        now() - '18 days'::interval, now() - '18 days'::interval,
        'prior error: download failed');

SELECT id, state, topological_order AS topo, release_status,
       CASE WHEN error IS NOT NULL THEN 'has error' ELSE NULL END AS has_error
  FROM public.upgrade ORDER BY id;

\echo '=== supersede: call procedure ==='

CALL public.upgrade_supersede_older(lpad(to_hex(100), 40, '0'), 0);

\echo '=== supersede: verify results ==='

SELECT id, state, release_status, superseded_at IS NOT NULL AS has_superseded_at,
       CASE WHEN error IS NOT NULL THEN 'has error' ELSE NULL END AS has_error
  FROM public.upgrade ORDER BY id;

-- Verify exact counts by state
SELECT state, count(*) AS cnt FROM public.upgrade GROUP BY state ORDER BY state;

\echo '=== supersede: unknown commit_sha returns 0 ==='

CALL public.upgrade_supersede_older('0000000000000000000000000000000000000000', 0);

\echo '=== supersede: idempotent — second call returns 0 ==='

CALL public.upgrade_supersede_older(lpad(to_hex(100), 40, '0'), 0);

\echo '=== supersede: hierarchy — commit cannot supersede prerelease or release ==='

-- Reset
TRUNCATE public.upgrade RESTART IDENTITY;

-- Row 1: a newer COMMIT (the triggering row)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, completed_at, log_relative_file_path)
VALUES (lpad(to_hex(110), 40, '0'), now(), 110, 'commit', 'completed',
        'newer plain commit (dev.sh fix)', now(), 'test-fixture-log.txt');

-- Row 2: older available PRERELEASE (should NOT be superseded by a commit)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags)
VALUES (lpad(to_hex(90), 40, '0'), now() - '2 days'::interval, 90, 'prerelease', 'available',
        'rc.30 prerelease', ARRAY['v2026.04.0-rc.30']);

-- Row 3: older available RELEASE (should NOT be superseded by a commit)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags)
VALUES (lpad(to_hex(80), 40, '0'), now() - '5 days'::interval, 80, 'release', 'available',
        'release v2026.03.0', ARRAY['v2026.03.0']);

-- Row 4: older available COMMIT (should be superseded — same status)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary)
VALUES (lpad(to_hex(70), 40, '0'), now() - '7 days'::interval, 70, 'commit', 'available',
        'older commit');

CALL public.upgrade_supersede_older(lpad(to_hex(110), 40, '0'), 0);

-- Only the older commit (id=4) should be superseded; prerelease and release are untouched
SELECT id, state, release_status, superseded_at IS NOT NULL AS has_superseded_at
  FROM public.upgrade ORDER BY id;

\echo '=== supersede: hierarchy — prerelease supersedes commits but not releases ==='

-- Reset
TRUNCATE public.upgrade RESTART IDENTITY;

-- Row 1: a newer PRERELEASE (the triggering row)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, completed_at, log_relative_file_path)
VALUES (lpad(to_hex(120), 40, '0'), now(), 120, 'prerelease', 'completed',
        'rc.31 prerelease', ARRAY['v2026.04.0-rc.31'], now(), 'test-fixture-log.txt');

-- Row 2: older available COMMIT (should be superseded — prerelease > commit)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary)
VALUES (lpad(to_hex(100), 40, '0'), now() - '3 days'::interval, 100, 'commit', 'available',
        'older commit');

-- Row 3: older available PRERELEASE (should be superseded — same status)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags)
VALUES (lpad(to_hex(90), 40, '0'), now() - '5 days'::interval, 90, 'prerelease', 'available',
        'rc.29 older prerelease', ARRAY['v2026.04.0-rc.29']);

-- Row 4: older available RELEASE (should NOT be superseded — release > prerelease)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags)
VALUES (lpad(to_hex(80), 40, '0'), now() - '10 days'::interval, 80, 'release', 'available',
        'release v2026.03.0', ARRAY['v2026.03.0']);

CALL public.upgrade_supersede_older(lpad(to_hex(120), 40, '0'), 0);

-- Commit (id=2) and prerelease (id=3) superseded; release (id=4) untouched
SELECT id, state, release_status, superseded_at IS NOT NULL AS has_superseded_at
  FROM public.upgrade ORDER BY id;

\echo '=== supersede test done ==='

ROLLBACK;
