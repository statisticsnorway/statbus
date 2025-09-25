BEGIN;

-- Use international date time parsing, to avoid
-- confusion with local syntax, where day and month may be reversed.
-- Transaction-local settings reference (commented out)
-- These settings only affect the current transaction
-- ------------------------------------------------------------
-- SET statement_timeout = 0;
-- SET lock_timeout = 0;
-- SET idle_in_transaction_session_timeout = 0;
-- ------------------------------------------------------------


-- Database-level configuration defaults
-- These settings affect all future connections to the database
DO $$
BEGIN
  EXECUTE format('ALTER DATABASE %I SET datestyle TO ''ISO, DMY'';', CURRENT_DATABASE());
  EXECUTE format('ALTER DATABASE %I SET check_function_bodies TO true;', CURRENT_DATABASE());
  EXECUTE format('ALTER DATABASE %I SET client_encoding TO ''UTF8'';', CURRENT_DATABASE());
  EXECUTE format('ALTER DATABASE %I SET standard_conforming_strings TO on;', CURRENT_DATABASE());
  EXECUTE format('ALTER DATABASE %I SET xmloption TO content;', CURRENT_DATABASE());
  EXECUTE format('ALTER DATABASE %I SET client_min_messages TO warning;', CURRENT_DATABASE());
  EXECUTE format('ALTER DATABASE %I SET row_security TO on;', CURRENT_DATABASE());
  EXECUTE format('ALTER DATABASE %I SET search_path TO ''public'';', CURRENT_DATABASE());
END
$$;

-- Role-specific settings
--   We need longer timeout for larger loads.
--   Ref. https://supabase.com/docs/guides/database/postgres/configuration
--   For API users
ALTER ROLE authenticated SET statement_timeout = '120s';
ALTER ROLE authenticated SET lock_timeout = '8s';

-- Ensure DELETE via web api must have a WHERE clause.
ALTER ROLE authenticator SET session_preload_libraries = safeupdate;

-- Use a separate schema, that is not exposed by PostgREST, for administrative functions.
CREATE SCHEMA IF NOT EXISTS admin;

-- Create a notification function for schema changes
CREATE OR REPLACE FUNCTION admin.notify_schema_change() 
RETURNS event_trigger AS $$
BEGIN
  PERFORM pg_notify('schema_change', 'Schema structure has been modified');
END;
$$ LANGUAGE plpgsql;

-- Create event trigger for schema changes
DROP EVENT TRIGGER IF EXISTS schema_change_trigger;
CREATE EVENT TRIGGER schema_change_trigger ON ddl_command_end
EXECUTE PROCEDURE admin.notify_schema_change();

-- Support fast path (ltree) (a.b.c...) operations.
CREATE EXTENSION ltree SCHEMA public;


-- There is an issue with
--   daterange(..,..,'(]') && daterange(..,..,'(]')
-- being very slow in comparison the OVERLAPS, but the semantics are incorrect
-- we need a valid_from <= time <= valid_to as opposed to the OVERLAPS valid_from <= time <= valid_to
-- We need two kinds of range overlap comparisons in this project, which are faster
-- alternatives to PostgreSQL's built-in range operators (`&&`).
--
-- 1. `from_until_overlaps(from1, until1, from2, until2)`
--    For Inclusive-Exclusive `[from, until)` ranges, used for sql_saga's core temporal logic.
--    This corresponds to the logic: `valid_from <= time < valid_until`.
--
-- 2. `from_to_overlaps(start1, end1, start2, end2)`
--    For Inclusive-Inclusive `[start, end]` ranges, used for UI-facing dates.
--    This corresponds to the logic: `valid_from <= time <= valid_to`.

CREATE OR REPLACE FUNCTION from_until_overlaps(
    from1 anyelement, until1 anyelement,
    from2 anyelement, until2 anyelement
) RETURNS BOOLEAN 
LANGUAGE sql IMMUTABLE PARALLEL SAFE COST 1 
AS $from_until_overlaps$
    -- This function implements range overlap check for any comparable type
    -- with the range semantics: from <= time < until
    -- The formula (from1 < until2 AND from2 < until1) checks if two half-open ranges overlap
    SELECT from1 < until2 AND from2 < until1;
$from_until_overlaps$;

CREATE OR REPLACE FUNCTION from_to_overlaps(
    start1 anyelement, end1 anyelement,
    start2 anyelement, end2 anyelement
) RETURNS BOOLEAN 
LANGUAGE sql IMMUTABLE PARALLEL SAFE COST 1 
AS $from_to_overlaps$
    -- This function implements range overlap check for any comparable type
    -- The formula (start1 <= end2 AND start2 <= end1) is the standard way to check
    -- if two ranges overlap, and it already handles inclusive endpoints correctly
    -- 
    -- This can replace the && operator for ranges when working with primitive types
    -- For example, instead of: daterange('2024-01-01', '2024-12-31') && daterange('2024-12-31', '2025-12-31')
    -- You can use: from_to_overlaps('2024-01-01'::date, '2024-12-31'::date, '2024-12-31'::date, '2025-12-31'::date)
    SELECT start1 <= end2 AND start2 <= end1;
$from_to_overlaps$;

END;
