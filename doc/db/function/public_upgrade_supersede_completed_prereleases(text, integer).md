```sql
CREATE OR REPLACE PROCEDURE public.upgrade_supersede_completed_prereleases(IN p_commit_sha text, INOUT p_superseded integer DEFAULT 0)
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $procedure$
DECLARE
    _committed      timestamptz;
    _family         text;
    _release_status public.release_status_type;
BEGIN
    SELECT u.committed_at, public.upgrade_family(u), u.release_status
      INTO _committed, _family, _release_status
      FROM public.upgrade u
     WHERE u.commit_sha = p_commit_sha
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE NOTICE 'upgrade_supersede_completed_prereleases: no row for commit_sha=%', p_commit_sha;
        RETURN;
    END IF;

    IF _release_status != 'prerelease' OR _family IS NULL THEN
        RETURN;
    END IF;

    WITH superseded AS (
        UPDATE public.upgrade u_target SET
            state = 'superseded',
            superseded_at = COALESCE(u_target.superseded_at, now())
         WHERE u_target.state = 'completed'
           AND u_target.release_status = 'prerelease'
           AND u_target.commit_sha != p_commit_sha
           AND public.upgrade_family(u_target) = _family
           AND u_target.committed_at < _committed
        RETURNING u_target.id
    )
    SELECT count(*) INTO p_superseded FROM superseded;

    IF p_superseded > 0 THEN
        RAISE NOTICE 'upgrade_supersede_completed_prereleases: superseded % completed prerelease(s) in family %',
            p_superseded, _family;
    END IF;
END;
$procedure$
```
