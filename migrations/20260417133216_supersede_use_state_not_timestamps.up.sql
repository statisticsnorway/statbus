BEGIN;

-- Fix: the previous migration (20260417130648) was edited after first
-- deploy, so dev still has the timestamp-based WHERE clause. This
-- migration replaces it with the state-based version.
--
-- PRINCIPLE: filter by STATE, not by timestamp columns. State is the
-- single source of truth. Timestamps record WHEN, not WHAT.
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
    SELECT topological_order, committed_at
      INTO _topo, _committed
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
