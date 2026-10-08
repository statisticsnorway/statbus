-- STATBUS-479: the sector upload (sector_custom_only, the getting-started
-- page) reports the real unique violation instead of masking it.
--
-- The old handler rebuilt the error through code::jsonb: a path without
-- digits crashed with "invalid input syntax for type json", and a path with
-- digits reported a fabricated code ("11.10") that is not the stored code
-- ("1110"). Both lost SQLSTATE 23505, the constraint and the key detail.
-- (The fabricated code existed only in the message; stored data was never
-- affected.)
--
-- The error's fields are captured as data (SQLSTATE, constraint, message,
-- DETAIL, HINT), so the assertion does not depend on the server's source
-- locations.
-- Invariants checked:
--   1. A custom path that exists as a standard sector (sector_path_key):
--      SQLSTATE 23505, the original message with the uploaded row appended,
--      the constraint and a HINT.
--   2. Two custom paths with the same digits (sector_code_enabled_key):
--      the same.
--   3. The DETAIL is exactly what PostgreSQL emitted: the key detail
--      (Key (path)=(domestic), Key (code)=(1110)) as the database owner, and
--      nothing under row level security (the admin user), where PostgreSQL
--      itself omits it. The handler never invents one.
--   4. A successful upload is unaffected.
BEGIN;

\i test/setup.sql

\echo "Test 141: sector upload reports the real unique violation (STATBUS-479)"

CREATE FUNCTION pg_temp.upload_error(p_rows text)
RETURNS TABLE(error_sqlstate text, error_constraint text, error_message text, error_detail text, error_hint text)
LANGUAGE plpgsql AS $upload_error$
BEGIN
    BEGIN
        EXECUTE format('INSERT INTO public.sector_custom_only(path, name) VALUES %s', p_rows);
        error_sqlstate := 'no error';
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_sqlstate = RETURNED_SQLSTATE
                              , error_constraint = CONSTRAINT_NAME
                              , error_message = MESSAGE_TEXT
                              , error_detail = PG_EXCEPTION_DETAIL
                              , error_hint = PG_EXCEPTION_HINT;
    END;
    RETURN NEXT;
END;
$upload_error$;
GRANT EXECUTE ON FUNCTION pg_temp.upload_error(text) TO PUBLIC;

\x on

\echo "141.1 and 141.2: as an admin user (row level security applies; PostgreSQL emits no key DETAIL)"
CALL test.set_user_from_email('test.admin@statbus.org');
SELECT 'path collision' AS case_name, e.* FROM pg_temp.upload_error($$('domestic', 'Domestic (custom)')$$) AS e;
SELECT 'code collision' AS case_name, e.* FROM pg_temp.upload_error($$('a1110', 'first'), ('b1110', 'second')$$) AS e;

\echo "141.3: as the database owner: PostgreSQL's key DETAIL is passed through unchanged"
RESET ROLE;
SELECT 'path collision' AS case_name, e.* FROM pg_temp.upload_error($$('domestic', 'Domestic (custom)')$$) AS e;
SELECT 'code collision' AS case_name, e.* FROM pg_temp.upload_error($$('a1110', 'first'), ('b1110', 'second')$$) AS e;

\x off

\echo "141.4: a valid upload still lands"
CALL test.set_user_from_email('test.admin@statbus.org');
INSERT INTO public.sector_custom_only(path, name) VALUES ('a1110', 'first'), ('b2220', 'second');
SELECT s.path, s.code, s.custom, s.enabled, s.name
  FROM public.sector AS s WHERE s.custom ORDER BY s.path;

ROLLBACK;
