BEGIN;

-- Drop the functions first
-- We must specify the function signature to drop an overloaded function.
-- The versions created in the corresponding `up` migration used `anyelement`.
DROP FUNCTION IF EXISTS from_to_overlaps(anyelement, anyelement, anyelement, anyelement);
DROP FUNCTION IF EXISTS from_until_overlaps(anyelement, anyelement, anyelement, anyelement);

-- Drop the extension and schema
DROP EXTENSION ltree;
DROP SCHEMA admin CASCADE;

END;
