BEGIN;

-- Widen upgrade_supersede_older to also supersede failed and rolled_back
-- rows that are older than the newly completed version. Previously these
-- lingered as "actionable" in the UI even though a newer version had
-- been successfully installed.
--
-- Two changes from the previous version:
--   1. Remove `AND started_at IS NULL` — failed/rolled_back have started_at
--   2. Keep error intact (remove `error = NULL`) — the error column preserves
--      the history of what went wrong. The CHECK constraint on state='superseded'
--      only requires superseded_at IS NOT NULL; error is unconstrained.
CREATE OR REPLACE PROCEDURE public.upgrade_supersede_older(
    IN p_commit_sha text,
    INOUT p_superseded integer DEFAULT 0
)
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
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
    --   (a) not already in a terminal state (completed, skipped, superseded)
    --   (b) a different commit than the just-installed one
    --   (c) older by topological_order (if both have it) OR by committed_at
    --
    -- This catches available, scheduled, failed, and rolled_back rows.
    -- The error column is preserved so the history of failures remains
    -- visible in the UI even after supersession.
    WITH superseded AS (
        UPDATE public.upgrade SET
            state = 'superseded',
            superseded_at = now()
         WHERE completed_at IS NULL
           AND superseded_at IS NULL
           AND skipped_at IS NULL
           AND dismissed_at IS NULL
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

END;
