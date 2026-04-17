-- Test: public.upgrade_supersede_older(commit_sha)
--
-- Exercises the shared procedure:
--   1. Supersedes rows older by topological_order
--   2. Supersedes rows older by committed_at (when topo is NULL)
--   3. Does NOT supersede the installed row itself
--   4. Does NOT supersede completed/started/skipped rows
--   5. Does NOT supersede rows newer than the installed one
--   6. Does NOT supersede failed rows (started_at guard)
--   7. Returns correct count via INOUT p_superseded
--
-- Shared-test harness: wrap in BEGIN/ROLLBACK for cloned-template isolation.

BEGIN;

\echo '=== supersede: setup ==='

-- Clean slate.
TRUNCATE public.upgrade RESTART IDENTITY;

\echo '=== supersede: fixtures ==='

-- Row 1: the just-installed commit (newest by both topo and committed_at)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, completed_at)
VALUES (lpad(to_hex(100), 40, '0'), now() - '1 hour'::interval, 100, 'release', 'completed',
        'installed release v2026.04.0', ARRAY['v2026.04.0'], now());

-- Row 2: older available (should be superseded — older topo + committed_at)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags)
VALUES (lpad(to_hex(50), 40, '0'), now() - '10 days'::interval, 50, 'release', 'available',
        'older release v2026.03.0', ARRAY['v2026.03.0']);

-- Row 3: older available commit (no topo, should be superseded by committed_at)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags)
VALUES (lpad(to_hex(30), 40, '0'), now() - '20 days'::interval, NULL, 'commit', 'available',
        'old commit', ARRAY['sha-000000001e']);

-- Row 4: older but COMPLETED (should NOT be superseded — already terminal)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, completed_at)
VALUES (lpad(to_hex(40), 40, '0'), now() - '15 days'::interval, 40, 'release', 'completed',
        'prior completed release', ARRAY['v2026.02.0'], now() - '14 days'::interval);

-- Row 5: older but IN_PROGRESS (should NOT be superseded — started_at is set)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, scheduled_at, started_at)
VALUES (lpad(to_hex(45), 40, '0'), now() - '12 days'::interval, 45, 'prerelease', 'in_progress',
        'stuck in_progress', ARRAY['v2026.03.0-rc.1'], now() - '12 days'::interval, now() - '12 days'::interval);

-- Row 6: NEWER than installed (should NOT be superseded — topo 200 > 100)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags)
VALUES (lpad(to_hex(200), 40, '0'), now() + '1 day'::interval, 200, 'release', 'available',
        'newer release v2026.05.0', ARRAY['v2026.05.0']);

-- Row 7: older FAILED (should NOT be superseded — started_at guard)
-- state='failed' requires scheduled_at + started_at + error per CHECK constraint.
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, scheduled_at, started_at, error)
VALUES (lpad(to_hex(35), 40, '0'), now() - '18 days'::interval, 35, 'prerelease', 'failed',
        'failed prerelease', ARRAY['v2026.02.0-rc.5'],
        now() - '18 days'::interval, now() - '18 days'::interval,
        'prior error: download failed');

SELECT id, state, topological_order AS topo,
       CASE WHEN error IS NOT NULL THEN 'has error' ELSE NULL END AS has_error
  FROM public.upgrade ORDER BY id;

\echo '=== supersede: call procedure ==='

CALL public.upgrade_supersede_older(lpad(to_hex(100), 40, '0'), 0);

\echo '=== supersede: verify results ==='

SELECT id, state, superseded_at IS NOT NULL AS has_superseded_at,
       CASE WHEN error IS NOT NULL THEN 'has error' ELSE NULL END AS has_error
  FROM public.upgrade ORDER BY id;

-- Verify exact counts by state
SELECT state, count(*) AS cnt FROM public.upgrade GROUP BY state ORDER BY state;

\echo '=== supersede: unknown commit_sha returns 0 ==='

CALL public.upgrade_supersede_older('0000000000000000000000000000000000000000', 0);

\echo '=== supersede: idempotent — second call returns 0 ==='

CALL public.upgrade_supersede_older(lpad(to_hex(100), 40, '0'), 0);

\echo '=== supersede test done ==='

ROLLBACK;
