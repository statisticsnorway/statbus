BEGIN;

-- PostgreSQL doesn't support removing enum values directly.
-- The 'edge' value remains but is unused after downgrade.
-- Servers on 'edge' should be switched to another channel first.

END;
