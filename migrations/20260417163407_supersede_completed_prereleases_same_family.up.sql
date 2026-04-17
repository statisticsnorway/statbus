BEGIN;

-- New procedure: supersede older completed prereleases in the same version
-- family when a prerelease completes.
--
-- Complements upgrade_supersede_older (which intentionally skips 'completed'
-- rows — stable completed releases must never be superseded) with a targeted
-- rule for prereleases only. Without this, prerelease-channel servers
-- accumulate multiple completed prereleases (rc.15, rc.16, rc.25, rc.26)
-- because upgrade_supersede_older only touches available/scheduled/failed/
-- rolled_back rows.
--
-- KEY DESIGN PRINCIPLE: filter by STATE, not by timestamp columns.
-- Uses upgrade_family() for family matching (same as retention Rule E).
CREATE OR REPLACE PROCEDURE public.upgrade_supersede_completed_prereleases(
    IN p_commit_sha text,
    INOUT p_superseded integer DEFAULT 0
)
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $upgrade_supersede_completed_prereleases$
DECLARE
    _topo           integer;
    _committed      timestamptz;
    _family         text;
    _release_status public.release_status_type;
BEGIN
    -- Look up the just-completed row's position and family.
    SELECT u.topological_order, u.committed_at,
           public.upgrade_family(u), u.release_status
      INTO _topo, _committed, _family, _release_status
      FROM public.upgrade u
     WHERE u.commit_sha = p_commit_sha
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE NOTICE 'upgrade_supersede_completed_prereleases: no row for commit_sha=%', p_commit_sha;
        RETURN;
    END IF;

    -- Only act on prereleases with a parseable family.
    -- Stable completed releases must never trigger this.
    IF _release_status != 'prerelease' OR _family IS NULL THEN
        RETURN;
    END IF;

    -- Supersede older completed prereleases in the same family.
    -- Ordering mirrors upgrade_supersede_older: topological_order first,
    -- committed_at as fallback. Only the newest completed prerelease in
    -- each family survives.
    WITH superseded AS (
        UPDATE public.upgrade u_target SET
            state = 'superseded',
            superseded_at = COALESCE(u_target.superseded_at, now())
         WHERE u_target.state = 'completed'
           AND u_target.release_status = 'prerelease'
           AND u_target.commit_sha != p_commit_sha
           AND public.upgrade_family(u_target) = _family
           AND (
               (_topo IS NOT NULL
                AND u_target.topological_order IS NOT NULL
                AND u_target.topological_order < _topo)
               OR u_target.committed_at < _committed
           )
        RETURNING u_target.id
    )
    SELECT count(*) INTO p_superseded FROM superseded;

    IF p_superseded > 0 THEN
        RAISE NOTICE 'upgrade_supersede_completed_prereleases: superseded % completed prerelease(s) in family %',
            p_superseded, _family;
    END IF;
END;
$upgrade_supersede_completed_prereleases$;

COMMENT ON PROCEDURE public.upgrade_supersede_completed_prereleases(text, integer) IS
    'Supersede older completed prereleases in the same version family when a prerelease completes. '
    'Complements upgrade_supersede_older (which skips completed rows by design). '
    'Uses upgrade_family() for family matching. Safe to call for any row — no-op for non-prereleases.';

END;
