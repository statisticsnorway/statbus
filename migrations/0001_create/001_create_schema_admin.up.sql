--
-- Hand edited PostgreSQL database dump.
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = true;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

-- Use international date time parsing, to avoid
-- confusion with local syntax, where day and month may be reversed.
ALTER DATABASE "postgres" SET datestyle TO 'ISO, DMY';
SET datestyle TO 'ISO, DMY';

-- We need longer timeout for larger loads.
-- Ref. https://supabase.com/docs/guides/database/postgres/configuration
-- For API users
ALTER ROLE authenticated SET statement_timeout = '120s';

-- Support fast path (ltree) (a.b.c...) operations.
CREATE EXTENSION ltree SCHEMA public;

-- Use a separate schema, that is not exposed by PostgREST, for administrative functions.
CREATE SCHEMA IF NOT EXISTS admin;
