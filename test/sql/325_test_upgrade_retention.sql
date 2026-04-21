-- Test: public.upgrade_retention_plan / upgrade_retention_apply
--
-- Exercises the planner rules:
--   A. install_same_family_prereleases     (purge same-family rc's when release installed)
--   B. install_old_commits_vs_release      (purge old commits when release installed)
--   C. install_old_commits_vs_prerelease   (purge old commits when prerelease installed)
--   D. time_safety                         (AND-gate: age > time_cap AND channel_count > count_cap AND rank > count_cap)
--   E. install_same_family_prerelease_to_prerelease (purge same-family rc's when prerelease installed)
--   + zombie protection for scheduled/in_progress (NULL cap cells never purged)
--   + executor matches planner output
--
-- Reason strings include volatile now()-derived age intervals; we redact those
-- with regexp_replace to make expected output deterministic.
--
-- Shared-test harness: wrap the whole file in BEGIN/ROLLBACK so SAVEPOINTs work
-- AND so the outer cloned-template database sees no side effects between tests.

BEGIN;

\echo '=== retention: setup ==='

-- Clean slate: drop any rows the test DB may carry from template fixtures.
-- (Template has a real-ish upgrade history; tests need a controlled one.)
-- RESTART IDENTITY so ids start at 1 for deterministic expected output.
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

-- Helper: keep commit_sha + summary concise but valid (40-hex, non-null summary).
-- sha(i) := lpad(to_hex(i), 40, '0')

\echo '=== retention: fixtures — 3 channels × stamped committed_at ==='

-- Commits (10 rows): 1 completed (1d), 9 superseded spanning newest→oldest
--   ids 1..10, committed_at stepped so rank order is deterministic.
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags, completed_at, log_relative_file_path) VALUES
    (lpad(to_hex( 1), 40, '0'), now() - '1 day'::interval, 'commit', 'completed',
     'commit #1 completed',  ARRAY['sha-0000000001'], now() - '1 day'::interval, 'test-fixture-log.txt');

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

-- Prereleases (ids 11..14): one completed recent, two same-family available, one older supersede.
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags, completed_at, log_relative_file_path) VALUES
    (lpad(to_hex(11), 40, '0'), now() - '30 days'::interval, 'prerelease', 'completed',
     'prerelease rc1 completed', ARRAY['v2026.03.0-rc.1'], now() - '29 days'::interval, 'test-fixture-log.txt');
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags) VALUES
    (lpad(to_hex(12), 40, '0'), now() - '10 days'::interval, 'prerelease', 'available',
     'prerelease rc2 same-family as installed release', ARRAY['v2026.04.0-rc.2']),
    (lpad(to_hex(13), 40, '0'), now() - ' 5 days'::interval, 'prerelease', 'available',
     'prerelease rc3 same-family as installed release', ARRAY['v2026.04.0-rc.3']);
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags, superseded_at) VALUES
    (lpad(to_hex(14), 40, '0'), now() - '40 days'::interval, 'prerelease', 'superseded',
     'prerelease rc old', ARRAY['v2026.02.0-rc.1'], now());

-- Releases (ids 15..16): the just-installed release + a prior completed release.
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags, completed_at, log_relative_file_path) VALUES
    (lpad(to_hex(15), 40, '0'), now() - '50 days'::interval, 'release', 'completed',
     'prior release v2026.03.0', ARRAY['v2026.03.0'], now() - '49 days'::interval, 'test-fixture-log.txt'),
    (lpad(to_hex(16), 40, '0'), now() - '2 hours'::interval, 'release', 'completed',
     'just-installed release v2026.04.0', ARRAY['v2026.04.0'], now(), 'test-fixture-log.txt');

-- Zombie rows: an in_progress and a scheduled, both absurdly old.
-- Caps are NULL for these cells → must NEVER be purged regardless of age.
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags, scheduled_at, started_at) VALUES
    (lpad(to_hex(17), 40, '0'), now() - '5 years'::interval, 'commit', 'in_progress',
     'ancient zombie in_progress', ARRAY['sha-0000000011'], now() - '5 years'::interval, now() - '5 years'::interval);
INSERT INTO public.upgrade (commit_sha, committed_at, release_status, state, summary, tags, scheduled_at) VALUES
    (lpad(to_hex(18), 40, '0'), now() - '5 years'::interval, 'prerelease', 'scheduled',
     'ancient zombie scheduled', ARRAY['v2020.01.0-rc.99'], now() - '5 years'::interval);

SELECT count(*) AS total_fixture_rows FROM public.upgrade;

\echo '=== family helpers ==='

SELECT public.version_family('v2026.04.0-rc.3') AS rc3_family,
       public.version_family('v2026.04.0')       AS stable_family,
       public.version_family('sha-0000000001')   AS sha_family;

-- upgrade_family should pick the stable tag if present, else last tag.
SELECT u.id, u.tags, public.upgrade_family(u) AS family
  FROM public.upgrade AS u
 WHERE u.id IN (12, 13, 15, 16)
 ORDER BY u.id;

\echo '=== rule D: time_safety (p_context=all, no install) ==='

-- Expect: commits 5..10 in the superseded channel (ranks 3..8, all > count_cap=2)
-- plus nothing else. id 1 is completed/1d — within cap. ids 2..4 are superseded
-- but within 14 days OR rank <= 2. The zombies (17, 18) must NOT appear.
SELECT p.id,
       p.action,
       -- Redact age (interval-style output varies across envs) + cap/rank for robustness.
       regexp_replace(p.reason, 'age=[^>]+ > cap=[^ ]+ ', 'age=<redacted> > cap=<redacted> ')
           AS reason_redacted
  FROM public.upgrade_retention_plan('all', NULL) AS p
 ORDER BY p.id;

\echo '=== rule A: install_same_family_prereleases (install release id=16, family=v2026.04.0) ==='

-- Expect: prereleases 12, 13 (both v2026.04.0-rc.*) in delete plan.
-- Plus rule B: old commits older than prior release (id=15, committed 50d ago) → commits 6..10.
-- Plus rule D time-safety (same as above).
-- DISTINCT ON collapses, so rows that match multiple rules still appear ONCE.
-- Note: plan rows are ORDER BY id, action — action is always 'delete' so id is the tie-breaker.
SELECT p.id,
       p.action,
       regexp_replace(
           regexp_replace(p.reason,
               'age=[^>]+ > cap=[^ ]+ ', 'age=<redacted> > cap=<redacted> '),
           'committed_at=[^)]+', 'committed_at=<redacted>')
           AS reason_redacted
  FROM public.upgrade_retention_plan('all', 16) AS p
 ORDER BY p.id;

\echo '=== rule C+E: install prerelease id=13 (family=v2026.04.0) ==='

-- Install prerelease with family=v2026.04.0. The prior completed prerelease
-- is id=11 (committed 30 days ago). Rule C → commits older than 30d ago
-- → ids 6..10 (40, 60, 80, 100, 120 days old).
-- Rule E → same-family prerelease id=12 (v2026.04.0-rc.2, available).
-- Rule D time-safety still fires on commits 5..10.
-- id=14 (v2026.02.0-rc.1) is different family → NOT purged by Rule E.
SELECT p.id,
       p.action
  FROM public.upgrade_retention_plan('all', 13) AS p
 ORDER BY p.id;

\echo '=== p_context=commit scopes time-safety to commit channel only ==='

-- With p_context='commit', only commit-channel rows hit time-safety. But the
-- install_* CTEs still check i.release_status; since p_installed_id is NULL,
-- they yield nothing. So the result equals "commit channel time-safety only".
SELECT p.id, p.action
  FROM public.upgrade_retention_plan('commit', NULL) AS p
 ORDER BY p.id;

\echo '=== executor: CALL upgrade_retention_apply deletes the planned rows ==='

-- Use a savepoint so the DELETE effect is visible to assertions, then rolled
-- back by the outer test-transaction rollback.
SAVEPOINT before_apply;
\set ON_ERROR_STOP on
SET client_min_messages TO WARNING;  -- suppress the per-row RAISE NOTICEs so expected/ is compact
CALL public.upgrade_retention_apply('all', NULL, 0);
RESET client_min_messages;

-- After apply with p_context=all, no install: commits 5..10 (6 rows) deleted.
-- Zombies (17, 18) remain. Completed + recent supersedes (1..4) remain.
SELECT count(*) FILTER (WHERE id BETWEEN 5 AND 10) AS commits_5_10_remaining,
       count(*) FILTER (WHERE id IN (17, 18))      AS zombies_remaining,
       count(*) FILTER (WHERE id BETWEEN 1 AND 4)  AS recent_commits_remaining,
       count(*) FILTER (WHERE id BETWEEN 11 AND 16) AS prerelease_and_release_remaining
  FROM public.upgrade;

ROLLBACK TO SAVEPOINT before_apply;

\echo '=== apply with install_id=16 cascades same-family prereleases too ==='

SAVEPOINT before_apply_install;
SET client_min_messages TO WARNING;
CALL public.upgrade_retention_apply('all', 16, 0);
RESET client_min_messages;

-- prereleases 12, 13 should also be gone after install-scoped purge.
SELECT count(*) FILTER (WHERE id IN (12, 13)) AS same_family_prereleases_remaining,
       count(*) FILTER (WHERE id = 14)        AS other_family_prerelease_remaining,
       count(*) FILTER (WHERE id IN (17, 18)) AS zombies_remaining
  FROM public.upgrade;
ROLLBACK TO SAVEPOINT before_apply_install;

\echo '=== rule E: prerelease-only server (install prerelease id=11, family=v2026.03.0) ==='

-- Install prerelease id=11 (v2026.03.0-rc.1, completed). This is a different
-- family from ids 12,13 (v2026.04.0-rc.*). Rule E targets same-family prereleases
-- only — so ids 12, 13 (v2026.04.0) are NOT purged by Rule E.
-- id=14 (v2026.02.0-rc.1) is also a different family → NOT purged.
-- Only time-safety (Rule D) fires on commits 5..10 as usual.
-- This verifies Rule E doesn't over-purge across families.
SELECT p.id, p.action
  FROM public.upgrade_retention_plan('all', 11) AS p
 ORDER BY p.id;

\echo '=== rule E: apply with prerelease install id=13 purges same-family ==='

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

\echo '=== caps flip: install_purge=false + NULL cap → zero-plan ==='

-- If ALL caps have NULL time/count AND install_purge=false, planner produces
-- no rows even for an install-context call.
SAVEPOINT before_caps_flip;
UPDATE public.upgrade_retention_caps SET time_cap = NULL, count_cap = NULL, install_purge = false;
SELECT count(*) AS planner_rows FROM public.upgrade_retention_plan('all', 16);
ROLLBACK TO SAVEPOINT before_caps_flip;

\echo '=== retention test done ==='

ROLLBACK;
