\set ECHO none
-- STATBUS-278: generate to a results-side artifact (gitignored, like every
-- other pg_regress results/ file), never the tracked app/src/lib/database.types.ts
-- directly. `./sb types generate` is the ONLY writer of the tracked file —
-- see generate_database_types.sql's header for the shared-definition design.
\set output_path test/results/016_database.types.ts
\i /statbus/cli/sql/generate_database_types.sql
DROP FUNCTION IF EXISTS public.generate_typescript_types();
\t off
\a
\set ECHO all

-- STATBUS-278: compare the freshly generated artifact against the committed
-- tracked file and fail loudly on any disagreement. This STRENGTHENS what
-- 016 proves: before, a generation-vs-committed mismatch was a silently
-- dirty tree that nothing checked; now it is a failing assertion. Read both
-- files in SQL (not shelled out) so a mismatch is a real ERROR the test
-- harness's own expected-output diff catches, exactly like any other
-- assertion failure in this suite.
DO $$
DECLARE
    v_generated text := pg_read_file('/statbus/test/results/016_database.types.ts');
    v_committed text := pg_read_file('/statbus/app/src/lib/database.types.ts');
BEGIN
    IF v_generated IS DISTINCT FROM v_committed THEN
        RAISE EXCEPTION E'STALE GENERATED FILE: app/src/lib/database.types.ts\n  Live-schema generation disagrees with the committed file (generated % bytes, committed % bytes).\n  Fix: run `./sb types generate` and commit the result.',
            length(v_generated), length(v_committed);
    END IF;
END $$;

SELECT 'TypeScript types generated; matches committed app/src/lib/database.types.ts' AS result;
WITH stats AS (
    SELECT
        (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')) as table_count,
        (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = 'public' AND c.relkind IN ('v', 'm')) as view_count,
        (SELECT count(*) FROM pg_type t JOIN pg_namespace n ON t.typnamespace = n.oid WHERE n.nspname = 'public' AND t.typtype = 'e') as enum_count,
        (SELECT count(*) FROM pg_constraint c JOIN pg_class cl ON cl.oid = c.conrelid JOIN pg_namespace n ON n.oid = cl.relnamespace WHERE n.nspname = 'public' AND c.contype = 'f') as fk_count
)
SELECT format('Stats: %s tables, %s views, %s enums, %s FK constraints', table_count, view_count, enum_count, fk_count) AS database_stats FROM stats;
