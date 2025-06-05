BEGIN;

-- Drop the functions first
DROP FUNCTION IF EXISTS from_to_overlaps;
DROP FUNCTION IF EXISTS after_to_overlaps;

-- Drop the extension and schema
DROP EXTENSION ltree;
DROP SCHEMA admin CASCADE;

END;
