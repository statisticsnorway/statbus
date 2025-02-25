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
ALTER DATABASE "postgres" SET datestyle TO 'ISO, DMY';
ALTER DATABASE "postgres" SET check_function_bodies TO true;
ALTER DATABASE "postgres" SET client_encoding TO 'UTF8';
ALTER DATABASE "postgres" SET standard_conforming_strings TO on;
ALTER DATABASE "postgres" SET xmloption TO content;
ALTER DATABASE "postgres" SET client_min_messages TO warning;
ALTER DATABASE "postgres" SET row_security TO on;
ALTER DATABASE "postgres" SET search_path TO 'public';

-- Role-specific settings
--   We need longer timeout for larger loads.
--   Ref. https://supabase.com/docs/guides/database/postgres/configuration
--   For API users
ALTER ROLE authenticated SET statement_timeout = '120s';

-- Support fast path (ltree) (a.b.c...) operations.
CREATE EXTENSION ltree SCHEMA public;

-- Use a separate schema, that is not exposed by PostgREST, for administrative functions.
CREATE SCHEMA IF NOT EXISTS admin;

END;
