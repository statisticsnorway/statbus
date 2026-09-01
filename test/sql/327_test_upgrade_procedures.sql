-- Test: public.upgrade_supersede_older + public.upgrade_retention_plan/apply
--
-- Combined test covering the two upgrade table management procedures:
--
-- Part 1 — upgrade_supersede_older:
--   1. Supersedes available rows older by committed_at
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
--  13. Hierarchy: commit does NOT supersede prerelease or release
--  14. Hierarchy: prerelease supersedes commits but NOT releases
--
-- The BEFORE-INSERT trigger upgrade_block_obsolete_pending_trigger is
-- disabled inside this test's transaction so fixture inserts don't
-- pre-supersede rows the procedure is being asked to supersede. The
-- trigger itself is exercised in 330_test_upgrade_invariant_trigger.sql.
--
-- Part 2 — upgrade_retention_plan / upgrade_retention_apply:
--   A. install_same_family_prereleases     (purge same-family rc's when release installed)
--   B. install_old_commits_vs_release      (purge old commits when release installed)
--   C. install_old_commits_vs_prerelease   (purge old commits when prerelease installed)
--   D. time_safety                         (AND-gate: age > time_cap AND count > count_cap)
--   E. install_same_family_prerelease_to_prerelease (purge same-family rc's on prerelease install)
--   + p_context='commit' scoping (time-safety limited to commit channel)
--   + executor apply with prerelease install id (Rule E executor path)
--   + zombie protection for scheduled/in_progress (NULL cap cells never purged)
--   + executor matches planner output
--
-- Shared-test harness: wrap in BEGIN/ROLLBACK for cloned-template isolation.

\i test/setup.sql

BEGIN;

-- Disable the BEFORE-INSERT trigger that auto-supersedes obsolete pending
-- rows on insert. This test exercises upgrade_supersede_older directly;
-- the trigger gets its own coverage in 330. ALTER inside BEGIN/ROLLBACK
-- is transactional, so this rolls back with the rest of the test.
ALTER TABLE public.upgrade DISABLE TRIGGER upgrade_block_obsolete_pending_trigger;

-- ============================================================
-- PART 1: SUPERSEDE
-- ============================================================

\echo '=== supersede: setup ==='

TRUNCATE public.upgrade RESTART IDENTITY;

\echo '=== supersede: fixtures ==='

-- Row 1: the just-installed commit (newest by committed_at)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, completed_at, log_relative_file_path)
VALUES (lpad(to_hex(100), 40, '0'), now() - '1 hour'::interval, 'release', 'completed',
        'installed release v2026.04.0', ARRAY['v2026.04.0'], now(), 'test-fixture-log.txt');

-- Row 2: older available (should be superseded — older committed_at)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags)
VALUES (lpad(to_hex(50), 40, '0'), now() - '10 days'::interval, 'release', 'available',
        'older release v2026.03.0', ARRAY['v2026.03.0']);

-- Row 3: older available commit (should be superseded by committed_at)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags)
VALUES (lpad(to_hex(30), 40, '0'), now() - '20 days'::interval, 'commit', 'available',
        'old commit', ARRAY['fixture-tag-000000001e']);

-- Row 4: older but COMPLETED (should NOT be superseded — completed_at IS NOT NULL)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, completed_at, log_relative_file_path)
VALUES (lpad(to_hex(40), 40, '0'), now() - '15 days'::interval, 'release', 'completed',
        'prior completed release', ARRAY['v2026.02.0'], now() - '14 days'::interval, 'test-fixture-log.txt');

-- Row 5: older IN_PROGRESS (should NOT be superseded — may still be running)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, scheduled_at, started_at)
VALUES (lpad(to_hex(45), 40, '0'), now() - '12 days'::interval, 'prerelease', 'in_progress',
        'stale in_progress', ARRAY['v2026.03.0-rc.1'], now() - '12 days'::interval, now() - '12 days'::interval);

-- Row 6: NEWER than installed (should NOT be superseded — committed_at > installed)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags)
VALUES (lpad(to_hex(200), 40, '0'), now() + '1 day'::interval, 'release', 'available',
        'newer release v2026.05.0', ARRAY['v2026.05.0']);

-- Row 7: older FAILED (now superseded — error preserved)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, scheduled_at, started_at, error)
VALUES (lpad(to_hex(35), 40, '0'), now() - '18 days'::interval, 'prerelease', 'failed',
        'failed prerelease', ARRAY['v2026.02.0-rc.5'],
        now() - '18 days'::interval, now() - '18 days'::interval,
        'download failed');

-- Row 8: older ROLLED_BACK (now superseded — error preserved)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, scheduled_at, started_at, error, rolled_back_at)
VALUES (lpad(to_hex(25), 40, '0'), now() - '22 days'::interval, 'prerelease', 'rolled_back',
        'rolled back prerelease', ARRAY['v2026.01.0-rc.3'],
        now() - '22 days'::interval, now() - '22 days'::interval,
        'migration failed', now() - '22 days'::interval);

-- Row 9: older SKIPPED (should NOT be superseded — skipped_at IS NOT NULL)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, skipped_at)
VALUES (lpad(to_hex(20), 40, '0'), now() - '25 days'::interval, 'release', 'skipped',
        'skipped release', ARRAY['v2026.01.0'], now() - '24 days'::interval);

-- Row 10: older DISMISSED (should NOT be superseded — dismissed_at IS NOT NULL)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, scheduled_at, started_at, error, dismissed_at)
VALUES (lpad(to_hex(15), 40, '0'), now() - '28 days'::interval, 'prerelease', 'dismissed',
        'dismissed failure', ARRAY['v2026.01.0-rc.1'],
        now() - '28 days'::interval, now() - '28 days'::interval,
        'build failed', now() - '27 days'::interval);

-- Row 11: older already SUPERSEDED (should NOT be superseded again)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, superseded_at)
VALUES (lpad(to_hex(10), 40, '0'), now() - '30 days'::interval, 'release', 'superseded',
        'already superseded', ARRAY['v2025.12.0'], now() - '29 days'::interval);

SELECT id, state,
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

\echo '=== supersede: hierarchy — commit cannot supersede prerelease or release ==='

-- Fresh fixture for hierarchy check. Triggering row is a plain commit; older
-- prerelease and release rows must remain available (commit < prerelease < release).
TRUNCATE public.upgrade RESTART IDENTITY;

-- Row 1: a newer COMMIT (the triggering row)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, completed_at, log_relative_file_path)
VALUES (lpad(to_hex(110), 40, '0'), now(), 'commit', 'completed',
        'newer plain commit (dev.sh fix)', now(), 'test-fixture-log.txt');

-- Row 2: older available PRERELEASE (should NOT be superseded by a commit)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags)
VALUES (lpad(to_hex(90), 40, '0'), now() - '2 days'::interval, 'prerelease', 'available',
        'rc.30 prerelease', ARRAY['v2026.04.0-rc.30']);

-- Row 3: older available RELEASE (should NOT be superseded by a commit)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags)
VALUES (lpad(to_hex(80), 40, '0'), now() - '5 days'::interval, 'release', 'available',
        'release v2026.03.0', ARRAY['v2026.03.0']);

-- Row 4: older available COMMIT (should be superseded — same status)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary)
VALUES (lpad(to_hex(70), 40, '0'), now() - '7 days'::interval, 'commit', 'available',
        'older commit');

CALL public.upgrade_supersede_older(lpad(to_hex(110), 40, '0'), 0);

-- Only the older commit (id=4) should be superseded; prerelease and release are untouched
SELECT id, state, release_status, superseded_at IS NOT NULL AS has_superseded_at
  FROM public.upgrade ORDER BY id;

\echo '=== supersede: hierarchy — prerelease supersedes commits but not releases ==='

-- Fresh fixture. Triggering row is a prerelease; it must supersede older commits
-- and same-channel prereleases, but NOT an older release.
TRUNCATE public.upgrade RESTART IDENTITY;

-- Row 1: a newer PRERELEASE (the triggering row)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, completed_at, log_relative_file_path)
VALUES (lpad(to_hex(120), 40, '0'), now(), 'prerelease', 'completed',
        'rc.31 prerelease', ARRAY['v2026.04.0-rc.31'], now(), 'test-fixture-log.txt');

-- Row 2: older available COMMIT (should be superseded — prerelease > commit)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary)
VALUES (lpad(to_hex(100), 40, '0'), now() - '3 days'::interval, 'commit', 'available',
        'older commit');

-- Row 3: older available PRERELEASE (should be superseded — same status)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags)
VALUES (lpad(to_hex(90), 40, '0'), now() - '5 days'::interval, 'prerelease', 'available',
        'rc.29 older prerelease', ARRAY['v2026.04.0-rc.29']);

-- Row 4: older available RELEASE (should NOT be superseded — release > prerelease)
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags)
VALUES (lpad(to_hex(80), 40, '0'), now() - '10 days'::interval, 'release', 'available',
        'release v2026.03.0', ARRAY['v2026.03.0']);

CALL public.upgrade_supersede_older(lpad(to_hex(120), 40, '0'), 0);

-- Commit (id=2) and prerelease (id=3) superseded; release (id=4) untouched
SELECT id, state, release_status, superseded_at IS NOT NULL AS has_superseded_at
  FROM public.upgrade ORDER BY id;

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
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, completed_at, log_relative_file_path) VALUES
    (lpad(to_hex( 1), 40, '0'), now() - '1 day'::interval, 'commit', 'completed',
     'commit #1 completed',  ARRAY['fixture-tag-0000000001'], now() - '1 day'::interval, 'test-fixture-log.txt');

INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, superseded_at) VALUES
    (lpad(to_hex( 2), 40, '0'), now() - ' 2 days'::interval, 'commit', 'superseded', 'commit #2 newest sup',  ARRAY['fixture-tag-0000000002'], now()),
    (lpad(to_hex( 3), 40, '0'), now() - ' 5 days'::interval, 'commit', 'superseded', 'commit #3 sup',         ARRAY['fixture-tag-0000000003'], now()),
    (lpad(to_hex( 4), 40, '0'), now() - '10 days'::interval, 'commit', 'superseded', 'commit #4 sup',         ARRAY['fixture-tag-0000000004'], now()),
    -- below the 14-day cap AND beyond count_cap=2 → time-safety candidates
    (lpad(to_hex( 5), 40, '0'), now() - '20 days'::interval, 'commit', 'superseded', 'commit #5 old',         ARRAY['fixture-tag-0000000005'], now()),
    (lpad(to_hex( 6), 40, '0'), now() - '40 days'::interval, 'commit', 'superseded', 'commit #6 older',       ARRAY['fixture-tag-0000000006'], now()),
    (lpad(to_hex( 7), 40, '0'), now() - '60 days'::interval, 'commit', 'superseded', 'commit #7 older still', ARRAY['fixture-tag-0000000007'], now()),
    (lpad(to_hex( 8), 40, '0'), now() - '80 days'::interval, 'commit', 'superseded', 'commit #8 ancient',     ARRAY['fixture-tag-0000000008'], now()),
    (lpad(to_hex( 9), 40, '0'), now() - '100 days'::interval,'commit', 'superseded', 'commit #9 ancient-2',   ARRAY['fixture-tag-0000000009'], now()),
    (lpad(to_hex(10), 40, '0'), now() - '120 days'::interval,'commit', 'superseded', 'commit #10 oldest',     ARRAY['fixture-tag-000000000a'], now());

-- Prereleases (ids 11..14): one completed recent, two same-family available, one older superseded.
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, completed_at, log_relative_file_path) VALUES
    (lpad(to_hex(11), 40, '0'), now() - '30 days'::interval, 'prerelease', 'completed',
     'prerelease rc1 completed', ARRAY['v2026.03.0-rc.1'], now() - '29 days'::interval, 'test-fixture-log.txt');
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags) VALUES
    (lpad(to_hex(12), 40, '0'), now() - '10 days'::interval, 'prerelease', 'available',
     'prerelease rc2 same-family as installed release', ARRAY['v2026.04.0-rc.2']),
    (lpad(to_hex(13), 40, '0'), now() - ' 5 days'::interval, 'prerelease', 'available',
     'prerelease rc3 same-family as installed release', ARRAY['v2026.04.0-rc.3']);
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, superseded_at) VALUES
    (lpad(to_hex(14), 40, '0'), now() - '40 days'::interval, 'prerelease', 'superseded',
     'prerelease rc old', ARRAY['v2026.02.0-rc.1'], now());

-- Releases (ids 15..16): the just-installed release + a prior completed release.
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, completed_at, log_relative_file_path) VALUES
    (lpad(to_hex(15), 40, '0'), now() - '50 days'::interval, 'release', 'completed',
     'prior release v2026.03.0', ARRAY['v2026.03.0'], now() - '49 days'::interval, 'test-fixture-log.txt'),
    (lpad(to_hex(16), 40, '0'), now() - '2 hours'::interval, 'release', 'completed',
     'just-installed release v2026.04.0', ARRAY['v2026.04.0'], now(), 'test-fixture-log.txt');

-- Zombie rows: absurdly old, NULL caps → must NEVER be purged.
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, scheduled_at, started_at) VALUES
    (lpad(to_hex(17), 40, '0'), now() - '5 years'::interval, 'commit', 'in_progress',
     'ancient zombie in_progress', ARRAY['fixture-tag-0000000011'], now() - '5 years'::interval, now() - '5 years'::interval);
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, commit_tags, scheduled_at) VALUES
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

\echo '=== retention: p_context=commit scopes time-safety to commit channel only ==='

-- With p_context='commit', only commit-channel rows hit time-safety. The
-- install_* CTEs still check i.release_status; since p_installed_id is NULL,
-- they yield nothing. So the result equals "commit channel time-safety only".
SELECT p.id, p.action
  FROM public.upgrade_retention_plan('commit', NULL) AS p
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

\echo '=== retention: apply with prerelease install id=13 purges same-family ==='

-- Execute retention with prerelease install context (id=13, v2026.04.0-rc.3).
-- Rule E purges id=12 (same family). Rule C purges commits 6..10.
-- Rule D purges commits 5..10. DISTINCT ON collapses overlaps.
-- Expected: 7 rows deleted (ids 5..10 + 12).
SAVEPOINT before_apply_prerelease;
SET client_min_messages TO WARNING;
CALL public.upgrade_retention_apply('all', 13, 0);
RESET client_min_messages;

SELECT count(*) FILTER (WHERE id = 12) AS same_family_prerelease_remaining,
       count(*) FILTER (WHERE id = 14) AS other_family_prerelease_remaining,
       count(*) FILTER (WHERE id IN (17, 18)) AS zombies_remaining,
       count(*) FILTER (WHERE id BETWEEN 5 AND 10) AS old_commits_remaining
  FROM public.upgrade;
ROLLBACK TO SAVEPOINT before_apply_prerelease;

\echo '=== retention: caps flip — NULL caps + install_purge=false → zero plan ==='

SAVEPOINT before_caps_flip;
UPDATE public.upgrade_retention_caps SET time_cap = NULL, count_cap = NULL, install_purge = false;
SELECT count(*) AS planner_rows FROM public.upgrade_retention_plan('all', 16);
ROLLBACK TO SAVEPOINT before_caps_flip;

-- ============================================================
-- PART 3: STATBUS-333 ONE SCHEDULE DOOR
-- ============================================================

\echo '=== schedule: setup ==='

-- Part 1 disabled this trigger so its fixtures could exercise the supersede
-- procedure directly. Scheduling needs the trigger as the authoritative
-- obsolete-candidate oracle.
ALTER TABLE public.upgrade ENABLE TRIGGER upgrade_block_obsolete_pending_trigger;
TRUNCATE public.upgrade_state_log, public.upgrade RESTART IDENTITY;
SET client_min_messages TO WARNING;

\echo '=== schedule: failed retry through admin role ==='

INSERT INTO public.upgrade (commit_sha, committed_at, state, summary)
VALUES ('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '2026-08-01 00:00:00+00', 'available',
        'older candidate to supersede')
RETURNING id \gset schedule_older_

INSERT INTO public.upgrade (
    commit_sha, committed_at, state, summary, scheduled_at, started_at,
    error, log_relative_file_path, recovery_attempts
)
VALUES (
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', '2026-08-02 00:00:00+00', 'failed',
    'failed candidate to retry', '2026-08-02 01:00:00+00', '2026-08-02 01:01:00+00',
    'attempt one failed', 'attempt-one.log', 3
)
RETURNING id \gset schedule_target_

CALL test.set_user_from_email('test.admin@statbus.org');

SELECT schedule_result, landed_state, superseded_count
  FROM public.upgrade_schedule('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', false);

\echo '=== schedule: current row clean ==='

SELECT state,
       scheduled_at > '2026-08-02 01:00:00+00'::timestamptz AS scheduled_at_refreshed,
       recreate = false AS recreate_set,
       started_at IS NULL
           AND completed_at IS NULL
           AND error IS NULL
           AND rolled_back_at IS NULL
           AND skipped_at IS NULL
           AND dismissed_at IS NULL
           AND superseded_at IS NULL
           AND log_relative_file_path IS NULL
           AND backup_path IS NULL AS lifecycle_and_evidence_clean,
       recovery_attempts = 0
           AND recovery_parked_at IS NULL
           AND recovery_parked_reason IS NULL AS recovery_clean
  FROM public.upgrade
 WHERE id = :schedule_target_id;

\echo '=== schedule: old evidence archived before reset ==='

SELECT old_state, new_state, old_error, old_log_relative_file_path,
       old_recovery_attempts, actor_source
  FROM public.upgrade_state_log
 WHERE upgrade_id = :schedule_target_id
 ORDER BY id DESC
 LIMIT 1;

\echo '=== schedule: older candidate superseded ==='

SELECT state, superseded_at IS NOT NULL AS has_superseded_at
  FROM public.upgrade
 WHERE id = :schedule_older_id;

\echo '=== schedule: parked same-row retry ==='

DELETE FROM public.upgrade_state_log;
DELETE FROM public.upgrade;

INSERT INTO public.upgrade (
    commit_sha, committed_at, state, summary, scheduled_at, started_at,
    error, log_relative_file_path, backup_path, recovery_attempts,
    recovery_parked_at, recovery_parked_reason
)
VALUES (
    'cccccccccccccccccccccccccccccccccccccccc', '2026-08-03 00:00:00+00', 'in_progress',
    'parked candidate', '2026-08-03 01:00:00+00', '2026-08-03 01:01:00+00',
    'parked error', 'parked.log', '/tmp/parked-backup', 4,
    '2026-08-03 02:00:00+00', 'deterministic park reason'
)
RETURNING id \gset parked_

SELECT schedule_result, landed_state, superseded_count
  FROM public.upgrade_schedule('cccccccccccccccccccccccccccccccccccccccc', false);

SELECT state,
       started_at IS NULL
           AND error IS NULL
           AND log_relative_file_path IS NULL
           AND backup_path IS NULL AS evidence_clean,
       recovery_attempts = 0
           AND recovery_parked_at IS NULL
           AND recovery_parked_reason IS NULL AS recovery_clean
  FROM public.upgrade
 WHERE id = :parked_id;

SELECT old_state, new_state,
       old_parked_at = '2026-08-03 02:00:00+00'::timestamptz AS old_park_time_captured,
       old_recovery_parked_reason, old_error, old_log_relative_file_path,
       old_backup_path, old_recovery_attempts
  FROM public.upgrade_state_log
 WHERE upgrade_id = :parked_id
 ORDER BY id DESC
 LIMIT 1;

\echo '=== schedule: standalone unpark captures old evidence ==='

DELETE FROM public.upgrade_state_log;
DELETE FROM public.upgrade;

INSERT INTO public.upgrade (
    commit_sha, committed_at, state, summary, scheduled_at, started_at,
    error, log_relative_file_path, backup_path, recovery_attempts,
    recovery_parked_at, recovery_parked_reason
)
VALUES (
    'dddddddddddddddddddddddddddddddddddddddd', '2026-08-04 00:00:00+00', 'in_progress',
    'standalone unpark candidate', '2026-08-04 01:00:00+00', '2026-08-04 01:01:00+00',
    'unpark error', 'unpark.log', '/tmp/unpark-backup', 5,
    '2026-08-04 02:00:00+00', 'unpark reason'
)
RETURNING id \gset unpark_

UPDATE public.upgrade
   SET recovery_attempts = 0,
       recovery_parked_at = NULL,
       recovery_parked_reason = NULL
 WHERE id = :unpark_id
   AND (state <> 'in_progress' OR recovery_parked_at IS NOT NULL);

SELECT count(*) AS log_rows
  FROM public.upgrade_state_log
 WHERE upgrade_id = :unpark_id;

SELECT old_state, new_state,
       old_parked_at = '2026-08-04 02:00:00+00'::timestamptz AS old_park_time_captured,
       old_recovery_parked_reason, old_error, old_log_relative_file_path,
       old_backup_path, old_recovery_attempts
  FROM public.upgrade_state_log
 WHERE upgrade_id = :unpark_id;

\echo '=== schedule: live in-progress refusal ==='

DELETE FROM public.upgrade_state_log;
DELETE FROM public.upgrade;

INSERT INTO public.upgrade (
    commit_sha, committed_at, state, summary, scheduled_at, started_at,
    error, log_relative_file_path, backup_path, recovery_attempts
)
VALUES (
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', '2026-08-05 00:00:00+00', 'in_progress',
    'live candidate', '2026-08-05 01:00:00+00', '2026-08-05 01:01:00+00',
    'live evidence', 'live.log', '/tmp/live-backup', 6
)
RETURNING id \gset live_

SELECT schedule_result, landed_state, superseded_count
  FROM public.upgrade_schedule('eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', false);

SELECT state = 'in_progress'
           AND scheduled_at = '2026-08-05 01:00:00+00'::timestamptz
           AND started_at = '2026-08-05 01:01:00+00'::timestamptz
           AND error = 'live evidence'
           AND log_relative_file_path = 'live.log'
           AND backup_path = '/tmp/live-backup'
           AND recovery_attempts = 6
           AND recovery_parked_at IS NULL AS row_unchanged,
       (SELECT count(*) FROM public.upgrade_state_log WHERE upgrade_id = :live_id) AS log_rows
  FROM public.upgrade
 WHERE id = :live_id;

\echo '=== schedule: restore-broke refusal ==='

DELETE FROM public.upgrade_state_log;
DELETE FROM public.upgrade;

INSERT INTO public.upgrade (commit_sha, committed_at, state, summary)
VALUES ('1111111111111111111111111111111111111111', '2026-08-05 00:00:00+00', 'available',
        'older candidate that must remain available')
RETURNING id \gset restore_older_

INSERT INTO public.upgrade (
    commit_sha, committed_at, state, summary, scheduled_at, started_at,
    error, log_relative_file_path, backup_path, recovery_attempts
)
VALUES (
    '2222222222222222222222222222222222222222', '2026-08-06 00:00:00+00', 'failed',
    'restore-broke candidate', '2026-08-06 01:00:00+00', '2026-08-06 01:01:00+00',
    'restore failed', 'restore-failed.log', '/tmp/restore-backup', 7
)
RETURNING id \gset restore_target_

SELECT schedule_result, landed_state, superseded_count
  FROM public.upgrade_schedule('2222222222222222222222222222222222222222', false);

SELECT state = 'failed'
           AND error = 'restore failed'
           AND log_relative_file_path = 'restore-failed.log'
           AND backup_path = '/tmp/restore-backup'
           AND recovery_attempts = 7 AS target_unchanged,
       (SELECT state FROM public.upgrade WHERE id = :restore_older_id) AS older_state,
       (SELECT count(*) FROM public.upgrade_state_log) AS log_rows
  FROM public.upgrade
 WHERE id = :restore_target_id;

\echo '=== schedule: unregistered is idempotent ==='

DELETE FROM public.upgrade_state_log;
DELETE FROM public.upgrade;

SELECT schedule_result, landed_state, superseded_count
  FROM public.upgrade_schedule('ffffffffffffffffffffffffffffffffffffffff', false);
SELECT schedule_result, landed_state, superseded_count
  FROM public.upgrade_schedule('ffffffffffffffffffffffffffffffffffffffff', false);
SELECT count(*) AS log_rows FROM public.upgrade_state_log;

\echo '=== schedule: already-scheduled target is untouched ==='

INSERT INTO public.upgrade (commit_sha, committed_at, state, summary)
VALUES ('3333333333333333333333333333333333333333', '2026-08-07 00:00:00+00', 'available',
        'older candidate for already-scheduled call')
RETURNING id \gset already_older_

INSERT INTO public.upgrade (
    commit_sha, committed_at, state, summary, scheduled_at, recreate
)
VALUES (
    '4444444444444444444444444444444444444444', '2026-08-08 00:00:00+00', 'scheduled',
    'already scheduled target', '2026-08-08 01:00:00+00', true
)
RETURNING id \gset already_target_

SELECT schedule_result, landed_state, superseded_count
  FROM public.upgrade_schedule('4444444444444444444444444444444444444444', false);
SELECT schedule_result, landed_state, superseded_count
  FROM public.upgrade_schedule('4444444444444444444444444444444444444444', false);

SELECT state = 'scheduled'
           AND scheduled_at = '2026-08-08 01:00:00+00'::timestamptz
           AND recreate = true AS target_unchanged,
       (SELECT count(*) FROM public.upgrade_state_log WHERE upgrade_id = :already_target_id) AS target_log_rows,
       (SELECT state FROM public.upgrade WHERE id = :already_older_id) AS older_state
  FROM public.upgrade
 WHERE id = :already_target_id;

\echo '=== schedule: obsolete superseded target is a no-mutation refusal ==='

DELETE FROM public.upgrade_state_log;
DELETE FROM public.upgrade;

INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary)
VALUES ('6666666666666666666666666666666666666666', '2026-08-09 00:00:00+00', 'release',
        'available', 'eligible older row whose supersede must roll back')
RETURNING id \gset obsolete_older_

INSERT INTO public.upgrade (
    commit_sha, committed_at, release_status, state, summary,
    completed_at, log_relative_file_path
)
VALUES (
    '7777777777777777777777777777777777777777', '2026-08-11 00:00:00+00', 'release',
    'completed', 'newer installed release', '2026-08-11 01:00:00+00', 'installed.log'
);

INSERT INTO public.upgrade (
    commit_sha, committed_at, release_status, state, summary,
    scheduled_at, started_at, error, log_relative_file_path, backup_path,
    superseded_at, recovery_attempts, recovery_parked_reason
)
VALUES (
    '5555555555555555555555555555555555555555', '2026-08-10 00:00:00+00', 'release',
    'superseded', 'obsolete target with evidence',
    '2026-08-10 01:00:00+00', '2026-08-10 01:01:00+00', 'obsolete evidence',
    'obsolete.log', '/tmp/obsolete-backup', '2026-08-10 02:00:00+00', 8,
    'obsolete recovery narrative'
)
RETURNING id \gset obsolete_target_

CREATE TEMP TABLE obsolete_target_before ON COMMIT DROP AS
SELECT * FROM public.upgrade WHERE id = :obsolete_target_id;

SELECT schedule_result, landed_state, superseded_count
  FROM public.upgrade_schedule('5555555555555555555555555555555555555555', false);

SELECT to_jsonb(u) = (SELECT to_jsonb(b) FROM obsolete_target_before AS b) AS target_byte_identical,
       (SELECT state FROM public.upgrade WHERE id = :obsolete_older_id) AS eligible_older_state,
       (SELECT count(*) FROM public.upgrade_state_log) AS log_rows
  FROM public.upgrade AS u
 WHERE u.id = :obsolete_target_id;

\echo '=== schedule: regular user refused at execute ==='

SAVEPOINT before_regular_user_attempt;
\set ON_ERROR_STOP off
CALL test.set_user_from_email('test.regular@statbus.org');
SELECT schedule_result
  FROM public.upgrade_schedule('5555555555555555555555555555555555555555', false);
\set ON_ERROR_STOP on
ROLLBACK TO SAVEPOINT before_regular_user_attempt;

SELECT to_jsonb(u) = (SELECT to_jsonb(b) FROM obsolete_target_before AS b) AS target_still_unchanged,
       (SELECT count(*) FROM public.upgrade_state_log) AS log_rows
  FROM public.upgrade AS u
 WHERE u.id = :obsolete_target_id;

\echo '=== all tests done ==='

ROLLBACK;
