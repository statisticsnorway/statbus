-- Down Migration 20260506112552:
--
-- Reverses schema-level changes: drops the new trigger + function,
-- drops the new backstop procedure, re-adds topological_order as
-- nullable INTEGER, and restores the prior procedure bodies (with
-- their topo arms) verbatim from
--   migrations/20260418204304_supersede_respects_release_status_hierarchy.up.sql:9-63
--   migrations/20260417163407_supersede_completed_prereleases_same_family.up.sql:15-74
--
-- The data heal in the up migration (refresh stale commit_version,
-- supersede orphan ancestors) is INTENTIONALLY NOT REVERSED.
-- Rolling back doesn't un-supersede correctly-superseded rows or
-- un-promote correctly-promoted commit_version strings — those
-- represent observed truth about the upgrade timeline.

BEGIN;

-- 1. Drop trigger + function.
DROP TRIGGER IF EXISTS upgrade_block_obsolete_pending_trigger ON public.upgrade;
DROP FUNCTION IF EXISTS public.upgrade_block_obsolete_pending();

-- 2. Drop the backstop procedure.
DROP PROCEDURE IF EXISTS public.upgrade_reap_ancestors_of_completed(integer);

-- 3. Re-add topological_order as nullable INTEGER. Existing rows will
--    have NULL — same state they were in before the up migration,
--    since nothing populated the column.
ALTER TABLE public.upgrade ADD COLUMN topological_order integer;

-- 4. Restore upgrade_supersede_older with topo arm
--    (verbatim from 20260418204304:9-63).
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

-- 5. Restore upgrade_supersede_completed_prereleases with topo arm
--    (verbatim from 20260417163407:15-74).
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

COMMIT;
