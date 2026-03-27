BEGIN;

-- Deliberately fail to test rollback.
-- This migration should cause the upgrade daemon to roll back the entire release,
-- including the previous marker migration (20260327110758).
SELECT 1/0;  -- division by zero

END;
