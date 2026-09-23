-- Migration 20260923084454: order upgrade candidates by version
BEGIN;

CREATE OR REPLACE FUNCTION public.upgrade_version_key(p_version text)
RETURNS integer[]
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $upgrade_version_key$
    SELECT CASE
        WHEN match IS NULL THEN NULL
        ELSE ARRAY[
            match[1]::integer,
            match[2]::integer,
            match[3]::integer,
            CASE WHEN match[4] IS NULL THEN 1 ELSE 0 END,
            COALESCE(match[4]::integer, 0)
        ]
    END
    FROM regexp_match(
        p_version,
        '^v+([0-9]{4})\.([0-9]{2})\.([0-9]+)(?:-rc\.([0-9]+))?$'
    ) AS match;
$upgrade_version_key$;

CREATE OR REPLACE PROCEDURE public.upgrade_supersede_older(
    IN p_commit_sha text,
    INOUT p_superseded integer DEFAULT 0
)
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $upgrade_supersede_older$
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

    -- Lower release tiers are always older. Peers are ordered by their
    -- calendar version, never by insertion id or discovery time. committed_at
    -- is the tie-break for aliases/equivalent versions and the fallback for
    -- unversioned commit rows.
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
$upgrade_supersede_older$;

END;
