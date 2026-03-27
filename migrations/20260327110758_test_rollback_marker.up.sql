BEGIN;

-- Test migration: creates a visible marker table to verify rollback consistency.
-- If rollback works correctly, this table should NOT exist after a failed upgrade.
CREATE TABLE public.rollback_test_marker (
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    message TEXT NOT NULL DEFAULT 'This table proves the migration was applied. If you see this after a rollback, the rollback was incomplete.'
);

INSERT INTO public.rollback_test_marker (message) VALUES ('Migration 20260327110758 was applied successfully');

END;
