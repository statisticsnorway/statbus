```sql
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
           AND (u.state <> 'failed' OR public.upgrade_transition_actor_present())
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
$procedure$
```
