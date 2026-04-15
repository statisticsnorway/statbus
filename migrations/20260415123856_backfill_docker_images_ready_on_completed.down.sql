-- Down Migration 20260415123856: backfill_docker_images_ready_on_completed
--
-- This backfill is not reversible: we cannot know which completed rows had
-- docker_images_ready=false before the UP migration ran versus those that
-- were already true. The invariant (completed => images ready) is correct
-- and should not be undone.
BEGIN;

-- Intentionally a no-op. The backfill cannot be reversed without tracking
-- which rows were changed, and reverting it would re-introduce an incorrect
-- state. To acknowledge: RAISE NOTICE is not valid outside PL/pgSQL, so
-- we document the decision here and let the empty transaction succeed.

END;
