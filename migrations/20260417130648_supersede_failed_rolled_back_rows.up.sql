BEGIN;

-- Widen upgrade_supersede_older to also supersede failed and rolled_back
-- rows that are older than the newly completed version.
--
-- KEY DESIGN PRINCIPLE: filter by STATE, not by timestamp columns.
-- The state column is the single source of truth for the upgrade lifecycle.
-- Timestamp columns (started_at, superseded_at, etc.) record WHEN transitions
-- happened but must NOT be used as filters for WHAT to do next. A row can
-- have superseded_at set from a previous event while still being in
-- rolled_back state — filtering on superseded_at IS NULL misses it.
--
-- The error column is preserved on supersede so the history of failures
-- remains visible in the collapsed history view.
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

    -- Supersede all non-terminal rows older than the just-completed version.
    -- Uses STATE as the filter — not timestamp columns — because state is
    -- the single source of truth. Timestamps can have stale values from
    -- previous lifecycle events (e.g. superseded_at set before a rollback).
    --
    -- States superseded: available, scheduled, failed, rolled_back
    -- States left alone:  in_progress (dangerous), completed, superseded,
    --                     skipped, dismissed (already terminal)
    WITH superseded AS (
        UPDATE public.upgrade SET
            state = 'superseded',
            superseded_at = COALESCE(superseded_at, now())
         WHERE state IN ('available', 'scheduled', 'failed', 'rolled_back')
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
