-- STATBUS-442: legacy ranking retirement, then the existing audited install route.
-- The actual Go completion route is exercised by Test442PinnedInstallCompletion.
BEGIN;
SET LOCAL client_min_messages = warning;
SET LOCAL statbus.actor = '';
\set VERBOSITY sqlstate

-- Exact released pre-435 ranking definition, transactionally restored at ROLLBACK.
CREATE OR REPLACE PROCEDURE public.upgrade_supersede_older(IN p_commit_sha text, INOUT p_superseded integer DEFAULT 0)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $procedure$
DECLARE
    _committed  timestamptz;
    _status     public.release_status_type;
    _version_key integer[];
BEGIN
    SELECT committed_at, release_status, public.upgrade_version_key(commit_version)
      INTO _committed, _status, _version_key
      FROM public.upgrade
     WHERE commit_sha = p_commit_sha
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE NOTICE 'upgrade_supersede_older: no row for commit_sha=%', p_commit_sha;
        RETURN;
    END IF;

    WITH superseded AS (
        UPDATE public.upgrade AS u SET
            state = 'superseded',
            superseded_at = COALESCE(u.superseded_at, now())
         WHERE u.state IN ('available', 'scheduled', 'failed', 'rolled_back')
           AND u.commit_sha != p_commit_sha
           AND (
               u.release_status < _status
               OR (
                   u.release_status = _status
                   AND CASE
                       WHEN _version_key IS NOT NULL
                        AND public.upgrade_version_key(u.commit_version) IS NOT NULL
                       THEN (public.upgrade_version_key(u.commit_version), u.committed_at)
                          < (_version_key, _committed)
                       ELSE u.committed_at < _committed
                   END
               )
           )
        RETURNING u.id
    )
    SELECT count(*) INTO p_superseded FROM superseded;

    IF p_superseded > 0 THEN
        RAISE NOTICE 'upgrade_supersede_older: superseded % row(s) older than % (status=%)',
            p_superseded, p_commit_sha, _status;
    END IF;
END;
$procedure$;

INSERT INTO public.upgrade
    (commit_sha, committed_at, commit_tags, commit_version, summary, release_status, state)
VALUES
    (repeat('a', 40), '2026-10-02 00:00:00+00', ARRAY['v2026.10.0-rc.12'],
     'v2026.10.0-rc.12', '442 installed candidate', 'prerelease', 'available'),
    (repeat('b', 40), '2026-09-25 00:00:00+00', ARRAY['v2026.09.3'],
     'v2026.09.3', '442 older stable', 'release', 'available');
CALL public.upgrade_supersede_older(repeat('b', 40), 0);

\echo '=== legacy ranking retires the newer exact candidate ==='
SELECT summary, state FROM public.upgrade WHERE commit_sha = repeat('a', 40);
SELECT old_state, new_state, actor_source,
       query LIKE 'CALL public.upgrade_supersede_older(%' AS ranking_invocation
FROM public.upgrade_state_log
WHERE upgrade_id = (SELECT id FROM public.upgrade WHERE commit_sha = repeat('a', 40));

\echo '=== pre-fix completion upsert cannot publish the installed fact ==='
INSERT INTO public.upgrade
    (commit_sha, committed_at, commit_tags, summary, state, completed_at, log_relative_file_path)
VALUES
    (repeat('a', 40), '2026-10-02 00:00:00+00', ARRAY['v2026.10.0-rc.12'],
     '442 installed candidate', 'completed', now(), '442-install.log')
ON CONFLICT (commit_sha) DO UPDATE
    SET state = 'completed', completed_at = now(), log_relative_file_path = '442-install.log'
WHERE upgrade.state NOT IN ('completed', 'superseded', 'failed', 'rolled_back', 'skipped', 'dismissed');
SELECT EXISTS (SELECT 1 FROM public.upgrade
               WHERE commit_sha = repeat('a', 40) AND state = 'completed') AS pre_fix_completed;

\echo '=== direct terminal completion still refuses ==='
SAVEPOINT terminal_control;
UPDATE public.upgrade SET state = 'completed', completed_at = now(), log_relative_file_path = '442-refused.log'
WHERE commit_sha = repeat('a', 40);
ROLLBACK TO SAVEPOINT terminal_control;

\echo '=== positive successful install uses the existing audited schedule door ==='
SET LOCAL statbus.actor = 'successful pinned ./sb install: pg_regress442';
SELECT schedule_result, landed_state FROM public.upgrade_schedule(repeat('a', 40), false);
UPDATE public.upgrade
SET state = 'completed', completed_at = now(), started_at = now(),
    docker_images_status = 'ready', release_builds_status = 'ready',
    log_relative_file_path = '442-install.log'
WHERE commit_sha = repeat('a', 40) AND state = 'scheduled';
SELECT EXISTS (SELECT 1 FROM public.upgrade
               WHERE commit_sha = repeat('a', 40) AND state = 'completed') AS exact_install_completed;
SELECT old_state, new_state, actor, actor_source
FROM public.upgrade_state_log
WHERE upgrade_id = (SELECT id FROM public.upgrade WHERE commit_sha = repeat('a', 40))
ORDER BY id;

\echo '=== unrelated operator retirement still refuses direct completion ==='
INSERT INTO public.upgrade
    (commit_sha, committed_at, commit_tags, summary, state)
VALUES (repeat('c', 40), '2026-10-03 00:00:00+00', ARRAY[]::text[], '442 operator-retired', 'available');
SET LOCAL statbus.actor = '442 retiring operator';
UPDATE public.upgrade SET state = 'superseded', superseded_at = now()
WHERE commit_sha = repeat('c', 40);
SAVEPOINT unrelated_control;
UPDATE public.upgrade SET state = 'completed', completed_at = now(), log_relative_file_path = '442-refused.log'
WHERE commit_sha = repeat('c', 40);
ROLLBACK TO SAVEPOINT unrelated_control;
SELECT state, completed_at IS NULL AS no_invented_completion
FROM public.upgrade WHERE commit_sha = repeat('c', 40);
ROLLBACK;
\set VERBOSITY default
