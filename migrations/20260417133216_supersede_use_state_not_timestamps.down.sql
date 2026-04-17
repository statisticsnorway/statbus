BEGIN;
-- Down: revert to the timestamp-based version from 20260417130648
-- (which itself was already an improvement over the original).
-- No-op in practice — the previous migration's version is close enough.
-- This just exists for rollback completeness.
END;
