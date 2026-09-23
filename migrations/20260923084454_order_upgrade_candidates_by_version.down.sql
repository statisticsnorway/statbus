-- Down for 20260923084454_order_upgrade_candidates_by_version
BEGIN;

CREATE OR REPLACE PROCEDURE public.upgrade_supersede_older(
    IN p_commit_sha text,
    INOUT p_superseded integer DEFAULT 0
)
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $upgrade_supersede_older$
DECLARE
    _committed timestamptz;
    _status    public.release_status_type;
BEGIN
    SELECT committed_at, release_status
      INTO _committed, _status
      FROM public.upgrade
     WHERE commit_sha = p_commit_sha
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE NOTICE 'upgrade_supersede_older: no row for commit_sha=%', p_commit_sha;
        RETURN;
    END IF;

    WITH superseded AS (
        UPDATE public.upgrade SET
            state = 'superseded',
            superseded_at = COALESCE(superseded_at, now())
         WHERE state IN ('available', 'scheduled', 'failed', 'rolled_back')
           AND commit_sha != p_commit_sha
           AND release_status <= _status
           AND committed_at < _committed
        RETURNING id
    )
    SELECT count(*) INTO p_superseded FROM superseded;

    IF p_superseded > 0 THEN
        RAISE NOTICE 'upgrade_supersede_older: superseded % row(s) older than % (status=%)',
            p_superseded, p_commit_sha, _status;
    END IF;
END;
$upgrade_supersede_older$;

DROP FUNCTION public.upgrade_version_key(text);

END;
