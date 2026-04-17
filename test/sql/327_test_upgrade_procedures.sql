-- Test: public.upgrade_supersede_older + public.upgrade_retention_plan/apply
--
-- Combined test covering the two upgrade table management procedures:
--
-- Part 1 — upgrade_supersede_older:
--   1. Supersedes available rows older by topo/committed_at
--   2. Supersedes failed rows (error preserved)
--   3. Supersedes rolled_back rows (error preserved)
--   4. Does NOT supersede in_progress rows (may still be running)
--   5. Does NOT supersede the installed row itself
--   6. Does NOT supersede completed rows
--   7. Does NOT supersede skipped rows
--   8. Does NOT supersede dismissed rows
--   9. Does NOT supersede already-superseded rows
--  10. Does NOT supersede newer rows
--  11. Returns correct count via INOUT p_superseded
--  12. Idempotent: second call returns 0
--
-- Part 2 — upgrade_retention_plan / upgrade_retention_apply:
--   A. install_same_family_prereleases     (purge same-family rc's when release installed)
--   B. install_old_commits_vs_release      (purge old commits when release installed)
--   C. install_old_commits_vs_prerelease   (purge old commits when prerelease installed)
--   D. time_safety                         (AND-gate: age > time_cap AND count > count_cap)
--   E. install_same_family_prerelease_to_prerelease (purge same-family rc's on prerelease install)
--   + zombie protection for scheduled/in_progress (NULL cap cells never purged)
--   + executor matches planner output
--
-- Shared-test harness: wrap in BEGIN/ROLLBACK for cloned-template isolation.

BEGIN;

-- ============================================================
-- PART 1: SUPERSEDE
-- ============================================================

\echo '=== supersede: setup ==='

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

-- Row 4: older but COMPLETED (should NOT be superseded — completed_at IS NOT NULL)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, completed_at)
VALUES (lpad(to_hex(40), 40, '0'), now() - '15 days'::interval, 40, 'release', 'completed',
        'prior completed release', ARRAY['v2026.02.0'], now() - '14 days'::interval);

-- Row 5: older IN_PROGRESS (should NOT be superseded — may still be running)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, scheduled_at, started_at)
VALUES (lpad(to_hex(45), 40, '0'), now() - '12 days'::interval, 45, 'prerelease', 'in_progress',
        'stale in_progress', ARRAY['v2026.03.0-rc.1'], now() - '12 days'::interval, now() - '12 days'::interval);

-- Row 6: NEWER than installed (should NOT be superseded — topo 200 > 100)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags)
VALUES (lpad(to_hex(200), 40, '0'), now() + '1 day'::interval, 200, 'release', 'available',
        'newer release v2026.05.0', ARRAY['v2026.05.0']);

-- Row 7: older FAILED (now superseded — error preserved)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, scheduled_at, started_at, error)
VALUES (lpad(to_hex(35), 40, '0'), now() - '18 days'::interval, 35, 'prerelease', 'failed',
        'failed prerelease', ARRAY['v2026.02.0-rc.5'],
        now() - '18 days'::interval, now() - '18 days'::interval,
        'download failed');

-- Row 8: older ROLLED_BACK (now superseded — error preserved)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, scheduled_at, started_at, error, rolled_back_at)
VALUES (lpad(to_hex(25), 40, '0'), now() - '22 days'::interval, 25, 'prerelease', 'rolled_back',
        'rolled back prerelease', ARRAY['v2026.01.0-rc.3'],
        now() - '22 days'::interval, now() - '22 days'::interval,
        'migration failed', now() - '22 days'::interval);

-- Row 9: older SKIPPED (should NOT be superseded — skipped_at IS NOT NULL)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, skipped_at)
VALUES (lpad(to_hex(20), 40, '0'), now() - '25 days'::interval, 20, 'release', 'skipped',
        'skipped release', ARRAY['v2026.01.0'], now() - '24 days'::interval);

-- Row 10: older DISMISSED (should NOT be superseded — dismissed_at IS NOT NULL)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, scheduled_at, started_at, error, dismissed_at)
VALUES (lpad(to_hex(15), 40, '0'), now() - '28 days'::interval, 15, 'prerelease', 'dismissed',
        'dismissed failure', ARRAY['v2026.01.0-rc.1'],
        now() - '28 days'::interval, now() - '28 days'::interval,
        'build failed', now() - '27 days'::interval);

-- Row 11: older already SUPERSEDED (should NOT be superseded again)
INSERT INTO public.upgrade (commit_sha, committed_at, topological_order, release_status, state, summary, tags, superseded_at)
VALUES (lpad(to_hex(10), 40, '0'), now() - '30 days'::interval, 10, 'release', 'superseded',
        'already superseded', ARRAY['v2025.12.0'], now() - '29 days'::interval);

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

\echo '=== supersede: error preserved on failed/rolled_back ==='

-- Verify that error text was preserved on rows 7 and 8
SELECT id, state, error FROM public.upgrade WHERE id IN (7, 8) ORDER BY id;

\echo '=== supersede: unknown commit_sha returns 0 ==='

CALL public.upgrade_supersede_older('0000000000000000000000000000000000000000', 0);

\echo '=== supersede: idempotent — second call returns 0 ==='

CALL public.upgrade_supersede_older(lpad(to_hex(100), 40, '0'), 0);

-- ============================================================
-- PART 2: RETENTION
-- ============================================================

\echo '=== retention: setup ==='

-- Fresh slate for retention fixtures.
TRUNCATE public.upgrade RESTART IDENTITY;

-- Tight caps so we can hit them without huge fixture counts.
-- Keep zombie cells at NULL to verify they are never purged.
TRUNCATE public.upgrade_retention_caps;
INSERT INTO public.upgrade_retention_caps (release_status, state, time_cap, count_cap, install_purge) VALUES
    ('release',    'scheduled',   NULL,               NULL, false),  -- zombie
    ('release',    'in_progress', NULL,               NULL, false),  -- zombie
    ('release',    'completed',   '10 years'::interval,  2, false),
    ('release',    'available',   '30 days'::interval,   2, false),
    ('release',    'superseded',  '30 days'::interval,   2, false),
    ('prerelease', 'scheduled',   NULL,               NULL, false),
    ('prerelease', 'in_progress', NULL,               NULL, false),
    ('prerelease', 'completed',   '1 year'::interval,    2, false),
    ('prerelease', 'available',   '30 days'::interval,   2, true),
    ('prerelease', 'superseded',  '30 days'::interval,   2, true),
    ('commit',     'scheduled',   NULL,               NULL, false),
    ('commit',     'in_progress', NULL,               NULL, false),
    ('commit',     'completed',   '90 days'::interval,   2, false),
    ('commit',     'available',   '14 days'::interval,   2, true),
    ('commit',     'superseded',  '14 days'::interval,   2, true);

\echo '=== retention: fixtures — 3 channels × stamped committed_at ==='

-- Commits (10 rows): 1 completed (1d), 9 superseded spanning newest→oldest
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags, completed_at) VALUES
    (lpad(to_hex( 1), 40, '0'), now() - '1 day'::interval, 'commit', 'completed',
     'commit #1 completed',  ARRAY['sha-0000000001'], now() - '1 day'::interval);

INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags, superseded_at) VALUES
    (lpad(to_hex( 2), 40, '0'), now() - ' 2 days'::interval, 'commit', 'superseded', 'commit #2 newest sup',  ARRAY['sha-0000000002'], now()),
    (lpad(to_hex( 3), 40, '0'), now() - ' 5 days'::interval, 'commit', 'superseded', 'commit #3 sup',         ARRAY['sha-0000000003'], now()),
    (lpad(to_hex( 4), 40, '0'), now() - '10 days'::interval, 'commit', 'superseded', 'commit #4 sup',         ARRAY['sha-0000000004'], now()),
    -- below the 14-day cap AND beyond count_cap=2 → time-safety candidates
    (lpad(to_hex( 5), 40, '0'), now() - '20 days'::interval, 'commit', 'superseded', 'commit #5 old',         ARRAY['sha-0000000005'], now()),
    (lpad(to_hex( 6), 40, '0'), now() - '40 days'::interval, 'commit', 'superseded', 'commit #6 older',       ARRAY['sha-0000000006'], now()),
    (lpad(to_hex( 7), 40, '0'), now() - '60 days'::interval, 'commit', 'superseded', 'commit #7 older still', ARRAY['sha-0000000007'], now()),
    (lpad(to_hex( 8), 40, '0'), now() - '80 days'::interval, 'commit', 'superseded', 'commit #8 ancient',     ARRAY['sha-0000000008'], now()),
    (lpad(to_hex( 9), 40, '0'), now() - '100 days'::interval,'commit', 'superseded', 'commit #9 ancient-2',   ARRAY['sha-0000000009'], now()),
    (lpad(to_hex(10), 40, '0'), now() - '120 days'::interval,'commit', 'superseded', 'commit #10 oldest',     ARRAY['sha-000000000a'], now());

-- Prereleases (ids 11..14): one completed recent, two same-family available, one older superseded.
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags, completed_at) VALUES
    (lpad(to_hex(11), 40, '0'), now() - '30 days'::interval, 'prerelease', 'completed',
     'prerelease rc1 completed', ARRAY['v2026.03.0-rc.1'], now() - '29 days'::interval);
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags) VALUES
    (lpad(to_hex(12), 40, '0'), now() - '10 days'::interval, 'prerelease', 'available',
     'prerelease rc2 same-family as installed release', ARRAY['v2026.04.0-rc.2']),
    (lpad(to_hex(13), 40, '0'), now() - ' 5 days'::interval, 'prerelease', 'available',
     'prerelease rc3 same-family as installed release', ARRAY['v2026.04.0-rc.3']);
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags, superseded_at) VALUES
    (lpad(to_hex(14), 40, '0'), now() - '40 days'::interval, 'prerelease', 'superseded',
     'prerelease rc old', ARRAY['v2026.02.0-rc.1'], now());

-- Releases (ids 15..16): the just-installed release + a prior completed release.
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags, completed_at) VALUES
    (lpad(to_hex(15), 40, '0'), now() - '50 days'::interval, 'release', 'completed',
     'prior release v2026.03.0', ARRAY['v2026.03.0'], now() - '49 days'::interval),
    (lpad(to_hex(16), 40, '0'), now() - '2 hours'::interval, 'release', 'completed',
     'just-installed release v2026.04.0', ARRAY['v2026.04.0'], now());

-- Zombie rows: absurdly old, NULL caps → must NEVER be purged.
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags, scheduled_at, started_at) VALUES
    (lpad(to_hex(17), 40, '0'), now() - '5 years'::interval, 'commit', 'in_progress',
     'ancient zombie in_progress', ARRAY['sha-0000000011'], now() - '5 years'::interval, now() - '5 years'::interval);
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags, scheduled_at) VALUES
    (lpad(to_hex(18), 40, '0'), now() - '5 years'::interval, 'prerelease', 'scheduled',
     'ancient zombie scheduled', ARRAY['v2020.01.0-rc.99'], now() - '5 years'::interval);

SELECT count(*) AS total_fixture_rows FROM public.upgrade;

\echo '=== retention: rule D time_safety (no install context) ==='

-- Expect: commits 5..10 (ranks 3..8 in superseded channel, all > count_cap=2).
-- Zombies (17, 18) must NOT appear (NULL caps).
SELECT p.id,
       p.action,
       regexp_replace(p.reason, 'age=[^>]+ > cap=[^ ]+ ', 'age=<redacted> > cap=<redacted> ')
           AS reason_redacted
  FROM public.upgrade_retention_plan('all', NULL) AS p
 ORDER BY p.id;

\echo '=== retention: rule A + B (install release id=16, family=v2026.04.0) ==='

-- Rule A: prereleases 12, 13 (same family v2026.04.0-rc.*).
-- Rule B: commits older than prior release (id=15, committed 50d ago) → 8, 9, 10.
-- Rule D: time-safety still fires on 5..10.
-- DISTINCT ON collapses overlaps.
SELECT p.id,
       p.action,
       regexp_replace(
           regexp_replace(p.reason,
               'age=[^>]+ > cap=[^ ]+ ', 'age=<redacted> > cap=<redacted> '),
           'committed_at=[^)]+', 'committed_at=<redacted>')
           AS reason_redacted
  FROM public.upgrade_retention_plan('all', 16) AS p
 ORDER BY p.id;

\echo '=== retention: rule C + E (install prerelease id=13, family=v2026.04.0) ==='

-- Rule C: commits older than prior completed prerelease (id=11, 30d ago) → 6..10.
-- Rule E: same-family prerelease id=12 (v2026.04.0-rc.2).
-- Rule D: time-safety on 5..10.
-- id=14 (v2026.02.0-rc.1) is different family → NOT purged by Rule E.
SELECT p.id,
       p.action
  FROM public.upgrade_retention_plan('all', 13) AS p
 ORDER BY p.id;

\echo '=== retention: rule E cross-family guard (install prerelease id=11, family=v2026.03.0) ==='

-- Install prerelease id=11 (v2026.03.0-rc.1). Different family from 12,13 (v2026.04.0).
-- Rule E must NOT purge across families. Only time-safety fires.
SELECT p.id, p.action
  FROM public.upgrade_retention_plan('all', 11) AS p
 ORDER BY p.id;

\echo '=== retention: executor deletes planned rows ==='

SAVEPOINT before_apply;
SET client_min_messages TO WARNING;
CALL public.upgrade_retention_apply('all', NULL, 0);
RESET client_min_messages;

SELECT count(*) FILTER (WHERE id BETWEEN 5 AND 10) AS old_commits_remaining,
       count(*) FILTER (WHERE id IN (17, 18))      AS zombies_remaining,
       count(*) FILTER (WHERE id BETWEEN 1 AND 4)  AS recent_commits_remaining
  FROM public.upgrade;

ROLLBACK TO SAVEPOINT before_apply;

\echo '=== retention: apply with install cascades same-family prereleases ==='

SAVEPOINT before_apply_install;
SET client_min_messages TO WARNING;
CALL public.upgrade_retention_apply('all', 16, 0);
RESET client_min_messages;

SELECT count(*) FILTER (WHERE id IN (12, 13)) AS same_family_prereleases_remaining,
       count(*) FILTER (WHERE id = 14)        AS other_family_prerelease_remaining,
       count(*) FILTER (WHERE id IN (17, 18)) AS zombies_remaining
  FROM public.upgrade;
ROLLBACK TO SAVEPOINT before_apply_install;

\echo '=== retention: caps flip — NULL caps + install_purge=false → zero plan ==='

SAVEPOINT before_caps_flip;
UPDATE public.upgrade_retention_caps SET time_cap = NULL, count_cap = NULL, install_purge = false;
SELECT count(*) AS planner_rows FROM public.upgrade_retention_plan('all', 16);
ROLLBACK TO SAVEPOINT before_caps_flip;

\echo '=== all tests done ==='

ROLLBACK;
