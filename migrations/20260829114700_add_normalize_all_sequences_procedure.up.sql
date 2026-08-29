-- Migration 20260829114700: public.normalize_all_sequences() (STATBUS-316).
--
-- THE PROBLEM. nextval() is non-transactional: a value it hands out is
-- burned even if the INSERT that consumed it later rolls back. Every
-- pg_restore-based restore path in this codebase (db.go's restoreLocal,
-- seed_build.go's restoreSeedDump, seed.go's seed restore, seed_verify.go's
-- restoreVerifyDB) loads an artifact whose sequences sit at whatever
-- position the SOURCE database's burn history left them at -- not a
-- position derived from the rows the restore just loaded. The pg_regress
-- shared-test suite hits the identical disease from the opposite
-- direction: BEGIN/ROLLBACK restores ROWS, never sequences, so ids burned
-- by one test file's rolled-back inserts are never returned (STATBUS-315).
--
-- THE FIX, ONE PLACE. A single procedure every caller shares -- Go restore
-- paths CALL it after their own genuine completion point, and
-- test/setup.sql CALLs it too (retiring STATBUS-315's bespoke auth.user-only
-- setval, which named this exact ticket as its retirement condition) --
-- so the SQL logic can never drift between a Go-embedded copy and a
-- test-file copy.
--
-- THE QUERY. pg_depend with deptype IN ('a', 'i') -- 'a' (SERIAL / DEFAULT
-- nextval()) alone would silently skip identity-column sequences ('i',
-- GENERATED ALWAYS AS IDENTITY); both are required to find every
-- column-owned sequence. Each owned sequence resets to
-- setval(seq, COALESCE(max(owning_column), 1), max(owning_column) IS NOT NULL)
-- -- the is_called argument matters: on the empty tables that dominate a
-- fresh seed, max() is NULL, and is_called=false is what makes the NEXT
-- nextval() correctly return 1 instead of skipping straight to 2.
--
-- Idempotent by construction: setval-to-max is the same operation however
-- often it runs -- a defensive duplicate CALL costs only a query, never
-- correctness. Bidirectional by construction too: a sequence AHEAD of the
-- data's actual max is pulled back down; a sequence BEHIND it (e.g. rows
-- loaded by COPY with explicit ids, never touching the sequence) is pushed
-- forward -- both directions are the same COALESCE(max(...), 1) call, not
-- two separate cases.
--
-- Sequences with NO column dependency (no pg_depend 'a'/'i' link) have no
-- authoritative "current row count" to derive a position from -- they are
-- used programmatically (an explicit nextval() call feeding a value into a
-- column that already has its own default/logic). Guessing at one would be
-- worse than leaving it alone, so this procedure reports them
-- (RAISE NOTICE, named, not silent) and never touches them. Known members
-- of this set today: graphql.seq_schema_version, import_job_priority_seq,
-- power_group_ident_seq, worker_task_priority_seq.

BEGIN;

CREATE PROCEDURE public.normalize_all_sequences()
LANGUAGE plpgsql
AS $normalize_all_sequences$
DECLARE
    r RECORD;
    v_max BIGINT;
    v_skipped TEXT;
BEGIN
    FOR r IN
        SELECT
            quote_ident(sn.nspname) || '.' || quote_ident(s.relname) AS seq_ident,
            quote_ident(a.attname) AS col_ident,
            quote_ident(tn.nspname) || '.' || quote_ident(t.relname) AS tbl_ident
        FROM pg_class s
        JOIN pg_namespace sn ON sn.oid = s.relnamespace
        JOIN pg_depend d ON d.objid = s.oid
                         AND d.classid = 'pg_class'::regclass
                         AND d.refclassid = 'pg_class'::regclass
        JOIN pg_class t ON t.oid = d.refobjid
        JOIN pg_namespace tn ON tn.oid = t.relnamespace
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
        WHERE s.relkind = 'S'
          AND d.deptype IN ('a', 'i')
        ORDER BY 1
    LOOP
        EXECUTE format('SELECT max(%s) FROM %s', r.col_ident, r.tbl_ident) INTO v_max;
        PERFORM setval(r.seq_ident, COALESCE(v_max, 1), v_max IS NOT NULL);
    END LOOP;

    SELECT string_agg(seq, ', ' ORDER BY seq) INTO v_skipped
    FROM (
        SELECT n.nspname || '.' || c.relname AS seq
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind = 'S'
        EXCEPT
        SELECT sn.nspname || '.' || s.relname
        FROM pg_class s
        JOIN pg_namespace sn ON sn.oid = s.relnamespace
        JOIN pg_depend d ON d.objid = s.oid
                         AND d.classid = 'pg_class'::regclass
                         AND d.refclassid = 'pg_class'::regclass
        JOIN pg_class t ON t.oid = d.refobjid
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
        WHERE s.relkind = 'S' AND d.deptype IN ('a', 'i')
    ) unowned;

    IF v_skipped IS NOT NULL THEN
        RAISE NOTICE 'normalize_all_sequences: skipped % (no owning column to derive an authoritative max from -- this procedure only ever normalizes column-owned sequences)', v_skipped;
    END IF;
END;
$normalize_all_sequences$;

COMMIT;
