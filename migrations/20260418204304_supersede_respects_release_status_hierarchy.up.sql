-- Migration 20260418204304: supersede respects release_status hierarchy
--
-- A plain commit must not supersede a tagged prerelease or release.
-- The release_status_type enum is ordered: commit < prerelease < release.
-- Add a guard: a row can only supersede rows with equal or lower release_status.

BEGIN;

CREATE OR REPLACE PROCEDURE public.upgrade_supersede_older(
    IN p_commit_sha text,
    INOUT p_superseded integer DEFAULT 0
)
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $upgrade_supersede_older$
DECLARE
    _topo      integer;
    _committed timestamptz;
    _status    public.release_status_type;
BEGIN
    SELECT topological_order, committed_at, release_status
      INTO _topo, _committed, _status
      FROM public.upgrade
     WHERE commit_sha = p_commit_sha
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE NOTICE 'upgrade_supersede_older: no row for commit_sha=%', p_commit_sha;
        RETURN;
    END IF;

    -- Filter by STATE — the single source of truth — not timestamps.
    -- States superseded: available, scheduled, failed, rolled_back
    -- States left alone: in_progress, completed, superseded, skipped, dismissed
    --
    -- Hierarchy guard: a row can only supersede rows with equal or lower
    -- release_status. A plain commit must never supersede a tagged prerelease
    -- or release — those have published artifacts and represent deliberate
    -- milestones. The enum ordering (commit < prerelease < release) makes
    -- the comparison natural.
    WITH superseded AS (
        UPDATE public.upgrade SET
            state = 'superseded',
            superseded_at = COALESCE(superseded_at, now())
         WHERE state IN ('available', 'scheduled', 'failed', 'rolled_back')
           AND commit_sha != p_commit_sha
           AND release_status <= _status
           AND (
               (_topo IS NOT NULL
                AND topological_order IS NOT NULL
                AND topological_order < _topo)
               OR committed_at < _committed
           )
        RETURNING id
    )
    SELECT count(*) INTO p_superseded FROM superseded;

    IF p_superseded > 0 THEN
        RAISE NOTICE 'upgrade_supersede_older: superseded % row(s) older than % (status=%)',
            p_superseded, p_commit_sha, _status;
    END IF;
END;
$upgrade_supersede_older$;

END;
