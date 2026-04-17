-- Migration 20260329000000: normalize_upgrade_release_status (DOWN)
-- This migration is not practically reversible: it was written to normalise a
-- diverged schema on a specific server. Rolling back past this point would
-- restore the old boolean columns on a server that may have advanced further.
-- Down is intentionally a no-op.
BEGIN;
-- no-op
END;
