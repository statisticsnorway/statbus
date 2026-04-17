-- Migration 20260417105000: Create upgrade_supersede_older procedure
--
-- Extracts the supersede-older-releases logic into a shared SQL procedure
-- so both the step-table path (psql) and the service path (pgx) call the
-- same code. Mirrors the logic from service.go:supersedeOlderReleases and
-- install.go:runInstallSupersede — single source of truth.

BEGIN;

CREATE OR REPLACE PROCEDURE public.upgrade_supersede_older(
    IN  p_commit_sha  text,
    INOUT p_superseded integer DEFAULT 0
)
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $upgrade_supersede_older$
DECLARE
    _topo   integer;
    _committed timestamptz;
BEGIN
    -- Look up the installed row's position.
    SELECT topological_order, committed_at
      INTO _topo, _committed
      FROM public.upgrade
     WHERE commit_sha = p_commit_sha
     LIMIT 1;

    IF NOT FOUND THEN
        RAISE NOTICE 'upgrade_supersede_older: no row for commit_sha=%', p_commit_sha;
        RETURN;
    END IF;

    -- Supersede all rows that are:
    --   (a) not yet in a terminal state (no completed/started/skipped/superseded timestamp)
    --   (b) a different commit than the just-installed one
    --   (c) older by topological_order (if both have it) OR by committed_at
    --
    -- Clearing error=NULL matters when a previously-failed row gets
    -- auto-superseded — the CHECK on state='superseded' only requires
    -- superseded_at IS NOT NULL.
    WITH superseded AS (
        UPDATE public.upgrade SET
            state = 'superseded',
            superseded_at = now(),
            error = NULL
         WHERE completed_at IS NULL
           AND started_at IS NULL
           AND skipped_at IS NULL
           AND superseded_at IS NULL
           AND commit_sha != p_commit_sha
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
        RAISE NOTICE 'upgrade_supersede_older: superseded % row(s) older than %',
            p_superseded, p_commit_sha;
    END IF;
END;
$upgrade_supersede_older$;

COMMENT ON PROCEDURE public.upgrade_supersede_older(text, integer) IS
    'Mark upgrade rows older than the given commit_sha as superseded. '
    'Called by both the step-table install path (psql) and the upgrade service (pgx) '
    'after a successful install/upgrade.';

END;
